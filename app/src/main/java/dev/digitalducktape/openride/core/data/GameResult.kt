package dev.digitalducktape.openride.core.data

import androidx.room.ColumnInfo
import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index

/**
 * One segment's result in a mini-games session (#35): a game's `segment_finished`, or the zero
 * result Kotlin records when a game doesn't report in time. A session records as one [Ride]
 * (its [Ride.gamePlan] says which plan) plus one row here per segment played or skipped.
 * Added in schema version 6 ([MIGRATION_5_6]).
 *
 * The enum-like columns hold the Bridge contract's wire words (docs/GAMES.md), so rows read the
 * same as the JSON the games sent.
 *
 * @param segmentIndex 0-based position in the session plan.
 * @param role `warmup`, `work`, `recovery`, `cooldown` or `free` (a Just Ride).
 * @param difficulty `easy`, `standard` or `hard`.
 * @param startSec ride seconds (the session clock, pauses excluded) when the segment started,
 *   intro card included.
 * @param durationSec gameplay seconds actually played, intro card excluded.
 * @param won null for games without a winner.
 * @param statsJson the game's `stats` object as JSON text (`effort_avg`, `played_sec`, …).
 * @param variant the game's own variant, such as Dodge Ball's `catch` mode, or `""`. Bests and
 *   leaderboards are kept per variant. Added in schema version 7 ([MIGRATION_6_7]).
 */
@Entity(
    tableName = "game_results",
    primaryKeys = ["rideId", "segmentIndex"],
    foreignKeys = [
        ForeignKey(
            entity = Ride::class,
            parentColumns = ["id"],
            childColumns = ["rideId"],
            onDelete = ForeignKey.CASCADE,
        ),
    ],
    indices = [Index("gameId")],
)
data class GameResult(
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
    @ColumnInfo(defaultValue = "") val variant: String = "",
)
