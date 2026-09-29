package dev.digitalducktape.openride.core.camera

import kotlin.math.PI
import kotlin.math.sin

/** A rider sitting centred, looking at the screen — the spike's seated median on the Gen 2 tablet. */
internal val SEATED = FaceObservation(cx = 0.47, cy = 0.63, size = 0.29, pitchDeg = -6.0, yawDeg = -3.0)

/** Spike numbers: a comfortable lean moves the face this far (frame widths) from centre. */
internal const val LEFT_LEAN_DX = -0.16
internal const val RIGHT_LEAN_DX = 0.18

internal data class Frame(val timestampMs: Long, val face: FaceObservation?)

/**
 * Builds a synthetic camera timeline at 30 fps (one frame every 33 ms), segment by segment, so
 * tests read like the rider's script: "sit centred for 3 s, lean left for 2 s, ...".
 */
internal class FrameScript(startMs: Long = 0L, private val frameMs: Long = 33L) {
    var now: Long = startMs
        private set
    val frames = mutableListOf<Frame>()

    /** Emits frames for [durationMs]; [face] gets the time since this segment started. */
    fun hold(durationMs: Long, face: (elapsedMs: Long) -> FaceObservation?): FrameScript {
        val start = now
        val end = now + durationMs
        while (now < end) {
            frames += Frame(now, face(now - start))
            now += frameMs
        }
        return this
    }

    fun hold(durationMs: Long, face: FaceObservation?): FrameScript = hold(durationMs) { face }
}

internal fun FaceObservation.shifted(
    dx: Double = 0.0,
    dy: Double = 0.0,
    sizeRatio: Double = 1.0,
    pitchDeg: Double = this.pitchDeg,
): FaceObservation = copy(cx = cx + dx, cy = cy + dy, size = size * sizeRatio, pitchDeg = pitchDeg)

/** Pedal bounce: a sinusoidal side-to-side wobble of [amplitude] frame widths at [hz]. */
internal fun bounce(elapsedMs: Long, amplitude: Double, hz: Double): Double =
    amplitude * sin(2 * PI * hz * elapsedMs / 1000.0)

/** Feeds [frames] to the engine, returning the state after each one. */
internal fun HeadTrackingEngine.play(frames: List<Frame>): List<Pair<Frame, HeadTrackerState>> =
    frames.map { it to onFrame(it.timestampMs, it.face) }

internal fun HeadTrackingEngine.play(script: FrameScript): List<Pair<Frame, HeadTrackerState>> =
    play(script.frames)

/**
 * Runs a full prompted calibration for [mode] with a well-behaved synthetic rider: steady
 * centre, then comfortable left/right leans (and in/back for `lean_2d`). Returns the script so
 * callers can keep appending frames on the same clock.
 */
internal fun HeadTrackingEngine.calibrateSynthetic(
    mode: TrackerMode = TrackerMode.LEAN_X,
    script: FrameScript = FrameScript(),
    reuse: HeadCalibration? = null,
    inRatio: Double = 1.2,
    backRatio: Double = 0.85,
): FrameScript {
    setMode(mode)
    startCalibration(mode, reuse)
    val config = this.config
    val centreMs = config.centreSettleMs + config.centreCaptureMs
    val extremeMs = config.extremeSettleMs + config.extremeCaptureMs
    script.hold(centreMs, SEATED)
    if (reuse == null || !reuse.covers(mode)) {
        script.hold(extremeMs, SEATED.shifted(dx = LEFT_LEAN_DX))
        script.hold(extremeMs, SEATED.shifted(dx = RIGHT_LEAN_DX))
        if (mode == TrackerMode.LEAN_2D) {
            script.hold(extremeMs, SEATED.shifted(sizeRatio = inRatio))
            script.hold(extremeMs, SEATED.shifted(sizeRatio = backRatio))
        }
    }
    // One more frame lets the last step evaluate.
    script.hold(100, SEATED)
    play(script)
    script.frames.clear()
    check(state.trackerState == TrackerState.TRACKING) { "synthetic calibration did not finish: $state" }
    return script
}
