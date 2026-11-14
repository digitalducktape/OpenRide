package dev.digitalducktape.openride.ui.telemetry

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TelemetryLabelsTest {
    private val notice get() = TelemetryLabels.notice.joinToString("\n") { (h, b) -> h + "\n" + b.joinToString("\n") }

    @Test
    fun noticeMentionsUsAndPerTablet() {
        assertTrue(notice.contains("United States"))
        assertTrue(notice.contains("every rider"))
        assertTrue(notice.contains("Aptabase"))
    }

    @Test
    fun noticeCoversOffSwitchAndInFlightRequests() {
        assertTrue(notice.contains("Share usage metrics"))
        assertTrue(notice.contains("held in memory only"))
    }

    @Test
    fun noticeListsWhatIsNeverSent() {
        assertTrue(notice.contains("Never sent"))
        assertTrue(notice.contains("Heart rate"))
    }

    @Test
    fun riderFacingCopyNeverSaysTelemetry() {
        // The prompt body is the maintainer's own wording, which says "app telemetry" on purpose.
        val all = listOf(
            TelemetryLabels.PROMPT_TITLE, TelemetryLabels.SHARE, TelemetryLabels.DECLINE,
            TelemetryLabels.WHATS_COLLECTED, TelemetryLabels.WHATS_COLLECTED_HINT, TelemetryLabels.SETTINGS_TITLE,
            TelemetryLabels.settingsValue(true), TelemetryLabels.settingsValue(false), notice,
        ).joinToString("\n").replace("docs/TELEMETRY.md", "") // the doc's filename is fine
        assertFalse(all.contains("telemetry", ignoreCase = true))
    }

    @Test
    fun settingsSubtitleFollowsTheSwitch() {
        assertTrue(TelemetryLabels.settingsValue(true).startsWith("On"))
        assertTrue(TelemetryLabels.settingsValue(false).startsWith("Off"))
    }

    @Test
    fun noticeNamesYourDataAndSettingsCategory() {
        listOf("backups", "routes", "updates", "rough counts")
            .forEach { assertTrue(it, notice.contains(it)) }
    }

    @Test
    fun noticeSaysCustomChannelNamesAreSent() {
        assertTrue(notice.contains("A channel you added is sent by its YouTube name"))
        assertTrue(notice.contains("only as \"playlist\""))
        assertFalse(notice.contains("as you typed"))
    }

    @Test
    fun promptDoesNotClaimNoMusic() {
        assertFalse(TelemetryLabels.PROMPT_BODY.contains("no music"))
        assertTrue(TelemetryLabels.PROMPT_BODY.contains("songs played"))
        assertTrue(TelemetryLabels.PROMPT_BODY.contains("OFF by default"))
    }
}
