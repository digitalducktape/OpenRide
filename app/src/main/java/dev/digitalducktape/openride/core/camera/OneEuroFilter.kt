package dev.digitalducktape.openride.core.camera

import kotlin.math.PI
import kotlin.math.abs

/**
 * The One Euro filter (Casiez, Roussel & Vogel, CHI 2012): a first-order low-pass whose cutoff
 * rises with the signal's speed. When the head is nearly still (pedal bounce around a steady
 * position) the cutoff sits at [minCutoffHz] and jitter is smoothed away; when the rider leans
 * deliberately the estimated speed raises the cutoff by [beta] per unit/s, so the lean comes
 * through with little lag.
 *
 * Written for this project from the paper's published description.
 *
 * @param derivativeCutoffHz cutoff for the low-passed speed estimate that drives the adaptation.
 */
class OneEuroFilter(
    private val minCutoffHz: Double,
    private val beta: Double,
    private val derivativeCutoffHz: Double,
) {
    private var hasValue = false
    private var lastTimestampMs = 0L
    private var value = 0.0
    private var speed = 0.0

    /** Filters [x] sampled at [timestampMs] (monotonic milliseconds) and returns the new estimate. */
    fun filter(timestampMs: Long, x: Double): Double {
        if (!hasValue) {
            hasValue = true
            lastTimestampMs = timestampMs
            value = x
            speed = 0.0
            return x
        }
        // Same-instant or out-of-order frames: treat as a minimal step rather than dividing by 0.
        val dtSec = ((timestampMs - lastTimestampMs).coerceAtLeast(1L)) / 1000.0
        lastTimestampMs = maxOf(lastTimestampMs, timestampMs)

        val rawSpeed = (x - value) / dtSec
        speed += smoothingFactor(derivativeCutoffHz, dtSec) * (rawSpeed - speed)
        val cutoff = minCutoffHz + beta * abs(speed)
        value += smoothingFactor(cutoff, dtSec) * (x - value)
        return value
    }

    /** Forgets history; the next sample passes straight through. */
    fun reset() {
        hasValue = false
    }

    private fun smoothingFactor(cutoffHz: Double, dtSec: Double): Double {
        val tau = 1.0 / (2 * PI * cutoffHz)
        return 1.0 / (1.0 + tau / dtSec)
    }
}
