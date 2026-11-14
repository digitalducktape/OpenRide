package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.camera.LeanSensitivity
import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonObject

/*
 * JSON payloads of the Bridge contract (docs/GAMES.md): v1, plus the Games hub's additive
 * messages (v1.1, docs/superpowers/specs/2026-10-19-games-hub-design.md §3). Signals and methods carry JSON text
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
    /**
     * The active rider's profile name, trimmed, or null with no active rider (or a blank name).
     * Added after v1 like [riderId] and optional: Kart Race puts it on the rider's kart.
     */
    @SerialName("rider_name") val riderName: String? = null,
    /** v1.1, only in a hub visit (absent otherwise): the visit this plan belongs to. */
    @OptIn(ExperimentalSerializationApi::class)
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    @SerialName("visit_id") val visitId: String? = null,
    /** v1.1, only in a visit: the 0-based count of plans started this visit. */
    @OptIn(ExperimentalSerializationApi::class)
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    @SerialName("plan_index") val planIndex: Int? = null,
    /** v1.1, only in a visit: what the visit's calibration covers, `""`, `lean_x` or `lean_2d`. */
    @OptIn(ExperimentalSerializationApi::class)
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    val calibrated: String? = null,
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
    /** The hub's Game music switch. On, game music still stays off while the rider's own music plays (frame field 12). */
    val music: Boolean = true,
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

/**
 * `session_finished(summary_json)`. In a hub visit it ends one plan: [rideId] is always null
 * there (the ride is saved on exit and its id comes in `visit_ended`), and the visit keys are set.
 */
@Serializable
data class SessionSummary(
    /** The saved ride, or null when nothing was recorded (always null in a visit). */
    @SerialName("ride_id") val rideId: Long?,
    val results: List<SegmentResult>,
    val totals: SessionTotals,
    val bests: JsonObject,
    @OptIn(ExperimentalSerializationApi::class)
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    @SerialName("visit_id") val visitId: String? = null,
    @OptIn(ExperimentalSerializationApi::class)
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    @SerialName("plan_index") val planIndex: Int? = null,
    @OptIn(ExperimentalSerializationApi::class)
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    @SerialName("plan_id") val planId: String? = null,
    @OptIn(ExperimentalSerializationApi::class)
    @EncodeDefault(EncodeDefault.Mode.NEVER)
    val difficulty: Difficulty? = null,
)

@Serializable
data class SessionTotals(
    val score: Double,
    val stars: Int,
    val segments: Int,
    @SerialName("elapsed_sec") val elapsedSec: Int,
)


// --- v1.1: the Games hub (spec §3) -----------------------------------------------------------

/** `hub_state.phase`: the visit's phase as Godot needs it. */
@Serializable
enum class HubPhase {
    @SerialName("hub") HUB,
    @SerialName("plan") PLAN,
    @SerialName("saving") SAVING,
    @SerialName("ended") ENDED,
}

/** `hub_state.camera.permission`. */
@Serializable
enum class CameraPermission {
    @SerialName("granted") GRANTED,
    @SerialName("denied") DENIED,
    @SerialName("ask") ASK,
}

/** `hub_state(state_json)`: a full snapshot every time, never a delta. */
@Serializable
data class HubStateMessage(
    @SerialName("hub_version") val hubVersion: Int = HUB_VERSION,
    /** New per visit; Godot resets visit-scoped state when it changes. */
    @SerialName("visit_id") val visitId: String,
    val phase: HubPhase,
    val rider: HubRider,
    val settings: HubSettings,
    /** The volumes (`GameAudioPrefs.resolve`), for the hub's own music. */
    val audio: AudioSettings,
    val camera: HubCamera,
    /** `GameCatalog` without the demo, in display order. */
    val catalog: List<HubCatalogGame>,
    val circuits: List<HubCircuit>,
    val bests: HubBests,
    val visit: HubVisit,
) {
    companion object {
        const val HUB_VERSION = 1
    }
}

/** With no active rider: id null and name `""` ("guest"). */
@Serializable
data class HubRider(
    val id: Long?,
    val name: String,
    /** A 256×256 PNG Kotlin rendered for this visit, or null. */
    @SerialName("avatar_png") val avatarPng: String?,
    /** `#RRGGBB`. */
    @SerialName("avatar_color") val avatarColor: String,
    @SerialName("ftp_watts") val ftpWatts: Int,
    /** No FTP set, so [ftpWatts] is the 150 W fallback: drives the FTP nudge. */
    @SerialName("ftp_is_default") val ftpIsDefault: Boolean,
)

@Serializable
data class HubSettings(
    @SerialName("camera_games") val cameraGames: Boolean,
    @SerialName("game_music") val gameMusic: Boolean = true,
    @SerialName("music_volume") val musicVolume: Double,
    @SerialName("sfx_volume") val sfxVolume: Double,
    /** `low | normal | high` (#71); added in hub v1.1 without a version bump, Godot defaults it. */
    @SerialName("lean_sensitivity") val leanSensitivity: String = LeanSensitivity.DEFAULT.code,
)

@Serializable
data class HubCamera(
    val permission: CameraPermission,
    /** Permission granted, camera games on, and the camera hasn't failed. */
    val available: Boolean,
    /** What this visit's calibration covers: `""`, `lean_x` or `lean_2d`. */
    val calibrated: String,
    /** A first calibration will take the centre only (the rider's extremes are from today). */
    @SerialName("same_day_extremes") val sameDayExtremes: Boolean,
)

@Serializable
data class HubCatalogGame(
    val id: String,
    val title: String,
    /** `minutes`, `rounds`, `open`. */
    val supports: List<String>,
    @SerialName("min_sec") val minSec: Int,
    @SerialName("max_sec") val maxSec: Int,
    @SerialName("min_rounds") val minRounds: Int,
    @SerialName("max_rounds") val maxRounds: Int,
    @SerialName("round_sec") val roundSec: Int,
    val roles: List<SegmentRole>,
    @SerialName("uses_camera") val usesCamera: Boolean,
    @SerialName("minute_steps") val minuteSteps: List<Int>,
    /** The role a custom-circuit slot of this game plays (spec §3.4). */
    @SerialName("circuit_role") val circuitRole: SegmentRole,
)

@Serializable
data class HubCircuit(
    val id: String,
    val minutes: Int,
    /** Planned seconds, intro cards included. */
    @SerialName("total_sec") val totalSec: Int,
    val slots: List<HubCircuitSlot>,
)

@Serializable
data class HubCircuitSlot(
    @SerialName("game_id") val gameId: String,
    val role: SegmentRole,
    @SerialName("duration_sec") val durationSec: Int,
)

/** The rider's bests, with this visit's finished plans already merged in. */
@Serializable
data class HubBests(
    val games: List<HubGameBest>,
    val plans: List<HubPlanBest>,
)

@Serializable
data class HubGameBest(
    @SerialName("game_id") val gameId: String,
    @SerialName("plan_id") val planId: String,
    val difficulty: Difficulty,
    val variant: String,
    val score: Double,
    val stars: Int,
    val plays: Int,
)

@Serializable
data class HubPlanBest(
    @SerialName("plan_id") val planId: String,
    val difficulty: Difficulty,
    val score: Double,
    val stars: Int,
)

@Serializable
data class HubVisit(
    /** False with no active rider, or while another ride holds the recorder. */
    val recording: Boolean,
    /** Ride seconds so far (menu time excluded). */
    @SerialName("ride_sec") val rideSec: Int,
    @SerialName("gameplay_sec") val gameplaySec: Int,
    val plans: List<HubVisitPlan>,
)

@Serializable
data class HubVisitPlan(
    @SerialName("plan_id") val planId: String,
    val difficulty: Difficulty,
    val score: Double,
    val stars: Int,
    @SerialName("game_ids") val gameIds: List<String>,
)

/** Why a `start_plan` can't be played. */
@Serializable
enum class PlanRejectReason {
    @SerialName("unknown_game") UNKNOWN_GAME,
    @SerialName("unsupported_mode") UNSUPPORTED_MODE,
    @SerialName("camera_unavailable") CAMERA_UNAVAILABLE,
    @SerialName("busy") BUSY,
    @SerialName("empty_circuit") EMPTY_CIRCUIT,
    @SerialName("too_long") TOO_LONG,
}

/** `plan_rejected(reason_json)`, sent instead of `session_started`. */
@Serializable
data class PlanRejectedMessage(
    /** The request as Godot sent it (`{}` if it wasn't a JSON object). */
    val request: JsonElement,
    val reason: PlanRejectReason,
)

/** `visit_ended(result_json)`: the ride is saved (or discarded). Godot calls nothing after it. */
@Serializable
data class VisitEndedMessage(
    @SerialName("visit_id") val visitId: String,
    @SerialName("ride_id") val rideId: Long?,
    val saved: Boolean,
    /** `""`, `too_short`, `no_pedalling` or `not_recording`. */
    @SerialName("discarded_reason") val discardedReason: String,
    /**
     * `app`, `edit_profile`, or `hub` when the visit was saved without leaving (the idle guard):
     * Godot stays in the hub, and a tap starts a new visit.
     */
    val next: String,
    /** Why the visit ended: `exit`, `idle`, `app_resumed` or `replaced`. Added beyond the spec. */
    val reason: String = "exit",
)

/** `start_plan`'s `kind`. */
enum class PlanRequestKind(val wire: String) {
    JUST_RIDE("just_ride"),
    CIRCUIT("circuit"),
    CUSTOM("custom"),
}

/** One slot of a custom circuit request. */
data class PlanRequestSlot(val gameId: String, val durationSec: Int)

/**
 * `start_plan(request_json)` (spec §3.4), parsed leniently by [BridgeMessages.parsePlanRequest].
 * Fields that don't apply to [kind] keep their defaults.
 *
 * @param mode `minutes`, `rounds` or `open` (Just Ride).
 * @param length minutes or rounds (Just Ride).
 */
data class PlanRequestMessage(
    val kind: PlanRequestKind,
    val gameId: String = "",
    val mode: String = "",
    val length: Int = 0,
    val presetId: String = "",
    val difficulty: Difficulty = Difficulty.STANDARD,
    val slots: List<PlanRequestSlot> = emptyList(),
)

/** `now_playing(json)`: the rider's music app's track, for the hub's music card. */
@Serializable
data class NowPlayingMessage(
    val title: String,
    val artist: String,
    /** A PNG of the album art in the app's cache, or "" without one. */
    val art: String,
    val playing: Boolean,
    @SerialName("can_previous") val canPrevious: Boolean,
    @SerialName("can_next") val canNext: Boolean,
)

/** `update_setting(key, value_json)`. */
sealed interface SettingUpdate {
    data class CameraGames(val on: Boolean) : SettingUpdate
    data class GameMusic(val on: Boolean) : SettingUpdate

    data class MusicVolume(val volume: Double) : SettingUpdate
    data class SfxVolume(val volume: Double) : SettingUpdate
    data class LeanSensitivity(val level: dev.digitalducktape.openride.core.camera.LeanSensitivity) : SettingUpdate
}

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
    fun encode(state: HubStateMessage): String = encode(HubStateMessage.serializer(), state)
    fun encode(rejected: PlanRejectedMessage): String = encode(PlanRejectedMessage.serializer(), rejected)
    fun encode(ended: VisitEndedMessage): String = encode(VisitEndedMessage.serializer(), ended)
    /** `{}` when nothing is playing. */
    fun encode(playing: NowPlayingMessage?): String = playing?.let { encode(NowPlayingMessage.serializer(), it) } ?: "{}"

    /** For tests and tools: the payloads Kotlin sends, read back. */
    fun decodeHubState(text: String): HubStateMessage = json.decodeFromString(HubStateMessage.serializer(), text)
    fun decodePlanRejected(text: String): PlanRejectedMessage = json.decodeFromString(PlanRejectedMessage.serializer(), text)
    fun decodeVisitEnded(text: String): VisitEndedMessage = json.decodeFromString(VisitEndedMessage.serializer(), text)

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
            variant = obj.string("variant") ?: "",
        )
    }

    /**
     * Parses `start_plan`'s request, or null if it isn't a JSON object with a known `kind`.
     * Numbers may be floats (`10.0`), unknown keys are ignored, and missing keys take their
     * defaults (an unknown `difficulty` reads as `standard`). Validation against the catalog
     * is the visit's job (`PlanRequestMessage.toSessionRequest`).
     */
    fun parsePlanRequest(requestJson: String): PlanRequestMessage? {
        val obj = parseObject(requestJson) ?: return null
        val kind = PlanRequestKind.entries.firstOrNull { it.wire == obj.string("kind") } ?: return null
        val slots = (obj["slots"] as? JsonArray).orEmpty().mapNotNull { element ->
            val slot = element as? JsonObject ?: return@mapNotNull null
            PlanRequestSlot(slot.string("game_id") ?: "", slot.number("duration_sec")?.toInt() ?: 0)
        }
        return PlanRequestMessage(
            kind = kind,
            gameId = obj.string("game_id") ?: "",
            mode = obj.string("mode") ?: "",
            length = obj.number("length")?.toInt() ?: 0,
            presetId = obj.string("preset_id") ?: "",
            difficulty = difficultyOf(obj.string("difficulty")),
            slots = slots,
        )
    }

    /** The request JSON as sent, for `plan_rejected` (`{}` if it isn't an object). */
    fun requestEcho(requestJson: String): JsonElement = parseObject(requestJson) ?: JsonObject(emptyMap())

    /** Parses `update_setting(key, value_json)`, or null for an unknown key or a bad value. Volumes clamp to 0..1. */
    fun parseSetting(key: String, valueJson: String): SettingUpdate? {
        val value = runCatching { json.parseToJsonElement(valueJson) }.getOrNull() as? JsonPrimitive ?: return null
        return when (key) {
            "camera_games" -> value.takeIf { !it.isString }?.booleanOrNull?.let { SettingUpdate.CameraGames(it) }
            "game_music" -> value.takeIf { !it.isString }?.booleanOrNull?.let { SettingUpdate.GameMusic(it) }
            "music_volume" -> value.takeIf { !it.isString }?.doubleOrNull?.let { SettingUpdate.MusicVolume(it.coerceIn(0.0, 1.0)) }
            "sfx_volume" -> value.takeIf { !it.isString }?.doubleOrNull?.let { SettingUpdate.SfxVolume(it.coerceIn(0.0, 1.0)) }
            "lean_sensitivity" -> value.takeIf { it.isString }?.content
                ?.let { code -> LeanSensitivity.entries.firstOrNull { it.code == code } }
                ?.let { SettingUpdate.LeanSensitivity(it) }
            else -> null
        }
    }

    private fun difficultyOf(word: String?): Difficulty = when (word) {
        "easy" -> Difficulty.EASY
        "hard" -> Difficulty.HARD
        else -> Difficulty.STANDARD
    }

    private fun parseObject(text: String): JsonObject? =
        runCatching { json.parseToJsonElement(text) }.getOrNull() as? JsonObject

    private fun JsonObject.string(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content

    private fun JsonObject.number(key: String): Double? = (this[key] as? JsonPrimitive)?.doubleOrNull
}
