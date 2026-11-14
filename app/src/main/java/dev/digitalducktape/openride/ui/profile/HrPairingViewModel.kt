package dev.digitalducktape.openride.ui.profile

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.heartrate.BleDevice
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.heartrate.BleScanner
import dev.digitalducktape.openride.core.heartrate.HeartRateDataSource
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.core.telemetry.HrSelectResult
import dev.digitalducktape.openride.core.telemetry.HrStrapSelected
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.trackSafely
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

/**
 * BLE heart-rate strap pairing screen (PRD P1-4, T17): scan for nearby straps, let the rider
 * pick one, and persist its address to the *active* profile's
 * [dev.digitalducktape.openride.core.data.Profile.pairedHrDeviceAddress] — matching
 * [dev.digitalducktape.openride.core.heartrate.HeartRateManager]'s "remember strap per
 * profile" contract, which reconnects automatically the next time this same profile is active.
 *
 * Permission handling is deliberately split: this view model only tracks [uiState.permissionState]
 * (set by the screen after it checks/requests permissions, since that's an Activity/Compose-level
 * concern this plain [ViewModel] can't perform itself) and refuses to scan while permissions
 * aren't [BlePermissionState.Granted] — the actual system permission dance
 * (`ContextCompat.checkSelfPermission`, `rememberLauncherForActivityResult`) lives in
 * [HrPairingScreen], with [dev.digitalducktape.openride.core.heartrate.reduceBlePermissionState]
 * as the shared, independently-unit-tested reducer between them.
 */
class HrPairingViewModel(
    private val bleScanner: BleScanner,
    private val profileRepository: ProfileRepository,
    private val activeProfileHolder: ActiveProfileHolder,
    /** The live strap feed ([dev.digitalducktape.openride.core.heartrate.HeartRateManager]), so
     *  the paired row can say "Connected"; null leaves it reading as paired only. */
    liveHeartRate: HeartRateDataSource? = null,
    private val telemetry: Telemetry = NoOpTelemetry,
) : ViewModel() {

    data class UiState(
        val permissionState: BlePermissionState = BlePermissionState.NotRequested,
        val isScanning: Boolean = false,
        val devices: List<BleDevice> = emptyList(),
        val error: String? = null,
        val pairedAddress: String? = null,
        /** The paired strap's name, once this screen's scan has seen it advertise one. */
        val pairedName: String? = null,
        val strapConnection: ConnectionState = ConnectionState.Unavailable,
        val strapBpm: Int? = null,
    ) {
        /** The scan's finds, less the strap already paired: that one is shown as paired instead
         *  of still being offered as "nearby" (rider, 2026-10-27). */
        val nearbyDevices: List<BleDevice>
            get() = devices.filterNot { it.address == pairedAddress }
    }

    private val _uiState = MutableStateFlow(UiState())
    val uiState: StateFlow<UiState> = _uiState.asStateFlow()

    init {
        // profileRepository.observeProfiles() is a Room @Query Flow, which (unlike
        // activeProfileId) doesn't necessarily emit synchronously on collection — onStart
        // seeds an empty list so this still resolves right away for "no rider active yet",
        // same reasoning as HeartRateManager's own combine.
        combine(
            activeProfileHolder.activeProfileId,
            profileRepository.observeProfiles().onStart { emit(emptyList()) },
        ) { id, profiles -> profiles.firstOrNull { it.id == id }?.pairedHrDeviceAddress }
            .onEach { address -> _uiState.value = _uiState.value.copy(pairedAddress = address) }
            .launchIn(viewModelScope)

        if (liveHeartRate != null) {
            combine(liveHeartRate.connectionState, liveHeartRate.bpm) { state, bpm -> state to bpm }
                .onEach { (state, bpm) -> _uiState.value = _uiState.value.copy(strapConnection = state, strapBpm = bpm) }
                .launchIn(viewModelScope)
        }
    }

    /** Called by the screen once it has determined the current [BlePermissionState]. */
    fun onPermissionState(state: BlePermissionState) {
        _uiState.value = _uiState.value.copy(permissionState = state)
    }

    /** No-op unless [BlePermissionState.Granted] — the screen is responsible for requesting
     *  permissions first and only calling this once they're granted. */
    fun startScan() {
        if (_uiState.value.permissionState != BlePermissionState.Granted) return
        if (!bleScanner.isBluetoothAvailable()) {
            _uiState.value = _uiState.value.copy(error = "Bluetooth is off or unavailable")
            telemetry.trackSafely { HrStrapSelected(HrSelectResult.BT_OFF) }
            return
        }
        _uiState.value = _uiState.value.copy(isScanning = true, devices = emptyList(), error = null)
        bleScanner.startScan(
            onDeviceFound = { device ->
                val current = _uiState.value
                if (current.devices.none { it.address == device.address }) {
                    val name = if (device.address == current.pairedAddress) device.name ?: current.pairedName else current.pairedName
                    _uiState.value = current.copy(devices = current.devices + device, pairedName = name)
                }
            },
            onScanFailed = { reason ->
                _uiState.value = _uiState.value.copy(isScanning = false, error = reason)
                // The reason is a system string: never sent.
                telemetry.trackSafely { HrStrapSelected(HrSelectResult.SCAN_FAILED) }
            },
        )
    }

    fun stopScan() {
        bleScanner.stopScan()
        _uiState.value = _uiState.value.copy(isScanning = false)
    }

    /** Persists [device]'s address as the active profile's paired strap and stops scanning. */
    fun selectDevice(device: BleDevice) {
        stopScan()
        _uiState.value = _uiState.value.copy(pairedName = device.name)
        val activeId = activeProfileHolder.activeProfileId.value ?: return
        viewModelScope.launch {
            val profile = profileRepository.getProfile(activeId) ?: return@launch
            profileRepository.updateProfile(profile.copy(pairedHrDeviceAddress = device.address))
            telemetry.trackSafely { HrStrapSelected(HrSelectResult.SELECTED) }
        }
    }

    /** Clears the active profile's paired strap. */
    fun forgetDevice() {
        val activeId = activeProfileHolder.activeProfileId.value ?: return
        viewModelScope.launch {
            val profile = profileRepository.getProfile(activeId) ?: return@launch
            profileRepository.updateProfile(profile.copy(pairedHrDeviceAddress = null))
        }
        _uiState.value = _uiState.value.copy(pairedName = null)
    }

    override fun onCleared() {
        bleScanner.stopScan()
    }
}
