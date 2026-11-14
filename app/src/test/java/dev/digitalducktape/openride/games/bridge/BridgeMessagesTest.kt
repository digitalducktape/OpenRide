package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.camera.LeanSensitivity
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

        assertEquals(setOf("kind", "plan_id", "difficulty", "total_sec", "segments", "rider_id", "rider_name"), json.keys)
        assertEquals("just_ride", json["kind"]!!.jsonPrimitive.content)
        assertEquals("standard", json["difficulty"]!!.jsonPrimitive.content)
        val segment = json["segments"]!!.jsonArray.single().jsonObject
        assertEquals(setOf("game_id", "role", "duration_sec"), segment.keys)
        assertEquals("free", segment["role"]!!.jsonPrimitive.content)
        assertEquals(-1, segment["duration_sec"]!!.jsonPrimitive.content.toInt())
    }

    @Test
    fun `the rider's name is an optional plan key`() {
        val plan = SessionPlanMessage(SessionKind.JUST_RIDE, "p", Difficulty.STANDARD, -1, emptyList(), riderId = 3L, riderName = "Ed")

        assertEquals("Ed", parse(BridgeMessages.encode(plan))["rider_name"]!!.jsonPrimitive.content)
        assertEquals(JsonNull, parse(BridgeMessages.encode(plan.copy(riderName = null)))["rider_name"])
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
            audio = AudioSettings(musicVolume = 0.8, sfxVolume = 1.0),
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
        assertEquals(setOf("game_id", "score", "stars", "won", "skipped", "stats", "variant"), encodedResult.keys)
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

    // --- v1.1: the Games hub ----------------------------------------------------------------

    @Test
    fun `a result's variant is parsed`() {
        val result = BridgeMessages.parseResult("""{"game_id":"dodge_ball","score":10,"stars":1,"variant":"catch"}""")!!

        assertEquals("catch", result.variant)
        assertEquals("", BridgeMessages.parseResult("""{"game_id":"dodge_ball"}""")!!.variant)
        assertEquals("", BridgeMessages.parseResult("""{"game_id":"dodge_ball","variant":null}""")!!.variant)
    }

    @Test
    fun `visit keys on session_started appear only in a visit`() {
        val plan = SessionPlanMessage(SessionKind.JUST_RIDE, "p", Difficulty.STANDARD, 70, emptyList())
        val visit = plan.copy(visitId = "v-1", planIndex = 2, calibrated = "lean_x")

        val json = parse(BridgeMessages.encode(visit))

        assertEquals("v-1", json["visit_id"]!!.jsonPrimitive.content)
        assertEquals(2, json["plan_index"]!!.jsonPrimitive.content.toInt())
        assertEquals("lean_x", json["calibrated"]!!.jsonPrimitive.content)
        assertFalse("visit_id" in parse(BridgeMessages.encode(plan)).keys)
    }

    @Test
    fun `visit keys on session_finished appear only in a visit`() {
        val summary = SessionSummary(null, emptyList(), SessionTotals(0.0, 0, 0, 0), JsonObject(emptyMap()))
        val visit = summary.copy(visitId = "v-1", planIndex = 0, planId = "circuit-20", difficulty = Difficulty.HARD)

        val json = parse(BridgeMessages.encode(visit))

        assertEquals(
            setOf("ride_id", "results", "totals", "bests", "visit_id", "plan_index", "plan_id", "difficulty"),
            json.keys,
        )
        assertEquals("hard", json["difficulty"]!!.jsonPrimitive.content)
        assertEquals(JsonNull, json["ride_id"])
    }

    private fun hubState() = HubStateMessage(
        visitId = "v-1760890000000",
        phase = HubPhase.HUB,
        rider = HubRider(id = 3, name = "Ed", avatarPng = "/cache/games/avatar_3.png", avatarColor = "#4F7CFF", ftpWatts = 150, ftpIsDefault = true),
        settings = HubSettings(cameraGames = true, musicVolume = 0.8, sfxVolume = 1.0),
        audio = AudioSettings(musicVolume = 0.8, sfxVolume = 1.0),
        camera = HubCamera(permission = CameraPermission.GRANTED, available = true, calibrated = "lean_x", sameDayExtremes = true),
        catalog = listOf(
            HubCatalogGame(
                id = "kart_race", title = "Kart Race", supports = listOf("minutes", "open"), minSec = 300, maxSec = 3600,
                minRounds = 1, maxRounds = 10, roundSec = 60, roles = emptyList(), usesCamera = true,
                minuteSteps = listOf(5, 10, 15, 20, 30, 45, 60), circuitRole = SegmentRole.FREE,
            ),
        ),
        circuits = listOf(HubCircuit("circuit-20", 20, 1120, listOf(HubCircuitSlot("cadence_karaoke", SegmentRole.WARMUP, 180)))),
        bests = HubBests(
            games = listOf(HubGameBest("dodge_ball", "just-ride:dodge_ball:minutes:20", Difficulty.STANDARD, "", 5400.0, 2, 4)),
            plans = listOf(HubPlanBest("circuit-20", Difficulty.STANDARD, 9100.0, 21)),
        ),
        visit = HubVisit(
            recording = true, rideSec = 754, gameplaySec = 690,
            plans = listOf(HubVisitPlan("just-ride:kart_race:minutes:10", Difficulty.STANDARD, 812.0, 2, listOf("kart_race"))),
        ),
    )

    @Test
    fun `hub_state uses the contract keys at every level`() {
        val json = parse(BridgeMessages.encode(hubState()))

        assertEquals(
            setOf("hub_version", "visit_id", "phase", "rider", "settings", "audio", "camera", "catalog", "circuits", "bests", "visit"),
            json.keys,
        )
        assertEquals(1, json["hub_version"]!!.jsonPrimitive.content.toInt())
        assertEquals("hub", json["phase"]!!.jsonPrimitive.content)
        assertEquals(
            setOf("id", "name", "avatar_png", "avatar_color", "ftp_watts", "ftp_is_default"),
            json["rider"]!!.jsonObject.keys,
        )
        assertEquals(setOf("camera_games", "game_music", "music_volume", "sfx_volume", "lean_sensitivity"), json["settings"]!!.jsonObject.keys)
        assertEquals(setOf("music", "music_volume", "sfx_volume"), json["audio"]!!.jsonObject.keys)
        val camera = json["camera"]!!.jsonObject
        assertEquals(setOf("permission", "available", "calibrated", "same_day_extremes"), camera.keys)
        assertEquals("granted", camera["permission"]!!.jsonPrimitive.content)
        val game = json["catalog"]!!.jsonArray.single().jsonObject
        assertEquals(
            setOf(
                "id", "title", "supports", "min_sec", "max_sec", "min_rounds", "max_rounds", "round_sec", "roles",
                "uses_camera", "minute_steps", "circuit_role",
            ),
            game.keys,
        )
        assertEquals("free", game["circuit_role"]!!.jsonPrimitive.content)
        val circuit = json["circuits"]!!.jsonArray.single().jsonObject
        assertEquals(setOf("id", "minutes", "total_sec", "slots"), circuit.keys)
        assertEquals(setOf("game_id", "role", "duration_sec"), circuit["slots"]!!.jsonArray.single().jsonObject.keys)
        val bests = json["bests"]!!.jsonObject
        assertEquals(
            setOf("game_id", "plan_id", "difficulty", "variant", "score", "stars", "plays"),
            bests["games"]!!.jsonArray.single().jsonObject.keys,
        )
        assertEquals(setOf("plan_id", "difficulty", "score", "stars"), bests["plans"]!!.jsonArray.single().jsonObject.keys)
        val visit = json["visit"]!!.jsonObject
        assertEquals(setOf("recording", "ride_sec", "gameplay_sec", "plans"), visit.keys)
        assertEquals(
            setOf("plan_id", "difficulty", "score", "stars", "game_ids"),
            visit["plans"]!!.jsonArray.single().jsonObject.keys,
        )
    }

    @Test
    fun `hub_state round-trips, and a guest rider has a null id`() {
        val state = hubState().copy(rider = HubRider(null, "", null, "#808080", 150, true))

        assertEquals(state, BridgeMessages.decodeHubState(BridgeMessages.encode(state)))
        assertEquals(JsonNull, parse(BridgeMessages.encode(state))["rider"]!!.jsonObject["id"])
    }

    @Test
    fun `plan_rejected carries the request as sent and the reason word`() {
        val request = buildJsonObject { put("kind", "just_ride"); put("game_id", "nope") }
        val message = PlanRejectedMessage(request, PlanRejectReason.UNKNOWN_GAME)

        val json = parse(BridgeMessages.encode(message))

        assertEquals(setOf("request", "reason"), json.keys)
        assertEquals(request, json["request"])
        assertEquals("unknown_game", json["reason"]!!.jsonPrimitive.content)
        assertEquals(
            listOf("unknown_game", "unsupported_mode", "camera_unavailable", "busy", "empty_circuit", "too_long"),
            PlanRejectReason.entries.map { parse(BridgeMessages.encode(PlanRejectedMessage(request, it)))["reason"]!!.jsonPrimitive.content },
        )
        assertEquals(message, BridgeMessages.decodePlanRejected(BridgeMessages.encode(message)))
    }

    @Test
    fun `visit_ended uses the contract keys`() {
        val message = VisitEndedMessage(visitId = "v-1", rideId = 42, saved = true, discardedReason = "", next = "app", reason = "exit")

        val json = parse(BridgeMessages.encode(message))

        assertEquals(setOf("visit_id", "ride_id", "saved", "discarded_reason", "next", "reason"), json.keys)
        assertEquals(42, json["ride_id"]!!.jsonPrimitive.content.toInt())
        assertEquals(message, BridgeMessages.decodeVisitEnded(BridgeMessages.encode(message)))
        assertEquals(JsonNull, parse(BridgeMessages.encode(message.copy(rideId = null)))["ride_id"])
    }

    @Test
    fun `plan requests parse every kind, with GDScript floats as ints`() {
        assertEquals(
            PlanRequestMessage(kind = PlanRequestKind.JUST_RIDE, gameId = "kart_race", mode = "minutes", length = 10, difficulty = Difficulty.STANDARD),
            BridgeMessages.parsePlanRequest("""{"kind":"just_ride","game_id":"kart_race","mode":"minutes","length":10.0,"difficulty":"standard"}"""),
        )
        assertEquals(
            PlanRequestMessage(kind = PlanRequestKind.CIRCUIT, presetId = "circuit-30", difficulty = Difficulty.HARD),
            BridgeMessages.parsePlanRequest("""{"kind":"circuit","preset_id":"circuit-30","difficulty":"hard"}"""),
        )
        assertEquals(
            PlanRequestMessage(
                kind = PlanRequestKind.CUSTOM,
                difficulty = Difficulty.EASY,
                slots = listOf(PlanRequestSlot("cadence_karaoke", 180), PlanRequestSlot("kart_race", 600)),
            ),
            BridgeMessages.parsePlanRequest(
                """{"kind":"custom","difficulty":"easy","slots":[{"game_id":"cadence_karaoke","duration_sec":180.0},{"game_id":"kart_race","duration_sec":600}]}""",
            ),
        )
    }

    @Test
    fun `plan requests ignore unknown keys and default what's missing`() {
        val request = BridgeMessages.parsePlanRequest("""{"kind":"just_ride","game_id":"dodge_ball","mode":"open","future":1}""")!!

        assertEquals(Difficulty.STANDARD, request.difficulty)
        assertEquals(0, request.length)
        assertEquals(emptyList<PlanRequestSlot>(), request.slots)
        assertEquals("", request.presetId)
    }

    @Test
    fun `unreadable plan requests parse to null`() {
        assertNull(BridgeMessages.parsePlanRequest("nope"))
        assertNull(BridgeMessages.parsePlanRequest("""{"game_id":"x"}"""))
        assertNull(BridgeMessages.parsePlanRequest("""{"kind":"teleport"}"""))
    }

    @Test
    fun `now playing uses the contract keys, and nothing playing is an empty object`() {
        val json = parse(BridgeMessages.encode(NowPlayingMessage("Song", "Band", "/cache/a.png", true, false, true)))
        assertEquals(setOf("title", "artist", "art", "playing", "can_previous", "can_next"), json.keys)
        assertEquals("{}", BridgeMessages.encode(null as NowPlayingMessage?))
    }

    @Test
    fun `settings updates parse by key, and anything else is null`() {
        assertEquals(SettingUpdate.CameraGames(false), BridgeMessages.parseSetting("camera_games", "false"))
        assertEquals(SettingUpdate.GameMusic(false), BridgeMessages.parseSetting("game_music", "false"))
        assertEquals(SettingUpdate.MusicVolume(0.5), BridgeMessages.parseSetting("music_volume", "0.5"))
        assertEquals(SettingUpdate.SfxVolume(1.0), BridgeMessages.parseSetting("sfx_volume", "1"))
        assertEquals(SettingUpdate.SfxVolume(1.0), BridgeMessages.parseSetting("sfx_volume", "7.0")) // clamped
        assertNull(BridgeMessages.parseSetting("music", "\"off\"")) // the old Game music switch, gone
        assertNull(BridgeMessages.parseSetting("camera_games", "\"yes\""))
        assertNull(BridgeMessages.parseSetting("brightness", "1"))
        assertNull(BridgeMessages.parseSetting("music_volume", "not json"))
    }

    @Test
    fun `lean sensitivity parses its three words only`() {
        for (level in LeanSensitivity.entries) {
            assertEquals(SettingUpdate.LeanSensitivity(level), BridgeMessages.parseSetting("lean_sensitivity", "\"${level.code}\""))
        }
        assertNull(BridgeMessages.parseSetting("lean_sensitivity", "\"ludicrous\""))
        assertNull(BridgeMessages.parseSetting("lean_sensitivity", "2"))
        assertNull(BridgeMessages.parseSetting("lean_sensitivity", "true"))
    }

    @Test
    fun `hub settings default the lean sensitivity, so an older payload still reads`() {
        assertEquals("normal", HubSettings(cameraGames = true, musicVolume = 0.8, sfxVolume = 1.0).leanSensitivity)
    }
}
