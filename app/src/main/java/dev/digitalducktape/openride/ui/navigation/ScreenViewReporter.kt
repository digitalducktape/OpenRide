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

/** Sends a `screen_view` for each destination [navController] reaches; removed when disposed. */
@Composable
fun ReportScreenViews(navController: NavController, telemetry: Telemetry) {
    val listener = remember(navController, telemetry) {
        NavController.OnDestinationChangedListener { _, destination, _ ->
            screenOf(destination.route)?.let { telemetry.track(ScreenView(it)) }
        }
    }
    DisposableEffect(navController, listener) {
        navController.addOnDestinationChangedListener(listener)
        onDispose { navController.removeOnDestinationChangedListener(listener) }
    }
}
