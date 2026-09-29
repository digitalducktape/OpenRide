@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.core.camera

import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class DefaultHeadTrackerTest {

    private class FakeFaceSource : FaceSource {
        var listener: FaceSource.Listener? = null
        var starts = 0
        val running get() = listener != null

        override fun start(listener: FaceSource.Listener) {
            starts++
            this.listener = listener
        }

        override fun stop() {
            listener = null
        }

        fun emit(script: FrameScript) {
            script.frames.forEach { listener?.onFrame(it.timestampMs, it.face) }
            script.frames.clear()
        }

        fun fail() = listener!!.onError(IllegalStateException("camera bind failed"))
    }

    private val zone = ZoneId.of("America/Los_Angeles")
    private val today = LocalDateTime.parse("2026-09-27T18:00:00").atZone(zone).toInstant().toEpochMilli()
    private val yesterday = today - 24 * 3_600_000L

    private val source = FakeFaceSource()
    private val store = InMemoryHeadCalibrationStore()
    private val profileId = MutableStateFlow<Long?>(7L)
    private var permission = true
    private val config = HeadTrackerConfig()
    private val centreMs = config.centreSettleMs + config.centreCaptureMs
    private val extremeMs = config.extremeSettleMs + config.extremeCaptureMs

    private fun TestScope.tracker(scope: CoroutineScope = backgroundScope): DefaultHeadTracker =
        DefaultHeadTracker(
            faceSource = source,
            calibrationStore = store,
            activeProfileId = profileId,
            hasCameraPermission = { permission },
            scope = scope,
            config = config,
            wallClockMs = { today },
            zone = { zone },
        ).also { runCurrent() }

    private fun fullCalibrationScript(start: Long = 0L) = FrameScript(start)
        .hold(centreMs, SEATED)
        .hold(extremeMs, SEATED.shifted(dx = LEFT_LEAN_DX))
        .hold(extremeMs, SEATED.shifted(dx = RIGHT_LEAN_DX))
        .hold(100, SEATED)

    @Test
    fun `the camera only runs while a mode is on`() = runTest {
        val tracker = tracker()
        assertFalse(source.running)
        assertEquals(TrackerState.OFF, tracker.state.value.trackerState)

        tracker.setMode(TrackerMode.LEAN_X)
        assertTrue(source.running)
        assertEquals(TrackerMode.LEAN_X, tracker.state.value.mode)

        tracker.setMode(TrackerMode.OFF)
        assertFalse(source.running)
        assertEquals(TrackerState.OFF, tracker.state.value.trackerState)
    }

    @Test
    fun `without the camera permission the tracker is unavailable and the camera stays off`() = runTest {
        permission = false
        val tracker = tracker()
        assertEquals(UnavailableReason.PERMISSION_DENIED, tracker.state.value.unavailable)

        tracker.setMode(TrackerMode.LEAN_X)
        assertFalse(source.running)
        assertEquals(TrackerState.OFF, tracker.state.value.trackerState)

        // The hub asks, the rider grants, the hub tells the tracker.
        permission = true
        tracker.refreshPermission()
        assertNull(tracker.state.value.unavailable)
        assertTrue(source.running)
    }

    @Test
    fun `camera games turned off make the tracker unavailable`() = runTest {
        val tracker = tracker()
        tracker.setCameraGamesEnabled(false)
        tracker.setMode(TrackerMode.LEAN_X)
        assertEquals(UnavailableReason.CAMERA_GAMES_OFF, tracker.state.value.unavailable)
        assertFalse(source.running)

        tracker.setCameraGamesEnabled(true)
        assertNull(tracker.state.value.unavailable)
        assertTrue(source.running)
    }

    @Test
    fun `a camera error reports no camera until the next calibration request`() = runTest {
        val tracker = tracker()
        tracker.setMode(TrackerMode.LEAN_X)
        source.fail()
        assertEquals(UnavailableReason.NO_CAMERA, tracker.state.value.unavailable)
        assertFalse(source.running)

        tracker.calibrate(TrackerMode.LEAN_X)
        assertNull(tracker.state.value.unavailable)
        assertTrue(source.running)
    }

    @Test
    fun `a full calibration is saved for the active profile`() = runTest {
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        assertTrue(source.running)
        assertEquals(TrackerState.CALIBRATING, tracker.state.value.trackerState)
        assertEquals(3, tracker.state.value.calibration!!.stepCount)

        source.emit(fullCalibrationScript())
        runCurrent()
        assertEquals(TrackerState.TRACKING, tracker.state.value.trackerState)
        val saved = store.load(7L)!!
        assertEquals(LEFT_LEAN_DX, saved.leftDx, 1e-6)
        assertEquals(today, saved.calibratedAtEpochMs)
    }

    @Test
    fun `same-day extremes are reused so only the centre is re-taken`() = runTest {
        store.save(7L, HeadCalibration(leftDx = -0.15, rightDx = 0.15, calibratedAtEpochMs = today - 3_600_000L))
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        assertEquals(1, tracker.state.value.calibration!!.stepCount)
        assertEquals(CalibrationStep.CENTRE, tracker.state.value.calibration!!.step)
    }

    @Test
    fun `yesterday's extremes are not reused`() = runTest {
        store.save(7L, HeadCalibration(leftDx = -0.15, rightDx = 0.15, calibratedAtEpochMs = yesterday))
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        assertEquals(3, tracker.state.value.calibration!!.stepCount)
    }

    @Test
    fun `a forced calibration (tap to recalibrate) runs every step`() = runTest {
        store.save(7L, HeadCalibration(leftDx = -0.15, rightDx = 0.15, calibratedAtEpochMs = today))
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X, force = true)
        assertEquals(3, tracker.state.value.calibration!!.stepCount)
    }

    @Test
    fun `switching rider loads that rider's extremes`() = runTest {
        store.save(8L, HeadCalibration(leftDx = -0.15, rightDx = 0.15, calibratedAtEpochMs = today))
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        assertEquals(3, tracker.state.value.calibration!!.stepCount)

        profileId.value = 8L
        runCurrent()
        tracker.calibrate(TrackerMode.LEAN_X)
        assertEquals(1, tracker.state.value.calibration!!.stepCount)
    }

    @Test
    fun `with no active profile calibration is full and nothing is saved`() = runTest {
        profileId.value = null
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        source.emit(fullCalibrationScript())
        runCurrent()
        assertEquals(TrackerState.TRACKING, tracker.state.value.trackerState)
        assertNull(store.load(7L))
    }

    @Test
    fun `no face after two tries makes camera games unavailable and stops the camera`() = runTest {
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        source.emit(FrameScript().hold(2 * centreMs + 200, null))
        assertEquals(UnavailableReason.NO_FACE, tracker.state.value.unavailable)
        assertEquals(TrackerState.OFF, tracker.state.value.trackerState)
        assertFalse(source.running)

        // Changing games doesn't retry by itself...
        tracker.setMode(TrackerMode.OFF)
        tracker.setMode(TrackerMode.LEAN_X)
        assertEquals(UnavailableReason.NO_FACE, tracker.state.value.unavailable)
        assertFalse(source.running)

        // ...but an explicit calibration request does.
        tracker.calibrate(TrackerMode.LEAN_X)
        assertNull(tracker.state.value.unavailable)
        assertTrue(source.running)
    }

    @Test
    fun `lean flows through to the published state`() = runTest {
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        val script = fullCalibrationScript()
        source.emit(script)
        source.emit(script.hold(1_000, SEATED.shifted(dx = LEFT_LEAN_DX)))
        val state = tracker.state.value
        assertEquals(-1.0, state.leanX, 0.0)
        assertEquals(TrackerState.TRACKING, state.trackerState)
    }

    @Test
    fun `turning off mid-calibration cancels it`() = runTest {
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        source.emit(FrameScript().hold(1_000, SEATED))
        tracker.setMode(TrackerMode.OFF)
        assertFalse(source.running)
        assertNull(tracker.state.value.calibration)
        tracker.setMode(TrackerMode.LEAN_X)
        assertEquals(TrackerState.NEEDS_CALIBRATION, tracker.state.value.trackerState)
    }

    @Test
    fun `calibrate with mode off is ignored`() = runTest {
        val tracker = tracker()
        tracker.calibrate(TrackerMode.OFF)
        assertFalse(source.running)
        assertEquals(TrackerState.OFF, tracker.state.value.trackerState)
    }

    @Test
    fun `the camera is restarted cleanly after being off`() = runTest {
        val tracker = tracker()
        tracker.calibrate(TrackerMode.LEAN_X)
        val script = fullCalibrationScript()
        source.emit(script)
        tracker.setMode(TrackerMode.OFF)
        tracker.setMode(TrackerMode.LEAN_X)
        assertEquals(2, source.starts)
        // Frames resume a minute later; no stale face-lost from the gap.
        source.emit(FrameScript(script.now + 60_000).hold(100, SEATED))
        assertEquals(TrackerState.TRACKING, tracker.state.value.trackerState)
    }
}
