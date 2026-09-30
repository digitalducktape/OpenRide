package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.BeforeClass
import org.junit.Test

/**
 * Replays bike run 4 (2026-09-30, MediaPipe keypoints) through the engine: a full lean_x
 * calibration, three rides of the demo game (sweeps, leans, a long look down), and the rider
 * turning the head away from the screen while the face stayed detected. Before the look-away
 * gate, those look-aways steered the cursor to full lock.
 */
class HeadTrackerRun4ReplayTest {

    private class Replayed(val row: HeadFixtureCsv.Row, val state: HeadTrackerState)

    companion object {
        private const val FIXTURE = "headtracker/bike-run4-lookaway-2026-09-30.csv"
        private lateinit var rows: List<HeadFixtureCsv.Row>

        @BeforeClass
        @JvmStatic
        fun load() {
            val stream = HeadTrackerRun4ReplayTest::class.java.classLoader!!.getResourceAsStream(FIXTURE)
                ?: error("missing test resource $FIXTURE")
            rows = stream.bufferedReader().useLines { HeadFixtureCsv.parse(it) }
        }
    }

    /** Replays the ride the way the app ran it: full calibration, then a centre-only one per new session. */
    private fun replay(config: HeadTrackerConfig = HeadTrackerConfig()): Pair<List<Replayed>, List<HeadCalibration>> {
        val saved = mutableListOf<HeadCalibration>()
        val engine = HeadTrackingEngine(config, wallClockMs = { 1_790_800_000_000L }, onFullCalibration = { saved += it })
        var previous: String? = null
        val out = rows.map { row ->
            if (row.step != previous) {
                when (row.step) {
                    "cal_centre" -> engine.startCalibration(TrackerMode.LEAN_X, reuse = null)
                    "centre2", "centre3" -> {
                        engine.setMode(TrackerMode.OFF)
                        engine.resetSession()
                        engine.startCalibration(TrackerMode.LEAN_X, reuse = saved.last())
                    }
                }
                previous = row.step
            }
            Replayed(row, engine.onFrame(row.timestampMs, row.face))
        }
        return out to saved
    }

    private fun ungated() = HeadTrackerConfig(lookAwayYawMarginDeg = 1e9)

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

    @Test
    fun `the replay calibrates like the ride did and records the rider's yaw range`() {
        val (replayed, saved) = replay()
        assertEquals(1, saved.size)
        val calibration = saved.single()
        println("run 4 calibration: left ${calibration.leftDx} right ${calibration.rightDx} yaw ${calibration.yawMinDeg}..${calibration.yawMaxDeg}")
        assertTrue(calibration.yawMinDeg!! < 0 && calibration.yawMaxDeg!! > 0)
        assertTrue(replayed.filter { it.row.step == "riding" }[10].state.trackerState == TrackerState.TRACKING)
    }

    @Test
    fun `riding never reads as looking away, and steers as it did without the gate`() {
        val (gated, saved) = replay()
        val plain = replay(ungated()).first
        val config = HeadTrackerConfig()
        val calibration = saved.single()
        fun outside(face: FaceObservation?) = face != null &&
            (face.yawDeg < calibration.yawMinDeg!! - config.lookAwayYawMarginDeg || face.yawDeg > calibration.yawMaxDeg!! + config.lookAwayYawMarginDeg)
        val riding = gated.indices.filter { gated[it].row.step == "riding" }
        assertTrue(riding.none { gated[it].state.lookingAway })
        assertTrue(riding.none { gated[it].state.trackerState == TrackerState.FACE_LOST })

        // The only frames the gate drops while riding are single-frame detector glitches (yaw -58
        // and -90 at an impossible face position): steering differs only just after them.
        val glitches = riding.filter { outside(gated[it].row.face) }.map { gated[it].row.timestampMs }
        println("riding: ${riding.size} frames, ${glitches.size} dropped as glitches at $glitches")
        assertTrue("dropped ${glitches.size} riding frames", glitches.size <= 3)
        val differing = riding.filter { abs(gated[it].state.leanX - plain[it].state.leanX) > 0.01 }
        for (i in differing) {
            val t = gated[i].row.timestampMs
            assertTrue("steering differs at $t, not just after a glitch", glitches.any { t - it in 0..1_000 })
        }
    }

    @Test
    fun `looking away holds steering, eases to centre and reports face lost`() {
        val gated = replay().first
        val plain = replay(ungated()).first
        val segments = gated.segments("look_away")

        // The first look-away: 16.7 s turned away, the face flickering in and out.
        val first = segments.first()
        val start = first.first().row.timestampMs
        val latched = first.first { it.state.lookingAway }
        println("look-away 1 latched after ${latched.row.timestampMs - start} ms, face lost after " +
            "${first.first { it.state.trackerState == TrackerState.FACE_LOST }.row.timestampMs - start} ms")
        assertTrue(latched.row.timestampMs - start <= 500)
        assertTrue(first.filter { it.row.timestampMs >= latched.row.timestampMs }.all { abs(it.state.leanX) <= 0.05 })
        assertTrue(first.any { it.state.trackerState == TrackerState.FACE_LOST })

        // While latched, steering only holds or eases towards the centre, never moves out.
        var limit = Double.MAX_VALUE
        for (r in gated) {
            if (!r.state.lookingAway) {
                limit = Double.MAX_VALUE
                continue
            }
            if (limit == Double.MAX_VALUE) limit = abs(r.state.leanX)
            assertTrue("steered to ${r.state.leanX} at ${r.row.timestampMs} while looking away", abs(r.state.leanX) <= limit + 1e-9)
            limit = abs(r.state.leanX)
        }

        // Across both look-aways (which include short glances back at the screen, where steering
        // rightly resumes): how often the cursor was visibly off-centre.
        fun steering(list: List<Replayed>) = list.filter { it.row.step == "look_away" }.let { l -> l.count { abs(it.state.leanX) > 0.1 } * 100.0 / l.size }
        val withGate = steering(gated)
        val without = steering(plain)
        println("look-away frames steering > 0.1: without the gate ${"%.0f".format(without)}%, with it ${"%.0f".format(withGate)}%")
        assertTrue(without > 50)
        assertTrue(withGate < 15)
    }

    @Test
    fun `without the gate the look-aways steered - the bug this fixes`() {
        val plain = replay(ungated()).first
        val worst = plain.filter { it.row.step == "look_away" }.maxOf { abs(it.state.leanX) }
        assertTrue("ungated worst $worst", worst > 0.9)
    }
}
