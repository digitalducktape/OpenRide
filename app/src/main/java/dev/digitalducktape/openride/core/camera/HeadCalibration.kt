package dev.digitalducktape.openride.core.camera

import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.SerializationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * A rider's measured lean extremes, saved per profile and reused while fresh (the same local
 * day). The centre is deliberately *not* here: it is re-taken at the start of every session
 * because seating position changes, and an off-centre silent calibration was the spike's worst
 * failure.
 *
 * Extremes are offsets from that session's centre, so they stay valid when the centre moves.
 * Stored as JSON (see [toJson]) in `Profile.headCalibration`.
 *
 * @param leftDx face-x offset (frame widths) of a comfortable lean to the rider's left.
 * @param rightDx face-x offset of a comfortable lean to the right; opposite sign to [leftDx].
 * @param inRatio face size when leaning in, over the centre size (> 1). `lean_2d` only.
 * @param backRatio face size when sat back, over the centre size (< 1). `lean_2d` only.
 */
@Serializable
data class HeadCalibration(
    val version: Int = CURRENT_VERSION,
    val leftDx: Double,
    val rightDx: Double,
    val inRatio: Double? = null,
    val backRatio: Double? = null,
    val calibratedAtEpochMs: Long,
) {
    val hasDepth: Boolean get() = inRatio != null && backRatio != null

    /** Whether these extremes are enough for [mode] without a full calibration. */
    fun covers(mode: TrackerMode): Boolean = when (mode) {
        TrackerMode.OFF -> true
        TrackerMode.LEAN_X, TrackerMode.LEAN_STAND -> true
        TrackerMode.LEAN_2D -> hasDepth
    }

    /** Fresh = calibrated on the same local calendar day as [nowEpochMs]. */
    fun isFreshAt(nowEpochMs: Long, zone: ZoneId): Boolean =
        Instant.ofEpochMilli(calibratedAtEpochMs).atZone(zone).toLocalDate() ==
            Instant.ofEpochMilli(nowEpochMs).atZone(zone).toLocalDate()

    fun toJson(): String = json.encodeToString(serializer(), this)

    companion object {
        const val CURRENT_VERSION = 1

        private val json = Json {
            ignoreUnknownKeys = true
            encodeDefaults = true
        }

        /**
         * Parses [text] from `Profile.headCalibration`. Anything missing, malformed or written by
         * a newer schema reads as null (the rider simply calibrates again), never as an error.
         */
        fun fromJson(text: String?): HeadCalibration? {
            if (text.isNullOrBlank()) return null
            val parsed = try {
                json.decodeFromString(serializer(), text)
            } catch (_: SerializationException) {
                return null
            } catch (_: IllegalArgumentException) {
                return null
            }
            return parsed.takeIf { it.version == CURRENT_VERSION }
        }
    }
}

/**
 * Where [HeadCalibration]s live, per profile. Kept behind an interface because the Room column
 * (`Profile.headCalibration`, JSON via [HeadCalibration.toJson]) arrives with the single 5→6
 * migration owned by the sessions issue (#35); until then [InMemoryHeadCalibrationStore] keeps
 * them for the app's lifetime.
 */
interface HeadCalibrationStore {
    suspend fun load(profileId: Long): HeadCalibration?
    suspend fun save(profileId: Long, calibration: HeadCalibration)
}

class InMemoryHeadCalibrationStore : HeadCalibrationStore {
    private val byProfile = mutableMapOf<Long, HeadCalibration>()

    override suspend fun load(profileId: Long): HeadCalibration? = synchronized(byProfile) { byProfile[profileId] }

    override suspend fun save(profileId: Long, calibration: HeadCalibration) {
        synchronized(byProfile) { byProfile[profileId] = calibration }
    }
}
