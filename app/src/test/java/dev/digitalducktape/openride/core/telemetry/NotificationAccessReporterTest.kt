package dev.digitalducktape.openride.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class NotificationAccessReporterTest {
    private val telemetry = RecordingTelemetry()
    private val reporter = NotificationAccessReporter(telemetry)

    @Test
    fun `reports granted once when the rider comes back with access`() {
        reporter.onSettingsOpened()
        reporter.onResume(hasAccess = true)
        reporter.onResume(hasAccess = true)

        assertEquals(listOf<Any>(NotificationAccess(GrantResult.GRANTED)), telemetry.events)
    }

    @Test
    fun `reports denied when the rider comes back without access`() {
        reporter.onSettingsOpened()
        reporter.onResume(hasAccess = false)

        assertEquals(listOf<Any>(NotificationAccess(GrantResult.DENIED)), telemetry.events)
    }

    @Test
    fun `an ordinary resume reports nothing`() {
        reporter.onResume(hasAccess = true)

        assertTrue(telemetry.events.isEmpty())
    }

    @Test
    fun `a second visit to settings reports again`() {
        reporter.onSettingsOpened()
        reporter.onResume(hasAccess = false)
        reporter.onSettingsOpened()
        reporter.onResume(hasAccess = true)

        assertEquals(2, telemetry.events.size)
    }
}
