package dev.digitalducktape.openride.ui.navigation

import dev.digitalducktape.openride.core.telemetry.Screen
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ScreenViewGateTest {
    private val gate = ScreenViewGate()

    @Test fun `a new screen is reported`() {
        assertEquals(Screen.HOME, gate.screenFor(MainTabs.Home))
        assertEquals(Screen.CLASSES, gate.screenFor(MainTabs.Classes))
    }

    @Test fun `the same screen reported again, as on activity recreation, is not re-sent`() {
        gate.screenFor(MainTabs.Home)
        gate.screenFor(Destinations.Main) // the outer host re-attaches on the tab wrapper
        assertNull(gate.screenFor(MainTabs.Home))
    }

    @Test fun `returning to a tab after a ride is a new view`() {
        gate.screenFor(MainTabs.Home)
        assertNull(gate.screenFor(Destinations.InRide))
        assertNull(gate.screenFor(Destinations.Main))
        assertEquals(Screen.HOME, gate.screenFor(MainTabs.Home))
    }

    @Test fun `returning to a tab from an outer screen is a new view`() {
        gate.screenFor(MainTabs.Profile)
        assertEquals(Screen.ABOUT, gate.screenFor(Destinations.About))
        gate.screenFor(Destinations.Main)
        assertEquals(Screen.PROFILE, gate.screenFor(MainTabs.Profile))
    }
}
