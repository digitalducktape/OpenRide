@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.ui.creator

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.content.ContentCache
import dev.digitalducktape.openride.core.content.ContentCategory
import dev.digitalducktape.openride.core.content.ContentSourceRepository
import dev.digitalducktape.openride.core.content.ContentSourceType
import dev.digitalducktape.openride.core.content.FeedFetcher
import dev.digitalducktape.openride.core.content.ResolvedSource
import dev.digitalducktape.openride.core.content.YouTubeContentRepository
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import java.io.IOException
import java.io.InputStream
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class CreatorViewModelTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private lateinit var db: OpenRideDatabase
    private lateinit var sources: ContentSourceRepository
    private lateinit var profileRepository: ProfileRepository
    private lateinit var rideRepository: RideRepository
    private lateinit var activeProfileHolder: ActiveProfileHolder
    private var sourceId = 0L

    private fun readFixture(name: String): String =
        requireNotNull(javaClass.classLoader?.getResourceAsStream("fixtures/$name"))
            .bufferedReader().use { it.readText() }

    private fun feedXml(): InputStream =
        requireNotNull(javaClass.classLoader?.getResourceAsStream("fixtures/sample_atom_feed.xml"))

    @Before
    fun setUp() = runTest {
        db = Room.inMemoryDatabaseBuilder(context, OpenRideDatabase::class.java).build()
        sources = ContentSourceRepository(db.contentSourceDao())
        profileRepository = ProfileRepository(db.profileDao())
        rideRepository = RideRepository(db, db.rideDao())
        activeProfileHolder = ActiveProfileHolder(context)
        sourceId = sources.add(
            ResolvedSource(ContentSourceType.CHANNEL, "UCTestChannel00000000", "Test Cycling Channel"),
            ContentCategory.Workout,
        )
        context.filesDir.resolve("content_cache").deleteRecursively()
    }

    @After
    fun tearDown() = db.close()

    private fun fetcher(playlistsFail: Boolean = false) = FeedFetcher { url ->
        when {
            url.contains("/playlists") ->
                if (playlistsFail) throw IOException("down")
                else readFixture("channel_playlists_page.html").byteInputStream()
            url.contains("feeds/videos.xml") -> feedXml()
            else -> readFixture("channel_videos_page.html").byteInputStream()
        }
    }

    private fun viewModel(
        scope: CoroutineScope,
        fetcher: FeedFetcher = fetcher(),
        id: Long = sourceId,
    ): Pair<CreatorViewModel, RideSessionManager> {
        val repository = YouTubeContentRepository(
            context = context,
            sourceRepository = sources,
            fetcher = fetcher,
            cache = ContentCache(context),
        )
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, scope)
        return CreatorViewModel(repository, manager, activeProfileHolder, rideRepository, id, routeLoaded = { false }) to manager
    }

    @Test
    fun `starts in Loading before load is called`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        assertTrue(viewModel.uiState.value is CreatorUiState.Loading)
    }

    @Test
    fun `load exposes the creator's latest videos and playlist rows`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        viewModel.load()

        val loaded = viewModel.uiState.value as CreatorUiState.Loaded
        assertEquals("Test Cycling Channel", loaded.displayName)
        assertEquals(listOf("vidLong00001", "vidNoDur0003"), loaded.latest.map { it.id })
        assertEquals(
            listOf("PLtheme000000001", "PLtheme000000002"),
            loaded.playlistRows.map { it.playlist.id },
        )
        assertFalse(loaded.refreshFailed)
    }

    @Test
    fun `playlist rows start empty and unloaded`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)

        viewModel.load()

        val loaded = viewModel.uiState.value as CreatorUiState.Loaded
        assertTrue(loaded.playlistRows.all { it.videos.isEmpty() && !it.isLoading && !it.loadFailed })
    }

    @Test
    fun `loadPlaylist fills in that row's videos and leaves the others alone`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)
        viewModel.load()

        viewModel.loadPlaylist("PLtheme000000001")

        val rows = (viewModel.uiState.value as CreatorUiState.Loaded).playlistRows
        assertEquals(listOf("vidLong00001", "vidNoDur0003"), rows.first().videos.map { it.id })
        assertFalse(rows.first().isLoading)
        assertTrue(rows.last().videos.isEmpty())
    }

    @Test
    fun `loadPlaylist flags a row that could not be loaded`() = runTest {
        val failing = FeedFetcher { url ->
            when {
                // Both the playlist's page and its atom feed must fail here, or the repository's
                // page+feed fallback (YouTubeContentRepository.fetchVideos) quietly serves the
                // feed alone and the row never actually fails to load.
                url.contains("playlist?list=") || url.contains("playlist_id=") -> throw IOException("down")
                url.contains("/playlists") -> readFixture("channel_playlists_page.html").byteInputStream()
                url.contains("feeds/videos.xml") -> feedXml()
                else -> readFixture("channel_videos_page.html").byteInputStream()
            }
        }
        val (viewModel, _) = viewModel(backgroundScope, failing)
        viewModel.load()

        viewModel.loadPlaylist("PLtheme000000001")

        val row = (viewModel.uiState.value as CreatorUiState.Loaded).playlistRows.first()
        assertTrue(row.loadFailed)
        assertFalse(row.isLoading)
    }

    @Test
    fun `cancelling a playlist load clears isLoading instead of leaving it stuck`() = runTest {
        // Finding 4: if the shelf scrolls off-screen (or the rider navigates away and back to
        // a retained view model) mid-fetch, the driving LaunchedEffect is cancelled and the
        // final updateRow call in the old implementation never ran — the row stayed
        // isLoading = true forever, and the screen's `!row.isLoading` guard then refused to
        // ever retry it. This blocks the playlist page fetch on a real latch (a genuine
        // suspension point inside contentRepository.playlistVideos' withContext(Dispatchers.IO))
        // so the cancellation happens truly mid-flight, not after the fetch already finished.
        val started = CountDownLatch(1)
        val release = CountDownLatch(1)
        val blockingFetcher = FeedFetcher { url ->
            if (url.contains("playlist?list=") || url.contains("playlist_id=")) {
                started.countDown()
                release.await()
            }
            when {
                url.contains("/playlists") -> readFixture("channel_playlists_page.html").byteInputStream()
                url.contains("feeds/videos.xml") -> feedXml()
                else -> readFixture("channel_videos_page.html").byteInputStream()
            }
        }
        val (viewModel, _) = viewModel(backgroundScope, blockingFetcher)
        viewModel.load()

        val loaderScope = CoroutineScope(Job())
        val job = loaderScope.launch { viewModel.loadPlaylist("PLtheme000000001") }
        assertTrue(started.await(5, TimeUnit.SECONDS))
        val duringLoad = (viewModel.uiState.value as CreatorUiState.Loaded).playlistRows.first()
        assertTrue(duringLoad.isLoading)

        job.cancel()
        release.countDown()
        job.join()

        val afterCancel = (viewModel.uiState.value as CreatorUiState.Loaded).playlistRows.first()
        assertFalse(afterCancel.isLoading)
        loaderScope.cancel()
    }

    @Test
    fun `loadPlaylist is a no-op for a playlist this creator does not have`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope)
        viewModel.load()
        val before = (viewModel.uiState.value as CreatorUiState.Loaded).playlistRows

        viewModel.loadPlaylist("PLnotHere0001")

        assertEquals(before, (viewModel.uiState.value as CreatorUiState.Loaded).playlistRows)
    }

    @Test
    fun `a creator page still loads when the playlists tab fails`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope, fetcher(playlistsFail = true))

        viewModel.load()

        val loaded = viewModel.uiState.value as CreatorUiState.Loaded
        assertEquals(2, loaded.latest.size)
        assertTrue(loaded.playlistRows.isEmpty())
    }

    @Test
    fun `an unknown source id resolves to NotFound`() = runTest {
        val (viewModel, _) = viewModel(backgroundScope, id = 9999L)

        viewModel.load()

        assertEquals(CreatorUiState.NotFound, viewModel.uiState.value)
    }

    @Test
    fun `startRideForVideo starts a session for the active profile`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val (viewModel, manager) = viewModel(backgroundScope)

        assertTrue(viewModel.startRideForVideo("vidLong00001"))
        assertEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `startRideForVideo returns false with no active profile`() = runTest {
        val (viewModel, manager) = viewModel(backgroundScope)

        assertFalse(viewModel.startRideForVideo("vidLong00001"))
        assertEquals(RideSessionState.Idle, manager.state.value)
    }
}
