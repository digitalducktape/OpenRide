package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.SegmentRole
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
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

    /**
     * The games a circuit preset's [role] slots draw from (#75): every game that declares the
     * role, in catalog order, without the demo, and without the camera games (those that declare
     * [GameDeclaration.usesCamera]) when [cameraGames] is false. A new game joins circuits by
     * declaring roles; nothing else lists it.
     */
    fun circuitPool(role: SegmentRole, cameraGames: Boolean = true): List<GameDeclaration> =
        games.filter { role in it.roles && it.id != DEMO.id && (cameraGames || !it.usesCamera) }

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

        /**
         * Cadence Karaoke (#42), `games/games/cadence_karaoke/`: a rhythm game for the legs. The
         * rider picks and adjusts their own pace; a circuit segment sends a `cadence_profile`
         * (the shape of the target, which the rider's pace shifts as a whole). No effort
         * multiplier. A Just Ride is scaled as recovery, and the game applies the Endurance cap
         * itself.
         */
        val CADENCE_KARAOKE = GameDeclaration(
            id = "cadence_karaoke",
            title = "Cadence Karaoke",
            supports = setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN),
            minSec = 60,
            maxSec = 3600,
            roles = setOf(SegmentRole.WARMUP, SegmentRole.RECOVERY, SegmentRole.COOLDOWN),
            freeRideScaling = SegmentRole.RECOVERY,
            params = { role, _, _ ->
                // The target's shape as (seconds, rpm) points: a warm-up ramp, a steady recovery
                // and a cool-down ramp, each as long as its circuit slot (the game cycles it if
                // the segment runs longer). A Just Ride sends none: the rider picks the pace.
                val points = when (role) {
                    SegmentRole.WARMUP -> listOf(0 to 70, 180 to 90)
                    SegmentRole.RECOVERY -> listOf(0 to 80, 90 to 85)
                    SegmentRole.COOLDOWN -> listOf(0 to 85, 180 to 65)
                    else -> emptyList()
                }
                if (points.isEmpty()) emptyMap()
                else mapOf(
                    "cadence_profile" to JsonArray(points.map { (t, rpm) ->
                        JsonObject(mapOf("t" to JsonPrimitive(t), "rpm" to JsonPrimitive(rpm)))
                    }),
                )
            },
        )

        /**
         * Kart Race (#43), `games/games/kart_race/`: a Grand Prix against seven bots, driven by
         * pedalling and steered by leaning. A timed Just Ride ends on the final race's finish
         * line ([EndMode.GAME]), with Kotlin's usual hard stop at 1.5 ×. No circuit roles.
         * `bot_pcts` are the bots' shares of the rider's FTP, weakest first. The kart is driven
         * by watts plus a cadence term (rider feedback 2026-10-19), the bots' too, so these are
         * tuned for an ordinary ride (80-90 rpm at 30-40%) to sit mid-pack at a 150 W FTP;
         * `drift_resistance` is the resistance at which
         * the knob speeds up a drift's charge.
         */
        val KART_RACE = GameDeclaration(
            id = "kart_race",
            title = "Kart Race",
            supports = setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN),
            minSec = 300,
            maxSec = 3600,
            usesCamera = true,
            effortInJustRide = true,
            timedEndMode = EndMode.GAME,
            params = { _, difficulty, _ ->
                val (weakest, strongest, knob) = when (difficulty) {
                    Difficulty.EASY -> Triple(0.40, 0.85, 35)
                    Difficulty.STANDARD -> Triple(0.50, 1.00, 40)
                    Difficulty.HARD -> Triple(0.60, 1.15, 45)
                }
                val shares = (0 until KART_BOTS).map { i ->
                    val share = weakest + (strongest - weakest) * i / (KART_BOTS - 1)
                    JsonPrimitive(Math.round(share * 1000) / 1000.0)
                }
                mapOf(
                    "bot_pcts" to JsonArray(shares),
                    "drift_resistance" to JsonPrimitive(knob),
                )
            },
        )

        /**
         * Watt Lane (#78), `games/games/watt_lane/`: a work game (and a low-profile warm-up). Smoothed
         * power is the rider's place across a night highway; a lane of watts drifts and jumps, and
         * every jump is announced 5 s ahead. Params, in watts on a 5 W grid: the lane's width (a
         * share of FTP with a floor, rounded up to 10 W) and its centre's range (shares of FTP).
         * Low on purpose (about half of FTP): the forgiving-thresholds lesson. The game widens a
         * range too narrow for a jump of over half a lane (watt_lane/DESIGN.md).
         */
        val WATT_LANE = GameDeclaration(
            id = "watt_lane",
            title = "Watt Lane",
            supports = setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN),
            minSec = 60,
            maxSec = 3600,
            roles = setOf(SegmentRole.WORK, SegmentRole.WARMUP),
            effortInJustRide = true,
            params = { role, difficulty, ftp ->
                val (widthShare, widthFloor) = when (difficulty) {
                    Difficulty.EASY -> 0.25 to 50
                    Difficulty.STANDARD -> 0.20 to 40
                    Difficulty.HARD -> 0.15 to 30
                }
                val (low, high) = when {
                    role == SegmentRole.WARMUP -> 0.35 to 0.55
                    difficulty == Difficulty.EASY -> 0.40 to 0.60
                    difficulty == Difficulty.STANDARD -> 0.45 to 0.70
                    else -> 0.50 to 0.75
                }
                val width = maxOf(Math.ceil(ftp.watts * widthShare / 10.0).toInt() * 10, widthFloor)
                fun grid(share: Double) = (ftp.watts * share / 5.0).roundToInt() * 5
                mapOf(
                    "lane_width_watts" to JsonPrimitive(width),
                    "lane_min_watts" to JsonPrimitive(grid(low)),
                    "lane_max_watts" to JsonPrimitive(grid(high)),
                )
            },
        )

        /**
         * The role a custom-circuit slot of [game] plays (the Games hub, spec §3.4): `work` if
         * the game can work, else its main role (recovery before warm-up and cool-down), else
         * `free` (Kart Race). [SessionPlans.custom] still plays warm-up in the first slot and
         * cool-down in the last for a game that has those roles.
         */
        fun circuitRole(game: GameDeclaration): SegmentRole =
            CIRCUIT_ROLE_ORDER.firstOrNull { it in game.roles } ?: SegmentRole.FREE

        private val CIRCUIT_ROLE_ORDER = listOf(SegmentRole.WORK, SegmentRole.RECOVERY, SegmentRole.WARMUP, SegmentRole.COOLDOWN)

        /** Kart Race's bots (eight racers, the rider included). */
        private const val KART_BOTS = 7

        /** Every registered game. Each game issue adds its declaration here. */
        val DEFAULT = GameCatalog(listOf(DEMO, DODGE_BALL, TUG_OF_WAR, SAFE_CRACKER, CADENCE_KARAOKE, KART_RACE, WATT_LANE))
    }
}
