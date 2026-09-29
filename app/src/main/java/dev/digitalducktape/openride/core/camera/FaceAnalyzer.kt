package dev.digitalducktape.openride.core.camera

import android.content.Context
import android.graphics.Bitmap
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.facedetector.FaceDetector

/**
 * Finds the rider's face in one upright camera frame. [CameraXFaceSource] owns the camera and
 * calls this on its analysis thread, one frame at a time, with increasing timestamps.
 */
interface FaceAnalyzer : AutoCloseable {
    /** The largest face in [frame] (already upright), or null. */
    fun detect(frame: Bitmap, timestampMs: Long): FaceObservation?
}

/**
 * MediaPipe Face Detector (BlazeFace short range, bundled in assets) in VIDEO mode, on the CPU:
 * a box and six keypoints per face, no head angles. Pitch and yaw are estimated from the
 * keypoints ([FaceGeometry.pitchFromKeypoints]); the engine only compares pitch with the
 * calibrated centre's, so the estimate's zero doesn't matter.
 *
 * Chosen over MediaPipe's Face Landmarker, whose transformation matrix gives a true head pose,
 * because on the Gen 2 tablet (MT8173) the landmarker took ~72 ms per 320x240 frame with a face
 * in view (13-14 fps), while this takes 17-26 ms and holds 30 fps with Godot rendering at 60.
 */
class MediaPipeFaceDetectorAnalyzer(context: Context) : FaceAnalyzer {
    private val detector = FaceDetector.createFromOptions(
        context,
        FaceDetector.FaceDetectorOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetPath(MODEL).setDelegate(Delegate.CPU).build())
            .setRunningMode(RunningMode.VIDEO)
            .build(),
    )

    override fun detect(frame: Bitmap, timestampMs: Long): FaceObservation? {
        val result = detector.detectForVideo(BitmapImageBuilder(frame).build(), timestampMs)
        val face = result.detections().maxByOrNull { it.boundingBox().width() * it.boundingBox().height() } ?: return null
        val box = face.boundingBox()
        val points = face.keypoints().orElse(null)
        val keypoints = if (points != null && points.size >= 4) {
            FaceGeometry.Keypoints(
                rightEye = FaceGeometry.Point(points[0].x().toDouble(), points[0].y().toDouble()),
                leftEye = FaceGeometry.Point(points[1].x().toDouble(), points[1].y().toDouble()),
                noseTip = FaceGeometry.Point(points[2].x().toDouble(), points[2].y().toDouble()),
                mouth = FaceGeometry.Point(points[3].x().toDouble(), points[3].y().toDouble()),
            )
        } else {
            null
        }
        return FaceObservation(
            cx = box.centerX().toDouble() / frame.width,
            cy = box.centerY().toDouble() / frame.height,
            size = box.height().toDouble() / frame.height,
            pitchDeg = keypoints?.let(FaceGeometry::pitchFromKeypoints) ?: 0.0,
            yawDeg = keypoints?.let(FaceGeometry::yawFromKeypoints) ?: 0.0,
        )
    }

    override fun close() = detector.close()

    companion object {
        /** From https://storage.googleapis.com/mediapipe-models/face_detector/blaze_face_short_range/float16/1/ */
        const val MODEL = "mediapipe/blaze_face_short_range.tflite"
    }
}
