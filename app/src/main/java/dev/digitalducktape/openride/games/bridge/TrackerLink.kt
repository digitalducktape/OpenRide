package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.camera.CalibrationProgress
import dev.digitalducktape.openride.core.camera.HeadTracker
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import dev.digitalducktape.openride.core.telemetry.CalibrationResult
import dev.digitalducktape.openride.core.telemetry.HeadCalibration
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.trackSafely
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import dev.digitalducktape.openride.core.camera.TrackerMode as CameraMode
import dev.digitalducktape.openride.core.camera.TrackerState as CameraTrackerState
import dev.digitalducktape.openride.core.telemetry.CalibrationMode as TelemetryMode

/**
 * `calibration_progress(step, fraction, step_index, step_count, attempt, retry_reason)`, which
 * drives the calibration UI that Godot draws (Bridge contract, docs/GAMES.md).
 *
 * @param step `centre`, `left`, `right`, `in` or `back`.
 * @param fraction 0..1 through the current step; restarts from 0 on a retry.
 * @param stepIndex 0-based position of [step] in this calibration.
 * @param stepCount steps in this calibration: 1 when only the centre is re-taken, 3 for
 *   `lean_x`, 5 for `lean_2d`.
 * @param attempt 1 for the first try at this step, 2+ for retries.
 * @param retryReason why the step is being repeated (`unstable`, `no_face`, `too_small`,
 *   `wrong_direction`), or `""` on a first attempt.
 */
data class CalibrationProgressSignal(
    val step: String,
    val fraction: Double,
    val stepIndex: Int,
    val stepCount: Int,
    val attempt: Int,
    val retryReason: String,
) {
    companion object {
        fun from(progress: CalibrationProgress) = CalibrationProgressSignal(
            step = progress.step.wireName,
            fraction = progress.fraction.coerceIn(0.0, 1.0),
            stepIndex = progress.stepIndex,
            stepCount = progress.stepCount,
            attempt = progress.attempt,
            retryReason = progress.retryReason?.wireName ?: "",
        )
    }
}

/** Input frame fields 6-9 from a head-tracker snapshot. */
fun HeadTrackerState.toTrackerReading(): TrackerReading = TrackerReading(
    leanX = leanX,
    leanDepth = leanDepth,
    standing = standing,
    state = when (trackerState) {
        CameraTrackerState.OFF -> TrackerState.OFF
        CameraTrackerState.NEEDS_CALIBRATION -> TrackerState.NEEDS_CALIBRATION
        CameraTrackerState.CALIBRATING -> TrackerState.CALIBRATING
        CameraTrackerState.TRACKING -> TrackerState.TRACKING
        CameraTrackerState.FACE_LOST -> TrackerState.FACE_LOST
    },
)

/**
 * One Games hub visit's use of the app's [HeadTracker] (spec §6, "calibrate once per visit"):
 * the contract's tracker methods, the hub's calibration, and `calibration_progress` while a
 * calibration runs. Fields 6-9 of the input frame don't go through here; [GameBridge] reads the
 * tracker's state directly, visit or not.
 *
 * - [startVisit] forgets the last visit's centre: the centre is re-taken once per visit (a
 *   silently off-centre calibration was the spike's worst failure), not per plan, so a later
 *   plan's camera game tracks at once.
 * - `set_tracker_mode(mode)` switches the camera on or off. A camera mode that has no
 *   calibration this visit starts one at once, reusing the rider's same-day extremes, so the
 *   visit's first camera game only re-takes the centre (3 s).
 * - `request_calibration(mode)` (the rider asked to recalibrate) runs every step.
 * - [hubCalibrate] calibrates from the hub (`full` forces every step); the camera turns off
 *   again when that calibration ends, however it ends, or on [cancelCalibration]. The camera is
 *   the tablet's biggest CPU cost, so it never runs idle in the menu.
 * - [planEnded] turns the camera off between plans, keeping the centre; [endVisit] also forgets it.
 * - [calibratedMode] is what this visit's calibration covers (`""`, `lean_x`, `lean_2d`).
 * - [calibrating] is true while any calibration runs (automatic, requested or for depth); a
 *   plan pauses on it, so a game never plays on while the rider holds still for the camera.
 *
 * Not thread-safe: the visit calls it from one thread. [HeadTracker] itself is thread-safe.
 */
class TrackerLink(
    private val tracker: HeadTracker,
    private val signals: GameSignals,
    private val scope: CoroutineScope,
    private val log: (String) -> Unit = {},
    private val telemetry: Telemetry = NoOpTelemetry,
) {
    private var progressJob: Job? = null
    private var watchJob: Job? = null
    private var calibrated = ""

    /** A calibration this link started hasn't been seen to end yet. */
    private var calibrationRunning = false

    /** A hub calibration is running ([hubCalibrate]). */
    var hubCalibrating = false
        private set

    /** The mode of the hub calibration in progress, for `head_calibration` (#85). */
    private var hubMode: CalibrationMode? = null

    /** Called when a hub calibration ends (completed, failed or cancelled): the visit resends `hub_state`. */
    var onHubCalibrationEnded: () -> Unit = {}

    /**
     * Whether a calibration is running: true from its start until it completes (`used_default`
     * fallbacks included, since calibration moves on after them) or ends as unavailable.
     */
    val calibrating: Flow<Boolean> = tracker.state
        .map { it.trackerState == CameraTrackerState.CALIBRATING }
        .distinctUntilChanged()

    /** A new visit: forget the last visit's centre, and follow this visit's calibrations. */
    fun startVisit() {
        progressJob?.cancel()
        watchJob?.cancel()
        tracker.resetSession()
        calibrated = ""
        hubCalibrating = false
        calibrationRunning = false
        progressJob = scope.launch {
            tracker.state
                .map { it.calibration }
                .distinctUntilChanged()
                .filterNotNull()
                .collect { signals.calibrationProgress(CalibrationProgressSignal.from(it)) }
        }
        // Not "saw CALIBRATING, then something else": a StateFlow collector can miss a short
        // calibration's states, so the link remembers the calibrations it started itself.
        watchJob = scope.launch {
            tracker.state.collect { state ->
                if (calibrationRunning && state.trackerState != CameraTrackerState.CALIBRATING) {
                    calibrationRunning = false
                    calibrationEnded(state)
                }
            }
        }
        val mode = tracker.state.value.mode
        if (mode != CameraMode.OFF) calibrate(mode, force = false)
    }

    private fun calibrate(mode: CameraMode, force: Boolean) {
        tracker.calibrate(mode, force)
        calibrationRunning = tracker.state.value.trackerState == CameraTrackerState.CALIBRATING
        // A calibration that couldn't even start (camera unavailable) has ended already.
        if (!calibrationRunning) calibrationEnded(tracker.state.value)
    }

    private fun calibrationEnded(state: HeadTrackerState) {
        if (state.trackerState == CameraTrackerState.TRACKING || state.trackerState == CameraTrackerState.FACE_LOST) {
            calibrated = when {
                state.mode == CameraMode.LEAN_2D || calibrated == CalibrationMode.LEAN_2D.wire -> CalibrationMode.LEAN_2D.wire
                else -> CalibrationMode.LEAN_X.wire
            }
        }
        if (hubCalibrating) {
            hubCalibrating = false
            // Completed is a success; ending unavailable (no face, no camera) is a failure.
            val completed = state.trackerState == CameraTrackerState.TRACKING || state.trackerState == CameraTrackerState.FACE_LOST
            trackCalibration(if (completed) CalibrationResult.SUCCESS else CalibrationResult.FAILED)
            tracker.setMode(CameraMode.OFF)
            onHubCalibrationEnded()
        }
    }

    /** What this visit's calibration covers: `""` (none yet), `lean_x` or `lean_2d`. */
    fun calibratedMode(): String = calibrated

    /**
     * Calibrates from the hub: the camera on in [wire]'s mode, then every step if [full], else
     * the centre only when the rider's extremes are from today. The camera goes off when it ends.
     */
    fun hubCalibrate(wire: String, full: Boolean) {
        val mode = CalibrationMode.fromWire(wire)?.toCameraMode()
            ?: return log("hub_calibrate: unknown mode '$wire'")
        hubCalibrating = true
        hubMode = CalibrationMode.fromWire(wire)
        tracker.setMode(mode)
        calibrate(mode, force = full)
    }

    private fun trackCalibration(result: CalibrationResult) {
        val mode = when (hubMode) {
            CalibrationMode.LEAN_X -> TelemetryMode.LEAN_X
            CalibrationMode.LEAN_2D -> TelemetryMode.LEAN_2D
            null -> return log("head_calibration: no mode known, not sent")
        }
        telemetry.trackSafely { HeadCalibration(result, mode) }
    }

    /** Stops a hub calibration: the camera off. The visit's earlier calibration stays. */
    fun cancelCalibration() {
        if (!hubCalibrating) return
        hubCalibrating = false
        calibrationRunning = false
        trackCalibration(CalibrationResult.CANCELLED)
        tracker.setMode(CameraMode.OFF)
        onHubCalibrationEnded()
    }

    fun setTrackerMode(wire: String) {
        val mode = TrackerMode.fromWire(wire)?.toCameraMode()
            ?: return log("set_tracker_mode: unknown mode '$wire'")
        tracker.setMode(mode)
        if (mode != CameraMode.OFF && tracker.state.value.trackerState == CameraTrackerState.NEEDS_CALIBRATION) {
            calibrate(mode, force = false)
        }
    }

    fun requestCalibration(wire: String) {
        val mode = CalibrationMode.fromWire(wire)?.toCameraMode()
            ?: return log("request_calibration: unknown mode '$wire'")
        calibrate(mode, force = true)
    }

    /** The hub's camera-games switch: off keeps the camera from running at all. */
    fun setCameraGamesEnabled(enabled: Boolean) = tracker.setCameraGamesEnabled(enabled)

    /** The camera permission may have changed (the host's prompt answered). */
    fun refreshPermission() = tracker.refreshPermission()

    /** Between plans: the camera off, keeping this visit's centre. */
    fun planEnded() {
        tracker.setMode(CameraMode.OFF)
    }

    /** The visit is over: the camera off, and its centre forgotten. */
    fun endVisit() {
        progressJob?.cancel()
        progressJob = null
        watchJob?.cancel()
        watchJob = null
        hubCalibrating = false
        calibrationRunning = false
        tracker.setMode(CameraMode.OFF)
        tracker.resetSession()
        calibrated = ""
    }

    private fun TrackerMode.toCameraMode(): CameraMode = when (this) {
        TrackerMode.OFF -> CameraMode.OFF
        TrackerMode.LEAN_X -> CameraMode.LEAN_X
        TrackerMode.LEAN_2D -> CameraMode.LEAN_2D
        TrackerMode.LEAN_STAND -> CameraMode.LEAN_STAND
    }

    private fun CalibrationMode.toCameraMode(): CameraMode = when (this) {
        CalibrationMode.LEAN_X -> CameraMode.LEAN_X
        CalibrationMode.LEAN_2D -> CameraMode.LEAN_2D
    }
}
