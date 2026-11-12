package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.SegmentRole
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** Power Grid's catalog entry (#81), kept apart from SessionPlansTest so parallel games merge cleanly. */
class PowerGridCatalogTest {
    private val ftp200 = FtpBasis(200, isFallback = false)

    private fun Map<String, JsonElement>.int(key: String) = this[key]!!.jsonPrimitive.int

    private fun params(role: SegmentRole, d: Difficulty = Difficulty.STANDARD) = GameCatalog.POWER_GRID.params(role, d, ftp200)

    @Test
    fun `it is registered for every circuit role, without the camera or rounds`() {
        val game = GameCatalog.DEFAULT["power_grid"]
        assertNotNull(game)
        assertEquals("Power Grid", game!!.title)
        assertEquals(setOf(SegmentRole.WARMUP, SegmentRole.WORK, SegmentRole.RECOVERY, SegmentRole.COOLDOWN), game.roles)
        assertEquals(setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN), game.supports)
        assertFalse(game.usesCamera)
        assertTrue(game.effortInJustRide)
        assertEquals(EndMode.TIMER, game.timedEndMode)
        assertEquals(SegmentRole.WORK, GameCatalog.circuitRole(game))
    }

    @Test
    fun `work demand follows difficulty`() {
        // The 2026-11 retune: 15-33% of FTP on standard, met at 90%.
        assertEquals(30, params(SegmentRole.WORK).int("demand_lo_watts"))
        assertEquals(66, params(SegmentRole.WORK).int("demand_hi_watts"))
        assertEquals(54, params(SegmentRole.WORK, Difficulty.EASY).int("demand_hi_watts"))
        assertEquals(90, params(SegmentRole.WORK, Difficulty.HARD).int("demand_hi_watts"))
        assertEquals(30, params(SegmentRole.WORK).int("storm_watts"))
    }

    @Test
    fun `the easy roles ignore difficulty and stay under their caps`() {
        for (d in Difficulty.entries) {
            assertEquals(24, params(SegmentRole.WARMUP, d).int("demand_lo_watts"))
            assertEquals(54, params(SegmentRole.WARMUP, d).int("demand_hi_watts"))
            assertEquals(54, params(SegmentRole.COOLDOWN, d).int("demand_hi_watts"))
            assertEquals(44, params(SegmentRole.RECOVERY, d).int("demand_hi_watts"))
        }
        val plan = SessionPlans.custom(listOf(CustomSlot("power_grid", 180), CustomSlot("power_grid", 180)), Difficulty.HARD,
            ftp200, GameCatalog(listOf(GameCatalog.DEMO, GameCatalog.POWER_GRID)), cameraGames = false)
        val first = plan.segments.first()
        assertEquals(SegmentRole.WARMUP, first.role)
        assertTrue(first.params.int("demand_hi_watts") < first.params.int("power_cap_watts"))
    }

    @Test
    fun `a Just Ride plays like work, with the effort multiplier`() {
        val segment = SessionPlans.justRide(GameCatalog.POWER_GRID, JustRideMode.Timed(10), Difficulty.STANDARD, ftp200)
            .segments.single()
        assertEquals(SegmentRole.FREE, segment.role)
        assertEquals(66, segment.params.int("demand_hi_watts"))
        assertTrue(segment.effort)
    }

    @Test
    fun `it joins every role's circuit pool`() {
        for (role in listOf(SegmentRole.WARMUP, SegmentRole.WORK, SegmentRole.RECOVERY, SegmentRole.COOLDOWN)) {
            assertTrue(GameCatalog.DEFAULT.circuitPool(role, cameraGames = false).any { it.id == "power_grid" })
        }
    }
}
