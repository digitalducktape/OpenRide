package dev.digitalducktape.openride.ui.telemetry

/**
 * The words of the usage-data prompt, its Profile switch and the "What's collected" screen,
 * kept apart so tests can pin them. Riders see "usage data", never the internal name.
 */
object TelemetryLabels {
    const val PROMPT_TITLE = "Share usage data?"
    const val PROMPT_BODY =
        "Help improve OpenRide by sharing which screens and features get used. " +
            "Nothing that identifies you or your rides is sent: no names, no heart rate or power, no music. " +
            "It's off unless you say yes, and you can change it any time under Profile."
    const val SHARE = "Share usage data"
    const val DECLINE = "No thanks"
    const val WHATS_COLLECTED = "What's collected"
    const val WHATS_COLLECTED_HINT = "What's sent, and what never is"

    const val SETTINGS_TITLE = "Share usage data"
    const val SETTINGS_GROUP = "Usage data"

    fun settingsValue(on: Boolean): String =
        if (on) "On. Sent for every rider on this tablet" else "Off. Nothing is sent"

    /** The "What's collected" screen: a heading and its text, in reading order. */
    val notice: List<Pair<String, String>> = listOf(
        "What's sent" to
            "Which screens are opened. When the app starts: the tablet model, its software version, and how many " +
            "riders it has (1, 2 or 3 or more). When a ride starts and ends: its type, a rough length, whether it was " +
            "saved, and whether the heart-rate strap and bike sensors stayed connected. For classes: the channel, " +
            "whether the class finished, and whether it was muted. For games: which games were played, the " +
            "difficulty, and the result as 0 to 3 stars. Whether the music player was used, and which music app. " +
            "How you answered the prompt.",
        "Never sent" to
            "Heart rate, power, cadence, speed, resistance, FTP or weight. Scores other than 0 to 3 stars. " +
            "Rider names or photos. Video IDs or titles. Playlist names. Song or artist info. Bluetooth names or " +
            "addresses. File names or route coordinates. Exact times. Error messages.",
        "Where it goes" to
            "Usage data is stored in the United States by Aptabase, an analytics service. Events from one visit " +
            "to the app share a session ID that isn't tied to a rider.",
        "Who it covers" to
            "This choice is per tablet. It covers every rider who uses this tablet.",
        "Unfinished rides" to
            "A ride that is abandoned, or that the system closes, shows up as a start with no matching end.",
        "Turning it off" to
            "Go to Profile, then Device, then turn off Share usage data. Sending stops right away. " +
            "A request already on its way may still complete.",
    )
}
