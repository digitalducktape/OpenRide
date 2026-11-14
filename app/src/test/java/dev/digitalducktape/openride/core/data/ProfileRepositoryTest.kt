package dev.digitalducktape.openride.core.data

import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class ProfileRepositoryTest {

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var repository: ProfileRepository

    @Before
    fun setUp() {
        repository = ProfileRepository(db.profileDao())
    }

    private fun sampleProfile(name: String = "Ed") = Profile(
        name = name,
        avatarEmoji = "🚴",
        avatarColor = 0xFF00AAFF.toInt(),
        weightKg = 80.0,
        ftp = 220,
    )

    @Test
    fun `create and read a profile by id`() = runTest {
        val id = repository.createProfile(sampleProfile())

        val loaded = repository.getProfile(id)

        requireNotNull(loaded)
        assertEquals("Ed", loaded.name)
        assertEquals(80.0, loaded.weightKg)
        assertEquals(220, loaded.ftp)
    }

    @Test
    fun `optional weight and ftp can be null`() = runTest {
        val id = repository.createProfile(
            Profile(name = "Kid", avatarEmoji = "🤖", avatarColor = 0xFFAA0000.toInt(), weightKg = null, ftp = null),
        )

        val loaded = repository.getProfile(id)

        requireNotNull(loaded)
        assertNull(loaded.weightKg)
        assertNull(loaded.ftp)
    }

    @Test
    fun `observeProfiles reflects inserts, updates, and deletes`() = runTest {
        val id = repository.createProfile(sampleProfile())
        assertEquals(1, repository.observeProfiles().first().size)

        val updated = repository.getProfile(id)!!.copy(ftp = 250)
        repository.updateProfile(updated)
        assertEquals(250, repository.observeProfiles().first().single().ftp)

        repository.deleteProfile(updated)
        assertTrue(repository.observeProfiles().first().isEmpty())
    }

    @Test
    fun `getProfile returns null for an unknown id`() = runTest {
        assertNull(repository.getProfile(id = 999L))
    }
}
