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
        // Muting rebuilds the player silent from its first frame, where it left off, so the
        // rider's music app can play without the class pausing.
        assertTrue(html.contains("if (muted) { rebuildPlayer(); } else { player.unMute(); }"))
        assertTrue(html.contains("\"mute\": wantMuted ? 1 : 0, \"start\": Math.floor(startSec)"))
        assertTrue(html.contains("var at = player.getCurrentTime ? player.getCurrentTime() : 0;"))
        // A mute asked for while the player was still loading is applied once it's ready.
        assertTrue(html.contains("if (wantMuted && !builtMuted) { rebuildPlayer(); return; }"))
        // The class starts with its sound on, from the beginning.
        assertTrue(html.contains("var wantMuted = false;"))
        assertTrue(html.contains("function onYouTubeIframeAPIReady() { buildPlayer(0); }"))
    }

    @Test
    fun `the mute script and label follow the mute state`() {
        assertEquals("openrideSetMuted(true)", YouTubeEmbed.muteScript(true))
        assertEquals("openrideSetMuted(false)", YouTubeEmbed.muteScript(false))
        assertEquals("Mute class", YouTubeEmbed.muteLabel(muted = false))
        assertEquals("Unmute class", YouTubeEmbed.muteLabel(muted = true))
    }

    @Test
    fun `the H264 preference turns away VP8, VP9 and AV1 through every capability check`() {
        val script = YouTubeEmbed.H264_PREFERENCE_SCRIPT

        assertTrue(script.contains("/vp0?9|vp8|av01/i"))
        assertTrue(script.contains("ms.isTypeSupported = "))
        assertTrue(script.contains("HTMLMediaElement.prototype.canPlayType = "))
        assertTrue(script.contains("mc.decodingInfo = "))
        // Anything else is still answered by the browser itself.
        assertTrue(script.contains("isTypeSupported(type)"))
        assertTrue(script.contains("canPlayType.call(this, type)"))
        assertTrue(script.contains("return decodingInfo(config)"))
    }

    @Test
    fun `the codec pattern matches the types YouTube asks about, and leaves H264 and audio alone`() {
        val avoid = Regex("vp0?9|vp8|av01", RegexOption.IGNORE_CASE)

        listOf(
            "video/webm; codecs=\"vp9\"",
            "video/webm; codecs=\"vp09.00.51.08.01.01.01.01.00\"",
            "video/webm; codecs=\"vp8\"",
            "video/mp4; codecs=\"av01.0.08M.08\"",
        ).forEach { assertTrue(it, avoid.containsMatchIn(it)) }
        listOf(
            "video/mp4; codecs=\"avc1.64002A\"",
            "audio/webm; codecs=\"opus\"",
            "audio/mp4; codecs=\"mp4a.40.2\"",
        ).forEach { assertTrue(it, !avoid.containsMatchIn(it)) }
    }

    @Test
    fun `the preference runs on the player's own origin`() {
        assertTrue(YouTubeEmbed.BASE_URL in YouTubeEmbed.PLAYER_ORIGINS)
    }

    @Test
    fun `a class can be built silent from its first frame`() {
        assertTrue(YouTubeEmbed.html("dQw4w9WgXcQ", startMuted = true).contains("var wantMuted = true;"))
        assertTrue(YouTubeEmbed.html("dQw4w9WgXcQ", startMuted = false).contains("var wantMuted = false;"))
    }

    @Test
    fun `the page reports player errors and the video length over the bridge`() {
        val html = YouTubeEmbed.html("dQw4w9WgXcQ")
        assertTrue(html.contains("onError: function (e)"))
        assertTrue(html.contains("window.OpenRideBridge.onPlayerError(e.data)"))
        assertTrue(html.contains("window.OpenRideBridge.onDuration(e.target.getDuration())"))
    }
}
