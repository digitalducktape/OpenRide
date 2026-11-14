package dev.digitalducktape.openride.core.content

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.InMemoryDatabaseRule
import java.io.IOException
import java.io.InputStream
import kotlin.coroutines.cancellation.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class YouTubeContentRepositoryTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var sources: ContentSourceRepository

    /** Matches the ids in `fixtures/channel_videos_page.html`: long / short / no-duration. */
    private fun pageHtml() = readFixture("channel_videos_page.html")
    private fun playlistsHtml() = readFixture("channel_playlists_page.html")

    private fun readFixture(name: String): String =
        requireNotNull(javaClass.classLoader?.getResourceAsStream("fixtures/$name"))
            .bufferedReader().use { it.readText() }

    private fun feedXml(): InputStream =
        requireNotNull(javaClass.classLoader?.getResourceAsStream("fixtures/sample_atom_feed.xml"))

    @Before
    fun setUp() = runTest {
        sources = ContentSourceRepository(db.contentSourceDao())
        sources.add(
            ResolvedSource(ContentSourceType.CHANNEL, "UCTestChannel00000000", "Test Cycling Channel"),
            ContentCategory.Scenic,
        )
        context.filesDir.resolve("content_cache").deleteRecursively()
    }

    /** Serves page HTML for `/videos` and `/playlists` URLs, and the Atom fixture for feeds. */
    private fun fetcher(
        page: (() -> String)? = { pageHtml() },
        feed: (() -> InputStream)? = { feedXml() },
        playlists: () -> String = { playlistsHtml() },
    ) = FeedFetcher { url ->
        when {
            url.contains("/playlists") -> playlists().byteInputStream()
            url.contains("feeds/videos.xml") ->
                feed?.invoke() ?: throw IOException("feed down")
            else -> (page?.invoke() ?: throw IOException("page down")).byteInputStream()
        }
    }

    private fun repository(fetcher: FeedFetcher) = YouTubeContentRepository(
        context = context,
        sourceRepository = sources,
        fetcher = fetcher,
        cache = ContentCache(context),
    )

    @Test
    fun `page videos carry durations and drop anything under ten minutes`() = runTest {
        val section = repository(fetcher()).channelSections().single()

        assertFalse(section.refreshFailed)
        // vidShort0002 is 5:04 and must be filtered out; the LIVE tile has no known duration
        // and is kept.
        assertEquals(listOf("vidLong00001", "vidNoDur0003"), section.videos.map { it.id })
        assertEquals(1103, section.videos.first().durationSec)
    }

    @Test
    fun `section reports the source row it came from`() = runTest {
        val source = sources.visibleOnce().single()

        val section = repository(fetcher()).channelSections().single()

        assertEquals(source.id, section.sourceId)
        assertEquals("UCTestChannel00000000", section.channelId)
        assertEquals("Test Cycling Channel", section.channelName)
        assertEquals(ContentCategory.Scenic, section.category)
    }

    @Test
    fun `videos absent from the page listing are dropped as non-public`() = runTest {
        // The Atom fixture's entries (testVideoOne1, testVideoTwo2, noThumbVideo3 — see
        // sample_atom_feed.xml) are not present in the page fixture, so a successful page
        // fetch means none of them survive — that's the members-only rule. This asserts the
        // concrete feed-only ids by name so the test would actually fail if the merge ever
        // unioned the page and feed lists instead of using the page as authoritative.
        val section = repository(fetcher()).channelSections().single()

        val feedOnlyIds = listOf("testVideoOne1", "testVideoTwo2", "noThumbVideo3")
        assertEquals(listOf("vidLong00001", "vidNoDur0003"), section.videos.map { it.id })
        assertTrue(section.videos.none { it.id in feedOnlyIds })
    }

    @Test
    fun `a failed page fetch degrades to the feed with unknown durations`() = runTest {
        val section = repository(fetcher(page = null)).channelSections().single()

        assertFalse(section.refreshFailed)
        assertEquals(3, section.videos.size)
        assertTrue(section.videos.all { it.durationSec == null })
    }

    @Test
    fun `feed-fallback videos are marked non-startable`() = runTest {
        // With no page to confirm them, feed-only videos can't be verified as public (the feed
        // carries no members-only marker), so they must not be startable.
        val section = repository(fetcher(page = null)).channelSections().single()

        assertTrue(section.videos.isNotEmpty())
        assertTrue(section.videos.none { it.startable })
    }

    @Test
    fun `page-verified videos are startable`() = runTest {
        val section = repository(fetcher()).channelSections().single()

        assertTrue(section.videos.isNotEmpty())
        assertTrue(section.videos.all { it.startable })
    }

    @Test
    fun `both fetches failing with no cache yields an empty section flagged as failed`() = runTest {
        val section = repository(fetcher(page = null, feed = null)).channelSections().single()

        assertTrue(section.refreshFailed)
        assertTrue(section.videos.isEmpty())
    }

    @Test
    fun `both fetches failing falls back to the cached list`() = runTest {
        repository(fetcher()).channelSections() // primes the cache

        val section = repository(fetcher(page = null, feed = null)).channelSections().single()

        assertTrue(section.refreshFailed)
        assertEquals(listOf("vidLong00001", "vidNoDur0003"), section.videos.map { it.id })
    }

    /** A page with exactly one video, under the ten-minute floor, and nothing else. */
    private fun tooShortPageHtml() = """
        <!DOCTYPE html><html><body>
        <script nonce="x">var ytInitialData = {"contents":{"tabs":[{"tabRenderer":{"content":{"richGridRenderer":{"contents":[
        {"richItemRenderer":{"content":{"lockupViewModel":{
          "contentId":"vidTooShort1","contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
          "contentImage":{"thumbnailViewModel":{
            "image":{"sources":[{"url":"https://i.ytimg.com/vi/vidTooShort1/hqdefault.jpg","width":168}]},
            "overlays":[{"thumbnailBottomOverlayViewModel":{"badges":[{"thumbnailBadgeViewModel":{"text":"3:00"}}]}}]}},
          "metadata":{"lockupMetadataViewModel":{
            "title":{"content":"Too Short To Ride"},
            "metadata":{"contentMetadataViewModel":{"metadataRows":[{"metadataParts":[
              {"text":{"content":"1 day ago"}}]}]}}}}}}}}
        ]}}}}]}};</script>
        </body></html>
    """.trimIndent()

    @Test
    fun `a fetch that succeeds but filters down to nothing keeps the existing cache`() = runTest {
        // Primes the cache with the normal fixture's two rideable videos.
        repository(fetcher()).channelSections()

        // A perfectly healthy fetch this time — page and feed both readable — but the only
        // video on the page is under the ten-minute floor, so the filtered result is empty.
        // This is exactly as ambiguous as a broken parse (Finding 1): both look like "nothing
        // to show." Overwriting the last-known-good cache with that empty result would destroy
        // the offline fallback for good, so the stale cache must win instead.
        val section = repository(fetcher(page = { tooShortPageHtml() })).channelSections().single()

        assertEquals(listOf("vidLong00001", "vidNoDur0003"), section.videos.map { it.id })
        // videos is a last-known cached list rather than this fetch's own (empty) result, so
        // this matches ChannelSection.refreshFailed's documented contract.
        assertTrue(section.refreshFailed)
    }

    @Test
    fun `a fetch that filters down to nothing does not overwrite the on-disk cache`() = runTest {
        repository(fetcher()).channelSections() // primes the cache

        repository(fetcher(page = { tooShortPageHtml() })).channelSections() // must not blank the cache

        // Everything down now: if the empty filtered result above had been written to the
        // cache, this would come back empty too instead of the original videos.
        val section = repository(fetcher(page = null, feed = null)).channelSections().single()
        assertEquals(listOf("vidLong00001", "vidNoDur0003"), section.videos.map { it.id })
    }

    @Test
    fun `a transient failure is retried once before falling back`() = runTest {
        var attempts = 0
        val flaky = FeedFetcher { url ->
            if (url.contains("feeds/videos.xml")) feedXml()
            else {
                attempts++
                if (attempts == 1) throw IOException("HTTP 500") else pageHtml().byteInputStream()
            }
        }

        val section = repository(flaky).channelSections().single()

        assertEquals(2, attempts)
        assertFalse(section.refreshFailed)
        assertEquals(1103, section.videos.first().durationSec)
    }

    @Test
    fun `hidden sources are not fetched`() = runTest {
        val source = sources.visibleOnce().single()
        sources.setHidden(source.id, true)

        assertTrue(repository(fetcher()).channelSections().isEmpty())
    }

    @Test
    fun `creatorContent returns the latest videos and the creator's playlists`() = runTest {
        val source = sources.visibleOnce().single()

        val content = repository(fetcher()).creatorContent(source.id)!!

        assertEquals("Test Cycling Channel", content.displayName)
        assertEquals(listOf("vidLong00001", "vidNoDur0003"), content.latest.map { it.id })
        assertEquals(listOf("PLtheme000000001", "PLtheme000000002"), content.playlists.map { it.id })
        assertFalse(content.refreshFailed)
    }

    @Test
    fun `creatorContent returns null for an unknown source id`() = runTest {
        assertNull(repository(fetcher()).creatorContent(9999L))
    }

    @Test
    fun `creatorContent still lists videos when the playlists tab fails`() = runTest {
        val fetcher = FeedFetcher { url ->
            when {
                url.contains("/playlists") -> throw IOException("playlists down")
                url.contains("feeds/videos.xml") -> feedXml()
                else -> pageHtml().byteInputStream()
            }
        }
        val source = sources.visibleOnce().single()

        val content = repository(fetcher).creatorContent(source.id)!!

        assertEquals(2, content.latest.size)
        assertTrue(content.playlists.isEmpty())
    }

    @Test
    fun `playlistVideos applies the same duration filter`() = runTest {
        val videos = repository(fetcher()).playlistVideos("PLtheme000000001", "Themed Rides")

        assertEquals(listOf("vidLong00001", "vidNoDur0003"), videos.map { it.id })
        assertEquals("Themed Rides", videos.first().channelName)
    }

    @Test
    fun `playlistVideos falls back to its own cache after a successful fetch`() = runTest {
        // Prime the cache: a successful fetch of a playlist reached only from a creator's
        // page (never its own content_sources row) must still populate a cache entry keyed
        // by that playlist id, otherwise a later failure has nothing to fall back to.
        repository(fetcher()).playlistVideos("PLtheme000000001", "Themed Rides")

        val videos = repository(fetcher(page = null, feed = null))
            .playlistVideos("PLtheme000000001", "Themed Rides")

        assertEquals(listOf("vidLong00001", "vidNoDur0003"), videos.map { it.id })
    }

    @Test
    fun `a cancelled coroutine propagates instead of falling back to the cache`() = runTest {
        val cancelling = FeedFetcher { throw CancellationException("coroutine cancelled") }

        try {
            repository(cancelling).channelSections()
            fail("expected CancellationException to propagate, not be swallowed into a cache fallback")
        } catch (expected: CancellationException) {
            // expected: cancellation must not be converted into "fetch failed"
        }
    }

    @Test
    fun `a playlist source is fetched from its playlist page`() = runTest {
        val playlistId = sources.add(
            ResolvedSource(ContentSourceType.PLAYLIST, "PLtheme000000001", "Themed Rides"),
            ContentCategory.Workout,
        )
        var requestedPlaylistPage = false
        val fetcher = FeedFetcher { url ->
            if (url.contains("playlist?list=PLtheme000000001")) requestedPlaylistPage = true
            when {
                url.contains("feeds/videos.xml") -> feedXml()
                else -> pageHtml().byteInputStream()
            }
        }

        val sections = repository(fetcher).channelSections()

        assertTrue(requestedPlaylistPage)
        assertEquals(2, sections.size)
        assertEquals(playlistId, sections.last().sourceId)
    }

    @Test
    fun `videos whose title is not a cycling class are dropped`() = runTest {
        // A configured channel is a whole creator, not a spin-only feed: both tiles are long
        // enough to ride, but only the one whose title reads as cycling belongs in the catalog.
        // The sculpt class must not appear.
        val mixedPage = """
            <script>var ytInitialData = {"contents":{"tabs":[{"tabRenderer":{"content":{
              "richGridRenderer":{"contents":[
                {"richItemRenderer":{"content":{"lockupViewModel":{
                  "contentId":"rideVid00001","contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
                  "contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailBottomOverlayViewModel":{
                    "badges":[{"thumbnailBadgeViewModel":{"text":"45:00"}}]}}]}},
                  "metadata":{"lockupMetadataViewModel":{
                    "title":{"content":"45 Minute Endurance Ride"}}}}}}},
                {"richItemRenderer":{"content":{"lockupViewModel":{
                  "contentId":"sculptVid001","contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
                  "contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailBottomOverlayViewModel":{
                    "badges":[{"thumbnailBadgeViewModel":{"text":"45:00"}}]}}]}},
                  "metadata":{"lockupMetadataViewModel":{
                    "title":{"content":"45 MIN SCULPT CLASS | Full Body"}}}}}}}
              ]}}}}]}};</script>
        """.trimIndent()

        val section = repository(fetcher(page = { mixedPage }, feed = null)).channelSections().single()

        assertEquals(listOf("rideVid00001"), section.videos.map { it.id })
    }

    @Test
    fun `a video listed twice on the page is collapsed to a single entry`() = runTest {
        // YouTube pages can list the same video more than once (e.g. a video that is both
        // pinned and appears again in the grid). Two Video objects sharing an id would collide
        // the `key = { it.id }` in the Creator screen's LazyRow and crash Compose with
        // "Key ... was already used", so the repository must deduplicate by id.
        val duplicatePage = """
            <script>var ytInitialData = {"contents":{"tabs":[{"tabRenderer":{"content":{
              "richGridRenderer":{"contents":[
                {"richItemRenderer":{"content":{"lockupViewModel":{
                  "contentId":"dupRideVid01","contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
                  "contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailBottomOverlayViewModel":{
                    "badges":[{"thumbnailBadgeViewModel":{"text":"45:00"}}]}}]}},
                  "metadata":{"lockupMetadataViewModel":{
                    "title":{"content":"45 Minute Endurance Ride"}}}}}}},
                {"richItemRenderer":{"content":{"lockupViewModel":{
                  "contentId":"dupRideVid01","contentType":"LOCKUP_CONTENT_TYPE_VIDEO",
                  "contentImage":{"thumbnailViewModel":{"overlays":[{"thumbnailBottomOverlayViewModel":{
                    "badges":[{"thumbnailBadgeViewModel":{"text":"45:00"}}]}}]}},
                  "metadata":{"lockupMetadataViewModel":{
                    "title":{"content":"45 Minute Endurance Ride"}}}}}}}
              ]}}}}]}};</script>
        """.trimIndent()

        val videos = repository(fetcher(page = { duplicatePage }, feed = null))
            .playlistVideos("PLtheme000000001", "Themed Rides")

        assertEquals(listOf("dupRideVid01"), videos.map { it.id })
    }

    @Test
    fun `a playlist listed twice on the page is collapsed to a single entry`() = runTest {
        // A page listing the same playlist twice would collide the `key = { it.playlist.id }`
        // in the Creator screen's playlist LazyColumn and crash Compose, so the repository must
        // deduplicate playlists by id too.
        val duplicatePlaylists = """
            <script>var ytInitialData = {"contents":{"items":[
              {"lockupViewModel":{"contentId":"PLspin000000001","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST",
                "metadata":{"lockupMetadataViewModel":{"title":{"content":"Spin Classes: Theme Rides"}}}}},
              {"lockupViewModel":{"contentId":"PLspin000000001","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST",
                "metadata":{"lockupMetadataViewModel":{"title":{"content":"Spin Classes: Theme Rides"}}}}}
            ]}};</script>
        """.trimIndent()
        val source = sources.visibleOnce().single()

        val content = repository(fetcher(playlists = { duplicatePlaylists })).creatorContent(source.id)!!

        assertEquals(listOf("PLspin000000001"), content.playlists.map { it.id })
    }

    @Test
    fun `playlists whose title is not a cycling class are dropped`() = runTest {
        val mixedPlaylists = """
            <script>var ytInitialData = {"contents":{"items":[
              {"lockupViewModel":{"contentId":"PLspin000000001","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST",
                "metadata":{"lockupMetadataViewModel":{"title":{"content":"Spin Classes: Theme Rides"}}}}},
              {"lockupViewModel":{"contentId":"PLsculpt00001","contentType":"LOCKUP_CONTENT_TYPE_PLAYLIST",
                "metadata":{"lockupMetadataViewModel":{"title":{"content":"Full Body Sculpt Classes"}}}}}
            ]}};</script>
        """.trimIndent()
        val source = sources.visibleOnce().single()

        val content = repository(fetcher(playlists = { mixedPlaylists })).creatorContent(source.id)!!

        assertEquals(listOf("PLspin000000001"), content.playlists.map { it.id })
    }
}
