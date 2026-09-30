package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.CalibrationProgressSignal
import dev.digitalducktape.openride.games.bridge.GameSignals
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

/** A fake bridge: records Kotlin → Godot signals in order. */
class RecordingSignals : GameSignals {
    val events = mutableListOf<Pair<String, String?>>()

    val names get() = events.map { it.first }

    fun payload(name: String): JsonObject =
        Json.parseToJsonElement(events.last { it.first == name }.second!!).jsonObject

    fun payloads(name: String): List<JsonObject> =
        events.filter { it.first == name }.map { Json.parseToJsonElement(it.second!!).jsonObject }

    override fun sessionStarted(planJson: String) { events += "session_started" to planJson }
    override fun segmentStarted(segmentJson: String) { events += "segment_started" to segmentJson }
    override fun segmentEnding() { events += "segment_ending" to null }
    override fun sessionPaused() { events += "session_paused" to null }
    override fun sessionResumed() { events += "session_resumed" to null }
    override fun calibrationProgress(progress: CalibrationProgressSignal) {
        events += "calibration_progress" to "${progress.step}:${progress.fraction}"
    }
    override fun sessionFinished(summaryJson: String) { events += "session_finished" to summaryJson }
}
