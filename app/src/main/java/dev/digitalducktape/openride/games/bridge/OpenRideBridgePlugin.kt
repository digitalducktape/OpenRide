package dev.digitalducktape.openride.games.bridge

import org.godotengine.godot.Godot
import org.godotengine.godot.plugin.GodotPlugin
import org.godotengine.godot.plugin.SignalInfo
import org.godotengine.godot.plugin.UsedByGodot

/**
 * The `OpenRideBridge` engine singleton (Bridge contract v1, docs/GAMES.md), registered by
 * `GameHostActivity` as a host plugin. GDScript reaches it only through the `InputBus` and
 * `Session` autoloads, as `Engine.get_singleton("OpenRideBridge")`.
 *
 * A thin adapter: Godot keeps this first instance for the life of the process, so all state
 * lives in the app-scoped [GameBridge]. Method names are the contract's snake_case names,
 * because GDScript calls them by their JVM name.
 */
@Suppress("FunctionName")
class OpenRideBridgePlugin(godot: Godot, private val bridge: GameBridge) : GodotPlugin(godot), GameSignals {
    init {
        bridge.emitter = this
    }

    override fun getPluginName() = NAME

    override fun getPluginSignals(): Set<SignalInfo> = SIGNALS

    // --- Godot → Kotlin methods ---

    /** The v1 input frame ([InputFrame]); arrives in GDScript as a `PackedFloat64Array`. */
    @UsedByGodot
    fun get_input_frame(): DoubleArray = bridge.inputFrame()

    @UsedByGodot
    fun segment_finished(resultJson: String) = bridge.segmentFinished(resultJson)

    @UsedByGodot
    fun request_calibration(mode: String) = bridge.requestCalibration(mode)

    @UsedByGodot
    fun set_tracker_mode(mode: String) = bridge.setTrackerMode(mode)

    @UsedByGodot
    fun request_pause() = bridge.requestPause()

    @UsedByGodot
    fun request_resume() = bridge.requestResume()

    @UsedByGodot
    fun request_end() = bridge.requestEnd()

    @UsedByGodot
    fun request_exit() = bridge.requestExit()

    // --- Kotlin → Godot signals (GodotPlugin queues them onto Godot's thread) ---

    override fun sessionStarted(planJson: String) = emitSignal(SESSION_STARTED.name, planJson)
    override fun segmentStarted(segmentJson: String) = emitSignal(SEGMENT_STARTED.name, segmentJson)
    override fun segmentEnding() = emitSignal(SEGMENT_ENDING.name)
    override fun sessionPaused() = emitSignal(SESSION_PAUSED.name)
    override fun sessionResumed() = emitSignal(SESSION_RESUMED.name)
    override fun calibrationProgress(step: String, fraction: Double) =
        emitSignal(CALIBRATION_PROGRESS.name, step, fraction)
    override fun sessionFinished(summaryJson: String) = emitSignal(SESSION_FINISHED.name, summaryJson)

    companion object {
        const val NAME = "OpenRideBridge"

        private val SESSION_STARTED = SignalInfo("session_started", String::class.java)
        private val SEGMENT_STARTED = SignalInfo("segment_started", String::class.java)
        private val SEGMENT_ENDING = SignalInfo("segment_ending")
        private val SESSION_PAUSED = SignalInfo("session_paused")
        private val SESSION_RESUMED = SignalInfo("session_resumed")
        private val CALIBRATION_PROGRESS =
            SignalInfo("calibration_progress", String::class.java, Double::class.javaObjectType)
        private val SESSION_FINISHED = SignalInfo("session_finished", String::class.java)

        private val SIGNALS = setOf(
            SESSION_STARTED, SEGMENT_STARTED, SEGMENT_ENDING, SESSION_PAUSED, SESSION_RESUMED,
            CALIBRATION_PROGRESS, SESSION_FINISHED,
        )
    }
}
