package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import kotlin.math.exp
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
 * A centre dead zone of half-width [zone] with a soft edge: values inside read 0; over the next
 * [ramp] the output eases in quadratically (slope 0 at the edge, so leaving the zone never jumps),
 * then grows linearly so ±1 still maps to ±1. Continuous with a continuous slope; clamped to ±1.
 * With [ramp] 0 it is the plain rescaled dead zone.
 */
fun deadZone(value: Double, zone: Double, ramp: Double = 0.0): Double {
    val magnitude = abs(value)
    if (magnitude <= zone) return 0.0
    val u = magnitude - zone
    val span = 1.0 - zone
    val r = ramp.coerceIn(0.0, span)
    val eased = if (u < r) u * u / (2 * r) else u - r / 2
    return (sign(value) * eased / (span - r / 2)).coerceIn(-1.0, 1.0)
}

/**
 * The lean's dead zone, applied only while the head is near-still. At rest it is [deadZone] with
 * its soft edge, which hides seated wobble. During a deliberate move (the filtered lean travels
 * at least [HeadTrackerConfig.deadZoneMoveOn] within [HeadTrackerConfig.deadZoneMoveWindowMs];
 * pedal bounce and seated wobble travel far less) the dead zone fades out and the output follows
 * the filtered lean one-to-one, so a lean from one side to the other no longer stalls in the
 * centre. Once the travel drops below [HeadTrackerConfig.deadZoneMoveOff] (hysteresis) it fades
 * back in over [HeadTrackerConfig.deadZoneFadeBackMs].
 *
 * Trade-off: at full lock and at the centre both mappings agree, but a move that stops part-way
 * (e.g. half a lean) settles from the one-to-one value back to the dead-zone curve.
 *
 * Not thread-safe; one per axis.
 */
class AdaptiveDeadZone(private val config: HeadTrackerConfig) {
    /** 1 = full dead zone (at rest), 0 = pass-through (moving). */
    var weight = 1.0
        private set

    var moving = false
        private set

    private val recent = ArrayDeque<Pair<Long, Double>>()
    private var lastMs: Long? = null

    fun apply(timestampMs: Long, value: Double): Double {
        val dtMs = lastMs?.let { (timestampMs - it).coerceIn(0L, 200L) } ?: 0L
        lastMs = timestampMs
        recent.addLast(timestampMs to value)
        while (recent.size > 1 && timestampMs - recent.first().first > config.deadZoneMoveWindowMs) recent.removeFirst()
        val travel = abs(value - recent.first().second)
        moving = if (moving) travel >= config.deadZoneMoveOff else travel >= config.deadZoneMoveOn

        val target = if (moving) 0.0 else 1.0
        val tauMs = if (moving) config.deadZoneFadeOutMs else config.deadZoneFadeBackMs
        weight += (target - weight) * (1.0 - exp(-dtMs / tauMs.toDouble().coerceAtLeast(1.0)))

        val zoned = deadZone(value, config.deadZone, config.deadZoneRamp)
        if (weight >= 0.999) return zoned
        return (weight * zoned + (1.0 - weight) * value.coerceIn(-1.0, 1.0)).coerceIn(-1.0, 1.0)
    }

    fun reset() {
        weight = 1.0
        moving = false
        recent.clear()
        lastMs = null
    }
}

/**
 * "Not looking at the screen": the face is still detected, but its keypoints say it is turned
 * away (see [HeadTrackerConfig.lookAwayYawMarginDeg] and [HeadTrackerConfig.lookAwayPitchUpDeg]).
 * Each such frame is rejected. When turned-away frames make up [HeadTrackerConfig.lookAwayShare]
 * of the last [HeadTrackerConfig.lookAwayWindowMs] of face frames, the gate latches and rejects
 * every frame, including the in-range ones a turned head flickers through, until the face has
 * stayed within range, frame after frame, for [HeadTrackerConfig.lookAwayReleaseMs]. A face well
 * below the calibrated centre (looking down at the bike) is never counted as turned away. The
 * engine treats rejected frames as a lost face: hold, ease to centre, then `face lost`.
 *
 * Not thread-safe.
 */
class LookAwayGate(private val config: HeadTrackerConfig) {
    private var yawMin: Double? = null
    private var yawMax: Double? = null
    private var centre: CentreBaseline? = null
    private val recent = ArrayDeque<Pair<Long, Boolean>>()
    private var insideSinceMs: Long? = null

    /** Latched: the rider is looking away. */
    var lookingAway = false
        private set

    /** The calibrated yaw range and centre; null disables the gate. */
    fun setReference(yawMinDeg: Double?, yawMaxDeg: Double?, centre: CentreBaseline?) {
        yawMin = yawMinDeg
        yawMax = yawMaxDeg
        this.centre = centre
        reset()
    }

    private enum class Look { AT_SCREEN, YAW_OUT, PITCH_UP }

    private fun classify(face: FaceObservation, lo: Double, hi: Double, base: CentreBaseline): Look = when {
        face.cy - base.cy > config.lookAwayLowFaceDrop -> Look.AT_SCREEN
        face.yawDeg < lo - config.lookAwayYawMarginDeg || face.yawDeg > hi + config.lookAwayYawMarginDeg -> Look.YAW_OUT
        face.pitchDeg - base.pitchDeg > config.lookAwayPitchUpDeg -> Look.PITCH_UP
        else -> Look.AT_SCREEN
    }

    /**
     * True when [face] must not be used for steering: while latched, or on its own when its yaw
     * is out of range (a detector glitch or the start of a turn). A pitch-up frame on its own is
     * still used: fast sweeps tip the head up for a moment (run 4), so pitch only counts towards
     * latching.
     */
    fun reject(timestampMs: Long, face: FaceObservation): Boolean {
        val look = classify(face, yawMin ?: return false, yawMax ?: return false, centre ?: return false)
        val outside = look != Look.AT_SCREEN
        recent.addLast(timestampMs to outside)
        while (recent.isNotEmpty() && timestampMs - recent.first().first > config.lookAwayWindowMs) recent.removeFirst()
        if (!lookingAway) {
            val away = recent.count { it.second }
            if (away >= MIN_FRAMES && away >= config.lookAwayShare * recent.size) lookingAway = true
        }
        if (!lookingAway) return look == Look.YAW_OUT
        if (outside) {
            insideSinceMs = null
            return true
        }
        val back = insideSinceMs ?: timestampMs.also { insideSinceMs = it }
        if (timestampMs - back >= config.lookAwayReleaseMs) {
            lookingAway = false
            insideSinceMs = null
            recent.clear()
            return false
        }
        return true
    }

    /** A frame without a face: it doesn't count as looking back. */
    fun onNoFace() {
        insideSinceMs = null
    }

    fun reset() {
        lookingAway = false
        recent.clear()
        insideSinceMs = null
    }

    private companion object {
        const val MIN_FRAMES = 3
    }
}
