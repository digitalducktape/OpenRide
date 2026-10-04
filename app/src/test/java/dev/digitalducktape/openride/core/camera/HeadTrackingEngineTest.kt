package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeadTrackingEngineTest {

    private val config = HeadTrackerConfig()
    private val saved = mutableListOf<HeadCalibration>()
    private val engine = HeadTrackingEngine(config, wallClockMs = { 1_790_000_000_000L }, onFullCalibration = { saved += it })

    private val standingFace = SEATED.shifted(dy = -0.3, sizeRatio = 1.6)

    private fun List<Pair<Frame, HeadTrackerState>>.after(ms: Long) = filter { it.first.timestampMs >= ms }.map { it.second }

    // --- modes and states --------------------------------------------------------------

    @Test
    fun `off by default`() {
        assertEquals(TrackerMode.OFF, engine.state.mode)
        assertEquals(TrackerState.OFF, engine.state.trackerState)
    }

    @Test
    fun `turning a mode on without a centre asks for calibration`() {
        engine.setMode(TrackerMode.LEAN_X)
        val state = engine.onFrame(0L, SEATED.shifted(dx = RIGHT_LEAN_DX))
        assertEquals(TrackerState.NEEDS_CALIBRATION, state.trackerState)
        assertEquals(0.0, state.leanX, 0.0)
    }

    @Test
    fun `calibrating reports progress and then tracks`() {
        engine.setMode(TrackerMode.LEAN_X)
        engine.startCalibration(TrackerMode.LEAN_X, reuse = null)
        val state = engine.onFrame(0L, SEATED)
        assertEquals(TrackerState.CALIBRATING, state.trackerState)
        assertEquals(CalibrationStep.CENTRE, state.calibration!!.step)
        assertEquals(0.0, state.leanX, 0.0)

        engine.calibrateSynthetic(TrackerMode.LEAN_X, FrameScript(33))
        assertEquals(TrackerState.TRACKING, engine.state.trackerState)
        assertNull(engine.state.calibration)
    }

    @Test
    fun `a full calibration is handed out for saving with its extremes and a timestamp`() {
        engine.calibrateSynthetic(TrackerMode.LEAN_X)
        val calibration = saved.single()
        assertEquals(LEFT_LEAN_DX, calibration.leftDx, 1e-6)
        assertEquals(RIGHT_LEAN_DX, calibration.rightDx, 1e-6)
        assertNull(calibration.inRatio)
        assertEquals(1_790_000_000_000L, calibration.calibratedAtEpochMs)
    }

    @Test
    fun `reusing saved extremes only re-takes the centre`() {
        val reuse = HeadCalibration(leftDx = -0.2, rightDx = 0.2, calibratedAtEpochMs = 1L)
        engine.setMode(TrackerMode.LEAN_X)
        engine.startCalibration(TrackerMode.LEAN_X, reuse)
        assertEquals(1, engine.state.calibration!!.stepCount)

        val script = FrameScript().hold(3_100, SEATED.shifted(dx = 0.05)) // rider sits a bit right today
        engine.play(script)
        assertEquals(TrackerState.TRACKING, engine.state.trackerState)
        assertTrue("a centre-only run is not re-saved", saved.isEmpty())

        // A comfortable lean is measured from today's centre with the saved extremes.
        val lean = FrameScript(script.now).hold(1_500, SEATED.shifted(dx = 0.05 + 0.2))
        assertEquals(1.0, engine.play(lean).last().second.leanX, 1e-6)
    }

    @Test
    fun `saved extremes without depth do not cover lean_2d`() {
        val reuse = HeadCalibration(leftDx = -0.2, rightDx = 0.2, calibratedAtEpochMs = 1L)
        engine.setMode(TrackerMode.LEAN_2D)
        engine.startCalibration(TrackerMode.LEAN_2D, reuse)
        assertEquals(5, engine.state.calibration!!.stepCount)
    }

    @Test
    fun `mode off stops output but keeps the session centre`() {
        val script = engine.calibrateSynthetic()
        engine.setMode(TrackerMode.OFF)
        assertEquals(TrackerState.OFF, engine.state.trackerState)
        assertEquals(0.0, engine.state.leanX, 0.0)

        // Next camera game in the same circuit: straight back to tracking.
        engine.setMode(TrackerMode.LEAN_X)
        val state = engine.play(FrameScript(script.now + 60_000).hold(1_000, SEATED.shifted(dx = RIGHT_LEAN_DX))).last().second
        assertEquals(TrackerState.TRACKING, state.trackerState)
        assertEquals(1.0, state.leanX, 1e-6)
    }

    @Test
    fun `resetSession forgets the centre`() {
        engine.calibrateSynthetic()
        engine.resetSession()
        assertEquals(TrackerState.NEEDS_CALIBRATION, engine.state.trackerState)
    }

    @Test
    fun `two failed calibrations report no face`() {
        engine.setMode(TrackerMode.LEAN_X)
        engine.startCalibration(TrackerMode.LEAN_X, reuse = null)
        engine.play(FrameScript().hold(6_200, null))
        assertEquals(UnavailableReason.NO_FACE, engine.state.unavailable)
        assertEquals(TrackerState.NEEDS_CALIBRATION, engine.state.trackerState)

        // Asking again clears it and starts over.
        engine.startCalibration(TrackerMode.LEAN_X, reuse = null)
        assertNull(engine.state.unavailable)
        assertEquals(TrackerState.CALIBRATING, engine.state.trackerState)
    }

    // --- lean -----------------------------------------------------------------------------

    @Test
    fun `a comfortable lean reaches each screen edge`() {
        val script = engine.calibrateSynthetic()
        val left = engine.play(script.hold(1_000, SEATED.shifted(dx = LEFT_LEAN_DX))).last().second
        assertEquals(-1.0, left.leanX, 0.0)
        val right = engine.play(script.hold(1_000, SEATED.shifted(dx = RIGHT_LEAN_DX))).last().second
        assertEquals(1.0, right.leanX, 0.0)
    }

    @Test
    fun `full lock is at 85 percent of the calibrated lean`() {
        val script = engine.calibrateSynthetic()
        val full = engine.play(script.hold(2_000, SEATED.shifted(dx = RIGHT_LEAN_DX * 0.85))).last().second
        assertTrue("85% lean read ${full.leanX}", full.leanX >= 0.99)
        val partial = engine.play(script.hold(2_000, SEATED.shifted(dx = RIGHT_LEAN_DX * 0.85 * 0.65))).last().second
        // 0.65 of full lock, through the soft dead zone.
        assertEquals(deadZone(0.65, config.deadZone, config.deadZoneRamp), partial.leanX, 0.02)
    }

    @Test
    fun `full lock follows the rider's lean within about 200 ms`() {
        val script = engine.calibrateSynthetic()
        engine.play(script.hold(1_000, SEATED))
        val leanStart = script.now
        // The rider takes 250 ms to lean all the way; they pass full lock (85%) at ~212 ms.
        val states = engine.play(script.hold(1_000) { t -> SEATED.shifted(dx = RIGHT_LEAN_DX * (t / 250.0).coerceAtMost(1.0)) })
        val fullAt = states.first { it.second.leanX >= 0.95 }.first.timestampMs
        assertTrue("full lock ${fullAt - leanStart} ms after the lean began", fullAt - leanStart <= 212 + 200)
    }

    @Test
    fun `a fast lean from one side to the other does not stall in the centre`() {
        // Bike run 3: "a bit of hesitation in the centre when going from far left to right".
        val script = engine.calibrateSynthetic()
        engine.play(script.hold(1_000, SEATED.shifted(dx = LEFT_LEAN_DX)))
        script.frames.clear()
        val states = engine.play(
            script.hold(600) { t -> SEATED.shifted(dx = LEFT_LEAN_DX + (RIGHT_LEAN_DX - LEFT_LEAN_DX) * t / 600) }
                .hold(1_000, SEATED.shifted(dx = RIGHT_LEAN_DX)),
        ).map { it.second }
        val stalledMs = states.count { abs(it.leanX) < 0.1 } * 33
        assertTrue("output sat within 0.1 of centre for $stalledMs ms", stalledMs <= 66)
        assertEquals(1.0, states.last().leanX, 1e-6)
    }

    @Test
    fun `sprint bounce produces no visible steering`() {
        // Spike: wobble sd ~0.02 of frame width while sprinting; model it as a 0.025 bounce at
        // pedal frequency plus a slower 0.01 sway.
        val script = engine.calibrateSynthetic()
        val states = engine.play(
            script.hold(20_000) { t -> SEATED.shifted(dx = bounce(t, 0.025, 3.3) + bounce(t, 0.01, 0.4)) },
        ).after(script.now - 18_000)
        val worst = states.maxOf { abs(it.leanX) }
        assertTrue("worst steering during sprint bounce was $worst", worst < 0.1)
    }

    @Test
    fun `a knob glance produces no steering, standing or depth`() {
        val script = engine.calibrateSynthetic(TrackerMode.LEAN_2D)
        val glance = SEATED.shifted(dy = 0.19, sizeRatio = 1.17, pitchDeg = -22.0)
        val states = engine.play(script.hold(5_000, glance)).map { it.second }
        assertTrue(states.all { abs(it.leanX) < 0.05 })
        assertTrue(states.none { it.standing })
        assertTrue("depth during glance: ${states.maxOf { abs(it.leanDepth) }}", states.all { abs(it.leanDepth) < 0.05 })
    }

    @Test
    fun `a lean that falls back to the default is used and reported, but not saved as the rider's`() {
        engine.setMode(TrackerMode.LEAN_X)
        engine.startCalibration(TrackerMode.LEAN_X, reuse = null)
        val centreMs = config.centreSettleMs + config.centreCaptureMs
        val extremeMs = config.extremeSettleMs + config.extremeCaptureMs
        val script = FrameScript()
            .hold(centreMs, SEATED)
            .hold(3 * extremeMs + config.fallbackNoticeMs + 200, SEATED.shifted(dx = -0.02)) // too small x3
            .hold(extremeMs + 100, SEATED.shifted(dx = RIGHT_LEAN_DX))
            .hold(200, SEATED)
        val states = engine.play(script).map { it.second }

        assertTrue(states.any { it.calibration?.retryReason == CalibrationRetryReason.USED_DEFAULT })
        val last = states.last()
        assertEquals(TrackerState.TRACKING, last.trackerState)
        assertEquals(setOf(CalibrationStep.LEFT), last.calibrationDefaults)
        assertEquals(config.defaultLeftDx, engine.calibration!!.leftDx, 0.0)
        assertTrue("defaulted extremes must not be saved: $saved", saved.isEmpty())
    }

    // --- standing and posture baselines ---------------------------------------------------

    @Test
    fun `standing is reported and steering re-baselines after two seconds of standing`() {
        val script = engine.calibrateSynthetic()
        // Standing shifts the face 0.09 to the right with no deliberate lean.
        val standing = standingFace.shifted(dx = 0.09)
        val standStart = script.now
        val states = engine.play(script.hold(4_000, standing))

        val enteredAt = states.first { it.second.standing }.first.timestampMs
        assertTrue(enteredAt - standStart in 480L..560L)
        // Before the standing baseline takes over the offset reads as some steering...
        assertTrue(states.first { it.first.timestampMs >= enteredAt + 1_500 }.second.leanX > 0.2)
        // ...after 2 s of standing it's measured from the standing baseline, so centre again.
        assertEquals(0.0, states.last().second.leanX, 1e-6)

        // A lean while standing is measured from the standing baseline.
        val lean = engine.play(script.hold(1_000, standing.shifted(dx = RIGHT_LEAN_DX))).last().second
        assertEquals(1.0, lean.leanX, 1e-6)
    }

    @Test
    fun `sitting back down returns to the seated baseline`() {
        val script = engine.calibrateSynthetic()
        engine.play(script.hold(4_000, standingFace.shifted(dx = 0.09)))
        val sitStart = script.now
        val states = engine.play(script.hold(3_000, SEATED))
        val exitedAt = states.first { !it.second.standing }.first.timestampMs
        assertTrue(exitedAt - sitStart in 1_480L..1_560L)
        assertEquals(0.0, states.last().second.leanX, 1e-6)
    }

    @Test
    fun `standing is reported in every camera mode`() {
        for (mode in listOf(TrackerMode.LEAN_X, TrackerMode.LEAN_STAND, TrackerMode.LEAN_2D)) {
            val engine = HeadTrackingEngine(config)
            val script = engine.calibrateSynthetic(mode)
            assertTrue(mode.toString(), engine.play(script.hold(1_000, standingFace)).last().second.standing)
        }
    }

    // --- face lost ------------------------------------------------------------------------

    @Test
    fun `a lost face holds, eases to centre, then reports face lost`() {
        val script = engine.calibrateSynthetic()
        engine.play(script.hold(1_000, SEATED.shifted(dx = RIGHT_LEAN_DX)))
        val lastFace = script.now - 33
        val states = engine.play(script.hold(4_000, null))
        fun at(ms: Long) = states.last { it.first.timestampMs <= lastFace + ms }.second

        assertEquals(1.0, at(400).leanX, 0.0) // held
        assertEquals(TrackerState.TRACKING, at(400).trackerState)
        val easing = at(750).leanX
        assertTrue("easing value $easing", easing > 0.2 && easing < 0.8)
        assertEquals(0.0, at(1_050).leanX, 0.0)
        assertEquals(TrackerState.TRACKING, at(2_900).trackerState)
        assertEquals(TrackerState.FACE_LOST, at(3_050).trackerState)
    }

    @Test
    fun `a single dropped frame changes nothing`() {
        val script = engine.calibrateSynthetic()
        engine.play(script.hold(1_000, SEATED.shifted(dx = RIGHT_LEAN_DX)))
        val states = engine.play(script.hold(33, null).hold(500, SEATED.shifted(dx = RIGHT_LEAN_DX))).map { it.second }
        assertTrue(states.all { it.leanX == 1.0 })
    }

    @Test
    fun `tracking resumes when the face comes back`() {
        val script = engine.calibrateSynthetic()
        engine.play(script.hold(4_000, null))
        assertEquals(TrackerState.FACE_LOST, engine.state.trackerState)
        val back = engine.play(script.hold(500, SEATED.shifted(dx = LEFT_LEAN_DX))).last().second
        assertEquals(TrackerState.TRACKING, back.trackerState)
        assertEquals(-1.0, back.leanX, 1e-6)
    }

    @Test
    fun `standing is dropped once the face is lost`() {
        val script = engine.calibrateSynthetic()
        engine.play(script.hold(2_000, standingFace))
        assertTrue(engine.state.standing)
        val states = engine.play(script.hold(4_000, null))
        assertTrue("held while briefly lost", states.first().second.standing)
        assertFalse(states.last().second.standing)
    }

    // --- depth (experimental) -------------------------------------------------------------

    @Test
    fun `depth is zero unless the mode is lean_2d`() {
        val script = engine.calibrateSynthetic(TrackerMode.LEAN_2D)
        engine.setMode(TrackerMode.LEAN_X)
        val state = engine.play(script.hold(1_000, SEATED.shifted(sizeRatio = 1.2))).last().second
        assertEquals(0.0, state.leanDepth, 0.0)
    }

    @Test
    fun `leaning in and sitting back as calibrated reach full depth`() {
        val script = engine.calibrateSynthetic(TrackerMode.LEAN_2D, inRatio = 1.2, backRatio = 0.85)
        val leanIn = engine.play(script.hold(1_000, SEATED.shifted(sizeRatio = 1.2))).last().second
        assertEquals(1.0, leanIn.leanDepth, 0.0)
        val back = engine.play(script.hold(1_000, SEATED.shifted(sizeRatio = 0.85))).last().second
        assertEquals(-1.0, back.leanDepth, 0.0)
        val partIn = engine.play(script.hold(2_000, SEATED.shifted(sizeRatio = 1 + 0.2 * 0.85 * 0.65))).last().second
        assertEquals(deadZone(0.65, config.deadZone, config.deadZoneRamp), partIn.leanDepth, 0.02)
        assertFalse(back.standing)
    }

    @Test
    fun `depth is pitch-gated so looking down does not read as leaning in`() {
        val script = engine.calibrateSynthetic(TrackerMode.LEAN_2D, inRatio = 1.2)
        val lookingDown = SEATED.shifted(sizeRatio = 1.2, pitchDeg = -20.0)
        assertEquals(0.0, engine.play(script.hold(2_000, lookingDown)).last().second.leanDepth, 1e-6)
    }

    @Test
    fun `depth reads zero while standing`() {
        val script = engine.calibrateSynthetic(TrackerMode.LEAN_2D)
        val states = engine.play(script.hold(3_000, standingFace))
        assertTrue(states.last().second.standing)
        assertEquals(0.0, states.last().second.leanDepth, 1e-6)
    }

    @Test
    fun `lean_2d without depth extremes still steers left and right`() {
        val reuse = HeadCalibration(leftDx = -0.2, rightDx = 0.2, calibratedAtEpochMs = 1L)
        engine.setMode(TrackerMode.LEAN_X)
        engine.startCalibration(TrackerMode.LEAN_X, reuse)
        val script = FrameScript().hold(3_100, SEATED)
        engine.play(script)
        engine.setMode(TrackerMode.LEAN_2D)
        val state = engine.play(script.hold(1_000, SEATED.shifted(dx = 0.2, sizeRatio = 1.2))).last().second
        assertEquals(1.0, state.leanX, 0.0)
        assertEquals(0.0, state.leanDepth, 0.0)
        assertNotNull(engine.calibration)
    }
}
