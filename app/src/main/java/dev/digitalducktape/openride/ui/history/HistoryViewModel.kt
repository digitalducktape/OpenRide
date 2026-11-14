package dev.digitalducktape.openride.ui.history

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.export.CsvExporter
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.telemetry.ExportFormat
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.RideExport
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.trackSafely
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

/**
 * History tab (PRD P0-5): the active profile's rides, newest first. Queries
 * [RideRepository.observeHistory], which returns aggregate [dev.digitalducktape.openride.core.data.Ride]
 * rows only (no per-second samples) — the "100+ rides without jank" acceptance criterion is
 * satisfied by never touching the sample tables here, not by any paging in this view model.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class HistoryViewModel(
    activeProfileHolder: ActiveProfileHolder,
    rideRepository: RideRepository,
    private val telemetry: Telemetry = NoOpTelemetry,
) : ViewModel() {
    private val ridesFlow: Flow<List<Ride>> = activeProfileHolder.activeProfileId.flatMapLatest { profileId ->
        if (profileId == null) flowOf(emptyList()) else rideRepository.observeHistory(profileId)
    }

    val rows: Flow<List<RideHistoryRow>> = ridesFlow.map { rides -> rides.map(RideHistoryMapper::map) }

    /** Lifetime aggregates + personal records for the overview band (v2 metrics spec). */
    val stats: Flow<HistoryStats> = ridesFlow.map(HistoryStats::from)

    /** Local dates with at least one ride — the calendar's marked days. */
    val rideDates: Flow<Set<java.time.LocalDate>> = ridesFlow.map { HistoryStats.rideDates(it) }

    /**
     * Everything the screen draws, in one value that stays loaded while the tabs are shown
     * (`MainScaffold` creates this view model up front), so History appears whole on its first
     * frame instead of empty and then filled in. `null` only until the first database read.
     */
    val uiState: StateFlow<HistoryUiState?> = ridesFlow
        .map { rides ->
            HistoryUiState(
                rows = rides.map(RideHistoryMapper::map),
                stats = HistoryStats.from(rides),
                rideDates = HistoryStats.rideDates(rides),
            )
        }
        .stateIn(viewModelScope, SharingStarted.Eagerly, null)

    /**
     * CSV export of the active profile's full ride history (PRD P1-2), as it stands at the
     * moment of the call — a one-shot snapshot via [Flow.first], not a live subscription,
     * since exporting is a discrete user action.
     */
    suspend fun historyCsvContent(): String =
        CsvExporter.exportHistory(ridesFlow.first()).also { telemetry.trackSafely { RideExport(ExportFormat.CSV_HISTORY) } }
}

/** The History tab's state: [HistoryViewModel.uiState]. */
data class HistoryUiState(
    val rows: List<RideHistoryRow>,
    val stats: HistoryStats,
    val rideDates: Set<java.time.LocalDate>,
)
