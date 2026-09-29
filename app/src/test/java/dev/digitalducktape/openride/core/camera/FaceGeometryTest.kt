package dev.digitalducktape.openride.core.camera

import dev.digitalducktape.openride.core.camera.FaceGeometry.Keypoints
import dev.digitalducktape.openride.core.camera.FaceGeometry.Point
import kotlin.math.sin
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FaceGeometryTest {

    /** A frontal face: eyes at y 0.40, mouth at 0.60, nose tip [nosePosition] of the way down. */
    private fun face(nosePosition: Double = FaceGeometry.NEUTRAL_NOSE_POSITION, noseDx: Double = 0.0) = Keypoints(
        rightEye = Point(0.45, 0.40),
        leftEye = Point(0.55, 0.40),
        noseTip = Point(0.50 + noseDx, 0.40 + 0.20 * nosePosition),
        mouth = Point(0.50, 0.60),
    )

    @Test
    fun `a frontal face has zero pitch and yaw`() {
        assertEquals(0.0, FaceGeometry.pitchFromKeypoints(face()), 1e-9)
        assertEquals(0.0, FaceGeometry.yawFromKeypoints(face()), 1e-9)
    }

    @Test
    fun `looking down reads as negative pitch, looking up as positive`() {
        // Pitching down by 22 degrees swings the nose tip towards the mouth.
        val down = face(nosePosition = FaceGeometry.NEUTRAL_NOSE_POSITION + FaceGeometry.NOSE_DEPTH_RATIO * sin(Math.toRadians(22.0)))
        assertEquals(-22.0, FaceGeometry.pitchFromKeypoints(down), 1e-6)
        val up = face(nosePosition = 0.4)
        assertTrue(FaceGeometry.pitchFromKeypoints(up) > 0)
    }

    @Test
    fun `turning the head moves yaw off zero with the nose`() {
        assertTrue(FaceGeometry.yawFromKeypoints(face(noseDx = 0.03)) > 10)
        assertTrue(FaceGeometry.yawFromKeypoints(face(noseDx = -0.03)) < -10)
    }

    @Test
    fun `degenerate keypoints give zero rather than NaN`() {
        val flat = Keypoints(Point(0.5, 0.5), Point(0.5, 0.5), Point(0.5, 0.5), Point(0.5, 0.5))
        assertEquals(0.0, FaceGeometry.pitchFromKeypoints(flat), 0.0)
        assertEquals(0.0, FaceGeometry.yawFromKeypoints(flat), 0.0)
        val extreme = face(nosePosition = 3.0)
        assertEquals(-90.0, FaceGeometry.pitchFromKeypoints(extreme), 1e-9)
    }
}
