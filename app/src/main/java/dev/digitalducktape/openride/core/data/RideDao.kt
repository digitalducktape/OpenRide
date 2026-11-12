package dev.digitalducktape.openride.core.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/**
 * Note: the "insert ride + samples in one transaction" requirement (PRD T4 AC) is
 * implemented in [RideRepository] via `RoomDatabase.withTransaction`, not with a
 * `@Transaction`-annotated default-body method here — Room's Kotlin DAO codegen needs
 * `-Xjvm-default` for default interface methods to work reliably with `@Transaction`,
 * which this project doesn't otherwise need, so the transaction boundary lives one layer
 * up instead.
 */
/** One row of [RideDao.observeTakenVideos]: a class and when it was last ridden. */
data class TakenVideo(val videoId: String, val lastTakenEpochMs: Long)

@Dao
interface RideDao {
    @Insert
    suspend fun insertRide(ride: Ride): Long

    @Insert
    suspend fun insertSamples(samples: List<RideSample>)

    @Query("SELECT * FROM rides WHERE profileId = :profileId ORDER BY startEpochMs DESC")
    fun observeHistory(profileId: Long): Flow<List<Ride>>

    @Query("SELECT * FROM rides WHERE id = :rideId")
    suspend fun getById(rideId: Long): Ride?

    @Query("SELECT * FROM ride_samples WHERE rideId = :rideId ORDER BY tSec ASC")
    suspend fun getSamples(rideId: Long): List<RideSample>

    /**
     * Deletes one ride. Its [RideSample]s and [GameResult]s go with it through their
     * `ON DELETE CASCADE` foreign keys. Returns the number of rides deleted (0 or 1).
     */
    @Query("DELETE FROM rides WHERE id = :rideId")
    suspend fun deleteById(rideId: Long): Int

    /** Total ride count across all profiles — a cheap "did ride data change?" signal for
     *  [dev.digitalducktape.openride.core.backup.AutoBackupManager] (samples only ever change
     *  together with their ride, so ride count covers both). */
    @Query("SELECT COUNT(*) FROM rides")
    fun observeRideCount(): Flow<Int>

    /** Most recent take of each class this profile has ridden (v2 "taken" badges). */
    @Query(
        "SELECT videoId, MAX(startEpochMs) AS lastTakenEpochMs FROM rides " +
            "WHERE profileId = :profileId AND videoId IS NOT NULL GROUP BY videoId",
    )
    fun observeTakenVideos(profileId: Long): Flow<List<TakenVideo>>

    // --- Backup & restore (PRD P1-8, T15) ---------------------------------------------------

    @Query("SELECT * FROM rides")
    suspend fun getAllRidesOnce(): List<Ride>

    @Query("SELECT * FROM ride_samples")
    suspend fun getAllSamplesOnce(): List<RideSample>

    /**
     * Bulk-inserts [rides] as-is, preserving each row's existing (non-zero) [Ride.id] — see
     * [ProfileDao.insertAll]'s doc for why this matters for a backup round-trip.
     */
    @Insert
    suspend fun insertRides(rides: List<Ride>)

    @Query("DELETE FROM rides")
    suspend fun deleteAllRides()

    @Query("DELETE FROM ride_samples")
    suspend fun deleteAllSamples()
}
