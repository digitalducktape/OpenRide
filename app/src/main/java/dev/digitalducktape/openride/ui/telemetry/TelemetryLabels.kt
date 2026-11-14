package dev.digitalducktape.openride.ui.telemetry

/**
 * The words of the usage-metrics prompt, its Profile switch and the "What's collected" screen,
 * kept apart so tests can pin them. Riders see "usage metrics", never the internal name.
 */
object TelemetryLabels {
    const val PROMPT_TITLE = "Share usage metrics?"
    const val PROMPT_BODY =
        "Anonymous usage metrics help us improve OpenRide. We collect basic app telemetry to inform what " +
            "parts of the app we need to iterate on and expand. No personal information (e.g. name, heart rate, " +
            "power, songs played) is collected. Metric collection is OFF by default. You can always change " +
            "your preference under Profile."
    const val SHARE = "Share usage metrics"
    const val DECLINE = "No thanks"
    const val WHATS_COLLECTED = "What's collected"
    const val WHATS_COLLECTED_HINT = "What's sent, and what never is"

    const val SETTINGS_TITLE = "Share usage metrics"
    const val SETTINGS_GROUP = "Usage metrics"

    fun settingsValue(on: Boolean): String =
        if (on) "On. Sent for every rider on this tablet" else "Off. Nothing is sent"

    /** The "What's collected" screen: short sections of bullets, in reading order. */
    val notice: List<Pair<String, List<String>>> = listOf(
        "What's sent" to listOf(
            "Which screens and features you use, and when",
            "App version, Android version, tablet model and language",
            "Ride, class and game lengths, rounded (for example 15–30 min)",
            "Ride type, whether it was saved, and whether the sensors and heart-rate strap stayed connected",
            "Class channels you watch. A channel you added is sent by its YouTube name; playlists only as \"playlist\"",
            "Games played, difficulty, 0–3 stars and whether you won",
            "Whether music played, and which music app you chose",
            "Whether backups, restores, imports, routes and updates worked, with rough counts",
        ),
        "Never sent" to listOf(
            "Your name or photo",
            "Heart rate, power, cadence, speed, resistance, FTP or weight",
            "Song, artist, video or playlist names",
            "Bluetooth device names, file names or route coordinates",
            "Exact lengths, clock times or error messages",
        ),
        "Good to know" to listOf(
            "Stored in the United States by Aptabase. A visit's events share a session ID that isn't tied to you",
            "One setting per tablet: it covers every rider",
            "Turn it off under Profile, then Device, then Share usage metrics. Sending stops right away; " +
                "events already queued are held in memory only and may still go out until the app closes",
            "Full list: docs/TELEMETRY.md at github.com/digitalducktape/openride",
        ),
    )
}
