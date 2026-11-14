@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.ui.ride

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.InMemoryDatabaseRule
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.ride.PowerZone
import dev.digitalducktape.openride.core.ride.RideGoal
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.core.telemetry.RideEntry
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class InRideViewModelTest {

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var rideRepository: RideRepository
    private lateinit var profileRepository: ProfileRepository
    private lateinit var activeProfileHolder: ActiveProfileHolder
    private lateinit var fakeBikeDataSource: FakeBikeDataSource
    private var profileId: Long = 0L

    @Before
    fun setUp() = runTest {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        rideRepository = RideRepository(db, db.rideDao())
        profileRepository = ProfileRepository(db.profileDao())
        activeProfileHolder = ActiveProfileHolder(context)
        profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        fakeBikeDataSource = FakeBikeDataSource()
    }

    @Test
    fun `sensorsAvailable is false once the connection has been down for 10 s`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        fakeBikeDataSource.setConnectionState(ConnectionState.Disconnected)
        advanceTimeBy(9_000)
        runCurrent()
        // The same rule as the top bar (issue #56): a blip never shows.
        assertTrue(values.last().sensorsAvailable)

        advanceTimeBy(1_001)
        runCurrent()
        assertFalse(values.last().sensorsAvailable)

        fakeBikeDataSource.setConnectionState(ConnectionState.Connected)
        runCurrent()
        assertTrue(values.last().sensorsAvailable)
    }

    @Test
    fun `the ride screen follows the shared offline rule it is given`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val offline = MutableStateFlow<Boolean?>(null)
        val viewModel = InRideViewModel(
            manager, fakeBikeDataSource, profileRepository, activeProfileHolder, sensorsOffline = offline,
        )
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()
        assertTrue("unknown counts as available", values.last().sensorsAvailable)

        offline.value = true
        runCurrent()
        assertFalse(values.last().sensorsAvailable)
    }

    @Test
    fun `isPaused reflects the session state`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        runCurrent()
        assertFalse(values.last().isPaused)

        manager.pause()
        runCurrent()
        assertTrue(values.last().isPaused)
    }

    @Test
    fun `liveOutputKj mirrors avgPower times elapsedSec over 1000`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 200)
        advanceTimeBy(3_000)
        runCurrent()

        // 3 seconds at 200W avg = 600 joules = 0.6 kJ.
        assertEquals(0.6, values.last().liveOutputKj, 0.0001)
    }

    @Test
    fun `distanceMiles accumulates while Active and freezes while Paused`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 200, speedMph = 36.0)
        advanceTimeBy(2_000) // 2 ticks at 36 mph = 0.01 mi/tick (36/3600) -> 0.02 mi total
        runCurrent()

        assertEquals(0.02, values.last().distanceMiles, 0.0001)

        manager.pause()
        advanceTimeBy(10_000) // time passes while paused; distance must not grow
        runCurrent()

        assertEquals(0.02, values.last().distanceMiles, 0.0001)
    }

    @Test
    fun `endRide delegates to the session manager and persists the ride`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()

        val ride = viewModel.endRide()

        requireNotNull(ride)
        assertTrue(ride.id > 0)
        assertEquals(RideSessionState.Finished(ride), manager.state.value)
    }

    // --- Power zones (T13/#13) --------------------------------------------------------------

    @Test
    fun `currentZone is null when the active profile has no FTP set`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 150)
        advanceTimeBy(1_000)
        runCurrent()

        assertEquals(null, values.last().currentZone)
    }

    @Test
    fun `currentZone reflects live power as a fraction of the active profile's FTP`() = runTest {
        val ftpProfileId = profileRepository.createProfile(
            Profile(name = "Zoned", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = 200),
        )
        activeProfileHolder.setActiveProfile(ftpProfileId)
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)

        manager.start(ftpProfileId, entry = RideEntry.HOME_QUICK_START, route = false)
        // 190W / 200W FTP = 95% -> Threshold zone (91-105%).
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 190)

        // A genuine suspend await (not the launch+runCurrent pattern used elsewhere in this
        // file) because ftp is sourced from a Room @Query Flow (profileRepository.observeProfiles()),
        // whose first real emission isn't guaranteed to land within a single runCurrent()
        // window the way this view model's other, purely in-memory inputs are.
        val state = viewModel.uiState.first { it.ftp != null }

        assertEquals(PowerZone.THRESHOLD, state.currentZone)
    }

    @Test
    fun `currentZone is null once sensors have been offline for 10 s`() = runTest {
        val ftpProfileId = profileRepository.createProfile(
            Profile(name = "Zoned", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = 200),
        )
        activeProfileHolder.setActiveProfile(ftpProfileId)
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.start(ftpProfileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 190)
        // Wait for the FTP (a Room query on its own thread): without it the zone is null anyway, and
        // the test would pass or fail on that race rather than on the sensors (2026-11-13 flake).
        assertEquals(PowerZone.THRESHOLD, viewModel.uiState.first { it.ftp != null }.currentZone)

        fakeBikeDataSource.setConnectionState(ConnectionState.Disconnected)
        // The one offline rule (issue #56): a disconnect counts only after 10 s.
        advanceTimeBy(10_001)
        runCurrent()

        assertEquals(null, values.last().currentZone)
    }

    // --- Ride goals (T13/#13) ----------------------------------------------------------------

    @Test
    fun `goalProgress is null when no goal is set`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(1_000)
        runCurrent()

        assertEquals(null, values.last().goalProgress)
    }

    @Test
    fun `goalProgress tracks elapsed time toward a Duration goal`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.setGoal(RideGoal.Duration(targetSec = 10))
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(0.5, values.last().goalProgress!!, 0.0001)
    }

    @Test
    fun `goalProgress tracks output toward an Output goal and clamps at 1_0`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope)
        val viewModel = InRideViewModel(manager, fakeBikeDataSource, profileRepository, activeProfileHolder)
        val values = mutableListOf<InRideUiState>()
        backgroundScope.launch { viewModel.uiState.collect { values.add(it) } }
        runCurrent()

        manager.setGoal(RideGoal.Output(targetKj = 0.5))
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        // 3 seconds at 200W = 600 joules = 0.6 kJ, over a 0.5 kJ goal -> clamped to 1.0.
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 200)
        advanceTimeBy(3_000)
        runCurrent()

        assertEquals(1.0, values.last().goalProgress!!, 0.0001)
    }
}
