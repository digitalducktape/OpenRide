package dev.digitalducktape.openride.ui.profile

import dev.digitalducktape.openride.core.data.Profile
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ProfileTabLabelsTest {

    private fun rider(weightKg: Double? = null, ftp: Int? = null) =
        Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0, weightKg = weightKg, ftp = ftp)

    @Test
    fun `rider details show weight in pounds and FTP, as before the refresh`() {
        assertEquals("185 lb  •  FTP 210W", ProfileTabLabels.riderDetails(rider(weightKg = 83.91452, ftp = 210)))
    }

    @Test
    fun `rider details show whichever part is set, or nothing`() {
        assertEquals("FTP 180W", ProfileTabLabels.riderDetails(rider(ftp = 180)))
        assertEquals("185 lb", ProfileTabLabels.riderDetails(rider(weightKg = 83.91452)))
        assertNull(ProfileTabLabels.riderDetails(rider()))
    }

    @Test
    fun `a route reads its name and distance in miles`() {
        assertEquals("Hill loop  •  1.00 mi", ProfileTabLabels.routeSummary("Hill loop", 1609.344))
        assertEquals("Loaded route  •  12.40 mi", ProfileTabLabels.routeSummary(null, 12.4 * 1609.344))
    }

    @Test
    fun `the strap row says whether one is paired`() {
        assertEquals("Paired", ProfileTabLabels.heartRateStrap(true))
        assertEquals("Not paired", ProfileTabLabels.heartRateStrap(false))
    }

    @Test
    fun `the music row names the chosen app, prompts when there's none, and flags one that's gone`() {
        assertEquals("Apple Music", ProfileTabLabels.musicApp("com.apple.android.music", "Apple Music"))
        assertEquals("Adds a Music button to the top bar", ProfileTabLabels.musicApp(null, null))
        assertEquals("No longer installed", ProfileTabLabels.musicApp("com.spotify.music", null))
    }
}
