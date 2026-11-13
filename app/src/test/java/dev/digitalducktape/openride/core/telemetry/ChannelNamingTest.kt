package dev.digitalducktape.openride.core.telemetry

import dev.digitalducktape.openride.core.content.ChannelConfig
import dev.digitalducktape.openride.core.content.ContentCategory
import dev.digitalducktape.openride.core.content.ContentSource
import dev.digitalducktape.openride.core.content.ContentSourceType
import org.junit.Assert.assertEquals
import org.junit.Test

class ChannelNamingTest {
    private fun source(
        type: ContentSourceType = ContentSourceType.CHANNEL,
        id: String = "UCcustom0000000000000",
        name: String = "My Channel",
        builtIn: Boolean = false,
    ) = ContentSource(1, type, id, name, ContentCategory.Workout, builtIn, position = 0)

    @Test
    fun `a curated channel is sent by its handle`() {
        val kaleigh = ChannelConfig.ALL.first { it.displayName == "Kaleigh Cohen Cycling" }
        val (name, kind) = channelFor(source(id = kaleigh.id, name = "Kaleigh Cohen Cycling", builtIn = true))
        assertEquals("@kaleigh", name.value)
        assertEquals(ChannelSource.CURATED, kind)
    }

    @Test
    fun `a custom channel is sent by its display name`() {
        val (name, kind) = channelFor(source(name = "Hill Repeats TV"))
        assertEquals("Hill Repeats TV", name.value)
        assertEquals(ChannelSource.CUSTOM, kind)
    }

    @Test
    fun `a playlist is sent as playlist`() {
        val (name, kind) = channelFor(source(type = ContentSourceType.PLAYLIST, name = "My secret playlist"))
        assertEquals("playlist", name.value)
        assertEquals(ChannelSource.CUSTOM, kind)
    }

    @Test
    fun `an 80 character name is cut to 64`() {
        val (name, _) = channelFor(source(name = "x".repeat(80)))
        assertEquals(64, name.value.length)
    }

    @Test
    fun `no source is unknown and custom`() {
        val (name, kind) = channelFor(null)
        assertEquals("unknown", name.value)
        assertEquals(ChannelSource.CUSTOM, kind)
    }
}
