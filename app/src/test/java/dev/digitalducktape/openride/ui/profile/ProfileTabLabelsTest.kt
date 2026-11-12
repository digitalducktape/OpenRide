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
    fun `the home-screen row says whether OpenRide is the bike's home screen`() {
        assertEquals("Off", ProfileTabLabels.homeScreen(isHome = false))
        assertEquals("On", ProfileTabLabels.homeScreen(isHome = true))
    }

    @Test
    fun `the music app row names the app, or says the player will ask`() {
        assertEquals("Spotify", ProfileTabLabels.musicApp("Spotify"))
        assertEquals("Not chosen. The player's Music button asks", ProfileTabLabels.musicApp(null))
    }

    @Test
    fun `the now playing row names the permission it needs while off`() {
        assertEquals("On. Shows what's playing, with controls", ProfileTabLabels.musicControls(true))
        assertEquals("Off. Needs Notification access; reads only what's playing", ProfileTabLabels.musicControls(false))
    }

    @Test
    fun `the import summary names only what happened`() {
        assertEquals("Imported 336 rides", ProfileTabLabels.importSummary(WorkoutImportSummary(336, 0, 0, 0)))
        assertEquals(
            "Imported 1 ride  •  2 other workouts skipped",
            ProfileTabLabels.importSummary(WorkoutImportSummary(1, 0, 2, 0)),
        )
        assertEquals(
            "No new rides  •  336 already here  •  1 other workout skipped  •  3 unreadable",
            ProfileTabLabels.importSummary(WorkoutImportSummary(0, 336, 1, 3)),
        )
        assertEquals("No new rides", ProfileTabLabels.importSummary(WorkoutImportSummary(0, 0, 0, 0)))
    }
}
