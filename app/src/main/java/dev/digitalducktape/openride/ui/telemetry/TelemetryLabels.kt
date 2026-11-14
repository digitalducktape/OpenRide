package dev.digitalducktape.openride.ui.telemetry

/**
 * The words of the usage-metrics prompt, its Profile switch and the "What's collected" screen,
 * kept apart so tests can pin them. Riders see "usage metrics", never the internal name.
 */
object TelemetryLabels {
    const val PROMPT_TITLE = "Share usage metrics?"
    const val PROMPT_BODY =
        "This helps improve OpenRide further. It collects only app feature usage, " +
            "never personal information: " +
            "no names, no heart rate or power, no song or artist info. " +
            "It's off unless you say yes, and you can change it any time under Profile."
    const val SHARE = "Share usage metrics"
    const val DECLINE = "No thanks"
    const val WHATS_COLLECTED = "What's collected"
    const val WHATS_COLLECTED_HINT = "What's sent, and what never is"

    const val SETTINGS_TITLE = "Share usage metrics"
    const val SETTINGS_GROUP = "Usage metrics"

    fun settingsValue(on: Boolean): String =
        if (on) "On. Sent for every rider on this tablet" else "Off. Nothing is sent"

    /** The "What's collected" screen: a heading and its text, in reading order. */
    val notice: List<Pair<String, String>> = listOf(
        "What's sent" to
            "Which screens are opened. Each event carries the time it happened, and the app version, Android " +
            "version, tablet model and language setting. " +
            "When the app starts: the tablet model, its software version, whether this is the bike build or a " +
            "test build, and how many riders it has (1, 2 or 3 or more). " +
            "Your answer to this prompt, sent when you say yes. " +
            "When you finish setting up a rider, and whether it has a photo. " +
            "When a ride starts and ends: its type, where it was started from, whether a route was loaded, " +
            "a rough length, whether it was saved, why a ride was discarded, and whether the " +
            "heart-rate strap and bike sensors stayed connected.",
        "Classes" to
            "Which class channel you watch, how long, whether the class finished, whether it was muted, and " +
            "playback errors. The name of a class channel you add yourself is sent, as YouTube lists it. " +
            "Playlists are sent only as \"playlist\".",
        "Games and music" to
            "Which games you play, the difficulty, and the result as 0 to 3 stars and whether you won. How long each game was played " +
            "and how it ended (finished, quit or skipped), and why a games visit ended. " +
            "Whether Game music is on or off, " +
            "and whether head-lean setup finished, was cancelled, or failed to find a face or camera. " +
            "Whether the music player was used, which music app you chose, and " +
            "whether your own music was playing, including during a ride.",
        "Sensors and camera" to
            "Whether a heart-rate strap was selected or Bluetooth was off, whether the bike's sensors connected, and " +
            "whether you allowed camera access.",
        "Your data and settings" to
            "Whether you backed up, restored, imported or exported rides, or deleted one. Whether you loaded or " +
            "cleared a route. Whether an update was offered or installed, or failed to check or download, and " +
            "whether you allowed notification access. Results and rough counts (how many rides were imported, " +
            "roughly how big a route is), never the contents.",
        "Never sent" to
            "Heart rate, power, cadence, speed, resistance, FTP or weight. Scores other than 0 to 3 stars. " +
            "Rider names or photos. Video IDs or titles. Playlist names. Song or artist info. Bluetooth names or " +
            "addresses. File names or route coordinates. " +
            "Exact ride or class lengths, or clock times, in event properties. Error messages.",
        "Where it goes" to
            "Usage metrics are stored in the United States by Aptabase, an analytics service. Events from one visit " +
            "to the app share a session ID that isn't tied to a rider.",
        "Who it covers" to
            "This choice is per tablet. It covers every rider who uses this tablet.",
        "Unfinished rides" to
            "A ride that is abandoned, or that the system closes, shows up as a start with no matching end.",
        "Turning it off" to
            "Go to Profile, then Device, then turn off Share usage metrics. Sending stops right away. " +
            "Events already handed to the sender are held in memory only and may still be sent until the " +
            "app closes. Nothing is stored on the tablet.",
    )
}
