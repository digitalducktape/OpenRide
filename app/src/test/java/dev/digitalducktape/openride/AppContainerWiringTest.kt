package dev.digitalducktape.openride

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The container's lazy singletons can be built, in the order the app builds them. The heart-rate
 * manager and the ride session manager use each other's flows; touching one while building the
 * other looped forever and crashed the app on launch (2026-10-27).
 */
@RunWith(AndroidJUnit4::class)
class AppContainerWiringTest {

    @Test
    fun `the heart-rate manager builds first, as OpenRideApplication does`() {
        val container = AppContainer(ApplicationProvider.getApplicationContext())
        assertNotNull(container.heartRateManager)
        assertNotNull(container.rideSessionManager)
    }

    @Test
    fun `the ride session manager builds first`() {
        val container = AppContainer(ApplicationProvider.getApplicationContext())
        assertNotNull(container.rideSessionManager)
        assertNotNull(container.heartRateManager)
    }

    @Test
    fun `a build that can't send has no-op telemetry and does no ride tracking`() {
        val container = AppContainer(ApplicationProvider.getApplicationContext())
        assertSame(NoOpTelemetry, container.telemetry)
        assertNull(container.rideSessionTracker)
    }
}
