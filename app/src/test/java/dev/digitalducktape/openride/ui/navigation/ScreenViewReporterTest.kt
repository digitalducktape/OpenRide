package dev.digitalducktape.openride.ui.navigation

import dev.digitalducktape.openride.core.telemetry.Screen
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.lang.reflect.Modifier

class ScreenViewReporterTest {
    /** Routes that deliberately send no screen_view. */
    private val unsent = setOf("main", "in_ride", "ride_summary/{rideId}", "video_ride/{videoId}")

    private fun constants(holder: Class<*>): List<String> = holder.declaredFields
        .filter { Modifier.isStatic(it.modifiers) && Modifier.isPublic(it.modifiers) && it.type == String::class.java && it.name != "INSTANCE" }
        .onEach { it.isAccessible = true }
        .map { it.get(null) as String }

    @Test fun everyRouteIsMappedOrDeliberatelyUnsent() {
        val args = setOf(Destinations.RideIdArg, Destinations.VideoIdArg, Destinations.SourceIdArg)
        val real = (constants(Destinations::class.java) + constants(MainTabs::class.java)).filter { it !in args }
        assert(real.size >= 15) { "reflection found too few routes: $real" }
        for (route in real) {
            if (route in unsent) assertNull(route, screenOf(route))
            else assertNotNull("route $route needs a Screen mapping or to join the unsent set", screenOf(route))
        }
    }

    @Test fun argumentsNeverLeak() {
        assertEquals(Screen.CREATOR, screenOf(Destinations.Creator))
        assertNull(screenOf("video_ride/abc123"))
        assertNull(screenOf("ride_summary/7"))
    }

    @Test fun unknownAndNullAreNull() {
        assertNull(screenOf(null))
        assertNull(screenOf("nope"))
    }
}
