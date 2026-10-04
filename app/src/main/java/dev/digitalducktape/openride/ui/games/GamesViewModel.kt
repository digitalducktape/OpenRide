package dev.digitalducktape.openride.ui.games

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.digitalducktape.openride.core.data.GamePersonalBest
import dev.digitalducktape.openride.core.data.PlanBest
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.session.CircuitPresets
import dev.digitalducktape.openride.games.session.FtpBasis
import dev.digitalducktape.openride.games.session.GameAudioPrefs
import dev.digitalducktape.openride.games.session.GameCatalog
import dev.digitalducktape.openride.games.session.GameDeclaration
import dev.digitalducktape.openride.games.session.GameMusicMode
import dev.digitalducktape.openride.games.session.GamesSettingsStore
import dev.digitalducktape.openride.games.session.JustRideMode
import dev.digitalducktape.openride.games.session.JustRideSupport
import dev.digitalducktape.openride.games.session.SessionPlans
import dev.digitalducktape.openride.games.session.SessionRequest
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update

/** Which kind of Just Ride a game card is set to. */
enum class RideKind { TIMED, ROUNDS, OPEN }

/** A circuit card: its length, the games in it and the rider's best total (if any). */
data class CircuitCard(val id: String, val title: String, val totalLabel: String, val lineup: String, val best: String?)

/** A Just Ride card for one game, with the options the game supports. */
data class GameCard(
    val id: String,
    val title: String,
    val kinds: List<RideKind>,
    val kind: RideKind,
    val minutes: Int,
    val minutesOptions: List<Int>,
    val rounds: Int,
    val roundsOptions: List<Int>,
    val difficulty: Difficulty,
    /** Camera games are off, so this game can't be started on its own. */
    val unavailable: Boolean,
    val usesCamera: Boolean,
    val best: String?,
)

data class GamesUiState(
    val ftpMissing: Boolean = false,
    val circuitDifficulty: Difficulty = Difficulty.STANDARD,
    val circuits: List<CircuitCard> = emptyList(),
    val games: List<GameCard> = emptyList(),
    val cameraGames: Boolean = true,
    val audio: GameAudioPrefs = GameAudioPrefs(),
)

/**
 * The Games tab (#38): circuit cards, a Just Ride card per game in the catalog (so a new game
 * appears without UI changes), the rider's bests, an FTP nudge and the game settings. Starting
 * something is [circuitRequest] / [justRideRequest]; the screen launches the games host with it.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GamesViewModel(
    private val catalog: GameCatalog,
    private val settingsStore: GamesSettingsStore,
    activeProfileId: Flow<Long?>,
    profileFtp: (Long) -> Flow<Int?>,
    personalBests: (Long) -> Flow<List<GamePersonalBest>>,
    private val circuitBest: suspend (profileId: Long, planId: String, difficulty: Difficulty) -> PlanBest?,
) : ViewModel() {
    private data class Pick(val kind: RideKind? = null, val minutes: Int? = null, val rounds: Int? = null, val difficulty: Difficulty = Difficulty.STANDARD)

    private val circuitDifficulty = MutableStateFlow(Difficulty.STANDARD)
    private val picks = MutableStateFlow<Map<String, Pick>>(emptyMap())

    private val ftpMissing: Flow<Boolean> = activeProfileId.flatMapLatest { id ->
        if (id == null) flowOf(false) else profileFtp(id).let { f -> combine(f, flowOf(Unit)) { ftp, _ -> ftp == null || ftp <= 0 } }
    }

    private val bests: Flow<List<GamePersonalBest>> = activeProfileId.flatMapLatest { id -> if (id == null) flowOf(emptyList()) else personalBests(id) }

    private val circuitBests: Flow<Map<String, PlanBest?>> =
        combine(activeProfileId, circuitDifficulty) { id, difficulty -> id to difficulty }.flatMapLatest { (id, difficulty) ->
            flow {
                emit(if (id == null) emptyMap() else CircuitPresets.ALL.associate { it.id to circuitBest(id, it.id, difficulty) })
            }
        }

    val state: StateFlow<GamesUiState> = combine(
        listOf(ftpMissing, bests, circuitBests, picks, circuitDifficulty, settingsStore.settings),
    ) { values ->
        @Suppress("UNCHECKED_CAST")
        build(
            values[0] as Boolean,
            values[1] as List<GamePersonalBest>,
            values[2] as Map<String, PlanBest?>,
            values[3] as Map<String, Pick>,
            values[4] as Difficulty,
            values[5] as dev.digitalducktape.openride.games.session.GamesSettings,
        )
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), GamesUiState())

    fun setCircuitDifficulty(difficulty: Difficulty) {
        circuitDifficulty.value = difficulty
    }

    fun setKind(gameId: String, kind: RideKind) = pick(gameId) { it.copy(kind = kind) }
    fun setMinutes(gameId: String, minutes: Int) = pick(gameId) { it.copy(minutes = minutes) }
    fun setRounds(gameId: String, rounds: Int) = pick(gameId) { it.copy(rounds = rounds) }
    fun setGameDifficulty(gameId: String, difficulty: Difficulty) = pick(gameId) { it.copy(difficulty = difficulty) }

    fun setCameraGames(on: Boolean) = settingsStore.update { it.copy(cameraGames = on) }
    fun setMusicMode(mode: GameMusicMode) = settingsStore.update { it.copy(audio = it.audio.copy(music = mode)) }
    fun setMusicVolume(volume: Double) = settingsStore.update { it.copy(audio = it.audio.copy(musicVolume = volume.coerceIn(0.0, 1.0))) }
    fun setEffectsVolume(volume: Double) = settingsStore.update { it.copy(audio = it.audio.copy(sfxVolume = volume.coerceIn(0.0, 1.0))) }

    /** The request to start circuit [presetId] at the picked difficulty. [cameraAvailable] is false when the camera permission was refused. */
    fun circuitRequest(presetId: String, cameraAvailable: Boolean = true) = SessionRequest.Circuit(
        presetId, circuitDifficulty.value, cameraGames = settingsStore.settings.value.cameraGames && cameraAvailable,
    )

    /** The request to start a Just Ride of [gameId] as its card is set, or null for an unknown or unavailable game. */
    fun justRideRequest(gameId: String): SessionRequest.JustRide? {
        val game = catalog[gameId] ?: return null
        val card = state.value.games.firstOrNull { it.id == gameId } ?: return null
        if (card.unavailable) return null
        val mode = when (card.kind) {
            RideKind.TIMED -> JustRideMode.Timed(card.minutes)
            RideKind.ROUNDS -> JustRideMode.Rounds(card.rounds)
            RideKind.OPEN -> JustRideMode.Open
        }
        return SessionRequest.JustRide(game.id, mode, card.difficulty)
    }

    private fun pick(gameId: String, change: (Pick) -> Pick) {
        picks.update { it + (gameId to change(it[gameId] ?: Pick())) }
    }

    private fun build(
        ftpMissing: Boolean,
        bests: List<GamePersonalBest>,
        circuitBests: Map<String, PlanBest?>,
        picks: Map<String, Pick>,
        circuitDifficulty: Difficulty,
        settings: dev.digitalducktape.openride.games.session.GamesSettings,
    ): GamesUiState {
        val circuits = CircuitPresets.ALL.map { preset ->
            val total = preset.slots.sumOf { it.durationSec + INTRO_SEC }
            val lineup = preset.slots.map { catalog[it.gameId]?.title ?: GameLabelsFallback.title(it.gameId) }.distinct().joinToString(" · ")
            val best = circuitBests[preset.id]?.takeIf { it.bestScore != null }?.let { "Best ${it.bestScore!!.toInt()} · ${it.bestStars ?: 0} stars" }
            CircuitCard(preset.id, "${preset.labelMinutes} min circuit", "%d:%02d".format(total / 60, total % 60), lineup, best)
        }
        val games = catalog.games.filter { it.id != "demo" }.map { game -> gameCard(game, picks[game.id] ?: Pick(), bests, settings.cameraGames) }
        return GamesUiState(ftpMissing, circuitDifficulty, circuits, games, settings.cameraGames, settings.audio)
    }

    private fun gameCard(game: GameDeclaration, pick: Pick, bests: List<GamePersonalBest>, cameraGames: Boolean): GameCard {
        val kinds = buildList {
            if (JustRideSupport.MINUTES in game.supports) add(RideKind.TIMED)
            if (JustRideSupport.ROUNDS in game.supports) add(RideKind.ROUNDS)
            if (JustRideSupport.OPEN in game.supports) add(RideKind.OPEN)
        }
        val kind = pick.kind?.takeIf { it in kinds } ?: kinds.first()
        val minutesOptions = MINUTE_STEPS.filter { it * 60 in game.minSec..game.maxSec }.ifEmpty { listOf(game.minSec / 60) }
        val minutes = pick.minutes?.takeIf { it in minutesOptions } ?: minutesOptions.firstOrNull { it >= DEFAULT_MINUTES } ?: minutesOptions.last()
        val roundsOptions = (game.minRounds..game.maxRounds).toList()
        val rounds = pick.rounds?.takeIf { it in roundsOptions } ?: roundsOptions.first()
        val mode = when (kind) {
            RideKind.TIMED -> JustRideMode.Timed(minutes)
            RideKind.ROUNDS -> JustRideMode.Rounds(rounds)
            RideKind.OPEN -> JustRideMode.Open
        }
        val plan = runCatching { SessionPlans.justRide(game, mode, pick.difficulty, FtpBasis.of(null)).planId }.getOrNull()
        val best = bests.filter { it.gameId == game.id && it.gamePlan == plan && it.difficulty == pick.difficulty.name.lowercase() }
            .maxByOrNull { it.bestScore }?.let { "Best ${it.bestScore.toInt()} · ${it.bestStars} stars" }
        return GameCard(
            id = game.id, title = game.title, kinds = kinds, kind = kind, minutes = minutes, minutesOptions = minutesOptions,
            rounds = rounds, roundsOptions = roundsOptions, difficulty = pick.difficulty,
            unavailable = game.usesCamera && !cameraGames, usesCamera = game.usesCamera, best = best,
        )
    }

    private object GameLabelsFallback {
        fun title(id: String) = id.split('_').joinToString(" ") { it.replaceFirstChar(Char::uppercase) }
    }

    companion object {
        const val INTRO_SEC = 10
        const val DEFAULT_MINUTES = 20
        val MINUTE_STEPS = listOf(5, 10, 15, 20, 30, 45, 60)
    }
}
