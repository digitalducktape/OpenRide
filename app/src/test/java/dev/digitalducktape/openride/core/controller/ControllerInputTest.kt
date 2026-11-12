package dev.digitalducktape.openride.core.controller

import dev.digitalducktape.openride.core.controller.ObcProtocol.Button
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ControllerInputTest {
    private fun press(vararg ids: Int) = ids.map { ObcButton(it, ObcProtocol.PRESSED) }
    private fun release(vararg ids: Int) = ids.map { ObcButton(it, ObcProtocol.RELEASED) }

    @Test
    fun `shift up presses and releases resistance up`() {
        val input = ControllerInput()

        assertEquals(listOf(ControllerEvent(ControllerAction.RESISTANCE_UP, pressed = true)), input.onButtons(press(Button.SHIFT_UP)))
        assertEquals(listOf(ControllerEvent(ControllerAction.RESISTANCE_UP, pressed = false)), input.onButtons(release(Button.SHIFT_UP)))
    }

    @Test
    fun `several ids for one action in one message are one press`() {
        // BikeControl's "Plus": Shift Up and Increase Difficulty together (PROTOCOL.md).
        val input = ControllerInput()

        assertEquals(
            listOf(ControllerEvent(ControllerAction.RESISTANCE_UP, pressed = true)),
            input.onButtons(press(Button.SHIFT_UP, Button.INCREASE_DIFFICULTY)),
        )
    }

    @Test
    fun `the action holds until every id for it is released`() {
        val input = ControllerInput()
        input.onButtons(press(Button.SHIFT_DOWN, Button.DECREASE_DIFFICULTY))

        assertEquals(emptyList<ControllerEvent>(), input.onButtons(release(Button.SHIFT_DOWN)))
        assertEquals(
            listOf(ControllerEvent(ControllerAction.RESISTANCE_DOWN, pressed = false)),
            input.onButtons(release(Button.DECREASE_DIFFICULTY)),
        )
    }

    @Test
    fun `ids OpenRide doesn't use are ignored`() {
        assertEquals(emptyList<ControllerEvent>(), ControllerInput().onButtons(press(0x20, 0x44, 0xA0)))
    }

    @Test
    fun `any power-up uses the item`() {
        val input = ControllerInput()

        assertEquals(listOf(ControllerEvent(ControllerAction.USE_ITEM, pressed = true)), input.onButtons(press(Button.POWER_UP_2)))
    }

    @Test
    fun `a controller that never steered has no steering`() {
        val input = ControllerInput()
        input.onButtons(press(Button.SHIFT_UP))

        assertNull(input.steer)
    }

    @Test
    fun `steer buttons steer fully while held, and centre once released`() {
        val input = ControllerInput()

        input.onButtons(press(Button.STEER_LEFT))
        assertEquals(-1.0, input.steer!!, 0.0)
        input.onButtons(release(Button.STEER_LEFT))
        assertEquals(0.0, input.steer!!, 0.0)
        input.onButtons(press(Button.STEER_RIGHT))
        assertEquals(1.0, input.steer!!, 0.0)
    }

    @Test
    fun `the angle steers in proportion, and wins over the buttons`() {
        val input = ControllerInput()

        input.onButtons(listOf(ObcButton(Button.STEERING_ANGLE, 0x94), ObcButton(Button.STEER_RIGHT, ObcProtocol.PRESSED)))
        assertEquals(10.0 / ControllerInput.FULL_LOCK_DEGREES, input.steer!!, 1e-9)
    }

    @Test
    fun `the angle clamps at full lock`() {
        val input = ControllerInput()

        input.onButtons(listOf(ObcButton(Button.STEERING_ANGLE, 0x02)))
        assertEquals(-1.0, input.steer!!, 0.0)
    }

    @Test
    fun `angle lost falls back to the buttons, or to none`() {
        val angleOnly = ControllerInput()
        angleOnly.onButtons(listOf(ObcButton(Button.STEERING_ANGLE, 0x90)))
        angleOnly.onButtons(listOf(ObcButton(Button.STEERING_ANGLE, 0x00)))
        assertNull(angleOnly.steer)

        val both = ControllerInput()
        both.onButtons(listOf(ObcButton(Button.STEERING_ANGLE, 0x90), ObcButton(Button.STEER_LEFT, ObcProtocol.PRESSED)))
        both.onButtons(listOf(ObcButton(Button.STEERING_ANGLE, 0x00)))
        assertEquals(-1.0, both.steer!!, 0.0)
    }

    @Test
    fun `reset releases everything held and forgets steering`() {
        val input = ControllerInput()
        input.onButtons(press(Button.SHIFT_UP, Button.PAUSE, Button.STEER_LEFT))

        val releases = input.reset()

        assertEquals(
            setOf(ControllerEvent(ControllerAction.RESISTANCE_UP, false), ControllerEvent(ControllerAction.PAUSE, false)),
            releases.toSet(),
        )
        assertNull(input.steer)
    }

    @Test
    fun `app info lists every id OpenRide acts on`() {
        assertEquals(
            setOf(
                Button.SHIFT_UP, Button.SHIFT_DOWN, Button.INCREASE_DIFFICULTY, Button.DECREASE_DIFFICULTY,
                Button.POWER_UP_1, Button.POWER_UP_2, Button.POWER_UP_3, Button.PAUSE, Button.RESUME,
                Button.STEER_LEFT, Button.STEER_RIGHT, Button.STEERING_ANGLE,
            ),
            ControllerAction.supportedButtonIds.toSet(),
        )
    }
}
