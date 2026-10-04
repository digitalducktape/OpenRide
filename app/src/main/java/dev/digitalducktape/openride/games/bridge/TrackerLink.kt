package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.camera.CalibrationProgress
import dev.digitalducktape.openride.core.camera.HeadTracker
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import dev.digitalducktape.openride.core.camera.TrackerMode as CameraMode
import dev.digitalducktape.openride.core.camera.TrackerState as CameraTrackerState

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
 * One game session's use of the app's [HeadTracker]: the contract's tracker methods, and
 * `calibration_progress` while a calibration runs. Fields 6-9 of the input frame don't go through
 * here; [GameBridge] reads the tracker's state directly, session or not.
 *
 * - [start] (`session_started`) forgets the last session's centre: the centre is re-taken every
 *   session, because a silently off-centre calibration was the spike's worst failure.
 * - `set_tracker_mode(mode)` switches the camera on or off. A camera mode that has no
 *   calibration this session starts one at once, reusing the rider's same-day extremes, so
 *   the first camera game of a session only re-takes the centre (3 s).
 * - `request_calibration(mode)` (the rider asked to recalibrate) runs every step.
 * - [stop] turns the camera off when the session ends or the rider leaves games.
 * - [calibrating] is true while any calibration runs (automatic, requested or for depth); the
 *   session pauses on it, so a game never plays on while the rider holds still for the camera.
 *
 * Not thread-safe: the session calls it from one thread. [HeadTracker] itself is thread-safe.
 */
class TrackerLink(
    private val tracker: HeadTracker,
    private val signals: GameSignals,
    private val scope: CoroutineScope,
    private val log: (String) -> Unit = {},
) {
    private var progressJob: Job? = null

    /**
     * Whether a calibration is running: true from its start until it completes (`used_default`
     * fallbacks included, since calibration moves on after them) or ends as unavailable.
     */
    val calibrating: Flow<Boolean> = tracker.state
        .map { it.trackerState == CameraTrackerState.CALIBRATING }
        .distinctUntilChanged()

    fun start() {
        progressJob?.cancel()
        tracker.resetSession()
        progressJob = scope.launch {
            tracker.state
                .map { it.calibration }
                .distinctUntilChanged()
                .filterNotNull()
                .collect { signals.calibrationProgress(CalibrationProgressSignal.from(it)) }
        }
        val mode = tracker.state.value.mode
        if (mode != CameraMode.OFF) tracker.calibrate(mode, force = false)
    }

    fun setTrackerMode(wire: String) {
        val mode = TrackerMode.fromWire(wire)?.toCameraMode()
            ?: return log("set_tracker_mode: unknown mode '$wire'")
        tracker.setMode(mode)
        if (mode != CameraMode.OFF && tracker.state.value.trackerState == CameraTrackerState.NEEDS_CALIBRATION) {
            tracker.calibrate(mode, force = false)
        }
    }

    fun requestCalibration(wire: String) {
        val mode = CalibrationMode.fromWire(wire)?.toCameraMode()
            ?: return log("request_calibration: unknown mode '$wire'")
        tracker.calibrate(mode, force = true)
    }

    fun stop() {
        progressJob?.cancel()
        progressJob = null
        tracker.setMode(CameraMode.OFF)
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
