package dev.digitalducktape.openride.ui.telemetry

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TelemetryLabelsTest {
    private val notice get() = TelemetryLabels.notice.joinToString("\n") { (h, b) -> "$h\n$b" }

    @Test
    fun noticeMentionsUsAndPerTablet() {
        assertTrue(notice.contains("United States"))
        assertTrue(notice.contains("every rider"))
        assertTrue(notice.contains("Aptabase"))
    }

    @Test
    fun noticeCoversOffSwitchAndInFlightRequests() {
        assertTrue(notice.contains("Share usage data"))
        assertTrue(notice.contains("held in memory only"))
    }

    @Test
    fun noticeListsWhatIsNeverSent() {
        assertTrue(notice.contains("Never sent"))
        assertTrue(notice.contains("Heart rate"))
    }

    @Test
    fun riderFacingCopyNeverSaysTelemetry() {
        val all = listOf(
            TelemetryLabels.PROMPT_TITLE, TelemetryLabels.PROMPT_BODY, TelemetryLabels.SHARE, TelemetryLabels.DECLINE,
            TelemetryLabels.WHATS_COLLECTED, TelemetryLabels.WHATS_COLLECTED_HINT, TelemetryLabels.SETTINGS_TITLE,
            TelemetryLabels.settingsValue(true), TelemetryLabels.settingsValue(false), notice,
        ).joinToString("\n")
        assertFalse(all.contains("telemetry", ignoreCase = true))
    }

    @Test
    fun settingsSubtitleFollowsTheSwitch() {
        assertTrue(TelemetryLabels.settingsValue(true).startsWith("On"))
        assertTrue(TelemetryLabels.settingsValue(false).startsWith("Off"))
    }

    @Test
    fun noticeNamesYourDataAndSettingsCategory() {
        listOf("backed up", "route", "update", "notification access", "never the contents")
            .forEach { assertTrue(it, notice.contains(it)) }
    }

    @Test
    fun noticeSaysCustomChannelNamesAreSent() {
        assertTrue(notice.contains("The name of a class channel you add yourself is sent"))
        assertTrue(notice.contains("only as \"playlist\""))
        assertTrue(notice.contains("as YouTube lists it"))
        assertFalse(notice.contains("as you typed"))
        assertTrue(notice.contains("Your answer to this prompt, sent when you say yes"))
    }

    @Test
    fun promptDoesNotClaimNoMusic() {
        assertFalse(TelemetryLabels.PROMPT_BODY.contains("no music"))
        assertTrue(TelemetryLabels.PROMPT_BODY.contains("no song or artist info"))
    }
}
