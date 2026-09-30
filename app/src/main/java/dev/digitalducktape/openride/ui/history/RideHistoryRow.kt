package dev.digitalducktape.openride.ui.history

import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.games.session.GameLabels
import dev.digitalducktape.openride.ui.common.TimeFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/** Display-ready row for the history list (PRD P0-5: date, duration, output kJ, avg cadence). */
data class RideHistoryRow(
    val rideId: Long,
    val dateLabel: String,
    val durationLabel: String,
    val outputKjLabel: String,
    val avgCadenceLabel: String,
    /** The game badge for a mini-games ride (#35), e.g. "Demo · 20 min"; null otherwise. */
    val gameBadge: String? = null,
)

/**
 * Pure mapping from a persisted [Ride] to its history-row display strings — kept separate
 * from [HistoryViewModel] so the formatting logic (date/duration/units) is plain-JUnit
 * testable without a Room/Robolectric dependency.
 */
object RideHistoryMapper {
    private val dateFormatter = DateTimeFormatter.ofPattern("MMM d, yyyy")

    fun map(ride: Ride, zoneId: ZoneId = ZoneId.systemDefault()): RideHistoryRow {
        val date = Instant.ofEpochMilli(ride.startEpochMs).atZone(zoneId).toLocalDate()
        return RideHistoryRow(
            rideId = ride.id,
            dateLabel = dateFormatter.format(date),
            durationLabel = TimeFormat.elapsed(ride.durationSec),
            outputKjLabel = "%.1f kJ".format(ride.outputKj),
            avgCadenceLabel = "${ride.avgCadence} rpm avg",
            gameBadge = GameLabels.planBadge(ride.gamePlan),
        )
    }
}
