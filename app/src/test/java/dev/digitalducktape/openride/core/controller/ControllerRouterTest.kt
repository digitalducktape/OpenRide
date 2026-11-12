@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.core.controller

import dev.digitalducktape.openride.core.ride.RideSessionState
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

class ControllerRouterTest {
    private val events = MutableSharedFlow<ControllerEvent>(extraBufferCapacity = 16)
    private val calls = mutableListOf<String>()
    private var gameOpen = false
    private var ride: RideSessionState = RideSessionState.Idle

    private fun TestScope.router() = ControllerRouter(
        events = events,
        scope = backgroundScope,
        gameSessionActive = { gameOpen },
        pauseGame = { calls += "pauseGame" },
        resumeGame = { calls += "resumeGame" },
        rideState = { ride },
        pauseRide = { calls += "pauseRide" },
        resumeRide = { calls += "resumeRide" },
        stepResistance = { calls += "resistance $it" },
    ).also { runCurrent() }

    private fun TestScope.press(action: ControllerAction) {
        events.tryEmit(ControllerEvent(action, pressed = true))
        runCurrent()
    }

    @Test
    fun `pause and resume go to the ride being recorded`() = runTest {
        router()
        ride = RideSessionState.Active
        press(ControllerAction.PAUSE)
        ride = RideSessionState.Paused
        press(ControllerAction.RESUME)

        assertEquals(listOf("pauseRide", "resumeRide"), calls)
    }

    @Test
    fun `pause and resume go to the games while a game is open`() = runTest {
        router()
        gameOpen = true
        ride = RideSessionState.Active
        press(ControllerAction.PAUSE)
        press(ControllerAction.RESUME)

        assertEquals(listOf("pauseGame", "resumeGame"), calls)
    }

    @Test
    fun `pause with no ride, or resume of a running one, does nothing`() = runTest {
        router()
        press(ControllerAction.PAUSE)
        ride = RideSessionState.Active
        press(ControllerAction.RESUME)

        assertEquals(emptyList<String>(), calls)
    }

    @Test
    fun `use item counts presses, not releases`() = runTest {
        val router = router()
        press(ControllerAction.USE_ITEM)
        events.tryEmit(ControllerEvent(ControllerAction.USE_ITEM, pressed = false))
        runCurrent()
        press(ControllerAction.USE_ITEM)

        assertEquals(2, router.itemPresses)
    }

    @Test
    fun `resistance buttons step the resistance`() = runTest {
        router()
        press(ControllerAction.RESISTANCE_UP)
        press(ControllerAction.RESISTANCE_DOWN)

        assertEquals(listOf("resistance 1", "resistance -1"), calls)
    }
}
