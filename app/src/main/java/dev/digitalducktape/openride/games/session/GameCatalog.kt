package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.SegmentRole
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive

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

        /** Every registered game. Each game issue adds its declaration here. */
        val DEFAULT = GameCatalog(listOf(DEMO))
    }
}
