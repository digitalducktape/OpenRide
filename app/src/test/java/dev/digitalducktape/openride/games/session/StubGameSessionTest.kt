package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.bridge.EndMode
import dev.digitalducktape.openride.games.bridge.GameSignals
import dev.digitalducktape.openride.games.bridge.PlanSegment
import dev.digitalducktape.openride.games.bridge.SegmentRole
import dev.digitalducktape.openride.games.bridge.SessionKind
import dev.digitalducktape.openride.games.bridge.SessionPlanMessage
import dev.digitalducktape.openride.games.bridge.TrackerMode
import kotlin.random.Random
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Records Kotlin → Godot signals in order. */
private class RecordingSignals : GameSignals {
    val events = mutableListOf<Pair<String, String?>>()

    val names get() = events.map { it.first }

    fun payload(name: String): JsonObject =
        Json.parseToJsonElement(events.last { it.first == name }.second!!).jsonObject

    override fun sessionStarted(planJson: String) { events += "session_started" to planJson }
    override fun segmentStarted(segmentJson: String) { events += "segment_started" to segmentJson }
    override fun segmentEnding() { events += "segment_ending" to null }
    override fun sessionPaused() { events += "session_paused" to null }
    override fun sessionResumed() { events += "session_resumed" to null }
    override fun calibrationProgress(step: String, fraction: Double) { events += "calibration_progress" to "$step:$fraction" }
    override fun sessionFinished(summaryJson: String) { events += "session_finished" to summaryJson }
}

@OptIn(ExperimentalCoroutinesApi::class)
class StubGameSessionTest {
    private val scope = TestScope()
    private val signals = RecordingSignals()
    private var exits = 0

    private fun session(plan: SessionPlanMessage = StubGameSession.placeholderJustRide()) =
        StubGameSession(signals, scope, plan, random = Random(7), onExit = { exits++ })

    private fun result(stars: Int = 2, skipped: Boolean = false) =
        """{"game_id":"placeholder","score":40,"stars":$stars,"won":null,"skipped":$skipped,"stats":{"effort_avg":1.0}}"""

    private fun timedPlan(vararg durations: Int) = SessionPlanMessage(
        kind = SessionKind.CIRCUIT,
        planId = "test",
        difficulty = Difficulty.EASY,
        totalSec = durations.sum(),
        segments = durations.map { PlanSegment("placeholder", SegmentRole.WORK, it) },
    )

    @Test
    fun `nothing is sent until the game is ready`() {
        session()
        scope.advanceTimeBy(5_000)

        assertTrue(signals.events.isEmpty())
    }

    @Test
    fun `the full lifecycle round-trips for the open-ended stub plan`() {
        val session = session()

        session.onGameReady()
        scope.runCurrent()
        assertEquals(listOf("session_started", "segment_started"), signals.names)
        val plan = signals.payload("session_started")
        assertEquals("just_ride", plan["kind"]!!.jsonPrimitive.content)
        assertEquals("placeholder", plan["segments"]!!.jsonArray.single().jsonObject["game_id"]!!.jsonPrimitive.content)
        val segment = signals.payload("segment_started")
        assertEquals(-1, segment["duration_sec"]!!.jsonPrimitive.int)
        assertEquals("game", segment["end_mode"]!!.jsonPrimitive.content)
        assertEquals(10, segment["intro_sec"]!!.jsonPrimitive.int)
        assertEquals("free", segment["role"]!!.jsonPrimitive.content)

        session.onRequestPause()
        scope.runCurrent()
        session.onRequestResume()
        scope.runCurrent()

        scope.advanceTimeBy(30_000)
        session.onSegmentFinished(result())
        scope.runCurrent()
        // Open-ended: the session waits for the rider to end it.
        assertFalse("session_finished" in signals.names)

        session.onRequestEnd()
        scope.runCurrent()
        session.onRequestExit()
        scope.runCurrent()

        assertEquals(
            listOf(
                "session_started", "segment_started", "session_paused", "session_resumed",
                "session_finished",
            ),
            signals.names,
        )
        val summary = signals.payload("session_finished")
        val results = summary["results"]!!.jsonArray
        assertEquals(1, results.size)
        assertEquals(2, results.single().jsonObject["stars"]!!.jsonPrimitive.int)
        assertEquals(2, summary["totals"]!!.jsonObject["stars"]!!.jsonPrimitive.int)
        assertEquals(1, exits)
    }

    @Test
    fun `segment time left counts gameplay only, after the intro`() {
        val session = session(timedPlan(60))
        assertEquals(-1.0, session.segmentTimeLeftSec, 0.0)

        session.onGameReady()
        scope.runCurrent()
        assertEquals(60.0, session.segmentTimeLeftSec, 0.0)

        scope.advanceTimeBy(10_001) // the intro card
        assertEquals(60.0, session.segmentTimeLeftSec, 0.0)

        scope.advanceTimeBy(15_000)
        assertEquals(45.0, session.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `open-ended segments report -1 time left`() {
        val session = session()
        session.onGameReady()
        scope.advanceTimeBy(20_001)

        assertEquals(-1.0, session.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `pausing freezes the clock`() {
        val session = session(timedPlan(60))
        session.onGameReady()
        scope.advanceTimeBy(20_001) // intro + 10 s of play
        assertEquals(50.0, session.segmentTimeLeftSec, 0.0)

        session.onRequestPause()
        scope.advanceTimeBy(30_000)
        assertEquals(50.0, session.segmentTimeLeftSec, 0.0)

        session.onRequestResume()
        scope.advanceTimeBy(5_000)
        assertEquals(45.0, session.segmentTimeLeftSec, 0.0)
    }

    @Test
    fun `pause and resume are only signalled on a change`() {
        val session = session()
        session.onGameReady()
        scope.runCurrent()

        session.onRequestResume()
        session.onRequestPause()
        session.onRequestPause()
        session.onRequestResume()
        scope.runCurrent()

        assertEquals(listOf("session_started", "segment_started", "session_paused", "session_resumed"), signals.names)
    }

    @Test
    fun `a timed segment ends with segment_ending, then the next segment starts on its result`() {
        val session = session(timedPlan(30, 45))
        session.onGameReady()
        scope.advanceTimeBy(40_001) // 10 s intro + 30 s play

        assertEquals("segment_ending", signals.names.last())

        session.onSegmentFinished(result())
        scope.runCurrent()

        assertEquals("segment_started", signals.names.last())
        val second = signals.payload("segment_started")
        assertEquals(1, second["index"]!!.jsonPrimitive.int)
        assertEquals(2, second["count"]!!.jsonPrimitive.int)
        assertEquals(45, second["duration_sec"]!!.jsonPrimitive.int)
        assertEquals("timer", second["end_mode"]!!.jsonPrimitive.content)
    }

    @Test
    fun `a timed plan finishes by itself after the last result`() {
        val session = session(timedPlan(30))
        session.onGameReady()
        scope.advanceTimeBy(40_001)
        session.onSegmentFinished(result(stars = 3))
        scope.runCurrent()

        assertEquals("session_finished", signals.names.last())
        assertEquals(3, signals.payload("session_finished")["totals"]!!.jsonObject["stars"]!!.jsonPrimitive.int)
    }

    @Test
    fun `no result within 5 s of segment_ending records a zero-score result`() {
        val session = session(timedPlan(30))
        session.onGameReady()
        scope.advanceTimeBy(40_001)
        assertEquals("segment_ending", signals.names.last())

        scope.advanceTimeBy(5_000)

        assertEquals("session_finished", signals.names.last())
        val recorded = signals.payload("session_finished")["results"]!!.jsonArray.single().jsonObject
        assertEquals(0.0, recorded["score"]!!.jsonPrimitive.content.toDouble(), 0.0)
        assertEquals(0, recorded["stars"]!!.jsonPrimitive.int)
        assertEquals("placeholder", recorded["game_id"]!!.jsonPrimitive.content)
    }

    @Test
    fun `request_end mid-segment asks the game to finish, then finishes the session`() {
        val session = session(timedPlan(60, 60))
        session.onGameReady()
        scope.advanceTimeBy(20_001)

        session.onRequestEnd()
        scope.runCurrent()
        assertEquals("segment_ending", signals.names.last())

        session.onSegmentFinished(result())
        scope.runCurrent()

        // The remaining segment is not started: the rider ended the session.
        assertEquals(1, signals.names.count { it == "segment_started" })
        assertEquals("session_finished", signals.names.last())
    }

    @Test
    fun `a skip during the intro card advances to the next segment`() {
        val session = session(timedPlan(60, 60))
        session.onGameReady()
        scope.advanceTimeBy(3_000)

        session.onSegmentFinished(result(stars = 0, skipped = true))
        scope.runCurrent()

        assertEquals(1, signals.payload("segment_started")["index"]!!.jsonPrimitive.int)
    }

    @Test
    fun `a game-ended segment is hard-stopped at 1_5x its duration`() {
        val plan = timedPlan(40).copy(kind = SessionKind.JUST_RIDE)
        val session = StubGameSession(
            signals, scope, plan, random = Random(7), onExit = { exits++ }, endModeFor = { EndMode.GAME },
        )
        session.onGameReady()
        scope.advanceTimeBy(10_000 + 40_001)
        assertFalse("segment_ending" in signals.names)

        scope.advanceTimeBy(20_000)
        assertEquals("segment_ending", signals.names.last())
    }

    @Test
    fun `a malformed result still advances, recorded as zero`() {
        val session = session(timedPlan(30))
        session.onGameReady()
        scope.advanceTimeBy(40_001)

        session.onSegmentFinished("{oops")
        scope.runCurrent()

        assertEquals("session_finished", signals.names.last())
        assertEquals(0, signals.payload("session_finished")["totals"]!!.jsonObject["stars"]!!.jsonPrimitive.int)
    }

    @Test
    fun `game ready twice starts the session once`() {
        val session = session()
        session.onGameReady()
        session.onGameReady()
        scope.runCurrent()

        assertEquals(1, signals.names.count { it == "session_started" })
    }

    @Test
    fun `request_exit before the summary finishes the session first`() {
        val session = session()
        session.onGameReady()
        scope.runCurrent()

        session.onRequestExit()
        scope.runCurrent()

        assertEquals("session_finished", signals.names.last())
        assertEquals(1, exits)
    }

    @Test
    fun `tracker mode and calibration requests are recorded`() {
        val session = session()
        session.onGameReady()
        session.onSetTrackerMode("lean_2d")
        session.onRequestCalibration("lean_x")
        session.onSetTrackerMode("bogus")
        scope.runCurrent()

        assertEquals(TrackerMode.LEAN_2D, session.trackerMode)
    }
}
