package dev.digitalducktape.openride.core.camera

import kotlin.math.abs
import kotlin.math.sign
import kotlin.math.sqrt

/**
 * What a completed calibration measured. The extremes are null for steps that weren't run
 * (a centre-only session start reuses saved extremes).
 */
data class CalibrationResult(
    val centre: CentreBaseline,
    val leftDx: Double? = null,
    val rightDx: Double? = null,
    val inRatio: Double? = null,
    val backRatio: Double? = null,
    /** Steps that fell back to a previous or default value after too many attempts. */
    val usedDefaults: Set<CalibrationStep> = emptySet(),
)

/**
 * The prompted calibration as a pure state machine over camera frames. Godot draws the prompts
 * from [progress]; this class only decides when each step is done and what it measured.
 *
 * Each step lasts settle + capture time from its first frame. Frames in the settle window are
 * ignored (the rider is still moving into position); the capture window is then judged:
 * - fewer than [HeadTrackerConfig.minFaceFraction] face frames → retry, [CalibrationRetryReason.NO_FACE];
 *   the [HeadTrackerConfig.maxNoFaceAttempts]th such failure ends calibration with [Outcome.FailedNoFace]
 * - centre wobbling more than [HeadTrackerConfig.maxCentreSd] → retry, [CalibrationRetryReason.UNSTABLE]
 * - a lean too small, or towards the wrong side → retry with the matching reason
 * Any other failure retries the step up to [HeadTrackerConfig.maxAttemptsPerStep] attempts in
 * all. After that the step falls back instead of retrying forever: extremes from [fallback] (the
 * rider's previous calibration) or the config defaults, and for the centre [fallbackCentre] or
 * the median of its last attempt. The step then reports [CalibrationRetryReason.USED_DEFAULT] for
 * [HeadTrackerConfig.fallbackNoticeMs] before moving on, and the result lists it in
 * [CalibrationResult.usedDefaults], so a fallback is never silent.
 */
class CalibrationSequence(
    val steps: List<CalibrationStep>,
    private val config: HeadTrackerConfig,
    private val fallback: HeadCalibration? = null,
    private val fallbackCentre: CentreBaseline? = null,
) {
    sealed interface Outcome {
        data object InProgress : Outcome
        data class Completed(val result: CalibrationResult) : Outcome
        data object FailedNoFace : Outcome
    }

    init {
        require(steps.firstOrNull() == CalibrationStep.CENTRE) { "calibration always starts with the centre" }
    }

    private var stepIndex = 0
    private var attempt = 1
    private var retryReason: CalibrationRetryReason? = null
    private var stepStartMs: Long? = null
    private var lastFraction = 0.0
    private var noFaceFailures = 0
    private var captureFrames = 0
    private val captured = mutableListOf<FaceObservation>()

    private var centre: CentreBaseline? = null
    private var leftDx: Double? = null
    private var rightDx: Double? = null
    private var inRatio: Double? = null
    private var backRatio: Double? = null
    private val usedDefaults = mutableSetOf<CalibrationStep>()
    /** While a fallen-back step shows its notice: when the notice ends. */
    private var noticeUntilMs: Long? = null

    private var outcome: Outcome = Outcome.InProgress

    val progress: CalibrationProgress
        get() = CalibrationProgress(
            step = steps[stepIndex],
            stepIndex = stepIndex,
            stepCount = steps.size,
            fraction = lastFraction,
            attempt = attempt,
            retryReason = retryReason,
        )

    fun onFrame(timestampMs: Long, face: FaceObservation?): Outcome {
        if (outcome != Outcome.InProgress) return outcome

        val start = stepStartMs ?: timestampMs.also { stepStartMs = it }
        val step = steps[stepIndex]

        val noticeEnd = noticeUntilMs
        if (noticeEnd != null) {
            if (timestampMs < noticeEnd) {
                lastFraction = (1.0 - (noticeEnd - timestampMs).toDouble() / config.fallbackNoticeMs).coerceIn(0.0, 1.0)
                return Outcome.InProgress
            }
            noticeUntilMs = null
            return advance(timestampMs)
        }

        val settleMs = if (step == CalibrationStep.CENTRE) config.centreSettleMs else config.extremeSettleMs
        val captureMs = if (step == CalibrationStep.CENTRE) config.centreCaptureMs else config.extremeCaptureMs
        val elapsed = timestampMs - start
        val total = settleMs + captureMs

        if (elapsed < total) {
            lastFraction = (elapsed.toDouble() / total).coerceIn(0.0, 1.0)
            if (elapsed >= settleMs) {
                captureFrames++
                if (face != null) captured += face
            }
            return Outcome.InProgress
        }

        // The step's time is up: judge it. This frame is the first of whatever comes next.
        val failure = evaluate(step)
        if (failure == null) return advance(timestampMs)
        if (failure == CalibrationRetryReason.NO_FACE && ++noFaceFailures >= config.maxNoFaceAttempts) {
            outcome = Outcome.FailedNoFace
            return outcome
        }
        if (failure != CalibrationRetryReason.NO_FACE && attempt >= config.maxAttemptsPerStep) {
            useFallback(step)
            retryReason = CalibrationRetryReason.USED_DEFAULT
            noticeUntilMs = timestampMs + config.fallbackNoticeMs
            lastFraction = 0.0
            return Outcome.InProgress
        }
        attempt++
        retryReason = failure
        restartStep(timestampMs)
        return Outcome.InProgress
    }

    /** The current step is done (measured or fallen back): the next step, or the result. */
    private fun advance(timestampMs: Long): Outcome {
        if (stepIndex == steps.lastIndex) {
            outcome = Outcome.Completed(
                CalibrationResult(centre!!, leftDx, rightDx, inRatio, backRatio, usedDefaults.toSet()),
            )
            return outcome
        }
        stepIndex++
        attempt = 1
        retryReason = null
        restartStep(timestampMs)
        return Outcome.InProgress
    }

    private fun restartStep(timestampMs: Long) {
        stepStartMs = timestampMs
        lastFraction = 0.0
        captureFrames = 0
        captured.clear()
    }

    private fun useFallback(step: CalibrationStep) {
        usedDefaults += step
        when (step) {
            CalibrationStep.CENTRE -> centre = fallbackCentre ?: CentreBaseline(
                cx = median(captured.map { it.cx }),
                cy = median(captured.map { it.cy }),
                size = median(captured.map { it.size }),
                pitchDeg = median(captured.map { it.pitchDeg }),
            )
            CalibrationStep.LEFT -> leftDx = fallback?.leftDx ?: config.defaultLeftDx
            CalibrationStep.RIGHT -> rightDx = fallback?.rightDx ?: config.defaultRightDx
            CalibrationStep.IN -> inRatio = fallback?.inRatio
            CalibrationStep.BACK -> backRatio = fallback?.backRatio
        }
    }

    /** Returns null if [step] measured successfully (and records it), else why it must repeat. */
    private fun evaluate(step: CalibrationStep): CalibrationRetryReason? {
        if (captureFrames == 0 || captured.size < captureFrames * config.minFaceFraction) {
            return CalibrationRetryReason.NO_FACE
        }
        return when (step) {
            CalibrationStep.CENTRE -> {
                val xs = captured.map { it.cx }
                if (standardDeviation(xs) > config.maxCentreSd) return CalibrationRetryReason.UNSTABLE
                centre = CentreBaseline(
                    cx = median(xs),
                    cy = median(captured.map { it.cy }),
                    size = median(captured.map { it.size }),
                    pitchDeg = median(captured.map { it.pitchDeg }),
                )
                null
            }
            CalibrationStep.LEFT -> {
                val dx = sustained(captured.map { it.cx - centre!!.cx })
                if (abs(dx) < config.minLeanDx) return CalibrationRetryReason.TOO_SMALL
                leftDx = dx
                null
            }
            CalibrationStep.RIGHT -> {
                val dx = sustained(captured.map { it.cx - centre!!.cx })
                val left = leftDx
                if (left != null && sign(dx) == sign(left) && dx != 0.0) {
                    return CalibrationRetryReason.WRONG_DIRECTION
                }
                if (abs(dx) < config.minLeanDx) return CalibrationRetryReason.TOO_SMALL
                rightDx = dx
                null
            }
            CalibrationStep.IN -> {
                val ratio = 1.0 + sustained(captured.map { it.size / centre!!.size - 1.0 })
                when {
                    ratio <= 1.0 - config.minDepthDelta -> CalibrationRetryReason.WRONG_DIRECTION
                    ratio < 1.0 + config.minDepthDelta -> CalibrationRetryReason.TOO_SMALL
                    else -> null.also { inRatio = ratio }
                }
            }
            CalibrationStep.BACK -> {
                val ratio = 1.0 + sustained(captured.map { it.size / centre!!.size - 1.0 })
                when {
                    ratio >= 1.0 + config.minDepthDelta -> CalibrationRetryReason.WRONG_DIRECTION
                    ratio > 1.0 - config.minDepthDelta -> CalibrationRetryReason.TOO_SMALL
                    else -> null.also { backRatio = ratio }
                }
            }
        }
    }

    /**
     * The offset the rider *sustained* through the capture window: its direction is the median's,
     * its magnitude the [HeadTrackerConfig.extremeQuantile] quantile of the magnitudes in that
     * direction. The recorded rider swung out to ~0.22 of frame width on arrival and then held
     * 0.13-0.15; a median put full lock beyond the lean they actually held.
     */
    private fun sustained(offsets: List<Double>): Double {
        val direction = sign(median(offsets))
        if (direction == 0.0) return 0.0
        return direction * quantile(offsets.map { it * direction }, config.extremeQuantile)
    }

    companion object {
        /** The steps to run for [mode]; [centreOnly] when fresh saved extremes cover the mode. */
        fun stepsFor(mode: TrackerMode, centreOnly: Boolean): List<CalibrationStep> = when {
            centreOnly -> listOf(CalibrationStep.CENTRE)
            mode == TrackerMode.LEAN_2D -> listOf(
                CalibrationStep.CENTRE, CalibrationStep.LEFT, CalibrationStep.RIGHT,
                CalibrationStep.IN, CalibrationStep.BACK,
            )
            else -> listOf(CalibrationStep.CENTRE, CalibrationStep.LEFT, CalibrationStep.RIGHT)
        }
    }
}

internal fun median(values: List<Double>): Double {
    require(values.isNotEmpty())
    val sorted = values.sorted()
    val mid = sorted.size / 2
    return if (sorted.size % 2 == 1) sorted[mid] else (sorted[mid - 1] + sorted[mid]) / 2.0
}

/** Nearest-rank quantile, [q] in 0..1. */
internal fun quantile(values: List<Double>, q: Double): Double {
    require(values.isNotEmpty())
    val sorted = values.sorted()
    return sorted[(q.coerceIn(0.0, 1.0) * (sorted.size - 1)).toInt()]
}

internal fun standardDeviation(values: List<Double>): Double {
    if (values.size < 2) return 0.0
    val mean = values.average()
    return sqrt(values.sumOf { (it - mean) * (it - mean) } / values.size)
}
