package dev.digitalducktape.openride.core.camera

/**
 * All of the head tracker's logic, with no Android or camera code: it turns a stream of
 * `(timestampMs, face or no face)` frames into [HeadTrackerState]. Time comes only from the frame
 * timestamps (monotonic milliseconds), so tests drive it with synthetic or recorded frames.
 *
 * Per frame, while tracking:
 * 1. [StandingDetector] updates seated/standing against the session's seated centre.
 * 2. Posture baseline: once standing has lasted [HeadTrackerConfig.postureSwitchMs], lean is
 *    measured from the median face x of standing's first [HeadTrackerConfig.postureLearnMs], so
 *    steering keeps working when the rider stands for a climb.
 * 3. Lean x = face-x offset → [AxisMapping] (full lock at 85% of each calibrated extreme) →
 *    [OneEuroFilter] → [deadZone].
 * 4. Depth (`lean_2d` with depth extremes only) = face size over the centre size, through the same
 *    chain. It reads 0 while standing or with the head pitched down (a knob glance).
 * With no face: hold the last output for [HeadTrackerConfig.faceLostHoldMs], ease to centre over
 * [HeadTrackerConfig.faceLostEaseMs], and report [TrackerState.FACE_LOST] after
 * [HeadTrackerConfig.faceLostStateMs].
 *
 * Not thread-safe: callers serialise access (see [DefaultHeadTracker]).
 *
 * @param wallClockMs stamps full calibrations for same-day reuse.
 * @param onFullCalibration receives each completed *full* calibration's extremes, for saving.
 */
class HeadTrackingEngine(
    val config: HeadTrackerConfig = HeadTrackerConfig(),
    private val wallClockMs: () -> Long = System::currentTimeMillis,
    private val onFullCalibration: (HeadCalibration) -> Unit = {},
) {
    var state: HeadTrackerState = HeadTrackerState()
        private set

    /** The extremes in use this session (saved or freshly measured), or null before calibrating. */
    var calibration: HeadCalibration? = null
        private set

    /** This session's seated centre, or null before the centre step has completed. */
    val sessionCentre: CentreBaseline? get() = centre

    private var mode = TrackerMode.OFF
    private var centre: CentreBaseline? = null
    private var sequence: CalibrationSequence? = null
    /** Saved extremes to adopt when a centre-only calibration completes. */
    private var pendingReuse: HeadCalibration? = null
    private var noFace = false

    private var leanAxis: AxisMapping? = null
    private var depthAxis: AxisMapping? = null
    private val leanFilter = newFilter()
    private val depthFilter = newFilter()
    private val standingDetector = StandingDetector(config)
    private val standingSamples = mutableListOf<Double>()
    private var standingCx: Double? = null

    private var lastFaceMs: Long? = null
    private var heldLean = 0.0
    private var heldDepth = 0.0
    private var faceLost = false

    fun setMode(newMode: TrackerMode) {
        if (newMode == mode) return
        val wasOff = mode == TrackerMode.OFF
        mode = newMode
        if (newMode == TrackerMode.OFF) {
            // Leaving a camera game cancels any calibration in progress but keeps the session
            // centre, so the next camera game in a circuit tracks straight away.
            sequence = null
            clearTracking()
        } else if (wasOff) {
            // The camera restarts after a gap; don't read the gap as a lost face.
            clearTracking()
        }
        publishIdle()
    }

    /**
     * Starts the prompted calibration for [mode]. If [reuse] (fresh saved extremes) covers the
     * mode, only the centre is re-taken; otherwise every step runs. Clears a previous no-face
     * failure.
     */
    fun startCalibration(mode: TrackerMode, reuse: HeadCalibration?) {
        if (mode == TrackerMode.OFF) return
        setMode(mode)
        val centreOnly = reuse != null && reuse.covers(mode)
        sequence = CalibrationSequence(CalibrationSequence.stepsFor(mode, centreOnly), config)
        pendingReuse = if (centreOnly) reuse else null
        noFace = false
        clearTracking()
        publishIdle()
    }

    /** Forgets this session's centre (and extremes), e.g. when a game session ends. */
    fun resetSession() {
        centre = null
        calibration = null
        leanAxis = null
        depthAxis = null
        sequence = null
        clearTracking()
        publishIdle()
    }

    /** Resets per-stream state after the camera (re)starts. */
    fun onCameraRestarted() {
        clearTracking()
    }

    fun onFrame(timestampMs: Long, face: FaceObservation?): HeadTrackerState {
        if (mode == TrackerMode.OFF) return state

        val seq = sequence
        if (seq != null) {
            when (val outcome = seq.onFrame(timestampMs, face)) {
                CalibrationSequence.Outcome.InProgress -> publishIdle()
                is CalibrationSequence.Outcome.Completed -> finishCalibration(outcome.result, timestampMs)
                CalibrationSequence.Outcome.FailedNoFace -> {
                    sequence = null
                    noFace = true
                    publishIdle()
                }
            }
            return state
        }

        if (centre == null || noFace) return state

        if (face == null) onNoFace(timestampMs) else onFace(timestampMs, face)
        return state
    }

    private fun finishCalibration(result: CalibrationResult, timestampMs: Long) {
        sequence = null
        centre = result.centre
        val extremes = pendingReuse ?: HeadCalibration(
            leftDx = result.leftDx!!,
            rightDx = result.rightDx!!,
            inRatio = result.inRatio,
            backRatio = result.backRatio,
            calibratedAtEpochMs = wallClockMs(),
        ).also(onFullCalibration)
        pendingReuse = null
        calibration = extremes
        leanAxis = AxisMapping.fromExtremes(extremes.leftDx, extremes.rightDx, config.fullLockFraction)
        depthAxis = if (extremes.hasDepth) {
            AxisMapping(
                minusOneExtreme = extremes.backRatio!! - 1.0,
                plusOneExtreme = extremes.inRatio!! - 1.0,
                fullLockFraction = config.fullLockFraction,
            )
        } else {
            null
        }
        clearTracking()
        lastFaceMs = timestampMs
        publishIdle()
    }

    private fun onFace(timestampMs: Long, face: FaceObservation) {
        val base = centre ?: return
        val axis = leanAxis ?: return
        val gap = lastFaceMs?.let { timestampMs - it } ?: 0L
        if (gap > config.faceLostHoldMs) {
            // Back after a real loss: start the filters fresh from where the head is now.
            leanFilter.reset()
            depthFilter.reset()
        }
        lastFaceMs = timestampMs
        faceLost = false

        val standing = standingDetector.update(timestampMs, face, base)
        val leanOriginX = postureOriginX(timestampMs, face, base, standing)

        val lean = deadZone(leanFilter.filter(timestampMs, axis.normalize(face.cx - leanOriginX)), config.deadZone, config.deadZoneRamp)

        val depthMapping = depthAxis
        val depth = if (mode == TrackerMode.LEAN_2D && depthMapping != null) {
            val gated = standing || face.pitchDeg - base.pitchDeg < config.depthMinPitchFromCentreDeg
            val raw = if (gated) 0.0 else depthMapping.normalize(face.size / base.size - 1.0)
            deadZone(depthFilter.filter(timestampMs, raw), config.deadZone, config.deadZoneRamp)
        } else {
            0.0
        }

        heldLean = lean
        heldDepth = depth
        state = HeadTrackerState(
            mode = mode,
            trackerState = TrackerState.TRACKING,
            leanX = lean,
            leanDepth = depth,
            standing = standing,
        )
    }

    /** The face x that reads as "no lean" right now: the seated centre, or the standing baseline. */
    private fun postureOriginX(timestampMs: Long, face: FaceObservation, base: CentreBaseline, standing: Boolean): Double {
        val since = standingDetector.standingSinceMs
        if (!standing || since == null) {
            standingSamples.clear()
            standingCx = null
            return base.cx
        }
        val standingFor = timestampMs - since
        if (standingCx == null) {
            if (standingFor < config.postureLearnMs) {
                standingSamples += face.cx
            } else if (standingSamples.isNotEmpty()) {
                standingCx = median(standingSamples)
            }
        }
        val learned = standingCx
        return if (learned != null && standingFor >= config.postureSwitchMs) learned else base.cx
    }

    private fun onNoFace(timestampMs: Long) {
        val last = lastFaceMs ?: timestampMs.also { lastFaceMs = it }
        val gap = timestampMs - last
        val scale = when {
            gap <= config.faceLostHoldMs -> 1.0
            gap >= config.faceLostHoldMs + config.faceLostEaseMs -> 0.0
            else -> 1.0 - (gap - config.faceLostHoldMs).toDouble() / config.faceLostEaseMs
        }
        if (gap >= config.faceLostStateMs && !faceLost) {
            faceLost = true
            standingDetector.reset()
            standingSamples.clear()
            standingCx = null
        }
        state = HeadTrackerState(
            mode = mode,
            trackerState = if (faceLost) TrackerState.FACE_LOST else TrackerState.TRACKING,
            leanX = heldLean * scale,
            leanDepth = heldDepth * scale,
            standing = standingDetector.standing,
        )
    }

    private fun clearTracking() {
        leanFilter.reset()
        depthFilter.reset()
        standingDetector.reset()
        standingSamples.clear()
        standingCx = null
        lastFaceMs = null
        heldLean = 0.0
        heldDepth = 0.0
        faceLost = false
    }

    /** Publishes the current mode/calibration status with zero outputs (no frame to measure yet). */
    private fun publishIdle() {
        val seq = sequence
        val trackerState = when {
            mode == TrackerMode.OFF -> TrackerState.OFF
            seq != null -> TrackerState.CALIBRATING
            centre == null || noFace -> TrackerState.NEEDS_CALIBRATION
            faceLost -> TrackerState.FACE_LOST
            else -> TrackerState.TRACKING
        }
        state = HeadTrackerState(
            mode = mode,
            trackerState = trackerState,
            calibration = seq?.progress,
            unavailable = if (noFace) UnavailableReason.NO_FACE else null,
        )
    }

    private fun newFilter() = OneEuroFilter(
        minCutoffHz = config.filterMinCutoffHz,
        beta = config.filterBeta,
        derivativeCutoffHz = config.filterDerivativeCutoffHz,
    )
}
