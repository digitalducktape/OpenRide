package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import kotlin.math.asin

/**
 * Head angles estimated from BlazeFace's keypoints (MediaPipe Face Detector), which carry no
 * angles of their own. Pure, so it is unit-tested directly. Points are normalised to the upright
 * frame: x = 0 left edge .. 1 right edge, y = 0 top .. 1 bottom.
 *
 * These are estimates with a fixed face model, not a head pose: their zero depends on the rider
 * and the camera's height. The engine therefore only compares pitch with the calibrated centre's.
 */
object FaceGeometry {

    /** A normalised image point. */
    data class Point(val x: Double, val y: Double)

    /**
     * BlazeFace keypoints 0-3: the rider's right eye (the observer's left), left eye, nose tip and
     * mouth centre. The two ear points are unused.
     */
    data class Keypoints(val rightEye: Point, val leftEye: Point, val noseTip: Point, val mouth: Point)

    /** Where the nose tip sits between the eye line (0) and the mouth (1) when facing the camera. */
    const val NEUTRAL_NOSE_POSITION = 0.55

    /**
     * How far the nose tip moves along the eye-to-mouth span per unit sine of pitch: the tip
     * stands ~3 cm proud of a ~6.5 cm eye-to-mouth span on an adult face.
     */
    const val NOSE_DEPTH_RATIO = 0.45

    /**
     * Pitch in degrees, negative when looking down (ML Kit's sign). Looking down swings the
     * protruding nose tip towards the mouth in the image; looking up, towards the eyes.
     */
    fun pitchFromKeypoints(k: Keypoints): Double {
        val eyeY = (k.rightEye.y + k.leftEye.y) / 2
        val span = k.mouth.y - eyeY
        if (span <= 1e-6) return 0.0
        val position = (k.noseTip.y - eyeY) / span
        val sine = ((position - NEUTRAL_NOSE_POSITION) / NOSE_DEPTH_RATIO).coerceIn(-1.0, 1.0)
        return -Math.toDegrees(asin(sine))
    }

    /** Yaw in degrees, from the nose tip's offset from the eyes' midpoint relative to eye spacing. */
    fun yawFromKeypoints(k: Keypoints): Double {
        val eyeX = (k.rightEye.x + k.leftEye.x) / 2
        val spacing = abs(k.leftEye.x - k.rightEye.x)
        if (spacing <= 1e-6) return 0.0
        val sine = ((k.noseTip.x - eyeX) / spacing).coerceIn(-1.0, 1.0)
        return Math.toDegrees(asin(sine))
    }
}
