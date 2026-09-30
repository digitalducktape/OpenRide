package dev.digitalducktape.openride.games.session

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class OtherMusicDetectorTest {
    private val players = mutableListOf<Any>()
    private var musicActive = false
    private var now = 0L
    private val detector = OtherMusicDetector({ players.toList() }, { musicActive }, { now })

    /** The engine starts: Godot's media player appears and keeps isMusicActive() true. */
    private fun startEngine() {
        detector.engineStarting()
        now += 2_000
        players += "godot"
        musicActive = true
        detector.observe()
    }

    @Test
    fun `before the engine runs, isMusicActive decides`() {
        assertFalse(detector.otherMusicActive())
        players += "spotify"
        musicActive = true
        assertTrue(detector.otherMusicActive())
    }

    @Test
    fun `Godot's own player isn't the rider's music`() {
        startEngine()
        now += 60_000

        assertFalse(detector.otherMusicActive())
    }

    @Test
    fun `music already playing when games start counts`() {
        players += "spotify"
        musicActive = true
        startEngine()
        now += 60_000

        assertTrue(detector.otherMusicActive())
    }

    @Test
    fun `music started or stopped mid-session counts`() {
        startEngine()
        now += 60_000
        assertFalse(detector.otherMusicActive())

        players += "spotify"
        assertTrue(detector.otherMusicActive())

        players -= "spotify"
        assertFalse(detector.otherMusicActive())
    }

    @Test
    fun `an engine player seen only when first asked, inside the window, is still the engine's`() {
        detector.engineStarting()
        now += 3_000
        players += "godot"
        musicActive = true

        assertFalse(detector.otherMusicActive())
    }

    @Test
    fun `nothing playing anywhere is never the rider's music`() {
        players += "spotify-paused"
        startEngine()
        musicActive = false

        assertFalse(detector.otherMusicActive())
    }

    @Test
    fun `later engine starts in the process change nothing`() {
        startEngine()
        now += 60_000
        players += "spotify"
        detector.engineStarting() // re-entering games: the engine is the same one
        now += 1_000

        assertTrue(detector.otherMusicActive())
    }
}
