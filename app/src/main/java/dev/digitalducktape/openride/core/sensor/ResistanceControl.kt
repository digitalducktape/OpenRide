package dev.digitalducktape.openride.core.sensor

import kotlinx.coroutines.flow.StateFlow

/**
 * A bike source whose resistance OpenRide sets (issue #68): a smart trainer has no knob, so its
 * resistance is a virtual 0-100 %, stepped by on-screen buttons or a controller's shifters and
 * sent to the trainer. It's what [BikeMetrics.resistancePercent] reports, so every screen and
 * game reads it as they read a Peloton's knob.
 */
interface ResistanceControl {
    /** Whether resistance can be set now (a trainer is the source, and takes targets). */
    val adjustable: StateFlow<Boolean>

    /** Moves the resistance [steps] steps of [RESISTANCE_STEP_PERCENT], clamped to 0-100. */
    fun stepResistance(steps: Int)

    companion object {
        /** One press: a twentieth of the range, so 0-100 takes 20 presses (or a 3 s hold). */
        const val RESISTANCE_STEP_PERCENT = 5
    }
}

/** A [BikeDataSource] with a lifecycle, so the source can be switched in the app (#68). */
interface ManagedBikeDataSource : BikeDataSource {
    /** Starts connecting. Never throws. */
    fun start()

    /** Disconnects and releases everything. Safe before [start]. */
    fun stop()
}
