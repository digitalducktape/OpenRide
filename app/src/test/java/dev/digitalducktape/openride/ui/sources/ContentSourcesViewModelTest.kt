package dev.digitalducktape.openride.ui.sources

import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.content.ChannelHandleResolver
import dev.digitalducktape.openride.core.content.ContentCategory
import dev.digitalducktape.openride.core.content.ContentSourceRepository
import dev.digitalducktape.openride.core.content.ContentSourceType
import dev.digitalducktape.openride.core.content.FeedFetcher
import dev.digitalducktape.openride.core.content.HttpStatusException
import dev.digitalducktape.openride.core.data.InMemoryDatabaseRule
import java.io.IOException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ContentSourcesViewModelTest {

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var repository: ContentSourceRepository

    private val channelPage = """
        <html><head><title>Kaleigh Cohen Cycling - YouTube</title></head>
        <body><script>{"externalId":"UChY_9WJx0saa0St48lSdytQ"}</script></body></html>
    """.trimIndent()

    @Before
    fun setUp() {
        repository = ContentSourceRepository(db.contentSourceDao())
    }

    private fun viewModel(fetcher: FeedFetcher = FeedFetcher { channelPage.byteInputStream() }) =
        ContentSourcesViewModel(repository, ChannelHandleResolver(fetcher))

    @Test
    fun `add state starts idle`() = runTest {
        assertEquals(AddSourceState.Idle, viewModel().addState.value)
    }

    @Test
    fun `sources exposes the built-in catalog on a fresh database without Classes ever having run`() = runTest {
        // Finding 2: seedIfEmpty used to be called only from
        // YouTubeContentRepository.channelSections(), so a rider who opened this screen
        // (Home -> Profile -> Content sources) before ever visiting the Classes tab saw an
        // empty list on a fresh install. This constructs the view model straight from an empty
        // database — nothing here touches YouTubeContentRepository or its channelSections() —
        // so the only way this can see the 12 built-ins is if observing `sources` seeds them.
        val freshViewModel = viewModel()

        val sources = freshViewModel.sources.first()

        assertEquals(12, sources.size)
        assertTrue(sources.all { it.builtIn })
    }

    @Test
    fun `resolving a handle exposes the resolved source for confirmation`() = runTest {
        val viewModel = viewModel()

        viewModel.resolve("@kaleigh")

        val resolved = viewModel.addState.value as AddSourceState.Resolved
        assertEquals("UChY_9WJx0saa0St48lSdytQ", resolved.source.youtubeId)
        assertEquals("Kaleigh Cohen Cycling", resolved.source.displayName)
        assertEquals(ContentSourceType.CHANNEL, resolved.source.sourceType)
    }

    @Test
    fun `resolving does not add anything until confirmed`() = runTest {
        val viewModel = viewModel()

        viewModel.resolve("@kaleigh")

        // observeAll() now seeds the built-in catalog on its own (Finding 2), so an untouched
        // database is no longer an empty list — the thing this test actually cares about is
        // that resolving alone doesn't persist a *rider-added* source.
        assertTrue(repository.observeAll().first().none { !it.builtIn })
    }

    @Test
    fun `confirmAdd saves the resolved source with the chosen category`() = runTest {
        val viewModel = viewModel()
        viewModel.resolve("@kaleigh")

        viewModel.confirmAdd(ContentCategory.Scenic)

        val saved = repository.observeAll().first().single()
        assertEquals("UChY_9WJx0saa0St48lSdytQ", saved.youtubeId)
        assertEquals(ContentCategory.Scenic, saved.category)
        assertFalse(saved.builtIn)
        assertEquals(AddSourceState.Idle, viewModel.addState.value)
    }

    @Test
    fun `confirmAdd with nothing resolved does nothing`() = runTest {
        val viewModel = viewModel()

        viewModel.confirmAdd(ContentCategory.Workout)

        // See the comment in `resolving does not add anything until confirmed` above: observing
        // the built-in catalog is not "adding something," so this checks specifically for the
        // absence of a rider-added row rather than an empty list.
        assertTrue(repository.observeAll().first().none { !it.builtIn })
    }

    @Test
    fun `a failed resolution surfaces a message and saves nothing`() = runTest {
        val viewModel = viewModel(FeedFetcher { throw IOException("offline") })

        viewModel.resolve("@kaleigh")

        val failed = viewModel.addState.value as AddSourceState.Failed
        assertEquals("No connection — try again", failed.message)
        assertTrue(repository.observeAll().first().none { !it.builtIn })
    }

    @Test
    fun `a page without a channel id reports not found`() = runTest {
        val viewModel = viewModel(FeedFetcher { "<html>nothing</html>".byteInputStream() })

        viewModel.resolve("@ghost")

        val failed = viewModel.addState.value as AddSourceState.Failed
        assertEquals("Couldn't find that channel or playlist", failed.message)
    }

    @Test
    fun `a non-2xx HTTP response reports not found, not offline`() = runTest {
        // A 404 for a mistyped handle is not a connectivity failure — it must not be
        // reported as "No connection", which would send the rider retrying a lookup that
        // can never succeed. Regression coverage for that mix-up.
        val viewModel = viewModel(FeedFetcher { throw HttpStatusException(404, "HTTP 404") })

        viewModel.resolve("@typo-handle")

        val failed = viewModel.addState.value as AddSourceState.Failed
        assertEquals("Couldn't find that channel or playlist", failed.message)
    }

    @Test
    fun `cancelAdd clears a pending resolution`() = runTest {
        val viewModel = viewModel()
        viewModel.resolve("@kaleigh")

        viewModel.cancelAdd()

        assertEquals(AddSourceState.Idle, viewModel.addState.value)
    }

    @Test
    fun `hiding and unhiding a source is reflected in the list`() = runTest {
        val viewModel = viewModel()
        repository.seedIfEmpty()
        val source = viewModel.sources.first().first()

        viewModel.setHidden(source.id, true)
        assertTrue(viewModel.sources.first().single { it.id == source.id }.hidden)

        viewModel.setHidden(source.id, false)
        assertFalse(viewModel.sources.first().single { it.id == source.id }.hidden)
    }

    @Test
    fun `deleting a custom source removes it from the list`() = runTest {
        val viewModel = viewModel()
        viewModel.resolve("@kaleigh")
        viewModel.confirmAdd(ContentCategory.Workout)
        val added = viewModel.sources.first().single()

        viewModel.deleteCustom(added.id)

        assertTrue(viewModel.sources.first().none { it.id == added.id })
    }

    @Test
    fun `deleting the only source re-seeds the built-in catalog instead of leaving it empty forever`() = runTest {
        // Before Finding 2's fix, adding a custom source before the built-ins were ever seeded
        // made seedIfEmpty's `count() > 0` guard true permanently — deleting that source left
        // an empty catalog with no in-app way to recover the built-ins. Now that observing the
        // list re-checks and re-seeds a genuinely empty database every time, this same sequence
        // instead recovers the built-in catalog.
        val viewModel = viewModel()
        viewModel.resolve("@kaleigh")
        viewModel.confirmAdd(ContentCategory.Workout)
        val added = viewModel.sources.first().single()

        viewModel.deleteCustom(added.id)

        val afterDelete = viewModel.sources.first()
        assertEquals(12, afterDelete.size)
        assertTrue(afterDelete.all { it.builtIn })
    }

    @Test
    fun `confirmAdd emits content_source_added with the resolved name, not the typed text`() = runTest {
        val recording = dev.digitalducktape.openride.core.telemetry.RecordingTelemetry()
        val viewModel = ContentSourcesViewModel(
            repository, ChannelHandleResolver(FeedFetcher { channelPage.byteInputStream() }), recording,
        )
        viewModel.resolve("@kaleigh")
        viewModel.confirmAdd(ContentCategory.Scenic)

        assertEquals(
            mapOf("channel" to "@kaleigh", "kind" to "channel"),
            recording.events.single().props(),
        )
    }

    @Test
    fun `a source that was not added emits nothing`() = runTest {
        val recording = dev.digitalducktape.openride.core.telemetry.RecordingTelemetry()
        val viewModel = ContentSourcesViewModel(
            repository, ChannelHandleResolver(FeedFetcher { channelPage.byteInputStream() }), recording,
        )
        viewModel.confirmAdd(ContentCategory.Scenic)
        assertTrue(recording.events.isEmpty())
    }
}
