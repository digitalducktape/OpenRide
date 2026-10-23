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

    /** The music picker's "no app" choice. */
    const val NO_MUSIC_APP = "None"

    /**
     * The Music app row's value: the chosen app's name, a prompt when none is chosen, or a note
     * when the chosen app has been uninstalled ([chosenLabel] null with a [chosenPackage]).
     */
    fun musicApp(chosenPackage: String?, chosenLabel: String?): String = when {
        chosenPackage == null -> "Adds a Music button to the top bar"
        chosenLabel == null -> "No longer installed"
        else -> chosenLabel
    }
}
