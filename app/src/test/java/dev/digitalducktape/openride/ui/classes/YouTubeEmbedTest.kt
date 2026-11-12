package dev.digitalducktape.openride.ui.classes

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class YouTubeEmbedTest {

    @Test
    fun `html builds the player for the video id on the privacy-enhanced host`() {
        val html = YouTubeEmbed.html("dQw4w9WgXcQ")

        assertTrue(html.contains("videoId: 'dQw4w9WgXcQ'"))
        assertTrue(html.contains("host: 'https://www.youtube-nocookie.com'"))
    }

    @Test
    fun `html keeps YouTube's own controls enabled and plays inline`() {
        val html = YouTubeEmbed.html("dQw4w9WgXcQ")

        // YouTube ToS stance: never strip YouTube's player UI…
        assertTrue(html.contains("\"controls\": 1"))
        // …and play inside our layout rather than forcing the fullscreen activity.
        assertTrue(html.contains("\"playsinline\": 1"))
        assertTrue(html.contains("\"autoplay\": 1"))
    }

    @Test
    fun `html exposes ride-pause hooks and reports playback end over the bridge`() {
        val html = YouTubeEmbed.html("dQw4w9WgXcQ")

        // Called by VideoRideScreen via evaluateJavascript when the ride pauses/resumes.
        assertTrue(html.contains("function openridePause()"))
        assertTrue(html.contains("function openrideResume()"))
        // Video completion → auto-end the workout (via the injected JS interface).
        assertTrue(html.contains("YT.PlayerState.ENDED"))
        assertTrue(html.contains("${YouTubeEmbed.BRIDGE_NAME}.onVideoEnded()"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun `html rejects a video id with markup or URL metacharacters`() {
        YouTubeEmbed.html("\"><script>alert(1)</script>")
    }

    @Test(expected = IllegalArgumentException::class)
    fun `html rejects an id that would escape the embed path`() {
        YouTubeEmbed.html("../watch?v=x")
    }

    @Test
    fun `underscore and dash ids are accepted`() {
        val html = YouTubeEmbed.html("a-b_c-D_e12")

        assertTrue(html.contains("videoId: 'a-b_c-D_e12'"))
    }

    @Test
    fun `html can mute the class audio, before or after the player is ready`() {
        val html = YouTubeEmbed.html("dQw4w9WgXcQ")

        assertTrue(html.contains("function openrideSetMuted(muted)"))
        // A mute asked for while the player was still loading is applied once it's ready.
        assertTrue(html.contains("if (wantMuted) { e.target.mute(); }"))
        assertTrue(html.contains("player.unMute()"))
        // The class starts with its sound on.
        assertTrue(html.contains("var wantMuted = false;"))
    }

    @Test
    fun `the mute script and label follow the mute state`() {
        assertEquals("openrideSetMuted(true)", YouTubeEmbed.muteScript(true))
        assertEquals("openrideSetMuted(false)", YouTubeEmbed.muteScript(false))
        assertEquals("Mute class", YouTubeEmbed.muteLabel(muted = false))
        assertEquals("Unmute class", YouTubeEmbed.muteLabel(muted = true))
    }
}
