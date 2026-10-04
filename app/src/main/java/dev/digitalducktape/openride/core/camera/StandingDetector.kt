package dev.digitalducktape.openride.core.camera

/** The seated, centred face measured by calibration's centre step. */
data class CentreBaseline(
    val cx: Double,
    val cy: Double,
    val size: Double,
    val pitchDeg: Double,
)

/**
 * Seated/standing with hysteresis. The standing posture is a face at least
 * [HeadTrackerConfig.standSizeRatio] times the seated size, not pitched down past
 * [HeadTrackerConfig.standMinPitchFromCentreDeg] from the seated pitch (so a knob glance never
 * counts), and not lower in the frame
 * than [HeadTrackerConfig.standMaxDrop] below the seated face (so leaning in or sitting down never
 * counts). It must hold for [HeadTrackerConfig.standEnterMs] to enter and be absent for
 * [HeadTrackerConfig.standExitMs] to exit. Frames without a face don't advance either timer.
 */
class StandingDetector(private val config: HeadTrackerConfig) {
    var standing: Boolean = false
        private set

    /** When standing was last entered, or null while seated. */
    var standingSinceMs: Long? = null
        private set

    private var changeSinceMs: Long? = null

    fun update(timestampMs: Long, face: FaceObservation, baseline: CentreBaseline): Boolean {
        val posture = looksStanding(face, baseline)
        if (posture == standing) {
            changeSinceMs = null
            return standing
        }
        val since = changeSinceMs ?: timestampMs.also { changeSinceMs = it }
        val needed = if (standing) config.standExitMs else config.standEnterMs
        if (timestampMs - since >= needed) {
            standing = posture
            standingSinceMs = if (posture) timestampMs else null
            changeSinceMs = null
        }
        return standing
    }

    fun reset() {
        standing = false
        standingSinceMs = null
        changeSinceMs = null
    }

    private fun looksStanding(face: FaceObservation, baseline: CentreBaseline): Boolean =
        face.size > baseline.size * config.standSizeRatio &&
            face.pitchDeg - baseline.pitchDeg > config.standMinPitchFromCentreDeg &&
            face.cy - baseline.cy <= config.standMaxDrop
}
