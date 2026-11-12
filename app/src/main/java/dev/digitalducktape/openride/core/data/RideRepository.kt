package dev.digitalducktape.openride.core.data

import androidx.room.RoomDatabase
import androidx.room.withTransaction
import dev.digitalducktape.openride.core.importer.ImportedWorkout
import kotlinx.coroutines.flow.Flow

/** What [RideRepository.importRides] did: rides added, and rides the profile already had. */
data class ImportOutcome(val imported: Int, val alreadyThere: Int)

/**
 * Persists finished rides and serves per-profile history.
 *
 * @param database the app's [RoomDatabase] instance, used only to open the transaction
 *   that [saveRide] needs to write the ride's aggregate row and its full sample series
 *   atomically (PRD T4 AC).
 * @param gameResultDao mini-games results (#35) for [getGameResults]; `null` (tests that don't
 *   involve games) reads every ride as having none.
 */
class RideRepository(
    private val database: RoomDatabase,
    private val rideDao: RideDao,
    private val gameResultDao: GameResultDao? = null,
) {
    /**
     * Writes [ride] and [samples] in a single transaction: either both land, or neither
     * does. [samples] are inserted with the ride's freshly generated id. Returns the
     * generated ride id.
     */
    suspend fun saveRide(ride: Ride, samples: List<RideSample>): Long =
        database.withTransaction {
            val rideId = rideDao.insertRide(ride)
            if (samples.isNotEmpty()) {
                rideDao.insertSamples(samples.map { it.copy(rideId = rideId) })
            }
            rideId
        }

    /** Newest-first ride history, scoped to a single profile. */
    fun observeHistory(profileId: Long): Flow<List<Ride>> = rideDao.observeHistory(profileId)

    /** Most recent take of each class this profile has ridden (v2 "taken" badges). */
    fun observeTakenVideos(profileId: Long): Flow<List<TakenVideo>> =
        rideDao.observeTakenVideos(profileId)

    suspend fun getRide(rideId: Long): Ride? = rideDao.getById(rideId)

    suspend fun getSamples(rideId: Long): List<RideSample> = rideDao.getSamples(rideId)

    /**
     * Deletes a ride for good (#84), with its per-second samples and any game results. History,
     * its totals and personal records, the Classes "taken" badges and the games' bests all read
     * the tables this removes from, so they follow without being told.
     */
    suspend fun deleteRide(rideId: Long) = rideDao.deleteRide(rideId)

    /**
     * Adds rides read from another service's workout history (#83) to [profileId]'s history, in
     * one transaction. A ride starting at the same moment as one the profile already has is
     * left out, so importing the same file twice adds nothing the second time.
     */
    suspend fun importRides(profileId: Long, workouts: List<ImportedWorkout>): ImportOutcome =
        database.withTransaction {
            val seen = rideDao.getStartTimes(profileId).toMutableSet()
            val fresh = workouts.filter { seen.add(it.startEpochMs) }
            if (fresh.isNotEmpty()) rideDao.insertRides(fresh.map { it.toRide(profileId) })
            ImportOutcome(imported = fresh.size, alreadyThere = workouts.size - fresh.size)
        }

    /** A game session's per-segment results, in plan order; empty for any other ride. */
    suspend fun getGameResults(rideId: Long): List<GameResult> = gameResultDao?.getForRide(rideId).orEmpty()
}
