package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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

class AdaptiveDeadZoneTest {
    private val config = HeadTrackerConfig()

    @Test
    fun `at rest it is the soft dead zone`() {
        val zone = AdaptiveDeadZone(config)
        for (i in 0 until 60) {
            val x = 0.3 + bounce(i * 33L, 0.03, 3.0)
            assertEquals(deadZone(x, config.deadZone, config.deadZoneRamp), zone.apply(i * 33L, x), 1e-9)
        }
        assertFalse(zone.moving)
    }

    @Test
    fun `pedal bounce never counts as a move`() {
        val zone = AdaptiveDeadZone(config)
        // +-0.1 lean units at 3 Hz is what reaches the dead zone after filtering a sprint.
        for (i in 0 until 300) zone.apply(i * 33L, bounce(i * 33L, 0.1, 3.0))
        assertFalse(zone.moving)
        assertEquals(1.0, zone.weight, 0.0)
    }

    @Test
    fun `a fast crossing passes through the centre one-to-one`() {
        val zone = AdaptiveDeadZone(config)
        for (i in 0 until 30) zone.apply(i * 33L, -1.0)
        // -1 -> +1 in 500 ms.
        var t = 30 * 33L
        var atCentre = Double.NaN
        for (i in 0..15) {
            val x = -1.0 + 2.0 * i / 15
            val y = zone.apply(t, x)
            if (i == 8) atCentre = y - x
            t += 33
        }
        assertTrue(zone.moving)
        // Mid-crossing the output follows the lean instead of sitting in the dead zone.
        assertEquals(0.0, atCentre, 0.05)
    }

    @Test
    fun `once still it fades back to the dead zone`() {
        val zone = AdaptiveDeadZone(config)
        for (i in 0..10) zone.apply(i * 33L, -1.0 + 1.3 * i / 10)
        assertTrue(zone.moving)
        var y = 0.0
        for (i in 11..60) y = zone.apply(i * 33L, 0.3)
        assertFalse(zone.moving)
        assertEquals(deadZone(0.3, config.deadZone, config.deadZoneRamp), y, 0.01)
    }
}

class LookAwayGateTest {
    private val config = HeadTrackerConfig()
    private fun face(yaw: Double) = SEATED.copy(yawDeg = yaw)
    private fun gate() = LookAwayGate(config).apply { setRange(-10.0, 5.0) }

    @Test
    fun `with no calibrated range nothing is rejected`() {
        val gate = LookAwayGate(config)
        assertFalse(gate.reject(0, face(90.0)))
    }

    @Test
    fun `yaw within the calibrated range plus the margin is used`() {
        val gate = gate()
        for (i in 0 until 60) assertFalse(gate.reject(i * 33L, face(if (i % 2 == 0) -34.0 else 29.0)))
        assertFalse(gate.lookingAway)
    }

    @Test
    fun `a single glitch frame is dropped but does not latch`() {
        val gate = gate()
        assertTrue(gate.reject(0, face(-90.0)))
        assertFalse(gate.reject(33, face(0.0)))
        assertFalse(gate.lookingAway)
    }

    @Test
    fun `300 ms turned away latches, through missing frames, and rejects in-range frames until looking back`() {
        val gate = gate()
        assertTrue(gate.reject(0, face(90.0)))
        gate.onNoFace() // the face flickers out mid-turn
        assertTrue(gate.reject(310, face(80.0)))
        assertTrue(gate.lookingAway)
        // A frame passing through the range while turning is still rejected...
        assertTrue(gate.reject(343, face(2.0)))
        gate.onNoFace()
        // ...and missing frames break a look back, so it must be 300 ms of face frames.
        assertTrue(gate.reject(700, face(2.0)))
        var t = 733L
        while (t < 1_000) {
            assertTrue(gate.reject(t, face(0.0)))
            t += 33
        }
        assertFalse(gate.reject(t + 33, face(0.0)))
        assertFalse(gate.lookingAway)
    }
}
