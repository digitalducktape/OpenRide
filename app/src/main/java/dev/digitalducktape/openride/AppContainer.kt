package dev.digitalducktape.openride

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.AudioPlaybackConfiguration
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelProvider
import androidx.core.content.ContextCompat
import java.time.ZoneId
import androidx.room.Room
import dev.digitalducktape.openride.core.backup.AutoBackupManager
import dev.digitalducktape.openride.core.backup.BackupRepository
import dev.digitalducktape.openride.core.backup.MediaStoreAutoBackupStore
import dev.digitalducktape.openride.core.camera.CameraXFaceSource
import dev.digitalducktape.openride.core.camera.DefaultHeadTracker
import dev.digitalducktape.openride.core.camera.FaceObservation
import dev.digitalducktape.openride.core.camera.HeadCalibration
import dev.digitalducktape.openride.core.camera.HeadFixtureCsv
import dev.digitalducktape.openride.core.camera.HeadTracker
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import dev.digitalducktape.openride.core.camera.UnavailableReason
import dev.digitalducktape.openride.core.content.ChannelHandleResolver
import dev.digitalducktape.openride.core.controller.BleObcLink
import dev.digitalducktape.openride.core.controller.ControllerManager
import dev.digitalducktape.openride.core.controller.ControllerRouter
import dev.digitalducktape.openride.core.controller.ControllerScanner
import dev.digitalducktape.openride.core.controller.ControllerStore
import dev.digitalducktape.openride.core.controller.ControllerTransport
import dev.digitalducktape.openride.core.controller.NetworkObcLink
import dev.digitalducktape.openride.core.controller.ObcControllerScanner
import dev.digitalducktape.openride.core.controller.ObcProtocol
import dev.digitalducktape.openride.core.controller.SharedPrefsControllerStore
import dev.digitalducktape.openride.core.content.ContentSourceRepository
import dev.digitalducktape.openride.core.content.YouTubeContentRepository
import dev.digitalducktape.openride.core.data.MIGRATION_1_2
import dev.digitalducktape.openride.core.data.MIGRATION_2_3
import dev.digitalducktape.openride.core.data.MIGRATION_3_4
import dev.digitalducktape.openride.core.data.MIGRATION_4_5
import dev.digitalducktape.openride.core.data.MIGRATION_5_6
import dev.digitalducktape.openride.core.data.MIGRATION_6_7
import dev.digitalducktape.openride.core.data.MIGRATION_7_8
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.ProfileHeadCalibrationStore
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.heartrate.AndroidBleScanner
import dev.digitalducktape.openride.core.heartrate.BleHeartRateDataSource
import dev.digitalducktape.openride.core.heartrate.BleScanner
import dev.digitalducktape.openride.core.heartrate.HeartRateManager
import dev.digitalducktape.openride.core.heartrate.strapWanted
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.profile.AvatarPhotoStore
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.route.RouteHolder
import dev.digitalducktape.openride.core.update.AvailableUpdate
import dev.digitalducktape.openride.core.update.UpdateCheckResult
import dev.digitalducktape.openride.core.update.UpdateRepository
import dev.digitalducktape.openride.games.bridge.CameraPermission
import dev.digitalducktape.openride.games.bridge.ControllerReading
import dev.digitalducktape.openride.games.bridge.GameBridge
import dev.digitalducktape.openride.games.bridge.TrackerLink
import dev.digitalducktape.openride.games.bridge.toTrackerReading
import dev.digitalducktape.openride.games.session.BitmapAvatarRenderer
import dev.digitalducktape.openride.games.session.GameSessionManager
import dev.digitalducktape.openride.games.session.GameVisitManager
import dev.digitalducktape.openride.games.session.VisitNavigator
import dev.digitalducktape.openride.games.session.GamesSettingsStore
import dev.digitalducktape.openride.games.session.SharedPrefsGamesSettingsStore
import dev.digitalducktape.openride.games.session.NowPlayingFeed
import dev.digitalducktape.openride.games.session.OtherMusicDetector
import dev.digitalducktape.openride.core.music.NowPlayingMonitor
import dev.digitalducktape.openride.core.sensor.AffernetBikeDataSource
import dev.digitalducktape.openride.core.sensor.BikeSourceStore
import dev.digitalducktape.openride.core.sensor.SharedPrefsBikeSourceStore
import dev.digitalducktape.openride.core.sensor.SwitchableBikeDataSource
import dev.digitalducktape.openride.core.trainer.FtmsBikeDataSource
import dev.digitalducktape.openride.core.trainer.FtmsProtocol
import dev.digitalducktape.openride.core.sensor.MockBikeDataSource
import java.io.File
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.sensor.offlineFor
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.emitAll
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/**
 * Simple hand-rolled dependency container (no Hilt/DI framework per project scope), owned by
 * [OpenRideApplication] so [MainActivity], the games host and Compose screens can pull their
 * dependencies from one place via constructor injection.
 *
 * [bikeDataSource]'s built-in source is [MockBikeDataSource] by default; [BuildConfig.USE_REAL_BIKE_SENSOR]
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
        ).addMigrations(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8).build()
    }

    /** Rider avatar photos on disk (camera capture feature); paths live on [dev.digitalducktape.openride.core.data.Profile.avatarPhotoPath]. */
    val avatarPhotoStore: AvatarPhotoStore by lazy {
        AvatarPhotoStore(File(applicationContext.filesDir, "avatars"))
    }

    val profileRepository: ProfileRepository by lazy {
        ProfileRepository(database.profileDao())
    }

    /**
     * The active rider, kept loaded for the life of the process so every screen draws with it on
     * its first frame (no rider-less frame, then a pop-in: rider bike test, 2026-10-21). `null`
     * while no rider is selected, or until the profile table's first read.
     */
    val activeProfile: StateFlow<Profile?> by lazy {
        combine(activeProfileHolder.activeProfileId, profileRepository.observeProfiles()) { id, profiles ->
            profiles.firstOrNull { it.id == id }
        }.stateIn(containerScope, SharingStarted.Eagerly, null)
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

    /** Which bike source the rider chose (#68): the built-in one, or a smart trainer. */
    val bikeSourceStore: BikeSourceStore by lazy { SharedPrefsBikeSourceStore(applicationContext) }

    /** Finds FTMS smart trainers for the bike-source screen (#68). */
    val trainerScanner: BleScanner by lazy {
        AndroidBleScanner(applicationContext, FtmsProtocol.SERVICE_UUID, offerConnected = false)
    }

    /**
     * The bike's live numbers, from whichever source [bikeSourceStore] holds (#68). The built-in
     * one is the build's: [AffernetBikeDataSource] when [BuildConfig.USE_REAL_BIKE_SENSOR], else
     * [MockBikeDataSource]. A trainer is [FtmsBikeDataSource], connected while OpenRide is in use.
     * On [containerScope], not the main thread: its wanted-flow reads [rideSessionManager], which
     * is built from this, so it must not be collected while this is still being built.
     */
    val bikeDataSource: SwitchableBikeDataSource by lazy {
        SwitchableBikeDataSource(
            store = bikeSourceStore,
            builtin = {
                if (BuildConfig.USE_REAL_BIKE_SENSOR) {
                    AffernetBikeDataSource(applicationContext, containerScope).also { it.start() }
                } else {
                    MockBikeDataSource(scope = containerScope)
                }
            },
            trainerFactory = { address -> FtmsBikeDataSource(applicationContext, address) },
            scope = containerScope,
            wanted = accessoriesWanted(),
        )
    }

    /**
     * Whether the bike's sensors count as offline, by the app's one rule (issue #56,
     * [offlineFor]): anything but Connected, a silent board included, for 10 s. `null` until
     * that is known. The top bar, the ride screens and the games all read this, so they agree.
     */
    val sensorsOffline: StateFlow<Boolean?> by lazy {
        bikeDataSource.connectionState.offlineFor().stateIn(containerScope, SharingStarted.Eagerly, null)
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
            keepCameraOnNoFace = ::trackerLoadSwitchOn,
        )
    }

    /**
     * The mock debug build's tracker load switch: with `files/tracker_load` present, the camera
     * and face detection keep running after a no-face calibration, so a game's frame rate can be
     * measured with the tracker's load and nobody on the bike (docs/GAMES.md, Kart Race). Off in
     * release and `debugReal`, whatever the file says.
     */
    private fun trackerLoadSwitchOn(): Boolean =
        BuildConfig.DEBUG && !BuildConfig.USE_REAL_BIKE_SENSOR &&
            java.io.File(applicationContext.filesDir, TRACKER_LOAD_FILE).exists()

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
                "raw=%+.3f lean=%+.3f depth=%+.3f standing=%d state=%d away=%d fixture=%s",
                state.rawLeanX, state.leanX, state.leanDepth, if (state.standing) 1 else 0, state.trackerState.code,
                if (state.lookingAway) 1 else 0,
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
            wanted = strapWanted(
                foreground = ProcessLifecycleOwner.get().lifecycle.currentStateFlow
                    .map { it.isAtLeast(Lifecycle.State.STARTED) },
                // Read on first collection, not here: rideSessionManager takes this manager's
                // bpm, so touching it while building this one loops forever (a crash on launch).
                rideActive = flow { emitAll(rideSessionManager.isRideActive) },
            ),
        )
    }

    /** Main-thread scope for the controllers: their links call back on the main thread. */
    private val mainScope: CoroutineScope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }

    /** Whether OpenRide needs its Bluetooth accessories now: in front, or recording a ride ([strapWanted]). */
    private fun accessoriesWanted() = strapWanted(
        foreground = ProcessLifecycleOwner.get().lifecycle.currentStateFlow
            .map { it.isAtLeast(Lifecycle.State.STARTED) },
        rideActive = flow { emitAll(rideSessionManager.isRideActive) },
    )

    /** The OpenBikeControl controllers the rider paired (#68): the bike's, shared by every rider. */
    val controllerStore: ControllerStore by lazy { SharedPrefsControllerStore(applicationContext) }

    /** Finds controllers for the pairing screen, over Bluetooth and the local network (#68). */
    val controllerScanner: ControllerScanner by lazy {
        ObcControllerScanner(
            applicationContext,
            AndroidBleScanner(applicationContext, ObcProtocol.SERVICE_UUID, offerConnected = false),
        )
    }

    /**
     * Keeps the paired controllers connected while OpenRide is in use (#68), like the strap, and
     * turns their buttons into actions. Built at launch from [OpenRideApplication.onCreate].
     */
    val controllerManager: ControllerManager by lazy {
        ControllerManager(
            store = controllerStore,
            linkFactory = { controller ->
                when (controller.transport) {
                    ControllerTransport.BLUETOOTH -> BleObcLink(applicationContext, controller.id, BuildConfig.VERSION_NAME)
                    ControllerTransport.NETWORK -> NetworkObcLink(applicationContext, controller.id, BuildConfig.VERSION_NAME)
                }
            },
            scope = mainScope,
            wanted = accessoriesWanted(),
        )
    }

    /** Sends the controllers' presses to the ride, the games and the trainer (#68). */
    val controllerRouter: ControllerRouter by lazy {
        ControllerRouter(
            events = controllerManager.events,
            scope = mainScope,
            gameSessionActive = { gameBridge.hasSession },
            // Lambdas, not bound references: launch builds this, and needn't build the bridge.
            pauseGame = { gameBridge.requestPause() },
            resumeGame = { gameBridge.requestResume() },
            rideState = { rideSessionManager.state.value },
            pauseRide = { rideSessionManager.pause() },
            resumeRide = { rideSessionManager.resume() },
            stepResistance = { steps ->
                if (bikeDataSource.adjustable.value) {
                    bikeDataSource.stepResistance(steps)
                    controllerManager.haptic(ObcProtocol.HAPTIC_SHORT)
                }
            },
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
            sensorsOffline = sensorsOffline,
            heartRateBpm = heartRateManager.bpm,
            trackerReading = { headTracker.state.value.toTrackerReading() },
            riderMusic = { riderMusic.value },
            musicControl = { NowPlayingFeed.control(nowPlaying, it) },
            controllerReading = { ControllerReading(controllerManager.steer.value, controllerRouter.itemPresses) },
        ).also { bridge ->
            // The hub's music card: the rider's track, sent as it changes.
            NowPlayingFeed(applicationContext, nowPlaying, bridge::publishNowPlaying, containerScope)
        }
    }

    /**
     * The rider has their own music, so game music stays off (rider's call, 2026-10-27: no
     * switch, sound effects keep playing). With Now playing access, that's the mini player
     * having a track, playing or paused; without it, [otherMusicDetector]'s guess. Checked once
     * a second off the main thread, since the games read it every frame.
     */
    val riderMusic: StateFlow<Boolean> by lazy {
        flow {
            while (true) {
                emit(if (nowPlaying.hasAccess.value) nowPlaying.nowPlaying.value != null else otherMusicDetector.otherMusicActive())
                delay(RIDER_MUSIC_CHECK_MS)
            }
        }.flowOn(Dispatchers.Default).stateIn(containerScope, SharingStarted.Eagerly, false)
    }

    /**
     * Mini-games sessions (#35): walks each session's plan over [gameBridge] and records it as a
     * ride through [rideSessionManager] plus its game results. App-scoped, on the main thread,
     * so a session's ride is saved even after the games host has gone to the back.
     */
    /** The Games hub's settings (#38): game audio and the camera-games switch. */
    val gamesSettings: GamesSettingsStore by lazy { SharedPrefsGamesSettingsStore(applicationContext) }

    /** Read by the Games hub for the rider's bests (#38). */
    val gameResultDao get() = database.gameResultDao()

    /** The plan runner (Games hub): walks one plan at a time over [gameBridge] for [gameVisitManager]. */
    val gameSessionManager: GameSessionManager by lazy {
        GameSessionManager(
            signals = gameBridge,
            scope = gamesScope,
            tracker = gameTrackerLink,
            audioPrefs = { gamesSettings.settings.value.audio },
            log = gamesLog,
        )
    }

    /** The head tracker as the games use it: the visit's session and the plans' modes. */
    val gameTrackerLink: TrackerLink by lazy { TrackerLink(headTracker, gameBridge, gamesScope, gamesLog) }

    /**
     * The Games hub visit (spec 2026-10-19): the bridge's session from entering games to
     * leaving them, recorded as one ride through [rideSessionManager] plus its game results.
     * App-scoped, on the main thread, so the ride is saved even after the host has gone to the
     * back. `MainActivity` ends a live visit when the app comes back ([GameVisitManager.endIfLive]).
     */
    val gameVisitManager: GameVisitManager by lazy {
        GameVisitManager(
            signals = gameBridge,
            scope = gamesScope,
            runner = gameSessionManager,
            rideSessionManager = rideSessionManager,
            gameResultDao = database.gameResultDao(),
            activeProfileId = { activeProfileHolder.activeProfileId.value },
            profile = { profileRepository.getProfile(it) },
            settings = gamesSettings,
            cameraPermission = ::gamesCameraPermission,
            cameraFailed = {
                headTracker.state.value.unavailable.let { it == UnavailableReason.NO_FACE || it == UnavailableReason.NO_CAMERA }
            },
            sameDayExtremes = { profile ->
                HeadCalibration.fromJson(profile.headCalibration)?.isFreshAt(System.currentTimeMillis(), ZoneId.systemDefault()) == true
            },
            tracker = gameTrackerLink,
            pedalling = { bikeDataSource.metrics.value.cadenceRpm > 0 },
            avatar = BitmapAvatarRenderer(applicationContext.cacheDir)::render,
            navigator = visitNavigator,
            log = gamesLog,
        )
    }

    /** Where the app goes after a games visit (the ride summary, or the profile editor): consumed by the NavHost. */
    val visitNavigator: VisitNavigator by lazy { VisitNavigator() }

    /**
     * The camera permission as the hub shows it. Android can't tell "never asked" from "denied
     * for good" before asking, so it's `ask` until the host's prompt is refused
     * ([gamesCameraPermissionRefused], set by the host).
     */
    private fun gamesCameraPermission(): CameraPermission = when {
        ContextCompat.checkSelfPermission(applicationContext, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED ->
            CameraPermission.GRANTED
        gamesCameraPermissionRefused -> CameraPermission.DENIED
        else -> CameraPermission.ASK
    }

    /** The rider refused the camera permission and Android won't ask again. */
    @Volatile
    var gamesCameraPermissionRefused = false

    /** The games' main-thread scope: the visit and the plan runner touch their state only on it. */
    val gamesScope: CoroutineScope by lazy { CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate) }

    val gamesLog: (String) -> Unit = { Log.i(GAMES_LOG_TAG, it) }

    /**
     * Tells the rider's own music from the Godot engine's player (#35), for [riderMusic] while
     * Now playing access is off. The games host calls [OtherMusicDetector.engineStarting]
     * before the engine starts.
     */
    val otherMusicDetector: OtherMusicDetector by lazy {
        val audioManager = applicationContext.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        OtherMusicDetector(
            players = {
                audioManager.activePlaybackConfigurations
                    .filter { it.audioAttributes.usage == AudioAttributes.USAGE_MEDIA }
            },
            musicActive = { audioManager.isMusicActive },
        ).also { detector ->
            audioManager.registerAudioPlaybackCallback(
                object : AudioManager.AudioPlaybackCallback() {
                    override fun onPlaybackConfigChanged(configs: MutableList<AudioPlaybackConfiguration>?) {
                        detector.observe()
                    }
                },
                Handler(Looper.getMainLooper()),
            )
        }
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

    /** What the rider's music app is playing, for the mini player (top bar and Just Ride). */
    val nowPlaying: NowPlayingMonitor by lazy { NowPlayingMonitor(applicationContext) }

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

/** How often [AppContainer.riderMusic] looks again: a song starting reaches the games within a second. */
private const val RIDER_MUSIC_CHECK_MS = 1_000L

/**
 * Builds a [ViewModelProvider.Factory] from a plain lambda, so screens can construct their
 * view models straight from [AppContainer] dependencies (manual DI, no Hilt) while still
 * getting normal [ViewModel] lifecycle/state-retention behavior from Compose Navigation's
 * per-destination [androidx.lifecycle.ViewModelStoreOwner].
 */
private const val HEAD_FRAMES_TAG = "HeadTrackerFrames"
private const val TRACKER_LOAD_FILE = "tracker_load"

fun <T : ViewModel> viewModelFactory(create: () -> T): ViewModelProvider.Factory =
    object : ViewModelProvider.Factory {
        @Suppress("UNCHECKED_CAST")
        override fun <VM : ViewModel> create(modelClass: Class<VM>): VM = create() as VM
    }
