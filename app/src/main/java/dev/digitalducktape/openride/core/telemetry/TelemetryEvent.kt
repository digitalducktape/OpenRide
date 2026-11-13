package dev.digitalducktape.openride.core.telemetry

/**
 * One telemetry event. [name] and the [props] keys are the wire names from the telemetry spec.
 * Every prop value is a String drawn from an enum, a bucket, a Boolean, or (for the channel) a
 * truncated [ChannelName]; nothing else can be passed in, by construction.
 */
sealed interface TelemetryEvent {
    val name: String
    fun props(): Map<String, String>
}

private fun Boolean.wire(): String = if (this) "true" else "false"

private fun props(vararg pairs: Pair<String, String?>): Map<String, String> =
    buildMap { pairs.forEach { (k, v) -> if (v != null) put(k, v) } }

// App

data class AppOpen(
    val tablet: Tablet,
    val firmware: Firmware,
    val profiles: ProfilesBucket,
    val flavor: Flavor,
) : TelemetryEvent {
    override val name get() = "app_open"
    override fun props() = props(
        "tablet" to tablet.wire, "firmware" to firmware.wire, "profiles" to profiles.wire, "flavor" to flavor.wire,
    )
}

data class ScreenView(val screen: Screen) : TelemetryEvent {
    override val name get() = "screen_view"
    override fun props() = props("screen" to screen.wire)
}

data class TelemetryEnabled(val source: ConsentSource) : TelemetryEvent {
    override val name get() = "telemetry_enabled"
    override fun props() = props("source" to source.wire)
}

// Profiles

data class ProfileCreated(val hasPhoto: Boolean) : TelemetryEvent {
    override val name get() = "profile_created"
    override fun props() = props("has_photo" to hasPhoto.wire())
}

// Rides

data class RideStart(val type: RideType, val entry: RideEntry, val route: Boolean) : TelemetryEvent {
    override val name get() = "ride_start"
    override fun props() = props("type" to type.wire, "entry" to entry.wire, "route" to route.wire())
}

/** [music] is sent only for Just Ride; pass null for classes and games rides. */
data class RideEnd(
    val type: RideType,
    val duration: DurationBucket,
    val outcome: RideOutcome,
    val discardReason: DiscardReason,
    val hr: HrState,
    val hrDrops: HrDropsBucket,
    val sensor: SensorState,
    val music: RideMusic?,
    val musicControlsUsed: Boolean,
) : TelemetryEvent {
    override val name get() = "ride_end"
    override fun props() = props(
        "type" to type.wire,
        "duration" to duration.wire,
        "outcome" to outcome.wire,
        "discard_reason" to discardReason.wire,
        "hr" to hr.wire,
        "hr_drops" to hrDrops.wire,
        "sensor" to sensor.wire,
        "music" to music?.wire,
        "music_controls_used" to musicControlsUsed.wire(),
    )
}

// Classes

data class ClassStart(
    val channel: ChannelName,
    val channelSource: ChannelSource,
    val category: ClassCategory,
    val source: ClassSource,
) : TelemetryEvent {
    override val name get() = "class_start"
    override fun props() = props(
        "channel" to channel.value, "channel_source" to channelSource.wire,
        "category" to category.wire, "source" to source.wire,
    )
}

data class ClassEnd(
    val channel: ChannelName,
    val channelSource: ChannelSource,
    val videoLength: DurationBucket,
    val watched: DurationBucket,
    val finished: Boolean,
    val muted: MuteState,
) : TelemetryEvent {
    override val name get() = "class_end"
    override fun props() = props(
        "channel" to channel.value, "channel_source" to channelSource.wire,
        "video_length" to videoLength.wire, "watched" to watched.wire,
        "finished" to finished.wire(), "muted" to muted.wire,
    )
}

data class ClassPlayerError(val code: YouTubeErrorCode, val channel: ChannelName) : TelemetryEvent {
    override val name get() = "class_player_error"
    override fun props() = props("code" to code.wire, "channel" to channel.value)
}

data class ContentSourceAdded(val channel: ChannelName, val kind: SourceKind) : TelemetryEvent {
    override val name get() = "content_source_added"
    override fun props() = props("channel" to channel.value, "kind" to kind.wire)
}

// Games

data class GamesPlanStart(val mode: PlanMode, val difficulty: GameDifficulty, val music: GameMusic) : TelemetryEvent {
    override val name get() = "games_plan_start"
    override fun props() = props("mode" to mode.wire, "difficulty" to difficulty.wire, "music" to music.wire)
}

data class GameFinish(
    val game: GameId,
    val difficulty: GameDifficulty,
    val outcome: GameOutcome,
    val won: Won,
    val stars: Stars,
    val played: GamePlayedBucket,
    val music: GameMusic,
) : TelemetryEvent {
    override val name get() = "game_finish"
    override fun props() = props(
        "game" to game.value,
        "difficulty" to difficulty.wire,
        "game_difficulty" to "${game.value}/${difficulty.wire}",
        "outcome" to outcome.wire,
        "won" to won.wire,
        "stars" to stars.wire,
        "played" to played.wire,
        "music" to music.wire,
    )
}

data class GamesVisitEnd(
    val played: DurationBucket,
    val games: GamesPlayedBucket,
    val reason: VisitEndReason,
    val music: VisitMusic,
    val musicControlsUsed: Boolean,
) : TelemetryEvent {
    override val name get() = "games_visit_end"
    override fun props() = props(
        "played" to played.wire, "games" to games.wire, "reason" to reason.wire,
        "music" to music.wire, "music_controls_used" to musicControlsUsed.wire(),
    )
}

data class GameMusicSwitch(val value: OnOff) : TelemetryEvent {
    override val name get() = "game_music_switch"
    override fun props() = props("value" to value.wire)
}

data class HeadCalibration(val result: CalibrationResult, val mode: CalibrationMode) : TelemetryEvent {
    override val name get() = "head_calibration"
    override fun props() = props("result" to result.wire, "mode" to mode.wire)
}

// Music

data class MusicPlayerOpen(val surface: MusicSurface) : TelemetryEvent {
    override val name get() = "music_player_open"
    override fun props() = props("surface" to surface.wire)
}

data class MusicAppChosen(val app: MusicApp) : TelemetryEvent {
    override val name get() = "music_app_chosen"
    override fun props() = props("app" to app.wire)
}

data class NotificationAccess(val result: GrantResult) : TelemetryEvent {
    override val name get() = "notification_access"
    override fun props() = props("result" to result.wire)
}

// Sensors and camera

data class HrStrapSelected(val result: HrSelectResult) : TelemetryEvent {
    override val name get() = "hr_strap_selected"
    override fun props() = props("result" to result.wire)
}

/** [path] is null when the state is `unavailable` (no path won). */
data class BikeSensor(val state: BikeSensorState, val path: SensorPath?) : TelemetryEvent {
    override val name get() = "bike_sensor"
    override fun props() = props("state" to state.wire, "path" to path?.wire)
}

data class CameraPermission(val result: GrantResult) : TelemetryEvent {
    override val name get() = "camera_permission"
    override fun props() = props("result" to result.wire)
}

// Your data

data class BackupExport(val result: SuccessResult) : TelemetryEvent {
    override val name get() = "backup_export"
    override fun props() = props("result" to result.wire)
}

data class BackupRestore(val result: RestoreResult) : TelemetryEvent {
    override val name get() = "backup_restore"
    override fun props() = props("result" to result.wire)
}

data object AutoBackupFailed : TelemetryEvent {
    override val name get() = "auto_backup_failed"
    override fun props() = emptyMap<String, String>()
}

data class HistoryImport(
    val result: ImportResult,
    val imported: ImportedBucket,
    val duplicates: Boolean,
) : TelemetryEvent {
    override val name get() = "history_import"
    override fun props() = props(
        "result" to result.wire, "imported" to imported.wire, "duplicates" to duplicates.wire(),
    )
}

data class RideDeleted(val type: DeletedRideType) : TelemetryEvent {
    override val name get() = "ride_deleted"
    override fun props() = props("type" to type.wire)
}

data class RideExport(val format: ExportFormat) : TelemetryEvent {
    override val name get() = "ride_export"
    override fun props() = props("format" to format.wire)
}

data class GpxImport(val result: SuccessResult, val points: GpxPointsBucket) : TelemetryEvent {
    override val name get() = "gpx_import"
    override fun props() = props("result" to result.wire, "points" to points.wire)
}

data object GpxRouteCleared : TelemetryEvent {
    override val name get() = "gpx_route_cleared"
    override fun props() = emptyMap<String, String>()
}

// Updates

data class UpdatePrompt(val action: UpdateAction) : TelemetryEvent {
    override val name get() = "update_prompt"
    override fun props() = props("action" to action.wire)
}

data class UpdateFailed(val stage: UpdateStage) : TelemetryEvent {
    override val name get() = "update_failed"
    override fun props() = props("stage" to stage.wire)
}
