package dev.digitalducktape.openride.ui.profile

import dev.digitalducktape.openride.core.controller.ControllerAction
import dev.digitalducktape.openride.core.controller.ControllerStatus
import dev.digitalducktape.openride.core.controller.ControllerTransport
import dev.digitalducktape.openride.core.controller.PairedController
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.sensor.ConnectionState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ControllersLabelsTest {
    private val phone = PairedController(ControllerTransport.NETWORK, "BikeControl", "BikeControl")
    private val shifter = PairedController(ControllerTransport.BLUETOOTH, "AA:BB:CC:DD:EE:FF", null)

    @Test
    fun `a controller without a name reads its address`() {
        assertEquals("AA:BB:CC:DD:EE:FF", ControllersLabels.title(shifter))
        assertEquals("BikeControl", ControllersLabels.title(phone))
    }

    @Test
    fun `status says how it connects, and its battery once connected`() {
        assertEquals("Connected  •  Wi-Fi  •  80% battery", ControllersLabels.status(phone, ControllerStatus(phone, ConnectionState.Connected, 80)))
        assertEquals("Connected  •  Bluetooth", ControllersLabels.status(shifter, ControllerStatus(shifter, ConnectionState.Connected, null)))
        assertEquals("Bluetooth  •  Reconnecting…", ControllersLabels.status(shifter, ControllerStatus(shifter, ConnectionState.Disconnected, null)))
        assertEquals("Wi-Fi  •  Connects when it's on", ControllersLabels.status(phone, null))
    }

    @Test
    fun `the test line names the last press`() {
        assertEquals("Last press: Resistance up", ControllersLabels.lastPress(ControllerAction.RESISTANCE_UP))
        assertEquals("Press a button on a controller to try it", ControllersLabels.lastPress(null))
    }

    @Test
    fun `the empty hint shows only when a search found nothing new`() {
        assertTrue(ControllersLabels.emptyHint(ControllersViewModel.UiState()) != null)
        assertNull(ControllersLabels.emptyHint(ControllersViewModel.UiState(isScanning = true)))
        assertNull(ControllersLabels.emptyHint(ControllersViewModel.UiState(found = listOf(phone))))
        assertTrue(ControllersLabels.emptyHint(ControllersViewModel.UiState(found = listOf(phone), paired = listOf(phone))) != null)
    }

    @Test
    fun `bluetooth permission is asked for, not required`() {
        assertNull(ControllersLabels.permissionPrompt(BlePermissionState.Granted))
        assertEquals(false, ControllersLabels.permissionPrompt(BlePermissionState.NotRequested)!!.opensAppSettings)
        assertEquals(true, ControllersLabels.permissionPrompt(BlePermissionState.PermanentlyDenied)!!.opensAppSettings)
    }

    @Test
    fun `the profile row counts paired and connected controllers`() {
        assertEquals("Shifters, buttons, BikeControl", ProfileTabLabels.controllers(0, 0))
        assertEquals("2 paired", ProfileTabLabels.controllers(2, 0))
        assertEquals("1 of 2 connected", ProfileTabLabels.controllers(2, 1))
    }
}
