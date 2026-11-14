package dev.digitalducktape.openride.ui.profile

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.telemetry.Consent
import dev.digitalducktape.openride.core.telemetry.ConsentSource
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.TelemetryConsentStore
import dev.digitalducktape.openride.core.telemetry.TelemetryEnabled
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Launch destination (PRD P0-3/P0-8): grid of existing riders plus "Add rider." Selecting a
 * profile scopes the rest of the session to it via [ActiveProfileHolder].
 */
class ProfileSelectViewModel(
    private val profileRepository: ProfileRepository,
    private val activeProfileHolder: ActiveProfileHolder,
    private val telemetry: Telemetry,
    private val consentStore: TelemetryConsentStore,
) : ViewModel() {
    /** Exposed directly (no `stateIn`) — collected lifecycle-aware from the screen. */
    val profiles: Flow<List<Profile>> = profileRepository.observeProfiles()

    private val _showConsentPrompt = MutableStateFlow(consentStore.consent.value == Consent.Unasked)

    /** True while the rider hasn't answered the usage-data question (#85). */
    val showConsentPrompt: StateFlow<Boolean> = _showConsentPrompt.asStateFlow()

    /** Share: consent is stored first, so the event announcing it is actually sent. */
    fun onConsentShare() {
        consentStore.set(Consent.Granted)
        telemetry.track(TelemetryEnabled(ConsentSource.FIRST_RUN))
        _showConsentPrompt.value = false
    }

    /** No thanks, and dismissing the prompt: stored as Declined so it never asks again. */
    fun onConsentDecline() {
        consentStore.set(Consent.Declined)
        _showConsentPrompt.value = false
    }

    fun selectProfile(profileId: Long) {
        activeProfileHolder.setActiveProfile(profileId)
    }
}
