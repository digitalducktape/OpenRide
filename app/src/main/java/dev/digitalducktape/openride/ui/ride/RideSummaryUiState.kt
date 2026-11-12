package dev.digitalducktape.openride.ui.ride

import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideSample
import dev.digitalducktape.openride.games.session.GameLabels
import dev.digitalducktape.openride.ui.common.TimeFormat
import dev.digitalducktape.openride.ui.designsystem.component.OrStatValue

/**
 * Everything the Ride summary draws, in one value, gathered from [RideSummaryViewModel]'s flows
 * by `RideSummaryRoute`. [ride] is `null` until it has loaded from Room.
 */
data class RideSummaryUiState(
    val ride: Ride? = null,
    val samples: List<RideSample> = emptyList(),
    /** "Demo · 20 min" for a game ride (#35), else null. */
    val gameBadge: String? = null,
    val gameResults: List<GameLabels.ResultRow> = emptyList(),
    /** Suggested FTP in watts, or `null` for a ride under 20 minutes. */
    val suggestedFtp: Int? = null,
    val ftpApplied: Boolean = false,
) {
    /** The tabs to offer: heart rate only when the ride recorded any. */
    val metrics: List<RideMetric> get() = RideMetric.available(samples)

    /** The right-hand column (games, FTP suggestion) only shows when it has something. */
    val hasSideColumn: Boolean get() = gameResults.isNotEmpty() || suggestedFtp != null

    companion object {
        /** The delete confirmation's body (#84): what goes, and that it can't come back. */
        const val DELETE_WARNING =
            "It leaves your history, totals and personal records, along with its graph and any game results. This can't be undone."

        /** "45:12 · 380 kcal", or the output in kJ when the bike gave no calories. */
        fun subtitle(ride: Ride): String =
            "${TimeFormat.elapsed(ride.durationSec)} · " + (ride.calories?.let { "$it kcal" } ?: "%.0f kJ".format(ride.outputKj))

        /** The headline stats for [metric] as the design system's stat values. */
        fun stats(metric: RideMetric, ride: Ride, samples: List<RideSample>): List<OrStatValue> =
            RideMetricStats.stats(metric, ride, samples).map { OrStatValue(it.label, it.value, it.unit) }
    }
}
