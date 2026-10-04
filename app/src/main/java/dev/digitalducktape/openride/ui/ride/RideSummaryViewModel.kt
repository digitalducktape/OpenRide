package dev.digitalducktape.openride.ui.ride

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.data.RideSample
import dev.digitalducktape.openride.core.export.CsvExporter
import dev.digitalducktape.openride.core.export.TcxExporter
import dev.digitalducktape.openride.core.ride.FtpEstimator
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.games.session.GameLabels
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Post-ride summary (PRD P0-5), reused unmodified as history's detail view (T8): loads a
 * ride's aggregates *and* its full per-second sample series by [rideId] from Room, rather
 * than being handed the just-stopped [Ride] directly, so a fresh-off-the-bike ride and an
 * older ride tapped from history go through the exact same code path.
 *
 * Also surfaces an FTP suggestion (PRD P1-3): once the ride is at least 20 minutes long,
 * [FtpEstimator] proposes 95% of the ride's best 20-minute average power as an FTP update for
 * the rider who logged it, applied via [applySuggestedFtp].
 */
class RideSummaryViewModel(
    private val rideRepository: RideRepository,
    private val profileRepository: ProfileRepository,
    private val rideSessionManager: RideSessionManager,
    private val rideId: Long,
) : ViewModel() {
    private val _ride = MutableStateFlow<Ride?>(null)
    val ride: StateFlow<Ride?> = _ride.asStateFlow()

    private val _samples = MutableStateFlow<List<RideSample>>(emptyList())
    val samples: StateFlow<List<RideSample>> = _samples.asStateFlow()

    private val _gameResults = MutableStateFlow<List<GameLabels.ResultRow>>(emptyList())
    /** A game session's segment results (#35), ready to show; empty for any other ride. */
    val gameResults: StateFlow<List<GameLabels.ResultRow>> = _gameResults.asStateFlow()

    private val _gameBadge = MutableStateFlow<String?>(null)
    /** "Demo · 20 min" for a game ride, else null. */
    val gameBadge: StateFlow<String?> = _gameBadge.asStateFlow()

    private val _suggestedFtp = MutableStateFlow<Int?>(null)
    /** Suggested FTP in watts, or `null` if the ride is shorter than 20 minutes. */
    val suggestedFtp: StateFlow<Int?> = _suggestedFtp.asStateFlow()

    private val _ftpApplied = MutableStateFlow(false)
    /** `true` once [applySuggestedFtp] has successfully updated the rider's profile. */
    val ftpApplied: StateFlow<Boolean> = _ftpApplied.asStateFlow()

    suspend fun load() {
        _ride.value = rideRepository.getRide(rideId)
        _samples.value = rideRepository.getSamples(rideId)
        _gameBadge.value = GameLabels.planBadge(_ride.value?.gamePlan)
        _gameResults.value = GameLabels.resultRows(rideRepository.getGameResults(rideId))
        _suggestedFtp.value = FtpEstimator.estimateFtp(_samples.value)
    }

    /**
     * Applies [suggestedFtp] to the profile that logged this ride. No-op if the ride hasn't
     * loaded, there's no suggestion (ride under 20 minutes), or the profile has since been
     * deleted.
     */
    suspend fun applySuggestedFtp() {
        val ride = _ride.value ?: return
        val ftp = _suggestedFtp.value ?: return
        val profile = profileRepository.getProfile(ride.profileId) ?: return
        profileRepository.updateProfile(profile.copy(ftp = ftp))
        _ftpApplied.value = true
    }

    /**
     * TCX export (PRD P1-1) for the loaded ride, or `null` before [load] has populated
     * [ride]/[samples]. Pure/synchronous — the data is already in memory once loaded, so this
     * needs no suspend round-trip; the UI layer writes it to a file and shares it (see
     * [dev.digitalducktape.openride.ui.common.ExportShare]).
     */
    fun tcxContent(): String? = _ride.value?.let { r -> TcxExporter.export(r, _samples.value) }

    /** Per-second sample CSV (bonus alongside PRD P1-2's history CSV) for the loaded ride. */
    fun sampleCsvContent(): String? = _ride.value?.let { CsvExporter.exportRideSamples(_samples.value) }

    /**
     * Returns to [dev.digitalducktape.openride.core.ride.RideSessionState.Idle] if it was
     * sitting in [dev.digitalducktape.openride.core.ride.RideSessionState.Finished] (the
     * just-stopped-this-ride path) — a no-op otherwise (e.g. viewing an older ride from
     * history), since [RideSessionManager.reset] only acts on `Finished`.
     */
    fun dismiss() {
        rideSessionManager.reset()
    }
}
