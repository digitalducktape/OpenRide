package dev.digitalducktape.openride.games.session

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

/** Keepy Uppy's catalog entry (#77), kept apart from SessionPlansTest so parallel games merge cleanly. */
class KeepyUppyCatalogTest {
    private val ftp200 = FtpBasis(200, isFallback = false)

    private fun JsonObject.int(key: String) = this[key]!!.jsonPrimitive.int

    private fun params(d: Difficulty) =
        SessionPlans.justRide(GameCatalog.KEEPY_UPPY, JustRideMode.Timed(10), d, ftp200).segments.single().params

    @Test
    fun `it is registered as a work game whose camera is an option`() {
        val game = GameCatalog.DEFAULT["keepy_uppy"]
        assertNotNull(game)
        assertEquals("Keepy Uppy", game!!.title)
        assertEquals(setOf(SegmentRole.WORK), game.roles)
        assertEquals(setOf(JustRideSupport.ROUNDS, JustRideSupport.MINUTES, JustRideSupport.OPEN), game.supports)
        // Steer is the rider's option, decided per segment in Godot: the catalog never needs the camera.
        assertFalse(game.usesCamera)
        assertTrue(game.effortInJustRide)
        assertEquals(EndMode.TIMER, game.timedEndMode)
        assertEquals(SegmentRole.WORK, GameCatalog.circuitRole(game))
    }

    @Test
    fun `the balloon weighs 30, 40 and 50 percent of FTP and the weather scales with FTP`() {
        assertEquals(60, params(Difficulty.EASY).int("weight_watts"))
        assertEquals(80, params(Difficulty.STANDARD).int("weight_watts"))
        assertEquals(100, params(Difficulty.HARD).int("weight_watts"))
        for (d in Difficulty.entries) {
            assertEquals(20, params(d).int("rain_watts"))
            assertEquals(10, params(d).int("bird_watts"))
            assertEquals(40, params(d).int("downdraft_watts"))
            assertEquals(200, params(d).int("ftp_watts"))
        }
    }

    @Test
    fun `a rounds Just Ride is a minute a round, ended by the game`() {
        val segment = SessionPlans.justRide(GameCatalog.KEEPY_UPPY, JustRideMode.Rounds(3), Difficulty.STANDARD, ftp200)
            .segments.single()
        assertEquals(180, segment.durationSec)
        assertEquals(EndMode.GAME, segment.endMode)
        assertEquals(3, segment.params.int("rounds"))
        assertTrue(segment.effort)
    }

    @Test
    fun `without camera games a circuit can still play it`() {
        val catalog = GameCatalog(listOf(GameCatalog.DEMO, GameCatalog.KEEPY_UPPY))
        val plan = SessionPlans.custom(listOf(CustomSlot("keepy_uppy", 90)), Difficulty.STANDARD, ftp200, catalog,
            cameraGames = false)
        assertEquals(listOf("keepy_uppy"), plan.segments.map { it.gameId })
        assertEquals(SegmentRole.WORK, plan.segments.single().role)
    }
}
