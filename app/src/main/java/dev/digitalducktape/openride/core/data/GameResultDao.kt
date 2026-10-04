package dev.digitalducktape.openride.core.data

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import kotlinx.coroutines.flow.Flow

/** One row of [GameResultDao.observePersonalBests]: a rider's best at one game, plan and difficulty. */
data class GamePersonalBest(
    val gameId: String,
    /** The ride's [Ride.gamePlan], which carries the Just Ride mode and length. */
    val gamePlan: String,
    val difficulty: String,
    val bestScore: Double,
    val bestStars: Int,
    val plays: Int,
    /** The game's variant ([GameResult.variant]), `""` for games without one. */
    val variant: String = "",
)

/** One row of [GameResultDao.leaderboard]: one household rider's best at a game. */
data class LeaderboardEntry(
    val profileId: Long,
    val profileName: String,
    val bestScore: Double,
    val bestStars: Int,
)

/** A rider's best whole session of one plan (all its segments summed), or nulls if none yet. */
data class PlanBest(
    val bestScore: Double?,
    val bestStars: Int?,
)

/**
 * Mini-games results (#35). Skipped segments never count towards a best: they score 0 and
 * would only crowd the leaderboard with riders who never played.
 */
@Dao
interface GameResultDao {
    @Insert
    suspend fun insertAll(results: List<GameResult>)

    @Query("SELECT * FROM game_results WHERE rideId = :rideId ORDER BY segmentIndex ASC")
    suspend fun getForRide(rideId: Long): List<GameResult>

    /** The rider's personal bests: per game, per plan (mode and length) and per difficulty. */
    @Query(
        "SELECT g.gameId AS gameId, g.variant AS variant, r.gamePlan AS gamePlan, g.difficulty AS difficulty, " +
            "MAX(g.score) AS bestScore, MAX(g.stars) AS bestStars, COUNT(*) AS plays " +
            "FROM game_results g JOIN rides r ON r.id = g.rideId " +
            "WHERE r.profileId = :profileId AND g.skipped = 0 AND r.gamePlan IS NOT NULL " +
            "GROUP BY g.gameId, g.variant, r.gamePlan, g.difficulty " +
            "ORDER BY g.gameId, g.variant, r.gamePlan, g.difficulty",
    )
    fun observePersonalBests(profileId: Long): Flow<List<GamePersonalBest>>

    /**
     * The household leaderboard for [gameId] at [difficulty]: each rider's best score, highest
     * first. [gamePlan] narrows it to one plan (e.g. the 20-minute Just Ride); null takes every
     * plan the game was played in. [variant] keeps it to one variant of the game.
     */
    @Query(
        "SELECT p.id AS profileId, p.name AS profileName, " +
            "MAX(g.score) AS bestScore, MAX(g.stars) AS bestStars " +
            "FROM game_results g JOIN rides r ON r.id = g.rideId JOIN profiles p ON p.id = r.profileId " +
            "WHERE g.gameId = :gameId AND g.difficulty = :difficulty AND g.skipped = 0 " +
            "AND (:gamePlan IS NULL OR r.gamePlan = :gamePlan) AND g.variant = :variant " +
            "GROUP BY p.id ORDER BY bestScore DESC, p.name ASC LIMIT :limit",
    )
    suspend fun leaderboard(gameId: String, difficulty: String, gamePlan: String?, variant: String = "", limit: Int = 10): List<LeaderboardEntry>

    /**
     * The rider's best whole session of [gamePlan] at [difficulty], leaving out [excludeRideId]
     * (the ride just saved, so the summary can say whether it beat the old best). A non-null
     * [variant] only compares sessions played wholly in that variant (e.g. Dodge Ball's `catch`).
     */
    @Query(
        "SELECT MAX(totalScore) AS bestScore, MAX(totalStars) AS bestStars FROM (" +
            "SELECT SUM(g.score) AS totalScore, SUM(g.stars) AS totalStars " +
            "FROM game_results g JOIN rides r ON r.id = g.rideId " +
            "WHERE r.profileId = :profileId AND r.gamePlan = :gamePlan AND g.difficulty = :difficulty " +
            "AND r.id != :excludeRideId GROUP BY r.id " +
            "HAVING :variant IS NULL OR SUM(g.variant != :variant) = 0)",
    )
    suspend fun planBest(profileId: Long, gamePlan: String, difficulty: String, excludeRideId: Long, variant: String? = null): PlanBest

    // --- Backup & restore (PRD P1-8) --------------------------------------------------------

    @Query("SELECT * FROM game_results")
    suspend fun getAllOnce(): List<GameResult>

    /** A "did game results change?" signal for the automatic backup. */
    @Query("SELECT COUNT(*) FROM game_results")
    fun observeCount(): Flow<Int>

    @Query("DELETE FROM game_results")
    suspend fun deleteAll()
}
