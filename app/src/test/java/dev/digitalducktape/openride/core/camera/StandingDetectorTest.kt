package dev.digitalducktape.openride.core.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StandingDetectorTest {

    private val config = HeadTrackerConfig()
    private val baseline = CentreBaseline(cx = SEATED.cx, cy = SEATED.cy, size = SEATED.size, pitchDeg = SEATED.pitchDeg)

    /** Standing on the Gen 2: the face grows 1.3-2.4x and rises in the frame. */
    private val standingFace = SEATED.shifted(dy = -0.3, sizeRatio = 1.6)

    private fun StandingDetector.run(script: FrameScript): List<Pair<Long, Boolean>> {
        val out = script.frames.map { it.timestampMs to update(it.timestampMs, it.face!!, baseline) }
        script.frames.clear()
        return out
    }

    private fun List<Pair<Long, Boolean>>.firstTrue(): Long? = firstOrNull { it.second }?.first
    private fun List<Pair<Long, Boolean>>.firstFalse(): Long? = firstOrNull { !it.second }?.first

    @Test
    fun `standing is entered after half a second of the standing posture`() {
        val detector = StandingDetector(config)
        val script = FrameScript().hold(1_000, SEATED).hold(2_000, standingFace)
        val out = detector.run(script)
        // Posture starts at 1023 (first frame of the segment); entered 0.5 s later.
        val entered = out.firstTrue()!!
        assertTrue("entered at $entered", entered in 1_500L..1_560L)
        assertEquals(entered, detector.standingSinceMs)
    }

    @Test
    fun `standing is left after one second back in the saddle`() {
        val detector = StandingDetector(config)
        detector.run(FrameScript().hold(2_000, standingFace))
        assertTrue(detector.standing)

        val script = FrameScript(2_000).hold(2_000, SEATED)
        val exitedAt = detector.run(script).firstFalse()!!
        assertTrue("exited at $exitedAt", exitedAt in 3_000L..3_060L)
        assertNull(detector.standingSinceMs)
    }

    @Test
    fun `a short bob of the head does not count as standing`() {
        val detector = StandingDetector(config)
        val script = FrameScript()
            .hold(1_000, SEATED)
            .hold(400, standingFace)
            .hold(1_000, SEATED)
            .hold(400, standingFace)
            .hold(1_000, SEATED)
        assertNull(detector.run(script).firstTrue())
    }

    @Test
    fun `a dip shorter than a second does not end standing`() {
        val detector = StandingDetector(config)
        val script = FrameScript()
            .hold(2_000, standingFace)
            .hold(800, SEATED)
            .hold(2_000, standingFace)
        val out = detector.run(script)
        assertTrue(out.drop(out.indexOfFirst { it.second }).all { it.second })
    }

    @Test
    fun `a knob glance never reads as standing`() {
        // Spike: looking down at the knob grows the face 1.17x (up to ~1.3x) and pitches the
        // head to about -22 degrees, with the face lower in the frame.
        val detector = StandingDetector(config)
        val glance = SEATED.shifted(dy = 0.19, sizeRatio = 1.3, pitchDeg = -22.0)
        assertNull(detector.run(FrameScript().hold(8_000, glance)).firstTrue())
    }

    @Test
    fun `the pitch limit is minus fifteen degrees`() {
        val tipped = StandingDetector(config)
        assertFalse(tipped.run(FrameScript().hold(2_000, standingFace.copy(pitchDeg = -16.0))).last().second)
        val level = StandingDetector(config)
        assertTrue(level.run(FrameScript().hold(2_000, standingFace.copy(pitchDeg = -14.0))).last().second)
    }

    @Test
    fun `the size threshold is 1_25x the seated baseline`() {
        val small = StandingDetector(config)
        assertFalse(small.run(FrameScript().hold(2_000, SEATED.shifted(dy = -0.2, sizeRatio = 1.24))).last().second)
        val big = StandingDetector(config)
        assertTrue(big.run(FrameScript().hold(2_000, SEATED.shifted(dy = -0.2, sizeRatio = 1.26))).last().second)
    }

    @Test
    fun `a big face lower in the frame is leaning in, not standing`() {
        // From the spike fixture: sitting back down (head forward and down) grew the face to
        // 2x with the face ~0.08 lower, and the plain size rule reported 1.4 s of false standing.
        val detector = StandingDetector(config)
        val leaningDown = SEATED.shifted(dy = 0.08, sizeRatio = 2.0, pitchDeg = -12.0)
        assertNull(detector.run(FrameScript().hold(3_000, leaningDown)).firstTrue())
    }

    @Test
    fun `reset clears standing`() {
        val detector = StandingDetector(config)
        detector.run(FrameScript().hold(2_000, standingFace))
        detector.reset()
        assertFalse(detector.standing)
        assertNull(detector.standingSinceMs)
    }
}
