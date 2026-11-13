package dev.digitalducktape.openride.core.telemetry

/** A [Telemetry] that remembers what it was given, for tests. */
class RecordingTelemetry : Telemetry {
    private val recorded = mutableListOf<TelemetryEvent>()
    val events: List<TelemetryEvent> get() = recorded.toList()
    override fun track(event: TelemetryEvent) {
        recorded += event
    }
}
