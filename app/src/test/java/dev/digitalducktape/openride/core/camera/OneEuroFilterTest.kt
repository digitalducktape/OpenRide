package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OneEuroFilterTest {

    private val config = HeadTrackerConfig()
    private fun defaultFilter() = OneEuroFilter(
        minCutoffHz = config.filterMinCutoffHz,
        beta = config.filterBeta,
        derivativeCutoffHz = config.filterDerivativeCutoffHz,
    )

    @Test
    fun `first sample passes straight through`() {
        val filter = defaultFilter()
        assertEquals(0.42, filter.filter(1_000L, 0.42), 1e-12)
    }

    @Test
    fun `a constant input stays put`() {
        val filter = defaultFilter()
        var out = 0.0
        for (i in 0 until 90) out = filter.filter(i * 33L, 0.3)
        assertEquals(0.3, out, 1e-9)
    }

    @Test
    fun `pedal bounce is smoothed below the dead zone`() {
        // Sprint wobble from the spike, in lean units: +-0.2 at 3 Hz (about +-0.026 of frame
        // width against a 0.13 full lock) — this is what made the naive tracker twitchy.
        val filter = defaultFilter()
        var peak = 0.0
        for (i in 0 until 300) {
            val t = i * 33L
            val out = filter.filter(t, bounce(t, 0.2, 3.0))
            if (t > 2_000) peak = maxOf(peak, abs(out))
        }
        assertTrue("bounce peak after filtering was $peak", peak < config.deadZone)
        assertEquals(0.0, deadZone(peak, config.deadZone), 0.0)
    }

    @Test
    fun `a deliberate lean is followed quickly`() {
        // The rider leans from centre to full lock over 300 ms and holds it.
        val filter = defaultFilter()
        var reachedAt: Long? = null
        for (i in 0 until 90) {
            val t = i * 33L
            val target = ((t - 1_000L).coerceAtLeast(0L) / 300.0).coerceAtMost(1.0)
            val out = filter.filter(t, target)
            if (reachedAt == null && out >= 0.9) reachedAt = t
        }
        // Lean finishes at 1300 ms; the filtered value is at 90% within 200 ms of that.
        val at = reachedAt ?: error("never reached 0.9")
        assertTrue("reached 0.9 at $at ms", at <= 1_500L)
    }

    @Test
    fun `a higher beta tracks a moving input with less lag`() {
        fun lagFor(beta: Double): Double {
            val filter = OneEuroFilter(minCutoffHz = 0.5, beta = beta, derivativeCutoffHz = 1.0)
            var lag = 0.0
            for (i in 0 until 60) {
                val t = i * 33L
                val input = t / 1000.0 // a steady 1 unit/s drift
                lag = input - filter.filter(t, input)
            }
            return lag
        }
        assertTrue(lagFor(beta = 1.0) < lagFor(beta = 0.0))
    }

    @Test
    fun `repeated or backwards timestamps do not produce NaN`() {
        val filter = defaultFilter()
        filter.filter(100L, 0.0)
        val same = filter.filter(100L, 1.0)
        val back = filter.filter(50L, 0.5)
        assertFalse(same.isNaN())
        assertFalse(back.isNaN())
    }

    @Test
    fun `reset makes the next sample pass straight through`() {
        val filter = defaultFilter()
        filter.filter(0L, 0.0)
        filter.filter(33L, 0.0)
        filter.reset()
        assertEquals(0.8, filter.filter(66L, 0.8), 1e-12)
    }
}
