package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.camera.CalibrationProgress
import dev.digitalducktape.openride.core.camera.CalibrationRetryReason
import dev.digitalducktape.openride.core.camera.CalibrationStep
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import dev.digitalducktape.openride.core.telemetry.CalibrationResult
import dev.digitalducktape.openride.core.telemetry.HeadCalibration
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
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
    override fun hubState(stateJson: String) = Unit
    override fun planRejected(reasonJson: String) = Unit
    override fun visitEnded(resultJson: String) = Unit
}

@OptIn(ExperimentalCoroutinesApi::class)
class TrackerLinkTest {
    private val scope = TestScope()
    private val tracker = FakeHeadTracker()
    private val signals = ProgressRecorder()
    private val log = mutableListOf<String>()
    private val telemetry = RecordingTelemetry()
    private val link = TrackerLink(tracker, signals, scope, log = { log += it }, telemetry = telemetry)
    private fun calibrations() = telemetry.events.filterIsInstance<HeadCalibration>().map { it.result.wire to it.mode.wire }

    // --- input frame fields 6-9 ---------------------------------------------------------------

    @Test
    fun `tracker snapshots map onto input frame fields 6-9`() {
        val bridge = GameBridge(FakeBikeDataSource(), MutableStateFlow(false), MutableStateFlow(null), trackerReading = { tracker.state.value.toTrackerReading() })
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
    fun `progress is forwarded while calibrating, without repeats, and not after the visit ends`() {
        link.startVisit()
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

        link.endVisit()
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
    fun `a visit starts by forgetting the last visit's centre`() {
        link.startVisit()

        assertEquals(listOf("resetSession"), tracker.calls)
    }

    @Test
    fun `the first camera mode of a visit calibrates, reusing same-day extremes`() {
        link.startVisit()
        link.setTrackerMode("lean_x")

        assertEquals(listOf("resetSession", "setMode:lean_x", "calibrate:lean_x:force=false"), tracker.calls)
    }

    @Test
    fun `a later camera game in the same visit tracks straight away`() {
        link.startVisit()
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
    fun `a visit that starts with the camera already on re-takes the centre`() {
        tracker.setMode(CameraMode.LEAN_X)
        tracker.calls.clear()

        link.startVisit()

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
    fun `the end of a visit turns the camera off and forgets its centre`() {
        link.startVisit()
        link.setTrackerMode("lean_x")
        link.endVisit()

        assertEquals(listOf("setMode:off", "resetSession"), tracker.calls.takeLast(2))
        assertEquals(CameraMode.OFF, tracker.state.value.mode)
    }

    // --- once per visit (the Games hub, spec §6) ----------------------------------------------

    @Test
    fun `the centre is taken once per visit, not per plan`() {
        link.startVisit()
        link.setTrackerMode("lean_x")
        tracker.finishCalibration()
        scope.runCurrent()
        link.planEnded()
        link.setTrackerMode("lean_x") // the second plan's camera game

        assertEquals(1, tracker.calls.count { it == "resetSession" })
        assertEquals(1, tracker.calls.count { it.startsWith("calibrate") })
        assertEquals(CameraTrackerState.TRACKING, tracker.state.value.trackerState)
        assertEquals("setMode:off", tracker.calls[tracker.calls.size - 2])
    }

    @Test
    fun `a hub calibration reuses same-day extremes unless full, and the camera goes off when it ends`() {
        link.startVisit()
        scope.runCurrent()
        link.hubCalibrate("lean_x", full = false)
        assertEquals(listOf("resetSession", "setMode:lean_x", "calibrate:lean_x:force=false"), tracker.calls)
        assertTrue(link.hubCalibrating)

        tracker.finishCalibration()
        scope.runCurrent()
        assertEquals("setMode:off", tracker.calls.last())
        assertFalse(link.hubCalibrating)
        assertEquals("lean_x", link.calibratedMode())

        link.hubCalibrate("lean_x", full = true)
        assertEquals("calibrate:lean_x:force=true", tracker.calls.last())
    }

    @Test
    fun `the camera goes off when a hub calibration fails, and the visit stays uncalibrated`() {
        var ended = 0
        link.onHubCalibrationEnded = { ended++ }
        link.startVisit()
        scope.runCurrent()
        link.hubCalibrate("lean_x", full = false)
        tracker.failCalibration()
        scope.runCurrent()

        assertEquals("setMode:off", tracker.calls.last())
        assertEquals("", link.calibratedMode())
        assertEquals(1, ended)
    }

    @Test
    fun `cancelling a hub calibration turns the camera off and keeps the earlier calibration`() {
        link.startVisit()
        scope.runCurrent()
        link.hubCalibrate("lean_x", full = false)
        tracker.finishCalibration()
        scope.runCurrent()
        link.hubCalibrate("lean_x", full = true)

        link.cancelCalibration()
        scope.runCurrent()

        assertEquals("setMode:off", tracker.calls.last())
        assertFalse(link.hubCalibrating)
        assertEquals("lean_x", link.calibratedMode())
        link.cancelCalibration() // nothing running: nothing happens
        assertEquals(2, tracker.calls.count { it == "setMode:off" })
    }

    @Test
    fun `the visit's calibration covers depth once a lean_2d calibration completes, and a new visit forgets it`() {
        link.startVisit()
        scope.runCurrent()
        link.setTrackerMode("lean_2d") // a plan's depth game calibrates by itself
        tracker.finishCalibration()
        scope.runCurrent()
        assertEquals("lean_2d", link.calibratedMode())
        link.requestCalibration("lean_x")
        tracker.finishCalibration()
        scope.runCurrent()
        assertEquals("lean_2d", link.calibratedMode()) // depth extremes are still there

        link.endVisit()
        link.startVisit()
        assertEquals("", link.calibratedMode())
    }

    @Test
    fun `a completed hub calibration emits success with its mode`() {
        link.startVisit()
        scope.runCurrent()
        link.hubCalibrate("lean_2d", full = true)
        tracker.finishCalibration()
        scope.runCurrent()

        assertEquals(listOf("success" to "lean_2d"), calibrations())
    }

    @Test
    fun `a cancelled hub calibration emits cancelled, once`() {
        link.startVisit()
        scope.runCurrent()
        link.hubCalibrate("lean_x", full = false)
        link.cancelCalibration()
        scope.runCurrent()
        link.cancelCalibration()

        assertEquals(listOf("cancelled" to "lean_x"), calibrations())
    }

    @Test
    fun `a calibration that fails to complete emits nothing, and nor does one outside the hub`() {
        link.startVisit()
        scope.runCurrent()
        link.hubCalibrate("lean_x", full = false)
        tracker.failCalibration()
        scope.runCurrent()
        link.requestCalibration("lean_x") // in a plan, not the hub
        tracker.finishCalibration()
        scope.runCurrent()

        assertTrue(calibrations().isEmpty())
    }
}
