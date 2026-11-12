package dev.digitalducktape.openride.ui.profile

import dev.digitalducktape.openride.core.controller.ControllerAction
import dev.digitalducktape.openride.core.controller.ControllerStatus
import dev.digitalducktape.openride.core.controller.ControllerTransport
import dev.digitalducktape.openride.core.controller.PairedController
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.sensor.ConnectionState

/** The controllers screen's derived text (issue #68), kept out of the composable for tests. */
object ControllersLabels {
    fun title(controller: PairedController): String = controller.name?.takeIf { it.isNotBlank() } ?: controller.id

    fun transport(transport: ControllerTransport): String = when (transport) {
        ControllerTransport.BLUETOOTH -> "Bluetooth"
        ControllerTransport.NETWORK -> "Wi-Fi"
    }

    /** A paired controller's line: how it connects and, once it has, its battery. */
    fun status(controller: PairedController, status: ControllerStatus?): String {
        val via = transport(controller.transport)
        return when (status?.connection) {
            ConnectionState.Connected -> listOfNotNull("Connected", via, status?.batteryPercent?.let { "$it% battery" }).joinToString("  •  ")
            ConnectionState.Disconnected -> "$via  •  Reconnecting…"
            else -> "$via  •  Connects when it's on"
        }
    }

    fun live(status: ControllerStatus?): Boolean = status?.connection == ConnectionState.Connected

    /** The test line: the last button pressed, so the rider sees the controller working. */
    fun lastPress(action: ControllerAction?): String =
        action?.let { "Last press: ${it.label}" } ?: "Press a button on a controller to try it"

    fun scanAction(isScanning: Boolean): String = if (isScanning) "Stop search" else "Search for controllers"

    /** A found controller's second line. */
    fun found(controller: PairedController): String = when (controller.transport) {
        ControllerTransport.BLUETOOTH -> "Bluetooth  •  ${controller.id}"
        ControllerTransport.NETWORK -> "Wi-Fi"
    }

    fun emptyHint(uiState: ControllersViewModel.UiState): String? =
        if (uiState.nearby.isEmpty() && !uiState.isScanning) {
            "Nothing found yet. Turn your controller on, or open BikeControl on your phone on the same Wi-Fi, and tap Search."
        } else {
            null
        }

    /**
     * Why Bluetooth permission is wanted, or `null` once it's granted. The network search runs
     * without it, so this asks rather than blocks.
     */
    fun permissionPrompt(state: BlePermissionState): HrPermissionPrompt? = when (state) {
        BlePermissionState.Granted -> null
        BlePermissionState.NotRequested, BlePermissionState.ShouldShowRationale -> HrPermissionPrompt(
            message = "Bluetooth permission lets OpenRide find controllers over Bluetooth. Controllers on " +
                "your Wi-Fi, like BikeControl on a phone, are found without it.",
            actionLabel = "Grant Bluetooth permission",
            opensAppSettings = false,
        )
        BlePermissionState.PermanentlyDenied -> HrPermissionPrompt(
            message = "Bluetooth permission was denied, so only controllers on your Wi-Fi can be found. " +
                "Turn it on in this app's system Settings page to find Bluetooth ones.",
            actionLabel = "Open Settings",
            opensAppSettings = true,
        )
    }
}
