package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.data.GamePersonalBest
import dev.digitalducktape.openride.core.data.PlanBestRow
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.games.bridge.CameraPermission
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.HubBests
import dev.digitalducktape.openride.games.bridge.HubCamera
import dev.digitalducktape.openride.games.bridge.HubCatalogGame
import dev.digitalducktape.openride.games.bridge.HubCircuit
import dev.digitalducktape.openride.games.bridge.HubCircuitSlot
import dev.digitalducktape.openride.games.bridge.HubGameBest
import dev.digitalducktape.openride.games.bridge.HubPhase
import dev.digitalducktape.openride.games.bridge.HubPlanBest
import dev.digitalducktape.openride.games.bridge.HubRider
import dev.digitalducktape.openride.games.bridge.HubSettings
import dev.digitalducktape.openride.games.bridge.HubStateMessage
import dev.digitalducktape.openride.games.bridge.HubVisit
import dev.digitalducktape.openride.games.bridge.HubVisitPlan

/** One result this visit has played, as the hub's bests need it. */
data class VisitResult(
    val planId: String,
    val planRun: Int,
    val gameId: String,
    val difficulty: String,
    val variant: String,
    val score: Double,
    val stars: Int,
    val skipped: Boolean,
    val playedSec: Int = 0,
)

/**
 * One plan this visit finished: its total (skips excluded) and its variant, `""` or a game's
 * variant when every played segment had it, null when mixed (as `GameResultDao.planBest`).
 */
data class VisitPlan(
    val planId: String,
    val difficulty: Difficulty,
    val variant: String?,
    val score: Double,
    val stars: Int,
    val gameIds: List<String>,
)

/** Everything `hub_state` is built from. */
data class HubInputs(
    val visitId: String,
    val phase: HubPhase,
    val profile: Profile?,
    val avatarPng: String?,
    val settings: GamesSettings,
    val permission: CameraPermission,
    /** The camera couldn't be used (no face found, no camera): cleared by the next calibration. */
    val cameraFailed: Boolean,
    val calibrated: String,
    val sameDayExtremes: Boolean,
    val catalog: GameCatalog,
    val gameBests: List<GamePersonalBest>,
    val planBests: List<PlanBestRow>,
    val recording: Boolean,
    val rideSec: Int,
    val visitResults: List<VisitResult>,
    val visitPlans: List<VisitPlan>,
    /** The seed the next preset circuit draws its games with (#75): the hub shows that lineup. */
    val circuitSeed: Long = 0L,
)

/**
 * Builds `hub_state` (Games hub spec §3.1): a pure function of the visit's inputs, so every
 * rule is unit-testable. `GameVisitManager` gathers the inputs and coalesces the sends.
 */
object HubStateBuilder {
    /** The lengths the hub offers for timed games, within each game's limits (the old Games tab's steps). */
    val MINUTE_STEPS = listOf(5, 10, 15, 20, 30, 45, 60)

    /** Custom circuits whose bests the hub gets: the most recently played. */
    const val CUSTOM_BESTS = 20

    private const val GUEST_COLOR = "#808080"

    fun build(inputs: HubInputs): HubStateMessage {
        val ftp = FtpBasis.of(inputs.profile?.ftp)
        val cameraAvailable = cameraAvailable(inputs.permission, inputs.settings.cameraGames, inputs.cameraFailed)
        return HubStateMessage(
            visitId = inputs.visitId,
            phase = inputs.phase,
            rider = inputs.profile?.let {
                HubRider(it.id, it.name.trim(), inputs.avatarPng, colorHex(it.avatarColor), ftp.watts, ftp.isFallback)
            } ?: HubRider(null, "", null, GUEST_COLOR, ftp.watts, ftp.isFallback),
            settings = HubSettings(
                cameraGames = inputs.settings.cameraGames,
                gameMusic = inputs.settings.audio.gameMusic,
                musicVolume = inputs.settings.audio.musicVolume,
                sfxVolume = inputs.settings.audio.sfxVolume,
            ),
            audio = inputs.settings.audio.resolve(),
            camera = HubCamera(inputs.permission, cameraAvailable, inputs.calibrated, inputs.sameDayExtremes),
            catalog = inputs.catalog.games.filter { it.id != GameCatalog.DEMO.id }.map(::catalogGame),
            circuits = CircuitPresets.ALL.map { preset ->
                val plan = SessionPlans.circuit(preset, Difficulty.STANDARD, ftp, inputs.catalog, cameraGames = cameraAvailable, seed = inputs.circuitSeed)
                HubCircuit(
                    id = preset.id,
                    minutes = preset.labelMinutes,
                    totalSec = plan.totalSec,
                    slots = plan.segments.map { HubCircuitSlot(it.gameId, it.role, it.durationSec) },
                )
            },
            bests = HubBests(gameBests(inputs), planBests(inputs)),
            visit = HubVisit(
                recording = inputs.recording,
                rideSec = inputs.rideSec,
                gameplaySec = inputs.visitResults.sumOf { it.playedSec },
                plans = inputs.visitPlans.map { HubVisitPlan(it.planId, it.difficulty, it.score, it.stars, it.gameIds) },
            ),
        )
    }

    /** `hub_state.camera.available`, and what plans use as `cameraGames`. */
    fun cameraAvailable(permission: CameraPermission, cameraGames: Boolean, cameraFailed: Boolean): Boolean =
        permission == CameraPermission.GRANTED && cameraGames && !cameraFailed

    private fun catalogGame(game: GameDeclaration) = HubCatalogGame(
        id = game.id,
        title = game.title,
        supports = listOfNotNull(
            "minutes".takeIf { JustRideSupport.MINUTES in game.supports },
            "rounds".takeIf { JustRideSupport.ROUNDS in game.supports },
            "open".takeIf { JustRideSupport.OPEN in game.supports },
        ),
        minSec = game.minSec,
        maxSec = game.maxSec,
        minRounds = game.minRounds,
        maxRounds = game.maxRounds,
        roundSec = game.roundSec,
        roles = game.roles.sortedBy { it.ordinal },
        usesCamera = game.usesCamera,
        minuteSteps = MINUTE_STEPS.filter { it * 60 in game.minSec..game.maxSec }.ifEmpty { listOf(game.minSec / 60) },
        circuitRole = GameCatalog.circuitRole(game),
    )

    private data class GameKey(val gameId: String, val planId: String, val difficulty: String, val variant: String)

    private fun gameBests(inputs: HubInputs): List<HubGameBest> {
        val merged = linkedMapOf<GameKey, Triple<Double, Int, Int>>()
        fun add(key: GameKey, score: Double, stars: Int, plays: Int) {
            val old = merged[key]
            merged[key] = if (old == null) Triple(score, stars, plays) else Triple(maxOf(old.first, score), maxOf(old.second, stars), old.third + plays)
        }
        inputs.gameBests.forEach { add(GameKey(it.gameId, it.gamePlan, it.difficulty, it.variant), it.bestScore, it.bestStars, it.plays) }
        inputs.visitResults.filterNot { it.skipped }.forEach { add(GameKey(it.gameId, it.planId, it.difficulty, it.variant), it.score, it.stars, 1) }
        return merged.entries
            .mapNotNull { (key, best) ->
                difficultyOf(key.difficulty)?.let { HubGameBest(key.gameId, key.planId, it, key.variant, best.first, best.second, best.third) }
            }
            .sortedWith(compareBy({ it.gameId }, { it.variant }, { it.planId }, { it.difficulty.ordinal }))
    }

    private fun planBests(inputs: HubInputs): List<HubPlanBest> {
        data class Best(val score: Double, val stars: Int, val lastPlayed: Long)
        val merged = linkedMapOf<Pair<String, Difficulty>, Best>()
        fun add(planId: String, difficulty: Difficulty, score: Double, stars: Int, lastPlayed: Long) {
            val key = planId to difficulty
            val old = merged[key]
            merged[key] = if (old == null) Best(score, stars, lastPlayed)
            else Best(maxOf(old.score, score), maxOf(old.stars, stars), maxOf(old.lastPlayed, lastPlayed))
        }
        inputs.planBests.forEach { row -> difficultyOf(row.difficulty)?.let { add(row.planId, it, row.bestScore, row.bestStars, row.lastPlayedMs) } }
        // This visit's runs aren't saved yet: they're the most recent of all.
        inputs.visitPlans.forEach { add(it.planId, it.difficulty, it.score, it.stars, Long.MAX_VALUE) }
        val presets = CircuitPresets.ALL.map { it.id }.toSet()
        val recentCustom = merged.entries
            .filter { it.key.first.startsWith(GameLabels.CUSTOM_PREFIX) }
            .groupBy { it.key.first }
            .map { (planId, rows) -> planId to rows.maxOf { it.value.lastPlayed } }
            .sortedByDescending { it.second }
            .take(CUSTOM_BESTS)
            .map { it.first }
            .toSet()
        return merged.entries
            .filter { it.key.first in presets || it.key.first in recentCustom }
            .map { (key, best) -> HubPlanBest(key.first, key.second, best.score, best.stars) }
            .sortedWith(compareBy({ it.planId }, { it.difficulty.ordinal }))
    }

    private fun difficultyOf(word: String): Difficulty? = Difficulty.entries.firstOrNull { it.name.lowercase() == word }

    private fun colorHex(argb: Int): String = "#%06X".format(argb and 0xFFFFFF)
}
