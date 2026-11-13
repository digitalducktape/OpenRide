package dev.digitalducktape.openride.core.backup

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.telemetry.AutoBackupFailed
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.data.ProfileRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Drives [AutoBackupManager] on a real scope with real (short) delays rather than a
 * `TestScope`: the manager's work is Room I/O, which runs on Room's own executor and so
 * doesn't complete within virtual time — a `runCurrent()`-style test passes vacuously
 * whether the manager works or not. Assertions therefore poll via [awaitUntil].
 */
@RunWith(AndroidJUnit4::class)
class AutoBackupManagerTest {

    /** In-memory [AutoBackupStore]: one slot, overwritten on every write. */
    private class FakeStore(@Volatile var content: String? = null) : AutoBackupStore {
        @Volatile
        var writeCount = 0

        override fun write(json: String): Boolean {
            content = json
            writeCount++
            return true
        }

        override fun readLatest(): String? = content
    }

    private lateinit var db: OpenRideDatabase
    private lateinit var profileRepository: ProfileRepository
    private lateinit var backupRepository: BackupRepository
    private lateinit var scope: CoroutineScope

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            OpenRideDatabase::class.java,
        ).build()
        profileRepository = ProfileRepository(db.profileDao())
        backupRepository = BackupRepository(db, db.profileDao(), db.rideDao()) { 1_700_000_000_000L }
        scope = CoroutineScope(SupervisorJob())
    }

    @After
    fun tearDown() {
        scope.cancel()
        db.close()
    }

    @Test
    fun `an empty database is restored from the latest automatic backup on start`() = runBlocking {
        // A backup taken by the "previous install", the one thing left after an update.
        val store = FakeStore(
            json(
                snapshot(
                    Profile(id = 4L, name = "Ed", avatarEmoji = "🚴", avatarColor = 1, weightKg = 80.0, ftp = 220),
                ),
            ),
        )

        manager(store, MutableStateFlow(0)).start()

        awaitUntil("the backed-up profile is restored") {
            profileRepository.observeProfiles().first().map { it.name } == listOf("Ed")
        }
        // Ids are preserved, so restored rides still point at the right rider.
        assertEquals(4L, profileRepository.observeProfiles().first().single().id)
    }

    @Test
    fun `a non-empty database is never overwritten by the stored backup`() = runBlocking {
        profileRepository.createProfile(
            Profile(name = "OnThisDevice", avatarEmoji = "🔥", avatarColor = 2, weightKg = null, ftp = null),
        )
        val store = FakeStore(
            json(snapshot(Profile(id = 9L, name = "Stale", avatarEmoji = "🚴", avatarColor = 1, weightKg = null, ftp = null))),
        )

        manager(store, MutableStateFlow(0)).start()
        // Wait for the manager to actually reach its steady state (it backs the live data up
        // over the stale file), so this can't pass merely by asserting too early.
        awaitUntil("the manager finishes its start-up pass") { store.writeCount > 0 }

        assertEquals(
            listOf("OnThisDevice"),
            profileRepository.observeProfiles().first().map { it.name },
        )
    }

    @Test
    fun `existing data is captured on first run when no automatic backup exists yet`() = runBlocking {
        profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 1, weightKg = null, ftp = null),
        )
        val store = FakeStore(content = null)

        manager(store, MutableStateFlow(0)).start()

        awaitUntil("the first automatic backup is written") { store.content != null }
        assertTrue(store.content!!.contains("\"Ed\""))
    }

    @Test
    fun `an empty database never overwrites the stored backup`() = runBlocking {
        // The dangerous launch: no local data, and the stored backup didn't restore.
        val store = FakeStore(content = "this is not a backup file")

        manager(store, MutableStateFlow(0)).start()
        delay(DEBOUNCE_MS * 4)

        assertEquals("this is not a backup file", store.content)
        assertEquals(0, store.writeCount)
    }

    @Test
    fun `a data change writes a fresh backup after the debounce settles`() = runBlocking {
        val changes = MutableStateFlow(0)
        val store = FakeStore(json(snapshot()))
        manager(store, changes).start()

        profileRepository.createProfile(
            Profile(name = "Later", avatarEmoji = "⚡", avatarColor = 3, weightKg = null, ftp = null),
        )
        changes.value = 1

        awaitUntil("the new profile reaches the automatic backup") {
            store.content?.contains("\"Later\"") == true
        }
    }

    @Test
    fun `a burst of changes collapses into a single write`() = runBlocking {
        val changes = MutableStateFlow(0)
        val store = FakeStore(json(snapshot()))
        profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 1, weightKg = null, ftp = null),
        )
        manager(store, changes).start()
        // Measure from the settled start-up write, not from zero.
        awaitUntil("the start-up write lands") { store.writeCount >= 1 }
        delay(DEBOUNCE_MS * 4)
        val settled = store.writeCount

        repeat(5) { changes.value = it + 1 }
        awaitUntil("the debounced write lands") { store.writeCount > settled }
        delay(DEBOUNCE_MS * 4)

        assertEquals(settled + 1, store.writeCount)
    }

    @Test
    fun `an unreadable stored backup leaves the database untouched`() = runBlocking {
        val store = FakeStore(content = "this is not a backup file")

        manager(store, MutableStateFlow(0)).start()
        // The manager survives the parse failure rather than crashing its scope.
        delay(DEBOUNCE_MS * 4)

        assertTrue(profileRepository.observeProfiles().first().isEmpty())
    }

    /** Polls [condition] until it holds, failing with [description] if it never does. */
    private suspend fun awaitUntil(description: String, condition: suspend () -> Boolean) {
        val satisfied = withTimeoutOrNull(AWAIT_TIMEOUT_MS) {
            while (!condition()) delay(20)
            true
        }
        assertNotNull("timed out waiting until $description", satisfied)
    }

    private fun manager(
        store: AutoBackupStore,
        changes: MutableStateFlow<Int>,
        telemetry: dev.digitalducktape.openride.core.telemetry.Telemetry = dev.digitalducktape.openride.core.telemetry.NoOpTelemetry,
    ) = AutoBackupManager(
        backupRepository = backupRepository,
        store = store,
        scope = scope,
        dataChanges = changes,
        isDatabaseEmpty = {
            db.profileDao().getAllOnce().isEmpty() && db.rideDao().getAllRidesOnce().isEmpty()
        },
        debounceMs = DEBOUNCE_MS,
        telemetry = telemetry,
    )

    private class FailingStore(private val throwing: Boolean) : AutoBackupStore {
        @Volatile
        var attempts = 0
        override fun write(json: String): Boolean {
            attempts++
            if (throwing) error("disk full")
            return false
        }
        override fun readLatest(): String? = null
    }

    @Test
    fun failureReportedOncePerProcess() = runBlocking {
        val telemetry = RecordingTelemetry()
        val changes = MutableStateFlow(0)
        profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 1, weightKg = null, ftp = null),
        )
        val store = FailingStore(throwing = true)
        manager(store, changes, telemetry).start()
        awaitUntil("the first write fails") { store.attempts >= 1 }

        changes.value = 1
        awaitUntil("a second write fails") { store.attempts >= 2 }
        delay(DEBOUNCE_MS * 3)

        assertEquals(listOf(AutoBackupFailed), telemetry.events)
    }

    @Test
    fun `a store that refuses the write counts as a failure`() = runBlocking {
        val telemetry = RecordingTelemetry()
        profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 1, weightKg = null, ftp = null),
        )
        val store = FailingStore(throwing = false)
        manager(store, MutableStateFlow(0), telemetry).start()

        awaitUntil("the failure is reported") { telemetry.events.isNotEmpty() }

        assertEquals(listOf(AutoBackupFailed), telemetry.events)
    }

    @Test
    fun `restoring on a fresh install reports nothing`() = runBlocking {
        val telemetry = RecordingTelemetry()
        val store = FakeStore(json(snapshot(Profile(name = "Old", avatarEmoji = "🚴", avatarColor = 1, weightKg = null, ftp = null))))
        manager(store, MutableStateFlow(0), telemetry).start()

        awaitUntil("the backup is restored") { profileRepository.observeProfiles().first().isNotEmpty() }
        delay(DEBOUNCE_MS * 3)

        assertEquals(emptyList<Any>(), telemetry.events)
    }

    private fun snapshot(vararg profiles: Profile) = BackupSnapshot(
        exportedAtEpochMs = 1L,
        profiles = profiles.map { it.toBackup() },
        rides = emptyList(),
        samples = emptyList(),
    )

    private fun json(snapshot: BackupSnapshot): String =
        JSON.encodeToString(BackupSnapshot.serializer(), snapshot)

    private companion object {
        const val DEBOUNCE_MS = 100L
        const val AWAIT_TIMEOUT_MS = 10_000L
        val JSON = Json { encodeDefaults = true }
    }
}
