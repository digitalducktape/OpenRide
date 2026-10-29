package dev.digitalducktape.openride.ui.profile

import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.profile.WeightUnits

/** The Profile tab's derived text, kept out of the composable so it can be unit-tested. */
object ProfileTabLabels {
    private const val METERS_PER_MILE = 1609.344

    /** "185 lb  •  FTP 210W", either part alone, or `null` when neither is set. */
    fun riderDetails(profile: Profile): String? = buildList {
        profile.weightKg?.let { add("${WeightUnits.formatLbs(it)} lb") }
        profile.ftp?.let { add("FTP ${it}W") }
    }.takeIf { it.isNotEmpty() }?.joinToString("  •  ")

    /** The loaded GPX route: "Hill loop  •  12.40 mi" ("Loaded route" when the file has no name). */
    fun routeSummary(name: String?, totalDistanceMeters: Double): String =
        "%s  •  %.2f mi".format(name ?: "Loaded route", totalDistanceMeters / METERS_PER_MILE)

    /** The heart-rate row's value. */
    fun heartRateStrap(paired: Boolean): String = if (paired) "Paired" else "Not paired"

    /** The controllers row's value (#68). */
    fun controllers(paired: Int, connected: Int): String = when {
        paired == 0 -> "Shifters, buttons, BikeControl"
        connected == 0 -> "$paired paired"
        else -> "$connected of $paired connected"
    }

    /** The home-screen row's value. */
    fun homeScreen(isHome: Boolean): String = if (isHome) "On" else "Off"

    /** The Music app row's value: the chosen app, or what happens until one is chosen. */
    fun musicApp(label: String?): String = label ?: "Not chosen. The player's Music button asks"

    /**
     * The Now playing row's value. Off, it names the permission Android will ask for, and
     * what OpenRide does with it, since Android's own wording says "all notifications".
     */
    fun musicControls(on: Boolean): String =
        if (on) "On. Shows what's playing, with controls" else "Off. Needs Notification access; reads only what's playing"
}
