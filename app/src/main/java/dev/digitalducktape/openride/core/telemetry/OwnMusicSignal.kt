package dev.digitalducktape.openride.core.telemetry

/** Whether the rider has a track actually playing in their own music app (not merely open or paused). */
fun interface OwnMusicSignal {
    fun trackPlaying(): Boolean
}
