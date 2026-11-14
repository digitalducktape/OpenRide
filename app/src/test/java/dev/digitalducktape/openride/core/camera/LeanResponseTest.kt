package dev.digitalducktape.openride.core.camera

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/** The lean response curve (#71): dead zone, expo, full lock, sensitivity levels. */
class LeanResponseTest {
    private val config = HeadTrackerConfig()
    private val zone = config.leanDeadZone
    private fun shape(x: Double, level: LeanSensitivity = LeanSensitivity.NORMAL) = level.shape(x, zone)

    /** -1.5..1.5 (the filter's bounded range) in fine steps. */
    private val inputs = (-1500..1500).map { it / 1000.0 }

    @Test
    fun `inside the dead zone the lean reads as centre`() {
        for (level in LeanSensitivity.entries) {
            assertEquals(0.0, level.shape(0.0, zone), 0.0)
            assertEquals(0.0, level.shape(zone, zone), 0.0)
            assertEquals(0.0, level.shape(-zone, zone), 0.0)
            assertEquals(0.0, level.shape(zone * 0.5, zone), 0.0)
        }
    }

    @Test
    fun `the dead zone is sized from the measured centre noise`() {
        // Spike and bike runs: seated centre sd ~0.02 of frame width is ~0.15 lean units raw;
        // after the One Euro filter the median |lean| at rest was 0.06-0.16.
        assertTrue("dead zone $zone", zone in 0.08..0.2)
    }

    @Test
    fun `leaving the dead zone has no step`() {
        for (level in LeanSensitivity.entries) {
            val justOut = level.shape(zone + 1e-6, zone)
            assertTrue("$level just outside the zone: $justOut", justOut > 0 && justOut < 1e-5)
        }
    }

    @Test
    fun `the response is continuous everywhere`() {
        for (level in LeanSensitivity.entries) {
            inputs.zipWithNext().forEach { (a, b) ->
                val jump = kotlin.math.abs(level.shape(b, zone) - level.shape(a, zone))
                assertTrue("$level jumps by $jump between $a and $b", jump < 0.005)
            }
        }
    }

    @Test
    fun `the response is monotonic and strictly rising between the dead zone and full lock`() {
        for (level in LeanSensitivity.entries) {
            inputs.zipWithNext().forEach { (a, b) ->
                val ya = level.shape(a, zone)
                val yb = level.shape(b, zone)
                assertTrue("$level falls between $a and $b", yb >= ya)
                if (a > zone && b < level.fullLock) assertTrue("$level flat between $a and $b", yb > ya)
            }
        }
    }

    @Test
    fun `left and right are mirror images`() {
        for (level in LeanSensitivity.entries) {
            for (x in inputs) assertEquals(-level.shape(x, zone), level.shape(-x, zone), 0.0)
        }
    }

    @Test
    fun `the output is bounded to full lock`() {
        for (level in LeanSensitivity.entries) {
            for (x in inputs) assertTrue(kotlin.math.abs(level.shape(x, zone)) <= 1.0)
            assertEquals(1.0, level.shape(5.0, zone), 0.0)
            assertEquals(-1.0, level.shape(-5.0, zone), 0.0)
        }
    }

    @Test
    fun `at the default level full lock comes at the same lean as before`() {
        // Before #71 full lock was lean 1.0 (85% of the calibrated comfortable lean).
        assertEquals(LeanSensitivity.NORMAL, LeanSensitivity.DEFAULT)
        assertEquals(1.0, shape(1.0), 0.0)
        assertEquals(-1.0, shape(-1.0), 0.0)
        assertTrue(shape(0.98) < 1.0)
        // No level asks for a bigger lean than that.
        for (level in LeanSensitivity.entries) assertEquals(1.0, level.shape(1.0, zone), 0.0)
    }

    @Test
    fun `near the centre the response is gentler than a straight line`() {
        for (level in LeanSensitivity.entries) {
            for (x in listOf(0.2, 0.3, 0.4, 0.5, 0.6)) {
                val linear = (x - zone) / (level.fullLock - zone)
                assertTrue("$level at $x: ${level.shape(x, zone)} vs linear $linear", level.shape(x, zone) < linear)
            }
        }
        // A 1-sd seated wobble (0.02 of frame width, ~0.2 lean units) barely moves the output.
        assertTrue("wobble ${shape(0.2)}", shape(0.2) < 0.05)
    }

    @Test
    fun `sensitivity levels are ordered`() {
        for (x in inputs.filter { it > zone }) {
            val low = LeanSensitivity.LOW.shape(x, zone)
            val normal = LeanSensitivity.NORMAL.shape(x, zone)
            val high = LeanSensitivity.HIGH.shape(x, zone)
            assertTrue("low $low <= normal $normal at $x", low <= normal)
            assertTrue("normal $normal <= high $high at $x", normal <= high)
            if (x < LeanSensitivity.HIGH.fullLock) assertTrue("normal < high at $x", normal < high)
            if (x < LeanSensitivity.NORMAL.fullLock) assertTrue("low < normal at $x", low < normal)
        }
    }

    @Test
    fun `levels are stored by their bridge code`() {
        for (level in LeanSensitivity.entries) assertEquals(level, LeanSensitivity.fromCode(level.code))
        assertEquals(listOf("low", "normal", "high"), LeanSensitivity.entries.map { it.code })
        assertEquals(LeanSensitivity.NORMAL, LeanSensitivity.fromCode(null))
        assertEquals(LeanSensitivity.NORMAL, LeanSensitivity.fromCode("ludicrous"))
    }
}
