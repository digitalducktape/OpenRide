package dev.digitalducktape.openride.ui.games

import dev.digitalducktape.openride.core.data.GamePersonalBest
import dev.digitalducktape.openride.core.data.PlanBest
import dev.digitalducktape.openride.games.bridge.Difficulty
import dev.digitalducktape.openride.games.session.GameCatalog
import dev.digitalducktape.openride.games.session.GameMusicMode
import dev.digitalducktape.openride.games.session.InMemoryGamesSettingsStore
import dev.digitalducktape.openride.games.session.JustRideMode
import dev.digitalducktape.openride.games.session.SessionRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class GamesViewModelTest {
    private val ftp = MutableStateFlow<Int?>(200)
    private val bests = MutableStateFlow<List<GamePersonalBest>>(emptyList())
    private val store = InMemoryGamesSettingsStore()
    private var circuitBest: PlanBest? = null

    @Before fun setUp() = Dispatchers.setMain(UnconfinedTestDispatcher())
    @After fun tearDown() = Dispatchers.resetMain()

    private fun vm(profile: Long? = 1L) = GamesViewModel(
        catalog = GameCatalog.DEFAULT,
        settingsStore = store,
        activeProfileId = flowOf(profile),
        profileFtp = { ftp },
        personalBests = { bests },
        circuitBest = { _, _, _ -> circuitBest },
    ).also { it.state.launchIn(kotlinx.coroutines.CoroutineScope(Dispatchers.Main)) }

    @Test
    fun `lists the three circuits with their length and lineup`() = runTest {
        val circuits = vm().state.first().circuits
        assertEquals(listOf("20 min circuit", "30 min circuit", "45 min circuit"), circuits.map { it.title })
        assertEquals(listOf("18:40", "31:00", "43:20"), circuits.map { it.totalLabel })
        assertTrue(circuits.first().lineup.contains("Tug of War"))
        assertTrue(circuits.first().lineup.contains("Cadence Karaoke"))
    }

    @Test
    fun `lists every catalog game except the demo, each with the modes it supports`() = runTest {
        val games = vm().state.first().games
        assertEquals(listOf("dodge_ball", "tug_of_war", "safe_cracker", "cadence_karaoke"), games.map { it.id })
        val cadence = games.first { it.id == "cadence_karaoke" }
        assertEquals(listOf(RideKind.TIMED, RideKind.OPEN), cadence.kinds)  // no rounds
        val dodge = games.first { it.id == "dodge_ball" }
        assertEquals(listOf(RideKind.TIMED, RideKind.ROUNDS, RideKind.OPEN), dodge.kinds)
        assertEquals(20, dodge.minutes)  // a default of 20 minutes
        assertTrue(dodge.minutesOptions.all { it * 60 in 60..3600 })
    }

    @Test
    fun `picking mode, length and difficulty builds the right Just Ride request`() = runTest {
        val vm = vm()
        vm.setKind("tug_of_war", RideKind.TIMED)
        vm.setMinutes("tug_of_war", 30)
        vm.setGameDifficulty("tug_of_war", Difficulty.HARD)
        assertEquals(SessionRequest.JustRide("tug_of_war", JustRideMode.Timed(30), Difficulty.HARD), vm.justRideRequest("tug_of_war"))
        vm.setKind("tug_of_war", RideKind.ROUNDS)
        vm.setRounds("tug_of_war", 5)
        assertEquals(JustRideMode.Rounds(5), vm.justRideRequest("tug_of_war")!!.mode)
        vm.setKind("tug_of_war", RideKind.OPEN)
        assertEquals(JustRideMode.Open, vm.justRideRequest("tug_of_war")!!.mode)
        assertNull(vm.justRideRequest("not_a_game"))
    }

    @Test
    fun `an unsupported kind falls back to one the game supports`() = runTest {
        val vm = vm()
        vm.setKind("cadence_karaoke", RideKind.ROUNDS)
        assertEquals(RideKind.TIMED, vm.state.first().games.first { it.id == "cadence_karaoke" }.kind)
    }

    @Test
    fun `circuit requests carry the difficulty and the camera setting`() = runTest {
        val vm = vm()
        vm.setCircuitDifficulty(Difficulty.EASY)
        assertEquals(SessionRequest.Circuit("circuit-30", Difficulty.EASY, cameraGames = true), vm.circuitRequest("circuit-30"))
        vm.setCameraGames(false)
        assertFalse(vm.circuitRequest("circuit-30").cameraGames)
        vm.setCameraGames(true)
        assertFalse(vm.circuitRequest("circuit-30", cameraAvailable = false).cameraGames)  // the permission was refused
    }

    @Test
    fun `with camera games off, camera games can't be started on their own`() = runTest {
        val vm = vm()
        vm.setCameraGames(false)
        val state = vm.state.first()
        assertTrue(state.games.first { it.id == "dodge_ball" }.unavailable)
        assertFalse(state.games.first { it.id == "tug_of_war" }.unavailable)
        assertNull(vm.justRideRequest("dodge_ball"))
        assertNotNull(vm.justRideRequest("tug_of_war"))
    }

    @Test
    fun `shows the rider's best for the plan and difficulty on screen`() = runTest {
        bests.value = listOf(
            GamePersonalBest("tug_of_war", "just-ride:tug_of_war:minutes:20", "standard", 5400.0, 2, 3),
            GamePersonalBest("tug_of_war", "just-ride:tug_of_war:minutes:20", "hard", 7000.0, 3, 1),
            GamePersonalBest("tug_of_war", "just-ride:tug_of_war:minutes:10", "standard", 999.0, 1, 1),
        )
        val vm = vm()
        assertEquals("Best 5400 · 2 stars", vm.state.first().games.first { it.id == "tug_of_war" }.best)
        vm.setGameDifficulty("tug_of_war", Difficulty.HARD)
        assertEquals("Best 7000 · 3 stars", vm.state.first().games.first { it.id == "tug_of_war" }.best)
        vm.setMinutes("tug_of_war", 5)
        assertNull(vm.state.first().games.first { it.id == "tug_of_war" }.best)
    }

    @Test
    fun `circuit bests come from the plan best at the circuit difficulty`() = runTest {
        circuitBest = PlanBest(bestScore = 12345.0, bestStars = 17)
        assertEquals("Best 12345 · 17 stars", vm().state.first().circuits.first().best)
        circuitBest = PlanBest(null, null)
        assertNull(vm().state.first().circuits.first().best)
    }

    @Test
    fun `nudges for an FTP only when the rider hasn't set one`() = runTest {
        ftp.value = null
        assertTrue(vm().state.first().ftpMissing)
        ftp.value = 0
        assertTrue(vm().state.first().ftpMissing)
        ftp.value = 180
        assertFalse(vm().state.first().ftpMissing)
    }

    @Test
    fun `audio settings are stored and clamped`() = runTest {
        val vm = vm()
        vm.setMusicMode(GameMusicMode.OFF)
        vm.setMusicVolume(1.7)
        vm.setEffectsVolume(-1.0)
        val audio = vm.state.first().audio
        assertEquals(GameMusicMode.OFF, audio.music)
        assertEquals(1.0, audio.musicVolume, 0.0)
        assertEquals(0.0, audio.sfxVolume, 0.0)
        assertEquals(GameMusicMode.OFF, store.settings.value.audio.music)
    }
}
