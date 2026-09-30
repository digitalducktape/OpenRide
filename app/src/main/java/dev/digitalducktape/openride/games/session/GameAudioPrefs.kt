package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.AudioSettings

/** The hub's "Game music" setting. */
enum class GameMusicMode {
    /** Off while the rider's own music plays, on otherwise. */
    AUTO,
    ON,
    OFF,
}

/**
 * The rider's game audio settings (the hub, #38, stores and edits them). Volumes are 0..1.
 */
data class GameAudioPrefs(
    val music: GameMusicMode = GameMusicMode.AUTO,
    val musicVolume: Double = 0.8,
    val sfxVolume: Double = 1.0,
) {
    /**
     * `segment.audio`, decided at each segment's start. With [GameMusicMode.AUTO], game music
     * stays off when [otherMusicActive] (the rider brought their own, see [OtherMusicDetector]);
     * effects always play.
     */
    fun resolve(otherMusicActive: Boolean) = AudioSettings(
        music = when (music) {
            GameMusicMode.ON -> true
            GameMusicMode.OFF -> false
            GameMusicMode.AUTO -> !otherMusicActive
        },
        musicVolume = musicVolume.coerceIn(0.0, 1.0),
        sfxVolume = sfxVolume.coerceIn(0.0, 1.0),
    )
}
