package dev.digitalducktape.openride.games.bridge

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject

/*
 * JSON payloads of the v1 Bridge contract (docs/GAMES.md). Signals and methods carry JSON text
 * as a single String argument; GDScript's `Session` autoload parses and stringifies it. Every
 * key and enum word here is the contract's snake_case wire name.
 */

@Serializable
enum class SessionKind {
    @SerialName("circuit") CIRCUIT,
    @SerialName("just_ride") JUST_RIDE,
}

@Serializable
enum class SegmentRole {
    @SerialName("warmup") WARMUP,
    @SerialName("work") WORK,
    @SerialName("recovery") RECOVERY,
    @SerialName("cooldown") COOLDOWN,

    /** A Just Ride segment. */
    @SerialName("free") FREE,
}

@Serializable
enum class Difficulty {
    @SerialName("easy") EASY,
    @SerialName("standard") STANDARD,
    @SerialName("hard") HARD,
}

@Serializable
enum class EndMode {
    /** Kotlin ends the segment at `duration_sec`. */
    @SerialName("timer") TIMER,

    /** The game ends it with `segment_finished`; Kotlin still hard-stops at 1.5 × `duration_sec`. */
    @SerialName("game") GAME,
}

/** `set_tracker_mode(mode)`. The camera only runs when not [OFF]. */
enum class TrackerMode(val wire: String) {
    OFF("off"),
    LEAN_X("lean_x"),
    LEAN_2D("lean_2d"),
    LEAN_STAND("lean_stand"),
    ;

    companion object {
        fun fromWire(value: String): TrackerMode? = entries.firstOrNull { it.wire == value }
    }
}

/** `request_calibration(mode)`. */
enum class CalibrationMode(val wire: String) {
    LEAN_X("lean_x"),
    LEAN_2D("lean_2d"),
    ;

    companion object {
        fun fromWire(value: String): CalibrationMode? = entries.firstOrNull { it.wire == value }
    }
}

/** `session_started(plan_json)`: sent once; drives the circuit progress strip. */
@Serializable
data class SessionPlanMessage(
    val kind: SessionKind,
    @SerialName("plan_id") val planId: String,
    val difficulty: Difficulty,
    /** Total planned seconds, or -1 for an open-ended Just Ride. */
    @SerialName("total_sec") val totalSec: Int,
    val segments: List<PlanSegment>,
    /** The active rider's profile id, or null with no active rider: games remember their options per rider. */
    @SerialName("rider_id") val riderId: Long? = null,
)

@Serializable
data class PlanSegment(
    @SerialName("game_id") val gameId: String,
    val role: SegmentRole,
    /** -1 for an open-ended Just Ride. */
    @SerialName("duration_sec") val durationSec: Int,
)

/** `segment_started(segment_json)`. */
@Serializable
data class SegmentStartMessage(
    val index: Int,
    val count: Int,
    @SerialName("game_id") val gameId: String,
    @SerialName("duration_sec") val durationSec: Int,
    @SerialName("intro_sec") val introSec: Int,
    @SerialName("end_mode") val endMode: EndMode,
    val role: SegmentRole,
    val difficulty: Difficulty,
    val effort: Boolean,
    val seed: Long,
    val audio: AudioSettings,
    /** Game-specific, already scaled to FTP and difficulty. */
    val params: JsonObject = JsonObject(emptyMap()),
)

@Serializable
data class AudioSettings(
    /** False when the rider's own music is playing or game music is off. */
    val music: Boolean,
    @SerialName("music_volume") val musicVolume: Double,
    @SerialName("sfx_volume") val sfxVolume: Double,
)

/** `segment_finished(result_json)`, parsed leniently by [BridgeMessages.parseResult]. */
@Serializable
data class SegmentResult(
    @SerialName("game_id") val gameId: String,
    val score: Double,
    /** 0-3. */
    val stars: Int,
    /** Null for games without a winner. */
    val won: Boolean?,
    val skipped: Boolean,
    val stats: JsonObject,
    /** The game's variant, e.g. Dodge Ball's `catch`; `""` (or absent) for none. */
    val variant: String = "",
) {
    companion object {
        /** Recorded when a game fails to report within the grace period, or reports garbage. */
        fun zero(gameId: String) =
            SegmentResult(gameId, score = 0.0, stars = 0, won = null, skipped = false, stats = JsonObject(emptyMap()))
    }
}

/** `session_finished(summary_json)`, sent after Kotlin has saved the ride. */
@Serializable
data class SessionSummary(
    /** The saved ride, or null when nothing was recorded. */
    @SerialName("ride_id") val rideId: Long?,
    val results: List<SegmentResult>,
    val totals: SessionTotals,
    val bests: JsonObject,
)

@Serializable
data class SessionTotals(
    val score: Double,
    val stars: Int,
    val segments: Int,
    @SerialName("elapsed_sec") val elapsedSec: Int,
)

object BridgeMessages {
    private val json = Json {
        // Every contract key is always sent, nulls included (e.g. `ride_id`, `won`).
        encodeDefaults = true
        ignoreUnknownKeys = true
    }

    fun encode(plan: SessionPlanMessage): String = encode(SessionPlanMessage.serializer(), plan)
    fun encode(segment: PlanSegment): String = encode(PlanSegment.serializer(), segment)
    fun encode(segment: SegmentStartMessage): String = encode(SegmentStartMessage.serializer(), segment)
    fun encode(summary: SessionSummary): String = encode(SessionSummary.serializer(), summary)

    private fun <T> encode(serializer: KSerializer<T>, value: T): String = json.encodeToString(serializer, value)

    /**
     * Parses a game's `segment_finished` payload, or null if it isn't a JSON object with a
     * `game_id`. Lenient where GDScript is loose: numbers may arrive as floats (`3.0`), `won`
     * may be null, and anything but `game_id` may be missing. Stars are clamped to 0-3.
     */
    fun parseResult(resultJson: String): SegmentResult? {
        val obj = runCatching { json.parseToJsonElement(resultJson).jsonObject }.getOrNull() ?: return null
        val gameId = (obj["game_id"] as? JsonPrimitive)?.takeIf { it.isString }?.content ?: return null
        return SegmentResult(
            gameId = gameId,
            score = obj.number("score") ?: 0.0,
            stars = (obj.number("stars") ?: 0.0).toInt().coerceIn(0, 3),
            won = (obj["won"] as? JsonPrimitive)?.takeIf { it != JsonNull }?.booleanOrNull,
            skipped = (obj["skipped"] as? JsonPrimitive)?.booleanOrNull ?: false,
            stats = obj["stats"] as? JsonObject ?: JsonObject(emptyMap()),
        )
    }

    private fun JsonObject.number(key: String): Double? = (this[key] as? JsonPrimitive)?.doubleOrNull
}
