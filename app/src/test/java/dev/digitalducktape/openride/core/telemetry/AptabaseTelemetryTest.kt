package dev.digitalducktape.openride.core.telemetry

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class AptabaseTelemetryTest {

    private class FakeClient(private val failWith: Throwable? = null) : AptabaseClient {
        val calls = mutableListOf<Pair<String, Map<String, Any>>>()
        override fun send(name: String, props: Map<String, Any>) {
            calls += name to props
            failWith?.let { throw it }
        }
    }

    private val rideStart = RideStart(RideType.JUST_RIDE, RideEntry.HOME_QUICK_START, route = false)
    private val rideEnd = RideEnd(
        RideType.JUST_RIDE, DurationBucket.M15_30, RideOutcome.SAVED, DiscardReason.NONE,
        HrState.CONNECTED, HrDropsBucket.ONE, SensorState.OK, RideMusic.OWN_MUSIC, true,
    )

    private fun telemetry(consent: Consent, client: AptabaseClient): Pair<AptabaseTelemetry, TelemetryConsentStore> {
        val store = InMemoryTelemetryConsentStore(consent)
        return AptabaseTelemetry(store, client) to store
    }

    @Test
    fun unaskedSendsNothing() {
        val client = FakeClient()
        telemetry(Consent.Unasked, client).first.track(rideStart)
        assertTrue(client.calls.isEmpty())
    }

    @Test
    fun declinedSendsNothing() {
        val client = FakeClient()
        telemetry(Consent.Declined, client).first.track(rideStart)
        assertTrue(client.calls.isEmpty())
    }

    @Test
    fun grantedSendsNameAndProps() {
        val client = FakeClient()
        telemetry(Consent.Granted, client).first.track(rideStart)
        assertEquals(listOf<Pair<String, Map<String, Any>>>(rideStart.name to rideStart.props()), client.calls)
    }

    @Test
    fun revokedMidRideSendsNothingAfter() {
        val client = FakeClient()
        val (t, store) = telemetry(Consent.Granted, client)
        t.track(rideStart)
        store.set(Consent.Declined)
        t.track(rideEnd)
        assertEquals(1, client.calls.size)
    }

    @Test
    fun clientThrowsIsSwallowed() {
        val client = FakeClient(RuntimeException("boom"))
        telemetry(Consent.Granted, client).first.track(rideStart)
        assertEquals(1, client.calls.size)
    }

    @Test
    fun sdkInitialisedOnlyAfterGrant() {
        var inits = 0
        val sent = mutableListOf<String>()
        val sdk = SdkAptabaseClient(
            context = ApplicationProvider.getApplicationContext(),
            appKey = "k", debugEvents = false, appVersion = "1",
            initializer = { inits++ },
            tracker = { name, _ -> sent += name },
        )
        val store = InMemoryTelemetryConsentStore(Consent.Unasked)
        val t = AptabaseTelemetry(store, sdk)

        t.track(rideStart)
        assertEquals(0, inits)
        store.set(Consent.Declined)
        t.track(rideStart)
        assertEquals(0, inits)
        store.set(Consent.Granted)
        t.track(rideStart)
        assertEquals(1, inits)
        t.track(rideEnd)
        assertEquals(1, inits)
        assertEquals(listOf("ride_start", "ride_end"), sent)
    }

    @Test
    fun sharedPrefsStoreRoundTrips() {
        val ctx = ApplicationProvider.getApplicationContext<android.content.Context>()
        val a = SharedPrefsTelemetryConsentStore(ctx)
        assertEquals(Consent.Unasked, a.consent.value)
        a.set(Consent.Granted)
        assertEquals(Consent.Granted, SharedPrefsTelemetryConsentStore(ctx).consent.value)
    }
}
