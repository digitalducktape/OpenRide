package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.sensor.BikeDataSource
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.flow.StateFlow

/** Kotlin → Godot signals of the v1 Bridge contract. JSON arguments are JSON text. */
interface GameSignals {
    fun sessionStarted(planJson: String)
    fun segmentStarted(segmentJson: String)
    fun segmentEnding()
    fun sessionPaused()
    fun sessionResumed()
    fun calibrationProgress(progress: CalibrationProgressSignal)
    fun sessionFinished(summaryJson: String)
}

/**
 * The Kotlin side of one game session: answers the contract's Godot → Kotlin methods and owns
 * the session clock. [dev.digitalducktape.openride.games.session.StubGameSession] until the
 * real `GameSessionManager` (#35) replaces it.
 *
 * The bridge calls these on Godot's thread; implementations hand off to their own.
 */
interface GameSession {
    /** Input frame index 10: gameplay seconds left in the current segment, -1 if open-ended or none. */
    val segmentTimeLeftSec: Double

    /** Godot is running and polling frames, so its signal handlers are connected: start the session. */
    fun onGameReady()

    fun onSegmentFinished(resultJson: String)
    fun onRequestCalibration(mode: String)
    fun onSetTrackerMode(mode: String)
    fun onRequestPause()
    fun onRequestResume()
    fun onRequestEnd()
    fun onRequestExit()
}

/**
 * App-scoped hub between the Godot plugin ([OpenRideBridgePlugin]) and whichever [GameSession]
 * the current `GameHostActivity` attached.
 *
 * App-scoped because Godot runs one engine per process and registers host plugins only on its
 * first start: after leaving and re-entering games, GDScript still talks to the first plugin
 * instance, so everything per-session lives here behind [attach]/[detach], never in the plugin.
 *
 * Readiness is implicit, so the contract needs no extra method: Godot connects its signal
 * handlers in the autoloads' `_ready`, before the first frame, so the first `get_input_frame()`
 * poll after [attach] is when the session may start sending signals ([GameSession.onGameReady]).
 */
class GameBridge(
    private val bikeDataSource: BikeDataSource,
    private val heartRateBpm: StateFlow<Int?>,
    /** Head-tracker fields 6-9: the camera tracker's latest snapshot (see [toTrackerReading]). */
    private val trackerReading: () -> TrackerReading = { TrackerReading.OFF },
) : GameSignals {
    @Volatile
    private var session: GameSession? = null
    private val readyPending = AtomicBoolean(false)

    /** Godot's side of the signals: the registered plugin, once the engine has started. */
    @Volatile
    var emitter: GameSignals? = null

    fun attach(session: GameSession) {
        this.session = session
        readyPending.set(true)
    }

    /** Detaches [session] if it is still the current one (a newer host may already have attached). */
    fun detach(session: GameSession) {
        if (this.session === session) {
            this.session = null
            readyPending.set(false)
        }
    }

    // --- Godot → Kotlin (called on Godot's thread) ---

    fun inputFrame(): DoubleArray {
        val current = session
        if (current != null && readyPending.compareAndSet(true, false)) current.onGameReady()
        return InputFrame.pack(
            metrics = bikeDataSource.metrics.value,
            connection = bikeDataSource.connectionState.value,
            heartRateBpm = heartRateBpm.value,
            tracker = trackerReading(),
            segmentTimeLeftSec = current?.segmentTimeLeftSec ?: -1.0,
        )
    }

    fun segmentFinished(resultJson: String) { session?.onSegmentFinished(resultJson) }
    fun requestCalibration(mode: String) { session?.onRequestCalibration(mode) }
    fun setTrackerMode(mode: String) { session?.onSetTrackerMode(mode) }
    fun requestPause() { session?.onRequestPause() }
    fun requestResume() { session?.onRequestResume() }
    fun requestEnd() { session?.onRequestEnd() }
    fun requestExit() { session?.onRequestExit() }

    // --- Kotlin → Godot ---

    override fun sessionStarted(planJson: String) { emitter?.sessionStarted(planJson) }
    override fun segmentStarted(segmentJson: String) { emitter?.segmentStarted(segmentJson) }
    override fun segmentEnding() { emitter?.segmentEnding() }
    override fun sessionPaused() { emitter?.sessionPaused() }
    override fun sessionResumed() { emitter?.sessionResumed() }
    override fun calibrationProgress(progress: CalibrationProgressSignal) { emitter?.calibrationProgress(progress) }
    override fun sessionFinished(summaryJson: String) { emitter?.sessionFinished(summaryJson) }
}
