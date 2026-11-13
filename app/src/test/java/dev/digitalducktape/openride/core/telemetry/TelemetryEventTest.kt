package dev.digitalducktape.openride.core.telemetry

import kotlin.reflect.KClass
import kotlin.reflect.full.primaryConstructor
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TelemetryEventTest {
    private val channel = ChannelName.of("@kaleigh")

    /** One instance of every event. [allEventsCovered] fails when a new event is not added here. */
    private val all: List<TelemetryEvent> = listOf(
        AppOpen(Tablet.BIKE, Firmware.RQ_250113_A, ProfilesBucket.TWO, Flavor.REAL),
        ScreenView(Screen.HOME),
        TelemetryEnabled(ConsentSource.FIRST_RUN),
        ProfileCreated(hasPhoto = true),
        RideStart(RideType.JUST_RIDE, RideEntry.HOME_QUICK_START, route = false),
        RideEnd(
            RideType.JUST_RIDE, DurationBucket.M15_30, RideOutcome.SAVED, DiscardReason.NONE,
            HrState.CONNECTED, HrDropsBucket.ONE, SensorState.OK, RideMusic.OWN_MUSIC, true,
        ),
        ClassStart(channel, ChannelSource.CURATED, ClassCategory.SCENIC, ClassSource.CLASSES),
        ClassEnd(channel, ChannelSource.CUSTOM, DurationBucket.M30_45, DurationBucket.M5_15, false, MuteState.DURING),
        ClassPlayerError(YouTubeErrorCode(150), channel),
        ContentSourceAdded(ChannelName.PLAYLIST, SourceKind.PLAYLIST),
        GamesPlanStart(PlanMode.CIRCUIT, GameDifficulty.STANDARD, GameMusic.GAME_MUSIC),
        GameFinish(GameId("balloon_pump"), GameDifficulty.HARD, GameOutcome.COMPLETED, Won.NA, Stars.THREE, GamePlayedBucket.M1_3, GameMusic.OFF),
        GamesVisitEnd(DurationBucket.LT_5M, GamesPlayedBucket.FIVE_PLUS, VisitEndReason.IDLE, VisitMusic.MIXED, false),
        GameMusicSwitch(OnOff.OFF),
        HeadCalibration(CalibrationResult.SUCCESS, CalibrationMode.LEAN_2D),
        MusicPlayerOpen(MusicSurface.TOP_BAR),
        MusicAppChosen(MusicApp.APPLE_MUSIC),
        NotificationAccess(GrantResult.GRANTED),
        HrStrapSelected(HrSelectResult.BT_OFF),
        BikeSensor(BikeSensorState.CONNECTED, SensorPath.POLLING),
        CameraPermission(GrantResult.DENIED),
        BackupExport(SuccessResult.SUCCESS),
        BackupRestore(RestoreResult.BAD_FILE),
        AutoBackupFailed,
        HistoryImport(ImportResult.SUCCESS, ImportedBucket.N1_10, duplicates = true),
        RideDeleted(DeletedRideType.IMPORTED),
        RideExport(ExportFormat.CSV_HISTORY),
        GpxImport(SuccessResult.FAILED, GpxPointsBucket.K2_10K),
        GpxRouteCleared,
        UpdatePrompt(UpdateAction.INSTALL_TAPPED),
        UpdateFailed(UpdateStage.DOWNLOAD),
        AboutLink(AboutTarget.COFFEE),
    )

    @Test
    fun allEventsCovered() {
        assertEquals(TelemetryEvent::class.sealedSubclasses.size, all.size)
        assertEquals(
            TelemetryEvent::class.sealedSubclasses.toSet(),
            all.map { it::class }.toSet(),
        )
    }

    @Test
    fun everyPropValueIsAString() {
        all.forEach { e ->
            val props: Map<String, Any?> = e.props()
            assertTrue(e.name, props.values.all { it is String && it.isNotEmpty() })
            assertTrue(e.name, e.name.matches(Regex("[a-z_]+")))
            assertTrue(e.name, props.keys.all { it.matches(Regex("[a-z_]+")) })
        }
    }

    @Test
    fun onlyChannelIsFreeForm() {
        val allowed: Set<KClass<*>> = setOf(Boolean::class, GameId::class, YouTubeErrorCode::class, ChannelName::class)
        val channelHosts = setOf(ClassStart::class, ClassEnd::class, ClassPlayerError::class, ContentSourceAdded::class)
        TelemetryEvent::class.sealedSubclasses.forEach { k ->
            val params = k.primaryConstructor?.parameters ?: return@forEach
            params.forEach { p ->
                val c = p.type.classifier as KClass<*>
                assertTrue("${k.simpleName}.${p.name}: ${c.simpleName}", c.java.isEnum || c in allowed)
                if (c == ChannelName::class) assertTrue(k.simpleName, k in channelHosts)
            }
        }
    }

    @Test
    fun channelTruncatesTo64() {
        assertEquals(64, ChannelName.of("x".repeat(80)).value.length)
        assertEquals("playlist", ChannelName.PLAYLIST.value)
    }

    @Test
    fun gameFinishCompositeProp() {
        val e = GameFinish(
            game = GameId("balloon_pump"), difficulty = GameDifficulty.HARD, outcome = GameOutcome.QUIT,
            won = Won.NO, stars = Stars.ONE, played = GamePlayedBucket.LT_1M, music = GameMusic.OWN_MUSIC,
        )
        assertEquals("balloon_pump/hard", e.props()["game_difficulty"])
        assertEquals(
            mapOf(
                "game" to "balloon_pump", "difficulty" to "hard", "game_difficulty" to "balloon_pump/hard",
                "outcome" to "quit", "won" to "no", "stars" to "1", "played" to "<1m", "music" to "own_music",
            ),
            e.props(),
        )
    }

    @Test
    fun rideEndProps() {
        val e = RideEnd(
            type = RideType.JUST_RIDE, duration = DurationBucket.M5_15, outcome = RideOutcome.DISCARDED,
            discardReason = DiscardReason.TOO_SHORT, hr = HrState.NEVER_CONNECTED, hrDrops = HrDropsBucket.TWO_5,
            sensor = SensorState.DROPPED, music = RideMusic.NONE, musicControlsUsed = false,
        )
        assertEquals("ride_end", e.name)
        assertEquals(
            mapOf(
                "type" to "just_ride", "duration" to "5–15m", "outcome" to "discarded",
                "discard_reason" to "too_short", "hr" to "never_connected", "hr_drops" to "2–5",
                "sensor" to "dropped", "music" to "none", "music_controls_used" to "false",
            ),
            e.props(),
        )
    }

    @Test
    fun rideEndOmitsMusicForNonJustRide() {
        val e = RideEnd(
            RideType.CLASS, DurationBucket.M5_15, RideOutcome.SAVED, DiscardReason.NONE,
            HrState.NONE, HrDropsBucket.ZERO, SensorState.OK, music = null, musicControlsUsed = false,
        )
        assertTrue("music" !in e.props())
    }

    @Test
    fun wireNamesMatchSpec() {
        assertEquals("class", RideType.CLASS.wire)
        assertEquals("bike_plus", Tablet.BIKE_PLUS.wire)
        assertEquals("RQ.250113.A", Firmware.RQ_250113_A.wire)
        assertEquals("other", Firmware.of("something-else").wire)
        assertEquals("QT.250804.A", Firmware.of("QT.250804.A").wire)
        assertEquals("not_recording", DiscardReason.NOT_RECORDING.wire)
        assertEquals("n/a", Won.NA.wire)
        assertEquals("150", YouTubeErrorCode(150).wire)
        assertEquals("app_resumed", VisitEndReason.APP_RESUMED.wire)
    }
}
