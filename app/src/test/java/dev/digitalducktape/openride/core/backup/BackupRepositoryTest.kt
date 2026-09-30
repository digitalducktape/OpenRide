package dev.digitalducktape.openride.core.backup

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.GameResult
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.data.RideSample
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerializationException
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class BackupRepositoryTest {

    private lateinit var db: OpenRideDatabase
    private lateinit var profileRepository: ProfileRepository
    private lateinit var rideRepository: RideRepository
    private lateinit var backupRepository: BackupRepository

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            OpenRideDatabase::class.java,
        ).build()
        profileRepository = ProfileRepository(db.profileDao())
        rideRepository = RideRepository(db, db.rideDao())
        backupRepository = BackupRepository(db, db.profileDao(), db.rideDao()) { 1_700_000_000_000L }
    }

    @After
    fun tearDown() {
        db.close()
    }

    private suspend fun seedData(): Triple<Long, Long, List<RideSample>> {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = 80.0, ftp = 220),
        )
        val samples = listOf(
            RideSample(rideId = 0L, tSec = 0, cadence = 85, resistance = 45, power = 120),
            RideSample(rideId = 0L, tSec = 1, cadence = 90, resistance = 50, power = 150),
        )
        val rideId = rideRepository.saveRide(
            Ride(
                profileId = profileId,
                startEpochMs = 1_600_000_000_000L,
                durationSec = 2,
                avgCadence = 87,
                maxCadence = 90,
                avgPower = 135,
                maxPower = 150,
                avgResistance = 47,
                outputKj = 0.27,
                calories = 26,
            ),
            samples,
        )
        return Triple(profileId, rideId, samples)
    }

    // --- createSnapshot / exportJson ----------------------------------------------------------

    @Test
    fun `createSnapshot captures every profile, ride, and sample`() = runTest {
        val (profileId, rideId, samples) = seedData()

        val snapshot = backupRepository.createSnapshot()

        assertEquals(BackupSnapshot.CURRENT_VERSION, snapshot.version)
        assertEquals(1_700_000_000_000L, snapshot.exportedAtEpochMs)
        assertEquals(listOf(profileId), snapshot.profiles.map { it.id })
        assertEquals(listOf(rideId), snapshot.rides.map { it.id })
        assertEquals(samples.size, snapshot.samples.size)
    }

    @Test
    fun `exportJson round-trips through parse back to an identical snapshot`() = runTest {
        seedData()
        val snapshot = backupRepository.createSnapshot()

        val json = backupRepository.exportJson()
        val reparsed = backupRepository.parse(json)

        assertEquals(snapshot, reparsed)
    }

    @Test
    fun `game rides and their results survive a backup and restore`() = runTest {
        val gameBackups = BackupRepository(db, db.profileDao(), db.rideDao(), gameResultDao = db.gameResultDao()) { 0L }
        val (profileId, _, _) = seedData()
        val rideId = rideRepository.saveRide(
            Ride(
                profileId = profileId, startEpochMs = 0, durationSec = 1200, avgCadence = 80, maxCadence = 90,
                avgPower = 150, maxPower = 200, avgResistance = 40, outputKj = 180.0, calories = 173,
                gamePlan = "just-ride:demo:minutes:20",
            ),
            emptyList(),
        )
        val result = GameResult(rideId, 0, "demo", "free", "standard", 0, 1200, 900.0, 2, null, false, """{"effort_avg":1.2}""")
        db.gameResultDao().insertAll(listOf(result))

        val json = gameBackups.exportJson()
        db.gameResultDao().deleteAll()
        gameBackups.restore(gameBackups.parse(json))

        assertEquals("just-ride:demo:minutes:20", rideRepository.getRide(rideId)?.gamePlan)
        assertEquals(listOf(result), db.gameResultDao().getForRide(rideId))
    }

    @Test
    fun `a backup file without game results still parses`() {
        val snapshot = backupRepository.parse(
            """{"version":1,"exportedAtEpochMs":0,"profiles":[],"rides":[],"samples":[]}""",
        )

        assertEquals(emptyList<GameResultBackup>(), snapshot.gameResults)
    }

    @Test
    fun `parse rejects malformed JSON`() {
        assertThrows(SerializationException::class.java) {
            backupRepository.parse("not valid json")
        }
    }

    // --- restore: the explicit backup -> wipe -> restore -> identical round trip -------------

    @Test
    fun `backup, wipe, and restore reproduces the exact original data`() = runTest {
        val (profileId, rideId, _) = seedData()
        val beforeProfiles = profileRepository.observeProfiles().first()
        val beforeRide = rideRepository.getRide(rideId)
        val beforeSamples = rideRepository.getSamples(rideId)

        val backup = backupRepository.createSnapshot()

        // Wipe: simulate a factory-reset tablet / fresh install losing everything.
        // clearAllTables() is a blocking Room call (not a suspend fun), so — like any direct
        // synchronous Room API — it must run off whatever thread this test body is on.
        withContext(Dispatchers.IO) { db.clearAllTables() }
        assertTrue(profileRepository.observeProfiles().first().isEmpty())

        backupRepository.restore(backup)

        val afterProfiles = profileRepository.observeProfiles().first()
        val afterRide = rideRepository.getRide(rideId)
        val afterSamples = rideRepository.getSamples(rideId)

        assertEquals(beforeProfiles, afterProfiles)
        assertEquals(beforeRide, afterRide)
        assertEquals(beforeSamples, afterSamples)
        // Foreign keys still resolve to the same restored ids, not just equal-looking values.
        assertEquals(profileId, afterRide?.profileId)
        assertTrue(afterSamples.all { it.rideId == rideId })
    }

    @Test
    fun `restore replaces existing data rather than appending to it`() = runTest {
        seedData()
        val backup = backupRepository.createSnapshot() // 1 profile, 1 ride

        // Simulate rides logged on this device after the backup was taken.
        val extraProfileId = profileRepository.createProfile(
            Profile(name = "Extra", avatarEmoji = "🔥", avatarColor = 0xFFAA0000.toInt(), weightKg = null, ftp = null),
        )
        rideRepository.saveRide(
            Ride(
                profileId = extraProfileId,
                startEpochMs = 0L,
                durationSec = 10,
                avgCadence = 0,
                maxCadence = 0,
                avgPower = 0,
                maxPower = 0,
                avgResistance = 0,
                outputKj = 0.0,
                calories = 0,
            ),
            emptyList(),
        )

        backupRepository.restore(backup)

        val profiles = profileRepository.observeProfiles().first()
        assertEquals(1, profiles.size)
        assertEquals("Ed", profiles.single().name)
    }

    @Test
    fun `restore rejects a backup version newer than this app supports`() = runTest {
        val futureSnapshot = BackupSnapshot(
            version = BackupSnapshot.CURRENT_VERSION + 1,
            exportedAtEpochMs = 0L,
            profiles = emptyList(),
            rides = emptyList(),
            samples = emptyList(),
        )

        assertThrows(IllegalArgumentException::class.java) {
            kotlinx.coroutines.runBlocking { backupRepository.restore(futureSnapshot) }
        }
    }

    @Test
    fun `restore of an empty snapshot leaves an empty database`() = runTest {
        seedData()

        backupRepository.restore(
            BackupSnapshot(exportedAtEpochMs = 0L, profiles = emptyList(), rides = emptyList(), samples = emptyList()),
        )

        assertTrue(profileRepository.observeProfiles().first().isEmpty())
    }
}
