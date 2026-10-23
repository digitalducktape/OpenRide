package dev.digitalducktape.openride.core.music

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MusicAppsTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun app(packageName: String, label: String) = InstalledApp(packageName, label)

    @Test
    fun `known music apps come first in their own order, then the rest by name`() {
        val ordered = MusicApps.order(
            listOf(
                app("org.mozilla.focus", "Firefox Focus"),
                app("com.spotify.music", "Spotify"),
                app("com.aurora.store", "aurora Store"),
                app("com.apple.android.music", "Apple Music"),
            ),
            exclude = "dev.digitalducktape.openride",
        )
        assertEquals(
            listOf("com.apple.android.music", "com.spotify.music", "com.aurora.store", "org.mozilla.focus"),
            ordered.map { it.packageName },
        )
    }

    @Test
    fun `OpenRide itself, nameless entries and duplicates are left out`() {
        val ordered = MusicApps.order(
            listOf(
                app("dev.digitalducktape.openride.real", "OpenRide"),
                app("com.onepeloton.odyssey", " "),
                app("com.spotify.music", "Spotify"),
                app("com.spotify.music", "Spotify"),
            ),
            exclude = "dev.digitalducktape.openride.real",
        )
        assertEquals(listOf("com.spotify.music"), ordered.map { it.packageName })
    }

    @Test
    fun `an app that isn't installed has no name and doesn't open`() {
        assertNull(MusicApps.label(context, "com.example.not.installed"))
        assertFalse(MusicApps.open(context, "com.example.not.installed"))
    }

    @Test
    fun `the choice survives a new store, and clears to none`() {
        SharedPrefsMusicAppStore(context).set("com.apple.android.music")
        assertEquals("com.apple.android.music", SharedPrefsMusicAppStore(context).packageName.value)

        SharedPrefsMusicAppStore(context).set(null)
        assertNull(SharedPrefsMusicAppStore(context).packageName.value)
    }
}
