package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.telemetry.GameDifficulty
import dev.digitalducktape.openride.core.telemetry.GameFinish
import dev.digitalducktape.openride.core.telemetry.GameId
import dev.digitalducktape.openride.core.telemetry.GameMusic
import dev.digitalducktape.openride.core.telemetry.GameOutcome
import dev.digitalducktape.openride.core.telemetry.GamePlayedBucket
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.Stars
import dev.digitalducktape.openride.core.telemetry.Won
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.FakeHeadTracker
import dev.digitalducktape.openride.games.bridge.TrackerLink
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
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
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The plan runner: one plan's timeline against a fake bridge ([RecordingSignals]) and a fake
 * ride ([FakePlanRide]), in virtual time. Recording (the ride, results, bests) is the visit's,
 * tested in GameVisitManagerTest.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class GameSessionManagerTest {
    private val scope = TestScope()
    private val signals = RecordingSignals()
    private val ride = FakePlanRide(scope)
    private val outcomes = mutableListOf<PlanOutcome>()

    /** A one-minute timed game, and a game that ends itself. Neither has effort in Just Ride. */
    private val quick = GameDeclaration("quick", "Quick", setOf(JustRideSupport.MINUTES, JustRideSupport.OPEN, JustRideSupport.ROUNDS), roundSec = 30)
    private val racer = GameDeclaration("racer", "Racer", setOf(JustRideSupport.MINUTES), timedEndMode = EndMode.GAME)
    private val catalog = GameCatalog(listOf(GameCatalog.DEMO, quick, racer))

    private val telemetry = RecordingTelemetry()
    private var ownTrack = false
    private var gameMusicOn = true

    private fun runner(tracker: TrackerLink? = null) = GameSessionManager(
        signals = signals,
        scope = scope,
        tracker = tracker,
        audioPrefs = { GameAudioPrefs(gameMusic = gameMusicOn) },
        random = Random(7),
        telemetry = telemetry,
        ownMusic = { ownTrack },
    ).also { lastRunner = it }

    private var lastRunner: GameSessionManager? = null

    private fun finishes() = telemetry.events.filterIsInstance<GameFinish>()

    private fun plan(request: SessionRequest, ftp: Int? = 200) = SessionPlans.forRequest(request, FtpBasis.of(ftp), catalog)!!

    private fun GameSessionManager.play(
        request: SessionRequest,
        start: PlanStart = PlanStart(riderId = 3, riderName = "Ed"),
        ftp: Int? = 200,
    ): GameSessionManager {
        run(plan(request, ftp), ride, start) { outcomes += it }
        scope.runCurrent()
        return this
    }

    private fun seconds(n: Int) {
        scope.advanceTimeBy(n * 1_000L)
        scope.runCurrent()
    }

    private fun GameSessionManager.report(score: Double = 40.0, stars: Int = 2, skipped: Boolean = false, gameId: String = "quick", variant: String = "") {
        segmentFinished("""{"game_id":"$gameId","score":$score,"stars":$stars,"won":null,"skipped":$skipped,"stats":{"effort_avg":1.2},"variant":"$variant"}""")
        scope.runCurrent()
    }

    private fun GameSessionManager.call(block: GameSessionManager.() -> Unit) {
        block()
        scope.runCurrent()
    }

    private val oneMinute = SessionRequest.JustRide("quick", JustRideMode.Timed(1))

    private fun JsonObject.int(key: String) = this[key]!!.jsonPrimitive.int
    private fun JsonObject.str(key: String) = this[key]!!.jsonPrimitive.content
    private fun pauseSignals() = signals.names.filter { it == "session_paused" || it == "session_resumed" }

    // --- Starting ---------------------------------------------------------------------------

    @Test
    fun `run sends the plan, then the first segment with its intro`() {
        val m = runner().play(SessionRequest.JustRide("demo", JustRideMode.Timed(20), Difficulty.HARD))

        assertEquals(listOf("session_started", "segment_started"), signals.names)
        assertTrue(m.isRunning)
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
        assertTrue(segment["audio"]!!.jsonObject["music"]!!.jsonPrimitive.boolean) // the Game music switch, on by default
        assertEquals(1200.0, m.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `the plan names the rider and carries the visit's keys`() {
        runner().play(oneMinute, PlanStart(riderId = 3, riderName = " Ed ", visitId = "v-1", planIndex = 2, calibrated = "lean_x"))

        val plan = signals.payload("session_started")
        assertEquals(3L, plan["rider_id"]!!.jsonPrimitive.long)
        assertEquals("Ed", plan.str("rider_name"))
        assertEquals("v-1", plan.str("visit_id"))
        assertEquals(2, plan.int("plan_index"))
        assertEquals("lean_x", plan.str("calibrated"))
    }

    @Test
    fun `a plan with no rider and no visit sends v1's keys only`() {
        runner().play(oneMinute, PlanStart())

        val plan = signals.payload("session_started")
        assertEquals(JsonNull, plan["rider_id"])
        assertEquals(JsonNull, plan["rider_name"])
        assertFalse("visit_id" in plan)
    }

    @Test
    fun `a second run while one is running is refused`() {
        val m = runner().play(oneMinute)
        m.run(plan(oneMinute), ride, PlanStart()) { outcomes += it }

        assertEquals(1, signals.names.count { it == "session_started" })
    }

    @Test
    fun `a missing FTP scales to 150 W and flags it`() {
        runner().play(SessionRequest.JustRide("demo", JustRideMode.Open), ftp = null)

        val params = signals.payload("segment_started")["params"]!!.jsonObject
        assertEquals(158, params.int("target_watts"))
        assertTrue(params["ftp_is_default"]!!.jsonPrimitive.boolean)
    }

    @Test
    fun `every segment carries the rider's volumes`() {
        runner().play(oneMinute)

        val audio = signals.payload("segment_started")["audio"]!!.jsonObject
        assertEquals(0.8, audio["music_volume"]!!.jsonPrimitive.double, 0.0)
        assertEquals(1.0, audio["sfx_volume"]!!.jsonPrimitive.double, 0.0)
    }

    @Test
    fun `effort is off in Just Rides of games that don't declare it`() {
        runner().play(oneMinute)

        assertFalse(signals.payload("segment_started")["effort"]!!.jsonPrimitive.boolean)
    }

    // --- Timer segments ---------------------------------------------------------------------

    @Test
    fun `time left counts gameplay only, and the timer ends the segment at its duration`() {
        val m = runner().play(oneMinute)

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
    fun `a finished plan hands its results to the visit, which sends session_finished`() {
        val m = runner().play(oneMinute)
        seconds(70)
        m.report(score = 640.0, stars = 3, variant = "catch")

        // The runner doesn't send session_finished itself: the visit adds the bests first.
        assertFalse("session_finished" in signals.names)
        assertFalse(m.isRunning)
        val outcome = outcomes.single()
        assertEquals("just-ride:quick:minutes:1", outcome.plan.planId)
        assertEquals(70, outcome.elapsedSec) // the intro card counts
        assertEquals(60, outcome.gameplaySec)
        val played = outcome.results.single()
        assertEquals("quick", played.segment.gameId)
        assertEquals(0, played.startSec)
        assertEquals(60, played.playedSec)
        assertEquals(640.0, played.result.score, 0.0)
        assertEquals(3, played.result.stars)
        assertEquals("catch", played.result.variant)
        assertNull(played.result.won)
        assertEquals(-1.0, m.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `no result within 5 s of segment_ending records a zero-score result`() {
        val m = runner().play(oneMinute)
        seconds(70)

        seconds(4)
        assertTrue(outcomes.isEmpty())
        seconds(1)

        val result = outcomes.single().results.single().result
        assertEquals(0.0, result.score, 0.0)
        assertEquals(0, result.stars)
        assertFalse(result.skipped)
        assertNull(result.won)
        assertFalse(m.isRunning)
    }

    @Test
    fun `a malformed result still advances, recorded as zero`() {
        val m = runner().play(oneMinute)
        seconds(70)
        m.call { segmentFinished("not json") }

        assertEquals(0.0, outcomes.single().results.single().result.score, 0.0)
    }

    // --- Game-ended segments ----------------------------------------------------------------

    @Test
    fun `a game-ended segment runs past its duration and is hard-stopped at 1_5x`() {
        runner().play(SessionRequest.JustRide("racer", JustRideMode.Timed(1)))
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
        val m = runner().play(SessionRequest.JustRide("racer", JustRideMode.Timed(2)))
        seconds(10 + 70)
        m.report(gameId = "racer")

        assertFalse("segment_ending" in signals.names)
        assertEquals(70, outcomes.single().results.single().playedSec)
    }

    @Test
    fun `a rounds Just Ride is ended by the game`() {
        runner().play(SessionRequest.JustRide("quick", JustRideMode.Rounds(3)))

        val segment = signals.payload("segment_started")
        assertEquals("game", segment.str("end_mode"))
        assertEquals(90, segment.int("duration_sec"))
        assertEquals(3, segment["params"]!!.jsonObject.int("rounds"))
    }

    // --- Multi-segment plans ----------------------------------------------------------------

    @Test
    fun `a circuit walks its segments in order, skips advance at once, and effort follows the role`() {
        val m = runner().play(SessionRequest.Circuit("circuit-20"))
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
        val results = outcomes.single().results
        assertEquals((0 until count).toList(), results.map { it.segment.index })
        assertEquals(listOf(false) + List(count - 1) { true }, results.map { it.result.skipped })
    }

    @Test
    fun `each segment's start is recorded on the ride clock`() {
        val m = runner().play(SessionRequest.Circuit("circuit-20"))
        seconds(10 + 180) // warm-up played to its end
        m.report(gameId = "demo")
        seconds(15)
        m.report(gameId = "demo")
        m.call { requestEnd() } // during the third segment's intro card, which never reports
        seconds(5)

        val results = outcomes.single().results
        assertEquals(listOf(0, 190, 205), results.map { it.startSec })
        assertEquals(listOf(180, 5, 0), results.map { it.playedSec })
    }

    @Test
    fun `a plan started later in the visit records starts from the ride's clock, not zero`() {
        seconds(300) // an earlier plan's ride time
        val m = runner().play(oneMinute)
        seconds(70)
        m.report()

        assertEquals(300, outcomes.single().results.single().startSec)
        assertEquals(70, outcomes.single().elapsedSec)
    }

    // --- Pause ------------------------------------------------------------------------------

    @Test
    fun `the rider's pause pauses the ride and freezes the clock`() {
        val m = runner().play(oneMinute)
        seconds(20)
        m.call { requestPause() }
        m.call { requestPause() } // signalled once

        assertEquals(listOf("pause"), ride.calls)
        seconds(30)
        assertEquals(50.0, m.segmentTimeLeftSec, 0.0)

        m.call { requestResume() }
        seconds(10)
        assertEquals(40.0, m.segmentTimeLeftSec, 0.0)
        assertEquals(listOf("pause", "resume"), ride.calls)
        assertEquals(listOf("session_paused", "session_resumed"), pauseSignals())
    }

    @Test
    fun `the ride's freewheel auto-pause pauses the plan until the rider pedals again`() {
        val m = runner().play(oneMinute)
        seconds(20)
        ride.autoPause()
        scope.runCurrent()

        assertEquals("session_paused", signals.names.last())
        val left = m.segmentTimeLeftSec
        seconds(20)
        assertEquals(left, m.segmentTimeLeftSec, 0.0)

        ride.pedalAgain()
        scope.runCurrent()
        assertEquals("session_resumed", signals.names.last())
    }

    @Test
    fun `a rider's pause during an auto-pause holds when pedalling resumes`() {
        val m = runner().play(oneMinute)
        seconds(20)
        ride.autoPause()
        scope.runCurrent()
        m.call { requestPause() }
        ride.pedalAgain()
        seconds(5)

        assertEquals("session_paused", signals.names.last())
        m.call { requestResume() }
        assertEquals("session_resumed", signals.names.last())
    }

    // --- Ending -----------------------------------------------------------------------------

    @Test
    fun `request_end mid-segment asks the game to finish, then finishes`() {
        val m = runner().play(SessionRequest.JustRide("quick", JustRideMode.Timed(2)))
        seconds(10 + 60)
        m.call { requestEnd() }
        assertEquals("segment_ending", signals.names.last())
        assertTrue(outcomes.isEmpty())
        m.report()

        assertEquals(60, outcomes.single().results.single().playedSec)
    }

    @Test
    fun `request_end while paused still finishes after the grace period`() {
        val m = runner().play(SessionRequest.JustRide("quick", JustRideMode.Timed(2)))
        seconds(10 + 80)
        m.call { requestPause() }
        m.call { requestEnd() }
        seconds(5)

        // The paused seconds aren't the plan's.
        assertEquals(90, outcomes.single().elapsedSec)
    }

    @Test
    fun `an open-ended Just Ride waits for request_end after its game ends`() {
        val m = runner().play(SessionRequest.JustRide("quick", JustRideMode.Open))
        seconds(10)
        assertEquals(-1.0, m.segmentTimeLeftSec, 0.0)
        seconds(600)
        assertFalse("segment_ending" in signals.names)

        m.report()
        assertTrue(outcomes.isEmpty())
        m.call { requestEnd() }

        assertEquals("just-ride:quick:open", outcomes.single().plan.planId)
    }

    @Test
    fun `finishNow ends the plan at once with what was played`() {
        val m = runner().play(SessionRequest.JustRide("quick", JustRideMode.Timed(2)))
        seconds(10 + 65)
        m.call { finishNow() }

        assertFalse(m.isRunning)
        assertEquals(emptyList<PlayedSegment>(), outcomes.single().results)
        assertEquals(65, outcomes.single().gameplaySec)
        // Later calls are ignored.
        m.call { requestEnd() }
        m.report()
        seconds(10)
        assertEquals(1, outcomes.size)
    }

    // --- Head tracker -----------------------------------------------------------------------

    @Test
    fun `game modes and recalibration reach the tracker while the plan runs, and nothing after`() {
        val tracker = FakeHeadTracker()
        val m = runner(tracker = TrackerLink(tracker, signals, scope)).play(oneMinute)

        m.call { setTrackerMode("lean_x") }
        assertEquals(listOf("setMode:lean_x", "calibrate:lean_x:force=false"), tracker.calls)
        tracker.finishCalibration()
        m.call { requestCalibration("lean_2d") }
        m.call { requestEnd() }
        seconds(5)
        assertFalse(m.isRunning)
        m.call { setTrackerMode("lean_x") } // from the result card: ignored

        // The plan never resets the session's centre: that's once per visit.
        assertEquals(listOf("setMode:lean_x", "calibrate:lean_x:force=false", "calibrate:lean_2d:force=true"), tracker.calls)
    }

    @Test
    fun `a recalibration pauses the plan until it completes, and the ride keeps recording`() {
        val tracker = FakeHeadTracker()
        val m = runner(tracker = TrackerLink(tracker, signals, scope)).play(oneMinute)
        m.call { setTrackerMode("lean_x") }
        tracker.finishCalibration()
        scope.runCurrent()
        signals.events.clear()
        seconds(15) // the 10 s intro card, then 5 s of play
        assertEquals(55.0, m.segmentTimeLeftSec, 0.0)

        m.call { requestCalibration("lean_x") }
        assertEquals(listOf("session_paused"), pauseSignals())
        seconds(10)
        assertEquals(55.0, m.segmentTimeLeftSec, 0.0)
        assertTrue("pause" !in ride.calls)

        tracker.finishCalibration()
        scope.runCurrent()
        assertEquals(listOf("session_paused", "session_resumed"), pauseSignals())
        seconds(5)
        assertEquals(50.0, m.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `the first calibration holds the intro card, and a calibration that fails still resumes`() {
        val tracker = FakeHeadTracker()
        val m = runner(tracker = TrackerLink(tracker, signals, scope)).play(oneMinute)
        m.call { setTrackerMode("lean_x") } // the visit's first camera mode calibrates at once
        assertEquals("session_paused", pauseSignals().last())
        seconds(30)
        assertEquals(60.0, m.segmentTimeLeftSec, 0.0) // still on the intro card

        tracker.failCalibration() // no face: camera steering is off
        scope.runCurrent()
        assertEquals(listOf("session_paused", "session_resumed"), pauseSignals())
        seconds(15)
        assertEquals(55.0, m.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `a rider's pause outlasts a calibration that ends under it`() {
        val tracker = FakeHeadTracker()
        val m = runner(tracker = TrackerLink(tracker, signals, scope)).play(oneMinute)
        m.call { setTrackerMode("lean_x") }
        m.call { requestPause() }
        tracker.finishCalibration()
        scope.runCurrent()
        assertEquals(listOf("session_paused"), pauseSignals())
        m.call { requestResume() }
        assertEquals(listOf("session_paused", "session_resumed"), pauseSignals())
    }

    // --- Telemetry (#85) ----------------------------------------------------------------------

    @Test
    fun `a reported segment emits game_finish completed`() {
        runner().play(oneMinute.copy(difficulty = Difficulty.HARD))
        seconds(40)
        segmentFinishedWon("quick", stars = 3, won = true)

        val e = finishes().single()
        assertEquals(GameId("quick"), e.game)
        assertEquals(GameDifficulty.HARD, e.difficulty)
        assertEquals(GameOutcome.COMPLETED, e.outcome)
        assertEquals(Won.YES, e.won)
        assertEquals(Stars.THREE, e.stars)
        assertEquals(GamePlayedBucket.LT_1M, e.played)
        assertEquals(GameMusic.GAME_MUSIC, e.music)
        assertEquals("quick/hard", e.props().getValue("game_difficulty"))
    }

    @Test
    fun `won is no for a loss and n-a for a game without a winner`() {
        runner().play(SessionRequest.JustRide("quick", JustRideMode.Rounds(2)))
        segmentFinishedWon("quick", stars = 1, won = false)
        assertEquals(Won.NO, finishes().last().won)
    }

    @Test
    fun `quitting a live segment emits quit once`() {
        val m = runner().play(oneMinute)
        seconds(10 + 45) // past the intro, into gameplay
        m.call { finishNow() }

        val e = finishes().single()
        assertEquals(GameOutcome.QUIT, e.outcome)
        assertEquals(Won.NA, e.won)
        assertEquals(Stars.ZERO, e.stars)
        assertEquals(GamePlayedBucket.LT_1M, e.played)
        assertEquals(1, outcomes.size)
    }

    @Test
    fun `quitting during the intro card emits quit with nothing played`() {
        val m = runner().play(oneMinute)
        seconds(4)
        m.call { finishNow() }

        assertEquals(GameOutcome.QUIT, finishes().single().outcome)
        assertEquals(GamePlayedBucket.LT_1M, finishes().single().played)
    }

    @Test
    fun `a normally finished segment does not also emit quit`() {
        val m = runner().play(oneMinute)
        seconds(70)
        m.report()
        m.call { finishNow() }

        assertEquals(listOf(GameOutcome.COMPLETED), finishes().map { it.outcome })
    }

    @Test
    fun `an open-ended plan waiting for the end does not emit quit when it ends`() {
        val m = runner().play(SessionRequest.JustRide("quick", JustRideMode.Open))
        seconds(30)
        m.report()
        m.call { finishNow() }

        assertEquals(listOf(GameOutcome.COMPLETED), finishes().map { it.outcome })
    }

    @Test
    fun `the last segment of a two-segment plan is quit while the first stays completed`() {
        val m = runner().play(SessionRequest.Custom(listOf(CustomSlot("quick", 60), CustomSlot("quick", 60)), Difficulty.STANDARD))
        seconds(40)
        m.report()
        seconds(20)
        m.call { finishNow() }

        assertEquals(listOf(GameOutcome.COMPLETED, GameOutcome.QUIT), finishes().map { it.outcome })
    }

    @Test
    fun `a skipped segment emits skipped`() {
        val m = runner().play(oneMinute)
        seconds(2)
        m.report(score = 0.0, stars = 0, skipped = true)

        val e = finishes().single()
        assertEquals(GameOutcome.SKIPPED, e.outcome)
        assertEquals(Stars.ZERO, e.stars)
    }

    @Test
    fun `a game that never reports gets no_result after the grace period`() {
        runner().play(oneMinute)
        seconds(10 + 60 + GameSessionManager.GRACE_SEC)

        val e = finishes().single()
        assertEquals(GameOutcome.NO_RESULT, e.outcome)
        assertEquals(Won.NA, e.won)
        assertEquals(Stars.ZERO, e.stars)
    }

    @Test
    fun `an unreadable result emits no_result`() {
        val m = runner().play(oneMinute)
        seconds(20)
        m.segmentFinished("garbage")

        assertEquals(GameOutcome.NO_RESULT, finishes().single().outcome)
    }

    @Test
    fun `own music playing reads own_music, and the switch off with nothing playing reads off`() {
        ownTrack = true
        val m = runner().play(oneMinute)
        seconds(20)
        m.report()
        assertEquals(GameMusic.OWN_MUSIC, finishes().single().music)

        ownTrack = false
        gameMusicOn = false
        val m2 = runner().play(oneMinute)
        seconds(20)
        m2.report()
        assertEquals(GameMusic.OFF, finishes().last().music)
    }

    @Test
    fun `an unknown game id passes through as its catalog string`() {
        val m = runner().play(oneMinute)
        seconds(20)
        m.report(gameId = "mystery") // the result's id is replaced by the segment's

        assertEquals(GameId("quick"), finishes().single().game)
    }

    @Test
    fun `a throwing telemetry never reaches the plan`() {
        val boom = object : dev.digitalducktape.openride.core.telemetry.Telemetry {
            override fun track(event: dev.digitalducktape.openride.core.telemetry.TelemetryEvent) = error("boom")
        }
        val m = GameSessionManager(signals, scope, random = Random(7), telemetry = boom)
        m.play(oneMinute)
        seconds(20)
        m.report()

        assertEquals(1, outcomes.size)
    }

    private fun segmentFinishedWon(gameId: String, stars: Int, won: Boolean) {
        lastRunner!!.segmentFinished("""{"game_id":"$gameId","score":10,"stars":$stars,"won":$won,"skipped":false,"stats":{}}""")
        scope.runCurrent()
    }
}
