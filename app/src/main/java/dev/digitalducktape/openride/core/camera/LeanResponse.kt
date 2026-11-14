package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import kotlin.math.sign

/**
 * The rider's lean sensitivity (#71), chosen in the games hub's options and applied by the head
 * tracker to `lean_x` before it reaches any game, so every game feels the same change.
 *
 * Each level is a response curve from the filtered lean (lean units: 0 = the calibrated centre,
 * 1 = 85% of the rider's comfortable lean) to the steering output, see [shape]:
 *
 * - a centre **dead zone** of half-width `deadZone` ([HeadTrackerConfig.leanDeadZone]), the same
 *   for every level because it hides measured noise, not preference;
 * - then an **expo** curve, `(1 - expo) * u + expo * u³` over `u` = the lean past the dead zone,
 *   rescaled so the output starts at 0 on the dead zone's edge (no step) and reaches ±1 at
 *   [fullLock]. Near the centre the slope is `1 - expo` of a straight line, so small sways and an
 *   imperfect return to centre move the output little; towards full lock it steepens.
 *
 * `fullLock` is 1.0 for Low and Normal: at the default level a rider leans no further than before
 * #71 to reach the edge. High reaches it at 0.85, for riders who want less travel.
 *
 * @param code the value stored in the rider's options and sent over the bridge.
 */
enum class LeanSensitivity(val code: String, val expo: Double, val fullLock: Double) {
    LOW("low", expo = 0.9, fullLock = 1.0),
    NORMAL("normal", expo = 0.75, fullLock = 1.0),
    HIGH("high", expo = 0.55, fullLock = 0.85),
    ;

    /** The steering output (-1..1) for a filtered lean [value], with a dead zone of [deadZone]. */
    fun shape(value: Double, deadZone: Double): Double {
        val magnitude = abs(value)
        if (magnitude <= deadZone) return 0.0
        val u = ((magnitude - deadZone) / (fullLock - deadZone)).coerceAtMost(1.0)
        return sign(value) * ((1.0 - expo) * u + expo * u * u * u)
    }

    companion object {
        val DEFAULT = NORMAL

        /** The level stored as [code]; anything unknown or missing is [DEFAULT]. */
        fun fromCode(code: String?): LeanSensitivity = entries.firstOrNull { it.code == code } ?: DEFAULT
    }
}
