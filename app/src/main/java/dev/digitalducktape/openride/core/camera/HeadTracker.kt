package dev.digitalducktape.openride.core.camera

import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * Camera head tracking for the mini-games, as the bridge (#32) sees it: no CameraX types, just a
 * [state] snapshot and the bridge contract's commands.
 *
 * - Input frame fields 6-9 come from [state]: `leanX`, `leanDepth`, `standingValue`,
 *   `trackerState.code`.
 * - `calibration_progress(step, fraction, step_index, step_count, attempt, retry_reason)` comes
 *   from [HeadTrackerState.calibration] while `trackerState` is `CALIBRATING`.
 * - `set_tracker_mode(mode)` → [setMode], plus [calibrate] (`force = false`) for the first camera
 *   mode of a session.
 * - `request_calibration(mode)` (the rider tapped to recalibrate) → [calibrate] with `force = true`.
 *
 * The games bridge does all of this in `games/bridge/TrackerLink.kt`.
 *
 * The camera runs only while the mode is not `off` and nothing makes the tracker
 * [HeadTrackerState.unavailable]. Frames are analysed in memory and never stored or sent.
 */
interface HeadTracker {
    val state: StateFlow<HeadTrackerState>

    /** Turns the camera on for a camera game's mode, or off. Keeps this session's calibration. */
    fun setMode(mode: TrackerMode)

    /**
     * Runs the prompted calibration for [mode] (and switches to it). The centre is always re-taken;
     * the lean extremes are re-measured unless the active rider has same-day extremes covering
     * [mode] — or always when [force] (the rider asked to recalibrate). Clears a previous
     * `no_face` / `no_camera` failure so the rider can try again. Ignored for [TrackerMode.OFF].
     */
    fun calibrate(mode: TrackerMode, force: Boolean = false)

    /** Forgets the session's centre; the next camera game needs calibrating again. */
    fun resetSession()

    /** The hub's "camera games" setting (#38). Off makes the tracker unavailable. */
    fun setCameraGamesEnabled(enabled: Boolean)

    /** Re-checks the CAMERA permission, e.g. after the hub's permission request returns. */
    fun refreshPermission()
}

/**
 * A stream of analysed camera frames. The production implementation is [CameraXFaceSource];
 * tests use a fake. Implementations call the listener from any thread, in frame order.
 */
interface FaceSource {
    interface Listener {
        /** One analysed frame: its capture time (monotonic ms) and the largest face, if any. */
        fun onFrame(timestampMs: Long, face: FaceObservation?)

        /** The camera couldn't be opened or failed. The tracker then calls [stop]. */
        fun onError(error: Throwable)
    }

    fun start(listener: Listener)
    fun stop()
}

/**
 * The app's [HeadTracker]: wires a [FaceSource] to the [HeadTrackingEngine], decides when the
 * camera may run, and loads/saves each rider's extremes through [calibrationStore].
 *
 * @param activeProfileId whose extremes to reuse and save; null means calibrate fully every time
 *   and save nothing.
 * @param hasCameraPermission checked on every command and [refreshPermission].
 * @param scope runs store loads/saves. Pass a `TestScope`'s `backgroundScope` in tests.
 */
class DefaultHeadTracker(
    private val faceSource: FaceSource,
    private val calibrationStore: HeadCalibrationStore,
    private val activeProfileId: StateFlow<Long?>,
    private val hasCameraPermission: () -> Boolean,
    private val scope: CoroutineScope,
    config: HeadTrackerConfig = HeadTrackerConfig(),
    private val wallClockMs: () -> Long = System::currentTimeMillis,
    private val zone: () -> ZoneId = ZoneId::systemDefault,
    /**
     * Debug builds only: sees every analysed frame with the state it produced (raw vs filtered
     * lean), on the camera's thread. Null in release.
     */
    private val frameLog: ((timestampMs: Long, face: FaceObservation?, state: HeadTrackerState) -> Unit)? = null,
) : HeadTracker {

    private val lock = Any()
    private val engine = HeadTrackingEngine(config, wallClockMs, ::onFullCalibration)

    private val _state = MutableStateFlow(HeadTrackerState())
    override val state: StateFlow<HeadTrackerState> = _state.asStateFlow()

    private var cameraGamesEnabled = true
    private var cameraFailed = false
    private var cameraRunning = false
    private var permissionGranted = false

    /** The active rider's saved extremes, preloaded so [calibrate] can decide synchronously. */
    @Volatile private var savedForProfile: Pair<Long, HeadCalibration?>? = null

    private val frameListener = object : FaceSource.Listener {
        override fun onFrame(timestampMs: Long, face: FaceObservation?) {
            synchronized(lock) {
                if (!cameraRunning) return
                val next = engine.onFrame(timestampMs, face)
                frameLog?.invoke(timestampMs, face, next)
                // The per-frame fast path: nothing about availability changed.
                if (next.unavailable == null) {
                    _state.value = next
                    return
                }
            }
            refresh(recheckPermission = false)
        }

        override fun onError(error: Throwable) {
            // refresh() then calls stop() so the source releases whatever it did open.
            synchronized(lock) { cameraFailed = true }
            refresh(recheckPermission = false)
        }
    }

    init {
        scope.launch {
            activeProfileId.collect { id ->
                savedForProfile = id?.let { it to calibrationStore.load(it) }
            }
        }
        refresh()
    }

    override fun setMode(mode: TrackerMode) {
        synchronized(lock) { engine.setMode(mode) }
        refresh()
    }

    override fun calibrate(mode: TrackerMode, force: Boolean) {
        if (mode == TrackerMode.OFF) return
        val reuse = if (force) null else reusableExtremes(mode)
        synchronized(lock) {
            cameraFailed = false
            engine.startCalibration(mode, reuse, fallback = savedExtremes())
        }
        refresh()
    }

    override fun resetSession() {
        synchronized(lock) { engine.resetSession() }
        refresh()
    }

    override fun setCameraGamesEnabled(enabled: Boolean) {
        synchronized(lock) { cameraGamesEnabled = enabled }
        refresh()
    }

    override fun refreshPermission() = refresh()

    /** The active rider's saved extremes, however old: the fallback for a step that keeps failing. */
    private fun savedExtremes(): HeadCalibration? {
        val profileId = activeProfileId.value ?: return null
        val (loadedFor, saved) = savedForProfile ?: return null
        return saved.takeIf { loadedFor == profileId }
    }

    private fun reusableExtremes(mode: TrackerMode): HeadCalibration? {
        val profileId = activeProfileId.value ?: return null
        val (loadedFor, saved) = savedForProfile ?: return null
        if (loadedFor != profileId || saved == null) return null
        return saved.takeIf { it.isFreshAt(wallClockMs(), zone()) && it.covers(mode) }
    }

    private fun onFullCalibration(calibration: HeadCalibration) {
        val profileId = activeProfileId.value ?: return
        savedForProfile = profileId to calibration
        scope.launch { calibrationStore.save(profileId, calibration) }
    }

    /**
     * Recomputes availability, starts/stops the camera to match, and publishes [state]. The
     * permission check can be an IPC, so the frame path skips it.
     */
    private fun refresh(recheckPermission: Boolean = true) {
        val permission = if (recheckPermission) hasCameraPermission() else null
        var start = false
        var stop = false
        synchronized(lock) {
            if (permission != null) permissionGranted = permission
            val engineState = engine.state
            val unavailable = when {
                !cameraGamesEnabled -> UnavailableReason.CAMERA_GAMES_OFF
                !permissionGranted -> UnavailableReason.PERMISSION_DENIED
                cameraFailed -> UnavailableReason.NO_CAMERA
                else -> engineState.unavailable
            }
            val shouldRun = engineState.mode != TrackerMode.OFF && unavailable == null
            if (shouldRun && !cameraRunning) {
                cameraRunning = true
                engine.onCameraRestarted()
                start = true
            } else if (!shouldRun && cameraRunning) {
                cameraRunning = false
                stop = true
            }
            _state.value = if (shouldRun) {
                engine.state
            } else {
                HeadTrackerState(mode = engineState.mode, trackerState = TrackerState.OFF, unavailable = unavailable)
            }
        }
        // Outside the lock: a source may deliver frames (or errors) synchronously.
        if (stop) faceSource.stop()
        if (start) faceSource.start(frameListener)
    }
}
