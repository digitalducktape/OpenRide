package dev.digitalducktape.openride.core.camera

/**
 * Every tunable in the head tracker, with defaults chosen from the camera spike's recording on
 * the Gen 2 bike (see `app/src/test/resources/headtracker/` and `HeadTrackerFixtureTest`).
 *
 * Lean is normalised before filtering: 0 = the calibrated centre, ±1 = full lock, which is
 * [fullLockFraction] of the rider's measured comfortable lean. Filter and dead-zone values are in
 * those units.
 */
data class HeadTrackerConfig(
    // --- filtering (One Euro, per axis) -------------------------------------------------------
    /**
     * Cutoff while the head is still. The spike's sprint wobble (sd ~0.02 of frame width, about
     * ±0.2 in lean units at pedal frequency) is attenuated ~4x at 0.5 Hz.
     */
    val filterMinCutoffHz: Double = 0.5,
    /**
     * How fast the cutoff rises with speed. 0.3 keeps bounce smooth while a deliberate lean
     * (several lean units per second) still arrives within ~100 ms of the raw signal.
     */
    val filterBeta: Double = 0.3,
    val filterDerivativeCutoffHz: Double = 1.0,
    /**
     * Centre dead zone, applied after filtering and rescaled so full lock is still ±1. 0.3 (about
     * 0.04 of frame width) removed all steering during the recorded knob glance and nearly all
     * during the sprint.
     */
    val deadZone: Double = 0.3,
    /** Full lock at 85% of each measured extreme, so reaching the screen edge is a comfortable lean. */
    val fullLockFraction: Double = 0.85,

    // --- calibration --------------------------------------------------------------------------
    /** Centre step: a short settle, then capture; 3 s in total ("3-2-1"). */
    val centreSettleMs: Long = 500,
    val centreCaptureMs: Long = 2_500,
    /** Each lean step: 1 s to get there (the spike's rider took 0.5-0.9 s), then capture. */
    val extremeSettleMs: Long = 1_000,
    val extremeCaptureMs: Long = 1_500,
    /**
     * Each extreme is the lean the rider sustained for (1 - this) of the capture window, not its
     * median or peak: on the bike the rider overshot on arrival and then relaxed ~20%, so the
     * median left full lock just out of reach (76% of held-lean frames at the edge vs 92% here).
     */
    val extremeQuantile: Double = 0.25,
    /** The centre must be stable: standard deviation of face x below this (frame widths). */
    val maxCentreSd: Double = 0.03,
    /** A step needs a face in at least this share of its capture frames. */
    val minFaceFraction: Double = 0.5,
    /** Smallest lean accepted as an extreme (frame widths; spike leans were 0.14-0.20). */
    val minLeanDx: Double = 0.04,
    /** Smallest in/back face-size change accepted as a depth extreme (ratio to centre size). */
    val minDepthDelta: Double = 0.04,
    /** Calibration gives up with [UnavailableReason.NO_FACE] after this many no-face attempts. */
    val maxNoFaceAttempts: Int = 2,

    // --- standing -----------------------------------------------------------------------------
    /** Standing: face larger than this multiple of the seated baseline... */
    val standSizeRatio: Double = 1.25,
    /**
     * ...with the head pitched down no further than this from the calibrated centre's pitch...
     *
     * Relative, not absolute, so it holds for any face model: the keypoint pitch estimate
     * ([FaceGeometry.pitchFromKeypoints]) and ML Kit's Euler angle disagree on where zero is.
     * On the recorded ride (ML Kit) the seated centre was -6.7°, a knob glance -22° (-15° from
     * centre) and standing -8° (-1.6° from centre); -8.5° from centre is the old absolute -15°.
     */
    val standMinPitchFromCentreDeg: Double = -8.5,
    /**
     * ...and the face no lower than this (fraction of frame height) below the seated baseline.
     * Standing raises the face; leaning in or sitting down lowers it. Without this guard the
     * recorded sit-down read as 1.4 s of standing.
     */
    val standMaxDrop: Double = 0.05,
    val standEnterMs: Long = 500,
    val standExitMs: Long = 1_000,

    // --- posture baselines --------------------------------------------------------------------
    /** Standing baseline = median face x over this long after standing is detected. */
    val postureLearnMs: Long = 1_000,
    /** Lean is measured from the standing baseline once standing has lasted this long. */
    val postureSwitchMs: Long = 2_000,

    // --- face lost ----------------------------------------------------------------------------
    val faceLostHoldMs: Long = 500,
    val faceLostEaseMs: Long = 500,
    val faceLostStateMs: Long = 3_000,

    // --- depth (experimental) -----------------------------------------------------------------
    /**
     * Depth reads 0 while the head is pitched further down than this from the calibrated centre
     * (knob glances); relative for the same reason as [standMinPitchFromCentreDeg].
     */
    val depthMinPitchFromCentreDeg: Double = -8.5,
)
