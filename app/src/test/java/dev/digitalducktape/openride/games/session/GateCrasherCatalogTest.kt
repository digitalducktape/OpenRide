package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.camera.HeadTrackerConfig
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.SegmentRole
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Gate Crasher's catalog entry (#80), kept apart from SessionPlansTest so parallel games merge cleanly. */
class GateCrasherCatalogTest {
    private val ftp200 = FtpBasis(200, isFallback = false)

    private fun JsonObject.int(key: String) = this[key]!!.jsonPrimitive.int
    private fun JsonObject.double(key: String) = this[key]!!.jsonPrimitive.content.toDouble()

    private fun params(d: Difficulty) =
        SessionPlans.justRide(GameCatalog.GATE_CRASHER, JustRideMode.Timed(10), d, ftp200).segments.single().params

    @Test
    fun `it is registered as a work game that needs the camera`() {
        val game = GameCatalog.DEFAULT["gate_crasher"]
        assertNotNull(game)
        assertEquals("Gate Crasher", game!!.title)
        assertEquals(setOf(SegmentRole.WORK), game.roles)
        assertEquals(setOf(JustRideSupport.ROUNDS, JustRideSupport.MINUTES, JustRideSupport.OPEN), game.supports)
        assertTrue(game.usesCamera)
        assertTrue(game.effortInJustRide)
        assertEquals(EndMode.TIMER, game.timedEndMode)
        assertEquals(SegmentRole.WORK, GameCatalog.circuitRole(game))
    }

    @Test
    fun `a camera-off circuit skips it`() {
        assertTrue(GameCatalog.DEFAULT.circuitPool(SegmentRole.WORK).any { it.id == "gate_crasher" })
        assertFalse(GameCatalog.DEFAULT.circuitPool(SegmentRole.WORK, cameraGames = false).any { it.id == "gate_crasher" })
    }

    @Test
    fun `the pace scales with FTP and the window eases on easy`() {
        // The 2026-11 retune: 25 / 32 / 42% of FTP.
        assertEquals(50, params(Difficulty.EASY).int("pace_watts"))
        assertEquals(64, params(Difficulty.STANDARD).int("pace_watts"))
        assertEquals(84, params(Difficulty.HARD).int("pace_watts"))
        assertEquals(1.4, params(Difficulty.EASY).double("window_sec"), 1e-9)
        assertEquals(1.2, params(Difficulty.STANDARD).double("window_sec"), 1e-9)
        assertEquals(8, params(Difficulty.STANDARD).int("fences"))
    }

    @Test
    fun `the lag it sends is the detector's`() {
        assertEquals(HeadTrackerConfig().standEnterMs / 1000.0, params(Difficulty.STANDARD).double("stand_lag_sec"), 1e-9)
    }

    @Test
    fun `a rounds ride ends on its own terms with its round count`() {
        val plan = SessionPlans.justRide(GameCatalog.GATE_CRASHER, JustRideMode.Rounds(3), Difficulty.STANDARD, ftp200)
        val segment = plan.segments.single()
        assertEquals(195, segment.durationSec)
        assertEquals(EndMode.GAME, segment.endMode)
        assertEquals(3, segment.params.int("rounds"))
    }
}
