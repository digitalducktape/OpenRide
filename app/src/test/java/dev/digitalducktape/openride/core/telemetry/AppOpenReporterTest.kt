package dev.digitalducktape.openride.core.telemetry

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class AppOpenReporterTest {
    private val telemetry = RecordingTelemetry()

    private fun TestScope.reporter(consent: TelemetryConsentStore, profiles: Int = 2) = AppOpenReporter(
        telemetry = telemetry,
        consent = consent,
        profileCount = { profiles },
        scope = backgroundScope,
        tablet = Tablet.BIKE,
        firmware = Firmware.RQ_250113_A,
        flavor = Flavor.REAL,
    )

    @Test fun firesOncePerProcess() = runTest {
        val r = reporter(InMemoryTelemetryConsentStore(Consent.Granted))
        r.start()
        r.onForeground()
        r.onForeground()
        testScheduler.runCurrent()
        assertEquals(
            listOf(AppOpen(Tablet.BIKE, Firmware.RQ_250113_A, ProfilesBucket.TWO, Flavor.REAL)),
            telemetry.events,
        )
    }

    @Test fun notBeforeConsent() = runTest {
        for (c in listOf(Consent.Unasked, Consent.Declined)) {
            val r = reporter(InMemoryTelemetryConsentStore(c))
            r.start()
            r.onForeground()
            testScheduler.runCurrent()
        }
        assertEquals(emptyList<TelemetryEvent>(), telemetry.events)
    }

    @Test fun firesOnGrantThenNotAgainOnForeground() = runTest {
        val store = InMemoryTelemetryConsentStore(Consent.Unasked)
        val r = reporter(store)
        r.start()
        r.onForeground()
        testScheduler.runCurrent()
        assertEquals(0, telemetry.events.size)
        store.set(Consent.Granted)
        testScheduler.runCurrent()
        assertEquals(1, telemetry.events.size)
        r.onForeground()
        testScheduler.runCurrent()
        assertEquals(1, telemetry.events.size)
    }

    @Test fun grantedWhileBackgroundedWaitsForForeground() = runTest {
        val store = InMemoryTelemetryConsentStore(Consent.Unasked)
        val r = reporter(store)
        r.start()
        store.set(Consent.Granted)
        testScheduler.runCurrent()
        assertEquals(0, telemetry.events.size)
        r.onForeground()
        testScheduler.runCurrent()
        assertEquals(1, telemetry.events.size)
    }

    @Test fun aFailingProfileCountDoesNotCrashAndReportsOneProfile() = runTest {
        val r = AppOpenReporter(
            telemetry = telemetry,
            consent = InMemoryTelemetryConsentStore(Consent.Granted),
            profileCount = { throw IllegalStateException("migration failed") },
            scope = backgroundScope,
            tablet = Tablet.BIKE,
            firmware = Firmware.RQ_250113_A,
            flavor = Flavor.REAL,
        )
        r.start()
        r.onForeground()
        testScheduler.runCurrent()
        assertEquals(
            listOf(AppOpen(Tablet.BIKE, Firmware.RQ_250113_A, ProfilesBucket.ONE, Flavor.REAL)),
            telemetry.events,
        )
    }
}
