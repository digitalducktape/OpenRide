package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test

/**
 * Replays a real ride recorded on the Gen 2 bike (the camera spike's scripted protocol:
 * centre, leans, sprint, knob glance, stand/sit — see the fixture's header) through the
 * production engine, calibrated from the same ride the way a rider would be prompted.
 *
 * The rider followed spoken-style prompts, so each labelled segment starts with ~0.5-2 s of
 * reaction and movement; assertions allow for that rather than assume instant compliance.
 */
class HeadTrackerFixtureTest {

    private class Segment(val step: String, val rows: List<HeadFixtureCsv.Row>) {
        val startMs get() = rows.first().timestampMs
    }

    private class Replayed(
        val step: String,
        val segmentStartMs: Long,
        val timestampMs: Long,
        val face: FaceObservation?,
        val state: HeadTrackerState,
    ) {
        val intoSegmentMs get() = timestampMs - segmentStartMs
    }

    companion object {
        private const val FIXTURE = "headtracker/spike-protocol-2026-09-27.csv"
        private lateinit var rows: List<HeadFixtureCsv.Row>
        private lateinit var segments: List<Segment>

        @BeforeClass
        @JvmStatic
        fun load() {
            val stream = HeadTrackerFixtureTest::class.java.classLoader!!.getResourceAsStream(FIXTURE)
                ?: error("missing test resource $FIXTURE")
            rows = stream.bufferedReader().useLines { HeadFixtureCsv.parse(it) }
            segments = buildList {
                var current = mutableListOf<HeadFixtureCsv.Row>()
                for (row in rows) {
                    if (current.isNotEmpty() && current.last().step != row.step) {
                        add(Segment(current.first().step, current))
                        current = mutableListOf()
                    }
                    current += row
                }
                add(Segment(current.first().step, current))
            }
        }
    }

    private fun segments(step: String) = segments.filter { it.step == step }

    /**
     * Calibrates [engine] the way a session would: the first 3 s of the first easy-centre
     * segment, then 2.5 s from the start of the first left and right lean prompts, played back
     * to back on one clock.
     */
    private fun calibrate(engine: HeadTrackingEngine, mode: TrackerMode = TrackerMode.LEAN_X): Long {
        engine.setMode(mode)
        engine.startCalibration(mode, reuse = null)
        val config = engine.config
        val windows = listOf(
            segments("easy_centre").first() to config.centreSettleMs + config.centreCaptureMs,
            segments("lean_left").first() to config.extremeSettleMs + config.extremeCaptureMs,
            segments("lean_right").first() to config.extremeSettleMs + config.extremeCaptureMs,
            segments("return_centre")[1] to 200L,
        )
        var clock = 0L
        for ((segment, duration) in windows) {
            for (row in segment.rows.filter { it.timestampMs - segment.startMs < duration }) {
                engine.onFrame(clock + row.timestampMs - segment.startMs, row.face)
            }
            clock += duration
        }
        check(engine.state.trackerState == TrackerState.TRACKING) { "fixture calibration failed: ${engine.state}" }
        return clock
    }

    /** Calibrates, then replays the whole recording after it. */
    private fun replay(mode: TrackerMode = TrackerMode.LEAN_X): Pair<HeadTrackingEngine, List<Replayed>> {
        val engine = HeadTrackingEngine()
        val offset = calibrate(engine, mode) + 1_000
        val startBySegment = segments.flatMap { s -> s.rows.map { it to s.startMs } }.toMap()
        val replayed = rows.map { row ->
            val state = engine.onFrame(offset + row.timestampMs, row.face)
            Replayed(row.step, offset + startBySegment.getValue(row), offset + row.timestampMs, row.face, state)
        }
        return engine to replayed
    }

    @Test
    fun `calibration from the recording measures the rider's real leans`() {
        val engine = HeadTrackingEngine()
        calibrate(engine)
        val calibration = engine.calibration!!
        // Spike analysis: left -0.15..-0.16, right +0.14..+0.16 of frame width.
        assertTrue("left ${calibration.leftDx}", calibration.leftDx in -0.19..-0.12)
        assertTrue("right ${calibration.rightDx}", calibration.rightDx in 0.12..0.19)
    }

    @Test
    fun `recorded leans reach the screen edge`() {
        val (_, replayed) = replay()
        val shares = mutableListOf<Double>()
        for (step in listOf("lean_left", "lean_right", "sprint_lean_left", "sprint_lean_right")) {
            val sign = if (step.endsWith("left")) -1.0 else 1.0
            replayed.filter { it.step == step }.groupBy { it.segmentStartMs }.values.forEach { segment ->
                // The rider has arrived by the second half of the 5 s prompt.
                val held = segment.filter { it.intoSegmentMs >= 2_500 }.map { it.state.leanX * sign }
                val atEdge = held.count { it >= 0.99 }.toDouble() / held.size
                println("$step @${segment.first().segmentStartMs}: ${"%.0f".format(atEdge * 100)}% of held frames at full lock")
                shares += atEdge
            }
        }
        // The rider's held lean varied ~0.12-0.22 of frame width between prompts; the smallest
        // held lean still spends most of its time at the edge.
        assertTrue("mean share at full lock ${shares.average()}", shares.average() >= 0.9)
        assertTrue("worst share at full lock ${shares.min()}", shares.min() >= 0.6)
    }

    @Test
    fun `seated easy riding at centre does not steer`() {
        val (_, replayed) = replay()
        val frames = replayed.filter { it.step == "easy_centre" }
        val visible = frames.count { abs(it.state.leanX) > 0.1 }.toDouble() / frames.size
        val worst = frames.maxOf { abs(it.state.leanX) }
        println("easy_centre: ${"%.1f".format(visible * 100)}% of frames steer > 0.1, worst ${"%.2f".format(worst)}")
        assertTrue("easy centre visible steering ${visible * 100}%", visible < 0.03)
        assertTrue("easy centre worst $worst", worst < 0.25)
    }

    @Test
    fun `sprint bounce alone produces no visible steering`() {
        // The sprint segment opens with a ~2 s real posture shift as the rider winds up (the raw
        // face moves 0.06-0.08 of frame width, as much as half a lean — no filter can call that
        // bounce) and ends anticipating the next prompt. Report the whole segment; assert on the
        // steady middle 12 s, where only pedal bounce moves the head.
        val (_, replayed) = replay()
        val whole = replayed.filter { it.step == "sprint_centre" }
        println(
            "sprint_centre (whole): ${"%.1f".format(whole.count { abs(it.state.leanX) > 0.1 } * 100.0 / whole.size)}% " +
                "> 0.1, worst ${"%.2f".format(whole.maxOf { abs(it.state.leanX) })}",
        )
        val steady = whole.filter { it.intoSegmentMs in 4_000L..16_000L }
        val visible = steady.count { abs(it.state.leanX) > 0.1 }.toDouble() / steady.size
        val worst = steady.maxOf { abs(it.state.leanX) }
        println("sprint_centre (steady 4-16 s): ${"%.1f".format(visible * 100)}% > 0.1, worst ${"%.2f".format(worst)}")
        assertTrue("steady sprint visible steering ${visible * 100}%", visible < 0.03)
        assertTrue("steady sprint worst $worst", worst < 0.25)
    }

    @Test
    fun `depth evidence - knob glance and standing against an assumed lean-in`() {
        // The recording has no deliberate lean-in/sit-back, so depth extremes are assumed
        // (in = 1.2x, back = 0.85x face size). This measures how much the knob glance and
        // standing leak into depth through the pitch and standing gates.
        val engine = HeadTrackingEngine()
        val clock = calibrate(engine, TrackerMode.LEAN_X)
        val extremes = engine.calibration!!.copy(inRatio = 1.2, backRatio = 0.85)
        engine.startCalibration(TrackerMode.LEAN_2D, reuse = extremes)
        val centre = segments("easy_centre").first()
        var t = clock + 1_000
        for (row in centre.rows.filter { it.timestampMs - centre.startMs < 3_200 }) {
            engine.onFrame(t + row.timestampMs - centre.startMs, row.face)
        }
        t += 5_000
        check(engine.state.trackerState == TrackerState.TRACKING)
        val bySegment = rows.map { row -> row.step to engine.onFrame(t + row.timestampMs, row.face) }

        fun report(step: String): Pair<Double, Double> {
            val depths = bySegment.filter { it.first == step }.map { it.second.leanDepth }
            val visible = depths.count { abs(it) > 0.1 }.toDouble() / depths.size
            println("depth during $step: ${"%.0f".format(visible * 100)}% of frames > 0.1, worst ${"%.2f".format(depths.maxOf { abs(it) })}")
            return visible to depths.maxOf { abs(it) }
        }
        val (knobVisible, _) = report("knob_glance")
        report("stand")
        report("sit")
        report("easy_centre")
        report("sprint_centre")
        assertTrue("knob glance leaked into depth on ${knobVisible * 100}% of frames", knobVisible < 0.1)
    }

    @Test
    fun `the knob glance does not steer or stand`() {
        val (_, replayed) = replay(TrackerMode.LEAN_X)
        val glance = replayed.filter { it.step == "knob_glance" }
        val worst = glance.maxOf { abs(it.state.leanX) }
        println("knob glance: worst steering ${"%.2f".format(worst)}")
        assertTrue("knob glance steered $worst", worst < 0.1)
        assertTrue(glance.none { it.state.standing })
    }

    @Test
    fun `nothing seated reads as standing`() {
        val (_, replayed) = replay()
        val seated = setOf(
            "setup", "easy_centre", "lean_left", "lean_right", "return_centre", "sprint_centre",
            "sprint_lean_left", "sprint_lean_right", "sprint_return_centre", "knob_glance",
        )
        val falseStanding = replayed.filter { it.step in seated && it.state.standing }
        assertEquals(emptyList<Long>(), falseStanding.map { it.timestampMs })
    }

    @Test
    fun `standing is entered within 1 s of rising and left within 1_5 s of sitting`() {
        val (engine, replayed) = replay()
        val centre = engine.sessionCentre!!
        val config = engine.config
        fun postureStanding(face: FaceObservation?) = face != null &&
            face.size > centre.size * config.standSizeRatio &&
            face.pitchDeg - centre.pitchDeg > config.standMinPitchFromCentreDeg &&
            face.cy - centre.cy <= config.standMaxDrop

        replayed.filter { it.step == "stand" }.groupBy { it.segmentStartMs }.values.forEach { segment ->
            // When the rider actually rose: the first frame whose face says "standing".
            val rose = segment.first { postureStanding(it.face) }
            val detected = segment.first { it.state.standing }
            val share = segment.count { it.state.standing }.toDouble() / segment.size
            println(
                "stand @${rose.segmentStartMs}: rose ${rose.intoSegmentMs} ms after the prompt, detected " +
                    "${detected.timestampMs - rose.timestampMs} ms later; standing ${"%.0f".format(share * 100)}% of the segment",
            )
            assertTrue(detected.timestampMs - rose.timestampMs <= 1_000)
        }
        replayed.filter { it.step == "sit" }.groupBy { it.segmentStartMs }.values.forEach { segment ->
            // When the rider actually sat: after the last frame whose face still says "standing".
            val lastUp = segment.lastOrNull { postureStanding(it.face) }
            val lastDetected = segment.lastOrNull { it.state.standing }
            println("sit @${segment.first().segmentStartMs}: face last looked standing at ${lastUp?.intoSegmentMs} ms, standing cleared after ${lastDetected?.intoSegmentMs} ms")
            if (lastDetected != null) {
                val sat = lastUp ?: segment.first()
                assertTrue(lastDetected.timestampMs - sat.timestampMs <= 1_500)
            }
        }
    }
}
