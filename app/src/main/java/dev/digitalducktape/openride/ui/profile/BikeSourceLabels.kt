package dev.digitalducktape.openride.ui.profile

import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.BikeSource
import dev.digitalducktape.openride.core.sensor.ConnectionState

/** The bike-source screen's derived text (issue #68), kept out of the composable for tests. */
object BikeSourceLabels {
    /** The built-in source's name: the Peloton in the real build, the simulation otherwise. */
    fun builtinName(realBike: Boolean): String = if (realBike) "Peloton bike" else "Simulated bike"

    fun builtinDetail(realBike: Boolean): String =
        if (realBike) "The bike's own sensors and resistance knob" else "Made-up numbers, for trying the app"

    fun trainerName(source: BikeSource.Trainer): String = source.name?.takeIf { it.isNotBlank() } ?: source.address

    /** The trainer in use: live numbers once it's sending, else what wakes it. */
    fun trainerStatus(connection: ConnectionState, metrics: BikeMetrics, adjustable: Boolean): String = when (connection) {
        ConnectionState.Connected -> buildList {
            add("Connected")
            add("${metrics.powerWatts} W")
            add("${metrics.cadenceRpm} rpm")
            add(if (adjustable) "OpenRide sets the resistance" else "Resistance can't be set")
        }.joinToString("  •  ")
        ConnectionState.Disconnected -> "Reconnecting…"
        ConnectionState.Unavailable -> "Connects when it's on and OpenRide is open"
    }

    /** The Profile tab row's value. */
    fun profileRow(source: BikeSource, realBike: Boolean): String = when (source) {
        BikeSource.Builtin -> builtinName(realBike)
        is BikeSource.Trainer -> "Smart trainer: ${trainerName(source)}"
    }

    fun scanAction(isScanning: Boolean): String = if (isScanning) "Stop scan" else "Scan for trainers"

    fun deviceName(name: String?): String = name ?: "Unknown trainer"

    fun emptyHint(uiState: BikeSourceViewModel.UiState): String? =
        if (uiState.nearby.isEmpty() && !uiState.isScanning && uiState.error == null) {
            "No trainers found yet. Wake yours by pedalling, close other apps using it, and tap Scan."
        } else {
            null
        }

    fun permissionPrompt(state: BlePermissionState): HrPermissionPrompt? = when (state) {
        BlePermissionState.Granted -> null
        BlePermissionState.NotRequested, BlePermissionState.ShouldShowRationale -> HrPermissionPrompt(
            message = "Bluetooth permission is needed to find smart trainers. It's only used to find and " +
                "connect to the trainer you pick.",
            actionLabel = "Grant Bluetooth permission",
            opensAppSettings = false,
        )
        BlePermissionState.PermanentlyDenied -> HrPermissionPrompt(
            message = "Bluetooth permission was denied. Turn it on in this app's system Settings page to use a smart trainer.",
            actionLabel = "Open Settings",
            opensAppSettings = true,
        )
    }
}
