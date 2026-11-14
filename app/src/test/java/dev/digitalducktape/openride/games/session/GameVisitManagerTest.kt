package dev.digitalducktape.openride.games.session

import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.InMemoryDatabaseRule
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import dev.digitalducktape.openride.core.telemetry.DurationBucket
import dev.digitalducktape.openride.core.telemetry.GameDifficulty
import dev.digitalducktape.openride.core.telemetry.GameFinish
import dev.digitalducktape.openride.core.telemetry.GameMusic
import dev.digitalducktape.openride.core.telemetry.GameMusicSwitch
import dev.digitalducktape.openride.core.telemetry.GameOutcome
import dev.digitalducktape.openride.core.telemetry.GamesPlanStart
import dev.digitalducktape.openride.core.telemetry.GamesPlayedBucket
import dev.digitalducktape.openride.core.telemetry.GamesVisitEnd
import dev.digitalducktape.openride.core.telemetry.OnOff
import dev.digitalducktape.openride.core.telemetry.PlanMode
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.RideEntry
import dev.digitalducktape.openride.core.telemetry.VisitEndReason
import dev.digitalducktape.openride.core.telemetry.VisitMusic
import dev.digitalducktape.openride.games.bridge.CameraPermission
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.FakeHeadTracker
import dev.digitalducktape.openride.games.bridge.PlanRequestKind
import dev.digitalducktape.openride.games.bridge.PlanRequestMessage
import dev.digitalducktape.openride.games.bridge.TrackerLink
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.toList
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * A hub visit end to end (Games hub spec §4-§5, §10) against a fake bridge ([RecordingSignals])
 * and the app's real recording path: [RideSessionManager] and Room (in memory, run inline so
 * virtual time drives it all). The plan runner's own timeline is in GameSessionManagerTest.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class GameVisitManagerTest {
    private val scope = TestScope()
    private val signals = RecordingSignals()
    private val bike = FakeBikeDataSource()
    private val settings = InMemoryGamesSettingsStore()
    private lateinit var rides: RideSessionManager
    private var riderId = 0L
    private val exits = mutableListOf<String>()
    private var clockMs = 1_760_000_000_000L
    private var permission = CameraPermission.GRANTED
    private var permissionAsks = 0

    /** While true, database work waits in [heldDb] (a save that takes a while). */
    private var holdDb = false
    private val heldDb = mutableListOf<Runnable>()

    @get:Rule val database = InMemoryDatabaseRule {
        setQueryExecutor { if (holdDb) heldDb += it else it.run() }
            .setTransactionExecutor { if (holdDb) heldDb += it else it.run() }
            .allowMainThreadQueries()
    }
    private val db get() = database.db

    /** A one-minute timed game, and a game that ends itself. */
    private val quick = GameDeclaration("quick", "Quick", setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN, JustRideSupport.ROUNDS), roundSec = 30, roles = setOf(dev.digitalducktape.openride.games.bridge.SegmentRole.WORK))
    private val racer = GameDeclaration("racer", "Racer", setOf(JustRideSupport.MINUTES), timedEndMode = EndMode.GAME, usesCamera = true)
    private val catalog = GameCatalog(listOf(GameCatalog.DEMO, quick, racer))

    @Before
    fun setUp() {
        riderId = runBlocking {
            db.profileDao().insert(Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0, weightKg = null, ftp = 200))
        }
        rides = RideSessionManager(bike, RideRepository(db, db.rideDao()), scope, autoPauseThresholdSec = 3) { clockMs }
        bike.setMetrics(cadenceRpm = 80, resistancePercent = 40, powerWatts = 180)
    }

    private val headTracker = FakeHeadTracker()
    private val trackerLink = TrackerLink(headTracker, signals, scope)

    private val navigator = VisitNavigator()
    private val telemetry = RecordingTelemetry()
    private var ownTrack = false

    private fun visit(profileId: Long? = riderId, tracker: TrackerLink? = null) = GameVisitManager(
        navigator = navigator,
        signals = signals,
        scope = scope,
        runner = GameSessionManager(signals, scope, tracker = tracker, random = Random(7), telemetry = telemetry, ownMusic = { ownTrack }),
        tracker = tracker,
        rideSessionManager = rides,
        routeLoaded = { false },
        gameResultDao = db.gameResultDao(),
        activeProfileId = { profileId },
        profile = { db.profileDao().getById(it) },
        settings = settings,
        cameraPermission = { permission },
        pedalling = { bike.metrics.value.cadenceRpm > 0 },
        catalog = catalog,
        clock = { clockMs++ },
        telemetry = telemetry,
        ownMusic = { ownTrack },
    ).also { it.permissionRequester = { permissionAsks++ } }

    private fun GameVisitManager.enter(autostart: PlanRequestMessage? = null): GameVisitManager {
        begin(autostart) { exits += it }
        onGameReady()
        scope.runCurrent()
        return this
    }

    private fun seconds(n: Int) {
        scope.advanceTimeBy(n * 1_000L)
        scope.runCurrent()
    }

    private fun GameVisitManager.call(block: GameVisitManager.() -> Unit): GameVisitManager {
        block()
        scope.runCurrent()
        return this
    }

    private fun GameVisitManager.start(json: String) = call { onStartPlan(json) }
    private fun GameVisitManager.startQuick(mode: String = "minutes", length: Int = 1) =
        start("""{"kind":"just_ride","game_id":"quick","mode":"$mode","length":$length,"difficulty":"standard"}""")

    private fun GameVisitManager.report(score: Double = 40.0, stars: Int = 2, skipped: Boolean = false, gameId: String = "quick") =
        call { onSegmentFinished("""{"game_id":"$gameId","score":$score,"stars":$stars,"won":null,"skipped":$skipped,"stats":{}}""") }

    /** A one-minute quick game played to its end: 70 ride seconds, 60 of gameplay. */
    private fun GameVisitManager.playQuickMinute(score: Double = 40.0, stars: Int = 2): GameVisitManager {
        startQuick()
        seconds(70)
        return report(score, stars)
    }

    private fun JsonObject.int(key: String) = this[key]!!.jsonPrimitive.int
    private fun JsonObject.str(key: String) = this[key]!!.jsonPrimitive.content
    private fun hub() = signals.payload("hub_state")
    private fun ended() = signals.payload("visit_ended")
    private fun allRides() = runBlocking { db.rideDao().getAllRidesOnce() }

    // --- Entering ---------------------------------------------------------------------------

    @Test
    fun `nothing is sent or recorded until the game is ready`() {
        visit().begin { exits += it }
        seconds(5)

        assertTrue(signals.events.isEmpty())
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    @Test
    fun `ready sends the hub state, and nothing is recorded with no plan`() {
        visit().enter()
        seconds(600)

        assertEquals(listOf("hub_state"), signals.names.distinct())
        val state = hub()
        assertEquals("hub", state.str("phase"))
        assertTrue(state.str("visit_id").startsWith("v-"))
        assertEquals("Ed", state["rider"]!!.jsonObject.str("name"))
        assertTrue(state["visit"]!!.jsonObject["recording"]!!.jsonPrimitive.boolean)
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    @Test
    fun `exiting with no plan played records nothing`() {
        val v = visit().enter().call { onExitHub("app") }

        assertEquals(listOf("app"), exits)
        assertFalse(ended()["saved"]!!.jsonPrimitive.boolean)
        assertEquals(JsonNull, ended()["ride_id"])
        assertEquals("too_short", ended().str("discarded_reason"))
        assertEquals(0, allRides().size)
        assertNull(v.finishedRideId.value)
    }

    // --- Recording --------------------------------------------------------------------------

    @Test
    fun `one ride records across two plans, with menu time excluded from duration and samples`() {
        val v = visit().enter().playQuickMinute(score = 100.0)
        assertEquals(RideSessionState.Paused, rides.state.value)
        seconds(300) // in the hub, pedalling: not riding by the rider's rule
        v.startQuick()
        seconds(70)
        v.report(score = 50.0)
        seconds(60)
        v.call { onExitHub("app") }

        val ride = allRides().single()
        assertEquals(140, ride.durationSec)
        assertEquals(140, runBlocking { db.rideDao().getSamples(ride.id) }.size)
        assertEquals(GameLabels.VISIT_PLAN, ride.gamePlan)
        assertEquals(1_760_000_000_000L + 1, ride.startEpochMs) // the first plan's start, not the entry
        val rows = runBlocking { db.gameResultDao().getForRide(ride.id) }
        assertEquals(listOf(0, 1), rows.map { it.segmentIndex })
        assertEquals(listOf(0, 1), rows.map { it.planRun })
        assertEquals(listOf("just-ride:quick:minutes:1", "just-ride:quick:minutes:1"), rows.map { it.planId })
        assertEquals(listOf(0, 70), rows.map { it.startSec })
        assertEquals(listOf(60, 60), rows.map { it.durationSec })
        assertEquals(ride.id, ended()["ride_id"]!!.jsonPrimitive.long)
        assertTrue(ended()["saved"]!!.jsonPrimitive.boolean)
        assertEquals(ride.id, v.finishedRideId.value)
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    @Test
    fun `a visit of one plan records that plan as the ride's gamePlan`() {
        visit().enter().playQuickMinute().call { onExitHub("app") }

        assertEquals("just-ride:quick:minutes:1", allRides().single().gamePlan)
    }

    @Test
    fun `session_finished ends a plan, not the ride, and carries the visit's keys`() {
        visit().enter().playQuickMinute(score = 640.0, stars = 3)

        val summary = signals.payload("session_finished")
        assertEquals(JsonNull, summary["ride_id"])
        assertEquals(hub().str("visit_id"), summary.str("visit_id"))
        assertEquals(0, summary.int("plan_index"))
        assertEquals("just-ride:quick:minutes:1", summary.str("plan_id"))
        assertEquals("standard", summary.str("difficulty"))
        assertEquals(70, summary["totals"]!!.jsonObject.int("elapsed_sec"))
        // The first scoring run of a plan is a best.
        assertEquals(setOf("score", "stars"), summary["bests"]!!.jsonObject.keys)
        // Back in the hub: the results are in hub_state.
        seconds(1)
        assertEquals("hub", hub().str("phase"))
        val plans = hub()["visit"]!!.jsonObject["plans"]!!.jsonArray
        assertEquals(640.0, plans.single().jsonObject["score"]!!.jsonPrimitive.double, 0.0)
        assertEquals(60, hub()["visit"]!!.jsonObject.int("gameplay_sec"))
    }

    @Test
    fun `the plan index and the calibration state go out with each session_started`() {
        val v = visit().enter().playQuickMinute()
        v.startQuick()

        val plans = signals.payloads("session_started")
        assertEquals(listOf(0, 1), plans.map { it.int("plan_index") })
        assertTrue(plans.all { it.str("visit_id") == plans.first().str("visit_id") })
        assertEquals(listOf("", ""), plans.map { it.str("calibrated") })
    }

    @Test
    fun `bests compare with earlier runs of the same plan in this visit`() {
        visit().enter().playQuickMinute(score = 500.0, stars = 2).playQuickMinute(score = 400.0, stars = 3)

        val bests = signals.payload("session_finished")["bests"]!!.jsonObject
        assertEquals(setOf("stars", "previous_score", "previous_stars"), bests.keys)
        assertEquals(500, bests.int("previous_score"))
        assertEquals(2, bests.int("previous_stars"))
    }

    @Test
    fun `bests compare with earlier visits too, and hub_state merges this visit's`() {
        visit().enter().playQuickMinute(score = 500.0, stars = 3).call { onExitHub("app") }
        signals.events.clear()

        val v = visit().enter().playQuickMinute(score = 600.0, stars = 1)
        val bests = signals.payload("session_finished")["bests"]!!.jsonObject
        assertEquals(setOf("score", "previous_score", "previous_stars"), bests.keys)
        seconds(1)
        val best = hub()["bests"]!!.jsonObject["games"]!!.jsonArray.single().jsonObject
        assertEquals(600.0, best["score"]!!.jsonPrimitive.double, 0.0)
        assertEquals(3, best.int("stars"))
        assertEquals(2, best.int("plays"))
        v.call { onExitHub("app") }
    }

    @Test
    fun `a visit with under a minute of gameplay is discarded`() {
        val v = visit().enter().startQuick("open")
        seconds(10 + 59) // a long intro doesn't count: only gameplay does
        v.call { onRequestEnd() }.report()
        v.call { onExitHub("app") }

        assertFalse(ended()["saved"]!!.jsonPrimitive.boolean)
        assertEquals("too_short", ended().str("discarded_reason"))
        assertEquals(0, allRides().size)
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    @Test
    fun `gameplay counts across the visit's plans for the one-minute rule`() {
        val v = visit().enter()
        repeat(2) {
            v.startQuick("open")
            seconds(10 + 40)
            v.call { onRequestEnd() }.report()
        }
        v.call { onExitHub("app") }

        assertTrue(ended()["saved"]!!.jsonPrimitive.boolean)
        assertEquals(1, allRides().size)
    }

    @Test
    fun `a visit without any pedalling is discarded, however long`() {
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        val v = visit().enter().startQuick()
        seconds(111)
        v.report().call { onExitHub("app") }

        assertEquals("no_pedalling", ended().str("discarded_reason"))
        assertEquals(0, allRides().size)
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    @Test
    fun `without an active rider the visit plays but records nothing`() {
        val v = visit(profileId = null).enter()
        assertFalse(hub()["visit"]!!.jsonObject["recording"]!!.jsonPrimitive.boolean)
        v.playQuickMinute()
        assertEquals(RideSessionState.Idle, rides.state.value)
        assertEquals(JsonObject(emptyMap()), signals.payload("session_finished")["bests"])
        v.call { onExitHub("app") }

        assertEquals("not_recording", ended().str("discarded_reason"))
        assertEquals(0, allRides().size)
    }

    @Test
    fun `a ride already in progress is left alone`() {
        rides.start(riderId, entry = RideEntry.HOME_QUICK_START, route = false)
        val v = visit().enter()
        assertFalse(hub()["visit"]!!.jsonObject["recording"]!!.jsonPrimitive.boolean)
        v.playQuickMinute().call { onExitHub("app") }

        assertEquals("not_recording", ended().str("discarded_reason"))
        assertEquals(RideSessionState.Active, rides.state.value)
    }

    @Test
    fun `a finished ride nobody dismissed doesn't block the visit`() {
        rides.start(riderId, entry = RideEntry.HOME_QUICK_START, route = false)
        seconds(5)
        runBlocking { rides.stop() }
        visit().enter().playQuickMinute().call { onExitHub("app") }

        assertEquals(2, allRides().size)
    }

    // --- Requests ---------------------------------------------------------------------------

    @Test
    fun `a start_plan while a plan runs is rejected as busy`() {
        val v = visit().enter().startQuick()
        v.startQuick()

        assertEquals("busy", signals.payload("plan_rejected").str("reason"))
        assertEquals(1, signals.names.count { it == "session_started" })
    }

    @Test
    fun `unplayable requests are rejected with the request as sent, and the hub stays put`() {
        val v = visit().enter()
        v.start("""{"kind":"just_ride","game_id":"pinball","mode":"open"}""")
        assertEquals("unknown_game", signals.payload("plan_rejected").str("reason"))
        assertEquals("pinball", signals.payload("plan_rejected")["request"]!!.jsonObject.str("game_id"))
        v.start("not json")
        assertEquals("unknown_game", signals.payload("plan_rejected").str("reason"))
        v.start("""{"kind":"custom","slots":[]}""")
        assertEquals("empty_circuit", signals.payload("plan_rejected").str("reason"))

        permission = CameraPermission.DENIED
        v.start("""{"kind":"just_ride","game_id":"racer","mode":"minutes","length":5}""")
        assertEquals("camera_unavailable", signals.payload("plan_rejected").str("reason"))

        assertFalse("session_started" in signals.names)
        v.playQuickMinute()
        assertEquals(1, signals.names.count { it == "session_started" })
    }

    @Test
    fun `camera games turned off in the hub make camera games unavailable`() {
        val v = visit().enter()
        v.call { onUpdateSetting("camera_games", "false") }
        seconds(1)
        assertFalse(settings.settings.value.cameraGames)
        assertFalse(hub()["camera"]!!.jsonObject["available"]!!.jsonPrimitive.boolean)
        v.start("""{"kind":"just_ride","game_id":"racer","mode":"minutes","length":5}""")
        assertEquals("camera_unavailable", signals.payload("plan_rejected").str("reason"))
    }

    @Test
    fun `settings are stored and the hub state follows, coalesced`() {
        val v = visit().enter()
        val before = signals.names.count { it == "hub_state" }
        v.call { onUpdateSetting("game_music", "false") }
        v.call { onUpdateSetting("music_volume", "0.4") }
        v.call { onUpdateSetting("brightness", "1") } // unknown: ignored
        seconds(1)

        assertEquals(0.4, settings.settings.value.audio.musicVolume, 0.0)
        assertEquals(before + 1, signals.names.count { it == "hub_state" })
        assertEquals(0.4, hub()["audio"]!!.jsonObject["music_volume"]!!.jsonPrimitive.double, 0.0)
        assertFalse(settings.settings.value.audio.gameMusic)
        assertFalse(hub()["audio"]!!.jsonObject["music"]!!.jsonPrimitive.boolean)
    }

    @Test
    fun `the camera permission is asked through the host, and its answer reaches the hub`() {
        permission = CameraPermission.ASK
        val v = visit().enter()
        assertEquals("ask", hub()["camera"]!!.jsonObject.str("permission"))
        v.call { onRequestCameraPermission() }
        assertEquals(1, permissionAsks)

        permission = CameraPermission.GRANTED
        v.call { onPermissionResult(true) }
        seconds(1)
        assertEquals("granted", hub()["camera"]!!.jsonObject.str("permission"))
    }

    @Test
    fun `the Compose tab's request autostarts once the hub is up`() {
        visit().enter(PlanRequestMessage(PlanRequestKind.JUST_RIDE, gameId = "quick", mode = "minutes", length = 1))

        assertEquals(listOf("hub_state", "session_started", "segment_started"), signals.names)
    }

    // --- Leaving ----------------------------------------------------------------------------

    @Test
    fun `exit saves the ride, sends visit_ended, then leaves for the next screen`() {
        val v = visit().enter().playQuickMinute().call { onExitHub("edit_profile") }

        assertEquals(listOf("edit_profile"), exits)
        assertEquals("edit_profile", ended().str("next"))
        assertEquals("exit", ended().str("reason"))
        assertEquals(hub().str("visit_id"), ended().str("visit_id"))
        assertEquals("visit_ended", signals.names.last())
        assertEquals(allRides().single().id, v.finishedRideId.value)
        v.call { onExitHub("app") } // once only
        assertEquals(1, exits.size)
    }

    @Test
    fun `request_exit in the hub exits to the app, and mid-plan ends the plan first`() {
        visit().enter().playQuickMinute().call { onRequestExit() }
        assertEquals(listOf("app"), exits)

        signals.events.clear()
        val v = visit().enter().startQuick("minutes", 2)
        seconds(75)
        v.call { onRequestExit() }

        assertEquals(listOf("session_finished", "visit_ended"), signals.names.filter { it != "hub_state" }.takeLast(2))
        assertEquals(listOf("app", "app"), exits)
        assertEquals(2, allRides().size)
    }

    @Test
    fun `back in the app, a live visit is saved and the next entry is a new visit`() {
        val v = visit().enter().playQuickMinute()
        val firstVisit = hub().str("visit_id")
        v.call { endIfLive("app_resumed") }

        assertEquals("app_resumed", ended().str("reason"))
        assertTrue(ended()["saved"]!!.jsonPrimitive.boolean)
        assertTrue(exits.isEmpty()) // the host is already behind the app
        assertEquals(1, allRides().size)
        v.call { endIfLive("app_resumed") } // nothing live: nothing happens
        assertEquals(1, signals.names.count { it == "visit_ended" })

        v.enter()
        assertNotEquals(firstVisit, hub().str("visit_id"))
    }

    @Test
    fun `saving is true while a visit's ride is saved, for the Games launcher`() {
        val v = visit().enter().playQuickMinute()
        val seen = mutableListOf<Boolean>()
        scope.backgroundScope.launch(UnconfinedTestDispatcher(scope.testScheduler)) { v.saving.toList(seen) }
        assertEquals(listOf(false), seen)

        v.call { endIfLive("app_resumed") }

        assertEquals(listOf(false, true, false), seen)
        assertFalse(v.saving.value)
    }

    @Test
    fun `back in the app mid-plan ends the plan and saves what was played`() {
        val v = visit().enter().startQuick("minutes", 5)
        seconds(10 + 90)
        v.call { endIfLive("app_resumed") }

        val ride = allRides().single()
        assertEquals(100, ride.durationSec)
        assertEquals(0, runBlocking { db.gameResultDao().getForRide(ride.id) }.size)
    }

    @Test
    fun `re-entering games while the last visit saves doesn't send the rider back out`() {
        // Review of PR #58: the save's onExit ran after the rider had re-entered, moving the new
        // visit's host to the back and detaching the bridge.
        val v = visit().enter().playQuickMinute()
        val firstVisit = hub().str("visit_id")
        holdDb = true
        v.call { onExitHub("app") }
        assertTrue(v.saving.value)
        v.enter() // Home, then Games again, while the ride is still being written

        holdDb = false
        while (heldDb.isNotEmpty()) {
            heldDb.removeAt(0).run()
            scope.runCurrent()
        }

        assertTrue(exits.isEmpty())
        assertNull(navigator.pending.value)
        assertEquals(1, allRides().size)
        assertNotEquals(firstVisit, hub().str("visit_id"))
    }

    @Test
    fun `re-entering games during a visit keeps it and resends the hub state`() {
        val v = visit().enter().playQuickMinute()
        val id = hub().str("visit_id")
        val states = signals.names.count { it == "hub_state" }
        v.enter()

        assertEquals(states + 1, signals.names.count { it == "hub_state" })
        assertEquals(id, hub().str("visit_id"))
        v.call { onExitHub("app") }
        assertEquals(1, runBlocking { db.gameResultDao().getAllOnce() }.size)
    }

    // --- The idle guard ---------------------------------------------------------------------

    @Test
    fun `an idle hub saves the visit's ride at 20 minutes, and a tap starts a new visit`() {
        val v = visit().enter().playQuickMinute()
        val id = hub().str("visit_id")
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        seconds(19 * 60 + 50)
        assertFalse("visit_ended" in signals.names)
        seconds(20)

        assertEquals("idle", ended().str("reason"))
        assertEquals("hub", ended().str("next"))
        assertTrue(ended()["saved"]!!.jsonPrimitive.boolean)
        assertTrue(exits.isEmpty())
        assertEquals(1, allRides().size)

        v.call { onHubActivity() }
        assertNotEquals(id, hub().str("visit_id"))
        assertEquals("hub", hub().str("phase"))
    }

    @Test
    fun `touches and pedalling keep the hub awake`() {
        val v = visit().enter().playQuickMinute()
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        seconds(15 * 60)
        v.call { onHubActivity() }
        seconds(15 * 60)
        bike.setMetrics(cadenceRpm = 60, resistancePercent = 40, powerWatts = 100)
        seconds(10)
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        seconds(15 * 60)

        assertFalse("visit_ended" in signals.names)
    }

    @Test
    fun `the idle guard never ends a plan`() {
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        val v = visit().enter().startQuick("open")
        seconds(30 * 60)

        assertFalse("visit_ended" in signals.names)
        v.call { onRequestEnd() }.report()
        seconds(20 * 60 + 5)
        assertEquals("idle", ended().str("reason"))
    }

    // --- Calibration once per visit (spec §6) -------------------------------------------------

    private val racerFive = """{"kind":"just_ride","game_id":"racer","mode":"minutes","length":5}"""

    @Test
    fun `a two-plan visit resets the tracker's centre once, and the second camera game tracks at once`() {
        val v = visit(tracker = trackerLink).enter().start(racerFive)
        v.call { onSetTrackerMode("lean_x") }
        headTracker.finishCalibration()
        scope.runCurrent()
        v.call { onRequestEnd() }
        seconds(5)
        assertEquals("setMode:off", headTracker.calls.last()) // the camera's off in the hub

        v.start(racerFive)
        assertEquals("lean_x", signals.payload("session_started").str("calibrated"))
        v.call { onSetTrackerMode("lean_x") }

        assertEquals(1, headTracker.calls.count { it == "resetSession" })
        assertEquals(1, headTracker.calls.count { it.startsWith("calibrate") })
        assertEquals(1, signals.names.count { it == "session_paused" }) // the first plan's calibration only
    }

    @Test
    fun `a hub calibration runs only in the hub and is reported in hub_state`() {
        val v = visit(tracker = trackerLink).enter()
        assertEquals("", hub()["camera"]!!.jsonObject.str("calibrated"))
        v.call { onHubCalibrate("lean_x", false) }
        assertEquals("calibrate:lean_x:force=false", headTracker.calls.last())
        headTracker.finishCalibration()
        seconds(1)

        assertEquals("setMode:off", headTracker.calls.last())
        assertEquals("lean_x", hub()["camera"]!!.jsonObject.str("calibrated"))
        v.call { onHubCalibrate("lean_x", true) }
        v.call { onCancelCalibration() }
        assertEquals("setMode:off", headTracker.calls.last())

        v.start(racerFive)
        val calls = headTracker.calls.size
        v.call { onHubCalibrate("lean_x", true) } // mid-plan: ignored
        assertEquals(calls, headTracker.calls.size)
    }

    @Test
    fun `the end of a visit turns the camera off, and the next visit calibrates afresh`() {
        val v = visit(tracker = trackerLink).enter().call { onHubCalibrate("lean_x", false) }
        headTracker.finishCalibration()
        scope.runCurrent()
        v.call { onExitHub("app") }
        assertEquals(listOf("setMode:off", "resetSession"), headTracker.calls.takeLast(2))

        v.enter()
        assertEquals(3, headTracker.calls.count { it == "resetSession" }) // visit start, end, start
        assertEquals("", hub()["camera"]!!.jsonObject.str("calibrated"))
    }


    // --- Where the app goes next ------------------------------------------------------------

    @Test
    fun `leaving games queues the ride summary, or the profile editor for the FTP nudge`() {
        val v = visit().enter().playQuickMinute().call { onExitHub("app") }
        assertEquals(VisitDestination.RideSummary(allRides().single().id), navigator.pending.value)

        navigator.consume(navigator.pending.value!!)
        v.enter().call { onExitHub("edit_profile") }
        assertEquals(VisitDestination.EditProfile, navigator.pending.value)
    }

    @Test
    fun `after the idle guard saved the visit, Exit still leaves games`() {
        val v = visit().enter().playQuickMinute()
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        seconds(20 * 60 + 5)
        assertEquals("idle", ended().str("reason"))
        assertEquals(null, navigator.pending.value) // the rider is still in games

        v.call { onExitHub("app") }

        assertEquals(listOf("app"), exits)
        assertEquals(1, signals.names.count { it == "visit_ended" })
        assertEquals(VisitDestination.RideSummary(allRides().single().id), navigator.pending.value)
    }

    @Test
    fun `the tracker gets the camera-games setting at the visit's start and on every change`() {
        settings.update { it.copy(cameraGames = false) }
        val v = visit(tracker = trackerLink).enter()
        assertTrue("setCameraGamesEnabled:false" in headTracker.calls)

        v.call { onUpdateSetting("camera_games", "true") }
        assertEquals("setCameraGamesEnabled:true", headTracker.calls.last())
    }

    // --- Telemetry (#85) ----------------------------------------------------------------------

    private fun visitEnds() = telemetry.events.filterIsInstance<GamesVisitEnd>()
    private fun finishes() = telemetry.events.filterIsInstance<GameFinish>()

    @Test
    fun `starting a plan emits games_plan_start with the mode, difficulty and music`() {
        visit().enter().startQuick()

        assertEquals(GamesPlanStart(PlanMode.SINGLE, GameDifficulty.STANDARD, GameMusic.GAME_MUSIC), telemetry.events.filterIsInstance<GamesPlanStart>().single())
    }

    @Test
    fun `a custom circuit is custom_circuit, and a rejected request emits nothing`() {
        val v = visit().enter()
        v.start("""{"kind":"custom","slots":[]}""")
        assertTrue(telemetry.events.filterIsInstance<GamesPlanStart>().isEmpty())
        v.start("""{"kind":"custom","difficulty":"hard","slots":[{"game_id":"quick","duration_sec":60}]}""")

        val e = telemetry.events.filterIsInstance<GamesPlanStart>().single()
        assertEquals(PlanMode.CUSTOM_CIRCUIT, e.mode)
        assertEquals(GameDifficulty.HARD, e.difficulty)
    }

    @Test
    fun `a visit with no games emits a visit end with zero games`() {
        visit().enter().call { onExitHub("app") }

        assertEquals(
            GamesVisitEnd(DurationBucket.LT_5M, GamesPlayedBucket.ZERO, VisitEndReason.EXIT, VisitMusic.GAME_MUSIC, false),
            visitEnds().single(),
        )
    }

    @Test
    fun `a visit end counts the games played, with the gameplay bucket`() {
        visit().enter().playQuickMinute().call { onExitHub("app") }

        val e = visitEnds().single()
        assertEquals(GamesPlayedBucket.ONE, e.games)
        assertEquals(VisitEndReason.EXIT, e.reason)
        assertEquals(listOf(GameOutcome.COMPLETED), finishes().map { it.outcome })
    }

    @Test
    fun `a skipped game is not counted as played`() {
        val v = visit().enter().startQuick()
        seconds(3)
        v.report(score = 0.0, stars = 0, skipped = true).call { onExitHub("app") }

        assertEquals(GamesPlayedBucket.ZERO, visitEnds().single().games)
        assertEquals(listOf(GameOutcome.SKIPPED), finishes().map { it.outcome })
    }

    @Test
    fun `leaving mid-game emits quit and counts it as played`() {
        val v = visit().enter().startQuick()
        seconds(40)
        v.call { onExitHub("app") }

        assertEquals(listOf(GameOutcome.QUIT), finishes().map { it.outcome })
        assertEquals(GamesPlayedBucket.ONE, visitEnds().single().games)
    }

    @Test
    fun `the end reason maps from the ending`() {
        val v = visit().enter().playQuickMinute()
        v.call { endIfLive("app_resumed") }
        assertEquals(VisitEndReason.APP_RESUMED, visitEnds().single().reason)
    }

    @Test
    fun `idle renewal starts new visit counters`() {
        val v = visit().enter().playQuickMinute()
        v.call { markMusicControl() }
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        seconds(20 * 60 + 5)

        val first = visitEnds().single()
        assertEquals(VisitEndReason.IDLE, first.reason)
        assertEquals(GamesPlayedBucket.ONE, first.games)
        assertTrue(first.musicControlsUsed)

        v.call { onHubActivity() }
        v.call { onExitHub("app") }

        val second = visitEnds().last()
        assertEquals(2, visitEnds().size)
        assertEquals(GamesPlayedBucket.ZERO, second.games)
        assertFalse(second.musicControlsUsed)
        assertEquals(DurationBucket.LT_5M, second.played)
    }

    @Test
    fun `music is mixed when own music starts mid-visit`() {
        val v = visit().enter().playQuickMinute()
        ownTrack = true
        v.startQuick()
        seconds(70)
        v.report().call { onExitHub("app") }

        assertEquals(VisitMusic.MIXED, visitEnds().single().music)
        assertEquals(listOf(GameMusic.GAME_MUSIC, GameMusic.OWN_MUSIC), finishes().map { it.music })
    }

    @Test
    fun `a whole visit on the rider's own music reads own_music`() {
        ownTrack = true
        visit().enter().playQuickMinute().call { onExitHub("app") }

        assertEquals(VisitMusic.OWN_MUSIC, visitEnds().single().music)
    }

    @Test
    fun `music controls used during the visit are reported`() {
        visit().enter().call { markMusicControl() }.call { onExitHub("app") }

        assertTrue(visitEnds().single().musicControlsUsed)
    }

    @Test
    fun `toggling game music emits once per change`() {
        val v = visit().enter()
        v.call { onUpdateSetting("game_music", "false") }
        v.call { onUpdateSetting("game_music", "false") } // no change
        v.call { onUpdateSetting("music_volume", "0.4") } // another setting
        v.call { onUpdateSetting("game_music", "true") }

        assertEquals(listOf(OnOff.OFF, OnOff.ON), telemetry.events.filterIsInstance<GameMusicSwitch>().map { it.value })
    }
}
