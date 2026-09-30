package dev.digitalducktape.openride.core.camera

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Matrix
import android.hardware.camera2.CaptureRequest
import android.os.SystemClock
import android.util.Log
import android.util.Range
import android.util.Size
import androidx.annotation.OptIn
import androidx.camera.camera2.interop.Camera2Interop
import androidx.camera.camera2.interop.ExperimentalCamera2Interop
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageProxy
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The thin Android layer under [HeadTracker]: CameraX image analysis (no preview) at 320x240,
 * each frame turned upright and handed to a [FaceAnalyzer] (MediaPipe, model bundled in the
 * APK's assets). Frames are analysed in memory and dropped; nothing is stored or sent.
 *
 * Settings proven on the Gen 2 tablet by the camera spike:
 * - The tablet has exactly one camera, rider-facing, whose HAL reports `LENS_FACING_BACK`; a
 *   front-camera selector finds nothing, so this takes whichever camera exists.
 * - Auto-exposure's default 5-30 fps range drags analysis to ~13 fps in room light; locking it to
 *   30-30 gives a steady 30 fps.
 *
 * The camera is bound to the *process* lifecycle, so it also stops whenever the app is in the
 * background, whatever the tracker mode.
 *
 * @param analyzerFactory creates the face model when the camera starts; it is closed when the
 *   camera stops, so its memory is only held while a camera game runs.
 */
class CameraXFaceSource(
    private val context: Context,
    private val lifecycleOwner: LifecycleOwner = ProcessLifecycleOwner.get(),
    @Volatile var analyzerFactory: (Context) -> FaceAnalyzer = ::MediaPipeFaceDetectorAnalyzer,
) : FaceSource {

    /** Rolling analysis rate and per-frame detection time, for the debug screen and logs. */
    data class Stats(val fps: Double = 0.0, val detectMs: Double = 0.0)

    private val _stats = MutableStateFlow(Stats())
    val stats: StateFlow<Stats> = _stats.asStateFlow()

    /**
     * Sees every frame the listener sees, just before it: the debug build's fixture logger
     * (numbers only). Null in normal use.
     */
    @Volatile var frameTap: ((timestampMs: Long, face: FaceObservation?) -> Unit)? = null

    private val mainExecutor = ContextCompat.getMainExecutor(context)

    /** One analysis thread for the source's (app-long) lifetime; the model only runs on it. */
    private val analysisExecutor: ExecutorService = Executors.newSingleThreadExecutor()

    // Guarded by the main thread (start/stop hop there before touching them).
    private var analysis: ImageAnalysis? = null

    /** Frames from a stopped session are dropped by comparing generations. */
    @Volatile private var generation = 0
    @Volatile private var listener: FaceSource.Listener? = null

    // Touched only on the analysis executor.
    private var analyzer: FaceAnalyzer? = null
    private var analyzerGeneration = -1
    private var frameBitmap: Bitmap? = null
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

                @Suppress("DEPRECATION") // ResolutionSelector needs CameraX 1.3's newer API; this is proven on the bike.
                val builder = ImageAnalysis.Builder()
                    .setTargetResolution(Size(ANALYSIS_WIDTH, ANALYSIS_HEIGHT))
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
                    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_RGBA_8888)
                Camera2Interop.Extender(builder).setCaptureRequestOption(
                    CaptureRequest.CONTROL_AE_TARGET_FPS_RANGE,
                    Range(TARGET_FPS, TARGET_FPS),
                )
                val useCase = builder.build()
                useCase.setAnalyzer(analysisExecutor) { proxy -> analyze(proxy, myGeneration, listener) }

                unbind()
                analysis = useCase
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
        // Release the model on the analysis thread, behind any frame already queued there.
        analysisExecutor.execute { closeAnalyzer() }
    }

    private fun analyze(proxy: ImageProxy, myGeneration: Int, listener: FaceSource.Listener) {
        try {
            if (myGeneration != generation) return
            val model = analyzerFor(myGeneration)
            val frame = upright(proxy)
            val timestampMs = proxy.imageInfo.timestamp / 1_000_000
            val detectStart = SystemClock.elapsedRealtime()
            val face = model.detect(frame, timestampMs)
            recordStats(SystemClock.elapsedRealtime() - detectStart)
            if (myGeneration == generation) {
                frameTap?.invoke(timestampMs, face)
                listener.onFrame(timestampMs, face)
            }
        } catch (e: Exception) {
            Log.w(TAG, "face analysis failed", e)
            if (myGeneration == generation) listener.onError(e)
        } finally {
            proxy.close()
        }
    }

    /** The model for this camera session, created on first use (on the analysis thread). */
    private fun analyzerFor(myGeneration: Int): FaceAnalyzer {
        val current = analyzer
        if (current != null && analyzerGeneration == myGeneration) return current
        closeAnalyzer()
        return analyzerFactory(context).also {
            analyzer = it
            analyzerGeneration = myGeneration
        }
    }

    private fun closeAnalyzer() {
        analyzer?.close()
        analyzer = null
        analyzerGeneration = -1
    }

    /** The frame as an upright RGBA bitmap, reusing one buffer when no rotation is needed. */
    private fun upright(proxy: ImageProxy): Bitmap {
        val plane = proxy.planes[0]
        val raw = if (plane.pixelStride == 4 && plane.rowStride == proxy.width * 4) {
            val reuse = frameBitmap?.takeIf { it.width == proxy.width && it.height == proxy.height }
                ?: Bitmap.createBitmap(proxy.width, proxy.height, Bitmap.Config.ARGB_8888).also { frameBitmap = it }
            plane.buffer.rewind()
            reuse.copyPixelsFromBuffer(plane.buffer)
            reuse
        } else {
            proxy.toBitmap()
        }
        val rotation = proxy.imageInfo.rotationDegrees
        if (rotation == 0) return raw
        return Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, Matrix().apply { postRotate(rotation.toFloat()) }, false)
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

    companion object {
        /** Log tag; the bike logs at W, so `adb shell setprop log.tag.HeadTracker VERBOSE` first. */
        const val TAG = "HeadTracker"
        private const val ANALYSIS_WIDTH = 320
        private const val ANALYSIS_HEIGHT = 240
        private const val TARGET_FPS = 30
        private const val STATS_WINDOW_MS = 5_000L
    }
}
