package dev.digitalducktape.openride.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Test

class GameMusicTest {
    @Test
    fun `classify follows the truth table`() {
        assertEquals(GameMusic.OWN_MUSIC, classify(gameMusicOn = true, ownTrackPlaying = true))
        assertEquals(GameMusic.OWN_MUSIC, classify(gameMusicOn = false, ownTrackPlaying = true))
        assertEquals(GameMusic.GAME_MUSIC, classify(gameMusicOn = true, ownTrackPlaying = false))
        assertEquals(GameMusic.OFF, classify(gameMusicOn = false, ownTrackPlaying = false))
    }

    @Test
    fun `the accumulator reports the one value it saw`() {
        val acc = VisitMusicAccumulator()
        acc.observe(GameMusic.OWN_MUSIC)
        acc.observe(GameMusic.OWN_MUSIC)
        assertEquals(VisitMusic.OWN_MUSIC, acc.result())
    }

    @Test
    fun `more than one distinct value is mixed`() {
        val acc = VisitMusicAccumulator()
        acc.observe(GameMusic.GAME_MUSIC)
        acc.observe(GameMusic.OWN_MUSIC)
        assertEquals(VisitMusic.MIXED, acc.result())
    }

    @Test
    fun `nothing observed reads as off`() {
        assertEquals(VisitMusic.OFF, VisitMusicAccumulator().result())
    }

    @Test
    fun `each single value maps across`() {
        assertEquals(VisitMusic.GAME_MUSIC, VisitMusicAccumulator().apply { observe(GameMusic.GAME_MUSIC) }.result())
        assertEquals(VisitMusic.OFF, VisitMusicAccumulator().apply { observe(GameMusic.OFF) }.result())
    }
}
