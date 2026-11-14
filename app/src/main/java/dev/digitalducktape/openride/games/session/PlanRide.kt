package dev.digitalducktape.openride.games.session

import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map

/**
 * The plan runner's view of the ride a hub visit records (spec §2, "split the visit from the
 * plan runner"). The visit starts and saves the ride; the plan runner only pauses and resumes
 * it for the rider's pause button, follows its freewheel auto-pause, and reads its clock.
 */
interface PlanRide {
    /** Ride seconds so far, pauses excluded: the clock each result's `startSec` is on. */
    val elapsedSec: Int

    /** Paused for any reason: the rider's (manual) pause, or the ride's freewheel auto-pause. */
    val isPaused: Boolean

    /** [isPaused] as it changes. */
    val pausedChanges: Flow<Boolean>

    /**
     * Whether the freewheel auto-pause may fire. The plan turns it off while the rider sets up
     * (intro card, camera calibration); turning it off also ends an auto-pause in force.
     */
    var autoPauseAllowed: Boolean

    /** A manual pause: it doesn't end when the rider pedals again. */
    fun pause()

    /** Ends any pause, manual or automatic. */
    fun resume()
}

/** A visit that isn't recording (no active rider, or another ride holds the recorder). */
object NoRide : PlanRide {
    override val elapsedSec: Int get() = 0
    override val isPaused: Boolean get() = false
    override val pausedChanges: Flow<Boolean> = flowOf(false)
    override var autoPauseAllowed: Boolean
        get() = true
        set(_) = Unit
    override fun pause() = Unit
    override fun resume() = Unit
}

/** The app's ride, through [RideSessionManager], once the visit has started it. */
class RideSessionPlanRide(private val rides: RideSessionManager) : PlanRide {
    override val elapsedSec: Int get() = rides.elapsedSec.value
    override val isPaused: Boolean get() = rides.state.value == RideSessionState.Paused
    override val pausedChanges: Flow<Boolean> = rides.state.map { it == RideSessionState.Paused }.distinctUntilChanged()
    override var autoPauseAllowed: Boolean
        get() = rides.autoPauseAllowed
        set(value) { rides.autoPauseAllowed = value }
    override fun pause() = rides.pause()
    override fun resume() = rides.resume()
}
