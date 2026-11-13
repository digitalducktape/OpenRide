package dev.digitalducktape.openride.core.telemetry

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The rider's answer to the telemetry opt-in. Nothing is sent unless [Granted]. */
enum class Consent { Unasked, Granted, Declined }

interface TelemetryConsentStore {
    val consent: StateFlow<Consent>
    fun set(value: Consent)
}

/** A store that keeps the answer in memory, for tests. */
class InMemoryTelemetryConsentStore(initial: Consent = Consent.Unasked) : TelemetryConsentStore {
    private val state = MutableStateFlow(initial)
    override val consent: StateFlow<Consent> = state.asStateFlow()
    override fun set(value: Consent) {
        state.value = value
    }
}

/** The real store: SharedPreferences, so the answer survives restarts. */
class SharedPrefsTelemetryConsentStore(context: Context) : TelemetryConsentStore {
    private val prefs = context.applicationContext.getSharedPreferences("telemetry", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(read())
    override val consent: StateFlow<Consent> = state.asStateFlow()

    override fun set(value: Consent) {
        prefs.edit().putString(KEY_CONSENT, value.name).apply()
        state.value = value
    }

    private fun read(): Consent =
        prefs.getString(KEY_CONSENT, null)
            ?.let { saved -> Consent.entries.firstOrNull { it.name == saved } }
            ?: Consent.Unasked

    private companion object {
        const val KEY_CONSENT = "consent"
    }
}
