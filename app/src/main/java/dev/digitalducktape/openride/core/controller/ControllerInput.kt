package dev.digitalducktape.openride.core.controller

import dev.digitalducktape.openride.core.controller.ObcProtocol.Button

/** What a controller button does in OpenRide (issue #68). Steering is separate: it's a level, not a press. */
enum class ControllerAction(val label: String, val buttonIds: Set<Int>) {
    /** Up a step of resistance: a trainer's virtual resistance (a Peloton's knob is its own). */
    RESISTANCE_UP("Resistance up", setOf(Button.SHIFT_UP, Button.INCREASE_DIFFICULTY)),
    RESISTANCE_DOWN("Resistance down", setOf(Button.SHIFT_DOWN, Button.DECREASE_DIFFICULTY)),

    /** Kart Race's item, which is otherwise a tap on the screen. */
    USE_ITEM("Use item", setOf(Button.POWER_UP_1, Button.POWER_UP_2, Button.POWER_UP_3)),
    PAUSE("Pause", setOf(Button.PAUSE)),
    RESUME("Resume", setOf(Button.RESUME)),
    ;

    companion object {
        /** Every button id OpenRide acts on, for the App Information message. */
        val supportedButtonIds: List<Int> =
            entries.flatMap { it.buttonIds } + listOf(Button.STEER_LEFT, Button.STEER_RIGHT, Button.STEERING_ANGLE)
    }
}

/** A press or a release of one [ControllerAction]. */
data class ControllerEvent(val action: ControllerAction, val pressed: Boolean)

/**
 * One controller's buttons, turned into OpenRide's actions. Fed every button state message the
 * controller sends; pure, so it's tested without a controller (`ControllerInputTest`).
 *
 * - **One press per action.** BikeControl and other controllers may send several ids for one
 *   physical button (PROTOCOL.md, Multiple Actions Per Button), say Shift Up with Increase
 *   Difficulty. Both mean [ControllerAction.RESISTANCE_UP] here, so the action is held while
 *   any of its ids is, and that press counts once.
 * - **Steering** is the proportional angle (`0x1B`) while the controller has one, else Steer
 *   Left / Right held (−1 or +1). It counts as present once the controller has sent either, so
 *   a shifter-only controller never takes the steering from the rider's head lean.
 */
class ControllerInput {
    private val held = mutableSetOf<Int>()
    private var angleDegrees: Double? = null
    private var sentDigitalSteering = false

    /** The actions held right now. */
    val heldActions: Set<ControllerAction>
        get() = ControllerAction.entries.filterTo(mutableSetOf()) { action -> action.buttonIds.any { it in held } }

    /**
     * Steering from −1 (full left) to +1 (full right), or `null` while this controller doesn't
     * steer (it never sent steering, or lost its angle with no buttons to fall back on).
     */
    val steer: Double?
        get() {
            angleDegrees?.let { return (it / FULL_LOCK_DEGREES).coerceIn(-1.0, 1.0) }
            if (!sentDigitalSteering) return null
            val left = if (Button.STEER_LEFT in held) 1.0 else 0.0
            val right = if (Button.STEER_RIGHT in held) 1.0 else 0.0
            return right - left
        }

    /** Applies one button state message; returns the presses and releases it made. */
    fun onButtons(buttons: List<ObcButton>): List<ControllerEvent> {
        val before = heldActions
        for (button in buttons) {
            when (button.id) {
                Button.STEERING_ANGLE -> {
                    // 0x00 means "no angle now"; other values outside the range are no-ops.
                    if (button.state == ObcProtocol.RELEASED) {
                        angleDegrees = null
                    } else {
                        ObcProtocol.steeringAngleDegrees(button.state)?.let { angleDegrees = it }
                    }
                }
                else -> {
                    if (button.id == Button.STEER_LEFT || button.id == Button.STEER_RIGHT) sentDigitalSteering = true
                    // Any non-zero state (pressed, or an analog value) holds the button.
                    if (button.state == ObcProtocol.RELEASED) held -= button.id else held += button.id
                }
            }
        }
        val after = heldActions
        return (after - before).map { ControllerEvent(it, pressed = true) } +
            (before - after).map { ControllerEvent(it, pressed = false) }
    }

    /** The controller went away: everything it held is let go. Returns the releases. */
    fun reset(): List<ControllerEvent> {
        val before = heldActions
        held.clear()
        angleDegrees = null
        sentDigitalSteering = false
        return before.map { ControllerEvent(it, pressed = false) }
    }

    companion object {
        /** The handlebar angle that steers fully: about what a steering block turns either way. */
        const val FULL_LOCK_DEGREES = 25.0
    }
}
