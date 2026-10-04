package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.data.GameResult
import dev.digitalducktape.openride.core.data.GameResultDao
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import dev.digitalducktape.openride.games.bridge.AudioSettings
import dev.digitalducktape.openride.games.bridge.BridgeMessages
import dev.digitalducktape.openride.games.bridge.CalibrationMode
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.GameSession
import dev.digitalducktape.openride.games.bridge.GameSignals
import dev.digitalducktape.openride.games.bridge.SegmentResult
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SegmentStartMessage
import dev.digitalducktape.openride.games.bridge.SessionSummary
import dev.digitalducktape.openride.games.bridge.SessionTotals
import dev.digitalducktape.openride.games.bridge.TrackerLink
import dev.digitalducktape.openride.games.bridge.TrackerMode
import kotlin.coroutines.cancellation.CancellationException
import kotlin.random.Random
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive

/**
 * Runs mini-games sessions (#35): the Kotlin side of the Bridge contract (docs/GAMES.md), and
 * the session's clock. App-scoped, like the ride it records: one session at a time, started by
 * [begin] each time the rider enters games.
 *
 * When Godot is ready ([onGameReady]) it builds the [SessionPlan] from the [SessionRequest]
 * and the active rider's FTP, starts the ride through the app's own [RideSessionManager] (so the
 * session records like any other ride, auto-pause included, as `Ride.gamePlan`), and walks
 * the plan on a 1 Hz clock:
 *
 * - `session_started` (the plan), then per segment `segment_started` → the intro card
 *   (`intro_sec`; the ride records through it, but `segment_time_left` counts gameplay only) →
 *   gameplay → the end:
 *   - `end_mode: timer`: `segment_ending` at `duration_sec`;
 *   - `end_mode: game`: the game ends it, with a hard stop (`segment_ending`) at 1.5 ×;
 *   - after `segment_ending` the game has 5 s to report, or a zero result is recorded.
 * - Any `segment_finished` (a skip from the intro card included) advances at once.
 * - Pauses come from the rider (`request_pause`/`request_resume`, which pause the ride), from
 *   the ride's own freewheel auto-pause, and from the head tracker while it calibrates (the
 *   ride keeps recording then: the rider is still on the bike). Any of them freezes the clock and
 *   is signalled; calibration resumes by itself when it completes or ends as unavailable.
 * - `request_end` asks the current game to finish (`segment_ending`), then ends the session.
 * - After the last segment a timed plan finishes by itself; an open-ended one waits for
 *   `request_end`.
 * - Finishing stops and saves the ride, writes one `game_results` row per segment, works out
 *   the rider's bests and only then sends `session_finished`. A session with under a minute of
 *   gameplay, or no pedalling at all, is discarded instead (`ride_id: null`).
 *
 * Every entry point hops onto [scope] (the main thread in the app), so all state is touched on
 * one thread; only [segmentTimeLeftSec] is read from Godot's thread. A session with no active
 * rider, or started while another ride is in progress, plays without recording (`ride_id: null`).
 */
class GameSessionManager(
    private val signals: GameSignals,
    private val scope: CoroutineScope,
    private val rideSessionManager: RideSessionManager,
    private val gameResultDao: GameResultDao,
    private val activeProfileId: () -> Long?,
    /** The rider's FTP, or null if unset (the plan falls back to 150 W). */
    private val profileFtp: suspend (profileId: Long) -> Int?,
    /** The camera head tracker's session side; null runs sessions without a camera. */
    private val tracker: TrackerLink? = null,
    private val catalog: GameCatalog = GameCatalog.DEFAULT,
    private val audioPrefs: () -> GameAudioPrefs = { GameAudioPrefs() },
    /** The rider's own music (another app's) is playing: [OtherMusicDetector] in the app. */
    private val otherMusicActive: () -> Boolean = { false },
    private val random: Random = Random.Default,
    private val log: (String) -> Unit = {},
) : GameSession {
    private enum class Phase { IDLE, WAITING, STARTING, INTRO, PLAYING, ENDING, AWAITING_END, SAVING, FINISHED }

    /** One segment's result with what Kotlin knows about the segment. */
    private data class Played(val segment: SegmentStartMessage, val startSec: Int, val playedSec: Int, val result: SegmentResult)

    private var phase = Phase.IDLE
    private var generation = 0
    private var request: SessionRequest? = null
    private var onExit: () -> Unit = {}
    private var plan: SessionPlan? = null
    private var sessionJob: Job? = null
    private var savingJob: Job? = null
    private var segment: SegmentStartMessage? = null
    private var segmentStartSec = 0
    private var introLeftSec = 0
    private var playedSec = 0
    private var graceLeftSec = 0
    private var elapsedSec = 0
    private var gameplaySec = 0
    private var riderPaused = false
    private var calibrationPaused = false
    private var paused = false
    private var endRequested = false
    private var exited = false
    private var profileId: Long? = null
    private var recording = false
    private val results = mutableListOf<Played>()

    @Volatile
    override var segmentTimeLeftSec: Double = -1.0
        private set

    private val _finishedRideId = MutableStateFlow<Long?>(null)

    /** The ride the last session saved, once `session_finished` is sent; for the hub's summary (#38). */
    val finishedRideId: StateFlow<Long?> = _finishedRideId.asStateFlow()

    /**
     * Readies a session of [request] for the next Godot frame poll. [onExit] runs when the game
     * calls `request_exit()`. A session still running is finished (and its ride saved) first.
     * Call on [scope]'s thread, before attaching this to the bridge.
     */
    fun begin(request: SessionRequest, onExit: () -> Unit) {
        if (phase in LIVE) {
            log("a new session replaces one still running: finishing it")
            finish()
        }
        generation++
        this.request = request
        this.onExit = onExit
        phase = Phase.WAITING
        plan = null
        segment = null
        segmentStartSec = 0
        introLeftSec = 0
        playedSec = 0
        graceLeftSec = 0
        elapsedSec = 0
        gameplaySec = 0
        riderPaused = false
        calibrationPaused = false
        paused = false
        endRequested = false
        exited = false
        profileId = null
        recording = false
        results.clear()
        segmentTimeLeftSec = -1.0
        _finishedRideId.value = null
    }

    override fun onGameReady() = post {
        if (phase != Phase.WAITING) return@post
        phase = Phase.STARTING
        val job = SupervisorJob(scope.coroutineContext[Job])
        sessionJob = job
        CoroutineScope(scope.coroutineContext + job).launch { start(generation) }
    }

    override fun onSegmentFinished(resultJson: String) = post {
        val current = segment ?: return@post
        if (phase !in setOf(Phase.INTRO, Phase.PLAYING, Phase.ENDING)) return@post
        val parsed = BridgeMessages.parseResult(resultJson) ?: SegmentResult.zero(current.gameId).also {
            log("segment_finished: unreadable result, recording zero: $resultJson")
        }
        if (parsed.gameId != current.gameId) log("segment_finished for '${parsed.gameId}' during '${current.gameId}'")
        log("segment_finished ${current.index}: score=${parsed.score} stars=${parsed.stars} skipped=${parsed.skipped}")
        record(parsed.copy(gameId = current.gameId))
        advance()
    }

    override fun onRequestCalibration(mode: String) = post {
        log("request_calibration ${CalibrationMode.fromWire(mode) ?: "unknown mode '$mode'"}")
        if (phase in PLAYABLE) tracker?.requestCalibration(mode)
    }

    override fun onSetTrackerMode(mode: String) = post {
        if (TrackerMode.fromWire(mode) == null) return@post log("set_tracker_mode: unknown mode '$mode'")
        log("set_tracker_mode $mode")
        // The summary screen never needs the camera.
        if (phase in PLAYABLE) tracker?.setTrackerMode(mode)
    }

    override fun onRequestPause() = post {
        if (phase !in PLAYABLE || riderPaused) return@post
        riderPaused = true
        if (recording) rideSessionManager.pause()
        refreshPaused()
    }

    override fun onRequestResume() = post {
        if (phase !in PLAYABLE) return@post
        riderPaused = false
        // Also ends an auto-pause: the rider pressed Resume on the pause screen.
        if (recording) rideSessionManager.resume()
        refreshPaused()
    }

    override fun onRequestEnd() = post {
        endRequested = true
        when (phase) {
            Phase.INTRO, Phase.PLAYING -> beginEnding()
            Phase.WAITING, Phase.AWAITING_END -> finish()
            // STARTING ends as soon as the first segment is up; the rest are ending already.
            else -> Unit
        }
    }

    override fun onRequestExit() = post {
        if (exited || phase == Phase.IDLE) return@post
        // The contract sends request_exit after the summary. A game that leaves early still
        // gets its ride saved, so nothing is left recording behind the closed host.
        if (phase != Phase.SAVING && phase != Phase.FINISHED) finish()
        exited = true
        onExit()
    }

    private suspend fun start(gen: Int) {
        // A replaced session's ride must be saved before this one's can start.
        savingJob?.join()
        if (gen != generation) return
        val pid = activeProfileId()
        val ftp = FtpBasis.of(pid?.let { runCatching { profileFtp(it) }.getOrNull() })
        val built = request?.let { SessionPlans.forRequest(it, ftp, catalog) }
        if (built == null) {
            log("can't plan $request: finishing without playing")
            finish()
            return
        }
        plan = built
        profileId = pid
        recording = startRide(pid, built.planId)
        log("session_started ${built.planId} (${built.difficulty}, FTP ${ftp.watts} W, recording=$recording)")
        tracker?.start()
        signals.sessionStarted(BridgeMessages.encode(built.toMessage(riderId = pid)))
        startSegment(0)
        val sessionScope = CoroutineScope(scope.coroutineContext + sessionJob!!)
        sessionScope.launch { rideSessionManager.state.collect { refreshPaused() } }
        tracker?.let { link ->
            sessionScope.launch {
                link.calibrating.collect {
                    calibrationPaused = it
                    refreshPaused()
                }
            }
        }
        sessionScope.launch { runClock() }
        if (endRequested) beginEnding()
    }

    private fun startRide(pid: Long?, planId: String): Boolean {
        if (pid == null) {
            log("no active rider: this session isn't recorded")
            return false
        }
        // A finished ride nobody dismissed (e.g. a summary still open) must not block this one.
        if (rideSessionManager.state.value is RideSessionState.Finished) rideSessionManager.reset()
        if (rideSessionManager.state.value != RideSessionState.Idle) {
            log("another ride is in progress: this session isn't recorded")
            return false
        }
        rideSessionManager.start(pid, gamePlan = planId)
        return true
    }

    private fun startSegment(index: Int) {
        val current = plan ?: return
        val planned = current.segments[index]
        val message = SegmentStartMessage(
            index = index,
            count = current.segments.size,
            gameId = planned.gameId,
            durationSec = planned.durationSec,
            introSec = current.introSec,
            endMode = planned.endMode,
            role = planned.role,
            difficulty = current.difficulty,
            effort = planned.effort,
            seed = random.nextLong(0, Int.MAX_VALUE.toLong()),
            // Re-checked every segment, so the rider's music starting or stopping mid-session counts.
            audio = audioPrefs().resolve(otherMusicActive()),
            params = planned.params,
        )
        segment = message
        segmentStartSec = elapsedSec
        introLeftSec = message.introSec
        playedSec = 0
        phase = if (introLeftSec > 0) Phase.INTRO else Phase.PLAYING
        updateTimeLeft()
        log("segment_started $index ${message.gameId} ${message.durationSec}s ${message.endMode}")
        signals.segmentStarted(BridgeMessages.encode(message))
    }

    private suspend fun runClock() {
        while (currentCoroutineContext().isActive) {
            delay(TICK_MS)
            tick()
        }
    }

    private fun tick() {
        val current = segment ?: return
        if (paused) {
            // A rider who ends the session from the pause screen still gets it ended.
            if (phase == Phase.ENDING && endRequested) graceTick(current)
            return
        }
        elapsedSec++
        when (phase) {
            Phase.INTRO -> if (--introLeftSec <= 0) phase = Phase.PLAYING
            Phase.PLAYING -> {
                playedSec++
                gameplaySec++
                updateTimeLeft()
                val duration = current.durationSec
                val stopAt = when {
                    duration < 0 -> null
                    current.endMode == EndMode.TIMER -> duration
                    else -> duration * 3 / 2
                }
                if (stopAt != null && playedSec >= stopAt) {
                    if (current.endMode == EndMode.GAME) log("segment ${current.index}: hard stop at ${stopAt}s")
                    beginEnding()
                }
            }
            Phase.ENDING -> graceTick(current)
            else -> Unit
        }
    }

    private fun graceTick(current: SegmentStartMessage) {
        if (--graceLeftSec > 0) return
        log("segment ${current.index}: no result within ${GRACE_SEC}s, recording zero")
        record(SegmentResult.zero(current.gameId))
        advance()
    }

    private fun beginEnding() {
        phase = Phase.ENDING
        graceLeftSec = GRACE_SEC
        signals.segmentEnding()
    }

    private fun record(result: SegmentResult) {
        val current = segment ?: return
        results += Played(current, segmentStartSec, playedSec, result)
    }

    private fun advance() {
        val current = segment ?: return
        val next = current.index + 1
        when {
            endRequested -> finish()
            next < (plan?.segments?.size ?: 0) -> startSegment(next)
            current.durationSec < 0 -> {
                phase = Phase.AWAITING_END
                segmentTimeLeftSec = -1.0
            }
            else -> finish()
        }
    }

    /** Pauses from either source, signalled to Godot only when the combined state changes. */
    private fun refreshPaused() {
        val now = riderPaused || calibrationPaused ||
            (recording && rideSessionManager.state.value == RideSessionState.Paused)
        if (now == paused) return
        paused = now
        if (phase !in PLAYABLE) return
        log(if (now) "session_paused" else "session_resumed")
        if (now) signals.sessionPaused() else signals.sessionResumed()
    }

    /** Stops the clock and the camera, then saves in the background and sends `session_finished`. */
    private fun finish() {
        if (phase == Phase.SAVING || phase == Phase.FINISHED || phase == Phase.IDLE) return
        phase = Phase.SAVING
        segmentTimeLeftSec = -1.0
        if (plan != null) tracker?.stop()
        sessionJob?.cancel()
        sessionJob = null
        val gen = generation
        val played = results.toList()
        val finishedPlan = plan
        val wasRecording = recording
        val pid = profileId
        val elapsed = elapsedSec
        val keep = wasRecording && worthKeeping(gameplaySec)
        if (wasRecording && !keep) {
            log("discarding the ride: ${gameplaySec}s of gameplay, pedalled=${pedalled()}")
            rideSessionManager.discard()
        }
        savingJob = scope.launch {
            val ride = if (keep) saveRide(played, finishedPlan) else null
            val bests = if (ride != null && pid != null && finishedPlan != null) bests(pid, ride.id, finishedPlan, played) else EMPTY
            val summary = SessionSummary(
                rideId = ride?.id,
                results = played.map { it.result },
                totals = SessionTotals(
                    score = played.sumOf { it.result.score },
                    stars = played.sumOf { it.result.stars },
                    segments = played.size,
                    elapsedSec = ride?.durationSec ?: elapsed,
                ),
                bests = bests,
            )
            log("session_finished: ride ${ride?.id}, ${played.size} results")
            signals.sessionFinished(BridgeMessages.encode(summary))
            if (gen == generation) phase = Phase.FINISHED
            _finishedRideId.value = ride?.id
        }
    }

    /**
     * Whether the session belongs in History: at least [MIN_GAMEPLAY_SEC] of gameplay (intro
     * cards don't count, so a skipped or abandoned game isn't a ride) and some pedalling.
     * Normal rides have no such rule; they're always ended deliberately from the ride screen.
     */
    private fun worthKeeping(gameplay: Int): Boolean = gameplay >= MIN_GAMEPLAY_SEC && pedalled()

    private fun pedalled(): Boolean = rideSessionManager.liveAggregates.value.let { it.maxCadence > 0 || it.maxPower > 0 }

    /** The ride through the normal recording path, then its results. Null if nothing was saved. */
    private suspend fun saveRide(played: List<Played>, finishedPlan: SessionPlan?): Ride? {
        val ride = try {
            rideSessionManager.stop()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log("saving the ride failed: $e")
            null
        } ?: return null
        val difficulty = wire(Difficulty.serializer(), finishedPlan?.difficulty ?: Difficulty.STANDARD)
        val rows = played.map { p ->
            GameResult(
                rideId = ride.id,
                segmentIndex = p.segment.index,
                gameId = p.segment.gameId,
                role = wire(SegmentRole.serializer(), p.segment.role),
                difficulty = difficulty,
                startSec = p.startSec,
                durationSec = p.playedSec,
                score = p.result.score,
                stars = p.result.stars,
                won = p.result.won,
                skipped = p.result.skipped,
                statsJson = p.result.stats.toString(),
            )
        }
        try {
            if (rows.isNotEmpty()) gameResultDao.insertAll(rows)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log("saving the game results failed: $e")
        }
        // Back to Idle so the app's next ride can start; the summary loads by ride id.
        rideSessionManager.reset()
        return ride
    }

    /**
     * `bests`: `{"score": true}` and/or `{"stars": true}` when this session beat the rider's
     * best at the same plan and difficulty (or is their first to score). Empty otherwise.
     */
    private suspend fun bests(pid: Long, rideId: Long, finishedPlan: SessionPlan, played: List<Played>): JsonObject {
        val previous = try {
            gameResultDao.planBest(pid, finishedPlan.planId, wire(Difficulty.serializer(), finishedPlan.difficulty), rideId)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            log("reading bests failed: $e")
            return EMPTY
        }
        val score = played.filterNot { it.result.skipped }.sumOf { it.result.score }
        val stars = played.filterNot { it.result.skipped }.sumOf { it.result.stars }
        val flags = buildMap {
            if (score > 0 && score > (previous.bestScore ?: 0.0)) put("score", JsonPrimitive(true))
            if (stars > 0 && stars > (previous.bestStars ?: 0)) put("stars", JsonPrimitive(true))
        }
        return JsonObject(flags)
    }

    private fun updateTimeLeft() {
        val duration = segment?.durationSec ?: -1
        segmentTimeLeftSec = if (duration < 0) -1.0 else (duration - playedSec).coerceAtLeast(0).toDouble()
    }

    private fun post(block: () -> Unit) {
        scope.launch { block() }
    }

    private fun <T> wire(serializer: KSerializer<T>, value: T): String =
        Json.encodeToJsonElement(serializer, value).jsonPrimitive.content

    companion object {
        const val GRACE_SEC = 5

        /** The shortest session saved as a ride: a game's shortest timed length (`min_sec`). */
        const val MIN_GAMEPLAY_SEC = 60
        private const val TICK_MS = 1_000L
        private val EMPTY = JsonObject(emptyMap())

        /** A session is under way: the tracker and pause requests apply. */
        private val PLAYABLE = setOf(Phase.STARTING, Phase.INTRO, Phase.PLAYING, Phase.ENDING, Phase.AWAITING_END)

        /** A session that [begin] must finish before replacing it. */
        private val LIVE = PLAYABLE + Phase.WAITING
    }
}
