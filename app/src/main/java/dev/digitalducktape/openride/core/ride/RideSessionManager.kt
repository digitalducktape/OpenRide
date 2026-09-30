package dev.digitalducktape.openride.core.ride

import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideRepository
import dev.digitalducktape.openride.core.data.RideSample
import dev.digitalducktape.openride.core.sensor.BikeDataSource
import kotlin.math.max
import kotlin.math.roundToInt
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** A no-op heart-rate source: no strap paired, so every sample records a `null` bpm. */
private val NO_HEART_RATE: StateFlow<Int?> = MutableStateFlow(null).asStateFlow()

/**
 * Drives a single ride from start to finish: `Idle -> Active <-> Paused -> Finished`.
 *
 * While [RideSessionState.Active], an internal 1 Hz coroutine ticker (using the same
 * "tick via `delay`, driven by an injected [CoroutineScope]" pattern as
 * [dev.digitalducktape.openride.core.sensor.MockBikeDataSource], so tests can drive it with
 * virtual time) both advances [elapsedSec] and samples [BikeDataSource.metrics] into an
 * in-memory buffer. Pausing cancels the ticker so neither the elapsed timer nor the sample
 * buffer advance; resuming starts a fresh ticker that continues exactly where the old one
 * left off — no time or samples are lost or duplicated across a pause/resume cycle.
 *
 * [stop] computes final aggregates from the buffer and persists the ride + full sample
 * series via [RideRepository] in one transaction, then transitions to
 * [RideSessionState.Finished].
 *
 * @param scope coroutine scope the 1 Hz ticker runs on. Pass a `TestScope`'s
 *   `backgroundScope` in tests to drive the simulation with virtual time.
 * @param heartRateBpm live bpm from whichever strap is currently paired (PRD P1-4, T17) —
 *   sampled into each [RideSample.heartRateBpm] alongside cadence/resistance/power. Defaults
 *   to a source that's always `null` (no strap), so every existing call site that doesn't
 *   care about heart rate is unaffected. Production wiring passes
 *   [dev.digitalducktape.openride.core.heartrate.HeartRateManager.bpm]; tests can pass a
 *   plain `MutableStateFlow<Int?>`.
 * @param autoPauseThresholdSec consecutive seconds of zero cadence — *after the rider has
 *   actually pedaled during the current Active stretch* — that trigger an automatic pause
 *   (PRD #20/T20, freewheel detection). Gating on "has pedaled" means a ride whose cadence
 *   simply starts at (or never leaves) zero never auto-pauses: this is specifically about a
 *   *spinning* rider coasting to a stop, not a sensor reading zero because nobody's on the
 *   bike. Auto-pause auto-resumes the instant cadence returns. Set to `0` (or negative) to
 *   disable auto-pause entirely; the default of 3 s matches the stock bike's freewheel feel.
 * @param epochMillisProvider supplies the ride's start wall-clock time; injectable so tests
 *   don't depend on real time.
 */
class RideSessionManager(
    private val bikeDataSource: BikeDataSource,
    private val rideRepository: RideRepository,
    private val scope: CoroutineScope,
    private val heartRateBpm: StateFlow<Int?> = NO_HEART_RATE,
    private val autoPauseThresholdSec: Int = 3,
    private val epochMillisProvider: () -> Long = System::currentTimeMillis,
) {
    private val _state = MutableStateFlow<RideSessionState>(RideSessionState.Idle)
    val state: StateFlow<RideSessionState> = _state.asStateFlow()

    private val _elapsedSec = MutableStateFlow(0)
    val elapsedSec: StateFlow<Int> = _elapsedSec.asStateFlow()

    private val _liveAggregates = MutableStateFlow(LiveAggregates())
    val liveAggregates: StateFlow<LiveAggregates> = _liveAggregates.asStateFlow()

    private val _goal = MutableStateFlow<RideGoal>(RideGoal.None)
    /** The rider's pre-ride target (PRD P1-3), if any. Set via [setGoal] before [start]. */
    val goal: StateFlow<RideGoal> = _goal.asStateFlow()

    /**
     * `true` only while [RideSessionState.Active] — a UI-agnostic signal the activity maps
     * to `FLAG_KEEP_SCREEN_ON` (PRD P0-10). Deliberately `false` while
     * [RideSessionState.Paused]: the "screen flag set only while ride active" acceptance
     * criterion is about the Active state specifically.
     */
    private val _isRideActive = MutableStateFlow(false)
    val isRideActive: StateFlow<Boolean> = _isRideActive.asStateFlow()

    /**
     * `true` while the ride is paused *because the rider stopped pedaling* (PRD #20/T20), as
     * opposed to a manual [pause]. Only an auto-pause auto-resumes when cadence returns; a
     * manual pause stays paused until [resume]. Lets the UI label the two differently while
     * both still report [RideSessionState.Paused].
     */
    private val _autoPaused = MutableStateFlow(false)
    val autoPaused: StateFlow<Boolean> = _autoPaused.asStateFlow()

    private var profileId: Long = 0
    private var videoId: String? = null
    private var gamePlan: String? = null
    private var rideStartEpochMs: Long = 0
    private var tickerJob: Job? = null
    private var resumeWatcherJob: Job? = null
    // Freewheel tracking for the current Active stretch (reset on every entry into Active).
    private var zeroCadenceStreak: Int = 0
    private var hasPedaledThisStretch: Boolean = false
    private val sampleBuffer = mutableListOf<RideSample>()

    private var sumCadence: Long = 0
    private var sumPower: Long = 0
    private var sumResistance: Long = 0
    private var maxCadenceSeen: Int = 0
    private var maxPowerSeen: Int = 0

    /**
     * Starts a new ride for [profileId]. No-op if not currently [RideSessionState.Idle].
     * [videoId] is the class the ride plays in the in-app player (v2), recorded on the
     * persisted ride for the Classes tab's "taken" badges; `null` for a Quick Start.
     * [gamePlan] is the mini-games session plan the ride records (#35), saved as
     * [Ride.gamePlan]; `null` for any other ride.
     */
    fun start(profileId: Long, videoId: String? = null, gamePlan: String? = null) {
        if (_state.value != RideSessionState.Idle) return

        this.profileId = profileId
        this.videoId = videoId
        this.gamePlan = gamePlan
        rideStartEpochMs = epochMillisProvider()
        sampleBuffer.clear()
        sumCadence = 0
        sumPower = 0
        sumResistance = 0
        maxCadenceSeen = 0
        maxPowerSeen = 0
        _elapsedSec.value = 0
        _liveAggregates.value = LiveAggregates()
        resetFreewheelTracking()

        _state.value = RideSessionState.Active
        _isRideActive.value = true
        startTicker()
    }

    /** Clears the per-stretch freewheel counters so a fresh Active stretch can't inherit a
     *  stale zero-cadence streak (which would auto-pause the moment it starts). */
    private fun resetFreewheelTracking() {
        zeroCadenceStreak = 0
        hasPedaledThisStretch = false
    }

    /**
     * Sets the rider's pre-ride goal (PRD P1-3). Only takes effect while
     * [RideSessionState.Idle] — a goal is a pre-ride decision, not something that changes
     * mid-ride — so this is a no-op once [start] has moved past Idle.
     */
    fun setGoal(goal: RideGoal) {
        if (_state.value != RideSessionState.Idle) return
        _goal.value = goal
    }

    /**
     * Manually pauses timer/sampling. A manual pause is deliberately *not* an [autoPaused] one,
     * so it will not auto-resume when the rider starts pedaling again — only [resume] brings it
     * back. During an auto-pause it turns that pause into a manual one (a game's pause button
     * can be pressed while freewheeling, #35); otherwise it is a no-op unless
     * [RideSessionState.Active].
     */
    fun pause() {
        if (_state.value == RideSessionState.Paused && _autoPaused.value) {
            resumeWatcherJob?.cancel()
            resumeWatcherJob = null
            _autoPaused.value = false
            return
        }
        if (_state.value != RideSessionState.Active) return

        tickerJob?.cancel()
        tickerJob = null
        _autoPaused.value = false
        _state.value = RideSessionState.Paused
        _isRideActive.value = false
    }

    /**
     * Resumes timer/sampling from where it left off (whether the pause was manual or an
     * auto-pause). No-op unless [RideSessionState.Paused]. Cancels any freewheel resume-watcher
     * and starts the current Active stretch's freewheel tracking fresh.
     */
    fun resume() {
        if (_state.value != RideSessionState.Paused) return

        resumeWatcherJob?.cancel()
        resumeWatcherJob = null
        _autoPaused.value = false
        resetFreewheelTracking()
        _state.value = RideSessionState.Active
        _isRideActive.value = true
        startTicker()
    }

    /**
     * Stops the ride, computes final aggregates, and persists the ride + samples in one
     * transaction (via [RideRepository.saveRide]). Returns the persisted [Ride], or `null`
     * if called outside [RideSessionState.Active]/[RideSessionState.Paused].
     */
    suspend fun stop(): Ride? {
        val current = _state.value
        if (current !is RideSessionState.Active && current !is RideSessionState.Paused) return null

        tickerJob?.cancel()
        tickerJob = null
        resumeWatcherJob?.cancel()
        resumeWatcherJob = null
        _autoPaused.value = false
        _isRideActive.value = false

        val aggregates = _liveAggregates.value
        // Each sample represents one second, so power (watts = joules/sec) summed across
        // samples is total joules; /1000 converts to kilojoules.
        val outputKj = sampleBuffer.sumOf { it.power } / 1000.0
        // Common indoor-cycling approximation: kcal ~= kJ x 0.96 (roughly accounting for
        // human mechanical efficiency without needing rider weight for this formula).
        val calories = (outputKj * KCAL_PER_KJ).roundToInt()

        val ride = Ride(
            profileId = profileId,
            startEpochMs = rideStartEpochMs,
            durationSec = _elapsedSec.value,
            avgCadence = aggregates.avgCadence,
            maxCadence = aggregates.maxCadence,
            avgPower = aggregates.avgPower,
            maxPower = aggregates.maxPower,
            avgResistance = aggregates.avgResistance,
            outputKj = outputKj,
            calories = calories,
            videoId = videoId,
            gamePlan = gamePlan,
        )

        val rideId = rideRepository.saveRide(ride, sampleBuffer.toList())
        val savedRide = ride.copy(id = rideId)
        _state.value = RideSessionState.Finished(savedRide)
        return savedRide
    }

    /** Returns to [RideSessionState.Idle], ready for another ride. No-op unless [RideSessionState.Finished]. */
    fun reset() {
        if (_state.value !is RideSessionState.Finished) return

        resumeWatcherJob?.cancel()
        resumeWatcherJob = null
        _autoPaused.value = false
        resetFreewheelTracking()
        _elapsedSec.value = 0
        _liveAggregates.value = LiveAggregates()
        sampleBuffer.clear()
        _goal.value = RideGoal.None
        _state.value = RideSessionState.Idle
    }

    private fun startTicker() {
        tickerJob = scope.launch {
            while (isActive) {
                delay(TICK_INTERVAL_MS)

                val newElapsed = _elapsedSec.value + 1
                _elapsedSec.value = newElapsed

                val metrics = bikeDataSource.metrics.value
                sampleBuffer.add(
                    RideSample(
                        rideId = 0L, // resolved to the real generated id by RideRepository.saveRide
                        tSec = newElapsed - 1,
                        cadence = metrics.cadenceRpm,
                        resistance = metrics.resistancePercent,
                        power = metrics.powerWatts,
                        heartRateBpm = heartRateBpm.value,
                    ),
                )

                sumCadence += metrics.cadenceRpm
                sumPower += metrics.powerWatts
                sumResistance += metrics.resistancePercent
                maxCadenceSeen = max(maxCadenceSeen, metrics.cadenceRpm)
                maxPowerSeen = max(maxPowerSeen, metrics.powerWatts)

                val n = sampleBuffer.size
                _liveAggregates.value = LiveAggregates(
                    avgCadence = (sumCadence / n).toInt(),
                    maxCadence = maxCadenceSeen,
                    avgPower = (sumPower / n).toInt(),
                    maxPower = maxPowerSeen,
                    avgResistance = (sumResistance / n).toInt(),
                )

                // Freewheel detection (PRD #20/T20): once the rider has actually pedaled this
                // stretch, a run of zero-cadence seconds past the threshold auto-pauses.
                if (metrics.cadenceRpm > 0) {
                    hasPedaledThisStretch = true
                    zeroCadenceStreak = 0
                } else if (hasPedaledThisStretch) {
                    zeroCadenceStreak++
                    if (autoPauseThresholdSec > 0 && zeroCadenceStreak >= autoPauseThresholdSec) {
                        autoPause()
                        return@launch
                    }
                }
            }
        }
    }

    /**
     * Auto-pauses because the rider stopped pedaling (PRD #20/T20). Unlike [pause], this marks
     * [autoPaused] and starts a watcher that auto-resumes the moment cadence returns.
     */
    private fun autoPause() {
        if (_state.value != RideSessionState.Active) return

        tickerJob?.cancel()
        tickerJob = null
        _autoPaused.value = true
        _state.value = RideSessionState.Paused
        _isRideActive.value = false
        startResumeWatcher()
    }

    /**
     * While auto-paused, polls cadence at the same 1 Hz cadence as the main ticker and
     * auto-resumes as soon as the rider pedals again. Only ever runs for an auto-pause — a
     * manual [pause] starts no watcher, so it never auto-resumes.
     */
    private fun startResumeWatcher() {
        resumeWatcherJob = scope.launch {
            while (isActive) {
                delay(TICK_INTERVAL_MS)
                if (_state.value != RideSessionState.Paused || !_autoPaused.value) return@launch
                if (bikeDataSource.metrics.value.cadenceRpm > 0) {
                    resumeWatcherJob = null
                    _autoPaused.value = false
                    resetFreewheelTracking()
                    _state.value = RideSessionState.Active
                    _isRideActive.value = true
                    startTicker()
                    return@launch
                }
            }
        }
    }

    companion object {
        private const val TICK_INTERVAL_MS = 1000L
        private const val KCAL_PER_KJ = 0.96
    }
}
