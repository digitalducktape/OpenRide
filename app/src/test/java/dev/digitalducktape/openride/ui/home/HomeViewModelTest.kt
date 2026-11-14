@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.ui.home

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.InMemoryDatabaseRule
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.ride.FakeBikeDataSource
import dev.digitalducktape.openride.core.ride.RideGoal
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HomeViewModelTest {

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var profileRepository: ProfileRepository
    private lateinit var rideRepository: RideRepository
    private lateinit var activeProfileHolder: ActiveProfileHolder

    @Before
    fun setUp() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        profileRepository = ProfileRepository(db.profileDao())
        rideRepository = RideRepository(db, db.rideDao())
        activeProfileHolder = ActiveProfileHolder(context)
    }

    @Test
    fun `startQuickRide returns false and starts nothing when no profile is active`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val viewModel = HomeViewModel(activeProfileHolder, profileRepository, manager, routeLoaded = { false })

        val started = viewModel.startQuickRide()

        assertTrue(!started)
        assertEquals(RideSessionState.Idle, manager.state.value)
    }

    @Test
    fun `startQuickRide starts the session for the active profile`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val viewModel = HomeViewModel(activeProfileHolder, profileRepository, manager, routeLoaded = { false })

        val started = viewModel.startQuickRide()

        assertTrue(started)
        assertEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `activeProfile is null until a profile is selected`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val viewModel = HomeViewModel(activeProfileHolder, profileRepository, manager, routeLoaded = { false })

        val first = viewModel.activeProfile.first()

        assertNull(first)
    }

    @Test
    fun `activeProfile resolves the selected profile's row`() = runTest {
        val profileId = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(profileId)
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val viewModel = HomeViewModel(activeProfileHolder, profileRepository, manager, routeLoaded = { false })

        val active = viewModel.activeProfile.first { it != null }

        assertEquals("Ed", active?.name)
    }

    @Test
    fun `goal defaults to None and setGoal delegates to the session manager`() = runTest {
        val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
        val viewModel = HomeViewModel(activeProfileHolder, profileRepository, manager, routeLoaded = { false })

        assertEquals(RideGoal.None, viewModel.goal.value)

        viewModel.setGoal(RideGoal.Duration(targetSec = 900))

        assertEquals(RideGoal.Duration(900), viewModel.goal.value)
        assertEquals(RideGoal.Duration(900), manager.goal.value)
    }

    @Test
    fun `uiState carries the active rider and the goal as one value`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        try {
            val profileId = profileRepository.createProfile(
                Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
            )
            activeProfileHolder.setActiveProfile(profileId)
            val manager = RideSessionManager(FakeBikeDataSource(), rideRepository, backgroundScope)
            val viewModel = HomeViewModel(activeProfileHolder, profileRepository, manager, routeLoaded = { false })
            val collector = backgroundScope.launch { viewModel.uiState.collect {} }

            val loaded = viewModel.uiState.first { it.profile != null }
            assertEquals("Ed", loaded.riderName)
            assertEquals(RideGoal.None, loaded.goal)

            viewModel.setGoal(RideGoal.Output(targetKj = 250.0))
            val withGoal = viewModel.uiState.first { it.goal != RideGoal.None }
            assertEquals(RideGoal.Output(250.0), withGoal.goal)
            assertEquals("Ed", withGoal.riderName)
            collector.cancel()
        } finally {
            Dispatchers.resetMain()
        }
    }
}
