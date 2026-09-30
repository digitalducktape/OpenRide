package dev.digitalducktape.openride.games.session

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.FakeHeadTracker
import dev.digitalducktape.openride.games.bridge.TrackerLink
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.test.TestScope
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
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * The session timeline against a fake bridge ([RecordingSignals]) and the app's real recording
 * path: [RideSessionManager] and Room (in memory, run inline so virtual time drives it all).
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class GameSessionManagerTest {
    private val scope = TestScope()
    private val signals = RecordingSignals()
    private val bike = FakeBikeDataSource()
    private lateinit var db: OpenRideDatabase
    private lateinit var rides: RideSessionManager
    private var riderId = 0L
    private var exits = 0

    /** A one-minute timed game, and a game that ends itself. Neither has effort in Just Ride. */
    private val quick = GameDeclaration("quick", "Quick", setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN, JustRideSupport.ROUNDS), roundSec = 30)
    private val racer = GameDeclaration("racer", "Racer", setOf(JustRideSupport.MINUTES), timedEndMode = EndMode.GAME)
    private val catalog = GameCatalog(listOf(GameCatalog.DEMO, quick, racer))

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(ApplicationProvider.getApplicationContext(), OpenRideDatabase::class.java)
            .setQueryExecutor { it.run() }
            .setTransactionExecutor { it.run() }
            .allowMainThreadQueries()
            .build()
        riderId = runBlocking {
            db.profileDao().insert(Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0, weightKg = null, ftp = 200))
        }
        rides = RideSessionManager(bike, RideRepository(db, db.rideDao()), scope, autoPauseThresholdSec = 3) { 1_000L }
        bike.setMetrics(cadenceRpm = 80, resistancePercent = 40, powerWatts = 180)
    }

    @After
    fun tearDown() {
        db.close()
    }

    private fun manager(
        profileId: Long? = riderId,
        ftp: Int? = 200,
        otherMusic: Boolean = false,
        tracker: TrackerLink? = null,
        otherMusicNow: (() -> Boolean)? = null,
    ) = GameSessionManager(
        signals = signals,
        scope = scope,
        rideSessionManager = rides,
        gameResultDao = db.gameResultDao(),
        activeProfileId = { profileId },
        profileFtp = { ftp },
        tracker = tracker,
        catalog = catalog,
        otherMusicActive = otherMusicNow ?: { otherMusic },
        random = Random(7),
    )

    private fun GameSessionManager.play(request: SessionRequest): GameSessionManager {
        begin(request) { exits++ }
        onGameReady()
        scope.runCurrent()
        return this
    }

    private fun seconds(n: Int) {
        scope.advanceTimeBy(n * 1_000L)
        scope.runCurrent()
    }

    private fun GameSessionManager.report(score: Double = 40.0, stars: Int = 2, skipped: Boolean = false, gameId: String = "quick") {
        onSegmentFinished("""{"game_id":"$gameId","score":$score,"stars":$stars,"won":null,"skipped":$skipped,"stats":{"effort_avg":1.2}}""")
        scope.runCurrent()
    }

    private fun GameSessionManager.call(block: GameSessionManager.() -> Unit) {
        block()
        scope.runCurrent()
    }

    private val oneMinute = SessionRequest.JustRide("quick", JustRideMode.Timed(1))

    private fun JsonObject.int(key: String) = this[key]!!.jsonPrimitive.int
    private fun JsonObject.str(key: String) = this[key]!!.jsonPrimitive.content

    // --- Starting ---------------------------------------------------------------------------

    @Test
    fun `nothing is sent or recorded until the game is ready`() {
        manager().begin(oneMinute) {}
        seconds(5)

        assertTrue(signals.events.isEmpty())
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    @Test
    fun `ready starts the ride and sends the plan, then the first segment with its intro`() {
        val m = manager().play(SessionRequest.JustRide("demo", JustRideMode.Timed(20), Difficulty.HARD))

        assertEquals(listOf("session_started", "segment_started"), signals.names)
        assertEquals(RideSessionState.Active, rides.state.value)
        val plan = signals.payload("session_started")
        assertEquals("just_ride", plan.str("kind"))
        assertEquals("just-ride:demo:minutes:20", plan.str("plan_id"))
        assertEquals(1210, plan.int("total_sec"))
        val segment = signals.payload("segment_started")
        assertEquals(10, segment.int("intro_sec"))
        assertEquals(1200, segment.int("duration_sec"))
        assertEquals("timer", segment.str("end_mode"))
        assertEquals("free", segment.str("role"))
        assertEquals("hard", segment.str("difficulty"))
        // The demo declares effort_in_just_ride.
        assertTrue(segment["effort"]!!.jsonPrimitive.boolean)
        val params = segment["params"]!!.jsonObject
        assertEquals(240, params.int("target_watts"))
        assertEquals(70, params.int("cadence_floor"))
        assertTrue(segment["audio"]!!.jsonObject["music"]!!.jsonPrimitive.boolean)
        assertEquals(1200.0, m.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `game ready twice starts the session once`() {
        val m = manager().play(oneMinute)
        m.call { onGameReady() }

        assertEquals(1, signals.names.count { it == "session_started" })
    }

    @Test
    fun `a missing FTP scales to 150 W and flags it`() {
        manager(ftp = null).play(SessionRequest.JustRide("demo", JustRideMode.Open))

        val params = signals.payload("segment_started")["params"]!!.jsonObject
        assertEquals(158, params.int("target_watts"))
        assertTrue(params["ftp_is_default"]!!.jsonPrimitive.boolean)
    }

    @Test
    fun `game music is off when the rider's own music plays`() {
        manager(otherMusic = true).play(oneMinute)

        val audio = signals.payload("segment_started")["audio"]!!.jsonObject
        assertFalse(audio["music"]!!.jsonPrimitive.boolean)
        assertEquals(1.0, audio["sfx_volume"]!!.jsonPrimitive.double, 0.0)
    }

    @Test
    fun `game music is re-checked at every segment start`() {
        var riderMusic = true
        val m = manager(otherMusicNow = { riderMusic }).play(SessionRequest.Circuit("circuit-20"))
        riderMusic = false
        m.report(skipped = true, gameId = "demo")
        riderMusic = true
        m.report(skipped = true, gameId = "demo")

        assertEquals(
            listOf(false, true, false),
            signals.payloads("segment_started").map { it["audio"]!!.jsonObject["music"]!!.jsonPrimitive.boolean },
        )
    }

    @Test
    fun `effort is off in Just Rides of games that don't declare it`() {
        manager().play(oneMinute)

        assertFalse(signals.payload("segment_started")["effort"]!!.jsonPrimitive.boolean)
    }

    // --- Timer segments ---------------------------------------------------------------------

    @Test
    fun `time left counts gameplay only, and the timer ends the segment at its duration`() {
        val m = manager().play(oneMinute)

        seconds(10) // the intro card
        assertEquals(60.0, m.segmentTimeLeftSec, 0.0)
        seconds(59)
        assertEquals(1.0, m.segmentTimeLeftSec, 0.0)
        assertFalse("segment_ending" in signals.names)
        seconds(1)

        assertEquals("segment_ending", signals.names.last())
        assertEquals(0.0, m.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `a timed Just Ride records one ride with its result, then sends the summary`() {
        val m = manager().play(oneMinute)
        seconds(70)
        m.report(score = 640.0, stars = 3)

        assertEquals("session_finished", signals.names.last())
        val summary = signals.payload("session_finished")
        val rideId = summary["ride_id"]!!.jsonPrimitive.long
        val ride = runBlocking { db.rideDao().getById(rideId) }!!
        assertEquals("just-ride:quick:minutes:1", ride.gamePlan)
        assertEquals(70, ride.durationSec) // the intro card is ridden too
        assertEquals(riderId, ride.profileId)
        assertEquals(70, runBlocking { db.rideDao().getSamples(rideId) }.size)
        val row = runBlocking { db.gameResultDao().getForRide(rideId) }.single()
        assertEquals("quick", row.gameId)
        assertEquals("free", row.role)
        assertEquals("standard", row.difficulty)
        assertEquals(0, row.startSec)
        assertEquals(60, row.durationSec)
        assertEquals(640.0, row.score, 0.0)
        assertEquals(3, row.stars)
        assertNull(row.won)
        assertEquals("""{"effort_avg":1.2}""", row.statsJson)
        val totals = summary["totals"]!!.jsonObject
        assertEquals(640.0, totals["score"]!!.jsonPrimitive.double, 0.0)
        assertEquals(3, totals.int("stars"))
        assertEquals(70, totals.int("elapsed_sec"))
        assertEquals(1, summary["results"]!!.jsonArray.size)
        // The first scoring ride of a plan is a best.
        assertEquals(setOf("score", "stars"), summary["bests"]!!.jsonObject.keys)
        // The app's next ride can start.
        assertEquals(RideSessionState.Idle, rides.state.value)
        assertEquals(rideId, m.finishedRideId.value)
    }

    @Test
    fun `bests are only claimed when the session beats the last one`() {
        val m = manager()
        m.play(oneMinute)
        seconds(70)
        m.report(score = 500.0, stars = 2)
        m.play(oneMinute)
        seconds(70)
        m.report(score = 400.0, stars = 3)

        assertEquals(setOf("stars"), signals.payload("session_finished")["bests"]!!.jsonObject.keys)
    }

    @Test
    fun `no result within 5 s of segment_ending records a zero-score result`() {
        val m = manager().play(oneMinute)
        seconds(70)

        seconds(4)
        assertFalse("session_finished" in signals.names)
        seconds(1)

        val result = signals.payload("session_finished")["results"]!!.jsonArray.single().jsonObject
        assertEquals(0.0, result["score"]!!.jsonPrimitive.double, 0.0)
        assertFalse(result["skipped"]!!.jsonPrimitive.boolean)
        assertEquals(JsonNull, result["won"])
        val rideId = signals.payload("session_finished")["ride_id"]!!.jsonPrimitive.long
        assertEquals(0, runBlocking { db.gameResultDao().getForRide(rideId) }.single().stars)
    }

    @Test
    fun `a malformed result still advances, recorded as zero`() {
        val m = manager().play(oneMinute)
        seconds(70)
        m.call { onSegmentFinished("not json") }

        assertEquals("session_finished", signals.names.last())
        assertEquals(0.0, signals.payload("session_finished")["totals"]!!.jsonObject["score"]!!.jsonPrimitive.double, 0.0)
    }

    // --- Game-ended segments ----------------------------------------------------------------

    @Test
    fun `a game-ended segment runs past its duration and is hard-stopped at 1_5x`() {
        manager().play(SessionRequest.JustRide("racer", JustRideMode.Timed(1)))
        assertEquals("game", signals.payload("segment_started").str("end_mode"))

        seconds(10 + 60)
        assertFalse("segment_ending" in signals.names)
        seconds(29)
        assertFalse("segment_ending" in signals.names)
        seconds(1)

        assertEquals("segment_ending", signals.names.last())
    }

    @Test
    fun `a game-ended segment finishes when the game reports`() {
        val m = manager().play(SessionRequest.JustRide("racer", JustRideMode.Timed(2)))
        seconds(10 + 70)
        m.report(gameId = "racer")

        assertFalse("segment_ending" in signals.names)
        assertEquals("session_finished", signals.names.last())
        val rideId = signals.payload("session_finished")["ride_id"]!!.jsonPrimitive.long
        assertEquals(70, runBlocking { db.gameResultDao().getForRide(rideId) }.single().durationSec)
    }

    @Test
    fun `a rounds Just Ride is ended by the game`() {
        manager().play(SessionRequest.JustRide("quick", JustRideMode.Rounds(3)))

        val segment = signals.payload("segment_started")
        assertEquals("game", segment.str("end_mode"))
        assertEquals(90, segment.int("duration_sec"))
        assertEquals(3, segment["params"]!!.jsonObject.int("rounds"))
    }

    // --- Multi-segment plans ----------------------------------------------------------------

    @Test
    fun `a circuit walks its segments in order, skips advance at once, and effort follows the role`() {
        val m = manager().play(SessionRequest.Circuit("circuit-20"))
        val count = signals.payload("session_started")["segments"]!!.jsonArray.size
        assertEquals(10, count)

        // Play the warm-up, then skip every other segment from its intro card.
        seconds(10 + 180)
        m.report(gameId = "demo")
        repeat(count - 1) { m.report(skipped = true, gameId = "demo") }

        val segments = signals.payloads("segment_started")
        assertEquals((0 until count).toList(), segments.map { it.int("index") })
        assertEquals(
            listOf("warmup", "work", "recovery", "work", "recovery", "work", "recovery", "work", "recovery", "cooldown"),
            segments.map { it.str("role") },
        )
        assertEquals(segments.map { it.str("role") == "work" }, segments.map { it["effort"]!!.jsonPrimitive.boolean })
        assertTrue(segments.all { it.str("end_mode") == "timer" })
        assertEquals("session_finished", signals.names.last())
        val rideId = signals.payload("session_finished")["ride_id"]!!.jsonPrimitive.long
        val rows = runBlocking { db.gameResultDao().getForRide(rideId) }
        assertEquals((0 until count).toList(), rows.map { it.segmentIndex })
        assertEquals(listOf(false) + List(count - 1) { true }, rows.map { it.skipped })
        assertEquals("circuit-20", runBlocking { db.rideDao().getById(rideId) }!!.gamePlan)
    }

    @Test
    fun `each segment's start is recorded on the session clock`() {
        val m = manager().play(SessionRequest.Circuit("circuit-20"))
        seconds(10 + 180) // warm-up played to its end
        m.report(gameId = "demo")
        seconds(15)
        m.report(gameId = "demo")
        m.call { onRequestEnd() } // during the third segment's intro card, which never reports
        seconds(5)

        val rideId = signals.payload("session_finished")["ride_id"]!!.jsonPrimitive.long
        val rows = runBlocking { db.gameResultDao().getForRide(rideId) }
        assertEquals(listOf(0, 190, 205), rows.map { it.startSec })
        assertEquals(listOf(180, 5, 0), rows.map { it.durationSec })
    }

    // --- Pause ------------------------------------------------------------------------------

    @Test
    fun `the rider's pause pauses the ride and freezes the clock`() {
        val m = manager().play(oneMinute)
        seconds(20)
        m.call { onRequestPause() }
        m.call { onRequestPause() } // signalled once

        assertEquals(RideSessionState.Paused, rides.state.value)
        seconds(30)
        assertEquals(50.0, m.segmentTimeLeftSec, 0.0)

        m.call { onRequestResume() }
        seconds(10)
        assertEquals(40.0, m.segmentTimeLeftSec, 0.0)
        assertEquals(RideSessionState.Active, rides.state.value)
        assertEquals(listOf("session_paused", "session_resumed"), signals.names.filter { it.startsWith("session_p") || it.startsWith("session_r") })
    }

    @Test
    fun `the ride's freewheel auto-pause pauses the session until the rider pedals again`() {
        val m = manager().play(oneMinute)
        seconds(20)
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        seconds(3)

        assertEquals("session_paused", signals.names.last())
        val left = m.segmentTimeLeftSec
        seconds(20)
        assertEquals(left, m.segmentTimeLeftSec, 0.0)

        bike.setMetrics(cadenceRpm = 80, resistancePercent = 40, powerWatts = 180)
        seconds(1)
        assertEquals("session_resumed", signals.names.last())
    }

    @Test
    fun `a rider's pause during an auto-pause holds when pedalling resumes`() {
        val m = manager().play(oneMinute)
        seconds(20)
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        seconds(3)
        m.call { onRequestPause() }
        bike.setMetrics(cadenceRpm = 80, resistancePercent = 40, powerWatts = 180)
        seconds(5)

        assertEquals("session_paused", signals.names.last())
        m.call { onRequestResume() }
        assertEquals("session_resumed", signals.names.last())
    }

    // --- Ending -----------------------------------------------------------------------------

    @Test
    fun `request_end mid-segment asks the game to finish, then saves and finishes`() {
        val m = manager().play(SessionRequest.JustRide("quick", JustRideMode.Timed(2)))
        seconds(10 + 60)
        m.call { onRequestEnd() }
        assertEquals("segment_ending", signals.names.last())
        m.report()

        assertEquals("session_finished", signals.names.last())
        assertTrue(signals.payload("session_finished")["ride_id"]!!.jsonPrimitive.long > 0)
    }

    @Test
    fun `request_end while paused still finishes after the grace period`() {
        val m = manager().play(SessionRequest.JustRide("quick", JustRideMode.Timed(2)))
        seconds(10 + 80)
        m.call { onRequestPause() }
        m.call { onRequestEnd() }
        seconds(5)

        assertEquals("session_finished", signals.names.last())
        val rideId = signals.payload("session_finished")["ride_id"]!!.jsonPrimitive.long
        // The paused seconds aren't ridden.
        assertEquals(90, runBlocking { db.rideDao().getById(rideId) }!!.durationSec)
    }

    @Test
    fun `an open-ended Just Ride waits for request_end after its game ends`() {
        val m = manager().play(SessionRequest.JustRide("quick", JustRideMode.Open))
        seconds(10)
        assertEquals(-1.0, m.segmentTimeLeftSec, 0.0)
        seconds(600)
        assertFalse("segment_ending" in signals.names)

        m.report()
        assertFalse("session_finished" in signals.names)
        m.call { onRequestEnd() }

        assertEquals("session_finished", signals.names.last())
        assertEquals("just-ride:quick:open", runBlocking {
            db.rideDao().getById(signals.payload("session_finished")["ride_id"]!!.jsonPrimitive.long)
        }!!.gamePlan)
    }

    @Test
    fun `request_exit before the summary saves the ride and leaves`() {
        val m = manager().play(SessionRequest.JustRide("quick", JustRideMode.Timed(2)))
        seconds(10 + 65)
        m.call { onRequestExit() }

        assertEquals(1, exits)
        assertEquals("session_finished", signals.names.last())
        assertEquals(RideSessionState.Idle, rides.state.value)
        assertEquals(1, runBlocking { db.rideDao().getAllRidesOnce() }.size)
        m.call { onRequestExit() }
        assertEquals(1, exits)
    }

    @Test
    fun `entering games again during a session saves the old ride before starting the new one`() {
        val m = manager().play(SessionRequest.JustRide("quick", JustRideMode.Timed(2)))
        seconds(10 + 65)
        m.play(oneMinute)

        assertEquals(listOf("session_started", "segment_started", "session_finished", "session_started", "segment_started"), signals.names)
        assertEquals(1, runBlocking { db.rideDao().getAllRidesOnce() }.size)
        assertEquals(RideSessionState.Active, rides.state.value)
    }

    // --- Not recorded -----------------------------------------------------------------------

    @Test
    fun `a session with under a minute of gameplay is discarded`() {
        val m = manager().play(SessionRequest.JustRide("quick", JustRideMode.Open))
        seconds(10 + 59) // a long intro doesn't count: only gameplay does
        m.call { onRequestEnd() }
        m.report()

        assertEquals(JsonNull, signals.payload("session_finished")["ride_id"])
        assertEquals(JsonObject(emptyMap()), signals.payload("session_finished")["bests"])
        assertEquals(0, runBlocking { db.rideDao().getAllRidesOnce() }.size)
        assertEquals(RideSessionState.Idle, rides.state.value)
        assertNull(m.finishedRideId.value)
    }

    @Test
    fun `a session skipped from its intro card is discarded`() {
        val m = manager().play(oneMinute)
        seconds(4)
        m.report(skipped = true)

        assertEquals(JsonNull, signals.payload("session_finished")["ride_id"])
        assertEquals(0, runBlocking { db.rideDao().getAllRidesOnce() }.size)
    }

    @Test
    fun `a minute of gameplay is kept`() {
        val m = manager().play(SessionRequest.JustRide("quick", JustRideMode.Open))
        seconds(10 + 60)
        m.call { onRequestEnd() }
        m.report()

        assertEquals(1, runBlocking { db.rideDao().getAllRidesOnce() }.size)
    }

    @Test
    fun `a session without any pedalling is discarded, however long`() {
        bike.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        val m = manager().play(oneMinute)
        seconds(111)
        m.report()

        assertEquals(JsonNull, signals.payload("session_finished")["ride_id"])
        assertEquals(0, runBlocking { db.rideDao().getAllRidesOnce() }.size)
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    @Test
    fun `a discarded session doesn't block the next ride`() {
        val m = manager().play(oneMinute)
        seconds(5)
        m.call { onRequestExit() }
        m.play(oneMinute)

        assertEquals(RideSessionState.Active, rides.state.value)
    }

    @Test
    fun `without an active rider the session plays but records nothing`() {
        val m = manager(profileId = null).play(oneMinute)
        assertEquals(RideSessionState.Idle, rides.state.value)
        seconds(70)
        m.report()

        assertEquals(JsonNull, signals.payload("session_finished")["ride_id"])
        assertEquals(0, runBlocking { db.rideDao().getAllRidesOnce() }.size)
    }

    @Test
    fun `a ride already in progress is left alone`() {
        rides.start(riderId)
        val m = manager().play(oneMinute)
        seconds(70)
        m.report()

        assertEquals(JsonNull, signals.payload("session_finished")["ride_id"])
        assertEquals(RideSessionState.Active, rides.state.value)
    }

    @Test
    fun `a finished ride nobody dismissed doesn't block the session`() {
        rides.start(riderId)
        seconds(5)
        runBlocking { rides.stop() }
        val m = manager().play(oneMinute)

        assertEquals(RideSessionState.Active, rides.state.value)
        seconds(70)
        m.report()
        assertEquals(2, runBlocking { db.rideDao().getAllRidesOnce() }.size)
    }

    @Test
    fun `an unplayable request finishes at once`() {
        manager().play(SessionRequest.JustRide("nope", JustRideMode.Open))

        assertEquals(listOf("session_finished"), signals.names)
        assertEquals(RideSessionState.Idle, rides.state.value)
    }

    // --- Head tracker -----------------------------------------------------------------------

    @Test
    fun `the head tracker follows the session - fresh centre, game modes, recalibration, off at the end`() {
        val tracker = FakeHeadTracker()
        val m = manager(tracker = TrackerLink(tracker, signals, scope)).play(oneMinute)

        m.call { onSetTrackerMode("lean_x") }
        assertEquals(listOf("resetSession", "setMode:lean_x", "calibrate:lean_x:force=false"), tracker.calls)
        assertEquals("centre:0.0", signals.events.last { it.first == "calibration_progress" }.second)

        tracker.finishCalibration()
        m.call { onRequestCalibration("lean_2d") }
        m.call { onRequestEnd() }
        seconds(5)
        assertEquals("session_finished", signals.names.last())
        m.call { onSetTrackerMode("lean_x") } // from the summary screen: ignored

        assertEquals(
            listOf(
                "resetSession", "setMode:lean_x", "calibrate:lean_x:force=false",
                "calibrate:lean_2d:force=true", "setMode:off",
            ),
            tracker.calls,
        )
    }
}
