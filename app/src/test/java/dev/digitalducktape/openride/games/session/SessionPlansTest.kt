package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SessionKind
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SessionPlansTest {
    private val ftp200 = FtpBasis(200, isFallback = false)

    /** A short-rounds recovery game, like Safe Cracker, with no effort in Just Ride. */
    private val roundsGame = GameDeclaration(
        id = "vault",
        title = "Vault",
        supports = setOf(JustRideSupport.ROUNDS, JustRideSupport.MINUTES),
        minSec = 120,
        maxSec = 1200,
        minRounds = 2,
        maxRounds = 8,
        roundSec = 45,
        freeRideScaling = SegmentRole.RECOVERY,
    )

    private fun JsonObject.int(key: String) = this[key]!!.jsonPrimitive.int

    // --- FTP scaling ------------------------------------------------------------------------

    @Test
    fun `work targets are 90, 105 and 120 percent of FTP`() {
        assertEquals(180, FtpScaling.params(SegmentRole.WORK, Difficulty.EASY, ftp200)["target_watts"]!!.jsonPrimitive.int)
        assertEquals(210, FtpScaling.params(SegmentRole.WORK, Difficulty.STANDARD, ftp200)["target_watts"]!!.jsonPrimitive.int)
        assertEquals(240, FtpScaling.params(SegmentRole.WORK, Difficulty.HARD, ftp200)["target_watts"]!!.jsonPrimitive.int)
    }

    @Test
    fun `recovery caps at 60 percent and warm-up and cool-down at 65, whatever the difficulty`() {
        for (difficulty in Difficulty.entries) {
            assertEquals(120, FtpScaling.params(SegmentRole.RECOVERY, difficulty, ftp200)["power_cap_watts"]!!.jsonPrimitive.int)
            assertEquals(130, FtpScaling.params(SegmentRole.WARMUP, difficulty, ftp200)["power_cap_watts"]!!.jsonPrimitive.int)
            assertEquals(130, FtpScaling.params(SegmentRole.COOLDOWN, difficulty, ftp200)["power_cap_watts"]!!.jsonPrimitive.int)
            assertFalse("target_watts" in FtpScaling.params(SegmentRole.RECOVERY, difficulty, ftp200))
        }
    }

    @Test
    fun `a missing FTP falls back to 150 W and flags the nudge`() {
        assertEquals(FtpBasis(150, isFallback = true), FtpBasis.of(null))
        assertEquals(FtpBasis(150, isFallback = true), FtpBasis.of(0))
        assertEquals(FtpBasis(230, isFallback = false), FtpBasis.of(230))

        val params = FtpScaling.params(SegmentRole.WORK, Difficulty.STANDARD, FtpBasis.of(null))
        assertEquals(158, params["target_watts"]!!.jsonPrimitive.int) // 157.5 rounds up
        assertEquals(150, params["ftp_watts"]!!.jsonPrimitive.int)
        assertTrue(params["ftp_is_default"]!!.jsonPrimitive.boolean)
    }

    // --- Just Ride --------------------------------------------------------------------------

    @Test
    fun `a timed Just Ride is one free segment of N minutes ended by the timer`() {
        val plan = SessionPlans.justRide(GameCatalog.DEMO, JustRideMode.Timed(20), Difficulty.STANDARD, ftp200)

        assertEquals(SessionKind.JUST_RIDE, plan.kind)
        assertEquals("just-ride:demo:minutes:20", plan.planId)
        val segment = plan.segments.single()
        assertEquals(1200, segment.durationSec)
        assertEquals(SegmentRole.FREE, segment.role)
        assertEquals(EndMode.TIMER, segment.endMode)
        assertEquals(1210, plan.totalSec)
        assertEquals(210, segment.params.int("target_watts"))
        assertEquals(60, segment.params.int("cadence_floor"))
    }

    @Test
    fun `timed lengths are clamped to the game's limits`() {
        assertEquals(1200, SessionPlans.justRide(roundsGame, JustRideMode.Timed(60), Difficulty.EASY, ftp200).segments.single().durationSec)
        val short = SessionPlans.justRide(roundsGame, JustRideMode.Timed(1), Difficulty.EASY, ftp200)
        assertEquals(120, short.segments.single().durationSec)
        assertEquals("just-ride:vault:minutes:2", short.planId)
    }

    @Test
    fun `a rounds Just Ride lets the game end it after N rounds`() {
        val plan = SessionPlans.justRide(roundsGame, JustRideMode.Rounds(5), Difficulty.HARD, ftp200)

        assertEquals("just-ride:vault:rounds:5", plan.planId)
        val segment = plan.segments.single()
        assertEquals(EndMode.GAME, segment.endMode)
        assertEquals(225, segment.durationSec)
        assertEquals(5, segment.params.int("rounds"))
        // A recovery game's Just Ride is capped, not targeted.
        assertEquals(120, segment.params.int("power_cap_watts"))
        assertEquals(8, SessionPlans.justRide(roundsGame, JustRideMode.Rounds(50), Difficulty.HARD, ftp200).segments.single().params.int("rounds"))
    }

    @Test
    fun `an open-ended Just Ride has no duration`() {
        val plan = SessionPlans.justRide(GameCatalog.DEMO, JustRideMode.Open, Difficulty.EASY, ftp200)

        assertEquals("just-ride:demo:open", plan.planId)
        assertEquals(-1, plan.segments.single().durationSec)
        assertEquals(EndMode.GAME, plan.segments.single().endMode)
        assertEquals(-1, plan.totalSec)
        assertEquals(-1, plan.toMessage().totalSec)
    }

    @Test
    fun `unsupported modes are refused`() {
        assertThrows(IllegalArgumentException::class.java) {
            SessionPlans.justRide(GameCatalog.DEMO, JustRideMode.Rounds(3), Difficulty.EASY, ftp200)
        }
        assertThrows(IllegalArgumentException::class.java) {
            SessionPlans.justRide(roundsGame, JustRideMode.Open, Difficulty.EASY, ftp200)
        }
    }

    @Test
    fun `difficulty scales a Just Ride's target and the game's own params`() {
        fun plan(d: Difficulty) = SessionPlans.justRide(GameCatalog.DEMO, JustRideMode.Timed(20), d, ftp200).segments.single().params

        assertEquals(listOf(180, 210, 240), Difficulty.entries.map { plan(it).int("target_watts") })
        assertEquals(listOf(55, 60, 70), Difficulty.entries.map { plan(it).int("cadence_floor") })
    }

    @Test
    fun `effort applies to Just Rides of games that declare it`() {
        assertTrue(SessionPlans.justRide(GameCatalog.DEMO, JustRideMode.Open, Difficulty.EASY, ftp200).segments.single().effort)
        assertFalse(SessionPlans.justRide(roundsGame, JustRideMode.Rounds(3), Difficulty.EASY, ftp200).segments.single().effort)
    }

    // --- Circuits ---------------------------------------------------------------------------

    @Test
    fun `circuit presets add up to the spec's lengths, intro cards included`() {
        val lengths = CircuitPresets.ALL.associate { preset ->
            preset.id to SessionPlans.circuit(preset, Difficulty.STANDARD, ftp200, GameCatalog.DEFAULT).totalSec
        }

        assertEquals(mapOf("circuit-20" to 1120, "circuit-30" to 1860, "circuit-45" to 2600), lengths)
    }

    @Test
    fun `a circuit never puts two work games back to back, and only work has effort`() {
        val plan = SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.HARD, ftp200, GameCatalog.DEFAULT)

        assertEquals(SegmentRole.WARMUP, plan.segments.first().role)
        assertEquals(SegmentRole.COOLDOWN, plan.segments.last().role)
        plan.segments.zipWithNext().forEach { (a, b) ->
            assertFalse(a.role == SegmentRole.WORK && b.role == SegmentRole.WORK)
        }
        plan.segments.forEach { assertEquals(it.role == SegmentRole.WORK, it.effort) }
        plan.segments.forEach { assertEquals(EndMode.TIMER, it.endMode) }
        val work = plan.segments.first { it.role == SegmentRole.WORK }
        assertEquals(240, work.params.int("target_watts"))
        assertEquals(120, plan.segments.first { it.role == SegmentRole.RECOVERY }.params.int("power_cap_watts"))
    }

    @Test
    fun `circuit games not in the catalog yet play the stand-in`() {
        val plan = SessionPlans.circuit(CircuitPresets.TWENTY, Difficulty.STANDARD, ftp200, GameCatalog.DEFAULT)

        assertTrue(plan.segments.all { it.gameId == "demo" })
        val withTug = GameCatalog(listOf(GameCatalog.DEMO, roundsGame.copy(id = "tug_of_war")))
        assertEquals("tug_of_war", SessionPlans.circuit(CircuitPresets.TWENTY, Difficulty.STANDARD, ftp200, withTug).segments[1].gameId)
    }

    // --- Requests ---------------------------------------------------------------------------

    @Test
    fun `requests round-trip as JSON and build their plans`() {
        val requests = listOf(
            SessionRequest.JustRide("demo", JustRideMode.Timed(20), Difficulty.HARD),
            SessionRequest.JustRide("demo", JustRideMode.Open),
            SessionRequest.Circuit("circuit-30", Difficulty.EASY),
        )
        for (request in requests) assertEquals(request, SessionRequest.fromJson(request.toJson()))

        assertEquals("just-ride:demo:minutes:20", SessionPlans.forRequest(requests[0], ftp200, GameCatalog.DEFAULT)?.planId)
        assertEquals("circuit-30", SessionPlans.forRequest(requests[2], ftp200, GameCatalog.DEFAULT)?.planId)
        assertNull(SessionPlans.forRequest(SessionRequest.JustRide("nope", JustRideMode.Open), ftp200, GameCatalog.DEFAULT))
        assertNull(SessionPlans.forRequest(SessionRequest.JustRide("demo", JustRideMode.Rounds(2)), ftp200, GameCatalog.DEFAULT))
        assertNull(SessionRequest.fromJson("{garbage"))
    }

    // --- Audio ------------------------------------------------------------------------------

    @Test
    fun `game music defaults off while the rider's own music plays, effects stay on`() {
        val auto = GameAudioPrefs(musicVolume = 0.5, sfxVolume = 0.7)

        val withOwnMusic = auto.resolve(otherMusicActive = true)
        assertFalse(withOwnMusic.music)
        assertEquals(0.7, withOwnMusic.sfxVolume, 0.0)
        assertEquals(0.5, withOwnMusic.musicVolume, 0.0)
        assertTrue(auto.resolve(otherMusicActive = false).music)
    }

    @Test
    fun `game music set on or off ignores the rider's music`() {
        assertTrue(GameAudioPrefs(music = GameMusicMode.ON).resolve(otherMusicActive = true).music)
        assertFalse(GameAudioPrefs(music = GameMusicMode.OFF).resolve(otherMusicActive = false).music)
    }
}
