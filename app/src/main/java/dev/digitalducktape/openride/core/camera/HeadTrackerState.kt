package dev.digitalducktape.openride.core.camera

/**
 * One analysed camera frame's largest face, in the upright image's coordinates.
 *
 * @param cx face-box centre x as a fraction of frame width (0 = left edge of the image).
 * @param cy face-box centre y as a fraction of frame height (0 = top edge).
 * @param size face-box height as a fraction of frame height (grows as the rider comes closer).
 * @param pitchDeg head pitch in degrees; negative = looking down. Only compared with the
 *   calibrated centre's pitch, so a model's zero point doesn't matter (see [FaceGeometry]).
 * @param yawDeg head yaw in degrees (recorded in fixtures; the engine doesn't use it).
 */
data class FaceObservation(
    val cx: Double,
    val cy: Double,
    val size: Double,
    val pitchDeg: Double,
    val yawDeg: Double,
)

/**
 * What a game asks the head tracker for (bridge contract: `set_tracker_mode(mode)`). The camera
 * only runs while the mode is not [OFF].
 */
enum class TrackerMode(val wireName: String) {
    OFF("off"),

    /** Left/right lean only. */
    LEAN_X("lean_x"),

    /** Left/right plus the experimental in/back depth axis. */
    LEAN_2D("lean_2d"),

    /** Left/right lean, with the game also relying on standing detection. */
    LEAN_STAND("lean_stand"),
    ;

    companion object {
        fun fromWireName(name: String): TrackerMode? = entries.firstOrNull { it.wireName == name }
    }
}

/** Bridge input-frame field 9, `tracker_state`. [code] is the value sent to Godot. */
enum class TrackerState(val code: Int) {
    OFF(0),
    NEEDS_CALIBRATION(1),
    CALIBRATING(2),
    TRACKING(3),
    FACE_LOST(4),
}

/** The prompted calibration's steps, in order. [wireName] is the `step` of `calibration_progress`. */
enum class CalibrationStep(val wireName: String) {
    /** "Sit centred, look at the screen" (3-2-1). Re-taken every session. */
    CENTRE("centre"),

    /** "Lean comfortably left." */
    LEFT("left"),

    /** "Lean right." */
    RIGHT("right"),

    /** "Lean in" (`lean_2d` only). */
    IN("in"),

    /** "Sit back" (`lean_2d` only). */
    BACK("back"),
}

/** Why the current calibration step is being repeated, so the prompt can say what to fix. */
enum class CalibrationRetryReason(val wireName: String) {
    /** The centre wobbled more than the stability limit ("hold still"). */
    UNSTABLE("unstable"),

    /** No face in at least half the frames ("look at the screen"). */
    NO_FACE("no_face"),

    /** The lean was too small to calibrate against ("lean a bit further"). */
    TOO_SMALL("too_small"),

    /** Leaned the same way as the other side, or sat back when asked to lean in. */
    WRONG_DIRECTION("wrong_direction"),

    /**
     * Not a retry: the step failed [HeadTrackerConfig.maxAttemptsPerStep] times, so calibration
     * uses the previous (or default) value for it and moves on after a short notice ("we'll use
     * your usual lean").
     */
    USED_DEFAULT("used_default"),
}

/**
 * Drives the calibration UI that Godot draws (`calibration_progress(step, fraction)`).
 *
 * @param fraction 0..1 through the current step; restarts from 0 on a retry.
 * @param attempt 1 for the first try at this step, 2+ for retries.
 * @param retryReason set while repeating a step, null on its first attempt.
 */
data class CalibrationProgress(
    val step: CalibrationStep,
    val stepIndex: Int,
    val stepCount: Int,
    val fraction: Double,
    val attempt: Int,
    val retryReason: CalibrationRetryReason?,
)

/**
 * Why camera games can't run right now. The hub (#38) hides or explains camera games and
 * circuits (#37) substitute the next non-camera game of the same role.
 */
enum class UnavailableReason(val wireName: String) {
    /** The CAMERA runtime permission isn't granted (never asked yet, or denied). */
    PERMISSION_DENIED("permission_denied"),

    /** The rider turned camera games off in the hub. */
    CAMERA_GAMES_OFF("camera_games_off"),

    /** Calibration found no face after two tries. Cleared by the next calibration request. */
    NO_FACE("no_face"),

    /** The tablet has no usable camera, or opening it failed. Cleared by the next calibration request. */
    NO_CAMERA("no_camera"),
}

/**
 * Everything the bridge needs from the head tracker, as one immutable snapshot.
 *
 * Bridge input-frame fields: 6 = [leanX], 7 = [leanDepth], 8 = [standing] (as 0/1),
 * 9 = [trackerState]`.code`. [calibration] feeds `calibration_progress` while calibrating.
 *
 * @param leanX -1 (rider's left) .. +1 (right), filtered, calibrated, with a centre dead zone.
 * @param leanDepth -1 (sat back) .. +1 (leaning in); always 0 unless [mode] is `lean_2d` and depth
 *   was calibrated. Experimental: games treat it as a bonus, never a requirement.
 * @param unavailable non-null when camera games can't run; [trackerState] is then [TrackerState.OFF].
 */
data class HeadTrackerState(
    val mode: TrackerMode = TrackerMode.OFF,
    val trackerState: TrackerState = TrackerState.OFF,
    val leanX: Double = 0.0,
    val leanDepth: Double = 0.0,
    val standing: Boolean = false,
    /**
     * The lean before filtering and the dead zone (same units: ±1 = full lock, not clamped), for
     * debug logging and tuning; 0 when no face was measured. Not sent to games.
     */
    val rawLeanX: Double = 0.0,
    /**
     * Steps of the last calibration that fell back to previous or default values instead of a
     * measurement, so the UI can suggest recalibrating. Empty when everything was measured.
     */
    val calibrationDefaults: Set<CalibrationStep> = emptySet(),
    /**
     * The face is detected but turned away from the screen (see [LookAwayGate]); steering holds
     * and eases to centre as if the face were lost, and `trackerState` becomes `FACE_LOST` after
     * [HeadTrackerConfig.faceLostStateMs].
     */
    val lookingAway: Boolean = false,
    val calibration: CalibrationProgress? = null,
    val unavailable: UnavailableReason? = null,
) {
    /** [standing] as the bridge's 0/1 float. */
    val standingValue: Double get() = if (standing) 1.0 else 0.0
}
