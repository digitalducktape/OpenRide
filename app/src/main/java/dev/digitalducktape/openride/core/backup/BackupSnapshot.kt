package dev.digitalducktape.openride.core.backup

import dev.digitalducktape.openride.core.data.GameResult
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideSample
import kotlinx.serialization.Serializable

/**
 * Serializable mirrors of the Room entities (PRD P1-8), kept as separate types rather than
 * annotating [Profile]/[Ride]/[RideSample] themselves with `@Serializable` — that keeps the
 * backup file's shape decoupled from Room's own annotations, so a future schema change on one
 * side (e.g. a Room migration) doesn't silently change the other.
 */
/**
 * @param avatarPhotoBase64 the rider's avatar photo bytes, base64-encoded — the photo itself
 *   rather than [Profile.avatarPhotoPath] (an install-specific path that would dangle on any
 *   other device/install). [BackupRepository] attaches it on export and re-materializes a
 *   photo file on restore.
 */
@Serializable
data class ProfileBackup(
    val id: Long,
    val name: String,
    val avatarEmoji: String,
    val avatarColor: Int,
    val weightKg: Double?,
    val ftp: Int?,
    val pairedHrDeviceAddress: String? = null,
    val avatarPhotoBase64: String? = null,
)

@Serializable
data class RideBackup(
    val id: Long,
    val profileId: Long,
    val startEpochMs: Long,
    val durationSec: Int,
    val avgCadence: Int,
    val maxCadence: Int,
    val avgPower: Int,
    val maxPower: Int,
    val avgResistance: Int,
    val outputKj: Double,
    val calories: Int?,
    val videoId: String? = null,
    val gamePlan: String? = null,
)

@Serializable
data class RideSampleBackup(
    val rideId: Long,
    val tSec: Int,
    val cadence: Int,
    val resistance: Int,
    val power: Int,
    val heartRateBpm: Int? = null,
)

// avatarPhotoPath deliberately doesn't round-trip here: the path is install-specific, so
// BackupRepository swaps it for the photo *bytes* (avatarPhotoBase64) on export and writes a
// fresh file (new path) on restore.
fun Profile.toBackup() = ProfileBackup(id, name, avatarEmoji, avatarColor, weightKg, ftp, pairedHrDeviceAddress)
fun ProfileBackup.toEntity() = Profile(id, name, avatarEmoji, avatarColor, weightKg, ftp, pairedHrDeviceAddress)

fun Ride.toBackup() = RideBackup(
    id, profileId, startEpochMs, durationSec, avgCadence, maxCadence, avgPower, maxPower, avgResistance, outputKj, calories, videoId, gamePlan,
)
fun RideBackup.toEntity() = Ride(
    id, profileId, startEpochMs, durationSec, avgCadence, maxCadence, avgPower, maxPower, avgResistance, outputKj, calories, videoId, gamePlan,
)

/** A mini-games segment result (#35). */
@Serializable
data class GameResultBackup(
    val rideId: Long,
    val segmentIndex: Int,
    val gameId: String,
    val role: String,
    val difficulty: String,
    val startSec: Int,
    val durationSec: Int,
    val score: Double,
    val stars: Int,
    val won: Boolean?,
    val skipped: Boolean,
    val statsJson: String,
    /** Added with schema 7; older backups read as `""`. */
    val variant: String = "",
)

fun GameResult.toBackup() = GameResultBackup(
    rideId, segmentIndex, gameId, role, difficulty, startSec, durationSec, score, stars, won, skipped, statsJson, variant,
)
fun GameResultBackup.toEntity() = GameResult(
    rideId, segmentIndex, gameId, role, difficulty, startSec, durationSec, score, stars, won, skipped, statsJson, variant,
)

fun RideSample.toBackup() = RideSampleBackup(rideId, tSec, cadence, resistance, power, heartRateBpm)
fun RideSampleBackup.toEntity() = RideSample(rideId, tSec, cadence, resistance, power, heartRateBpm)

/**
 * A full-database snapshot (PRD P1-8): every profile, ride, per-second sample and game result, plus a
 * [version] field so a future format change can be detected and handled deliberately rather
 * than silently misparsed (PRD's explicit "version field in the format" requirement).
 */
@Serializable
data class BackupSnapshot(
    val version: Int = CURRENT_VERSION,
    val exportedAtEpochMs: Long,
    val profiles: List<ProfileBackup>,
    val rides: List<RideBackup>,
    val samples: List<RideSampleBackup>,
    /** Mini-games results (#35). Absent from older files, which read as none. */
    val gameResults: List<GameResultBackup> = emptyList(),
) {
    companion object {
        const val CURRENT_VERSION = 1
    }
}
