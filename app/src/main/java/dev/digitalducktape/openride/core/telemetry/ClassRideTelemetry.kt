package dev.digitalducktape.openride.core.telemetry

import dev.digitalducktape.openride.core.content.ContentCategory

/**
 * The class events of one video ride (#85): `class_start` when a class is started from the
 * Classes tab or a creator page, `class_end` once when the ride finishes, and
 * `class_player_error` from the embedded player. Remembers which channel the current class
 * is from, since the player screen only knows the video id.
 *
 * Nothing here throws into the ride: telemetry failing must not touch playback.
 */
class ClassRideTelemetry(private val telemetry: Telemetry) {
    private var channel: ChannelName? = null
    private var channelSource = ChannelSource.CUSTOM
    private var ended = true
    private var durationSec: Int? = null
    private var mutedAtStart: Boolean? = null
    private var mutedLater = false

    fun start(channel: ChannelName, channelSource: ChannelSource, category: ContentCategory, source: ClassSource) {
        this.channel = channel
        this.channelSource = channelSource
        ended = false
        durationSec = null
        mutedAtStart = null
        mutedLater = false
        emit(
            ClassStart(
                channel, channelSource,
                if (category == ContentCategory.Scenic) ClassCategory.SCENIC else ClassCategory.WORKOUT,
                source,
            ),
        )
    }

    /** The player's reported length, when it has one. */
    fun videoDuration(seconds: Double) {
        if (seconds > 0 && seconds.isFinite()) durationSec = seconds.toInt()
    }

    /** The class's current mute state; the first call is the state it started in. */
    fun muteState(muted: Boolean) {
        if (mutedAtStart == null) mutedAtStart = muted else if (muted) mutedLater = true
    }

    /** Emits `class_end` once per class; later calls (end button and video end both firing) do nothing. */
    fun end(watchedSec: Long, finished: Boolean) {
        val name = channel ?: return
        if (ended) return
        ended = true
        val watched = watchedSec.coerceAtLeast(0)
        // When the player never reported a length, the time watched is the best floor we have.
        val length = maxOf(durationSec?.toLong() ?: 0L, watched)
        emit(
            ClassEnd(
                name, channelSource,
                TelemetryBuckets.rideDuration(length),
                TelemetryBuckets.rideDuration(watched),
                finished,
                when {
                    mutedAtStart == true -> MuteState.FROM_START
                    mutedLater -> MuteState.DURING
                    else -> MuteState.NEVER
                },
            ),
        )
    }

    fun playerError(code: Int) {
        emit(ClassPlayerError(YouTubeErrorCode(code), channel ?: ChannelName.of("")))
    }

    private fun emit(event: TelemetryEvent) {
        runCatching { telemetry.track(event) }
    }
}
