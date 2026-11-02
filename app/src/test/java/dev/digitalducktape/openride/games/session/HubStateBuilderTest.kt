package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.data.GamePersonalBest
import dev.digitalducktape.openride.core.data.PlanBestRow
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.games.bridge.CameraPermission
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.HubGameBest
import dev.digitalducktape.openride.games.bridge.HubPhase
import dev.digitalducktape.openride.games.bridge.HubPlanBest
import dev.digitalducktape.openride.games.bridge.SegmentRole
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HubStateBuilderTest {
    private val ed = Profile(id = 3, name = " Ed ", avatarEmoji = "🚴", avatarColor = 0xFF4F7CFF.toInt(), weightKg = null, ftp = 220)

    private fun inputs(
        profile: Profile? = ed,
        settings: GamesSettings = GamesSettings(),
        permission: CameraPermission = CameraPermission.GRANTED,
        cameraFailed: Boolean = false,
        gameBests: List<GamePersonalBest> = emptyList(),
        planBests: List<PlanBestRow> = emptyList(),
        visitResults: List<VisitResult> = emptyList(),
        visitPlans: List<VisitPlan> = emptyList(),
    ) = HubInputs(
        visitId = "v-1",
        phase = HubPhase.HUB,
        profile = profile,
        avatarPng = "/cache/games/avatar_3.png",
        settings = settings,
        permission = permission,
        cameraFailed = cameraFailed,
        calibrated = "",
        sameDayExtremes = false,
        catalog = GameCatalog.DEFAULT,
        gameBests = gameBests,
        planBests = planBests,
        recording = true,
        rideSec = 0,
        visitResults = visitResults,
        visitPlans = visitPlans,
    )

    @Test
    fun `the rider comes from the profile, with the FTP nudge only when FTP is unset`() {
        val rider = HubStateBuilder.build(inputs()).rider
        assertEquals(3L, rider.id)
        assertEquals("Ed", rider.name)
        assertEquals("#4F7CFF", rider.avatarColor)
        assertEquals(220, rider.ftpWatts)
        assertFalse(rider.ftpIsDefault)

        val unset = HubStateBuilder.build(inputs(profile = ed.copy(ftp = null))).rider
        assertEquals(150, unset.ftpWatts)
        assertTrue(unset.ftpIsDefault)
    }

    @Test
    fun `with no active rider the hub plays as a guest`() {
        val rider = HubStateBuilder.build(inputs(profile = null)).rider
        assertNull(rider.id)
        assertEquals("", rider.name)
        assertNull(rider.avatarPng)
        assertTrue(rider.ftpIsDefault)
    }

    @Test
    fun `the catalog leaves out the demo and gives each game's minute steps within its limits`() {
        val catalog = HubStateBuilder.build(inputs()).catalog.associateBy { it.id }

        assertFalse("demo" in catalog)
        assertEquals(listOf("dodge_ball", "tug_of_war", "safe_cracker", "cadence_karaoke", "kart_race", "keepy_uppy"),
            catalog.keys.toList())
        assertEquals(listOf(5, 10, 15, 20, 30, 45, 60), catalog["kart_race"]!!.minuteSteps)
        assertEquals(listOf("minutes", "open"), catalog["kart_race"]!!.supports)
        assertEquals(listOf("minutes", "rounds", "open"), catalog["dodge_ball"]!!.supports)
        assertEquals(300, catalog["kart_race"]!!.minSec)
        assertTrue(catalog["kart_race"]!!.usesCamera)
    }

    @Test
    fun `a game whose limits fit no minute step offers its shortest length`() {
        val odd = GameDeclaration("odd", "Odd", setOf(JustRideSupport.MINUTES), minSec = 120, maxSec = 240)
        val state = HubStateBuilder.build(inputs().copy(catalog = GameCatalog(listOf(odd))))
        assertEquals(listOf(2), state.catalog.single().minuteSteps)
    }

    @Test
    fun `each game's circuit role follows the custom-circuit rule`() {
        val roles = HubStateBuilder.build(inputs()).catalog.associate { it.id to it.circuitRole }
        assertEquals(SegmentRole.WORK, roles["dodge_ball"])
        assertEquals(SegmentRole.RECOVERY, roles["safe_cracker"])
        assertEquals(SegmentRole.RECOVERY, roles["cadence_karaoke"])
        assertEquals(SegmentRole.FREE, roles["kart_race"])
    }

    @Test
    fun `the camera is available only with permission, camera games on and no failure`() {
        assertTrue(HubStateBuilder.build(inputs()).camera.available)
        assertEquals(CameraPermission.ASK, HubStateBuilder.build(inputs(permission = CameraPermission.ASK)).camera.permission)
        assertFalse(HubStateBuilder.build(inputs(permission = CameraPermission.ASK)).camera.available)
        assertFalse(HubStateBuilder.build(inputs(permission = CameraPermission.DENIED)).camera.available)
        assertFalse(HubStateBuilder.build(inputs(settings = GamesSettings(cameraGames = false))).camera.available)
        assertFalse(HubStateBuilder.build(inputs(cameraFailed = true)).camera.available)
    }

    @Test
    fun `presets show the lineup they'd play now, with camera games swapped out when unavailable`() {
        val on = HubStateBuilder.build(inputs()).circuits.first { it.id == "circuit-20" }
        assertEquals(20, on.minutes)
        assertEquals(1120, on.totalSec)
        assertTrue(on.slots.any { it.gameId == "dodge_ball" })

        val off = HubStateBuilder.build(inputs(permission = CameraPermission.DENIED)).circuits.first { it.id == "circuit-20" }
        assertFalse(off.slots.any { it.gameId == "dodge_ball" })
        assertEquals(on.slots.map { it.role }, off.slots.map { it.role })
    }

    @Test
    fun `settings and the resolved audio are sent as wire words`() {
        val state = HubStateBuilder.build(inputs(settings = GamesSettings(GameAudioPrefs(gameMusic = false, musicVolume = 0.5, sfxVolume = 0.7))))
        assertFalse(state.settings.gameMusic)
        assertFalse(state.audio.music)
        assertEquals(0.5, state.settings.musicVolume, 0.0)
        assertEquals(0.5, state.audio.musicVolume, 0.0)
        assertEquals(0.7, state.audio.sfxVolume, 0.0)
    }

    @Test
    fun `game bests merge this visit's results`() {
        val kart = "just-ride:kart_race:minutes:10"
        val state = HubStateBuilder.build(
            inputs(
                gameBests = listOf(GamePersonalBest("kart_race", kart, "standard", 700.0, 3, 4)),
                visitResults = listOf(
                    VisitResult(kart, 0, "kart_race", "standard", "", 812.0, 2, skipped = false),
                    VisitResult("circuit-20", 1, "dodge_ball", "hard", "catch", 90.0, 1, skipped = false),
                    VisitResult("circuit-20", 1, "tug_of_war", "hard", "", 0.0, 0, skipped = true),
                ),
            ),
        )

        assertEquals(
            listOf(
                HubGameBest("dodge_ball", "circuit-20", Difficulty.HARD, "catch", 90.0, 1, 1),
                HubGameBest("kart_race", kart, Difficulty.STANDARD, "", 812.0, 3, 5),
            ),
            state.bests.games,
        )
    }

    @Test
    fun `plan bests cover presets and the last 20 custom circuits, merged with this visit`() {
        val customs = (1..25).map { PlanBestRow("custom:tug_of_war.${it * 30}", "standard", it.toDouble(), 1, lastPlayedMs = it.toLong()) }
        val state = HubStateBuilder.build(
            inputs(
                planBests = customs + listOf(
                    PlanBestRow("circuit-20", "standard", 100.0, 10, 0),
                    PlanBestRow("just-ride:kart_race:minutes:10", "standard", 812.0, 2, 0),
                ),
                visitPlans = listOf(VisitPlan("circuit-20", Difficulty.STANDARD, "", 150.0, 9, listOf("tug_of_war"))),
            ),
        )

        val plans = state.bests.plans.associateBy { it.planId }
        assertEquals(HubPlanBest("circuit-20", Difficulty.STANDARD, 150.0, 10), plans["circuit-20"])
        assertFalse("just-ride:kart_race:minutes:10" in plans)
        assertEquals(20, plans.keys.count { it.startsWith("custom:") })
        assertFalse("custom:tug_of_war.30" in plans) // the oldest five drop out
        assertTrue("custom:tug_of_war.750" in plans)
    }

    @Test
    fun `the visit block sums this visit's plans`() {
        val visit = HubStateBuilder.build(
            inputs(
                visitResults = listOf(VisitResult("circuit-20", 0, "tug_of_war", "standard", "", 50.0, 1, skipped = false, playedSec = 60)),
                visitPlans = listOf(VisitPlan("circuit-20", Difficulty.STANDARD, "", 50.0, 1, listOf("tug_of_war"))),
            ).copy(rideSec = 754),
        ).visit

        assertTrue(visit.recording)
        assertEquals(754, visit.rideSec)
        assertEquals(60, visit.gameplaySec)
        assertEquals(listOf("tug_of_war"), visit.plans.single().gameIds)
    }
}
