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
    private val centre = CentreBaseline(cx = SEATED.cx, cy = SEATED.cy, size = SEATED.size, pitchDeg = 2.0)
    private fun face(yaw: Double = -2.0, pitch: Double = 2.0, dy: Double = 0.0) =
        SEATED.copy(yawDeg = yaw, pitchDeg = pitch, cy = SEATED.cy + dy)
    private fun gate() = LookAwayGate(config).apply { setReference(-10.0, 5.0, centre) }

    /** Feeds [face] every 33 ms for [ms]; returns the last rejection and the next timestamp. */
    private fun LookAwayGate.feed(fromMs: Long, ms: Long, face: (Int) -> FaceObservation): Pair<Boolean, Long> {
        var t = fromMs
        var last = false
        var i = 0
        while (t < fromMs + ms) {
            last = reject(t, face(i++))
            t += 33
        }
        return last to t
    }

    @Test
    fun `with no calibrated reference nothing is rejected`() {
        assertFalse(LookAwayGate(config).reject(0, face(yaw = 90.0)))
    }

    @Test
    fun `riding within the calibrated range plus the margins is used`() {
        val gate = gate()
        val (rejected, _) = gate.feed(0, 2_000) { i -> if (i % 2 == 0) face(yaw = -34.0, pitch = 21.0) else face(yaw = 29.0, pitch = -40.0) }
        assertFalse(rejected)
        assertFalse(gate.lookingAway)
    }

    @Test
    fun `a single glitch frame is dropped but does not latch`() {
        val gate = gate()
        assertTrue(gate.reject(0, face(yaw = -90.0)))
        assertFalse(gate.reject(33, face()))
        assertFalse(gate.lookingAway)
    }

    @Test
    fun `turning right saturates yaw and latches`() {
        val gate = gate()
        gate.feed(0, 400) { face(yaw = 90.0) }
        assertTrue(gate.lookingAway)
    }

    @Test
    fun `turning left lifts the pitch estimate and latches, even with a third of frames back in range`() {
        val gate = gate()
        gate.feed(0, 500) { i -> if (i % 3 == 2) face(yaw = -4.0) else face(yaw = -6.0, pitch = 30.0) }
        assertTrue(gate.lookingAway)
    }

    @Test
    fun `looking down at the bike never counts as turned away`() {
        val gate = gate()
        val (rejected, _) = gate.feed(0, 2_000) { i -> face(yaw = if (i % 2 == 0) 60.0 else -90.0, pitch = 40.0, dy = 0.15) }
        assertFalse(rejected)
        assertFalse(gate.lookingAway)
    }

    @Test
    fun `once latched it holds through in-range and missing frames until 300 ms of looking back`() {
        val gate = gate()
        val (_, t) = gate.feed(0, 400) { face(yaw = 90.0) }
        assertTrue(gate.lookingAway)
        assertTrue(gate.reject(t, face()))
        gate.onNoFace()
        val (stillRejected, t2) = gate.feed(t + 400, 280) { face() }
        assertTrue(stillRejected)
        val (rejected, _) = gate.feed(t2, 100) { face() }
        assertFalse(rejected)
        assertFalse(gate.lookingAway)
    }
}
