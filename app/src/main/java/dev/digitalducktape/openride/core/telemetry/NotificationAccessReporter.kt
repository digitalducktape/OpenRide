package dev.digitalducktape.openride.core.telemetry

/**
 * `notification_access`: the rider went to Android's Notification access screen and came back.
 * The first resume after the visit reports whether the grant is on; later resumes say nothing.
 */
class NotificationAccessReporter(private val telemetry: Telemetry) {
    private var pending = false

    /** The settings intent was started. */
    fun onSettingsOpened() {
        pending = true
    }

    /** The app is back in front; [hasAccess] is the grant as just re-read. */
    fun onResume(hasAccess: Boolean) {
        if (!pending) return
        pending = false
        telemetry.trackSafely { NotificationAccess(if (hasAccess) GrantResult.GRANTED else GrantResult.DENIED) }
    }
}
