package dev.digitalducktape.openride.games.bridge

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** JSON payloads of the v1 Bridge contract: exact key names and tolerant result parsing. */
class BridgeMessagesTest {
    private fun parse(json: String): JsonObject = Json.parseToJsonElement(json).jsonObject

    @Test
    fun `session plan uses the contract keys`() {
        val plan = SessionPlanMessage(
            kind = SessionKind.JUST_RIDE,
            planId = "just-ride:placeholder",
            difficulty = Difficulty.STANDARD,
            totalSec = -1,
            segments = listOf(PlanSegment(gameId = "placeholder", role = SegmentRole.FREE, durationSec = -1)),
        )

        val json = parse(BridgeMessages.encode(plan))

        assertEquals(setOf("kind", "plan_id", "difficulty", "total_sec", "segments"), json.keys)
        assertEquals("just_ride", json["kind"]!!.jsonPrimitive.content)
        assertEquals("standard", json["difficulty"]!!.jsonPrimitive.content)
        val segment = json["segments"]!!.jsonArray.single().jsonObject
        assertEquals(setOf("game_id", "role", "duration_sec"), segment.keys)
        assertEquals("free", segment["role"]!!.jsonPrimitive.content)
        assertEquals(-1, segment["duration_sec"]!!.jsonPrimitive.content.toInt())
    }

    @Test
    fun `circuit kind and every role and difficulty encode as the contract words`() {
        val roles = SegmentRole.entries.map {
            parse(BridgeMessages.encode(PlanSegment("g", it, 60)))["role"]!!.jsonPrimitive.content
        }
        assertEquals(listOf("warmup", "work", "recovery", "cooldown", "free"), roles)

        val difficulties = Difficulty.entries.map {
            parse(BridgeMessages.encode(SessionPlanMessage(SessionKind.CIRCUIT, "circuit-20", it, 1120, emptyList())))
        }
        assertEquals(listOf("easy", "standard", "hard"), difficulties.map { it["difficulty"]!!.jsonPrimitive.content })
        assertEquals("circuit", difficulties.first()["kind"]!!.jsonPrimitive.content)
    }

    @Test
    fun `segment start uses the contract keys, including audio and params`() {
        val segment = SegmentStartMessage(
            index = 0,
            count = 1,
            gameId = "placeholder",
            durationSec = 90,
            introSec = 10,
            endMode = EndMode.TIMER,
            role = SegmentRole.WORK,
            difficulty = Difficulty.HARD,
            effort = true,
            seed = 1234,
            audio = AudioSettings(music = false, musicVolume = 0.8, sfxVolume = 1.0),
            params = buildJsonObject { put("target_watts", 250) },
        )

        val json = parse(BridgeMessages.encode(segment))

        assertEquals(
            setOf(
                "index", "count", "game_id", "duration_sec", "intro_sec", "end_mode", "role",
                "difficulty", "effort", "seed", "audio", "params",
            ),
            json.keys,
        )
        assertEquals("timer", json["end_mode"]!!.jsonPrimitive.content)
        assertEquals(setOf("music", "music_volume", "sfx_volume"), json["audio"]!!.jsonObject.keys)
        assertEquals("false", json["audio"]!!.jsonObject["music"]!!.jsonPrimitive.content)
        assertEquals(250, json["params"]!!.jsonObject["target_watts"]!!.jsonPrimitive.content.toInt())
        assertEquals("game", parse(BridgeMessages.encode(segment.copy(endMode = EndMode.GAME)))["end_mode"]!!.jsonPrimitive.content)
    }

    @Test
    fun `parses a full segment result`() {
        val result = BridgeMessages.parseResult(
            """{"game_id":"dodge_ball","score":1520,"stars":2,"won":true,"skipped":false,
               "stats":{"effort_avg":1.27,"hits":4}}""",
        )!!

        assertEquals("dodge_ball", result.gameId)
        assertEquals(1520.0, result.score, 0.0)
        assertEquals(2, result.stars)
        assertEquals(true, result.won)
        assertFalse(result.skipped)
        assertEquals(1.27, result.stats["effort_avg"]!!.jsonPrimitive.content.toDouble(), 0.0)
        assertEquals(4, result.stats["hits"]!!.jsonPrimitive.content.toInt())
    }

    @Test
    fun `accepts GDScript floats for whole numbers and a null won`() {
        // Godot's JSON.stringify writes floats as 3.0, and a game without a winner sends null.
        val result = BridgeMessages.parseResult("""{"game_id":"safe_cracker","score":12.0,"stars":3.0,"won":null}""")!!

        assertEquals(12.0, result.score, 0.0)
        assertEquals(3, result.stars)
        assertNull(result.won)
    }

    @Test
    fun `missing optional fields default, stars are clamped to 0-3`() {
        val result = BridgeMessages.parseResult("""{"game_id":"tug_of_war","skipped":true,"stars":7}""")!!

        assertEquals(0.0, result.score, 0.0)
        assertEquals(3, result.stars)
        assertNull(result.won)
        assertTrue(result.skipped)
        assertEquals(JsonObject(emptyMap()), result.stats)
    }

    @Test
    fun `malformed results parse to null`() {
        assertNull(BridgeMessages.parseResult("not json"))
        assertNull(BridgeMessages.parseResult("[1,2]"))
        assertNull(BridgeMessages.parseResult("""{"score":5}"""))
    }

    @Test
    fun `result round-trips inside the session summary`() {
        val result = SegmentResult(gameId = "placeholder", score = 10.0, stars = 1, won = null, skipped = false, stats = JsonObject(emptyMap()))
        val summary = SessionSummary(
            rideId = null,
            results = listOf(result),
            totals = SessionTotals(score = 10.0, stars = 1, segments = 1, elapsedSec = 75),
            bests = JsonObject(emptyMap()),
        )

        val json = parse(BridgeMessages.encode(summary))

        assertEquals(setOf("ride_id", "results", "totals", "bests"), json.keys)
        assertEquals(JsonNull, json["ride_id"])
        val encodedResult = json["results"]!!.jsonArray.single().jsonObject
        assertEquals(setOf("game_id", "score", "stars", "won", "skipped", "stats"), encodedResult.keys)
        assertEquals(JsonNull, encodedResult["won"])
        assertEquals(JsonPrimitive(75), json["totals"]!!.jsonObject["elapsed_sec"])
        assertEquals(result, BridgeMessages.parseResult(encodedResult.toString()))
    }

    @Test
    fun `tracker and calibration modes parse from the contract words`() {
        assertEquals(TrackerMode.OFF, TrackerMode.fromWire("off"))
        assertEquals(TrackerMode.LEAN_X, TrackerMode.fromWire("lean_x"))
        assertEquals(TrackerMode.LEAN_2D, TrackerMode.fromWire("lean_2d"))
        assertEquals(TrackerMode.LEAN_STAND, TrackerMode.fromWire("lean_stand"))
        assertNull(TrackerMode.fromWire("sideways"))

        assertEquals(CalibrationMode.LEAN_X, CalibrationMode.fromWire("lean_x"))
        assertEquals(CalibrationMode.LEAN_2D, CalibrationMode.fromWire("lean_2d"))
        assertNull(CalibrationMode.fromWire("off"))
    }
}
