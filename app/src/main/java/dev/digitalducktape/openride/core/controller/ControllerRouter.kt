package dev.digitalducktape.openride.core.controller

import dev.digitalducktape.openride.core.ride.RideSessionState
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/**
 * Where a controller's presses go (issue #68), for the whole app:
 *
 * - **Pause / Resume** pause the games' session while a games host is open ([gameSessionActive];
 *   it owns the ride then), else the ride being recorded.
 * - **Use item** counts up [itemPresses], which the games read in their input frame.
 * - **Resistance up / down** step the trainer's resistance through [stepResistance], when the
 *   bike source has one to step. A Peloton's knob is its own, so there they do nothing.
 *
 * Releases are ignored: every action here acts on the press.
 */
class ControllerRouter(
    events: Flow<ControllerEvent>,
    scope: CoroutineScope,
    private val gameSessionActive: () -> Boolean,
    private val pauseGame: () -> Unit,
    private val resumeGame: () -> Unit,
    private val rideState: () -> RideSessionState,
    private val pauseRide: () -> Unit,
    private val resumeRide: () -> Unit,
    private val stepResistance: (steps: Int) -> Unit = {},
) {
    private val _itemPresses = AtomicInteger()

    /** Use item presses since the app started; read on the games' thread. */
    val itemPresses: Int get() = _itemPresses.get()

    init {
        events.onEach { if (it.pressed) onPress(it.action) }.launchIn(scope)
    }

    private fun onPress(action: ControllerAction) {
        when (action) {
            ControllerAction.PAUSE -> when {
                gameSessionActive() -> pauseGame()
                rideState() == RideSessionState.Active -> pauseRide()
            }
            ControllerAction.RESUME -> when {
                gameSessionActive() -> resumeGame()
                rideState() == RideSessionState.Paused -> resumeRide()
            }
            ControllerAction.USE_ITEM -> _itemPresses.incrementAndGet()
            ControllerAction.RESISTANCE_UP -> stepResistance(1)
            ControllerAction.RESISTANCE_DOWN -> stepResistance(-1)
        }
    }
}
