package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.PlanRejectReason
import dev.digitalducktape.openride.games.bridge.PlanRequestKind
import dev.digitalducktape.openride.games.bridge.PlanRequestMessage
import dev.digitalducktape.openride.games.bridge.PlanRequestSlot
import dev.digitalducktape.openride.games.bridge.PlanSegment
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SessionKind
import dev.digitalducktape.openride.games.bridge.SessionPlanMessage
import kotlin.math.roundToInt
import kotlin.random.Random
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
    fun toMessage(riderId: Long? = null, riderName: String? = null) = SessionPlanMessage(
        kind = kind,
        planId = planId,
        difficulty = difficulty,
        totalSec = totalSec,
        segments = segments.map { PlanSegment(it.gameId, it.role, it.durationSec) },
        riderId = riderId,
        riderName = riderName?.trim()?.takeIf { it.isNotEmpty() },
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

    /**
     * A circuit. With [cameraGames] false (the rider turned them off, or the camera isn't
     * available), its slots draw from pools without the camera games (#75).
     */
    @Serializable @SerialName("circuit")
    data class Circuit(
        val presetId: String,
        override val difficulty: Difficulty = Difficulty.STANDARD,
        val cameraGames: Boolean = true,
    ) : SessionRequest

    /**
     * A custom circuit from the Games hub's builder (spec §3.4): [slots] in order, each with
     * its gameplay seconds. With [cameraGames] false, camera games are substituted as in
     * [Circuit].
     */
    @Serializable @SerialName("custom")
    data class Custom(
        val slots: List<CustomSlot>,
        override val difficulty: Difficulty = Difficulty.STANDARD,
        val cameraGames: Boolean = true,
    ) : SessionRequest

    fun toJson(): String = json.encodeToString(serializer(), this)

    companion object {
        private val json = Json { ignoreUnknownKeys = true }

        /** Null for anything unreadable. */
        fun fromJson(text: String?): SessionRequest? =
            text?.let { runCatching { json.decodeFromString(serializer(), it) }.getOrNull() }
    }
}

/** One slot of a custom circuit: a game and its gameplay seconds (normalised by [SessionPlans.custom]). */
@Serializable
data class CustomSlot(val gameId: String, val durationSec: Int)

/** What a hub `start_plan` request maps to: a [SessionRequest] to plan, or why it can't be played. */
sealed interface RequestMapping {
    data class Ok(val request: SessionRequest) : RequestMapping
    data class Rejected(val reason: PlanRejectReason) : RequestMapping
}

/**
 * Maps the hub's `start_plan` request onto a [SessionRequest] (spec §3.4). [cameraGames] is
 * Kotlin's own view (the setting, the permission and the camera): Godot never sends it. A Just
 * Ride of a camera game without the camera is rejected; circuits substitute instead.
 */
fun PlanRequestMessage.toSessionRequest(cameraGames: Boolean, catalog: GameCatalog): RequestMapping = when (kind) {
    PlanRequestKind.JUST_RIDE -> {
        val game = catalog[gameId]
        val mode = when (mode) {
            "minutes" -> JustRideMode.Timed(length) to JustRideSupport.MINUTES
            "rounds" -> JustRideMode.Rounds(length) to JustRideSupport.ROUNDS
            "open" -> JustRideMode.Open to JustRideSupport.OPEN
            else -> null
        }
        when {
            game == null -> RequestMapping.Rejected(PlanRejectReason.UNKNOWN_GAME)
            mode == null || mode.second !in game.supports -> RequestMapping.Rejected(PlanRejectReason.UNSUPPORTED_MODE)
            game.usesCamera && !cameraGames -> RequestMapping.Rejected(PlanRejectReason.CAMERA_UNAVAILABLE)
            else -> RequestMapping.Ok(SessionRequest.JustRide(game.id, mode.first, difficulty))
        }
    }
    PlanRequestKind.CIRCUIT ->
        if (CircuitPresets[presetId] == null) RequestMapping.Rejected(PlanRejectReason.UNKNOWN_GAME)
        else RequestMapping.Ok(SessionRequest.Circuit(presetId, difficulty, cameraGames))
    PlanRequestKind.CUSTOM -> {
        val custom = slots.map { CustomSlot(it.gameId, it.durationSec) }
        SessionPlans.customProblem(custom, catalog, cameraGames)?.let { RequestMapping.Rejected(it) }
            ?: RequestMapping.Ok(SessionRequest.Custom(custom, difficulty, cameraGames))
    }
}

/**
 * The hub's `start_plan` request for this app-side request: the inverse of
 * [PlanRequestMessage.toSessionRequest] (SessionPlansTest pins the round trip). `cameraGames`
 * isn't carried: the visit applies its own.
 */
fun SessionRequest.toPlanRequest(): PlanRequestMessage = when (this) {
    is SessionRequest.JustRide -> when (val m = mode) {
        is JustRideMode.Timed -> PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = gameId, mode = "minutes", length = m.minutes, difficulty = difficulty)
        is JustRideMode.Rounds -> PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = gameId, mode = "rounds", length = m.rounds, difficulty = difficulty)
        JustRideMode.Open -> PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = gameId, mode = "open", difficulty = difficulty)
    }
    is SessionRequest.Circuit -> PlanRequestMessage(PlanRequestKind.CIRCUIT, presetId = presetId, difficulty = difficulty)
    is SessionRequest.Custom -> PlanRequestMessage(
        PlanRequestKind.CUSTOM,
        difficulty = difficulty,
        slots = slots.map { PlanRequestSlot(it.gameId, it.durationSec) },
    )
}

/** One slot of a circuit preset: its role and gameplay seconds. The game is drawn per ride (#75). */
data class CircuitSlot(val role: SegmentRole, val durationSec: Int)

/**
 * A circuit (epic #31, "Sessions, circuits and Just Ride"): warm-up, [blocks] × [block], then
 * cool-down, each slot after a 10 s intro card. Presets are shapes only: each ride draws the
 * slots' games from their roles' pools ([CircuitDraw]).
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
    private val WARMUP = CircuitSlot(SegmentRole.WARMUP, 180)
    private val COOLDOWN = CircuitSlot(SegmentRole.COOLDOWN, 180)

    /** Work : recovery between 1:1 and 1:1.5, never two work games back to back. 6:10 with intro cards. */
    private val BLOCK = listOf(
        CircuitSlot(SegmentRole.WORK, 60),
        CircuitSlot(SegmentRole.RECOVERY, 90),
        CircuitSlot(SegmentRole.WORK, 90),
        CircuitSlot(SegmentRole.RECOVERY, 90),
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

/**
 * Draws a circuit's games (#75), one slot at a time in circuit order, from each role's
 * [GameCatalog.circuitPool], with a [Random] of the ride's [seed] (same seed, same lineup).
 *
 * - A game fills a slot only if the slot's length is within its `min_sec`..`max_sec`.
 * - Each role keeps a shuffled bag of its pool: a slot takes the first game in the bag that fits,
 *   so no game repeats in a role until every game that fits the slot has played. Then the bag
 *   refills (the game just played goes to its end, so it doesn't play twice running).
 * - A slot prefers a game that fits fewer of the role's slot lengths (Ready for Launch, 90 s,
 *   takes a 1:30 work slot before a game that also fits 1:00), so long slots use up the games
 *   only they can play, and the short slots don't run out first.
 * - Never the game of the slot before, when another fits.
 * - A slot no pool game fits returns null: [SessionPlans.circuit] plays its stand-in.
 */
class CircuitDraw(
    private val catalog: GameCatalog,
    private val cameraGames: Boolean,
    seed: Long,
    /** Every slot length per role in this circuit, for the "fits fewer lengths" preference. */
    private val roleLengths: Map<SegmentRole, Set<Int>> = emptyMap(),
) {
    private val random = Random(seed)
    private val bags = mutableMapOf<SegmentRole, MutableList<GameDeclaration>>()
    private val lastOfRole = mutableMapOf<SegmentRole, String>()
    private var previous: String? = null

    fun next(role: SegmentRole, durationSec: Int): GameDeclaration? {
        val pool = catalog.circuitPool(role, cameraGames)
        if (pool.none { fits(it, durationSec) }) {
            previous = null // the stand-in plays it
            return null
        }
        val bag = bags.getOrPut(role) { mutableListOf() }
        if (bag.none { fits(it, durationSec) }) {
            bag.clear()
            bag += pool.shuffled(random)
            lastOfRole[role]?.let { last -> bag.firstOrNull { it.id == last }?.let { bag.remove(it); bag.add(it) } }
        }
        val lengths = roleLengths[role].orEmpty()
        val candidates = bag.filter { fits(it, durationSec) }
            .sortedBy { game -> lengths.count { fits(game, it) } } // stable: the bag's order breaks ties
        val pick = candidates.firstOrNull { it.id != previous } ?: candidates.first()
        bag.remove(pick)
        lastOfRole[role] = pick.id
        previous = pick.id
        return pick
    }

    companion object {
        fun fits(game: GameDeclaration, durationSec: Int): Boolean = durationSec in game.minSec..game.maxSec
    }
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
     * A circuit from [preset]: each slot's game drawn from its role's pool with the ride's
     * [seed] ([CircuitDraw]), keeping the slot's role and length and the circuit's id, so its
     * bests stay per length whichever games played. With [cameraGames] false the pools leave
     * out camera games. A slot no game in [catalog] fits plays [standIn].
     */
    fun circuit(
        preset: CircuitPreset,
        difficulty: Difficulty,
        ftp: FtpBasis,
        catalog: GameCatalog,
        standIn: GameDeclaration = GameCatalog.DEMO,
        cameraGames: Boolean = true,
        seed: Long = 0L,
    ): SessionPlan {
        val lengths = preset.slots.groupBy { it.role }.mapValues { (_, slots) -> slots.map { it.durationSec }.toSet() }
        val draw = CircuitDraw(catalog, cameraGames, seed, lengths)
        val segments = preset.slots.map { slot ->
            val game = draw.next(slot.role, slot.durationSec) ?: standIn
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

    /** A custom circuit's limits (spec §3.4). */
    const val CUSTOM_MAX_SLOTS = 12
    const val CUSTOM_MAX_SEC = 90 * 60
    private const val CUSTOM_STEP_SEC = 30

    /** Why [slots] can't be played as a custom circuit, or null if they can. */
    fun customProblem(slots: List<CustomSlot>, catalog: GameCatalog, cameraGames: Boolean = true): PlanRejectReason? {
        if (slots.isEmpty()) return PlanRejectReason.EMPTY_CIRCUIT
        if (slots.size > CUSTOM_MAX_SLOTS) return PlanRejectReason.TOO_LONG
        val games = slots.map { catalog[it.gameId] ?: return PlanRejectReason.UNKNOWN_GAME }
        if (slots.zip(games).sumOf { (slot, game) -> customSeconds(game, slot.durationSec) } > CUSTOM_MAX_SEC) {
            return PlanRejectReason.TOO_LONG
        }
        if (!cameraGames && games.any { customGame(it, catalog, false) == null }) {
            return PlanRejectReason.CAMERA_UNAVAILABLE
        }
        return null
    }

    /**
     * A custom circuit (spec §3.4). Each slot's seconds are rounded to 30 s and clamped to its
     * game's limits; its role is the game's [GameCatalog.circuitRole], except that the first
     * slot plays warm-up and the last cool-down when the game has those roles. A `free` slot
     * (Kart Race) is scaled and ended as in a Just Ride. The id is `custom:` plus the lineup,
     * `<game>.<sec>` joined by `,`, so the same lineup keys the same bests. With [cameraGames]
     * false, a camera game's slot goes to the first camera-free game of its role, keeping the id.
     * Throws [IllegalArgumentException] for slots [customProblem] rejects.
     */
    fun custom(
        slots: List<CustomSlot>,
        difficulty: Difficulty,
        ftp: FtpBasis,
        catalog: GameCatalog,
        cameraGames: Boolean = true,
    ): SessionPlan {
        customProblem(slots, catalog, cameraGames)?.let { throw IllegalArgumentException("custom circuit: $it") }
        val planned = slots.map { catalog[it.gameId]!! }
        val seconds = slots.zip(planned).map { (slot, game) -> customSeconds(game, slot.durationSec) }
        val segments = planned.mapIndexed { i, requested ->
            val role = customRole(requested, i, planned.size)
            val game = customGame(requested, catalog, cameraGames)!!
            val free = role == SegmentRole.FREE
            Segment(
                gameId = game.id,
                durationSec = seconds[i],
                role = role,
                params = JsonObject(
                    FtpScaling.params(if (free) game.freeRideScaling else role, difficulty, ftp) +
                        game.params(role, difficulty, ftp),
                ),
                endMode = game.timedEndMode,
                effort = if (free) game.effortInJustRide else role == SegmentRole.WORK,
            )
        }
        val id = "custom:" + planned.indices.joinToString(",") { "${planned[it].id}.${seconds[it]}" }
        return SessionPlan(SessionKind.CIRCUIT, id, difficulty, segments, ftp)
    }

    /** A slot's role in a custom circuit (shown by the hub's builder, which mirrors this rule). */
    fun customRole(game: GameDeclaration, index: Int, count: Int): SegmentRole = when {
        index == 0 && SegmentRole.WARMUP in game.roles -> SegmentRole.WARMUP
        index == count - 1 && count > 1 && SegmentRole.COOLDOWN in game.roles -> SegmentRole.COOLDOWN
        else -> GameCatalog.circuitRole(game)
    }

    private fun customSeconds(game: GameDeclaration, sec: Int): Int =
        (Math.round(sec / CUSTOM_STEP_SEC.toDouble()).toInt() * CUSTOM_STEP_SEC).coerceIn(game.minSec, game.maxSec)

    /** [game], or with the camera off the first camera-free game of the same circuit role (null if none). */
    private fun customGame(game: GameDeclaration, catalog: GameCatalog, cameraGames: Boolean): GameDeclaration? =
        if (cameraGames || !game.usesCamera) game
        else catalog.games.firstOrNull { !it.usesCamera && GameCatalog.circuitRole(it) == GameCatalog.circuitRole(game) }

    /**
     * The plan for [request], or null if it names an unknown game or preset or an unsupported
     * mode. [circuitSeed] draws a preset circuit's games (the ride's seed; the hub shows the
     * lineup drawn with the same one).
     */
    fun forRequest(request: SessionRequest, ftp: FtpBasis, catalog: GameCatalog, circuitSeed: Long = 0L): SessionPlan? = when (request) {
        is SessionRequest.JustRide -> catalog[request.gameId]?.let { game ->
            runCatching { justRide(game, request.mode, request.difficulty, ftp) }.getOrNull()
        }
        is SessionRequest.Circuit -> CircuitPresets[request.presetId]?.let {
            circuit(it, request.difficulty, ftp, catalog, cameraGames = request.cameraGames, seed = circuitSeed)
        }
        is SessionRequest.Custom -> runCatching {
            custom(request.slots, request.difficulty, ftp, catalog, request.cameraGames)
        }.getOrNull()
    }

    private data class JustRidePlan(val suffix: String, val durationSec: Int, val endMode: EndMode, val params: Map<String, JsonElement>)

    private fun ceilDiv(a: Int, b: Int) = (a + b - 1) / b
}
