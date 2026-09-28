package dev.digitalducktape.openride.core.camera

import android.content.Context
import android.hardware.camera2.CaptureRequest
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import androidx.annotation.OptIn
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The thin Android layer under [HeadTracker]: CameraX image analysis (no preview) at 320x240 into
 * ML Kit's bundled face detector, reporting the largest face per frame as a [FaceObservation].
 * Frames are analysed in memory and closed immediately; nothing is stored or sent.
 *
 * Settings proven on the Gen 2 tablet by the camera spike:
 * - The tablet has exactly one camera, rider-facing, whose HAL reports `LENS_FACING_BACK`; a
 *   front-camera selector finds nothing, so this takes whichever camera exists.
 * - Auto-exposure's default 5-30 fps range drags analysis to ~13 fps in room light; locking it to
 *   30-30 gives a steady 30 fps.
 * - 320x240, fast mode, min face 0.2: 9-20 ms per frame, ~65 ms capture-to-result, about one core.
 *
 * The camera is bound to the *process* lifecycle, so it also stops whenever the app is in the
 * background, whatever the tracker mode.
 */
class CameraXFaceSource(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner = ProcessLifecycleOwner.get(),
) : FaceSource {

    /** Rolling analysis rate and per-frame detection time, for the debug screen and logs. */
    data class Stats(val fps: Double = 0.0, val detectMs: Double = 0.0)

    private val _stats = MutableStateFlow(Stats())
    val stats: StateFlow<Stats> = _stats.asStateFlow()

    private val mainExecutor = ContextCompat.getMainExecutor(context)

    /**
     * One analysis thread for the source's (app-long) lifetime. Never shut down: ML Kit posts
     * completions to it after a stop, and a shut-down executor would reject them.
     */
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // Guarded by the main thread (start/stop hop there before touching them).
    private var analysis: ImageAnalysis? = null
    private var detector: FaceDetector? = null

    /** Frames from a stopped session are dropped by comparing generations. */
    @Volatile private var generation = 0
    @Volatile private var listener: FaceSource.Listener? = null

    // Stats, touched only on the analysis executor.
    private var windowStartMs = 0L
    private var windowFrames = 0
    private var windowDetectMs = 0L

    override fun start(listener: FaceSource.Listener) {
        val myGeneration = ++generation
        this.listener = listener
        mainExecutor.execute { bind(myGeneration, listener) }
    }

    override fun stop() {
        generation++
        listener = null
        mainExecutor.execute { unbind() }
    }

    @OptIn(ExperimentalCamera2Interop::class)
    private fun bind(myGeneration: Int, listener: FaceSource.Listener) {
        if (myGeneration != generation) return
        val providerFuture = ProcessCameraProvider.getInstance(context)
        providerFuture.addListener({
            if (myGeneration != generation) return@addListener
            try {
                val provider = providerFuture.get()
                val cameraInfo = provider.availableCameraInfos.firstOrNull()
                    ?: throw IllegalStateException("no camera on this device")

                val faceDetector = FaceDetection.getClient(
                    FaceDetectorOptions.Builder()
                        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                        .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
                        .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_NONE)
                        .setContourMode(FaceDetectorOptions.CONTOUR_MODE_NONE)
                        .setMinFaceSize(MIN_FACE_SIZE)
                        .build(),
                )
                val builder = ImageAnalysis.Builder()
                    .setTargetResolution(Size(ANALYSIS_WIDTH, ANALYSIS_HEIGHT))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                Camera2Interop.Extender(builder).setCaptureRequestOption(
                    CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                    Range(TARGET_FPS, TARGET_FPS),
                )
                val useCase = builder.build()
                useCase.setAnalyzer(analysisExecutor) { proxy -> analyze(proxy, faceDetector, myGeneration) }

                unbind()
                analysis = useCase
                detector = faceDetector
                analysisExecutor.execute { resetStats() }
                provider.bindToLifecycle(lifecycleOwner, cameraInfo.cameraSelector, useCase)
                Log.i(TAG, "camera bound: ${provider.availableCameraInfos.size} camera(s), facing=${cameraInfo.lensFacing}")
            } catch (e: Exception) {
                Log.w(TAG, "camera unavailable", e)
                unbind()
                if (myGeneration == generation) listener.onError(e)
            }
        }, mainExecutor)
    }

    private fun unbind() {
        val useCase = analysis ?: return
        analysis = null
        try {
            ProcessCameraProvider.getInstance(context).get().unbind(useCase)
        } catch (e: Exception) {
            Log.w(TAG, "unbind failed", e)
        }
        useCase.clearAnalyzer()
        val faceDetector = detector
        detector = null
        // Close on the analysis thread, behind any frame already queued there.
        analysisExecutor.execute { faceDetector?.close() }
    }

    @OptIn(ExperimentalGetImage::class)
    private fun analyze(proxy: ImageProxy, faceDetector: FaceDetector, myGeneration: Int) {
        val image = proxy.image
        if (image == null || myGeneration != generation) {
            proxy.close()
            return
        }
        val rotation = proxy.imageInfo.rotationDegrees
        // ML Kit reports boxes in upright coordinates.
        val uprightWidth = if (rotation == 90 || rotation == 270) proxy.height else proxy.width
        val uprightHeight = if (rotation == 90 || rotation == 270) proxy.width else proxy.height
        val timestampMs = proxy.imageInfo.timestamp / 1_000_000
        val detectStart = SystemClock.elapsedRealtime()

        faceDetector.process(InputImage.fromMediaImage(image, rotation))
            .addOnCompleteListener(analysisExecutor) { task ->
                try {
                    val face = if (task.isSuccessful) task.result.maxByOrNull(::area) else null
                    recordStats(SystemClock.elapsedRealtime() - detectStart)
                    val current = listener
                    if (current != null && myGeneration == generation) {
                        current.onFrame(timestampMs, face?.toObservation(uprightWidth, uprightHeight))
                    }
                } finally {
                    proxy.close()
                }
            }
    }

    private fun resetStats() {
        windowStartMs = 0L
        windowFrames = 0
        windowDetectMs = 0L
    }

    private fun recordStats(detectMs: Long) {
        val now = SystemClock.elapsedRealtime()
        if (windowStartMs == 0L) windowStartMs = now
        windowFrames++
        windowDetectMs += detectMs
        val elapsed = now - windowStartMs
        if (elapsed >= STATS_WINDOW_MS) {
            val stats = Stats(fps = windowFrames * 1000.0 / elapsed, detectMs = windowDetectMs.toDouble() / windowFrames)
            _stats.value = stats
            Log.i(TAG, "analysis %.1f fps, detect %.1f ms/frame".format(stats.fps, stats.detectMs))
            windowStartMs = now
            windowFrames = 0
            windowDetectMs = 0
        }
    }

    private fun area(face: Face) = face.boundingBox.width() * face.boundingBox.height()

    private fun Face.toObservation(width: Int, height: Int) = FaceObservation(
        cx = boundingBox.exactCenterX().toDouble() / width,
        cy = boundingBox.exactCenterY().toDouble() / height,
        size = boundingBox.height().toDouble() / height,
        pitchDeg = headEulerAngleX.toDouble(),
        yawDeg = headEulerAngleY.toDouble(),
    )

    companion object {
        /** Log tag; the bike logs at W, so `adb shell setprop log.tag.HeadTracker VERBOSE` first. */
        const val TAG = "HeadTracker"
        private const val ANALYSIS_WIDTH = 320
        private const val ANALYSIS_HEIGHT = 240
        private const val TARGET_FPS = 30
        private const val MIN_FACE_SIZE = 0.2f
        private const val STATS_WINDOW_MS = 5_000L
    }
}
