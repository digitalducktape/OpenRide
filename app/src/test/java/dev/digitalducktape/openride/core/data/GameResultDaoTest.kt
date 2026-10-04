package dev.digitalducktape.openride.core.data

import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.camera.HeadCalibration
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class GameResultDaoTest {

    private lateinit var db: OpenRideDatabase
    private lateinit var dao: GameResultDao
    private lateinit var rides: RideRepository
    private var ed = 0L
    private var kid = 0L

    @Before
    fun setUp() = runTest {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            OpenRideDatabase::class.java,
        ).build()
        dao = db.gameResultDao()
        rides = RideRepository(db, db.rideDao())
        ed = db.profileDao().insert(profile("Ed"))
        kid = db.profileDao().insert(profile("Kid"))
    }

    @After
    fun tearDown() {
        db.close()
    }

    private fun profile(name: String) =
        Profile(name = name, avatarEmoji = "🚴", avatarColor = 0, weightKg = null, ftp = 200)

    private suspend fun gameRide(profileId: Long, plan: String?, vararg results: Pair<Double, Int>, difficulty: String = "standard", gameId: String = "demo", skipped: Boolean = false, variant: String = ""): Long {
        val rideId = rides.saveRide(
            Ride(
                profileId = profileId, startEpochMs = 0, durationSec = 60, avgCadence = 80, maxCadence = 90,
                avgPower = 150, maxPower = 200, avgResistance = 40, outputKj = 9.0, calories = 9, gamePlan = plan,
            ),
            emptyList(),
        )
        dao.insertAll(
            results.mapIndexed { i, (score, stars) ->
                GameResult(rideId, i, gameId, "free", difficulty, i * 60, 60, score, stars, null, skipped, "{}", variant)
            },
        )
        return rideId
    }

    @Test
    fun `results round-trip in segment order`() = runTest {
        val rideId = gameRide(ed, "circuit-20", 10.0 to 1, 20.0 to 2)

        val saved = dao.getForRide(rideId)

        assertEquals(listOf(0, 1), saved.map { it.segmentIndex })
        assertEquals(listOf(10.0, 20.0), saved.map { it.score })
    }

    @Test
    fun `personal bests are per game, plan and difficulty, for one rider, skips excluded`() = runTest {
        gameRide(ed, "just-ride:demo:minutes:20", 500.0 to 1)
        gameRide(ed, "just-ride:demo:minutes:20", 900.0 to 2)
        gameRide(ed, "just-ride:demo:minutes:20", 300.0 to 3, difficulty = "hard")
        gameRide(ed, "just-ride:demo:open", 100.0 to 0)
        gameRide(ed, "just-ride:demo:open", 0.0 to 0, skipped = true)
        gameRide(kid, "just-ride:demo:minutes:20", 5000.0 to 3)

        val bests = dao.observePersonalBests(ed).first()

        assertEquals(
            listOf(
                GamePersonalBest("demo", "just-ride:demo:minutes:20", "hard", 300.0, 3, 1),
                GamePersonalBest("demo", "just-ride:demo:minutes:20", "standard", 900.0, 2, 2),
                GamePersonalBest("demo", "just-ride:demo:open", "standard", 100.0, 0, 1),
            ),
            bests,
        )
    }

    @Test
    fun `the household leaderboard ranks each rider's best, highest first`() = runTest {
        gameRide(ed, "just-ride:demo:minutes:20", 500.0 to 1)
        gameRide(ed, "just-ride:demo:minutes:20", 900.0 to 2)
        gameRide(kid, "just-ride:demo:minutes:30", 1200.0 to 3)
        gameRide(kid, "just-ride:demo:minutes:20", 2000.0 to 3, skipped = true)
        gameRide(kid, "just-ride:demo:minutes:20", 5000.0 to 3, difficulty = "easy")
        gameRide(kid, "just-ride:other:minutes:20", 9000.0 to 3, gameId = "other")

        val everyPlan = dao.leaderboard("demo", "standard", gamePlan = null)
        val twentyMinutes = dao.leaderboard("demo", "standard", gamePlan = "just-ride:demo:minutes:20")

        assertEquals(
            listOf(LeaderboardEntry(kid, "Kid", 1200.0, 3), LeaderboardEntry(ed, "Ed", 900.0, 2)),
            everyPlan,
        )
        assertEquals(listOf(LeaderboardEntry(ed, "Ed", 900.0, 2)), twentyMinutes)
    }

    @Test
    fun `the plan best sums each session and leaves out the ride just saved`() = runTest {
        assertEquals(PlanBest(null, null), dao.planBest(ed, "circuit-20", "standard", excludeRideId = 0))

        gameRide(ed, "circuit-20", 10.0 to 1, 20.0 to 2)
        gameRide(ed, "circuit-20", 50.0 to 1, 1.0 to 1)
        gameRide(ed, "circuit-20", 999.0 to 3, difficulty = "hard")
        gameRide(kid, "circuit-20", 999.0 to 3)
        val latest = gameRide(ed, "circuit-20", 500.0 to 3, 500.0 to 3)

        assertEquals(PlanBest(51.0, 3), dao.planBest(ed, "circuit-20", "standard", excludeRideId = latest))
    }

    @Test
    fun `results are deleted with their ride`() = runTest {
        val rideId = gameRide(ed, "circuit-20", 10.0 to 1)

        db.profileDao().delete(db.profileDao().getById(ed)!!)

        assertEquals(emptyList<GameResult>(), dao.getForRide(rideId))
    }

    @Test
    fun `the head calibration store keeps each rider's extremes in their profile`() = runTest {
        val store = ProfileHeadCalibrationStore(db.profileDao())
        val calibration = HeadCalibration(leftDx = -0.15, rightDx = 0.16, calibratedAtEpochMs = 1_000L)

        assertNull(store.load(ed))
        store.save(ed, calibration)

        assertEquals(calibration, store.load(ed))
        assertNull(store.load(kid))
        // Other profile fields are untouched.
        assertEquals("Ed", db.profileDao().getById(ed)?.name)
        assertEquals(200, db.profileDao().getById(ed)?.ftp)
    }

    @Test
    fun `an unreadable stored calibration reads as none`() = runTest {
        db.profileDao().setHeadCalibration(ed, "{not json")

        assertNull(ProfileHeadCalibrationStore(db.profileDao()).load(ed))
    }

    @Test
    fun `bests, leaderboards and plan bests are kept per variant`() = runTest {
        val plan = "just-ride:dodge_ball:minutes:20"
        gameRide(ed, plan, 900.0 to 2, gameId = "dodge_ball", variant = "")
        val catchRide = gameRide(ed, plan, 400.0 to 1, gameId = "dodge_ball", variant = "catch")

        val bests = dao.observePersonalBests(ed).first().filter { it.gameId == "dodge_ball" }
        assertEquals(mapOf("" to 900.0, "catch" to 400.0), bests.associate { it.variant to it.bestScore })
        assertEquals(400.0, dao.leaderboard("dodge_ball", "standard", plan, variant = "catch").single().bestScore, 0.0)
        assertEquals(900.0, dao.leaderboard("dodge_ball", "standard", plan).single().bestScore, 0.0)

        val newCatch = gameRide(ed, plan, 500.0 to 2, gameId = "dodge_ball", variant = "catch")
        assertEquals(400.0, dao.planBest(ed, plan, "standard", newCatch, variant = "catch").bestScore!!, 0.0)
        assertEquals(900.0, dao.planBest(ed, plan, "standard", newCatch, variant = "").bestScore!!, 0.0)
        assertEquals(900.0, dao.planBest(ed, plan, "standard", catchRide).bestScore!!, 0.0) // no variant: all sessions
    }
}
