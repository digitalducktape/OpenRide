package dev.digitalducktape.openride.core.telemetry

/** Which music app the rider chose, as a fixed name. The package name itself is never sent. */
object MusicAppMapping {
    fun of(packageName: String): MusicApp = when {
        packageName == "com.spotify.music" -> MusicApp.SPOTIFY
        packageName == "com.apple.android.music" -> MusicApp.APPLE_MUSIC
        packageName == "com.pandora.android" -> MusicApp.PANDORA
        packageName == "com.sirius" || packageName.startsWith("com.siriusxm") -> MusicApp.SIRIUSXM
        packageName == "tv.plex.labs.plexamp" -> MusicApp.PLEXAMP
        else -> MusicApp.OTHER
    }
}
