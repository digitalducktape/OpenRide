package dev.digitalducktape.openride.core.telemetry

import dev.digitalducktape.openride.core.content.ChannelConfig
import dev.digitalducktape.openride.core.content.ContentSource
import dev.digitalducktape.openride.core.content.ContentSourceType

/**
 * What a source is called in telemetry (#85): a curated channel by its public handle, a
 * rider-added channel by the name YouTube gave its page (never the text the rider typed), a
 * playlist as `playlist`.
 */
fun channelFor(
    youtubeId: String,
    type: ContentSourceType,
    displayName: String,
    curatedHandle: String? = ChannelConfig.ALL.firstOrNull { it.id == youtubeId }?.handle,
): Pair<ChannelName, ChannelSource> = when {
    type == ContentSourceType.PLAYLIST -> ChannelName.PLAYLIST to ChannelSource.CUSTOM
    curatedHandle != null -> ChannelName.of(curatedHandle) to ChannelSource.CURATED
    else -> ChannelName.of(displayName) to ChannelSource.CUSTOM
}

fun channelFor(source: ContentSource?, curatedHandle: String?): Pair<ChannelName, ChannelSource> =
    if (source == null) ChannelName.of("") to ChannelSource.CUSTOM
    else channelFor(source.youtubeId, source.sourceType, source.displayName, curatedHandle)

fun channelFor(source: ContentSource?): Pair<ChannelName, ChannelSource> =
    channelFor(source, source?.let { s -> ChannelConfig.ALL.firstOrNull { it.id == s.youtubeId }?.handle })
