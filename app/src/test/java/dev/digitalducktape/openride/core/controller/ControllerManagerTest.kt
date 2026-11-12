@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.core.controller

import dev.digitalducktape.openride.core.controller.ObcProtocol.Button
import dev.digitalducktape.openride.core.sensor.ConnectionState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ControllerManagerTest {
    private class FakeLink(val controller: PairedController) : ObcLink {
        override val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
        override val batteryPercent: StateFlow<Int?> = MutableStateFlow(null)
        var started = false
        var stopped = false
        val haptics = mutableListOf<Int>()
        private var onMessage: (ObcMessage) -> Unit = {}

        override fun start(onMessage: (ObcMessage) -> Unit) {
            started = true
            this.onMessage = onMessage
        }

        override fun stop() { stopped = true }
        override fun haptic(pattern: Int) { haptics += pattern }

        fun send(vararg buttons: ObcButton) = onMessage(ObcMessage.ButtonState(buttons.toList()))
    }

    private val shifter = PairedController(ControllerTransport.BLUETOOTH, "AA:BB:CC:DD:EE:FF", "Shifter")
    private val phone = PairedController(ControllerTransport.NETWORK, "BikeControl", "BikeControl")
    private val links = mutableListOf<FakeLink>()

    private fun TestScope.manager(store: ControllerStore, wanted: MutableStateFlow<Boolean> = MutableStateFlow(true)) =
        ControllerManager(store, { FakeLink(it).also(links::add) }, backgroundScope, wanted)

    private fun TestScope.recordEvents(manager: ControllerManager): MutableList<ControllerEvent> {
        val events = mutableListOf<ControllerEvent>()
        backgroundScope.launch { manager.events.collect { events += it } }
        runCurrent()
        return events
    }

    private fun pressed(id: Int) = ObcButton(id, ObcProtocol.PRESSED)
    private fun released(id: Int) = ObcButton(id, ObcProtocol.RELEASED)

    @Test
    fun `connects every paired controller`() = runTest {
        val manager = manager(InMemoryControllerStore(listOf(shifter, phone)))
        runCurrent()

        assertEquals(listOf(shifter, phone), links.map { it.controller })
        assertTrue(links.all { it.started })
        assertEquals(listOf(shifter, phone), manager.statuses.value.map { it.controller })
    }

    @Test
    fun `forgetting a controller stops its link`() = runTest {
        val store = InMemoryControllerStore(listOf(shifter, phone))
        manager(store)
        runCurrent()

        store.remove(shifter)
        runCurrent()

        assertTrue(links.first { it.controller == shifter }.stopped)
        assertFalse(links.first { it.controller == phone }.stopped)
    }

    @Test
    fun `not wanted lets every controller go, and wanted again reconnects`() = runTest {
        val wanted = MutableStateFlow(true)
        manager(InMemoryControllerStore(listOf(shifter)), wanted)
        runCurrent()

        wanted.value = false
        runCurrent()
        assertTrue(links.single().stopped)

        wanted.value = true
        runCurrent()
        assertEquals(2, links.size)
        assertTrue(links.last().started)
    }

    @Test
    fun `button presses become actions`() = runTest {
        val manager = manager(InMemoryControllerStore(listOf(shifter)))
        val events = recordEvents(manager)

        links.single().send(pressed(Button.PAUSE))
        runCurrent()

        assertEquals(listOf(ControllerEvent(ControllerAction.PAUSE, pressed = true)), events)
        assertEquals(ControllerAction.PAUSE, manager.lastPress.value)
    }

    @Test
    fun `a held resistance button repeats until released`() = runTest {
        val manager = manager(InMemoryControllerStore(listOf(shifter)))
        val events = recordEvents(manager)

        links.single().send(pressed(Button.SHIFT_UP))
        runCurrent()
        advanceTimeBy(ControllerManager.REPEAT_AFTER_MS + 2 * ControllerManager.REPEAT_EVERY_MS + 1)
        links.single().send(released(Button.SHIFT_UP))
        runCurrent()
        advanceTimeBy(1_000)

        val presses = events.count { it.action == ControllerAction.RESISTANCE_UP && it.pressed }
        assertEquals(1 + 3, presses)
        assertEquals(ControllerEvent(ControllerAction.RESISTANCE_UP, pressed = false), events.last())
    }

    @Test
    fun `a dropped link releases what it held`() = runTest {
        val manager = manager(InMemoryControllerStore(listOf(shifter)))
        val events = recordEvents(manager)
        val link = links.single()
        link.connectionState.value = ConnectionState.Connected
        runCurrent()
        link.send(pressed(Button.SHIFT_DOWN), pressed(Button.STEER_LEFT))
        runCurrent()
        assertEquals(-1.0, manager.steer.value!!, 0.0)

        link.connectionState.value = ConnectionState.Disconnected
        runCurrent()
        advanceTimeBy(1_000)

        assertEquals(ControllerEvent(ControllerAction.RESISTANCE_DOWN, pressed = false), events.last())
        assertNull(manager.steer.value)
        assertEquals(ConnectionState.Disconnected, manager.statuses.value.single().connection)
    }

    @Test
    fun `steering is null until a controller steers, and sums across controllers`() = runTest {
        val manager = manager(InMemoryControllerStore(listOf(shifter, phone)))
        runCurrent()
        links[0].send(pressed(Button.SHIFT_UP))
        runCurrent()
        assertNull(manager.steer.value)

        links[0].send(ObcButton(Button.STEERING_ANGLE, 0x80 + 20)) // 10° right
        links[1].send(pressed(Button.STEER_RIGHT))
        runCurrent()

        assertEquals(1.0, manager.steer.value!!, 0.0)
    }

    @Test
    fun `haptics go to every controller`() = runTest {
        val manager = manager(InMemoryControllerStore(listOf(shifter, phone)))
        runCurrent()

        manager.haptic(ObcProtocol.HAPTIC_SHORT)

        assertEquals(listOf(listOf(ObcProtocol.HAPTIC_SHORT), listOf(ObcProtocol.HAPTIC_SHORT)), links.map { it.haptics })
    }
}
