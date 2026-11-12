package dev.digitalducktape.openride.core.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RideRepositoryTest {

    private lateinit var db: OpenRideDatabase
    private lateinit var rideRepository: RideRepository
    private lateinit var profileRepository: ProfileRepository

    @Before
    fun setUp() {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            OpenRideDatabase::class.java,
        ).build()
        rideRepository = RideRepository(db, db.rideDao())
        profileRepository = ProfileRepository(db.profileDao())
    }

    @After
    fun tearDown() {
        db.close()
    }

    private suspend fun createProfile(name: String): Long =
        profileRepository.createProfile(
            Profile(name = name, avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = 70.0, ftp = 200),
        )

    private fun rideFor(profileId: Long, startEpochMs: Long) = Ride(
        profileId = profileId,
        startEpochMs = startEpochMs,
        durationSec = 600,
        avgCadence = 80,
        maxCadence = 105,
        avgPower = 150,
        maxPower = 300,
        avgResistance = 40,
        outputKj = 90.0,
        calories = 86,
    )

    private fun samplesFor(count: Int) = (0 until count).map { t ->
        RideSample(rideId = 0L, tSec = t, cadence = 80 + t, resistance = 40, power = 150 + t)
    }

    @Test
    fun `saveRide writes the ride and all samples, linked by the generated id`() = runTest {
        val profileId = createProfile("Ed")
        val samples = samplesFor(10)

        val rideId = rideRepository.saveRide(rideFor(profileId, startEpochMs = 1_000L), samples)

        val savedRide = rideRepository.getRide(rideId)
        requireNotNull(savedRide)
        assertEquals(profileId, savedRide.profileId)
        assertEquals(600, savedRide.durationSec)

        val savedSamples = rideRepository.getSamples(rideId)
        assertEquals(10, savedSamples.size)
        assertTrue(savedSamples.all { it.rideId == rideId })
        assertEquals((0 until 10).toList(), savedSamples.map { it.tSec })
    }

    @Test
    fun `saveRide works with an empty sample list`() = runTest {
        val profileId = createProfile("Ed")

        val rideId = rideRepository.saveRide(rideFor(profileId, startEpochMs = 1_000L), emptyList())

        assertEquals(0, rideRepository.getSamples(rideId).size)
        requireNotNull(rideRepository.getRide(rideId))
    }

    @Test
    fun `history is scoped by profile and ordered newest first`() = runTest {
        val edId = createProfile("Ed")
        val alexId = createProfile("Alex")

        rideRepository.saveRide(rideFor(edId, startEpochMs = 1_000L), emptyList())
        val edNewestRideId = rideRepository.saveRide(rideFor(edId, startEpochMs = 3_000L), emptyList())
        rideRepository.saveRide(rideFor(edId, startEpochMs = 2_000L), emptyList())
        rideRepository.saveRide(rideFor(alexId, startEpochMs = 5_000L), emptyList())

        val edHistory = rideRepository.observeHistory(edId).first()

        assertEquals(3, edHistory.size)
        assertEquals(edNewestRideId, edHistory.first().id)
        assertEquals(listOf(3_000L, 2_000L, 1_000L), edHistory.map { it.startEpochMs })
        assertTrue(edHistory.all { it.profileId == edId })
    }

    @Test
    fun `deleteRide removes only that ride, with its samples and game results`() = runTest {
        val profileId = createProfile("Ed")
        val keptId = rideRepository.saveRide(rideFor(profileId, startEpochMs = 1_000L), samplesFor(5))
        val deletedId = rideRepository.saveRide(rideFor(profileId, startEpochMs = 2_000L), samplesFor(5))
        db.gameResultDao().insertAll(
            listOf(GameResult(deletedId, 0, "demo", "free", "standard", 0, 60, 10.0, 1, null, false, "{}", "")),
        )

        assertTrue(rideRepository.deleteRide(deletedId))

        assertNull(rideRepository.getRide(deletedId))
        assertTrue(rideRepository.getSamples(deletedId).isEmpty())
        assertTrue(db.gameResultDao().getForRide(deletedId).isEmpty())
        assertEquals(listOf(keptId), rideRepository.observeHistory(profileId).first().map { it.id })
        assertEquals(5, rideRepository.getSamples(keptId).size)
    }

    @Test
    fun `deleteRide returns false for an unknown id`() = runTest {
        assertFalse(rideRepository.deleteRide(rideId = 999L))
    }

    @Test
    fun `getRide returns null for an unknown id`() = runTest {
        assertNull(rideRepository.getRide(rideId = 999L))
    }
}
