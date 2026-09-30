package dev.digitalducktape.openride.core.backup

import androidx.room.RoomDatabase
import androidx.room.withTransaction
import dev.digitalducktape.openride.core.data.GameResultDao
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileDao
import dev.digitalducktape.openride.core.data.RideDao
import dev.digitalducktape.openride.core.profile.AvatarPhotoStore
import java.util.Base64
import kotlinx.serialization.SerializationException
import kotlinx.serialization.json.Json

/**
 * Backup & restore to one shareable file (PRD P1-8) — the tablet is otherwise a single point
 * of failure for years of ride history. Backs up every profile, ride, and per-second sample as
 * one JSON [BackupSnapshot]; restoring replaces the current database entirely inside one
 * transaction (all-or-nothing).
 *
 * **Not actually whole-database:** the `content_sources` table (a rider's added channels and
 * playlists, plus which built-ins they've hidden) is deliberately excluded from
 * [BackupSnapshot]. This is a deliberate design decision; the consequence: after a
 * reinstall + restore, rides and
 * profiles come back but any rider-added channels/playlists and hidden-state are silently
 * gone, reset to just the seeded built-in catalog.
 *
 * @param avatarPhotoStore where rider avatar photos live on disk. When provided, each
 *   profile's photo travels *inside* the backup as base64 bytes and is re-materialized as a
 *   fresh file on restore, so photos survive reinstalls the same way ride data does. `null`
 *   (tests without photo concerns) simply leaves photos out.
 * @param gameResultDao mini-games results (#35), which travel with their rides. `null` (tests
 *   that predate them) leaves them out of the snapshot and untouched on restore.
 */
class BackupRepository(
    private val database: RoomDatabase,
    private val profileDao: ProfileDao,
    private val rideDao: RideDao,
    private val avatarPhotoStore: AvatarPhotoStore? = null,
    private val gameResultDao: GameResultDao? = null,
    private val epochMillisProvider: () -> Long = System::currentTimeMillis,
) {
    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
    }

    /** Builds a snapshot of the database's current contents. */
    suspend fun createSnapshot(): BackupSnapshot = BackupSnapshot(
        exportedAtEpochMs = epochMillisProvider(),
        profiles = profileDao.getAllOnce().map { profile ->
            profile.toBackup().copy(avatarPhotoBase64 = encodePhoto(profile))
        },
        rides = rideDao.getAllRidesOnce().map { it.toBackup() },
        samples = rideDao.getAllSamplesOnce().map { it.toBackup() },
        gameResults = gameResultDao?.getAllOnce()?.map { it.toBackup() }.orEmpty(),
    )

    private fun encodePhoto(profile: Profile): String? = profile.avatarPhotoPath
        ?.let { path -> avatarPhotoStore?.readBytes(path) }
        ?.let { bytes -> Base64.getEncoder().encodeToString(bytes) }

    /** [createSnapshot] serialized to a JSON string ready to write to a shareable file. */
    suspend fun exportJson(): String = json.encodeToString(BackupSnapshot.serializer(), createSnapshot())

    /**
     * Parses [content] as a backup file. Throws [SerializationException] on malformed JSON, or
     * [IllegalArgumentException] (from [restore]) if its version is newer than this app
     * understands — callers should surface either as "this doesn't look like a valid OpenRide
     * backup" rather than attempting a partial restore.
     */
    fun parse(content: String): BackupSnapshot = json.decodeFromString(BackupSnapshot.serializer(), content)

    /**
     * Replaces the entire current database with [snapshot]'s contents. Deletes existing rows
     * (samples, then rides, then profiles — child tables first, regardless of whether foreign
     * key cascading is relied on) and re-inserts the snapshot's rows in parent-before-child
     * order (profiles, then rides, then samples), all inside one transaction so a failure
     * partway through can't leave a half-restored database.
     *
     * IDs are preserved exactly as backed up — Room only auto-generates a fresh id when an
     * autoGenerate primary key field is 0 — so every ride's `profileId` and every sample's
     * `rideId` still points at the right restored row afterward.
     */
    suspend fun restore(snapshot: BackupSnapshot) {
        require(snapshot.version <= BackupSnapshot.CURRENT_VERSION) {
            "Backup version ${snapshot.version} is newer than this app supports (${BackupSnapshot.CURRENT_VERSION})"
        }
        // Photo files are written before the DB transaction (file IO inside a Room transaction
        // is asking for trouble); a failed restore at worst leaves a few orphaned photo files.
        val restoredProfiles = snapshot.profiles.map { backup ->
            backup.toEntity().copy(avatarPhotoPath = restorePhoto(backup))
        }
        database.withTransaction {
            gameResultDao?.deleteAll()
            rideDao.deleteAllSamples()
            rideDao.deleteAllRides()
            profileDao.deleteAll()

            profileDao.insertAll(restoredProfiles)
            rideDao.insertRides(snapshot.rides.map { it.toEntity() })
            rideDao.insertSamples(snapshot.samples.map { it.toEntity() })
            gameResultDao?.insertAll(snapshot.gameResults.map { it.toEntity() })
        }
    }

    private fun restorePhoto(backup: ProfileBackup): String? = backup.avatarPhotoBase64
        ?.let { encoded -> runCatching { Base64.getDecoder().decode(encoded) }.getOrNull() }
        ?.let { bytes -> avatarPhotoStore?.saveBytes(bytes) }
}
