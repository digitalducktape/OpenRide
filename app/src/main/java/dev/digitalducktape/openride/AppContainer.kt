package dev.digitalducktape.openride

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.core.content.ContextCompat
import androidx.room.Room
import dev.digitalducktape.openride.core.backup.AutoBackupManager
import dev.digitalducktape.openride.core.backup.BackupRepository
import dev.digitalducktape.openride.core.backup.MediaStoreAutoBackupStore
import dev.digitalducktape.openride.core.camera.CameraXFaceSource
import dev.digitalducktape.openride.core.camera.DefaultHeadTracker
import dev.digitalducktape.openride.core.camera.FaceObservation
import dev.digitalducktape.openride.core.camera.HeadFixtureCsv
import dev.digitalducktape.openride.core.camera.HeadTracker
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import dev.digitalducktape.openride.core.content.ChannelHandleResolver
import dev.digitalducktape.openride.core.content.ContentSourceRepository
import dev.digitalducktape.openride.core.content.YouTubeContentRepository
import dev.digitalducktape.openride.core.data.MIGRATION_1_2
import dev.digitalducktape.openride.core.data.MIGRATION_2_3
import dev.digitalducktape.openride.core.data.MIGRATION_3_4
import dev.digitalducktape.openride.core.data.MIGRATION_4_5
import dev.digitalducktape.openride.core.data.MIGRATION_5_6
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.ProfileHeadCalibrationStore
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.heartrate.AndroidBleScanner
import dev.digitalducktape.openride.core.heartrate.BleHeartRateDataSource
import dev.digitalducktape.openride.core.heartrate.BleScanner
import dev.digitalducktape.openride.core.heartrate.HeartRateManager
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.profile.AvatarPhotoStore
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.route.RouteHolder
import dev.digitalducktape.openride.core.update.AvailableUpdate
import dev.digitalducktape.openride.core.update.UpdateCheckResult
import dev.digitalducktape.openride.core.update.UpdateRepository
import dev.digitalducktape.openride.games.bridge.GameBridge
import dev.digitalducktape.openride.games.bridge.TrackerLink
import dev.digitalducktape.openride.games.bridge.toTrackerReading
import dev.digitalducktape.openride.games.session.GameSessionManager
import dev.digitalducktape.openride.core.sensor.AffernetBikeDataSource
import dev.digitalducktape.openride.core.sensor.BikeDataSource
import dev.digitalducktape.openride.core.sensor.MockBikeDataSource
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine

/**
 * Simple hand-rolled dependency container (no Hilt/DI framework per project scope), owned by
 * [OpenRideApplication] so [MainActivity], the games host and Compose screens can pull their
 * dependencies from one place via constructor injection.
 *
 * [bikeDataSource] is [MockBikeDataSource] by default; [BuildConfig.USE_REAL_BIKE_SENSOR]
 * (default `false`) switches it to [AffernetBikeDataSource] — the real system-service binding,
 * which races the two affernet sensor interfaces and keeps whichever one the board actually
 * feeds (Gen 2 streams over `IV1Interface`, Bike+ over `IBikeInterface`). Every other layer
 * only depends on the [BikeDataSource] interface, so this toggle is the one place the choice
 * is made.
 */
class AppContainer(private val applicationContext: Context) {
    /** Long-lived scope for singletons that need to run coroutines outside any one screen's lifecycle. */
    private val containerScope = CoroutineScope(SupervisorJob())

    private val database: OpenRideDatabase by lazy {
        Room.databaseBuilder(
            applicationContext,
            OpenRideDatabase::class.java,
            OpenRideDatabase.DATABASE_NAME,
        ).addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6).build()
    }

    /** Rider avatar photos on disk (camera capture feature); paths live on [dev.digitalducktape.openride.core.data.Profile.avatarPhotoPath]. */
    val avatarPhotoStore: AvatarPhotoStore by lazy {
        AvatarPhotoStore(File(applicationContext.filesDir, "avatars"))
    }

    val profileRepository: ProfileRepository by lazy {
        ProfileRepository(database.profileDao())
    }

    val rideRepository: RideRepository by lazy {
        RideRepository(database, database.rideDao(), database.gameResultDao())
    }

    /** Whole-database backup/restore to one shareable file (PRD P1-8, T15). */
    val backupRepository: BackupRepository by lazy {
        BackupRepository(database, database.profileDao(), database.rideDao(), avatarPhotoStore, database.gameResultDao())
    }

    /**
     * Rolling automatic backup to shared Downloads storage plus silent restore on an empty
     * database, so an app update/reinstall doesn't lose ride data. Started once from
     * [OpenRideApplication.onCreate].
     */
    val autoBackupManager: AutoBackupManager by lazy {
        AutoBackupManager(
            backupRepository = backupRepository,
            store = MediaStoreAutoBackupStore(applicationContext),
            scope = containerScope,
            dataChanges = combine(
                database.profileDao().observeAll(),
                database.rideDao().observeRideCount(),
                // A game session saves its results just after its ride.
                database.gameResultDao().observeCount(),
            ) { profiles, rideCount, resultCount -> Triple(profiles, rideCount, resultCount) },
            isDatabaseEmpty = {
                database.profileDao().getAllOnce().isEmpty() && database.rideDao().getAllRidesOnce().isEmpty()
            },
        )
    }

    val bikeDataSource: BikeDataSource by lazy {
        if (BuildConfig.USE_REAL_BIKE_SENSOR) {
            AffernetBikeDataSource(applicationContext, containerScope).also { it.start() }
        } else {
            MockBikeDataSource(scope = containerScope)
        }
    }

    val rideSessionManager: RideSessionManager by lazy {
        RideSessionManager(
            bikeDataSource = bikeDataSource,
            rideRepository = rideRepository,
            scope = containerScope,
            heartRateBpm = heartRateManager.bpm,
        )
    }

    /**
     * Camera head lean/standing for the mini-games (#33). The camera only runs while a game sets
     * a tracker mode other than `off`. Each rider's lean extremes are kept in
     * `Profile.headCalibration`.
     */
    val headTracker: HeadTracker by lazy {
        DefaultHeadTracker(
            faceSource = headFaceSource,
            calibrationStore = ProfileHeadCalibrationStore(database.profileDao()),
            activeProfileId = activeProfileHolder.activeProfileId,
            hasCameraPermission = {
                ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.CAMERA) ==
                    PackageManager.PERMISSION_GRANTED
            },
            scope = containerScope,
            frameLog = if (BuildConfig.DEBUG) ::logHeadFrame else null,
        )
    }

    /**
     * Debug builds: one line per camera frame with the raw and filtered lean, and the face as a
     * fixture CSV row (numbers only) so a ride can be replayed in the unit tests. Silent unless
     * enabled: `adb shell setprop log.tag.HeadTrackerFrames VERBOSE`.
     */
    private fun logHeadFrame(timestampMs: Long, face: FaceObservation?, state: HeadTrackerState) {
        if (!Log.isLoggable(HEAD_FRAMES_TAG, Log.VERBOSE)) return
        Log.v(
            HEAD_FRAMES_TAG,
            String.format(
                java.util.Locale.US,
                "raw=%+.3f lean=%+.3f depth=%+.3f standing=%d state=%d fixture=%s",
                state.rawLeanX, state.leanX, state.leanDepth, if (state.standing) 1 else 0, state.trackerState.code,
                HeadFixtureCsv.format(HeadFixtureCsv.Row(timestampMs, "live", face, bikeDataSource.metrics.value.cadenceRpm)),
            ),
        )
    }

    /**
     * The camera under [headTracker]. Only [headTracker] starts and stops it; the debug bench
     * reads its frame-rate stats and taps its frames for fixtures.
     */
    val headFaceSource: CameraXFaceSource by lazy { CameraXFaceSource(applicationContext) }

    /** Scopes the session to whichever rider is currently selected (PRD P0-3). */
    val activeProfileHolder: ActiveProfileHolder by lazy {
        ActiveProfileHolder(applicationContext)
    }

    /** BLE scanning for nearby heart-rate straps (PRD P1-4, T17), used by the pairing screen. */
    val bleScanner: BleScanner by lazy {
        AndroidBleScanner(applicationContext)
    }

    /**
     * Connects to whichever BLE strap is paired for the active profile and exposes a single
     * live bpm/connection-state pair (PRD P1-4, T17). Constructed eagerly from
     * [OpenRideApplication.onCreate] (not just whenever a screen happens to reference it first) so it
     * starts observing the active profile the moment the app launches, same reasoning as
     * [rideSessionManager]'s screen-on observation.
     */
    val heartRateManager: HeartRateManager by lazy {
        HeartRateManager(
            activeProfileHolder = activeProfileHolder,
            profileRepository = profileRepository,
            connectionFactory = { address -> BleHeartRateDataSource(applicationContext, address) },
            scope = containerScope,
        )
    }

    /**
     * Mini-games (#32): the app-scoped side of the Godot bridge. One per process, like the
     * Godot engine itself, so every GameHostActivity (and the engine's one plugin instance)
     * shares it and the same live sensor feed.
     */
    val gameBridge: GameBridge by lazy {
        GameBridge(
            bikeDataSource = bikeDataSource,
            heartRateBpm = heartRateManager.bpm,
            trackerReading = { headTracker.state.value.toTrackerReading() },
        )
    }

    /**
     * Mini-games sessions (#35): walks each session's plan over [gameBridge] and records it as a
     * ride through [rideSessionManager] plus its game results. App-scoped, on the main thread,
     * so a session's ride is saved even after the games host has gone to the back.
     */
    val gameSessionManager: GameSessionManager by lazy {
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        val log: (String) -> Unit = { Log.i(GAMES_LOG_TAG, it) }
        GameSessionManager(
            signals = gameBridge,
            scope = scope,
            rideSessionManager = rideSessionManager,
            gameResultDao = database.gameResultDao(),
            activeProfileId = { activeProfileHolder.activeProfileId.value },
            profileFtp = { profileRepository.getProfile(it)?.ftp },
            tracker = TrackerLink(headTracker, gameBridge, scope, log),
            otherMusicActive = {
                (applicationContext.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)?.isMusicActive == true
            },
            log = log,
        )
    }

    /** The Classes tab's configured source list — seeded catalog plus rider additions. */
    val contentSourceRepository: ContentSourceRepository by lazy {
        ContentSourceRepository(database.contentSourceDao())
    }

    /** Curated YouTube-channel content for the Classes browser (PRD P0-6, T9/T10). */
    val contentRepository: YouTubeContentRepository by lazy {
        YouTubeContentRepository(applicationContext, contentSourceRepository)
    }

    /** Resolves pasted channel/playlist links for the Content Sources screen. */
    val channelHandleResolver: ChannelHandleResolver by lazy {
        ChannelHandleResolver()
    }

    /** The currently-loaded GPX route overlay for the ride screen (PRD #21/T21), if any. */
    val routeHolder: RouteHolder by lazy {
        RouteHolder()
    }

    /** Fetch/download side of the GitHub-native self-updater (PRD #22/T22). */
    val updateRepository: UpdateRepository by lazy {
        UpdateRepository(applicationContext)
    }

    private val _updateAvailability = MutableStateFlow<AvailableUpdate?>(null)

    /** The newer release found by the last launch check, or null if none / not yet checked. */
    val updateAvailability: StateFlow<AvailableUpdate?> = _updateAvailability.asStateFlow()

    private val _updateBannerDismissed = MutableStateFlow(false)

    /** Whether the rider dismissed the Home update banner this session (resets on relaunch). */
    val updateBannerDismissed: StateFlow<Boolean> = _updateBannerDismissed.asStateFlow()

    /** Hides the Home update banner until the next launch (the update stays reachable via Profile). */
    fun dismissUpdateBanner() {
        _updateBannerDismissed.value = true
    }

    /**
     * Best-effort launch check (PRD #22/T22): asks GitHub for the latest release and, if it's
     * newer, publishes it to [updateAvailability] for the Home banner. Silent on any failure —
     * a launch must never be blocked or interrupted by the updater. Called from [OpenRideApplication].
     */
    suspend fun refreshUpdateAvailability(currentVersionCode: Int, assetInfix: String) {
        val result = updateRepository.check(currentVersionCode, assetInfix)
        if (result is UpdateCheckResult.Available) {
            _updateAvailability.value = result.update
        }
    }
}

private const val GAMES_LOG_TAG = "OpenRideGames"

/**
 * Builds a [ViewModelProvider.Factory] from a plain lambda, so screens can construct their
 * view models straight from [AppContainer] dependencies (manual DI, no Hilt) while still
 * getting normal [ViewModel] lifecycle/state-retention behavior from Compose Navigation's
 * per-destination [androidx.lifecycle.ViewModelStoreOwner].
 */
private const val HEAD_FRAMES_TAG = "HeadTrackerFrames"

fun <T : ViewModel> viewModelFactory(create: () -> T): ViewModelProvider.Factory =
    object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <VM : ViewModel> create(modelClass: Class<VM>): VM = create() as VM
    }
