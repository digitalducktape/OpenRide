package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import kotlin.math.sign

/**
 * Maps a measured offset from the calibrated centre (face x in frame widths, or face-size ratio
 * minus 1 for depth) to lean units: -1 at [fullLockFraction] of [minusOneExtreme], +1 at
 * [fullLockFraction] of [plusOneExtreme], linear on each side so an asymmetric rider still
 * reaches both edges. The extremes only need opposite signs, so a camera that mirrors the image
 * is handled by calibration rather than by a flag.
 *
 * The result is bounded to ±[MAX_RAW] (not ±1) so the filter can settle past full lock quickly
 * when the rider leans further than 85%; [deadZone] then clamps it to ±1.
 */
class AxisMapping(
    private val minusOneExtreme: Double,
    private val plusOneExtreme: Double,
    private val fullLockFraction: Double,
) {
    init {
        require(minusOneExtreme != 0.0 && plusOneExtreme != 0.0 && sign(minusOneExtreme) != sign(plusOneExtreme)) {
            "extremes must be non-zero with opposite signs: $minusOneExtreme, $plusOneExtreme"
        }
    }

    fun normalize(offset: Double): Double {
        if (offset == 0.0) return 0.0
        val lean = if (sign(offset) == sign(plusOneExtreme)) {
            offset / (plusOneExtreme * fullLockFraction)
        } else {
            -offset / (minusOneExtreme * fullLockFraction)
        }
        return lean.coerceIn(-MAX_RAW, MAX_RAW)
    }

    companion object {
        const val MAX_RAW = 1.5

        /** Left/right: the rider's left lean reads -1. */
        fun fromExtremes(leftExtreme: Double, rightExtreme: Double, fullLockFraction: Double) =
            AxisMapping(minusOneExtreme = leftExtreme, plusOneExtreme = rightExtreme, fullLockFraction = fullLockFraction)
    }
}

/**
 * A centre dead zone of half-width [zone] that keeps the output continuous: values inside read 0,
 * and the rest is rescaled so ±1 still maps to ±1. Clamped to ±1.
 */
fun deadZone(value: Double, zone: Double): Double {
    val magnitude = abs(value)
    if (magnitude <= zone) return 0.0
    return (sign(value) * (magnitude - zone) / (1.0 - zone)).coerceIn(-1.0, 1.0)
}
