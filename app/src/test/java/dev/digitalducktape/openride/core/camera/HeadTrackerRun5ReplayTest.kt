package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test

/**
 * Replays bike run 5 (2026-09-30): riding, look-aways to the right and to the left, glances down
 * at the knob, a long look down at the bike, and standing at the end. With the first look-away
 * gate (yaw only), right look-aways gated but left ones didn't: turning left, BlazeFace's
 * keypoint yaw mostly stays in range and the pitch estimate jumps up instead. And the look down
 * at the bike degraded the keypoints enough to latch it, freezing steering.
 */
class HeadTrackerRun5ReplayTest {

    private class Replayed(val row: HeadFixtureCsv.Row, val state: HeadTrackerState)

    companion object {
        private const val FIXTURE = "headtracker/bike-run5-lookaway-2026-09-30.csv"
        private lateinit var rows: List<HeadFixtureCsv.Row>

        /** The extremes the session reused (run 4's, saved before calibrations recorded yaw). */
        private val SAVED = HeadCalibration(leftDx = -0.1031, rightDx = 0.1079, calibratedAtEpochMs = 1_790_800_000_000L)

        @BeforeClass
        @JvmStatic
        fun load() {
            val stream = HeadTrackerRun5ReplayTest::class.java.classLoader!!.getResourceAsStream(FIXTURE)
                ?: error("missing test resource $FIXTURE")
            rows = stream.bufferedReader().useLines { HeadFixtureCsv.parse(it) }
        }
    }

    private fun replay(config: HeadTrackerConfig = HeadTrackerConfig()): List<Replayed> {
        val engine = HeadTrackingEngine(config, wallClockMs = { 1_790_800_000_000L })
        engine.startCalibration(TrackerMode.LEAN_X, reuse = SAVED)
        return rows.map { Replayed(it, engine.onFrame(it.timestampMs, it.face)) }
    }

    /** The first gate: yaw only, no pitch rule, no low-face exemption. */
    private fun yawOnly() = HeadTrackerConfig(lookAwayPitchUpDeg = 1e9, lookAwayLowFaceDrop = 1e9)
    private fun ungated() = HeadTrackerConfig(lookAwayYawMarginDeg = 1e9, lookAwayPitchUpDeg = 1e9, lookAwayLowFaceDrop = 1e9)

    /** Contiguous runs of rows labelled [step]. */
    private fun List<Replayed>.segments(step: String): List<List<Replayed>> {
        val result = mutableListOf<MutableList<Replayed>>()
        var last: String? = null
        for (r in this) {
            if (r.row.step == step) {
                if (last != step) result += mutableListOf<Replayed>()
                result.last() += r
            }
            last = r.row.step
        }
        return result
    }

    private fun share(list: List<Replayed>, predicate: (Replayed) -> Boolean) = list.count(predicate) * 100.0 / list.size

    @Test
    fun `look-aways to either side gate, as they did not to the left before`() {
        val gated = replay()
        val before = replay(yawOnly())
        val plain = replay(ungated())
        for (side in listOf("look_right", "look_left")) {
            gated.segments(side).forEachIndexed { n, segment ->
                val start = segment.first().row.timestampMs
                val span = segment.first().row.timestampMs..segment.last().row.timestampMs
                val was = before.filter { it.row.timestampMs in span }
                val raw = plain.filter { it.row.timestampMs in span }
                val latched = segment.firstOrNull { it.state.lookingAway }
                println(
                    "$side ${n + 1} (${segment.last().row.timestampMs - start} ms): latched ${"%.0f".format(share(segment) { it.state.lookingAway })}% " +
                        "(yaw-only gate ${"%.0f".format(share(was) { it.state.lookingAway })}%), after ${latched?.let { it.row.timestampMs - start }} ms; " +
                        "frames steering > 0.1: ungated ${"%.0f".format(share(raw) { abs(it.state.leanX) > 0.1 })}%, " +
                        "yaw-only ${"%.0f".format(share(was) { abs(it.state.leanX) > 0.1 })}%, now ${"%.0f".format(share(segment) { abs(it.state.leanX) > 0.1 })}%",
                )
                assertTrue("$side ${n + 1} never latched", latched != null)
                assertTrue("$side ${n + 1} latched only ${share(segment) { it.state.lookingAway }}%", share(segment) { it.state.lookingAway } >= 75)
            }
        }
    }

    @Test
    fun `while latched, steering only holds or eases towards the centre`() {
        var limit = Double.MAX_VALUE
        for (r in replay()) {
            if (!r.state.lookingAway) {
                limit = Double.MAX_VALUE
                continue
            }
            if (limit == Double.MAX_VALUE) limit = abs(r.state.leanX)
            assertTrue("steered to ${r.state.leanX} at ${r.row.timestampMs} while looking away", abs(r.state.leanX) <= limit + 1e-9)
            limit = abs(r.state.leanX)
        }
    }

    @Test
    fun `looking down at the knob or the bike never freezes steering`() {
        val gated = replay()
        val before = replay(yawOnly())
        for (step in listOf("look_down_knob", "look_down_bike")) {
            val now = gated.filter { it.row.step == step }
            val was = before.filter { it.row.step == step }
            println("$step: latched ${"%.0f".format(share(now) { it.state.lookingAway })}% (yaw-only gate ${"%.0f".format(share(was) { it.state.lookingAway })}%), " +
                "face lost ${"%.0f".format(share(now) { it.state.trackerState == TrackerState.FACE_LOST })}%")
            assertTrue(now.none { it.state.lookingAway })
            assertTrue(now.none { it.state.trackerState == TrackerState.FACE_LOST })
        }
    }

    @Test
    fun `riding and standing never gate`() {
        val riding = replay().filter { it.row.step == "riding" }
        val standing = riding.filter { it.state.standing }
        println("riding: ${riding.size} frames (${standing.size} standing)")
        assertTrue(standing.isNotEmpty())
        assertTrue(riding.none { it.state.lookingAway })
        assertTrue(riding.none { it.state.trackerState == TrackerState.FACE_LOST })
    }
}
