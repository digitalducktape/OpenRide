package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.sensor.ConnectionState
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

private class RecordingSession(override val segmentTimeLeftSec: Double = 33.0) : GameSession {
    val calls = mutableListOf<String>()

    override fun onGameReady() { calls += "ready" }
    override fun onSegmentFinished(resultJson: String) { calls += "segment_finished:$resultJson" }
    override fun onRequestCalibration(mode: String) { calls += "request_calibration:$mode" }
    override fun onSetTrackerMode(mode: String) { calls += "set_tracker_mode:$mode" }
    override fun onRequestPause() { calls += "request_pause" }
    override fun onRequestResume() { calls += "request_resume" }
    override fun onRequestEnd() { calls += "request_end" }
    override fun onRequestExit() { calls += "request_exit" }
    override fun onStartPlan(requestJson: String) { calls += "start_plan:$requestJson" }
    override fun onUpdateSetting(key: String, valueJson: String) { calls += "update_setting:$key=$valueJson" }
    override fun onHubCalibrate(mode: String, full: Boolean) { calls += "hub_calibrate:$mode:$full" }
    override fun onCancelCalibration() { calls += "cancel_calibration" }
    override fun onRequestCameraPermission() { calls += "request_camera_permission" }
    override fun onExitHub(next: String) { calls += "exit_hub:$next" }
    override fun onHubActivity() { calls += "hub_activity" }
}

private class RecordingEmitter : GameSignals {
    val events = mutableListOf<String>()

    override fun sessionStarted(planJson: String) { events += "session_started:$planJson" }
    override fun segmentStarted(segmentJson: String) { events += "segment_started:$segmentJson" }
    override fun segmentEnding() { events += "segment_ending" }
    override fun sessionPaused() { events += "session_paused" }
    override fun sessionResumed() { events += "session_resumed" }
    override fun calibrationProgress(progress: CalibrationProgressSignal) {
        events += "calibration_progress:${progress.step}:${progress.fraction}:${progress.stepIndex}/${progress.stepCount}" +
            ":${progress.attempt}:${progress.retryReason}"
    }
    override fun sessionFinished(summaryJson: String) { events += "session_finished:$summaryJson" }
    override fun hubState(stateJson: String) { events += "hub_state:$stateJson" }
    override fun planRejected(reasonJson: String) { events += "plan_rejected:$reasonJson" }
    override fun visitEnded(resultJson: String) { events += "visit_ended:$resultJson" }
    override fun nowPlaying(nowPlayingJson: String) { events += "now_playing:$nowPlayingJson" }
}

class GameBridgeTest {
    private val bike = FakeBikeDataSource()
    private val heartRate = MutableStateFlow<Int?>(null)
    private val sensorsOffline = MutableStateFlow<Boolean?>(false)
    private val bridge = GameBridge(bike, sensorsOffline, heartRate)

    @Test
    fun `the input frame carries live bike metrics and the session's time left`() {
        bike.setMetrics(cadenceRpm = 85, resistancePercent = 35, powerWatts = 160, speedMph = 16.0)
        heartRate.value = 128
        bridge.attach(RecordingSession(segmentTimeLeftSec = 33.0))

        val frame = bridge.inputFrame()

        assertArrayEquals(
            doubleArrayOf(1.0, 85.0, 160.0, 35.0, 16.0, 128.0, 0.0, 0.0, 0.0, 0.0, 33.0, 1.0, 0.0, 0.0, 0.0, 0.0),
            frame,
            0.0,
        )
    }

    @Test
    fun `the input frame carries the controllers' steering and item presses`() {
        val withController = GameBridge(bike, sensorsOffline, heartRate, controllerReading = { ControllerReading(steer = -0.5, itemPresses = 2) })

        val frame = withController.inputFrame()

        assertEquals(-0.5, frame[InputFrame.CONTROLLER_STEER], 0.0)
        assertEquals(1.0, frame[InputFrame.CONTROLLER_STEERING], 0.0)
        assertEquals(2.0, frame[InputFrame.CONTROLLER_ITEM_PRESSES], 0.0)
    }

    @Test
    fun `the rider's music reaches the frame as it changes`() {
        var riderMusic = false
        val withMusic = GameBridge(bike, sensorsOffline, heartRate, riderMusic = { riderMusic })
        assertEquals(0.0, withMusic.inputFrame()[InputFrame.RIDER_MUSIC], 0.0)
        riderMusic = true
        assertEquals(1.0, withMusic.inputFrame()[InputFrame.RIDER_MUSIC], 0.0)
    }

    @Test
    fun `sensors_ok follows the app's one offline rule, not the raw connection`() {
        // A blip: the shared rule hasn't called it yet (issue #56), so the game carries on.
        bike.setConnectionState(ConnectionState.Disconnected)
        assertEquals(1.0, bridge.inputFrame()[InputFrame.SENSORS_OK], 0.0)

        sensorsOffline.value = true
        assertEquals(0.0, bridge.inputFrame()[InputFrame.SENSORS_OK], 0.0)

        // Not known yet (the app's first 10 s) counts as ok, as on the top bar.
        sensorsOffline.value = null
        assertEquals(1.0, bridge.inputFrame()[InputFrame.SENSORS_OK], 0.0)
    }

    @Test
    fun `with no session attached, time left is -1 and calls are ignored`() {
        assertEquals(-1.0, bridge.inputFrame()[InputFrame.SEGMENT_TIME_LEFT], 0.0)

        bridge.segmentFinished("{}")
        bridge.requestPause()
        bridge.requestExit()
    }

    @Test
    fun `the first poll after attach tells the session the game is ready, once`() {
        val session = RecordingSession()
        bridge.attach(session)

        bridge.inputFrame()
        bridge.inputFrame()
        bridge.inputFrame()

        assertEquals(listOf("ready"), session.calls)
    }

    @Test
    fun `now playing reaches Godot, and is sent again when it's next ready`() {
        val emitter = RecordingEmitter()
        bridge.publishNowPlaying("{\"title\":\"Before\"}")  // the engine isn't running yet: dropped, but kept
        bridge.emitter = emitter
        bridge.attach(RecordingSession())

        bridge.inputFrame()
        bridge.publishNowPlaying("{}")

        assertEquals(listOf("now_playing:{\"title\":\"Before\"}", "now_playing:{}"), emitter.events)
    }

    @Test
    fun `the music card's buttons reach the app`() {
        val actions = mutableListOf<String>()
        GameBridge(bike, sensorsOffline, heartRate, musicControl = { actions += it }).musicControl("next")
        assertEquals(listOf("next"), actions)
    }

    @Test
    fun `re-entering games readies the new session`() {
        val first = RecordingSession()
        bridge.attach(first)
        bridge.inputFrame()
        bridge.detach(first)

        val second = RecordingSession()
        bridge.attach(second)
        bridge.inputFrame()

        assertEquals(listOf("ready"), first.calls)
        assertEquals(listOf("ready"), second.calls)
    }

    @Test
    fun `detaching a stale session keeps the current one`() {
        val old = RecordingSession()
        val current = RecordingSession()
        bridge.attach(old)
        bridge.attach(current)

        bridge.detach(old)
        bridge.requestPause()

        assertEquals(listOf("request_pause"), current.calls)
        assertTrue(old.calls.isEmpty())
    }

    @Test
    fun `Godot calls are routed to the attached session`() {
        val session = RecordingSession()
        bridge.attach(session)

        bridge.segmentFinished("""{"game_id":"x"}""")
        bridge.requestCalibration("lean_x")
        bridge.setTrackerMode("lean_2d")
        bridge.requestPause()
        bridge.requestResume()
        bridge.requestEnd()
        bridge.requestExit()

        assertEquals(
            listOf(
                """segment_finished:{"game_id":"x"}""", "request_calibration:lean_x",
                "set_tracker_mode:lean_2d", "request_pause", "request_resume", "request_end",
                "request_exit",
            ),
            session.calls,
        )
    }

    @Test
    fun `signals reach Godot once its plugin is registered, and are dropped before`() {
        bridge.sessionPaused()

        val emitter = RecordingEmitter()
        bridge.emitter = emitter
        bridge.sessionStarted("{}")
        bridge.segmentStarted("{}")
        bridge.segmentEnding()
        bridge.sessionPaused()
        bridge.sessionResumed()
        bridge.calibrationProgress(CalibrationProgressSignal("centre", 0.5, 0, 3, 2, "unstable"))
        bridge.sessionFinished("{}")

        assertEquals(
            listOf(
                "session_started:{}", "segment_started:{}", "segment_ending", "session_paused",
                "session_resumed", "calibration_progress:centre:0.5:0/3:2:unstable", "session_finished:{}",
            ),
            emitter.events,
        )
    }

    @Test
    fun `the hub's calls are routed to the attached session`() {
        val session = RecordingSession()
        bridge.attach(session)

        bridge.startPlan("""{"kind":"circuit"}""")
        bridge.updateSetting("music", "\"off\"")
        bridge.hubCalibrate("lean_x", true)
        bridge.cancelCalibration()
        bridge.requestCameraPermission()
        bridge.hubActivity()
        bridge.exitHub("edit_profile")

        assertEquals(
            listOf(
                """start_plan:{"kind":"circuit"}""", "update_setting:music=\"off\"", "hub_calibrate:lean_x:true",
                "cancel_calibration", "request_camera_permission", "hub_activity", "exit_hub:edit_profile",
            ),
            session.calls,
        )
    }

    @Test
    fun `the hub's signals reach Godot`() {
        val emitter = RecordingEmitter()
        bridge.emitter = emitter

        bridge.hubState("{}")
        bridge.planRejected("""{"reason":"busy"}""")
        bridge.visitEnded("{}")

        assertEquals(listOf("hub_state:{}", """plan_rejected:{"reason":"busy"}""", "visit_ended:{}"), emitter.events)
    }

    @Test
    fun `tracker readings feed the head-tracker fields`() {
        val tracked = GameBridge(bike, sensorsOffline, heartRate, trackerReading = {
            TrackerReading(leanX = 0.3, leanDepth = -0.2, standing = true, state = TrackerState.TRACKING)
        })

        val frame = tracked.inputFrame()

        assertEquals(0.3, frame[InputFrame.LEAN_X], 0.0)
        assertEquals(-0.2, frame[InputFrame.LEAN_DEPTH], 0.0)
        assertEquals(1.0, frame[InputFrame.STANDING], 0.0)
        assertEquals(3.0, frame[InputFrame.TRACKER_STATE], 0.0)
    }
}
