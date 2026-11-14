package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.telemetry.GameDifficulty
import dev.digitalducktape.openride.core.telemetry.GameFinish
import dev.digitalducktape.openride.core.telemetry.GameId
import dev.digitalducktape.openride.core.telemetry.GameMusic
import dev.digitalducktape.openride.core.telemetry.GameOutcome
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.OwnMusicSignal
import dev.digitalducktape.openride.core.telemetry.Stars
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.TelemetryBuckets
import dev.digitalducktape.openride.core.telemetry.Won
import dev.digitalducktape.openride.core.telemetry.classify
import dev.digitalducktape.openride.core.telemetry.trackSafely
import dev.digitalducktape.openride.games.bridge.BridgeMessages
import dev.digitalducktape.openride.games.bridge.CalibrationMode
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.GameSignals
import dev.digitalducktape.openride.games.bridge.SegmentResult
import dev.digitalducktape.openride.games.bridge.SegmentStartMessage
import dev.digitalducktape.openride.games.bridge.TrackerLink
import dev.digitalducktape.openride.games.bridge.TrackerMode
import kotlin.random.Random
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** What `session_started` says about who plays and, in a hub visit, which visit. */
data class PlanStart(
    val riderId: Long? = null,
    val riderName: String? = null,
    /** Null outside a visit: then none of the visit keys is sent. */
    val visitId: String? = null,
    val planIndex: Int? = null,
    /** The visit's calibration: `""`, `lean_x` or `lean_2d`. */
    val calibrated: String? = null,
)

/** One segment as played: its `segment_started`, its start on the ride clock and its gameplay seconds. */
data class PlayedSegment(
    val segment: SegmentStartMessage,
    val startSec: Int,
    val playedSec: Int,
    val result: SegmentResult,
    /** What the game played over when it ended (telemetry, #85). */
    val music: GameMusic = GameMusic.OFF,
)

/**
 * A finished plan, for the visit to record and summarise.
 *
 * @param elapsedSec the plan's own seconds, from its first intro card to its end, pauses excluded.
 * @param gameplaySec gameplay seconds, intro cards excluded (the visit's keep-or-discard rule).
 */
data class PlanOutcome(
    val plan: SessionPlan,
    val results: List<PlayedSegment>,
    val elapsedSec: Int,
    val gameplaySec: Int,
    /** Telemetry (#85): what a segment still live when the plan was cut short played over, or null if none was. */
    val quitMusic: GameMusic? = null,
)

/**
 * The plan runner (Games hub spec §2): walks one [SessionPlan] on a 1 Hz clock, the Kotlin side
 * of the Bridge contract *within a plan* (docs/GAMES.md). The class keeps its v1 name to limit
 * churn; the hub visit ([GameVisitManager]) owns everything around it: the ride, the camera's
 * session, results, bests and `session_finished`.
 *
 * - [run] sends `session_started` (the plan, with [PlanStart]'s keys), then per segment
 *   `segment_started` → the intro card (`intro_sec`; `segment_time_left` counts gameplay only)
 *   → gameplay → the end:
 *   - `end_mode: timer`: `segment_ending` at `duration_sec`;
 *   - `end_mode: game`: the game ends it, with a hard stop (`segment_ending`) at 1.5 ×;
 *   - after `segment_ending` the game has 5 s to report, or a zero result is recorded.
 * - Any `segment_finished` (a skip from the intro card included) advances at once.
 * - Pauses come from the rider ([requestPause]/[requestResume], which pause the [PlanRide] too),
 *   from the ride's freewheel auto-pause, and from the head tracker while it calibrates (the
 *   ride keeps recording then). Any of them freezes the clock and is signalled; calibration
 *   resumes by itself when it completes or ends as unavailable.
 * - [requestEnd] asks the current game to finish (`segment_ending`), then ends the plan.
 * - After the last segment a timed plan finishes by itself; an open-ended one waits for
 *   [requestEnd]. [finishNow] ends it at once (the rider left games).
 * - Finishing stops the clock and hands a [PlanOutcome] to `onFinished`, synchronously. Each
 *   result's `startSec` is on the ride's clock ([PlanRide.elapsedSec]), so it lines up with the
 *   samples across a visit's plans.
 *
 * Not thread-safe: call everything on [scope]'s thread (the visit posts onto it). Only
 * [segmentTimeLeftSec] is read from Godot's thread.
 */
class GameSessionManager(
    private val signals: GameSignals,
    private val scope: CoroutineScope,
    /** The camera head tracker's plan side; null runs plans without a camera. */
    private val tracker: TrackerLink? = null,
    private val audioPrefs: () -> GameAudioPrefs = { GameAudioPrefs() },
    private val random: Random = Random.Default,
    private val log: (String) -> Unit = {},
    private val telemetry: Telemetry = NoOpTelemetry,
    /** A track is playing in the rider's own music app: `game_finish`'s `music`. */
    private val ownMusic: OwnMusicSignal = OwnMusicSignal { false },
) {
    private enum class Phase { IDLE, INTRO, PLAYING, ENDING, AWAITING_END, FINISHED }

    private var phase = Phase.IDLE
    private var plan: SessionPlan? = null
    private var ride: PlanRide = NoRide
    private var onFinished: (PlanOutcome) -> Unit = {}
    private var planJob: Job? = null
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

    /** The current segment has started and not yet recorded a result. */
    private var segmentOpen = false
    private val results = mutableListOf<PlayedSegment>()

    /** Input frame index 10: gameplay seconds left in the current segment, -1 if open-ended or none. */
    @Volatile
    var segmentTimeLeftSec: Double = -1.0
        private set

    /** A plan is under way: from [run] until it finishes. */
    val isRunning: Boolean get() = phase in PLAYABLE

    /**
     * Runs [plan] against [ride] (already resumed by the visit). [onFinished] gets the outcome
     * when it ends. Ignored while another plan runs.
     */
    fun run(plan: SessionPlan, ride: PlanRide, start: PlanStart, onFinished: (PlanOutcome) -> Unit) {
        if (isRunning) return log("run ${plan.planId}: a plan is already running")
        this.plan = plan
        this.ride = ride
        this.onFinished = onFinished
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
        segmentOpen = false
        results.clear()
        log("session_started ${plan.planId} (${plan.difficulty}, FTP ${plan.ftp.watts} W)")
        signals.sessionStarted(
            BridgeMessages.encode(
                plan.toMessage(riderId = start.riderId, riderName = start.riderName)
                    .copy(visitId = start.visitId, planIndex = start.planIndex, calibrated = start.calibrated),
            ),
        )
        startSegment(0)
        val job = SupervisorJob(scope.coroutineContext[Job])
        planJob = job
        val planScope = CoroutineScope(scope.coroutineContext + job)
        planScope.launch { ride.pausedChanges.collect { refreshPaused() } }
        tracker?.let { link ->
            planScope.launch {
                link.calibrating.collect {
                    calibrationPaused = it
                    refreshPaused()
                }
            }
        }
        planScope.launch { runClock() }
    }

    fun segmentFinished(resultJson: String) {
        val current = segment ?: return
        if (phase !in setOf(Phase.INTRO, Phase.PLAYING, Phase.ENDING)) return
        var unreadable = false
        val parsed = BridgeMessages.parseResult(resultJson) ?: SegmentResult.zero(current.gameId).also {
            unreadable = true
            log("segment_finished: unreadable result, recording zero: $resultJson")
        }
        if (parsed.gameId != current.gameId) log("segment_finished for '${parsed.gameId}' during '${current.gameId}'")
        log("segment_finished ${current.index}: score=${parsed.score} stars=${parsed.stars} skipped=${parsed.skipped}")
        val outcome = when {
            parsed.skipped -> GameOutcome.SKIPPED
            unreadable -> GameOutcome.NO_RESULT
            else -> GameOutcome.COMPLETED
        }
        record(parsed.copy(gameId = current.gameId), outcome)
        advance()
    }

    fun requestCalibration(mode: String) {
        log("request_calibration ${CalibrationMode.fromWire(mode) ?: "unknown mode '$mode'"}")
        if (isRunning) tracker?.requestCalibration(mode)
    }

    fun setTrackerMode(mode: String) {
        if (TrackerMode.fromWire(mode) == null) return log("set_tracker_mode: unknown mode '$mode'")
        log("set_tracker_mode $mode")
        // The result card never needs the camera.
        if (isRunning) tracker?.setTrackerMode(mode)
    }

    fun requestPause() {
        if (!isRunning || riderPaused) return
        riderPaused = true
        ride.pause()
        refreshPaused()
    }

    fun requestResume() {
        if (!isRunning) return
        riderPaused = false
        // Also ends an auto-pause: the rider pressed Resume on the pause screen.
        ride.resume()
        refreshPaused()
    }

    fun requestEnd() {
        endRequested = true
        when (phase) {
            Phase.INTRO, Phase.PLAYING -> beginEnding()
            Phase.AWAITING_END -> finish()
            else -> Unit
        }
    }

    /** Ends the plan now, with the results so far (the rider left games mid-plan). */
    fun finishNow() {
        if (isRunning) finish()
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
            audio = audioPrefs().resolve(),
            params = planned.params,
        )
        segment = message
        segmentOpen = true
        segmentStartSec = ride.elapsedSec
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
            // A rider who ends the plan from the pause screen still gets it ended.
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
        record(SegmentResult.zero(current.gameId), GameOutcome.NO_RESULT)
        advance()
    }

    private fun beginEnding() {
        phase = Phase.ENDING
        graceLeftSec = GRACE_SEC
        signals.segmentEnding()
    }

    private fun record(result: SegmentResult, outcome: GameOutcome) {
        val current = segment ?: return
        val music = currentMusic()
        results += PlayedSegment(current, segmentStartSec, playedSec, result, music)
        segmentOpen = false
        emitFinish(current, outcome, result, music)
    }

    private fun currentMusic(): GameMusic =
        runCatching { classify(audioPrefs().gameMusic, ownMusic.trackPlaying()) }.getOrDefault(GameMusic.OFF)

    /** `game_finish` (#85). Never throws into the plan. */
    private fun emitFinish(current: SegmentStartMessage, outcome: GameOutcome, result: SegmentResult?, music: GameMusic) {
        telemetry.trackSafely {
            val completed = outcome == GameOutcome.COMPLETED
            GameFinish(
                game = GameId(current.gameId),
                difficulty = when (plan?.difficulty ?: current.difficulty) {
                    Difficulty.EASY -> GameDifficulty.EASY
                    Difficulty.STANDARD -> GameDifficulty.STANDARD
                    Difficulty.HARD -> GameDifficulty.HARD
                },
                outcome = outcome,
                won = when (result?.won.takeIf { completed }) {
                    true -> Won.YES
                    false -> Won.NO
                    null -> Won.NA
                },
                stars = Stars.of(if (completed) result?.stars ?: 0 else 0),
                played = TelemetryBuckets.gamePlayed(playedSec.toLong()),
                music = music,
            )
        }
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

    /** Pauses from any source, signalled to Godot only when the combined state changes. */
    private fun refreshPaused() {
        val now = riderPaused || calibrationPaused || ride.isPaused
        if (now == paused) return
        paused = now
        if (!isRunning) return
        log(if (now) "session_paused" else "session_resumed")
        if (now) signals.sessionPaused() else signals.sessionResumed()
    }

    private fun finish() {
        val finishedPlan = plan ?: return
        phase = Phase.FINISHED
        segmentTimeLeftSec = -1.0
        planJob?.cancel()
        planJob = null
        // A segment still live was cut short (the rider left games): that is a quit.
        var quitMusic: GameMusic? = null
        if (segmentOpen) {
            segment?.let { quitMusic = currentMusic().also { music -> emitFinish(it, GameOutcome.QUIT, null, music) } }
            segmentOpen = false
        }
        val outcome = PlanOutcome(finishedPlan, results.toList(), elapsedSec, gameplaySec, quitMusic)
        log("plan ${finishedPlan.planId} finished: ${outcome.results.size} results, ${gameplaySec}s of gameplay")
        onFinished(outcome)
    }

    private fun updateTimeLeft() {
        val duration = segment?.durationSec ?: -1
        segmentTimeLeftSec = if (duration < 0) -1.0 else (duration - playedSec).coerceAtLeast(0).toDouble()
    }

    companion object {
        const val GRACE_SEC = 5
        private const val TICK_MS = 1_000L

        /** A plan is under way: the tracker and pause requests apply. */
        private val PLAYABLE = setOf(Phase.INTRO, Phase.PLAYING, Phase.ENDING, Phase.AWAITING_END)
    }
}
