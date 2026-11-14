package dev.digitalducktape.openride.core.telemetry

/**
 * What a game played over (#85): the rider's own track when one is actually playing, else the
 * game's music if the switch is on, else nothing.
 */
fun classify(gameMusicOn: Boolean, ownTrackPlaying: Boolean): GameMusic = when {
    ownTrackPlaying -> GameMusic.OWN_MUSIC
    gameMusicOn -> GameMusic.GAME_MUSIC
    else -> GameMusic.OFF
}

/** Folds a visit's [GameMusic] observations into one [VisitMusic]: more than one distinct value is `mixed`. */
class VisitMusicAccumulator {
    private val seen = mutableSetOf<GameMusic>()

    fun observe(music: GameMusic) {
        seen += music
    }

    fun result(): VisitMusic = when (seen.size) {
        0 -> VisitMusic.OFF
        1 -> when (seen.first()) {
            GameMusic.GAME_MUSIC -> VisitMusic.GAME_MUSIC
            GameMusic.OWN_MUSIC -> VisitMusic.OWN_MUSIC
            GameMusic.OFF -> VisitMusic.OFF
        }
        else -> VisitMusic.MIXED
    }
}

/** Sends the event [build] makes (none if it returns null); a failure building or sending it never reaches the caller. */
inline fun Telemetry.trackSafely(build: () -> TelemetryEvent?) {
    runCatching { build()?.let(::track) }
}
