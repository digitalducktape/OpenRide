package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AxisMappingTest {

    @Test
    fun `values inside the dead zone read as centre`() {
        assertEquals(0.0, deadZone(0.0, 0.3), 0.0)
        assertEquals(0.0, deadZone(0.29, 0.3), 0.0)
        assertEquals(0.0, deadZone(-0.3, 0.3), 0.0)
    }

    @Test
    fun `the dead zone is continuous and still reaches full lock`() {
        assertEquals(0.0, deadZone(0.3 + 1e-9, 0.3), 1e-6)
        assertEquals(0.5, deadZone(0.65, 0.3), 1e-9)
        assertEquals(-0.5, deadZone(-0.65, 0.3), 1e-9)
        assertEquals(1.0, deadZone(1.0, 0.3), 1e-9)
        assertEquals(-1.0, deadZone(-1.0, 0.3), 1e-9)
    }

    @Test
    fun `the soft edge eases out of the dead zone with no step in value or slope`() {
        val zone = 0.15
        val ramp = 0.3
        assertEquals(0.0, deadZone(0.15, zone, ramp), 0.0)
        // Just outside the zone the output is tiny (slope 0 at the edge)...
        val justOut = deadZone(0.16, zone, ramp)
        assertTrue("just out $justOut", justOut > 0 && justOut < 1e-3)
        // ...and it rises monotonically and smoothly to full lock.
        var previous = 0.0
        var previousSlope = 0.0
        for (i in 1..1000) {
            val x = zone + i * (1 - zone) / 1000
            val y = deadZone(x, zone, ramp)
            val slope = (y - previous) / ((1 - zone) / 1000)
            assertTrue("monotonic at $x", y >= previous)
            assertTrue("smooth slope at $x", abs(slope - previousSlope) < 0.02 || i == 1)
            previous = y
            previousSlope = slope
        }
        assertEquals(1.0, deadZone(1.0, zone, ramp), 1e-9)
        assertEquals(-1.0, deadZone(-1.0, zone, ramp), 1e-9)
        assertEquals(-deadZone(0.4, zone, ramp), deadZone(-0.4, zone, ramp), 0.0)
    }

    @Test
    fun `a zero ramp is the plain rescaled dead zone`() {
        assertEquals(deadZone(0.65, 0.3), deadZone(0.65, 0.3, 0.0), 0.0)
    }

    @Test
    fun `the dead zone clamps beyond full lock`() {
        assertEquals(1.0, deadZone(1.4, 0.3), 0.0)
        assertEquals(-1.0, deadZone(-2.0, 0.3), 0.0)
    }

    @Test
    fun `full lock is 85 percent of each measured extreme`() {
        val axis = AxisMapping(minusOneExtreme = -0.16, plusOneExtreme = 0.20, fullLockFraction = 0.85)
        assertEquals(-1.0, axis.normalize(-0.16 * 0.85), 1e-9)
        assertEquals(1.0, axis.normalize(0.20 * 0.85), 1e-9)
        // Asymmetric: half the right-hand full lock is half of +1.
        assertEquals(0.5, axis.normalize(0.10 * 0.85), 1e-9)
        assertEquals(0.0, axis.normalize(0.0), 0.0)
    }

    @Test
    fun `a comfortable lean past full lock still reads as full lock`() {
        val axis = AxisMapping(minusOneExtreme = -0.16, plusOneExtreme = 0.20, fullLockFraction = 0.85)
        assertEquals(-1.0, deadZone(axis.normalize(-0.16), 0.3), 0.0)
        assertEquals(1.0, deadZone(axis.normalize(0.20), 0.3), 0.0)
    }

    @Test
    fun `a mirrored camera maps the rider's left from the measured extremes`() {
        // If a camera reported the rider's left lean as a positive dx, calibration measures it
        // that way and the mapping still says -1 for "left".
        val axis = AxisMapping.fromExtremes(leftExtreme = 0.15, rightExtreme = -0.17, fullLockFraction = 0.85)
        assertEquals(-1.0, axis.normalize(0.15 * 0.85), 1e-9)
        assertEquals(1.0, axis.normalize(-0.17 * 0.85), 1e-9)
    }

    @Test
    fun `the normalized value is bounded before filtering`() {
        val axis = AxisMapping(minusOneExtreme = -0.1, plusOneExtreme = 0.1, fullLockFraction = 0.85)
        assertEquals(AxisMapping.MAX_RAW, axis.normalize(5.0), 0.0)
        assertEquals(-AxisMapping.MAX_RAW, axis.normalize(-5.0), 0.0)
    }
}
