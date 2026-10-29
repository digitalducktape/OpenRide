package dev.digitalducktape.openride.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.digitalducktape.openride.core.heartrate.BleDevice
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.heartrate.BleScanner
import dev.digitalducktape.openride.core.sensor.BikeDataSource
import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.BikeSource
import dev.digitalducktape.openride.core.sensor.BikeSourceStore
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.core.sensor.ResistanceControl
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn

/**
 * The bike-source screen (issue #68): the built-in source (the Peloton, or the simulation) or a
 * smart trainer over FTMS, picked from a Bluetooth scan. Permissions work as on the strap's
 * screen ([HrPairingViewModel]).
 */
class BikeSourceViewModel(
    private val scanner: BleScanner,
    private val store: BikeSourceStore,
    bike: BikeDataSource,
) : ViewModel() {

    data class UiState(
        val permissionState: BlePermissionState = BlePermissionState.NotRequested,
        val isScanning: Boolean = false,
        val devices: List<BleDevice> = emptyList(),
        val error: String? = null,
        val source: BikeSource = BikeSource.Builtin,
        val connection: ConnectionState = ConnectionState.Unavailable,
        val metrics: BikeMetrics = BikeMetrics.ZERO,
        val adjustable: Boolean = false,
    ) {
        /** The scan's finds, less the trainer in use. */
        val nearby: List<BleDevice>
            get() = devices.filterNot { (source as? BikeSource.Trainer)?.address == it.address }
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        combine(
            store.source,
            bike.connectionState,
            bike.metrics,
            (bike as? ResistanceControl)?.adjustable ?: flowOf(false),
        ) { source, connection, metrics, adjustable ->
            _uiState.value = _uiState.value.copy(source = source, connection = connection, metrics = metrics, adjustable = adjustable)
        }.launchIn(viewModelScope)
    }

    fun onPermissionState(state: BlePermissionState) {
        _uiState.value = _uiState.value.copy(permissionState = state)
    }

    fun startScan() {
        if (_uiState.value.permissionState != BlePermissionState.Granted) return
        if (!scanner.isBluetoothAvailable()) {
            _uiState.value = _uiState.value.copy(error = "Bluetooth is off or unavailable")
            return
        }
        _uiState.value = _uiState.value.copy(isScanning = true, devices = emptyList(), error = null)
        scanner.startScan(
            onDeviceFound = { device ->
                val current = _uiState.value
                if (current.devices.none { it.address == device.address }) _uiState.value = current.copy(devices = current.devices + device)
            },
            onScanFailed = { reason -> _uiState.value = _uiState.value.copy(isScanning = false, error = reason) },
        )
    }

    fun stopScan() {
        scanner.stopScan()
        _uiState.value = _uiState.value.copy(isScanning = false)
    }

    fun useTrainer(device: BleDevice) {
        stopScan()
        store.set(BikeSource.Trainer(device.address, device.name))
    }

    fun useBuiltin() {
        store.set(BikeSource.Builtin)
    }

    override fun onCleared() {
        scanner.stopScan()
    }
}
