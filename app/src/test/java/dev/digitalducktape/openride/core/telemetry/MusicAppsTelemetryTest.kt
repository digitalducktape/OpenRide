package dev.digitalducktape.openride.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Test

class MusicAppsTelemetryTest {
    @Test
    fun `known music apps map to their names`() {
        assertEquals(MusicApp.SPOTIFY, MusicAppMapping.of("com.spotify.music"))
        assertEquals(MusicApp.APPLE_MUSIC, MusicAppMapping.of("com.apple.android.music"))
        assertEquals(MusicApp.PANDORA, MusicAppMapping.of("com.pandora.android"))
        assertEquals(MusicApp.SIRIUSXM, MusicAppMapping.of("com.sirius"))
        assertEquals(MusicApp.PLEXAMP, MusicAppMapping.of("tv.plex.labs.plexamp"))
    }

    @Test
    fun `anything else is other, and the package name never travels`() {
        assertEquals(MusicApp.OTHER, MusicAppMapping.of("org.example.player"))
        assertEquals(MusicApp.OTHER, MusicAppMapping.of(""))
        assertEquals(mapOf("app" to "other"), MusicAppChosen(MusicAppMapping.of("org.example.player")).props())
    }
}
