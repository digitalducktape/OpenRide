package dev.digitalducktape.openride.ui.profile

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.telemetry.Consent
import dev.digitalducktape.openride.core.telemetry.ConsentSource
import dev.digitalducktape.openride.core.telemetry.InMemoryTelemetryConsentStore
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.TelemetryEnabled
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProfileSelectViewModelTest {
    private lateinit var db: OpenRideDatabase
    private val telemetry = RecordingTelemetry()

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        db = Room.inMemoryDatabaseBuilder(context, OpenRideDatabase::class.java).build()
    }

    @After
    fun tearDown() = db.close()

    private fun viewModel(store: InMemoryTelemetryConsentStore): ProfileSelectViewModel {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        return ProfileSelectViewModel(ProfileRepository(db.profileDao()), ActiveProfileHolder(context), telemetry, store)
    }

    @Test
    fun promptShownWhenUnasked() {
        assertTrue(viewModel(InMemoryTelemetryConsentStore(Consent.Unasked)).showConsentPrompt.value)
    }

    @Test
    fun notShownWhenDecided() {
        assertFalse(viewModel(InMemoryTelemetryConsentStore(Consent.Granted)).showConsentPrompt.value)
        assertFalse(viewModel(InMemoryTelemetryConsentStore(Consent.Declined)).showConsentPrompt.value)
    }

    @Test
    fun shareSetsGrantedAndTracksFirstRun() {
        val store = InMemoryTelemetryConsentStore()
        val vm = viewModel(store)
        vm.onConsentShare()
        assertEquals(Consent.Granted, store.consent.value)
        assertEquals(listOf(TelemetryEnabled(ConsentSource.FIRST_RUN)), telemetry.events)
        assertFalse(vm.showConsentPrompt.value)
    }

    @Test
    fun declineAndDismissSetDeclinedAndTrackNothing() {
        val store = InMemoryTelemetryConsentStore()
        val vm = viewModel(store)
        vm.onConsentDecline()
        assertEquals(Consent.Declined, store.consent.value)
        assertTrue(telemetry.events.isEmpty())
        assertFalse(vm.showConsentPrompt.value)
    }
}
