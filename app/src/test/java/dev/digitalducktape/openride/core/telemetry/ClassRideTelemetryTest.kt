package dev.digitalducktape.openride.core.telemetry

import dev.digitalducktape.openride.core.content.ContentCategory
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ClassRideTelemetryTest {
    private val recording = RecordingTelemetry()
    private val classes = ClassRideTelemetry(recording)

    private fun start() =
        classes.start(ChannelName.of("@kaleigh"), ChannelSource.CURATED, ContentCategory.Workout, ClassSource.CLASSES)

    @Test
    fun `start emits class_start with channel and category`() {
        start()
        assertEquals(
            mapOf("channel" to "@kaleigh", "channel_source" to "curated", "category" to "workout", "source" to "classes"),
            recording.events.single().props(),
        )
    }

    @Test
    fun `end emits once even when called twice`() {
        start()
        classes.muteState(false)
        classes.videoDuration(1800.0)
        classes.end(watchedSec = 1200, finished = false)
        classes.end(watchedSec = 1800, finished = true)
        val ends = recording.events.filterIsInstance<ClassEnd>()
        assertEquals(1, ends.size)
        assertEquals(
            mapOf(
                "channel" to "@kaleigh", "channel_source" to "curated", "video_length" to "30–45m",
                "watched" to "15–30m", "finished" to "false", "muted" to "never",
            ),
            ends.single().props(),
        )
    }

    @Test
    fun `end without a start emits nothing`() {
        classes.end(60, true)
        assertTrue(recording.events.isEmpty())
    }

    @Test
    fun `muted from the start is from_start even if unmuted later`() {
        start()
        classes.muteState(true)
        classes.muteState(false)
        classes.end(60, true)
        assertEquals("from_start", recording.events.filterIsInstance<ClassEnd>().single().props()["muted"])
    }

    @Test
    fun `muted after the start is during`() {
        start()
        classes.muteState(false)
        classes.muteState(true)
        classes.end(60, true)
        assertEquals("during", recording.events.filterIsInstance<ClassEnd>().single().props()["muted"])
    }

    @Test
    fun `an unknown video length falls back to the time watched`() {
        start()
        classes.end(watchedSec = 20 * 60, finished = false)
        assertEquals("15–30m", recording.events.filterIsInstance<ClassEnd>().single().props()["video_length"])
    }

    @Test
    fun `a second class can end after the first`() {
        start(); classes.end(60, true)
        start(); classes.end(60, true)
        assertEquals(2, recording.events.filterIsInstance<ClassEnd>().size)
    }

    @Test
    fun `player error sends only the numeric code and the channel`() {
        start()
        classes.playerError(150)
        assertEquals(mapOf("code" to "150", "channel" to "@kaleigh"), recording.events.last().props())
    }

    @Test
    fun `a player error after the class ended does not reuse its channel`() {
        start()
        classes.end(watchedSec = 60, finished = false)
        classes.playerError(150)
        assertEquals("unknown", recording.events.filterIsInstance<ClassPlayerError>().single().props()["channel"])
    }

    @Test
    fun `a failing telemetry never throws`() {
        val throwing = ClassRideTelemetry(object : Telemetry {
            override fun track(event: TelemetryEvent) = error("boom")
        })
        throwing.start(ChannelName.of("a"), ChannelSource.CUSTOM, ContentCategory.Scenic, ClassSource.CREATOR)
        throwing.end(1, true)
        throwing.playerError(2)
    }

    @Test
    fun `a fallback end closes a class left early, once`() {
        start()
        classes.end(300, finished = false) // screen left
        classes.end(300, finished = false) // e.g. the session-state fallback too
        assertEquals(1, recording.events.filterIsInstance<ClassEnd>().size)
    }

    @Test
    fun `a fallback after the end button or video end does not repeat`() {
        start()
        classes.end(1800, finished = true)
        classes.end(1800, finished = false) // dispose fallback
        val ends = recording.events.filterIsInstance<ClassEnd>()
        assertEquals(1, ends.size)
        assertEquals("true", ends.single().props()["finished"])
    }
}
