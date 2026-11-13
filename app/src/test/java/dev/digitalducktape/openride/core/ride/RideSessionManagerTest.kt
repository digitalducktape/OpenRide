@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.core.ride

import dev.digitalducktape.openride.core.telemetry.DiscardReason
import dev.digitalducktape.openride.core.telemetry.RideEntry
import androidx.room.Room
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.OpenRideDatabase
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.telemetry.DurationBucket
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.RideEnd
import dev.digitalducktape.openride.core.telemetry.RideOutcome
import dev.digitalducktape.openride.core.telemetry.RideStart
import dev.digitalducktape.openride.core.telemetry.RideTelemetryTracker
import dev.digitalducktape.openride.core.telemetry.RideType
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.TelemetryEvent
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RideSessionManagerTest {

    private lateinit var db: OpenRideDatabase
    private lateinit var rideRepository: RideRepository
    private var profileId: Long = 0L
    private lateinit var fakeBikeDataSource: FakeBikeDataSource

    @Before
    fun setUp() = runTest {
        db = Room.inMemoryDatabaseBuilder(
            ApplicationProvider.getApplicationContext(),
            OpenRideDatabase::class.java,
        ).build()
        rideRepository = RideRepository(db, db.rideDao())
        profileId = ProfileRepository(db.profileDao()).createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = 80.0, ftp = 220),
        )
        fakeBikeDataSource = FakeBikeDataSource()
    }

    @After
    fun tearDown() {
        db.close()
    }

    // --- Initial state -----------------------------------------------------------------

    @Test
    fun `starts Idle with zeroed elapsed and aggregates`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }

        assertEquals(RideSessionState.Idle, manager.state.value)
        assertEquals(0, manager.elapsedSec.value)
        assertEquals(LiveAggregates(), manager.liveAggregates.value)
        assertTrue(!manager.isRideActive.value)
    }

    // --- start() -------------------------------------------------------------------------

    @Test
    fun `start transitions Idle to Active and sets isRideActive`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }

        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        assertEquals(RideSessionState.Active, manager.state.value)
        assertTrue(manager.isRideActive.value)
    }

    @Test
    fun `start is a no-op when not Idle`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()
        val elapsedBeforeSecondStart = manager.elapsedSec.value

        manager.start(profileId = 999L, entry = RideEntry.HOME_QUICK_START, route = false) // different profile id, should be ignored

        assertEquals(RideSessionState.Active, manager.state.value)
        assertEquals(elapsedBeforeSecondStart, manager.elapsedSec.value)
    }

    // --- 1 Hz sampling + live aggregates --------------------------------------------------

    @Test
    fun `ticks elapsedSec once per second while Active`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        advanceTimeBy(3_000)
        runCurrent()

        assertEquals(3, manager.elapsedSec.value)
    }

    @Test
    fun `live aggregates reflect avg and max across sampled ticks`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        fakeBikeDataSource.setMetrics(cadenceRpm = 80, resistancePercent = 40, powerWatts = 100)
        advanceTimeBy(1_000)
        runCurrent()

        fakeBikeDataSource.setMetrics(cadenceRpm = 100, resistancePercent = 50, powerWatts = 200)
        advanceTimeBy(1_000)
        runCurrent()

        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 45, powerWatts = 150)
        advanceTimeBy(1_000)
        runCurrent()

        val aggregates = manager.liveAggregates.value
        assertEquals(90, aggregates.avgCadence) // (80+100+90)/3
        assertEquals(100, aggregates.maxCadence)
        assertEquals(150, aggregates.avgPower) // (100+200+150)/3
        assertEquals(200, aggregates.maxPower)
        assertEquals(45, aggregates.avgResistance) // (40+50+45)/3
    }

    // --- pause()/resume() timer math -------------------------------------------------------

    @Test
    fun `pause stops elapsed accumulation and sampling`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(5, manager.elapsedSec.value)

        manager.pause()
        assertEquals(RideSessionState.Paused, manager.state.value)
        assertTrue(!manager.isRideActive.value)

        advanceTimeBy(10_000)
        runCurrent()

        assertEquals(5, manager.elapsedSec.value)
    }

    @Test
    fun `resume continues elapsed accumulation from where it paused`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(5_000)
        runCurrent()
        manager.pause()
        advanceTimeBy(10_000) // time passes while paused; must not count
        runCurrent()

        manager.resume()
        assertEquals(RideSessionState.Active, manager.state.value)
        assertTrue(manager.isRideActive.value)

        advanceTimeBy(3_000)
        runCurrent()

        assertEquals(8, manager.elapsedSec.value) // 5 before pause + 3 after resume
    }

    @Test
    fun `pause is a no-op unless Active`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }

        manager.pause() // Idle, should be ignored

        assertEquals(RideSessionState.Idle, manager.state.value)
    }

    @Test
    fun `resume is a no-op unless Paused`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        manager.resume() // already Active, should be ignored

        assertEquals(RideSessionState.Active, manager.state.value)
    }

    // --- stop() persistence + aggregate computation ---------------------------------------

    @Test
    fun `stop persists the ride and its samples in one transaction`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 42_000L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 200)
        advanceTimeBy(4_000)
        runCurrent()

        val ride = manager.stop()

        requireNotNull(ride)
        assertTrue(ride.id > 0)
        assertEquals(profileId, ride.profileId)
        assertEquals(42_000L, ride.startEpochMs)
        assertEquals(4, ride.durationSec)
        assertEquals(90, ride.avgCadence)
        assertEquals(90, ride.maxCadence)
        assertEquals(200, ride.avgPower)
        assertEquals(200, ride.maxPower)
        assertEquals(50, ride.avgResistance)

        val persisted = rideRepository.getRide(ride.id)
        requireNotNull(persisted)
        assertEquals(ride, persisted)

        val samples = rideRepository.getSamples(ride.id)
        assertEquals(4, samples.size)
        assertEquals((0 until 4).toList(), samples.map { it.tSec })
        assertTrue(samples.all { it.cadence == 90 && it.power == 200 && it.resistance == 50 })
    }

    @Test
    fun `stop records the class video id when the ride was started with one`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, videoId = "dQw4w9WgXcQ", entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()

        val ride = manager.stop()

        requireNotNull(ride)
        assertEquals("dQw4w9WgXcQ", ride.videoId)
        assertEquals("dQw4w9WgXcQ", rideRepository.getRide(ride.id)?.videoId)
    }

    @Test
    fun `stop records the game plan when the ride was started with one`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, gamePlan = "just-ride:demo:minutes:20", entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()

        val ride = manager.stop()

        requireNotNull(ride)
        assertEquals("just-ride:demo:minutes:20", rideRepository.getRide(ride.id)?.gamePlan)
        assertNull(ride.videoId)
    }

    @Test
    fun `discard ends the ride without saving it and returns to Idle`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, gamePlan = "just-ride:demo:open", entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 80, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(5_000)
        runCurrent()

        manager.discard(DiscardReason.TOO_SHORT)
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(RideSessionState.Idle, manager.state.value)
        assertEquals(0, manager.elapsedSec.value)
        assertTrue(!manager.isRideActive.value)
        assertEquals(0, db.rideDao().getAllRidesOnce().size)
        // The next ride starts cleanly.
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        assertEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `a quick start ride persists no video id`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()

        val ride = manager.stop()

        requireNotNull(ride)
        assertNull(ride.videoId)
    }

    @Test
    fun `stop computes outputKj and calories from summed power`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        // 3 seconds at 200W = 600 joules = 0.6 kJ.
        fakeBikeDataSource.setMetrics(cadenceRpm = 90, resistancePercent = 50, powerWatts = 200)
        advanceTimeBy(3_000)
        runCurrent()

        val ride = manager.stop()

        requireNotNull(ride)
        assertEquals(0.6, ride.outputKj, 0.0001)
        // kcal ~= kJ * 0.96 (documented approximation), rounded.
        assertEquals(Math.round(0.6 * 0.96).toInt(), ride.calories)
    }

    @Test
    fun `stop transitions to Finished carrying the persisted ride`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(1_000)
        runCurrent()

        val ride = manager.stop()

        requireNotNull(ride)
        assertEquals(RideSessionState.Finished(ride), manager.state.value)
        assertTrue(!manager.isRideActive.value)
    }

    @Test
    fun `stop works from Paused too`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()
        manager.pause()

        val ride = manager.stop()

        requireNotNull(ride)
        assertEquals(2, ride.durationSec)
        assertTrue(manager.state.value is RideSessionState.Finished)
    }

    @Test
    fun `stop is a no-op and returns null when Idle`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }

        val ride = manager.stop()

        assertNull(ride)
        assertEquals(RideSessionState.Idle, manager.state.value)
    }

    @Test
    fun `stop with zero elapsed seconds persists a zero-duration ride without crashing`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        val ride = manager.stop()

        requireNotNull(ride)
        assertEquals(0, ride.durationSec)
        assertEquals(0.0, ride.outputKj, 0.0001)
        assertEquals(0, rideRepository.getSamples(ride.id).size)
    }

    // --- reset() ---------------------------------------------------------------------------

    @Test
    fun `reset returns Finished to Idle with zeroed state`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()
        manager.stop()

        manager.reset()

        assertEquals(RideSessionState.Idle, manager.state.value)
        assertEquals(0, manager.elapsedSec.value)
        assertEquals(LiveAggregates(), manager.liveAggregates.value)
    }

    @Test
    fun `reset is a no-op unless Finished`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        manager.reset() // Active, should be ignored

        assertEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `a fresh ride after reset starts sample numbering back at zero`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(2_000)
        runCurrent()
        manager.stop()
        manager.reset()

        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(3_000)
        runCurrent()
        val secondRide = manager.stop()

        requireNotNull(secondRide)
        assertEquals(3, secondRide.durationSec)
        assertEquals((0 until 3).toList(), rideRepository.getSamples(secondRide.id).map { it.tSec })
    }

    // --- Auto-pause / auto-resume on freewheel (T20/#20) -------------------------------------

    @Test
    fun `auto-pauses after the cadence-zero threshold once the rider has pedaled`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope, autoPauseThresholdSec = 3,
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        // Pedal for 2 s so the "has pedaled this stretch" gate is satisfied.
        fakeBikeDataSource.setMetrics(cadenceRpm = 85, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(RideSessionState.Active, manager.state.value)

        // Coast: cadence drops to 0. After 3 consecutive zero-cadence seconds → auto-pause.
        fakeBikeDataSource.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        advanceTimeBy(3_000)
        runCurrent()

        assertEquals(RideSessionState.Paused, manager.state.value)
        assertTrue(manager.autoPaused.value)
        assertTrue(!manager.isRideActive.value)
    }

    @Test
    fun `does not auto-pause a ride whose cadence never left zero`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope, autoPauseThresholdSec = 3,
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        // Never pedaled (cadence stays at the default 0) — the "has pedaled" gate blocks it.
        advanceTimeBy(10_000)
        runCurrent()

        assertEquals(RideSessionState.Active, manager.state.value)
        assertTrue(!manager.autoPaused.value)
    }

    @Test
    fun `auto-resumes when cadence returns after an auto-pause`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope, autoPauseThresholdSec = 3,
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 85, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(2_000)
        runCurrent()
        fakeBikeDataSource.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        advanceTimeBy(3_000)
        runCurrent()
        assertEquals(RideSessionState.Paused, manager.state.value)
        val elapsedAtPause = manager.elapsedSec.value

        // Rider pedals again → the resume-watcher flips it back to Active on the next poll.
        fakeBikeDataSource.setMetrics(cadenceRpm = 70, resistancePercent = 40, powerWatts = 120)
        advanceTimeBy(1_000)
        runCurrent()

        assertEquals(RideSessionState.Active, manager.state.value)
        assertTrue(!manager.autoPaused.value)
        assertTrue(manager.isRideActive.value)

        // And it keeps timing from where it auto-paused (no time lost/gained while coasting-paused).
        advanceTimeBy(2_000)
        runCurrent()
        assertEquals(elapsedAtPause + 2, manager.elapsedSec.value)
    }

    @Test
    fun `a manual pause does not auto-resume when the rider pedals`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope, autoPauseThresholdSec = 3,
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 85, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(2_000)
        runCurrent()

        manager.pause()
        assertTrue(!manager.autoPaused.value)

        // Still pedaling hard — a manual pause must stay paused (no watcher running).
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(RideSessionState.Paused, manager.state.value)
    }

    @Test
    fun `a manual pause during an auto-pause stops it auto-resuming`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope, autoPauseThresholdSec = 3,
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 85, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(2_000)
        runCurrent()
        fakeBikeDataSource.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        advanceTimeBy(3_000)
        runCurrent()
        assertTrue(manager.autoPaused.value)

        manager.pause()
        assertTrue(!manager.autoPaused.value)
        fakeBikeDataSource.setMetrics(cadenceRpm = 85, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(5_000)
        runCurrent()

        assertEquals(RideSessionState.Paused, manager.state.value)
        manager.resume()
        assertEquals(RideSessionState.Active, manager.state.value)
    }

    @Test
    fun `threshold of zero disables auto-pause entirely`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope, autoPauseThresholdSec = 0,
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 85, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(2_000)
        runCurrent()
        fakeBikeDataSource.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)

        advanceTimeBy(30_000)
        runCurrent()

        assertEquals(RideSessionState.Active, manager.state.value)
        assertTrue(!manager.autoPaused.value)
    }

    @Test
    fun `manual resume after an auto-pause clears the auto-paused flag`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope, autoPauseThresholdSec = 3,
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 85, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(2_000)
        runCurrent()
        fakeBikeDataSource.setMetrics(cadenceRpm = 0, resistancePercent = 40, powerWatts = 0)
        advanceTimeBy(3_000)
        runCurrent()
        assertTrue(manager.autoPaused.value)

        manager.resume()

        assertEquals(RideSessionState.Active, manager.state.value)
        assertTrue(!manager.autoPaused.value)
        // The stale resume-watcher must not later re-toggle state; advance well past a poll.
        advanceTimeBy(5_000)
        runCurrent()
        assertEquals(RideSessionState.Active, manager.state.value)
    }

    // --- Ride goals (T13/#13) ----------------------------------------------------------------

    @Test
    fun `goal defaults to None`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }

        assertEquals(RideGoal.None, manager.goal.value)
    }

    @Test
    fun `setGoal takes effect while Idle`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }

        manager.setGoal(RideGoal.Duration(targetSec = 600))

        assertEquals(RideGoal.Duration(600), manager.goal.value)
    }

    @Test
    fun `setGoal is a no-op once the ride has started`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)

        manager.setGoal(RideGoal.Output(targetKj = 100.0))

        assertEquals(RideGoal.None, manager.goal.value)
    }

    @Test
    fun `goal persists through the ride and is cleared by reset`() = runTest {
        val manager = RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope) { 0L }
        manager.setGoal(RideGoal.Duration(targetSec = 300))
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        advanceTimeBy(1_000)
        runCurrent()
        assertEquals(RideGoal.Duration(300), manager.goal.value)

        manager.stop()
        assertEquals(RideGoal.Duration(300), manager.goal.value) // still visible on the summary path

        manager.reset()
        assertEquals(RideGoal.None, manager.goal.value)
    }

    // --- Telemetry (#85) ------------------------------------------------------------------

    private val telemetry = RecordingTelemetry()

    private fun TestScope.telemetryManager(tracker: RideTelemetryTracker? = null) =
        RideSessionManager(fakeBikeDataSource, rideRepository, backgroundScope, telemetry = telemetry, rideTracker = tracker) { 0L }

    @Test
    fun `start emits ride_start with type, entry and route`() = runTest {
        val manager = telemetryManager()
        manager.start(profileId, videoId = "abc", entry = RideEntry.CLASSES, route = true)
        assertEquals(listOf<TelemetryEvent>(RideStart(RideType.CLASS, RideEntry.CLASSES, true)), telemetry.events)
    }

    @Test
    fun `start infers just ride and games`() = runTest {
        val a = telemetryManager()
        a.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        a.discard(DiscardReason.TOO_SHORT)
        a.start(profileId, gamePlan = "visit", entry = RideEntry.GAMES, route = false)
        assertEquals(
            listOf(RideType.JUST_RIDE, RideType.JUST_RIDE, RideType.GAMES),
            telemetry.events.map { (it as? RideStart)?.type ?: (it as RideEnd).type },
        )
    }

    @Test
    fun `stop emits saved with the active duration, excluding the pause`() = runTest {
        val manager = telemetryManager()
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        fakeBikeDataSource.setMetrics(cadenceRpm = 80, resistancePercent = 40, powerWatts = 150)
        advanceTimeBy(10 * 60_000L)
        runCurrent()
        manager.pause()
        advanceTimeBy(20 * 60_000L)
        runCurrent()
        manager.resume()
        manager.stop()

        val end = telemetry.events.last() as RideEnd
        assertEquals(RideOutcome.SAVED, end.outcome)
        assertEquals(DiscardReason.NONE, end.discardReason)
        assertEquals(DurationBucket.M5_15, end.duration)
    }

    @Test
    fun `discard emits the reason`() = runTest {
        val manager = telemetryManager()
        manager.start(profileId, gamePlan = "visit", entry = RideEntry.GAMES, route = false)
        advanceTimeBy(5_000)
        runCurrent()
        manager.discard(DiscardReason.NO_PEDALLING)

        val end = telemetry.events.last() as RideEnd
        assertEquals(RideOutcome.DISCARDED, end.outcome)
        assertEquals(DiscardReason.NO_PEDALLING, end.discardReason)
        assertEquals(DurationBucket.LT_5M, end.duration)
    }

    @Test
    fun `a throwing telemetry never reaches the ride`() = runTest {
        val manager = RideSessionManager(
            fakeBikeDataSource, rideRepository, backgroundScope,
            telemetry = object : Telemetry {
                override fun track(event: TelemetryEvent) = error("boom")
            },
        ) { 0L }
        manager.start(profileId, entry = RideEntry.HOME_QUICK_START, route = false)
        assertEquals(RideSessionState.Active, manager.state.value)
        assertTrue(manager.stop() != null)
        assertTrue(manager.state.value is RideSessionState.Finished)
    }
}
