package dev.digitalducktape.openride.core.telemetry

/** A telemetry prop value: it is sent as exactly [wire], never anything else. */
interface Wire {
    val wire: String
}

enum class Tablet(override val wire: String) : Wire { BIKE("bike"), BIKE_PLUS("bike_plus"), OTHER("other") }

/** Known `Build.DISPLAY` values; anything else is [OTHER]. */
enum class Firmware(override val wire: String) : Wire {
    RQ_250113_A("RQ.250113.A"),
    QT_250804_A("QT.250804.A"),
    OTHER("other"),
    ;

    companion object {
        fun of(display: String?): Firmware = entries.firstOrNull { it != OTHER && it.wire == display } ?: OTHER
    }
}

enum class Flavor(override val wire: String) : Wire { REAL("real"), MOCK("mock") }

enum class Screen(override val wire: String) : Wire {
    PROFILE_SELECT("profile_select"), PROFILE_CREATE("profile_create"), PROFILE_EDIT("profile_edit"),
    HOME("home"), CLASSES("classes"), GAMES("games"), HISTORY("history"), PROFILE("profile"),
    HR_PAIRING("hr_pairing"), APP_UPDATE("app_update"), ABOUT("about"), CONTENT_SOURCES("content_sources"),
    CREATOR("creator"), TELEMETRY_INFO("telemetry_info"),
}

enum class ConsentSource(override val wire: String) : Wire { FIRST_RUN("first_run"), SETTINGS("settings") }

enum class RideType(override val wire: String) : Wire { JUST_RIDE("just_ride"), CLASS("class"), GAMES("games") }

/** [RideType] plus `imported`, for `ride_deleted`. */
enum class DeletedRideType(override val wire: String) : Wire {
    JUST_RIDE("just_ride"), CLASS("class"), GAMES("games"), IMPORTED("imported"),
}

enum class RideEntry(override val wire: String) : Wire {
    HOME_QUICK_START("home_quick_start"), CLASSES("classes"), CREATOR("creator"), GAMES("games"),
}

enum class RideOutcome(override val wire: String) : Wire { SAVED("saved"), DISCARDED("discarded") }

enum class DiscardReason(override val wire: String) : Wire {
    NONE("none"), TOO_SHORT("too_short"), NO_PEDALLING("no_pedalling"), NOT_RECORDING("not_recording"),
}

enum class HrState(override val wire: String) : Wire {
    NONE("none"), CONNECTED("connected"), DROPPED("dropped"), NEVER_CONNECTED("never_connected"),
}

enum class SensorState(override val wire: String) : Wire { OK("ok"), DROPPED("dropped"), NEVER("never") }

/** Just Ride only; classes and games rides send no `music` on `ride_end`. */
enum class RideMusic(override val wire: String) : Wire { OWN_MUSIC("own_music"), NONE("none") }

enum class ChannelSource(override val wire: String) : Wire { CURATED("curated"), CUSTOM("custom") }

enum class ClassCategory(override val wire: String) : Wire { SCENIC("scenic"), WORKOUT("workout") }

enum class ClassSource(override val wire: String) : Wire { CLASSES("classes"), CREATOR("creator") }

enum class MuteState(override val wire: String) : Wire { NEVER("never"), FROM_START("from_start"), DURING("during") }

enum class SourceKind(override val wire: String) : Wire { CHANNEL("channel"), PLAYLIST("playlist") }

enum class PlanMode(override val wire: String) : Wire {
    SINGLE("single"), CIRCUIT("circuit"), CUSTOM_CIRCUIT("custom_circuit"),
}

enum class GameDifficulty(override val wire: String) : Wire {
    EASY("easy"), STANDARD("standard"), HARD("hard"),
}

enum class GameMusic(override val wire: String) : Wire {
    GAME_MUSIC("game_music"), OWN_MUSIC("own_music"), OFF("off"),
}

/** [GameMusic] plus `mixed`, for a visit that saw more than one. */
enum class VisitMusic(override val wire: String) : Wire {
    GAME_MUSIC("game_music"), OWN_MUSIC("own_music"), MIXED("mixed"), OFF("off"),
}

enum class GameOutcome(override val wire: String) : Wire {
    COMPLETED("completed"), QUIT("quit"), SKIPPED("skipped"), NO_RESULT("no_result"),
}

enum class Won(override val wire: String) : Wire { YES("yes"), NO("no"), NA("n/a") }

enum class Stars(override val wire: String) : Wire {
    ZERO("0"), ONE("1"), TWO("2"), THREE("3");

    companion object {
        fun of(n: Int): Stars = entries[n.coerceIn(0, 3)]
    }
}

enum class VisitEndReason(override val wire: String) : Wire {
    EXIT("exit"), IDLE("idle"), APP_RESUMED("app_resumed"), REPLACED("replaced"),
}

enum class OnOff(override val wire: String) : Wire { ON("on"), OFF("off") }

enum class CalibrationResult(override val wire: String) : Wire { SUCCESS("success"), CANCELLED("cancelled"), FAILED("failed") }

enum class CalibrationMode(override val wire: String) : Wire { LEAN_X("lean_x"), LEAN_2D("lean_2d") }

enum class MusicSurface(override val wire: String) : Wire {
    TOP_BAR("top_bar"), JUST_RIDE("just_ride"), VIDEO_RIDE("video_ride"), GAMES("games"),
}

enum class MusicApp(override val wire: String) : Wire {
    SPOTIFY("spotify"), APPLE_MUSIC("apple_music"), PANDORA("pandora"), SIRIUSXM("siriusxm"),
    PLEXAMP("plexamp"), OTHER("other"),
}

/** `granted` / `denied`, for notification access and the camera permission. */
enum class GrantResult(override val wire: String) : Wire { GRANTED("granted"), DENIED("denied") }

enum class HrSelectResult(override val wire: String) : Wire {
    SELECTED("selected"), BT_OFF("bt_off"), SCAN_FAILED("scan_failed"),
}

enum class BikeSensorState(override val wire: String) : Wire { CONNECTED("connected"), UNAVAILABLE("unavailable") }

/** Which binder fed the bike: the `race()` winner (`AffernetBikeDataSource`), or polling. */
enum class SensorPath(override val wire: String) : Wire {
    IV1_INTERFACE("iv1_interface"), BIKE_INTERFACE("bike_interface"), POLLING("polling"),
}

/** `success` / `failed`, for backup export and GPX import. */
enum class SuccessResult(override val wire: String) : Wire { SUCCESS("success"), FAILED("failed") }

enum class RestoreResult(override val wire: String) : Wire {
    SUCCESS("success"), FAILED("failed"), BAD_FILE("bad_file"),
}

enum class ImportResult(override val wire: String) : Wire {
    SUCCESS("success"), FAILED("failed"), WRONG_FILE("wrong_file"), NO_RIDER("no_rider"),
}

enum class ExportFormat(override val wire: String) : Wire {
    TCX("tcx"), CSV_RIDE("csv_ride"), CSV_HISTORY("csv_history"),
}

enum class UpdateAction(override val wire: String) : Wire { SHOWN("shown"), INSTALL_TAPPED("install_tapped") }

enum class UpdateStage(override val wire: String) : Wire { CHECK("check"), DOWNLOAD("download") }

enum class AboutTarget(override val wire: String) : Wire {
    RELEASE_NOTES("release_notes"), GITHUB("github"), COFFEE("coffee"),
}

// Buckets (see TelemetryBuckets). Edges are half-open: [low, high).

/** Ride, visit and class durations: ride `duration`, visit `played`, `video_length`, `watched`. */
enum class DurationBucket(override val wire: String) : Wire {
    LT_5M("<5m"), M5_15("5–15m"), M15_30("15–30m"), M30_45("30–45m"), M45_60("45–60m"), M60_PLUS("60m+"),
}

/** One game's `played`. */
enum class GamePlayedBucket(override val wire: String) : Wire {
    LT_1M("<1m"), M1_3("1–3m"), M3_5("3–5m"), M5_10("5–10m"), M10_PLUS("10m+"),
}

enum class ProfilesBucket(override val wire: String) : Wire { ONE("1"), TWO("2"), THREE_PLUS("3+") }

enum class HrDropsBucket(override val wire: String) : Wire {
    ZERO("0"), ONE("1"), TWO_5("2–5"), SIX_PLUS("6+"),
}

enum class GamesPlayedBucket(override val wire: String) : Wire {
    ZERO("0"), ONE("1"), TWO("2"), THREE("3"), FOUR("4"), FIVE_PLUS("5+"),
}

enum class ImportedBucket(override val wire: String) : Wire {
    ZERO("0"), N1_10("1–10"), N11_50("11–50"), N51_200("51–200"), N200_PLUS("200+"),
}

enum class GpxPointsBucket(override val wire: String) : Wire {
    LT_500("<500"), P500_2K("500–2k"), K2_10K("2k–10k"), K10_PLUS("10k+"),
}

/** The one free-form prop: a channel name, at most [MAX] characters. Use [of] to build one. */
@JvmInline
value class ChannelName private constructor(val value: String) {
    companion object {
        const val MAX = 64

        /** Sent for playlists instead of a name. */
        val PLAYLIST = ChannelName("playlist")

        fun of(raw: String): ChannelName = ChannelName(raw.trim().take(MAX).ifEmpty { "unknown" })
    }
}

/** A mini-game's catalog id. */
@JvmInline
value class GameId(val value: String)

/** A YouTube IFrame player error code; sent as its digits. */
@JvmInline
value class YouTubeErrorCode(val code: Int) {
    val wire: String get() = code.toString()
}
