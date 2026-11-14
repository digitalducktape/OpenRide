package dev.digitalducktape.openride.core.content

import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.InMemoryDatabaseRule
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ContentSourceRepositoryTest {

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var repository: ContentSourceRepository

    @Before
    fun setUp() {
        repository = ContentSourceRepository(db.contentSourceDao())
    }

    @Test
    fun `seedIfEmpty inserts the built-in catalog in order`() = runTest {
        repository.seedIfEmpty()

        val sources = repository.observeAll().first()
        assertEquals(ChannelConfig.ALL.size, sources.size)
        assertEquals(ChannelConfig.ALL.map { it.id }, sources.map { it.youtubeId })
        assertTrue(sources.all { it.builtIn })
        assertTrue(sources.none { it.hidden })
        assertEquals(List(sources.size) { it }, sources.map { it.position })
    }

    @Test
    fun `observeAll seeds the built-in catalog on its own, without seedIfEmpty being called first`() = runTest {
        // Regression coverage for Finding 2: seedIfEmpty was previously only ever called from
        // YouTubeContentRepository.channelSections(), so a rider who opened Content Sources
        // (Home -> Profile -> Content sources) before ever visiting Classes saw an empty list
        // on a fresh install — and if they then added a channel there, count() > 0 became true
        // forever and the built-ins were never seeded, with no in-app way to recover them.
        // observeAll() is the Content Sources screen's only way to see the catalog, so seeding
        // reliably has to happen right there rather than depending on some other screen having
        // been opened first.
        val sources = repository.observeAll().first()

        assertEquals(ChannelConfig.ALL.size, sources.size)
        assertTrue(sources.all { it.builtIn })
    }

    @Test
    fun `seedIfEmpty is idempotent`() = runTest {
        repository.seedIfEmpty()
        repository.seedIfEmpty()

        assertEquals(ChannelConfig.ALL.size, repository.observeAll().first().size)
    }

    @Test
    fun `adding a custom source appends it after the built-ins`() = runTest {
        repository.seedIfEmpty()

        val id = repository.add(
            ResolvedSource(ContentSourceType.PLAYLIST, "PLcustom0001", "My Climbs"),
            ContentCategory.Workout,
        )

        val added = repository.getById(id)!!
        assertEquals("PLcustom0001", added.youtubeId)
        assertEquals("My Climbs", added.displayName)
        assertEquals(ContentSourceType.PLAYLIST, added.sourceType)
        assertEquals(ContentCategory.Workout, added.category)
        assertFalse(added.builtIn)
        assertEquals(ChannelConfig.ALL.size, added.position)
    }

    @Test
    fun `hidden sources are excluded from the visible list but kept in the full list`() = runTest {
        repository.seedIfEmpty()
        val first = repository.observeAll().first().first()

        repository.setHidden(first.id, true)

        assertFalse(repository.observeVisible().first().any { it.id == first.id })
        assertTrue(repository.observeAll().first().any { it.id == first.id && it.hidden })
        assertEquals(ChannelConfig.ALL.size - 1, repository.visibleOnce().size)
    }

    @Test
    fun `unhiding restores a source to the visible list`() = runTest {
        repository.seedIfEmpty()
        val first = repository.observeAll().first().first()
        repository.setHidden(first.id, true)

        repository.setHidden(first.id, false)

        assertTrue(repository.observeVisible().first().any { it.id == first.id })
    }

    @Test
    fun `deleteCustom removes a user-added source`() = runTest {
        val id = repository.add(
            ResolvedSource(ContentSourceType.CHANNEL, "UCcustom00001", "Custom"),
            ContentCategory.Scenic,
        )

        repository.deleteCustom(id)

        assertNull(repository.getById(id))
    }

    @Test
    fun `deleteCustom refuses to delete a built-in source`() = runTest {
        repository.seedIfEmpty()
        val builtIn = repository.observeAll().first().first()

        repository.deleteCustom(builtIn.id)

        assertTrue(repository.getById(builtIn.id) != null)
    }

    @Test
    fun `adding a source that already exists does not duplicate it`() = runTest {
        repository.seedIfEmpty()
        val existing = ChannelConfig.ALL.first()

        repository.add(
            ResolvedSource(ContentSourceType.CHANNEL, existing.id, existing.displayName),
            ContentCategory.Scenic,
        )

        assertEquals(
            1,
            repository.observeAll().first().count { it.youtubeId == existing.id },
        )
    }
}
