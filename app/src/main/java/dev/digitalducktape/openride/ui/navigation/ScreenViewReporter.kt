package dev.digitalducktape.openride.ui.navigation

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.remember
import androidx.navigation.NavController
import dev.digitalducktape.openride.core.telemetry.Screen
import dev.digitalducktape.openride.core.telemetry.ScreenView
import dev.digitalducktape.openride.core.telemetry.Telemetry

/**
 * The `screen` for a nav route pattern, or null for routes that send no `screen_view`: the outer
 * `main` wrapper (its tab reports instead), the ride screens, and unknown routes. Matches the
 * route pattern, never an argument value, so ids cannot leak.
 */
fun screenOf(route: String?): Screen? = when (route) {
    Destinations.ProfileSelect -> Screen.PROFILE_SELECT
    Destinations.ProfileCreate -> Screen.PROFILE_CREATE
    Destinations.ProfileEdit -> Screen.PROFILE_EDIT
    Destinations.HrPairing -> Screen.HR_PAIRING
    Destinations.AppUpdate -> Screen.APP_UPDATE
    Destinations.About -> Screen.ABOUT
    Destinations.TelemetryInfo -> Screen.TELEMETRY_INFO
    Destinations.ContentSources -> Screen.CONTENT_SOURCES
    Destinations.Creator -> Screen.CREATOR
    MainTabs.Home -> Screen.HOME
    MainTabs.Classes -> Screen.CLASSES
    MainTabs.Games -> Screen.GAMES
    MainTabs.History -> Screen.HISTORY
    MainTabs.Profile -> Screen.PROFILE
    else -> null
}

/**
 * Decides which destination changes are a new `screen_view`, shared by the outer and tab hosts for
 * the whole process. A host re-attaching (activity recreation, or the tabs coming back into
 * composition) replays its current destination; that is not a new view, so the same screen twice
 * in a row is sent once. Leaving for an unreported screen (a ride) clears the last screen, so
 * coming back to the same tab afterwards counts. The outer `main` wrapper is ignored: its tab reports.
 */
class ScreenViewGate {
    private var last: Screen? = null

    @Synchronized
    fun screenFor(route: String?): Screen? {
        if (route == Destinations.Main) return null
        val screen = screenOf(route)
        if (screen == last) return null
        last = screen
        return screen
    }
}

/** Sends a `screen_view` for each new screen [navController] reaches; removed when disposed. */
@Composable
fun ReportScreenViews(navController: NavController, telemetry: Telemetry, gate: ScreenViewGate) {
    val listener = remember(navController, telemetry, gate) {
        NavController.OnDestinationChangedListener { _, destination, _ ->
            runCatching { gate.screenFor(destination.route) }.getOrNull()?.let { telemetry.track(ScreenView(it)) }
        }
    }
    DisposableEffect(navController, listener) {
        navController.addOnDestinationChangedListener(listener)
        onDispose { navController.removeOnDestinationChangedListener(listener) }
    }
}
