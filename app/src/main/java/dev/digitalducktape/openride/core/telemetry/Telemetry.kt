package dev.digitalducktape.openride.core.telemetry

/** Where typed [TelemetryEvent]s go. Implementations never throw and never block the caller. */
interface Telemetry {
    fun track(event: TelemetryEvent)
}

/** Drops everything: used when telemetry is not built in (no key, or not a release build). */
object NoOpTelemetry : Telemetry {
    override fun track(event: TelemetryEvent) = Unit
}
