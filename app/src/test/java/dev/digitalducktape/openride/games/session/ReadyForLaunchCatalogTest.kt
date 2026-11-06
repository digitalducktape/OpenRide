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

/** Ready for Launch's catalog entry (#82), kept apart from SessionPlansTest so parallel games merge cleanly. */
class ReadyForLaunchCatalogTest {
    private val ftp200 = FtpBasis(200, isFallback = false)

    private fun JsonObject.int(key: String) = this[key]!!.jsonPrimitive.int

    private fun params(d: Difficulty) =
        SessionPlans.justRide(GameCatalog.READY_FOR_LAUNCH, JustRideMode.Timed(10), d, ftp200).segments.single().params

    @Test
    fun `it is registered as a work game with no camera`() {
        val game = GameCatalog.DEFAULT["ready_for_launch"]
        assertNotNull(game)
        assertEquals("Ready for Launch", game!!.title)
        assertEquals(setOf(SegmentRole.WORK), game.roles)
        assertEquals(setOf(JustRideSupport.ROUNDS, JustRideSupport.MINUTES, JustRideSupport.OPEN), game.supports)
        assertFalse(game.usesCamera)
        assertTrue(game.effortInJustRide)
        assertEquals(EndMode.TIMER, game.timedEndMode)
        assertEquals(SegmentRole.WORK, GameCatalog.circuitRole(game))
    }

    @Test
    fun `a 1-30 slot fits one launch`() {
        assertEquals(90, GameCatalog.READY_FOR_LAUNCH.minSec)
        val plan = SessionPlans.custom(listOf(CustomSlot("ready_for_launch", 90)), Difficulty.STANDARD, ftp200,
            GameCatalog(listOf(GameCatalog.DEMO, GameCatalog.READY_FOR_LAUNCH)), cameraGames = false)
        assertEquals(90, plan.segments.single().durationSec)
        assertEquals(SegmentRole.WORK, plan.segments.single().role)
    }

    @Test
    fun `fuel lines scale with difficulty and FTP, and the push has its target`() {
        assertEquals(90, params(Difficulty.EASY).int("fuel_line_watts"))
        assertEquals(110, params(Difficulty.EASY).int("fuel_full_watts"))
        assertEquals(100, params(Difficulty.STANDARD).int("fuel_line_watts"))
        assertEquals(120, params(Difficulty.STANDARD).int("fuel_full_watts"))
        assertEquals(110, params(Difficulty.HARD).int("fuel_line_watts"))
        assertEquals(130, params(Difficulty.HARD).int("fuel_full_watts"))
        assertEquals(210, params(Difficulty.STANDARD).int("target_watts"))
        assertEquals(200, params(Difficulty.HARD).int("ftp_watts"))
    }

    @Test
    fun `a rounds Just Ride is ninety seconds a round, ended by the game`() {
        val segment = SessionPlans.justRide(GameCatalog.READY_FOR_LAUNCH, JustRideMode.Rounds(3), Difficulty.STANDARD, ftp200)
            .segments.single()
        assertEquals(270, segment.durationSec)
        assertEquals(EndMode.GAME, segment.endMode)
        assertEquals(3, segment.params.int("rounds"))
        assertTrue(segment.effort)
    }
}
