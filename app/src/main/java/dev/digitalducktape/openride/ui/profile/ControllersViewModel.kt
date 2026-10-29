package dev.digitalducktape.openride.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.digitalducktape.openride.core.controller.ControllerAction
import dev.digitalducktape.openride.core.controller.ControllerScanner
import dev.digitalducktape.openride.core.controller.ControllerStatus
import dev.digitalducktape.openride.core.controller.ControllerStore
import dev.digitalducktape.openride.core.controller.PairedController
import dev.digitalducktape.openride.core.controller.sameAs
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach

/**
 * The controllers screen (issue #68): the paired OpenBikeControl controllers with how each is
 * connected, the last button pressed (so the rider sees one working), and a search for more over
 * Bluetooth and the local network. Permissions work as on the strap's screen ([HrPairingViewModel]):
 * the screen checks and requests them, and reports the result here.
 */
class ControllersViewModel(
    private val scanner: ControllerScanner,
    private val store: ControllerStore,
    statuses: StateFlow<List<ControllerStatus>>,
    lastPress: StateFlow<ControllerAction?>,
) : ViewModel() {

    data class UiState(
        val permissionState: BlePermissionState = BlePermissionState.NotRequested,
        val isScanning: Boolean = false,
        val found: List<PairedController> = emptyList(),
        val error: String? = null,
        val paired: List<PairedController> = emptyList(),
        val statuses: List<ControllerStatus> = emptyList(),
        val lastPress: ControllerAction? = null,
    ) {
        /** The search's finds, less the ones already paired. */
        val nearby: List<PairedController>
            get() = found.filterNot { f -> paired.any { it.sameAs(f) } }

        fun statusOf(controller: PairedController): ControllerStatus? = statuses.firstOrNull { it.controller.sameAs(controller) }
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        combine(store.paired, statuses, lastPress) { paired, status, press -> Triple(paired, status, press) }
            .onEach { (paired, status, press) ->
                _uiState.value = _uiState.value.copy(paired = paired, statuses = status, lastPress = press)
            }
            .launchIn(viewModelScope)
    }

    fun onPermissionState(state: BlePermissionState) {
        _uiState.value = _uiState.value.copy(permissionState = state)
    }

    /**
     * Searches Bluetooth (once permission is granted) and the network. Without Bluetooth
     * permission the network search still runs: BikeControl on a phone is found over Wi-Fi.
     */
    fun startScan() {
        _uiState.value = _uiState.value.copy(isScanning = true, found = emptyList(), error = null)
        scanner.start(
            onFound = { controller ->
                val current = _uiState.value
                if (current.found.none { it.sameAs(controller) }) _uiState.value = current.copy(found = current.found + controller)
            },
            onFailed = { reason -> _uiState.value = _uiState.value.copy(error = reason) },
            bluetooth = _uiState.value.permissionState == BlePermissionState.Granted,
        )
    }

    fun stopScan() {
        scanner.stop()
        _uiState.value = _uiState.value.copy(isScanning = false)
    }

    fun pair(controller: PairedController) {
        store.add(controller)
    }

    fun forget(controller: PairedController) {
        store.remove(controller)
    }

    override fun onCleared() {
        scanner.stop()
    }
}
