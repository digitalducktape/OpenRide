package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.camera.CalibrationProgress
import dev.digitalducktape.openride.core.camera.CalibrationRetryReason
import dev.digitalducktape.openride.core.camera.CalibrationStep
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Test
import dev.digitalducktape.openride.core.camera.TrackerMode as CameraMode
import dev.digitalducktape.openride.core.camera.TrackerState as CameraTrackerState

private class ProgressRecorder : GameSignals {
    val progress = mutableListOf<CalibrationProgressSignal>()

    override fun sessionStarted(planJson: String) = Unit
    override fun segmentStarted(segmentJson: String) = Unit
    override fun segmentEnding() = Unit
    override fun sessionPaused() = Unit
    override fun sessionResumed() = Unit
    override fun calibrationProgress(progress: CalibrationProgressSignal) { this.progress += progress }
    override fun sessionFinished(summaryJson: String) = Unit
}

@OptIn(ExperimentalCoroutinesApi::class)
class TrackerLinkTest {
    private val scope = TestScope()
    private val tracker = FakeHeadTracker()
    private val signals = ProgressRecorder()
    private val log = mutableListOf<String>()
    private val link = TrackerLink(tracker, signals, scope, log = { log += it })

    // --- input frame fields 6-9 ---------------------------------------------------------------

    @Test
    fun `tracker snapshots map onto input frame fields 6-9`() {
        val bridge = GameBridge(FakeBikeDataSource(), MutableStateFlow(null)) { tracker.state.value.toTrackerReading() }
        tracker.mutableState.value = HeadTrackerState(
            mode = CameraMode.LEAN_2D,
            trackerState = CameraTrackerState.TRACKING,
            leanX = -0.75,
            leanDepth = 0.4,
            standing = true,
        )

        val frame = bridge.inputFrame()

        assertEquals(-0.75, frame[InputFrame.LEAN_X], 0.0)
        assertEquals(0.4, frame[InputFrame.LEAN_DEPTH], 0.0)
        assertEquals(1.0, frame[InputFrame.STANDING], 0.0)
        assertEquals(3.0, frame[InputFrame.TRACKER_STATE], 0.0)
    }

    @Test
    fun `every tracker state keeps its contract code`() {
        for (state in CameraTrackerState.entries) {
            val reading = HeadTrackerState(trackerState = state).toTrackerReading()
            assertEquals(state.name, state.code, reading.state.code)
            assertEquals(state.name, reading.state.name)
        }
    }

    @Test
    fun `a tracker that is off reads as zeros and state 0`() {
        assertEquals(TrackerReading.OFF, HeadTrackerState().toTrackerReading())
    }

    // --- calibration_progress --------------------------------------------------------------

    @Test
    fun `calibration progress carries the step as its wire name plus index, count, attempt and reason`() {
        val signal = CalibrationProgressSignal.from(
            CalibrationProgress(CalibrationStep.RIGHT, stepIndex = 2, stepCount = 3, fraction = 0.4, attempt = 2, retryReason = CalibrationRetryReason.WRONG_DIRECTION),
        )

        assertEquals(CalibrationProgressSignal("right", 0.4, 2, 3, 2, "wrong_direction"), signal)
    }

    @Test
    fun `a first attempt has an empty retry reason`() {
        val signal = CalibrationProgressSignal.from(CalibrationProgress(CalibrationStep.CENTRE, 0, 1, 0.0, 1, null))

        assertEquals("", signal.retryReason)
        assertEquals("centre", signal.step)
    }

    @Test
    fun `progress is forwarded while calibrating, without repeats, and not after stop`() {
        link.start()
        scope.runCurrent()
        val centre = CalibrationProgress(CalibrationStep.CENTRE, 0, 3, 0.5, 1, null)
        tracker.mutableState.value = HeadTrackerState(mode = CameraMode.LEAN_X, trackerState = CameraTrackerState.CALIBRATING, calibration = centre)
        scope.runCurrent()
        tracker.mutableState.value = tracker.mutableState.value.copy(leanX = 0.01) // same progress
        scope.runCurrent()
        tracker.mutableState.value = tracker.mutableState.value.copy(calibration = centre.copy(fraction = 0.0, attempt = 2, retryReason = CalibrationRetryReason.UNSTABLE))
        scope.runCurrent()
        tracker.mutableState.value = HeadTrackerState(mode = CameraMode.LEAN_X, trackerState = CameraTrackerState.TRACKING)
        scope.runCurrent()

        link.stop()
        tracker.mutableState.value = HeadTrackerState(mode = CameraMode.LEAN_X, trackerState = CameraTrackerState.CALIBRATING, calibration = centre)
        scope.runCurrent()

        assertEquals(
            listOf(
                CalibrationProgressSignal("centre", 0.5, 0, 3, 1, ""),
                CalibrationProgressSignal("centre", 0.0, 0, 3, 2, "unstable"),
            ),
            signals.progress,
        )
    }

    // --- commands ----------------------------------------------------------------------------

    @Test
    fun `a session starts by forgetting the last session's centre`() {
        link.start()

        assertEquals(listOf("resetSession"), tracker.calls)
    }

    @Test
    fun `the first camera mode of a session calibrates, reusing same-day extremes`() {
        link.start()
        link.setTrackerMode("lean_x")

        assertEquals(listOf("resetSession", "setMode:lean_x", "calibrate:lean_x:force=false"), tracker.calls)
    }

    @Test
    fun `a later camera game in the same session tracks straight away`() {
        link.start()
        link.setTrackerMode("lean_x")
        tracker.finishCalibration()
        link.setTrackerMode("off")
        link.setTrackerMode("lean_stand")

        assertEquals(
            listOf("resetSession", "setMode:lean_x", "calibrate:lean_x:force=false", "setMode:off", "setMode:lean_stand"),
            tracker.calls,
        )
    }

    @Test
    fun `a session that starts with the camera already on re-takes the centre`() {
        tracker.setMode(CameraMode.LEAN_X)
        tracker.calls.clear()

        link.start()

        assertEquals(listOf("resetSession", "calibrate:lean_x:force=false"), tracker.calls)
    }

    @Test
    fun `request_calibration runs the full calibration`() {
        link.requestCalibration("lean_2d")

        assertEquals(listOf("calibrate:lean_2d:force=true"), tracker.calls)
    }

    @Test
    fun `unknown modes are logged and ignored`() {
        link.setTrackerMode("lean_z")
        link.requestCalibration("lean_stand") // not a calibration mode

        assertEquals(emptyList<String>(), tracker.calls)
        assertEquals(2, log.size)
    }

    @Test
    fun `stop turns the camera off`() {
        link.start()
        link.setTrackerMode("lean_x")
        link.stop()

        assertEquals("setMode:off", tracker.calls.last())
        assertEquals(CameraMode.OFF, tracker.state.value.mode)
    }
}
