@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.ui.classes

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.content.ContentCache
import dev.digitalducktape.openride.core.content.ContentCategory
import dev.digitalducktape.openride.core.content.ContentSourceRepository
import dev.digitalducktape.openride.core.content.ContentSourceType
import dev.digitalducktape.openride.core.content.FeedFetcher
import dev.digitalducktape.openride.core.content.ResolvedSource
import dev.digitalducktape.openride.core.content.Video
import dev.digitalducktape.openride.core.content.YouTubeContentRepository
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import java.io.IOException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ClassesViewModelTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private lateinit var db: OpenRideDatabase
    private lateinit var profileRepository: ProfileRepository
    private lateinit var rideRepository: RideRepository
    private lateinit var activeProfileHolder: ActiveProfileHolder
    private lateinit var sources: ContentSourceRepository

    @Before
    fun setUp() = runTest {
        // ClassesViewModel's filter/grid/rows flows are stateIn'd against viewModelScope
        // (SharingStarted.Eagerly), so Main needs to be the test dispatcher for runTest to
        // drive them deterministically — same reasoning as HrPairingViewModelTest.
        Dispatchers.setMain(UnconfinedTestDispatcher())
        db = Room.inMemoryDatabaseBuilder(context, OpenRideDatabase::class.java).build()
        profileRepository = ProfileRepository(db.profileDao())
        rideRepository = RideRepository(db, db.rideDao())
        activeProfileHolder = ActiveProfileHolder(context)
        sources = ContentSourceRepository(db.contentSourceDao())
        sources.add(
            ResolvedSource(ContentSourceType.CHANNEL, "UCTestChannel00000000", "Test Cycling Channel"),
            ContentCategory.Scenic,
        )
    }

    @After
    fun tearDown() {
        db.close()
        Dispatchers.resetMain()
    }

    private fun fixtureXml() =
        requireNotNull(javaClass.classLoader?.getResourceAsStream("fixtures/sample_atom_feed.xml"))

    private fun pageHtml() =
        requireNotNull(javaClass.classLoader?.getResourceAsStream("fixtures/channel_videos_page.html"))
            .bufferedReader().use { it.readText() }

    /**
     * The normal case: a real page (so videos are page-verified and startable) plus the feed for
     * timestamps. Tests that need the degraded page-down path pass a feed-only fetcher explicitly.
     */
    private fun pageBackedFetcher() = FeedFetcher { url ->
        if (url.contains("feeds/videos.xml")) fixtureXml() else pageHtml().byteInputStream()
    }

    private fun repository(fetcher: FeedFetcher = pageBackedFetcher()) =
        YouTubeContentRepository(
            context = context,
            sourceRepository = sources,
            fetcher = fetcher,
            cache = ContentCache(context),
        )

    private fun viewModel(
        scope: CoroutineScope,
        fetcher: FeedFetcher = pageBackedFetcher(),
    ): Pair<ClassesViewModel, RideSessionManager> {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, scope)
        val viewModel = ClassesViewModel(repository(fetcher), manager, activeProfileHolder, rideRepository, routeLoaded = { false })
        return viewModel to manager
    }

    @Test
    fun `starts in Loading state before refresh is called`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        assertTrue(viewModel.uiState.value is ClassesUiState.Loading)
    }

    @Test
    fun `refresh loads channel sections successfully`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        viewModel.refresh()

        val loaded = viewModel.uiState.value as ClassesUiState.Loaded
        assertFalse(loaded.anyRefreshFailed)
        assertEquals(1, loaded.sections.size)
        // The page fixture has three video tiles; the 5:04 one is dropped as too short, leaving two.
        assertEquals(2, loaded.sections.single().videos.size)
        assertTrue(loaded.sections.single().videos.all { it.startable })
    }

    @Test
    fun `anyRefreshFailed is true when a channel's fetch fails`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope, FeedFetcher { throw IOException("down") })

        viewModel.refresh()

        val loaded = viewModel.uiState.value as ClassesUiState.Loaded
        assertTrue(loaded.anyRefreshFailed)
        assertTrue(loaded.sections.single().videos.isEmpty())
    }

    @Test
    fun `a second refresh keeps the previously loaded sections visible instead of resetting to Loading`() = runTest {
        // Finding 5a: refresh() used to reset state to Loading unconditionally, and the
        // screen's LaunchedEffect(Unit) { refresh() } re-fires every time the rider returns to
        // the Classes tab — a full-screen spinner and a blank tab on every visit, not just the
        // first. The fetcher below captures uiState.value from inside the *second* refresh's
        // feed fetch, i.e. while that fetch is still in flight and before its own Loaded state
        // has been written — proving the previous content is still showing at that moment
        // rather than having been blanked back to Loading.
        lateinit var viewModel: ClassesViewModel
        var fetchCount = 0
        var stateDuringSecondFetch: ClassesUiState? = null
        val fetcher = FeedFetcher { url ->
            if (url.contains("feeds/videos.xml")) {
                fetchCount++
                if (fetchCount == 2) {
                    stateDuringSecondFetch = viewModel.uiState.value
                }
            }
            fixtureXml()
        }
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        viewModel = ClassesViewModel(repository(fetcher), manager, activeProfileHolder, rideRepository, routeLoaded = { false })

        viewModel.refresh() // cold start: nothing loaded yet, Loading is fine here
        viewModel.refresh() // second refresh: must not blank the already-loaded content

        val captured = stateDuringSecondFetch as ClassesUiState.Loaded
        assertEquals(1, captured.sections.size)
    }

    @Test
    fun `channelSections fetches multiple sources concurrently rather than one at a time`() = runTest {
        // Finding 5b: channelSections() used to fetch each configured source sequentially —
        // 12 sources x (a ~1 MB page + a feed, each retried) is plausibly 20-40s of blank
        // spinner on the bike's Wi-Fi. Simulates a slow network per source and asserts on wall
        // clock: two 300ms feed fetches sequentially would take ~600ms+; concurrently, they
        // finish in roughly one source's worth of time. The threshold is generous to avoid CI
        // flakiness while still failing definitively against a sequential implementation.
        sources.add(
            ResolvedSource(ContentSourceType.PLAYLIST, "PLtheme000000001", "Themed Rides"),
            ContentCategory.Workout,
        )
        val fetcher = FeedFetcher { url ->
            when {
                url.contains("feeds/videos.xml") -> {
                    Thread.sleep(300)
                    fixtureXml()
                }
                else -> fixtureXml() // not valid page HTML, so page fetch fails fast and cheap
            }
        }

        val elapsedMs = kotlin.system.measureTimeMillis {
            repository(fetcher).channelSections()
        }

        assertTrue("expected concurrent fetch to finish well under 600ms, took ${elapsedMs}ms", elapsedMs < 500)
    }

    @Test
    fun `refresh can be called again to reload`() = runTest {
        // Counts only feed fetches: the repository also probes the channel page on every
        // call, but that page fetch is retried (and this fixture isn't valid page HTML), so
        // its own call count doesn't cleanly reflect "one network round per refresh."
        var feedCalls = 0
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val viewModel = ClassesViewModel(
            repository(
                FeedFetcher { url ->
                    if (url.contains("feeds/videos.xml")) feedCalls++
                    fixtureXml()
                },
            ),
            manager,
            activeProfileHolder,
            rideRepository,
            routeLoaded = { false },
        )

        viewModel.refresh()
        viewModel.refresh()

        assertEquals(2, feedCalls)
    }

    private fun video(id: String, startable: Boolean = true) = Video(
        id = id,
        title = "$id Ride",
        thumbnailUrl = "https://example.com/$id.jpg",
        channelName = "Chan",
        durationSec = 1800,
        publishedEpochMs = 1000L,
        startable = startable,
    )

    @Test
    fun `startRideForVideo returns false and starts nothing when no profile is active`() = runTest {
        val (viewModel, manager) = viewModel(backgroundScope)

        val started = viewModel.startRideForVideo(video("videoAbc123"))

        assertFalse(started)
        assertEquals(RideSessionState.Idle, manager.state.value)
    }

    @Test
    fun `startRideForVideo starts the session for the active profile`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val (viewModel, manager) = viewModel(backgroundScope)

        val started = viewModel.startRideForVideo(video("videoAbc123"))

        assertTrue(started)
        assertEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `startRideForVideo refuses a non-startable video and notifies the rider`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val (viewModel, manager) = viewModel(backgroundScope)
        val messages = mutableListOf<String>()
        backgroundScope.launch { viewModel.messages.collect { messages.add(it) } }
        runCurrent() // let the collector subscribe before the emit

        val started = viewModel.startRideForVideo(video("feedOnly", startable = false))
        runCurrent() // deliver the emitted message to the collector

        assertFalse(started)
        assertEquals(RideSessionState.Idle, manager.state.value)
        assertEquals(1, messages.size)
    }

    @Test
    fun `takenVideos maps each ridden class to its most recent take`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val (viewModel, _) = viewModel(backgroundScope)

        suspend fun save(videoId: String?, startEpochMs: Long) {
            rideRepository.saveRide(
                Ride(
                    profileId = profileId,
                    startEpochMs = startEpochMs,
                    durationSec = 60,
                    avgCadence = 70,
                    maxCadence = 80,
                    avgPower = 100,
                    maxPower = 120,
                    avgResistance = 30,
                    outputKj = 6.0,
                    calories = 6,
                    videoId = videoId,
                ),
                emptyList(),
            )
        }
        save(videoId = "classA", startEpochMs = 1_000L)
        save(videoId = "classA", startEpochMs = 2_000L)
        save(videoId = "classB", startEpochMs = 3_000L)
        save(videoId = null, startEpochMs = 4_000L) // quick start, never badged

        // takenVideos is a StateFlow fed by Room's observe flow, which emits on Room's own
        // executor off the test scheduler. `.first()` would return whatever snapshot is current
        // — often still the initial emptyMap before the writes above have propagated — which
        // flaked under full-suite load. Await the flow actually reaching the expected state.
        val expected = mapOf("classA" to 2_000L, "classB" to 3_000L)
        assertEquals(expected, viewModel.takenVideos.first { it == expected })
    }

    @Test
    fun `takenVideos is empty when no profile is active`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        assertEquals(emptyMap<String, Long>(), viewModel.takenVideos.first())
    }

    @Test
    fun `filters start at newest with no category or length restriction`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        assertEquals(ClassFilters(), viewModel.filters.value)
    }

    @Test
    fun `setting a length filter switches the screen into grid mode`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)
        viewModel.refresh()

        assertNull(viewModel.gridVideos.value)

        viewModel.setLength(LengthFilter.Over45)

        assertNotNull(viewModel.gridVideos.value)
    }

    @Test
    fun `category filtering applies to the rows in browse mode`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)
        viewModel.refresh()

        viewModel.setCategory(CategoryFilter.Workout)

        // The seeded test source is Scenic, so a Workout filter empties the rows.
        assertTrue(viewModel.rows.value.isEmpty())

        viewModel.setCategory(CategoryFilter.Scenic)

        assertEquals(1, viewModel.rows.value.size)
    }

    @Test
    fun `randomVideo returns null before content has loaded`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        assertNull(viewModel.randomVideo())
    }

    @Test
    fun `randomVideo returns a video from the filtered pool`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)
        viewModel.refresh()

        val picked = viewModel.randomVideo()!!

        assertTrue(viewModel.rows.value.single().videos.any { it.id == picked.id })
    }

    @Test
    fun `randomVideo returns null when the filters match nothing`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)
        viewModel.refresh()

        viewModel.setCategory(CategoryFilter.Workout)

        assertNull(viewModel.randomVideo())
    }

    @Test
    fun `startRandomRide starts a ride for the active profile and returns its video`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val (viewModel, manager) = viewModel(backgroundScope)
        viewModel.refresh()

        val id = viewModel.startRandomRide()

        assertTrue(viewModel.rows.value.single().videos.any { it.id == id })
        assertEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `startRandomRide returns null and starts nothing without a rider or a match`() = runTest {
        val (viewModel, manager) = viewModel(backgroundScope)
        assertNull(viewModel.startRandomRide())
        viewModel.refresh()
        assertNull(viewModel.startRandomRide())
        assertNotEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `randomVideo never returns a non-startable feed-fallback video`() = runTest {
        // Feed-only fetcher: the page is unavailable, so every loaded video is feed-fallback and
        // non-startable. Random Ride must find nothing rather than pick a class that won't start.
        val (viewModel, _) = viewModel(backgroundScope, FeedFetcher { fixtureXml() })
        viewModel.refresh()

        assertTrue(viewModel.rows.value.single().videos.isNotEmpty())
        assertNull(viewModel.randomVideo())
    }

    @Test
    fun `hideTaken drops finished classes from the browse rows`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val (viewModel, _) = viewModel(backgroundScope)
        viewModel.refresh()
        val before = viewModel.rows.value.single().videos.map { it.id }
        assertTrue(before.contains("vidLong00001"))

        rideRepository.saveRide(
            Ride(
                profileId = profileId,
                startEpochMs = 1_000L,
                durationSec = 1200,
                avgCadence = 70,
                maxCadence = 80,
                avgPower = 100,
                maxPower = 120,
                avgResistance = 30,
                outputKj = 6.0,
                calories = 6,
                videoId = "vidLong00001",
            ),
            emptyList(),
        )
        // Wait for the Room-backed taken flow to reflect the saved ride before toggling. That
        // emission originates on Room's own executor, off the test scheduler.
        viewModel.takenVideos.first { it.containsKey("vidLong00001") }
        viewModel.setHideTaken(true)

        // `rows` is a downstream combine(loadedSections, _filters, takenVideos) with its own
        // collector; awaiting `takenVideos` above does not guarantee `rows` has recomputed with
        // the toggled filter yet. Reading `rows.value` synchronously here raced that recompute
        // and flaked under full-suite load, so await `rows` actually dropping the completed
        // class instead of snapshotting it.
        val after = viewModel.rows
            .map { sections -> sections.single().videos.map { it.id } }
            .first { ids -> !ids.contains("vidLong00001") }
        assertEquals(before.size - 1, after.size)
    }

    @Test
    fun `starting a class from Classes emits class_start with the channel and category`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val recording = dev.digitalducktape.openride.core.telemetry.RecordingTelemetry()
        val viewModel = ClassesViewModel(
            repository(), manager, activeProfileHolder, rideRepository, routeLoaded = { false },
            classTelemetry = dev.digitalducktape.openride.core.telemetry.ClassRideTelemetry(recording),
        )
        viewModel.refresh()
        val section = (viewModel.uiState.value as ClassesUiState.Loaded).sections.first { it.videos.isNotEmpty() }

        viewModel.startRideForVideo(section.videos.first())

        assertEquals(
            mapOf(
                "channel" to "Test Cycling Channel", "channel_source" to "custom",
                "category" to "scenic", "source" to "classes",
            ),
            recording.events.single().props(),
        )
    }

    @Test
    fun `starting a class while a ride is already running sends no second class_start`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val recording = dev.digitalducktape.openride.core.telemetry.RecordingTelemetry()
        val viewModel = ClassesViewModel(
            repository(), manager, activeProfileHolder, rideRepository, routeLoaded = { false },
            classTelemetry = dev.digitalducktape.openride.core.telemetry.ClassRideTelemetry(recording),
        )
        viewModel.refresh()
        val section = (viewModel.uiState.value as ClassesUiState.Loaded).sections.first { it.videos.isNotEmpty() }

        viewModel.startRideForVideo(section.videos.first())
        viewModel.startRideForVideo(section.videos.first())

        assertEquals(1, recording.events.count { it.name == "class_start" })
    }
}
