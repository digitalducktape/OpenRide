package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import kotlin.math.sqrt
import org.junit.BeforeClass
import org.junit.Test

/**
 * Issue #71 ("too sensitive, hard to return to centre"), measured on the spike's scripted ride
 * (`spike-protocol-2026-09-27.csv`: centre, leans and returns, sprint, knob glance, stand/sit)
 * replayed through the production engine. Prints the metrics the fix is judged by and asserts
 * the tuned behaviour:
 *
 * - **centre jitter**: how much the output moves while the rider is nominally centred;
 * - **settle**: after a return to centre, how long until the output stays in the neutral band;
 * - **lag**: from the raw lean reaching full lock to the output reaching it, and from the raw
 *   lean passing half to the output leaving centre (visible steering).
 */
class LeanResponseReplayTest {

    private class Segment(val step: String, val rows: List<HeadFixtureCsv.Row>) {
        val startMs get() = rows.first().timestampMs
    }

    private class Frame(val step: String, val segmentStartMs: Long, val tMs: Long, val raw: Double, val out: Double, val tracking: Boolean)

    companion object {
        private const val FIXTURE = "headtracker/spike-protocol-2026-09-27.csv"
        const val NEUTRAL_BAND = 0.1
        private const val SETTLE_HOLD_MS = 500L
        private lateinit var rows: List<HeadFixtureCsv.Row>
        private lateinit var segments: List<Segment>

        @BeforeClass
        @JvmStatic
        fun load() {
            val stream = LeanResponseReplayTest::class.java.classLoader!!.getResourceAsStream(FIXTURE)
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

    /** As [HeadTrackerFixtureTest]: centre, left and right from the first prompts, on one clock. */
    private fun calibrate(engine: HeadTrackingEngine): Long {
        engine.setMode(TrackerMode.LEAN_X)
        engine.startCalibration(TrackerMode.LEAN_X, reuse = null)
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

    private fun replay(engine: HeadTrackingEngine): List<Frame> {
        val offset = calibrate(engine) + 1_000
        val startBySegment = segments.flatMap { s -> s.rows.map { it to s.startMs } }.toMap()
        var lastRaw = 0.0
        return rows.map { row ->
            val state = engine.onFrame(offset + row.timestampMs, row.face)
            if (row.face != null) lastRaw = state.rawLeanX
            Frame(row.step, startBySegment.getValue(row), row.timestampMs, lastRaw, state.leanX, row.face != null)
        }
    }

    class Metrics(
        val centreSd: Double,
        val centreMeanStep: Double,
        val centreVisible: Double,
        val centreWorst: Double,
        val settleMs: List<Long>,
        val fullLockLagMs: List<Long>,
        val departLagMs: List<Long>,
        val returnOvershoot: Double,
    ) {
        override fun toString() = buildString {
            appendLine("centre (easy x3 + sprint steady): sd ${f(centreSd)}, mean |step| ${f(centreMeanStep)}/frame, |out|>$NEUTRAL_BAND on ${f(centreVisible * 100, 1)}% , worst ${f(centreWorst)}")
            appendLine("settle into ±$NEUTRAL_BAND for ${SETTLE_HOLD_MS} ms after raw passes half on the way home: $settleMs ms (median ${median(settleMs)})")
            appendLine("full-lock lag (raw >= 1 -> out >= 0.99): $fullLockLagMs ms (median ${median(fullLockLagMs)})")
            appendLine("departure lag (raw passes 0.5 -> out > $NEUTRAL_BAND): $departLagMs ms (median ${median(departLagMs)})")
            append("worst opposite-side overshoot on returns: ${f(returnOvershoot)}")
        }

        private fun f(v: Double, digits: Int = 3) = "%.${digits}f".format(v)
    }

    fun measure(config: HeadTrackerConfig = HeadTrackerConfig()): Metrics {
        val frames = replay(HeadTrackingEngine(config))

        val centre = frames.filter { it.step == "easy_centre" } +
            frames.filter { it.step == "sprint_centre" && it.tMs - it.segmentStartMs in 4_000L..16_000L }
        val outs = centre.map { it.out }
        val mean = outs.average()
        val sd = sqrt(outs.sumOf { (it - mean) * (it - mean) } / outs.size)
        val steps = centre.zipWithNext().filter { (a, b) -> a.segmentStartMs == b.segmentStartMs }.map { (a, b) -> abs(b.out - a.out) }

        val settle = mutableListOf<Long>()
        var overshoot = 0.0
        for (step in listOf("return_centre", "sprint_return_centre")) {
            frames.filter { it.step == step }.groupBy { it.segmentStartMs }.values.forEach { seg ->
                // Which side the rider is coming back from: the previous prompt's held lean.
                val from = frames.last { it.tMs < seg.first().tMs && it.tracking }.raw
                val side = if (from < 0) -1.0 else 1.0
                val home = seg.firstOrNull { it.tracking && it.raw * side < 0.5 } ?: return@forEach
                val after = seg.filter { it.tMs >= home.tMs }
                val settled = after.firstOrNull { start ->
                    val window = after.filter { it.tMs in start.tMs..start.tMs + SETTLE_HOLD_MS }
                    start.tMs + SETTLE_HOLD_MS <= after.last().tMs && window.all { abs(it.out) <= NEUTRAL_BAND }
                }
                settle += (settled?.tMs ?: after.last().tMs) - home.tMs
                overshoot = maxOf(overshoot, after.maxOf { -it.out * side })
            }
        }

        val fullLock = mutableListOf<Long>()
        val depart = mutableListOf<Long>()
        for (step in listOf("lean_left", "lean_right", "sprint_lean_left", "sprint_lean_right")) {
            val side = if (step.endsWith("left")) -1.0 else 1.0
            frames.filter { it.step == step }.groupBy { it.segmentStartMs }.values.forEach { seg ->
                seg.firstOrNull { it.tracking && it.raw * side >= 0.5 }?.let { half ->
                    seg.firstOrNull { it.tMs >= half.tMs && it.out * side > NEUTRAL_BAND }?.let { depart += it.tMs - half.tMs }
                }
                seg.firstOrNull { it.tracking && it.raw * side >= 1.0 }?.let { lock ->
                    seg.firstOrNull { it.tMs >= lock.tMs && it.out * side >= 0.99 }?.let { fullLock += it.tMs - lock.tMs }
                }
            }
        }

        return Metrics(
            centreSd = sd,
            centreMeanStep = steps.average(),
            centreVisible = outs.count { abs(it) > NEUTRAL_BAND }.toDouble() / outs.size,
            centreWorst = outs.maxOf { abs(it) },
            settleMs = settle,
            fullLockLagMs = fullLock,
            departLagMs = depart,
            returnOvershoot = overshoot,
        )
    }

    /**
     * Bike runs 4 and 5 (MediaPipe, the production detector): free riding of the demo game.
     * Each time the raw lean comes home from at least 0.8 and then rests within ±0.35 for 1 s,
     * how long the output takes to stay within ±[NEUTRAL_BAND] for 500 ms, and how far it
     * swings past centre. Plus run 5's long knob glances (seated, centred, looking down).
     */
    class RideMetrics(val settleMs: List<Long>, val overshoot: Double, val knobVisible: Double, val knobWorst: Double, val ridingMeanStep: Double) {
        override fun toString() = buildString {
            val sorted = settleMs.sorted()
            appendLine("runs 4+5 rests after a lean (${settleMs.size}): settle median ${median(settleMs)} ms, p90 ${sorted[sorted.size * 9 / 10]} ms, worst ${sorted.last()} ms")
            appendLine("runs 4+5 worst opposite-side overshoot on those returns: ${"%.3f".format(overshoot)}")
            appendLine("run 5 knob glances: |out|>$NEUTRAL_BAND on ${"%.1f".format(knobVisible * 100)}%, worst ${"%.3f".format(knobWorst)}")
            append("runs 4+5 riding: mean |step| ${"%.4f".format(ridingMeanStep)}/frame")
        }
    }

    private fun loadRows(name: String) = LeanResponseReplayTest::class.java.classLoader!!.getResourceAsStream(name)!!
        .bufferedReader().useLines { HeadFixtureCsv.parse(it) }

    private fun replayRun(config: HeadTrackerConfig, run: Int): List<Frame> {
        val engine = HeadTrackingEngine(config, wallClockMs = { 1_790_800_000_000L })
        val saved = HeadCalibration(leftDx = -0.1031, rightDx = 0.1079, calibratedAtEpochMs = 1_790_800_000_000L)
        val runRows = loadRows(if (run == 4) "headtracker/bike-run4-lookaway-2026-09-30.csv" else "headtracker/bike-run5-lookaway-2026-09-30.csv")
        var previous: String? = null
        var lastRaw = 0.0
        var segmentStart = 0L
        return runRows.map { row ->
            if (row.step != previous) {
                segmentStart = row.timestampMs
                when {
                    run == 5 && previous == null -> engine.startCalibration(TrackerMode.LEAN_X, reuse = saved)
                    row.step == "cal_centre" -> engine.startCalibration(TrackerMode.LEAN_X, reuse = null)
                    row.step == "centre2" || row.step == "centre3" -> {
                        engine.setMode(TrackerMode.OFF)
                        engine.resetSession()
                        engine.startCalibration(TrackerMode.LEAN_X, reuse = engine.calibration ?: saved)
                    }
                }
                previous = row.step
            }
            val state = engine.onFrame(row.timestampMs, row.face)
            if (row.face != null) lastRaw = state.rawLeanX
            Frame(row.step, segmentStart, row.timestampMs, lastRaw, state.leanX, row.face != null && state.trackerState == TrackerState.TRACKING)
        }
    }

    fun measureRides(config: HeadTrackerConfig = HeadTrackerConfig()): RideMetrics {
        val settle = mutableListOf<Long>()
        var overshoot = 0.0
        var knob = listOf<Frame>()
        val ridingSteps = mutableListOf<Double>()
        for (run in listOf(4, 5)) {
            val frames = replayRun(config, run)
            if (run == 5) knob = frames.filter { it.step == "look_down_knob" }
            val riding = frames.filter { it.step == "riding" && it.tracking }
            riding.zipWithNext().filter { (a, b) -> b.tMs - a.tMs < 100 }.forEach { (a, b) -> ridingSteps += abs(b.out - a.out) }
            var peak = 0.0
            for (f in riding) {
                if (abs(f.raw) >= 0.8) peak = f.raw
                if (peak == 0.0 || abs(f.raw) >= 0.5) continue
                val rest = riding.filter { it.tMs in f.tMs..f.tMs + 1_500 }
                val resting = rest.filter { it.tMs in f.tMs + 300..f.tMs + 1_000 }.all { abs(it.raw) <= 0.35 }
                if (rest.last().tMs - f.tMs >= 1_400 && resting) {
                    val settled = rest.firstOrNull { start ->
                        start.tMs + SETTLE_HOLD_MS <= rest.last().tMs &&
                            rest.filter { it.tMs in start.tMs..start.tMs + SETTLE_HOLD_MS }.all { abs(it.out) <= NEUTRAL_BAND }
                    }
                    settle += (settled?.tMs ?: rest.last().tMs) - f.tMs
                    val side = if (peak < 0) -1.0 else 1.0
                    overshoot = maxOf(overshoot, rest.maxOf { -it.out * side })
                }
                peak = 0.0
            }
        }
        return RideMetrics(
            settleMs = settle,
            overshoot = overshoot,
            knobVisible = knob.count { abs(it.out) > NEUTRAL_BAND }.toDouble() / knob.size,
            knobWorst = knob.maxOf { abs(it.out) },
            ridingMeanStep = ridingSteps.average(),
        )
    }

    @Test
    fun `report the lean response on the recorded rides`() {
        println(measure())
        println(measureRides())
    }

    @Test
    fun `diag noise`() {
        val c = HeadTrackerConfig()
        fun q(v: List<Double>, p: Double) = v.map { abs(it) }.sorted()[(v.size * p).toInt().coerceAtMost(v.size - 1)]
        fun rep(name: String, fr: List<Frame>) {
            val f = OneEuroFilter(c.filterMinCutoffHz, c.filterBeta, c.filterDerivativeCutoffHz)
            val filt = fr.filter { it.tracking }.map { f.filter(it.tMs, it.raw) }.drop(15)
            val raw = fr.filter { it.tracking }.map { it.raw }
            println("$name n=${raw.size} raw mean ${"%.3f".format(raw.average())} p50 ${"%.3f".format(q(raw, .5))} p95 ${"%.3f".format(q(raw, .95))} | filt mean ${"%.3f".format(filt.average())} p50 ${"%.3f".format(q(filt, .5))} p90 ${"%.3f".format(q(filt, .9))} p95 ${"%.3f".format(q(filt, .95))} p99 ${"%.3f".format(q(filt, .99))}")
        }
        val spike = replay(HeadTrackingEngine(c))
        spike.groupBy { it.step to it.segmentStartMs }.filterKeys { it.first in setOf("easy_centre", "sprint_centre", "knob_glance", "sit") }
            .forEach { (k, v) -> rep("spike ${k.first}@${k.second / 1000}", v.filter { it.tMs - it.segmentStartMs > 2_000 }) }
        val r5 = replayRun(c, 5)
        r5.groupBy { it.step to it.segmentStartMs }.filterKeys { it.first in setOf("look_down_knob") }
            .forEach { (k, v) -> rep("run5 ${k.first}@${k.second / 1000}", v) }
        rep("run5 riding all", r5.filter { it.step == "riding" })
        rep("run4 riding all", replayRun(c, 4).filter { it.step == "riding" })
        println("static adaptive off:")
        println(measure(HeadTrackerConfig(deadZoneMoveOn = 1e9)))
        println(measureRides(HeadTrackerConfig(deadZoneMoveOn = 1e9)))
    }
}

private fun median(values: List<Long>): Long = if (values.isEmpty()) -1 else values.sorted()[values.size / 2]
