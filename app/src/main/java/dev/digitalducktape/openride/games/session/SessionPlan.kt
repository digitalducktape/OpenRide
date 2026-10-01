package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.PlanSegment
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SessionKind
import dev.digitalducktape.openride.games.bridge.SessionPlanMessage
import kotlin.math.roundToInt
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * The FTP a session's targets are scaled to. [isFallback] means the rider has no FTP set, so
 * [watts] is [FtpScaling.FALLBACK_FTP] and the hub shows a "set your FTP for accurate targets"
 * nudge.
 */
data class FtpBasis(val watts: Int, val isFallback: Boolean) {
    companion object {
        fun of(profileFtp: Int?): FtpBasis =
            if (profileFtp == null || profileFtp <= 0) FtpBasis(FtpScaling.FALLBACK_FTP, isFallback = true)
            else FtpBasis(profileFtp, isFallback = false)
    }
}

/**
 * Power targets from FTP (epic #31, "FTP scaling"): work at 90 / 105 / 120 % of FTP for easy /
 * standard / hard; recovery capped at 60 %, warm-up and cool-down at 65 %. Difficulty never
 * moves a cap: recovery games make themselves harder through their own params (tolerances,
 * hidden targets).
 */
object FtpScaling {
    const val FALLBACK_FTP = 150
    const val RECOVERY_CAP = 0.60
    const val WARM_COOL_CAP = 0.65

    fun workFraction(difficulty: Difficulty): Double = when (difficulty) {
        Difficulty.EASY -> 0.90
        Difficulty.STANDARD -> 1.05
        Difficulty.HARD -> 1.20
    }

    /**
     * The params every segment gets: `ftp_watts`, `ftp_is_default`, and `target_watts` for work
     * or `power_cap_watts` for recovery, warm-up and cool-down. [role] is the scaling role, so a
     * Just Ride passes its game's [GameDeclaration.freeRideScaling].
     */
    fun params(role: SegmentRole, difficulty: Difficulty, ftp: FtpBasis): Map<String, JsonElement> {
        val power = when (role) {
            SegmentRole.WORK, SegmentRole.FREE -> "target_watts" to ftp.watts * workFraction(difficulty)
            SegmentRole.RECOVERY -> "power_cap_watts" to ftp.watts * RECOVERY_CAP
            SegmentRole.WARMUP, SegmentRole.COOLDOWN -> "power_cap_watts" to ftp.watts * WARM_COOL_CAP
        }
        return mapOf(
            "ftp_watts" to JsonPrimitive(ftp.watts),
            "ftp_is_default" to JsonPrimitive(ftp.isFallback),
            power.first to JsonPrimitive(power.second.roundToInt()),
        )
    }
}

/**
 * One game in a session plan.
 *
 * @param durationSec gameplay seconds, intro card excluded; -1 for an open-ended Just Ride.
 * @param params game-specific, already scaled to FTP and difficulty.
 * @param effort whether the effort multiplier applies (`segment.effort`).
 */
data class Segment(
    val gameId: String,
    val durationSec: Int,
    val role: SegmentRole,
    val params: JsonObject,
    val endMode: EndMode,
    val effort: Boolean,
)

/**
 * What `GameSessionManager` walks: a list of [Segment]s, each after an [introSec] intro card.
 * [planId] is recorded as the ride's `gamePlan` and keys the rider's bests, so it names the
 * mode and length: `just-ride:<game>:minutes:<n>`, `just-ride:<game>:rounds:<n>`,
 * `just-ride:<game>:open`, or a circuit preset's id (`circuit-20`).
 */
data class SessionPlan(
    val kind: SessionKind,
    val planId: String,
    val difficulty: Difficulty,
    val segments: List<Segment>,
    val ftp: FtpBasis,
    val introSec: Int = INTRO_SEC,
) {
    init {
        require(segments.isNotEmpty()) { "a session plan needs at least one segment" }
    }

    /** Planned seconds, intro cards included, or -1 when any segment is open-ended. */
    val totalSec: Int
        get() = if (segments.any { it.durationSec < 0 }) -1 else segments.sumOf { it.durationSec + introSec }

    /** `session_started`'s payload. */
    fun toMessage(riderId: Long? = null) = SessionPlanMessage(
        kind = kind,
        planId = planId,
        difficulty = difficulty,
        totalSec = totalSec,
        segments = segments.map { PlanSegment(it.gameId, it.role, it.durationSec) },
        riderId = riderId,
    )

    companion object {
        /** The intro card before every segment (Bridge contract: 10 s). */
        const val INTRO_SEC = 10
    }
}

/** How long a Just Ride lasts. */
@Serializable
sealed interface JustRideMode {
    @Serializable @SerialName("minutes")
    data class Timed(val minutes: Int) : JustRideMode

    @Serializable @SerialName("rounds")
    data class Rounds(val rounds: Int) : JustRideMode

    /** Until the rider ends it. */
    @Serializable @SerialName("open")
    data object Open : JustRideMode
}

/** What the rider picked: turned into a [SessionPlan] once their FTP is known. */
@Serializable
sealed interface SessionRequest {
    val difficulty: Difficulty

    @Serializable @SerialName("just_ride")
    data class JustRide(val gameId: String, val mode: JustRideMode, override val difficulty: Difficulty = Difficulty.STANDARD) :
        SessionRequest

    @Serializable @SerialName("circuit")
    data class Circuit(val presetId: String, override val difficulty: Difficulty = Difficulty.STANDARD) : SessionRequest

    fun toJson(): String = json.encodeToString(serializer(), this)

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Null for anything unreadable. */
        fun fromJson(text: String?): SessionRequest? =
            text?.let { runCatching { json.decodeFromString(serializer(), it) }.getOrNull() }
    }
}

/** One slot of a circuit preset. */
data class CircuitSlot(val gameId: String, val role: SegmentRole, val durationSec: Int)

/**
 * A circuit (epic #31, "Sessions, circuits and Just Ride"): warm-up, [blocks] × [block], then
 * cool-down, each slot after a 10 s intro card. Presets are data; circuit mode and its UX are #37.
 */
data class CircuitPreset(
    val id: String,
    val labelMinutes: Int,
    val warmup: CircuitSlot,
    val block: List<CircuitSlot>,
    val blocks: Int,
    val cooldown: CircuitSlot,
) {
    val slots: List<CircuitSlot> get() = listOf(warmup) + List(blocks) { block }.flatten() + cooldown
}

object CircuitPresets {
    private val WARMUP = CircuitSlot("cadence_karaoke", SegmentRole.WARMUP, 180)
    private val COOLDOWN = CircuitSlot("cadence_karaoke", SegmentRole.COOLDOWN, 180)

    /** Work : recovery between 1:1 and 1:1.5, never two work games back to back. 6:10 with intro cards. */
    private val BLOCK = listOf(
        CircuitSlot("tug_of_war", SegmentRole.WORK, 60),
        CircuitSlot("safe_cracker", SegmentRole.RECOVERY, 90),
        CircuitSlot("dodge_ball", SegmentRole.WORK, 90),
        CircuitSlot("cadence_karaoke", SegmentRole.RECOVERY, 90),
    )

    private fun preset(minutes: Int, blocks: Int) =
        CircuitPreset("circuit-$minutes", minutes, WARMUP, BLOCK, blocks, COOLDOWN)

    /** 18:40. */
    val TWENTY = preset(20, blocks = 2)

    /** 31:00. */
    val THIRTY = preset(30, blocks = 4)

    /** 43:20. */
    val FORTY_FIVE = preset(45, blocks = 6)

    val ALL = listOf(TWENTY, THIRTY, FORTY_FIVE)

    operator fun get(id: String): CircuitPreset? = ALL.firstOrNull { it.id == id }
}

/** Builds [SessionPlan]s: Just Rides of any one game, and circuits from presets. */
object SessionPlans {
    /**
     * A Just Ride of [game], within its declared limits (lengths outside them are clamped).
     * Throws [IllegalArgumentException] for a mode the game doesn't support.
     */
    fun justRide(game: GameDeclaration, mode: JustRideMode, difficulty: Difficulty, ftp: FtpBasis): SessionPlan {
        val (planSuffix, durationSec, endMode, extra) = when (mode) {
            is JustRideMode.Timed -> {
                require(JustRideSupport.MINUTES in game.supports) { "${game.id} has no timed Just Ride" }
                val minutes = mode.minutes.coerceIn(ceilDiv(game.minSec, 60), maxOf(1, game.maxSec / 60))
                JustRidePlan("minutes:$minutes", minutes * 60, game.timedEndMode, emptyMap())
            }
            is JustRideMode.Rounds -> {
                require(JustRideSupport.ROUNDS in game.supports) { "${game.id} has no rounds Just Ride" }
                val rounds = mode.rounds.coerceIn(game.minRounds, game.maxRounds)
                JustRidePlan("rounds:$rounds", rounds * game.roundSec, EndMode.GAME, mapOf("rounds" to JsonPrimitive(rounds)))
            }
            JustRideMode.Open -> {
                require(JustRideSupport.OPEN in game.supports) { "${game.id} has no open-ended Just Ride" }
                JustRidePlan("open", -1, EndMode.GAME, emptyMap())
            }
        }
        val segment = Segment(
            gameId = game.id,
            durationSec = durationSec,
            role = SegmentRole.FREE,
            params = JsonObject(FtpScaling.params(game.freeRideScaling, difficulty, ftp) + game.params(SegmentRole.FREE, difficulty, ftp) + extra),
            endMode = endMode,
            effort = game.effortInJustRide,
        )
        return SessionPlan(SessionKind.JUST_RIDE, "just-ride:${game.id}:$planSuffix", difficulty, listOf(segment), ftp)
    }

    /**
     * A circuit from [preset]. A slot whose game isn't in [catalog] yet plays [standIn]
     * instead (the demo until the real games land, #37).
     */
    fun circuit(
        preset: CircuitPreset,
        difficulty: Difficulty,
        ftp: FtpBasis,
        catalog: GameCatalog,
        standIn: GameDeclaration = GameCatalog.DEMO,
    ): SessionPlan {
        val segments = preset.slots.map { slot ->
            val game = catalog[slot.gameId] ?: standIn
            Segment(
                gameId = game.id,
                durationSec = slot.durationSec,
                role = slot.role,
                params = JsonObject(FtpScaling.params(slot.role, difficulty, ftp) + game.params(slot.role, difficulty, ftp)),
                endMode = EndMode.TIMER,
                effort = slot.role == SegmentRole.WORK,
            )
        }
        return SessionPlan(SessionKind.CIRCUIT, preset.id, difficulty, segments, ftp)
    }

    /** The plan for [request], or null if it names an unknown game or preset or an unsupported mode. */
    fun forRequest(request: SessionRequest, ftp: FtpBasis, catalog: GameCatalog): SessionPlan? = when (request) {
        is SessionRequest.JustRide -> catalog[request.gameId]?.let { game ->
            runCatching { justRide(game, request.mode, request.difficulty, ftp) }.getOrNull()
        }
        is SessionRequest.Circuit -> CircuitPresets[request.presetId]?.let { circuit(it, request.difficulty, ftp, catalog) }
    }

    private data class JustRidePlan(val suffix: String, val durationSec: Int, val endMode: EndMode, val params: Map<String, JsonElement>)

    private fun ceilDiv(a: Int, b: Int) = (a + b - 1) / b
}
