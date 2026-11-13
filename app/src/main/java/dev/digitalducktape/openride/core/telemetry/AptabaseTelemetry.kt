package dev.digitalducktape.openride.core.telemetry

import android.content.Context
import android.util.Log
import com.aptabase.Aptabase
import com.aptabase.InitOptions
import com.aptabase.TrackingMode

/** The wire to Aptabase, split out so tests never touch the SDK singleton. */
fun interface AptabaseClient {
    fun send(name: String, props: Map<String, Any>)
}

/**
 * The real client. The SDK is initialised lazily, on the first [send], so a rider who has not
 * opted in never starts it. [trackingMode] is always explicit: the SDK's own environment detection
 * would mislabel a debuggable release-like build. [Aptabase.trackEvent] posts to its own thread
 * pool, so this does not block the caller.
 */
class SdkAptabaseClient(
    context: Context,
    appKey: String,
    debugEvents: Boolean,
    appVersion: String,
    private val initializer: () -> Unit = {
        Aptabase.instance.initialize(
            context.applicationContext,
            appKey,
            InitOptions(
                trackingMode = if (debugEvents) TrackingMode.asDebug else TrackingMode.asRelease,
                appVersion = appVersion,
            ),
        )
    },
    private val tracker: (String, Map<String, Any>) -> Unit = { name, props ->
        Aptabase.instance.trackEvent(name, props)
    },
) : AptabaseClient {
    private val initialised by lazy { initializer(); true }

    override fun send(name: String, props: Map<String, Any>) {
        check(initialised)
        tracker(name, props)
    }
}

/** Sends events to [client] only while the rider has granted consent, read at each call. */
class AptabaseTelemetry(
    private val consent: TelemetryConsentStore,
    private val client: AptabaseClient,
) : Telemetry {
    override fun track(event: TelemetryEvent) {
        runCatching {
            if (consent.consent.value != Consent.Granted) return
            client.send(event.name, event.props())
            Log.d(TAG, "Telemetry: sent ${event.name}")
        }
    }

    private companion object {
        const val TAG = "Telemetry"
    }
}
