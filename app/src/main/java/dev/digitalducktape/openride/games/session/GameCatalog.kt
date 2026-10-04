package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.SegmentRole
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlin.math.roundToInt

/** Just Ride modes a game supports (`GameInfo.supports`). */
enum class JustRideSupport { ROUNDS, MINUTES, OPEN }

/**
 * What Kotlin needs to know about a game to plan its sessions: the Kotlin mirror of the
 * GDScript declarations in `GameInfo` (docs/GAMES.md, "Adding a game"). Keep the two in step
 * when adding a game.
 *
 * @param roundSec how long one round usually takes, for `rounds` Just Rides: the segment's
 *   `duration_sec` is rounds × this, and the game ends the segment itself (`end_mode: game`),
 *   with Kotlin's usual hard stop at 1.5 ×.
 * @param timedEndMode `end_mode` for a timed (`minutes`) Just Ride: [EndMode.TIMER] unless the
 *   game ends on its own terms, like a race finishing on a lap line.
 * @param freeRideScaling which role's power scaling a Just Ride (`role: free`) uses:
 *   [SegmentRole.WORK] for a target at the difficulty's share of FTP, [SegmentRole.RECOVERY]
 *   (or warm-up / cool-down) for a power cap.
 * @param params the game's own `params` for a segment, on top of [FtpScaling.params].
 */
data class GameDeclaration(
    val id: String,
    val title: String,
    val supports: Set<JustRideSupport>,
    val minSec: Int = 60,
    val maxSec: Int = 3600,
    val minRounds: Int = 1,
    val maxRounds: Int = 10,
    val roundSec: Int = 60,
    val roles: Set<SegmentRole> = emptySet(),
    val usesCamera: Boolean = false,
    val effortInJustRide: Boolean = false,
    val timedEndMode: EndMode = EndMode.TIMER,
    val freeRideScaling: SegmentRole = SegmentRole.WORK,
    val params: (role: SegmentRole, difficulty: Difficulty, ftp: FtpBasis) -> Map<String, JsonElement> = { _, _, _ -> emptyMap() },
)

/** The games Kotlin can plan sessions for, by `game_id`. */
class GameCatalog(games: List<GameDeclaration>) {
    private val byId = games.associateBy { it.id }

    val games: List<GameDeclaration> = games

    operator fun get(gameId: String): GameDeclaration? = byId[gameId]

    companion object {
        /** The framework's reference game (#34), `games/games/demo/`. */
        val DEMO = GameDeclaration(
            id = "demo",
            title = "Demo",
            supports = setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN),
            minSec = 60,
            maxSec = 3600,
            roles = setOf(SegmentRole.WARMUP, SegmentRole.WORK, SegmentRole.RECOVERY, SegmentRole.COOLDOWN),
            usesCamera = true,
            effortInJustRide = true,
            params = { _, difficulty, _ ->
                // DemoLogic.LEVELS' cadence floors, sent so the demo shows how params reach a game.
                val floor = when (difficulty) {
                    Difficulty.EASY -> 55
                    Difficulty.STANDARD -> 60
                    Difficulty.HARD -> 70
                }
                mapOf("cadence_floor" to JsonPrimitive(floor))
            },
        )

        /** Dodge Ball (#39), `games/games/dodge_ball/`: a work game steered by leaning. */
        val DODGE_BALL = GameDeclaration(
            id = "dodge_ball",
            title = "Dodge Ball",
            supports = setOf(JustRideSupport.ROUNDS, JustRideSupport.MINUTES, JustRideSupport.OPEN),
            minSec = 60,
            maxSec = 3600,
            minRounds = 1,
            maxRounds = 10,
            roundSec = 90,
            roles = setOf(SegmentRole.WORK),
            usesCamera = true,
            effortInJustRide = true,
            params = { _, difficulty, _ ->
                // DodgeBallLogic.LEVELS: the cadence floor and the ball rate's ramp (balls a second).
                val (floor, start, end) = when (difficulty) {
                    Difficulty.EASY -> Triple(75, 0.5, 1.2)
                    Difficulty.STANDARD -> Triple(85, 0.6, 1.5)
                    Difficulty.HARD -> Triple(90, 0.7, 1.8)
                }
                mapOf(
                    "cadence_floor" to JsonPrimitive(floor),
                    "ball_rate_start" to JsonPrimitive(start),
                    "ball_rate_end" to JsonPrimitive(end),
                )
            },
        )

        /**
         * Tug of War (#40), `games/games/tug_of_war/`: a work game of watts against a bot's.
         * The camera only runs with the rider's "Brace lean" option, which Godot decides per
         * segment, so [GameDeclaration.usesCamera] stays false.
         */
        val TUG_OF_WAR = GameDeclaration(
            id = "tug_of_war",
            title = "Tug of War",
            supports = setOf(JustRideSupport.ROUNDS, JustRideSupport.MINUTES, JustRideSupport.OPEN),
            minSec = 60,
            maxSec = 3600,
            minRounds = 1,
            maxRounds = 10,
            // A best-of-N match: rounds of up to 60 s with a 60 s recovery between them.
            roundSec = 120,
            roles = setOf(SegmentRole.WORK),
            effortInJustRide = true,
            params = { _, difficulty, ftp ->
                // TugLogic: the bot holds 50 / 60 / 70% of FTP and surges 20% of FTP above that,
                // in watts (the game adds 5% of FTP a rung on the ladder). Low on purpose: the
                // first version, at 100-120%, asked more than a person can give.
                val bot = when (difficulty) {
                    Difficulty.EASY -> 0.5
                    Difficulty.STANDARD -> 0.6
                    Difficulty.HARD -> 0.7
                }
                mapOf(
                    "bot_watts" to JsonPrimitive((ftp.watts * bot).roundToInt()),
                    "surge_watts" to JsonPrimitive((ftp.watts * (bot + 0.2)).roundToInt()),
                )
            },
        )

        /**
         * Safe Cracker (#41), `games/games/safe_cracker/`: a recovery game played with the
         * resistance knob. No effort multiplier, and a Just Ride is scaled as recovery, so its
         * power cap is `power_cap_watts` (60% of FTP).
         */
        val SAFE_CRACKER = GameDeclaration(
            id = "safe_cracker",
            title = "Safe Cracker",
            supports = setOf(JustRideSupport.ROUNDS, JustRideSupport.MINUTES, JustRideSupport.OPEN),
            minSec = 60,
            maxSec = 3600,
            minRounds = 1,
            maxRounds = 10,
            // A round is one safe: about a minute to crack, with the door and the next safe.
            roundSec = 75,
            roles = setOf(SegmentRole.RECOVERY),
            freeRideScaling = SegmentRole.RECOVERY,
            params = { _, _, _ ->
                // SafeLogic's defaults, sent so a tuning change doesn't need a new game build:
                // the resistance range of the combinations and the dial's cadence floor.
                mapOf(
                    "res_min" to JsonPrimitive(15),
                    "res_max" to JsonPrimitive(40),
                    "cadence_min" to JsonPrimitive(60),
                )
            },
        )

        /** Every registered game. Each game issue adds its declaration here. */
        val DEFAULT = GameCatalog(listOf(DEMO, DODGE_BALL, TUG_OF_WAR, SAFE_CRACKER))
    }
}
