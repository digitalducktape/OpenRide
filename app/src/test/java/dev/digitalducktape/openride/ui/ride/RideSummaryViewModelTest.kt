@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.ui.ride

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
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RideSummaryViewModelTest {

    private lateinit var db: OpenRideDatabase
    private lateinit var rideRepository: RideRepository
    private lateinit var profileRepository: ProfileRepository
    private var profileId: Long = 0L

    @Before
    fun setUp() = runTest {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        db = Room.inMemoryDatabaseBuilder(context, OpenRideDatabase::class.java).build()
        rideRepository = RideRepository(db, db.rideDao())
        profileRepository = ProfileRepository(db.profileDao())
        profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
    }

    @After
    fun tearDown() {
        db.close()
    }

    @Test
    fun `load fetches the ride by id`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        advanceTimeBy(2_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.load()

        assertNotNull(viewModel.ride.value)
        assertEquals(ride.id, viewModel.ride.value?.id)
    }

    @Test
    fun `load also fetches the ride's full sample series`() = runTest {
        val fakeBikeDataSource = FakeBikeDataSource()
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 200)
        advanceTimeBy(3_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.load()

        assertEquals(3, viewModel.samples.value.size)
        assertEquals((0 until 3).toList(), viewModel.samples.value.map { it.tSec })
        assertTrue(viewModel.samples.value.all { it.power == 200 })
    }

    @Test
    fun `a game ride loads its badge and segment results`() = runTest {
        val gameRides = RideRepository(db, db.rideDao(), db.gameResultDao())
        val rideId = gameRides.saveRide(
            Ride(
                profileId = profileId, startEpochMs = 0, durationSec = 1210, avgCadence = 80, maxCadence = 90,
                avgPower = 150, maxPower = 200, avgResistance = 40, outputKj = 180.0, calories = 173,
                gamePlan = "just-ride:demo:minutes:20",
            ),
            emptyList(),
        )
        db.gameResultDao().insertAll(listOf(GameResult(rideId, 0, "demo", "free", "standard", 0, 1200, 900.0, 2, null, false, "{}")))
        val manager = RideSessionManager(FakeBikeDataSource(), gameRides, backgroundScope) { 0L }

        val viewModel = RideSummaryViewModel(gameRides, profileRepository, manager, rideId)
        viewModel.load()

        assertEquals("Demo · 20 min", viewModel.gameBadge.value)
        assertEquals(listOf("1. Demo"), viewModel.gameResults.value.map { it.title })
        assertEquals(2, viewModel.gameResults.value.single().stars)
    }

    @Test
    fun `an ordinary ride has no game results`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        advanceTimeBy(1_000)
        runCurrent()
        val ride = requireNotNull(manager.stop())

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.load()

        assertNull(viewModel.gameBadge.value)
        assertTrue(viewModel.gameResults.value.isEmpty())
    }

    @Test
    fun `dismiss resets the session when it was Finished`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        advanceTimeBy(1_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.dismiss()

        assertEquals(RideSessionState.Idle, manager.state.value)
    }

    @Test
    fun `dismiss is a no-op when the session isn't Finished (history detail case)`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        advanceTimeBy(1_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)
        manager.reset() // back to Idle, simulating an unrelated older ride being viewed later

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.dismiss()

        assertEquals(RideSessionState.Idle, manager.state.value)
    }

    // --- FTP suggestion (T13/#13) ------------------------------------------------------------

    private fun longRideOf(power: Int): Ride = Ride(
        profileId = profileId,
        startEpochMs = 0L,
        durationSec = 1200,
        avgCadence = 90,
        maxCadence = 90,
        avgPower = power,
        maxPower = power,
        avgResistance = 50,
        outputKj = power * 1200 / 1000.0,
        calories = null,
    )

    @Test
    fun `suggestedFtp is null for a ride shorter than 20 minutes`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        advanceTimeBy(5_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.load()

        assertNull(viewModel.suggestedFtp.value)
    }

    @Test
    fun `suggestedFtp is 95pct of the best 20-minute average for a 20-minute-plus ride`() = runTest {
        val samples = (0 until 1200).map { t -> RideSample(rideId = 0L, tSec = t, cadence = 90, resistance = 50, power = 200) }
        val rideId = rideRepository.saveRide(longRideOf(power = 200), samples)
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, rideId)
        viewModel.load()

        assertEquals(190, viewModel.suggestedFtp.value) // 95% of 200W
    }

    @Test
    fun `applySuggestedFtp updates the profile that logged the ride and flips ftpApplied`() = runTest {
        val samples = (0 until 1200).map { t -> RideSample(rideId = 0L, tSec = t, cadence = 90, resistance = 50, power = 200) }
        val rideId = rideRepository.saveRide(longRideOf(power = 200), samples)
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, rideId)
        viewModel.load()
        assertEquals(false, viewModel.ftpApplied.value)

        viewModel.applySuggestedFtp()

        assertEquals(190, profileRepository.getProfile(profileId)?.ftp)
        assertTrue(viewModel.ftpApplied.value)
    }

    // --- Export (T14/#14) ---------------------------------------------------------------------

    @Test
    fun `tcxContent and sampleCsvContent are null before load`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        advanceTimeBy(1_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)

        assertEquals(null, viewModel.tcxContent())
        assertEquals(null, viewModel.sampleCsvContent())
    }

    @Test
    fun `tcxContent and sampleCsvContent reflect the loaded ride and samples`() = runTest {
        val fakeBikeDataSource = FakeBikeDataSource()
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 200)
        advanceTimeBy(2_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.load()

        val tcx = viewModel.tcxContent()
        requireNotNull(tcx)
        assertTrue(tcx.contains("TrainingCenterDatabase"))
        assertTrue(tcx.contains("<Watts>200</Watts>"))

        val csv = viewModel.sampleCsvContent()
        requireNotNull(csv)
        assertEquals("t_sec,cadence,resistance,power\n0,90,50,200\n1,90,50,200\n", csv)
    }

    @Test
    fun `applySuggestedFtp is a no-op when the ride is too short to have a suggestion`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope) { 0L }
        manager.start(profileId)
        advanceTimeBy(5_000)
        runCurrent()
        val ride = manager.stop()
        requireNotNull(ride)

        val viewModel = RideSummaryViewModel(rideRepository, profileRepository, manager, ride.id)
        viewModel.load()
        viewModel.applySuggestedFtp()

        assertEquals(null, profileRepository.getProfile(profileId)?.ftp)
        assertEquals(false, viewModel.ftpApplied.value)
    }
}
