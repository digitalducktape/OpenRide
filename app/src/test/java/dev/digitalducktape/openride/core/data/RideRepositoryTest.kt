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
class RideRepositoryTest {

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var rideRepository: RideRepository
    private lateinit var profileRepository: ProfileRepository

    @Before
    fun setUp() {
        rideRepository = RideRepository(db, db.rideDao())
        profileRepository = ProfileRepository(db.profileDao())
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
    fun `getRide returns null for an unknown id`() = runTest {
        assertNull(rideRepository.getRide(rideId = 999L))
    }

    @Test
    fun `deleteRide removes the ride with its samples and game results, and nothing else`() = runTest {
        val gameRides = RideRepository(db, db.rideDao(), db.gameResultDao())
        val profileId = createProfile("Ed")
        val keptId = gameRides.saveRide(rideFor(profileId, startEpochMs = 1_000L), samplesFor(3))
        val deletedId = gameRides.saveRide(rideFor(profileId, startEpochMs = 2_000L), samplesFor(5))
        db.gameResultDao().insertAll(
            listOf(
                GameResult(keptId, 0, "demo", "free", "standard", 0, 60, 100.0, 1, null, false, "{}"),
                GameResult(deletedId, 0, "demo", "free", "standard", 0, 60, 900.0, 3, null, false, "{}"),
            ),
        )

        gameRides.deleteRide(deletedId)

        assertNull(gameRides.getRide(deletedId))
        assertTrue(gameRides.getSamples(deletedId).isEmpty())
        assertTrue(gameRides.getGameResults(deletedId).isEmpty())
        assertEquals(listOf(keptId), gameRides.observeHistory(profileId).first().map { it.id })
        assertEquals(3, gameRides.getSamples(keptId).size)
        assertEquals(1, gameRides.getGameResults(keptId).size)
        assertEquals(3, db.rideDao().getAllSamplesOnce().size)
    }

    @Test
    fun `deleteRide of an unknown id changes nothing`() = runTest {
        val profileId = createProfile("Ed")
        val rideId = rideRepository.saveRide(rideFor(profileId, startEpochMs = 1_000L), samplesFor(2))

        rideRepository.deleteRide(rideId + 100)

        assertEquals(1, rideRepository.observeHistory(profileId).first().size)
        assertEquals(2, rideRepository.getSamples(rideId).size)
    }
}
