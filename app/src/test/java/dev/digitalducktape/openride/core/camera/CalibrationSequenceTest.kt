package dev.digitalducktape.openride.core.camera

import dev.digitalducktape.openride.core.camera.CalibrationSequence.Outcome
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CalibrationSequenceTest {

    private val config = HeadTrackerConfig()
    private val centreMs = config.centreSettleMs + config.centreCaptureMs
    private val extremeMs = config.extremeSettleMs + config.extremeCaptureMs

    private fun CalibrationSequence.run(script: FrameScript): List<Outcome> {
        val outcomes = script.frames.map { onFrame(it.timestampMs, it.face) }
        script.frames.clear()
        return outcomes
    }

    private fun fullLeanX() = CalibrationSequence(CalibrationSequence.stepsFor(TrackerMode.LEAN_X, centreOnly = false), config)

    @Test
    fun `steps are centre then left then right, plus in and back for lean_2d`() {
        assertEquals(
            listOf(CalibrationStep.CENTRE, CalibrationStep.LEFT, CalibrationStep.RIGHT),
            CalibrationSequence.stepsFor(TrackerMode.LEAN_X, centreOnly = false),
        )
        assertEquals(
            listOf(CalibrationStep.CENTRE, CalibrationStep.LEFT, CalibrationStep.RIGHT),
            CalibrationSequence.stepsFor(TrackerMode.LEAN_STAND, centreOnly = false),
        )
        assertEquals(
            listOf(
                CalibrationStep.CENTRE, CalibrationStep.LEFT, CalibrationStep.RIGHT,
                CalibrationStep.IN, CalibrationStep.BACK,
            ),
            CalibrationSequence.stepsFor(TrackerMode.LEAN_2D, centreOnly = false),
        )
        assertEquals(listOf(CalibrationStep.CENTRE), CalibrationSequence.stepsFor(TrackerMode.LEAN_2D, centreOnly = true))
    }

    @Test
    fun `the whole lean_x flow takes about eight seconds`() {
        assertEquals(8_000L, centreMs + 2 * extremeMs)
        assertEquals(3_000L, centreMs)
    }

    @Test
    fun `a steady rider completes with the median centre and the measured extremes`() {
        val seq = fullLeanX()
        val script = FrameScript()
            .hold(centreMs) { t -> SEATED.shifted(dx = bounce(t, 0.01, 1.5)) }
            .hold(extremeMs) { t -> if (t < 400) SEATED else SEATED.shifted(dx = LEFT_LEAN_DX) }
            .hold(extremeMs) { t -> if (t < 400) SEATED else SEATED.shifted(dx = RIGHT_LEAN_DX) }
            .hold(100, SEATED)
        val outcome = seq.run(script).last()

        val result = (outcome as Outcome.Completed).result
        assertEquals(SEATED.cx, result.centre.cx, 0.005)
        assertEquals(SEATED.size, result.centre.size, 1e-9)
        // Offsets from the (bouncing) centre's median.
        assertEquals(LEFT_LEAN_DX, result.leftDx!!, 0.005)
        assertEquals(RIGHT_LEAN_DX, result.rightDx!!, 0.005)
        assertNull(result.inRatio)
        assertNull(result.backRatio)
    }

    @Test
    fun `progress walks through each step with a rising fraction`() {
        val seq = fullLeanX()
        assertEquals(CalibrationStep.CENTRE, seq.progress.step)
        assertEquals(0.0, seq.progress.fraction, 0.0)

        seq.run(FrameScript().hold(1_500, SEATED))
        assertEquals(CalibrationStep.CENTRE, seq.progress.step)
        assertEquals(0.5, seq.progress.fraction, 0.02)
        assertEquals(0, seq.progress.stepIndex)
        assertEquals(3, seq.progress.stepCount)
        assertEquals(1, seq.progress.attempt)
        assertNull(seq.progress.retryReason)

        seq.run(FrameScript(1_500).hold(1_600, SEATED))
        assertEquals(CalibrationStep.LEFT, seq.progress.step)
        assertEquals(1, seq.progress.stepIndex)
    }

    @Test
    fun `an unstable centre is retried`() {
        val seq = fullLeanX()
        // sd of a +-0.06 sine is ~0.042 > 0.03.
        val script = FrameScript().hold(centreMs + 33) { t -> SEATED.shifted(dx = bounce(t, 0.06, 1.0)) }
        val outcomes = seq.run(script)

        assertTrue(outcomes.none { it is Outcome.Completed || it is Outcome.FailedNoFace })
        assertEquals(CalibrationStep.CENTRE, seq.progress.step)
        assertEquals(2, seq.progress.attempt)
        assertEquals(CalibrationRetryReason.UNSTABLE, seq.progress.retryReason)
    }

    @Test
    fun `wobble inside the stability limit is accepted`() {
        val seq = fullLeanX()
        // sd of a +-0.035 sine is ~0.025 < 0.03, comparable to the spike's sprint wobble.
        seq.run(FrameScript().hold(centreMs + 33) { t -> SEATED.shifted(dx = bounce(t, 0.035, 2.0)) })
        assertEquals(CalibrationStep.LEFT, seq.progress.step)
    }

    @Test
    fun `no face twice makes calibration fail`() {
        val seq = fullLeanX()
        val first = seq.run(FrameScript().hold(centreMs + 33, null))
        assertTrue(first.none { it is Outcome.FailedNoFace })
        assertEquals(CalibrationRetryReason.NO_FACE, seq.progress.retryReason)
        assertEquals(2, seq.progress.attempt)

        val second = seq.run(FrameScript(centreMs + 33).hold(centreMs + 33, null))
        assertTrue(second.last() is Outcome.FailedNoFace)
    }

    @Test
    fun `a face in under half the capture frames counts as no face`() {
        val seq = fullLeanX()
        seq.run(FrameScript().hold(centreMs + 33) { t -> if ((t / 33) % 3 == 0L) SEATED else null })
        assertEquals(CalibrationRetryReason.NO_FACE, seq.progress.retryReason)
    }

    @Test
    fun `one missed attempt then a good one completes`() {
        val seq = fullLeanX()
        val script = FrameScript()
            .hold(centreMs + 33, null)
            .hold(centreMs, SEATED)
            .hold(extremeMs, SEATED.shifted(dx = LEFT_LEAN_DX))
            .hold(extremeMs, SEATED.shifted(dx = RIGHT_LEAN_DX))
            .hold(100, SEATED)
        assertTrue(seq.run(script).last() is Outcome.Completed)
    }

    @Test
    fun `a lean that is too small is retried`() {
        val seq = fullLeanX()
        seq.run(FrameScript().hold(centreMs, SEATED).hold(extremeMs + 33, SEATED.shifted(dx = -0.02)))
        assertEquals(CalibrationStep.LEFT, seq.progress.step)
        assertEquals(CalibrationRetryReason.TOO_SMALL, seq.progress.retryReason)
        assertEquals(2, seq.progress.attempt)
    }

    @Test
    fun `leaning the same way twice is retried as the wrong direction`() {
        val seq = fullLeanX()
        seq.run(
            FrameScript()
                .hold(centreMs, SEATED)
                .hold(extremeMs, SEATED.shifted(dx = LEFT_LEAN_DX))
                .hold(extremeMs + 33, SEATED.shifted(dx = LEFT_LEAN_DX)),
        )
        assertEquals(CalibrationStep.RIGHT, seq.progress.step)
        assertEquals(CalibrationRetryReason.WRONG_DIRECTION, seq.progress.retryReason)
    }

    @Test
    fun `the extreme is measured after the settle time, not while the rider is still moving`() {
        val seq = fullLeanX()
        val script = FrameScript()
            .hold(centreMs, SEATED)
            // Arrives late but inside the settle window; the capture window only sees the lean.
            .hold(extremeMs) { t -> if (t < config.extremeSettleMs) SEATED else SEATED.shifted(dx = LEFT_LEAN_DX) }
            .hold(extremeMs, SEATED.shifted(dx = RIGHT_LEAN_DX))
            .hold(100, SEATED)
        val result = (seq.run(script).last() as Outcome.Completed).result
        assertEquals(LEFT_LEAN_DX, result.leftDx!!, 1e-6)
    }

    @Test
    fun `an overshooting lean calibrates to the lean the rider held, not the peak`() {
        // Recorded on the bike: the rider swung out to ~0.22 on arrival, then held ~0.15.
        // Here the swing fills 60% of the capture window, so a median would say 0.22.
        val seq = fullLeanX()
        val script = FrameScript()
            .hold(centreMs, SEATED)
            .hold(extremeMs) { t -> SEATED.shifted(dx = if (t < config.extremeSettleMs + 900) -0.22 else -0.15) }
            .hold(extremeMs, SEATED.shifted(dx = RIGHT_LEAN_DX))
            .hold(100, SEATED)
        val result = (seq.run(script).last() as Outcome.Completed).result
        assertEquals(-0.15, result.leftDx!!, 1e-6)
    }

    @Test
    fun `lean_2d measures in and back as face-size ratios`() {
        val seq = CalibrationSequence(CalibrationSequence.stepsFor(TrackerMode.LEAN_2D, centreOnly = false), config)
        val script = FrameScript()
            .hold(centreMs, SEATED)
            .hold(extremeMs, SEATED.shifted(dx = LEFT_LEAN_DX))
            .hold(extremeMs, SEATED.shifted(dx = RIGHT_LEAN_DX))
            .hold(extremeMs, SEATED.shifted(sizeRatio = 1.2))
            .hold(extremeMs, SEATED.shifted(sizeRatio = 0.85))
            .hold(100, SEATED)
        val result = (seq.run(script).last() as Outcome.Completed).result
        assertEquals(1.2, result.inRatio!!, 1e-6)
        assertEquals(0.85, result.backRatio!!, 1e-6)
    }

    @Test
    fun `sitting back when asked to lean in is the wrong direction`() {
        val seq = CalibrationSequence(CalibrationSequence.stepsFor(TrackerMode.LEAN_2D, centreOnly = false), config)
        seq.run(
            FrameScript()
                .hold(centreMs, SEATED)
                .hold(extremeMs, SEATED.shifted(dx = LEFT_LEAN_DX))
                .hold(extremeMs, SEATED.shifted(dx = RIGHT_LEAN_DX))
                .hold(extremeMs + 33, SEATED.shifted(sizeRatio = 0.85)),
        )
        assertEquals(CalibrationStep.IN, seq.progress.step)
        assertEquals(CalibrationRetryReason.WRONG_DIRECTION, seq.progress.retryReason)
    }

    @Test
    fun `centre-only calibration completes after three seconds without extremes`() {
        val seq = CalibrationSequence(CalibrationSequence.stepsFor(TrackerMode.LEAN_X, centreOnly = true), config)
        val result = (seq.run(FrameScript().hold(centreMs + 33, SEATED)).last() as Outcome.Completed).result
        assertNotNull(result.centre)
        assertNull(result.leftDx)
        assertNull(result.rightDx)
    }
}
