package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.PlanRejectReason
import dev.digitalducktape.openride.games.bridge.PlanRequestKind
import dev.digitalducktape.openride.games.bridge.PlanRequestMessage
import dev.digitalducktape.openride.games.bridge.PlanRequestSlot
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SessionKind
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
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
    fun `the message carries the rider's name trimmed, and null when blank`() {
        val plan = SessionPlans.justRide(GameCatalog.DEMO, JustRideMode.Open, Difficulty.EASY, ftp200)

        assertEquals("Ed", plan.toMessage(7L, "  Ed ").riderName)
        assertEquals(null, plan.toMessage(7L, "   ").riderName)
        assertEquals(null, plan.toMessage().riderName)
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
    fun `Tug of War sends the bot's watts as a low share of FTP, surging 20 percent of FTP above it`() {
        fun params(d: Difficulty) =
            SessionPlans.justRide(GameCatalog.TUG_OF_WAR, JustRideMode.Timed(20), d, ftp200).segments.single().params
        assertEquals(100, params(Difficulty.EASY).int("bot_watts"))
        assertEquals(140, params(Difficulty.EASY).int("surge_watts"))
        assertEquals(120, params(Difficulty.STANDARD).int("bot_watts"))
        assertEquals(160, params(Difficulty.STANDARD).int("surge_watts"))
        assertEquals(140, params(Difficulty.HARD).int("bot_watts"))
        assertEquals(180, params(Difficulty.HARD).int("surge_watts"))
        assertEquals(200, params(Difficulty.STANDARD).int("ftp_watts"))
        // A Just Ride earns the effort multiplier, as the issue asks.
        assertTrue(SessionPlans.justRide(GameCatalog.TUG_OF_WAR, JustRideMode.Open, Difficulty.STANDARD, ftp200)
            .segments.single().effort)
    }

    @Test
    fun `Balloon Pump scales its push line by role and its race by difficulty`() {
        fun segment(d: Difficulty) =
            SessionPlans.justRide(GameCatalog.BALLOON_PUMP, JustRideMode.Timed(20), d, ftp200).segments.single()
        // A Just Ride is work: the line runs from 20% to 45% of FTP, with the effort multiplier.
        assertEquals(40, segment(Difficulty.STANDARD).params.int("push_lo_watts"))
        assertEquals(90, segment(Difficulty.STANDARD).params.int("push_hi_watts"))
        assertTrue(segment(Difficulty.STANDARD).effort)
        assertEquals(listOf(4, 5, 7), Difficulty.entries.map { segment(it).params.int("race_balloons") })
        assertEquals(120, segment(Difficulty.HARD).params.int("race_sec"))
        // Recovery is gentler: 15% to 30% of FTP.
        val recovery = GameCatalog.BALLOON_PUMP.params(SegmentRole.RECOVERY, Difficulty.STANDARD, ftp200)
        assertEquals(30, recovery["push_lo_watts"]!!.jsonPrimitive.int)
        assertEquals(60, recovery["push_hi_watts"]!!.jsonPrimitive.int)
        assertEquals(SegmentRole.WORK, GameCatalog.circuitRole(GameCatalog.BALLOON_PUMP))
        assertEquals(125, GameCatalog.BALLOON_PUMP.roundSec)
    }

    @Test
    fun `Safe Cracker is a recovery game with a power cap and no effort multiplier`() {
        val plan = SessionPlans.justRide(GameCatalog.SAFE_CRACKER, JustRideMode.Timed(20), Difficulty.HARD, ftp200)
        val segment = plan.segments.single()
        // Recovery scaling whatever the difficulty: a cap of 60% of FTP, and no effort badge.
        assertEquals(120, segment.params.int("power_cap_watts"))
        assertEquals(15, segment.params.int("res_min"))
        assertEquals(40, segment.params.int("res_max"))
        assertEquals(60, segment.params.int("cadence_min"))
        assertFalse(segment.effort)
    }

    @Test
    fun `Cadence Karaoke sends circuit profiles and no effort, and a Just Ride sends none`() {
        fun params(role: SegmentRole) = GameCatalog.CADENCE_KARAOKE.params(role, Difficulty.STANDARD, ftp200)
        val warmup = params(SegmentRole.WARMUP)["cadence_profile"] as kotlinx.serialization.json.JsonArray
        assertEquals(70, warmup.first().jsonObject["rpm"]!!.jsonPrimitive.int)
        assertEquals(90, warmup.last().jsonObject["rpm"]!!.jsonPrimitive.int)
        val cooldown = params(SegmentRole.COOLDOWN)["cadence_profile"] as kotlinx.serialization.json.JsonArray
        assertEquals(85, cooldown.first().jsonObject["rpm"]!!.jsonPrimitive.int)
        assertEquals(65, cooldown.last().jsonObject["rpm"]!!.jsonPrimitive.int)
        assertTrue(params(SegmentRole.RECOVERY).containsKey("cadence_profile"))
        assertTrue(params(SegmentRole.FREE).isEmpty())
        val ride = SessionPlans.justRide(GameCatalog.CADENCE_KARAOKE, JustRideMode.Open, Difficulty.STANDARD, ftp200)
        assertFalse(ride.segments.single().effort)
        assertFalse(ride.segments.single().params.containsKey("cadence_profile"))
    }

    @Test
    fun `Kart Race is a timed or open Grand Prix with no circuit roles that ends on its own terms`() {
        val kart = GameCatalog.KART_RACE
        assertEquals("kart_race", kart.id)
        assertEquals("Kart Race", kart.title)
        assertEquals(setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN), kart.supports)
        assertEquals(300, kart.minSec)
        assertEquals(3600, kart.maxSec)
        assertTrue(kart.roles.isEmpty())
        assertTrue(kart.usesCamera)
        assertTrue(kart.effortInJustRide)
        assertEquals(EndMode.GAME, kart.timedEndMode)
        assertEquals(kart, GameCatalog.DEFAULT["kart_race"])
        assertThrows(IllegalArgumentException::class.java) {
            SessionPlans.justRide(kart, JustRideMode.Rounds(3), Difficulty.STANDARD, ftp200)
        }
        // Lengths are clamped to 5-60 minutes.
        assertEquals(300, SessionPlans.justRide(kart, JustRideMode.Timed(2), Difficulty.STANDARD, ftp200).segments.single().durationSec)
        val open = SessionPlans.justRide(kart, JustRideMode.Open, Difficulty.STANDARD, ftp200).segments.single()
        assertEquals(EndMode.GAME, open.endMode)
        assertEquals(-1, open.durationSec)
    }

    @Test
    fun `a 20 minute Kart Race carries the bots' FTP shares and the drift knob by difficulty`() {
        fun segment(d: Difficulty) = SessionPlans.justRide(GameCatalog.KART_RACE, JustRideMode.Timed(20), d, ftp200).segments.single()
        fun shares(d: Difficulty) =
            (segment(d).params["bot_pcts"] as kotlinx.serialization.json.JsonArray).map { it.jsonPrimitive.content.toDouble() }

        val standard = segment(Difficulty.STANDARD)
        assertEquals(1200, standard.durationSec)
        assertEquals(EndMode.GAME, standard.endMode)
        assertTrue(standard.effort)
        assertEquals(200, standard.params.int("ftp_watts"))
        for ((difficulty, range) in mapOf(
            Difficulty.EASY to (0.40 to 0.85),
            Difficulty.STANDARD to (0.50 to 1.00),
            Difficulty.HARD to (0.60 to 1.15),
        )) {
            val pcts = shares(difficulty)
            assertEquals(7, pcts.size)
            assertEquals(range.first, pcts.first(), 0.001)
            assertEquals(range.second, pcts.last(), 0.001)
            pcts.zipWithNext().forEach { (a, b) -> assertTrue("$difficulty rises: $pcts", b > a) }
        }
        assertEquals(listOf(35, 40, 45), Difficulty.entries.map { segment(it).params.int("drift_resistance") })
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
    fun `without camera games a circuit keeps its shape and draws from camera-free pools`() {
        for (seed in 0L until 20L) {
            val withCamera = SessionPlans.circuit(CircuitPresets.TWENTY, Difficulty.STANDARD, ftp200, GameCatalog.DEFAULT, seed = seed)
            val without = SessionPlans.circuit(CircuitPresets.TWENTY, Difficulty.STANDARD, ftp200, GameCatalog.DEFAULT, cameraGames = false, seed = seed)

            assertFalse(without.segments.any { GameCatalog.DEFAULT[it.gameId]!!.usesCamera })
            // Same shape: every slot keeps its role, length and effort; only the games change.
            assertEquals(withCamera.segments.map { it.role }, without.segments.map { it.role })
            assertEquals(withCamera.segments.map { it.durationSec }, without.segments.map { it.durationSec })
            assertEquals(withCamera.segments.map { it.effort }, without.segments.map { it.effort })
            assertEquals(withCamera.planId, without.planId)
            // Only camera-free work games play the work slots (Tug of War and Balloon Pump today).
            val free = GameCatalog.DEFAULT.circuitPool(SegmentRole.WORK, cameraGames = false).map { it.id }.toSet()
            without.segments.filter { it.role == SegmentRole.WORK }.forEach { assertTrue(it.gameId in free) }
        }
        // With the camera, Dodge Ball plays its share.
        assertTrue(SessionPlans.circuit(CircuitPresets.TWENTY, Difficulty.STANDARD, ftp200, GameCatalog.DEFAULT).segments.any { it.gameId == "dodge_ball" })
    }

    @Test
    fun `a circuit request carries the camera setting and defaults to camera games`() {
        val off = SessionRequest.Circuit("circuit-20", Difficulty.EASY, cameraGames = false)
        assertEquals(off, SessionRequest.fromJson(off.toJson()))
        assertTrue(SessionRequest.Circuit("circuit-20").cameraGames)
        // A request saved before the setting existed still reads, with camera games on.
        val saved = SessionRequest.Circuit("circuit-30", Difficulty.HARD).toJson()
        val old = SessionRequest.fromJson(saved.replace(""","cameraGames":true""", ""))
        assertTrue((old as SessionRequest.Circuit).cameraGames)
        val plan = SessionPlans.forRequest(off, ftp200, GameCatalog.DEFAULT)!!
        assertFalse(plan.segments.any { it.gameId == "dodge_ball" })
    }

    @Test
    fun `a slot no game in the catalog fits plays the stand-in`() {
        val demoOnly = GameCatalog(listOf(GameCatalog.DEMO))
        val plan = SessionPlans.circuit(CircuitPresets.TWENTY, Difficulty.STANDARD, ftp200, demoOnly)

        // The demo is never in a pool: it only stands in.
        assertTrue(plan.segments.all { it.gameId == "demo" })
        val withTug = GameCatalog(listOf(GameCatalog.DEMO, roundsGame.copy(id = "tug_of_war", minSec = 60, roles = setOf(SegmentRole.WORK))))
        val mixed = SessionPlans.circuit(CircuitPresets.TWENTY, Difficulty.STANDARD, ftp200, withTug)
        assertEquals("tug_of_war", mixed.segments[1].gameId)
        assertEquals("demo", mixed.segments[2].gameId) // no recovery game yet
    }

    // --- Circuit pools (#75) ----------------------------------------------------------------

    /** A game of [roles], like a wave-2 game declaring its circuit roles. */
    private fun poolGame(id: String, vararg roles: SegmentRole, minSec: Int = 60, camera: Boolean = false) = GameDeclaration(
        id = id,
        title = id,
        supports = setOf(JustRideSupport.MINUTES),
        minSec = minSec,
        roles = roles.toSet(),
        usesCamera = camera,
    )

    /** Eleven games, as the epic plans them: some only fit the 1:30 work slot, three need the camera. */
    /** Today's games plus fakes for the wave 2 games not registered yet (eleven or more). */
    private val elevenGames = GameCatalog(
        GameCatalog.DEFAULT.games + listOf(
            poolGame("power_grid", SegmentRole.WARMUP, SegmentRole.COOLDOWN, SegmentRole.WORK),
            poolGame("watt_lane", SegmentRole.WARMUP, SegmentRole.COOLDOWN, SegmentRole.RECOVERY),
            poolGame("gate_crasher", SegmentRole.WORK, camera = true),
            poolGame("ready_for_launch", SegmentRole.WORK, minSec = 90),
            poolGame("keepy_uppy", SegmentRole.RECOVERY),
            poolGame("the_pull"),
        ).filter { fake -> GameCatalog.DEFAULT[fake.id] == null },
    )

    private val catalogs = listOf(GameCatalog.DEFAULT, elevenGames)

    @Test
    fun `the eleven-game fake catalog has eleven games besides the demo`() {
        assertTrue(elevenGames.games.count { it.id != GameCatalog.DEMO.id } >= 11)
    }

    @Test
    fun `a circuit's draw is the same for the same seed and changes with it`() {
        for (catalog in catalogs) {
            val lineups = (0L until 30L).map { seed ->
                val a = SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, catalog, seed = seed)
                val b = SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, catalog, seed = seed)
                assertEquals(a, b)
                a.segments.map { it.gameId }
            }
            assertTrue("seeds give different mixes", lineups.toSet().size > 1)
        }
    }

    @Test
    fun `the plan id stays the preset's whichever games are drawn`() {
        for (catalog in catalogs) for (seed in 0L until 10L) {
            assertEquals("circuit-45", SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, catalog, seed = seed).planId)
        }
    }

    @Test
    fun `every slot gets a game of its role whose min_sec fits`() {
        for (catalog in catalogs) for (camera in listOf(true, false)) for (seed in 0L until 50L) {
            val plan = SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, catalog, cameraGames = camera, seed = seed)
            plan.segments.forEach { segment ->
                val game = catalog[segment.gameId]!!
                assertTrue("${game.id} in a ${segment.role} slot", segment.role in game.roles)
                assertTrue("${game.id} fits ${segment.durationSec}s", segment.durationSec in game.minSec..game.maxSec)
                assertFalse(game.id == GameCatalog.DEMO.id)
            }
        }
        // Ready for Launch (90 s) plays 1:30 work slots, never the 1:00 one.
        val plays = (0L until 50L).flatMap { seed ->
            SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, elevenGames, seed = seed).segments
        }.filter { it.gameId == "ready_for_launch" }
        assertTrue(plays.isNotEmpty())
        assertTrue(plays.all { it.durationSec == 90 })
    }

    @Test
    fun `no game repeats in a role until every game that fits has played`() {
        for (catalog in catalogs) for (camera in listOf(true, false)) for (seed in 0L until 50L) {
            val plan = SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, catalog, cameraGames = camera, seed = seed)
            for (role in SegmentRole.entries) {
                val played = mutableSetOf<String>()
                for ((i, slot) in plan.segments.withIndex()) {
                    if (slot.role != role) continue
                    if (slot.gameId in played) {
                        // Not twice running wins: a round may end early on the game that played
                        // the slot before (a game in two pools).
                        val before = plan.segments.getOrNull(i - 1)?.gameId
                        val fitting = catalog.circuitPool(role, camera).filter { slot.durationSec in it.minSec..it.maxSec }
                            .map { it.id }.filter { it != before }
                        assertTrue("$role repeats ${slot.gameId} before $fitting all played (seed $seed)", played.containsAll(fitting))
                        played.clear()
                    }
                    played += slot.gameId
                }
            }
        }
    }

    @Test
    fun `a 45-minute circuit covers each role's whole pool`() {
        for (catalog in catalogs) for (camera in listOf(true, false)) for (seed in 0L until 50L) {
            val plan = SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, catalog, cameraGames = camera, seed = seed)
            // 12 work and 12 recovery slots: every game of those pools plays at least once.
            for (role in listOf(SegmentRole.WORK, SegmentRole.RECOVERY)) {
                val pool = catalog.circuitPool(role, camera).map { it.id }.toSet()
                assertEquals("$role pool, seed $seed", pool, plan.segments.filter { it.role == role }.map { it.gameId }.toSet())
            }
        }
    }

    @Test
    fun `pools come from the catalog's roles and leave out the demo and, without the camera, camera games`() {
        assertEquals(listOf("cadence_karaoke"), GameCatalog.DEFAULT.circuitPool(SegmentRole.WARMUP).map { it.id })
        assertEquals(listOf("cadence_karaoke"), GameCatalog.DEFAULT.circuitPool(SegmentRole.COOLDOWN).map { it.id })
        assertEquals(setOf("dodge_ball", "tug_of_war", "balloon_pump"), GameCatalog.DEFAULT.circuitPool(SegmentRole.WORK).map { it.id }.toSet())
        assertEquals(listOf("tug_of_war", "balloon_pump"), GameCatalog.DEFAULT.circuitPool(SegmentRole.WORK, cameraGames = false).map { it.id })
        assertEquals(setOf("cadence_karaoke", "power_grid", "watt_lane"), elevenGames.circuitPool(SegmentRole.WARMUP).map { it.id }.toSet())
        assertFalse(elevenGames.circuitPool(SegmentRole.WORK, cameraGames = false).any { it.usesCamera })
        assertTrue(SegmentRole.entries.none { role -> elevenGames.circuitPool(role).any { it.id == "the_pull" || it.id == "kart_race" } })
    }

    @Test
    fun `no game plays two slots running when another fits`() {
        for (seed in 0L until 50L) {
            val plan = SessionPlans.circuit(CircuitPresets.FORTY_FIVE, Difficulty.STANDARD, ftp200, elevenGames, seed = seed)
            plan.segments.zipWithNext().forEach { (a, b) -> assertFalse("seed $seed", a.gameId == b.gameId) }
        }
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
    fun `the audio sent is the rider's volumes, clamped`() {
        val audio = GameAudioPrefs(musicVolume = 1.5, sfxVolume = 0.7).resolve()
        assertEquals(1.0, audio.musicVolume, 0.0)
        assertEquals(0.7, audio.sfxVolume, 0.0)
    }

    // --- Custom circuits (the Games hub, spec §3.4) ------------------------------------------

    private val catalog = GameCatalog.DEFAULT
    private fun slot(game: String, sec: Int) = CustomSlot(game, sec)

    @Test
    fun `a game's circuit role is work if it can work, else its main role, else free`() {
        assertEquals(SegmentRole.WORK, GameCatalog.circuitRole(GameCatalog.DODGE_BALL))
        assertEquals(SegmentRole.WORK, GameCatalog.circuitRole(GameCatalog.TUG_OF_WAR))
        assertEquals(SegmentRole.RECOVERY, GameCatalog.circuitRole(GameCatalog.SAFE_CRACKER))
        assertEquals(SegmentRole.RECOVERY, GameCatalog.circuitRole(GameCatalog.CADENCE_KARAOKE))
        assertEquals(SegmentRole.FREE, GameCatalog.circuitRole(GameCatalog.KART_RACE))
    }

    @Test
    fun `a custom circuit's id is its lineup, so the same lineup keys the same bests`() {
        val slots = listOf(slot("cadence_karaoke", 180), slot("kart_race", 600), slot("safe_cracker", 120))
        val plan = SessionPlans.custom(slots, Difficulty.STANDARD, ftp200, catalog)

        assertEquals("custom:cadence_karaoke.180,kart_race.600,safe_cracker.120", plan.planId)
        assertEquals(plan.planId, SessionPlans.custom(slots, Difficulty.HARD, ftp200, catalog).planId)
        assertEquals(SessionKind.CIRCUIT, plan.kind)
        assertEquals(listOf(180, 600, 120), plan.segments.map { it.durationSec })
    }

    @Test
    fun `custom lengths are clamped to the game's limits and rounded to 30 s`() {
        val plan = SessionPlans.custom(
            listOf(slot("kart_race", 60), slot("dodge_ball", 100), slot("tug_of_war", 9999), slot("safe_cracker", 74)),
            Difficulty.STANDARD, ftp200, catalog,
        )

        assertEquals(listOf(300, 90, 3600, 60), plan.segments.map { it.durationSec })
        assertEquals("custom:kart_race.300,dodge_ball.90,tug_of_war.3600,safe_cracker.60", plan.planId)
    }

    @Test
    fun `a custom slot plays its game's circuit role, warm-up first and cool-down last where the game has them`() {
        val plan = SessionPlans.custom(
            listOf(slot("cadence_karaoke", 180), slot("tug_of_war", 60), slot("cadence_karaoke", 90), slot("safe_cracker", 90), slot("cadence_karaoke", 180)),
            Difficulty.STANDARD, ftp200, catalog,
        )

        assertEquals(
            listOf(SegmentRole.WARMUP, SegmentRole.WORK, SegmentRole.RECOVERY, SegmentRole.RECOVERY, SegmentRole.COOLDOWN),
            plan.segments.map { it.role },
        )
        assertEquals(listOf(false, true, false, false, false), plan.segments.map { it.effort })
        assertEquals(130, plan.segments[0].params.int("power_cap_watts"))
        assertEquals(210, plan.segments[1].params.int("target_watts"))
        // A game without warm-up and cool-down roles plays its own role in the first and last slots.
        val ends = SessionPlans.custom(listOf(slot("safe_cracker", 90), slot("dodge_ball", 90)), Difficulty.STANDARD, ftp200, catalog)
        assertEquals(listOf(SegmentRole.RECOVERY, SegmentRole.WORK), ends.segments.map { it.role })
    }

    @Test
    fun `Kart Race plays free in a custom circuit and ends on its line`() {
        val kart = SessionPlans.custom(listOf(slot("kart_race", 600)), Difficulty.HARD, ftp200, catalog).segments.single()

        assertEquals(SegmentRole.FREE, kart.role)
        assertEquals(EndMode.GAME, kart.endMode)
        assertTrue(kart.effort)
        assertEquals(240, kart.params.int("target_watts"))
        assertTrue("bot_pcts" in kart.params)
        val timer = SessionPlans.custom(listOf(slot("tug_of_war", 60)), Difficulty.HARD, ftp200, catalog).segments.single()
        assertEquals(EndMode.TIMER, timer.endMode)
    }

    @Test
    fun `without camera games a custom slot goes to the next camera-free game of its role, keeping its id`() {
        val slots = listOf(slot("dodge_ball", 90), slot("safe_cracker", 90))
        val plan = SessionPlans.custom(slots, Difficulty.STANDARD, ftp200, catalog, cameraGames = false)

        assertEquals(listOf("tug_of_war", "safe_cracker"), plan.segments.map { it.gameId })
        assertEquals(SegmentRole.WORK, plan.segments[0].role)
        assertEquals("custom:dodge_ball.90,safe_cracker.90", plan.planId)
        assertNull(SessionPlans.customProblem(slots, catalog, cameraGames = false))
        // Kart Race has nothing to stand in for it.
        assertEquals(
            PlanRejectReason.CAMERA_UNAVAILABLE,
            SessionPlans.customProblem(listOf(slot("kart_race", 600)), catalog, cameraGames = false),
        )
    }

    @Test
    fun `custom circuits must have 1 to 12 known games and at most 90 minutes of play`() {
        assertEquals(PlanRejectReason.EMPTY_CIRCUIT, SessionPlans.customProblem(emptyList(), catalog))
        assertEquals(PlanRejectReason.UNKNOWN_GAME, SessionPlans.customProblem(listOf(slot("pinball", 60)), catalog))
        assertEquals(PlanRejectReason.TOO_LONG, SessionPlans.customProblem(List(13) { slot("tug_of_war", 60) }, catalog))
        assertNull(SessionPlans.customProblem(List(12) { slot("tug_of_war", 60) }, catalog))
        assertNull(SessionPlans.customProblem(List(3) { slot("kart_race", 1800) }, catalog)) // exactly 90 min
        assertEquals(PlanRejectReason.TOO_LONG, SessionPlans.customProblem(List(3) { slot("kart_race", 1830) }, catalog))
        assertThrows(IllegalArgumentException::class.java) {
            SessionPlans.custom(emptyList(), Difficulty.STANDARD, ftp200, catalog)
        }
    }

    @Test
    fun `custom requests round-trip as JSON and build their plans`() {
        val request = SessionRequest.Custom(listOf(slot("tug_of_war", 60)), Difficulty.EASY, cameraGames = false)

        assertEquals(request, SessionRequest.fromJson(request.toJson()))
        assertEquals("custom:tug_of_war.60", SessionPlans.forRequest(request, ftp200, catalog)!!.planId)
        assertNull(SessionPlans.forRequest(SessionRequest.Custom(emptyList()), ftp200, catalog))
    }

    // --- start_plan requests → SessionRequest --------------------------------------------------

    private fun map(request: PlanRequestMessage, cameraGames: Boolean = true) = request.toSessionRequest(cameraGames, catalog)

    @Test
    fun `Just Ride requests map by mode`() {
        val timed = PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = "kart_race", mode = "minutes", length = 10)
        val rounds = PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = "tug_of_war", mode = "rounds", length = 3, difficulty = Difficulty.HARD)
        val open = PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = "dodge_ball", mode = "open", difficulty = Difficulty.EASY)

        assertEquals(RequestMapping.Ok(SessionRequest.JustRide("kart_race", JustRideMode.Timed(10))), map(timed))
        assertEquals(RequestMapping.Ok(SessionRequest.JustRide("tug_of_war", JustRideMode.Rounds(3), Difficulty.HARD)), map(rounds))
        assertEquals(RequestMapping.Ok(SessionRequest.JustRide("dodge_ball", JustRideMode.Open, Difficulty.EASY)), map(open))
    }

    @Test
    fun `Just Ride requests are rejected for unknown games, unsupported modes and an unavailable camera`() {
        val just = PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = "kart_race", mode = "minutes", length = 10)

        assertEquals(RequestMapping.Rejected(PlanRejectReason.UNKNOWN_GAME), map(just.copy(gameId = "pinball")))
        assertEquals(RequestMapping.Rejected(PlanRejectReason.UNSUPPORTED_MODE), map(just.copy(mode = "rounds", length = 3)))
        assertEquals(RequestMapping.Rejected(PlanRejectReason.UNSUPPORTED_MODE), map(just.copy(mode = "sideways")))
        assertEquals(RequestMapping.Rejected(PlanRejectReason.CAMERA_UNAVAILABLE), map(just, cameraGames = false))
        assertTrue(map(just.copy(gameId = "tug_of_war"), cameraGames = false) is RequestMapping.Ok)
    }

    @Test
    fun `circuit and custom requests carry the camera setting`() {
        val circuit = PlanRequestMessage(PlanRequestKind.CIRCUIT, presetId = "circuit-30", difficulty = Difficulty.HARD)
        val custom = PlanRequestMessage(PlanRequestKind.CUSTOM, slots = listOf(PlanRequestSlot("dodge_ball", 90)))

        assertEquals(RequestMapping.Ok(SessionRequest.Circuit("circuit-30", Difficulty.HARD, cameraGames = false)), map(circuit, cameraGames = false))
        assertEquals(RequestMapping.Rejected(PlanRejectReason.UNKNOWN_GAME), map(circuit.copy(presetId = "circuit-99")))
        assertEquals(RequestMapping.Ok(SessionRequest.Custom(listOf(CustomSlot("dodge_ball", 90)), cameraGames = false)), map(custom, cameraGames = false))
        assertEquals(RequestMapping.Rejected(PlanRejectReason.EMPTY_CIRCUIT), map(custom.copy(slots = emptyList())))
    }

    @Test
    fun `an app-side request becomes the hub request that maps back to it`() {
        val requests = listOf(
            SessionRequest.JustRide("kart_race", JustRideMode.Timed(10), Difficulty.HARD),
            SessionRequest.JustRide("tug_of_war", JustRideMode.Rounds(3)),
            SessionRequest.JustRide("dodge_ball", JustRideMode.Open, Difficulty.EASY),
            SessionRequest.Circuit("circuit-30", Difficulty.HARD),
            SessionRequest.Custom(listOf(CustomSlot("tug_of_war", 60), CustomSlot("safe_cracker", 90))),
        )

        for (request in requests) {
            assertEquals(RequestMapping.Ok(request), request.toPlanRequest().toSessionRequest(cameraGames = true, catalog))
        }
    }
}
