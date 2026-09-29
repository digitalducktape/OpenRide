package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.AudioSettings
import dev.digitalducktape.openride.games.bridge.BridgeMessages
import dev.digitalducktape.openride.games.bridge.CalibrationMode
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.GameSession
import dev.digitalducktape.openride.games.bridge.GameSignals
import dev.digitalducktape.openride.games.bridge.PlanSegment
import dev.digitalducktape.openride.games.bridge.SegmentResult
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SegmentStartMessage
import dev.digitalducktape.openride.games.bridge.SessionKind
import dev.digitalducktape.openride.games.bridge.SessionPlanMessage
import dev.digitalducktape.openride.games.bridge.SessionSummary
import dev.digitalducktape.openride.games.bridge.SessionTotals
import dev.digitalducktape.openride.games.bridge.TrackerLink
import dev.digitalducktape.openride.games.bridge.TrackerMode
import kotlin.random.Random
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.json.JsonObject

/**
 * Walks a session plan over the bridge without recording anything: the foundation's (#32)
 * stand-in for `GameSessionManager` (#35), which will also drive `RideSessionManager`, compute
 * FTP-scaled `params`, auto-pause and save the ride before `session_finished`.
 *
 * It implements the contract's timeline on a 1 Hz clock: `session_started`, then per segment
 * `segment_started` → intro card (`intro_sec`, clock not counting gameplay) → gameplay →
 * `segment_ending` when the timer runs out (or the 1.5 × hard stop for `end_mode: game`) →
 * the game's `segment_finished`, or a zero result after a 5 s grace. After the last segment
 * a timed plan finishes by itself; an open-ended one waits for `request_end`.
 *
 * Every entry point hops onto [scope] (the host activity's main-thread scope), so all state is
 * touched on one thread; [segmentTimeLeftSec] is read from Godot's thread.
 */
class StubGameSession(
    private val signals: GameSignals,
    private val scope: CoroutineScope,
    private val plan: SessionPlanMessage = placeholderJustRide(),
    private val random: Random = Random.Default,
    private val onExit: () -> Unit,
    private val endModeFor: (PlanSegment) -> EndMode = { if (it.durationSec < 0) EndMode.GAME else EndMode.TIMER },
    private val log: (String) -> Unit = {},
    /** The camera head tracker's session side; null runs the session without a camera. */
    private val tracker: TrackerLink? = null,
) : GameSession {
    private enum class Phase { WAITING, INTRO, PLAYING, ENDING, AWAITING_END, FINISHED }

    private var phase = Phase.WAITING
    private var segment: SegmentStartMessage? = null
    private var introLeftSec = 0
    private var playedSec = 0
    private var graceLeftSec = 0
    private var elapsedSec = 0
    private var paused = false
    private var endRequested = false
    private var exited = false
    private val results = mutableListOf<SegmentResult>()

    @Volatile
    override var segmentTimeLeftSec: Double = -1.0
        private set

    /** The last valid `set_tracker_mode`. */
    @Volatile
    var trackerMode: TrackerMode = TrackerMode.OFF
        private set

    override fun onGameReady() = post {
        if (phase != Phase.WAITING) return@post
        log("session_started ${plan.planId}")
        tracker?.start()
        signals.sessionStarted(BridgeMessages.encode(plan))
        startSegment(0)
        startClock()
    }

    override fun onSegmentFinished(resultJson: String) = post {
        val current = segment ?: return@post
        if (phase !in setOf(Phase.INTRO, Phase.PLAYING, Phase.ENDING)) return@post
        val result = BridgeMessages.parseResult(resultJson) ?: SegmentResult.zero(current.gameId).also {
            log("segment_finished: unreadable result, recording zero: $resultJson")
        }
        log("segment_finished ${current.index}: score=${result.score} stars=${result.stars} skipped=${result.skipped}")
        results += result
        advance()
    }

    override fun onRequestCalibration(mode: String) = post {
        log("request_calibration ${CalibrationMode.fromWire(mode) ?: "unknown mode '$mode'"}")
        if (phase != Phase.FINISHED) tracker?.requestCalibration(mode)
    }

    override fun onSetTrackerMode(mode: String) = post {
        val parsed = TrackerMode.fromWire(mode)
        if (parsed == null) {
            log("set_tracker_mode: unknown mode '$mode'")
            return@post
        }
        log("set_tracker_mode ${parsed.wire}")
        trackerMode = parsed
        // The summary screen never needs the camera.
        if (phase != Phase.FINISHED) tracker?.setTrackerMode(mode)
    }

    override fun onRequestPause() = post {
        if (paused || phase == Phase.WAITING || phase == Phase.FINISHED) return@post
        paused = true
        signals.sessionPaused()
    }

    override fun onRequestResume() = post {
        if (!paused) return@post
        paused = false
        signals.sessionResumed()
    }

    override fun onRequestEnd() = post { end() }

    override fun onRequestExit() = post {
        if (exited) return@post
        // The contract sends request_exit after the summary. A game that leaves early still
        // gets a finished session, so nothing is left running behind the closed host.
        if (phase != Phase.FINISHED) finish()
        exited = true
        onExit()
    }

    private fun end() {
        endRequested = true
        when (phase) {
            Phase.INTRO, Phase.PLAYING -> beginEnding()
            Phase.WAITING, Phase.AWAITING_END -> finish()
            Phase.ENDING, Phase.FINISHED -> Unit
        }
    }

    private fun startSegment(index: Int) {
        val planned = plan.segments[index]
        val message = SegmentStartMessage(
            index = index,
            count = plan.segments.size,
            gameId = planned.gameId,
            durationSec = planned.durationSec,
            introSec = INTRO_SEC,
            endMode = endModeFor(planned),
            role = planned.role,
            difficulty = plan.difficulty,
            effort = planned.role == SegmentRole.WORK,
            seed = random.nextInt(0, Int.MAX_VALUE).toLong(),
            audio = AudioSettings(music = true, musicVolume = 0.8, sfxVolume = 1.0),
            params = JsonObject(emptyMap()),
        )
        segment = message
        phase = Phase.INTRO
        introLeftSec = message.introSec
        playedSec = 0
        updateTimeLeft()
        log("segment_started $index ${message.gameId} ${message.durationSec}s")
        signals.segmentStarted(BridgeMessages.encode(message))
    }

    private fun startClock() {
        scope.launch {
            while (isActive && phase != Phase.FINISHED) {
                delay(TICK_MS)
                if (!paused) tick()
            }
        }
    }

    private fun tick() {
        elapsedSec++
        val current = segment ?: return
        when (phase) {
            Phase.INTRO -> if (--introLeftSec <= 0) phase = Phase.PLAYING
            Phase.PLAYING -> {
                playedSec++
                updateTimeLeft()
                val duration = current.durationSec
                val stopAt = when {
                    duration < 0 -> null
                    current.endMode == EndMode.TIMER -> duration
                    else -> duration * 3 / 2
                }
                if (stopAt != null && playedSec >= stopAt) beginEnding()
            }
            Phase.ENDING -> if (--graceLeftSec <= 0) {
                log("segment ${current.index}: no result within ${GRACE_SEC}s, recording zero")
                results += SegmentResult.zero(current.gameId)
                advance()
            }
            else -> Unit
        }
    }

    private fun beginEnding() {
        phase = Phase.ENDING
        graceLeftSec = GRACE_SEC
        signals.segmentEnding()
    }

    private fun advance() {
        val current = segment ?: return
        val next = current.index + 1
        when {
            endRequested -> finish()
            next < plan.segments.size -> startSegment(next)
            current.durationSec < 0 -> {
                phase = Phase.AWAITING_END
                segmentTimeLeftSec = -1.0
            }
            else -> finish()
        }
    }

    private fun finish() {
        phase = Phase.FINISHED
        segmentTimeLeftSec = -1.0
        tracker?.stop()
        val summary = SessionSummary(
            rideId = null, // Nothing is recorded until #35.
            results = results.toList(),
            totals = SessionTotals(
                score = results.sumOf { it.score },
                stars = results.sumOf { it.stars },
                segments = results.size,
                elapsedSec = elapsedSec,
            ),
            bests = JsonObject(emptyMap()),
        )
        log("session_finished: ${results.size} results")
        signals.sessionFinished(BridgeMessages.encode(summary))
    }

    private fun updateTimeLeft() {
        val duration = segment?.durationSec ?: -1
        segmentTimeLeftSec = if (duration < 0) -1.0 else (duration - playedSec).coerceAtLeast(0).toDouble()
    }

    private fun post(block: () -> Unit) {
        scope.launch { block() }
    }

    companion object {
        const val INTRO_SEC = 10
        const val GRACE_SEC = 5
        private const val TICK_MS = 1_000L

        /** The foundation's default plan: an open-ended Just Ride of the placeholder scene. */
        fun placeholderJustRide() = SessionPlanMessage(
            kind = SessionKind.JUST_RIDE,
            planId = "just-ride:placeholder",
            difficulty = Difficulty.STANDARD,
            totalSec = -1,
            segments = listOf(PlanSegment(gameId = "placeholder", role = SegmentRole.FREE, durationSec = -1)),
        )
    }
}
