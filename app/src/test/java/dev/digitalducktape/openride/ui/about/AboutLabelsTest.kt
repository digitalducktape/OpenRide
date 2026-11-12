package dev.digitalducktape.openride.ui.about

import dev.digitalducktape.openride.BuildConfig
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class AboutLabelsTest {

    @Test
    fun `the Profile row names the version and the funding page`() {
        assertEquals("Version 1.1.0  •  Help fund this app", AboutLabels.rowValue("1.1.0"))
    }

    @Test
    fun `the version drops the bike build's suffix`() {
        assertEquals("Version 1.1.0", AboutLabels.version("1.1.0-real"))
    }

    @Test
    fun `urls show without their scheme`() {
        assertEquals("buymeacoffee.com/digitalducktape", AboutLabels.display(AboutLabels.SUPPORT_URL))
        assertEquals("github.com/digitalducktape/openride", AboutLabels.display(AboutLabels.REPO_URL))
    }

    /** The release recipe (docs/INSTALL.md) writes these per release; this catches a forgotten one. */
    @Test
    fun `the bundled release notes are this version's`() {
        val notes = File("src/main/res/raw/release_notes.txt").readText()
        val majorMinor = BuildConfig.VERSION_NAME.substringBefore('-').split('.').take(2).joinToString(".")
        assertTrue(
            "release_notes.txt should start with \"OpenRide $majorMinor\"",
            notes.startsWith("OpenRide $majorMinor"),
        )
    }
}
