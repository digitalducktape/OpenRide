package dev.digitalducktape.openride.games.session

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** The Games hub's settings (#38): game audio, and whether camera games are on. */
data class GamesSettings(
    val audio: GameAudioPrefs = GameAudioPrefs(),
    /** Off: circuits play a camera-free game in place of each camera game, and Just Rides of camera games are unavailable. */
    val cameraGames: Boolean = true,
)

/** Where [GamesSettings] live: read by the session manager at each segment, edited by the hub. */
interface GamesSettingsStore {
    val settings: StateFlow<GamesSettings>
    fun update(transform: (GamesSettings) -> GamesSettings)
}

/** A store that keeps its settings in memory, for tests. */
class InMemoryGamesSettingsStore(initial: GamesSettings = GamesSettings()) : GamesSettingsStore {
    private val state = MutableStateFlow(initial)
    override val settings: StateFlow<GamesSettings> = state.asStateFlow()
    override fun update(transform: (GamesSettings) -> GamesSettings) {
        state.value = transform(state.value)
    }
}

/** The real store: SharedPreferences, so the settings survive restarts. */
class SharedPrefsGamesSettingsStore(context: Context) : GamesSettingsStore {
    private val prefs = context.applicationContext.getSharedPreferences("games_settings", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(read())
    override val settings: StateFlow<GamesSettings> = state.asStateFlow()

    override fun update(transform: (GamesSettings) -> GamesSettings) {
        val next = transform(state.value)
        prefs.edit()
            .putString(KEY_MUSIC, next.audio.music.name)
            .putFloat(KEY_MUSIC_VOLUME, next.audio.musicVolume.toFloat())
            .putFloat(KEY_SFX_VOLUME, next.audio.sfxVolume.toFloat())
            .putBoolean(KEY_CAMERA_GAMES, next.cameraGames)
            .apply()
        state.value = next
    }

    private fun read() = GamesSettings(
        audio = GameAudioPrefs(
            music = prefs.getString(KEY_MUSIC, null)?.let { runCatching { GameMusicMode.valueOf(it) }.getOrNull() } ?: GameMusicMode.AUTO,
            musicVolume = prefs.getFloat(KEY_MUSIC_VOLUME, 0.8f).toDouble(),
            sfxVolume = prefs.getFloat(KEY_SFX_VOLUME, 1.0f).toDouble(),
        ),
        cameraGames = prefs.getBoolean(KEY_CAMERA_GAMES, true),
    )

    private companion object {
        const val KEY_MUSIC = "music"
        const val KEY_MUSIC_VOLUME = "music_volume"
        const val KEY_SFX_VOLUME = "sfx_volume"
        const val KEY_CAMERA_GAMES = "camera_games"
    }
}
