@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.ui.profile

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.data.InMemoryDatabaseRule
import dev.digitalducktape.openride.core.data.Profile
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.heartrate.BleDevice
import dev.digitalducktape.openride.core.heartrate.BlePermissionState
import dev.digitalducktape.openride.core.heartrate.BleScanner
import dev.digitalducktape.openride.core.heartrate.FakeManagedHeartRateDataSource
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.core.telemetry.HrSelectResult
import dev.digitalducktape.openride.core.telemetry.HrStrapSelected
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Covers the pairing screen's view model (PRD P1-4, T17) against a fake [BleScanner]: the
 * permission gate, the scan lifecycle, and persistence of the chosen strap to the *active*
 * profile — everything except the real `android.bluetooth` scan, which has no hardware to
 * exercise here (see [dev.digitalducktape.openride.core.heartrate.AndroidBleScanner]).
 *
 * Unlike the plain-`suspend`-fun view models elsewhere in this app, this one legitimately
 * fires DB writes and a profile observer from non-suspend entry points (an `onClick`, `init`),
 * so it uses `viewModelScope`. The dispatcher is installed as Main here so `runTest` drives
 * those coroutines deterministically.
 */
@RunWith(AndroidJUnit4::class)
class HrPairingViewModelTest {

    @get:Rule val database = InMemoryDatabaseRule()
    private val db get() = database.db
    private lateinit var profileRepository: ProfileRepository
    private lateinit var activeProfileHolder: ActiveProfileHolder
    private lateinit var scanner: FakeBleScanner
    private lateinit var viewModel: HrPairingViewModel
    private val telemetry = RecordingTelemetry()

    @Before
    fun setUp() {
        Dispatchers.setMain(UnconfinedTestDispatcher())
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        profileRepository = ProfileRepository(db.profileDao())
        activeProfileHolder = ActiveProfileHolder(context)
        scanner = FakeBleScanner()
        viewModel = HrPairingViewModel(scanner, profileRepository, activeProfileHolder, telemetry = telemetry)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    @Test
    fun `startScan is a no-op until permissions are granted`() {
        viewModel.startScan()

        assertFalse(viewModel.uiState.value.isScanning)
        assertEquals(0, scanner.startCallCount)
    }

    @Test
    fun `startScan surfaces an error when Bluetooth is off`() {
        scanner.bluetoothAvailable = false
        viewModel.onPermissionState(BlePermissionState.Granted)

        viewModel.startScan()

        assertFalse(viewModel.uiState.value.isScanning)
        assertEquals("Bluetooth is off or unavailable", viewModel.uiState.value.error)
        assertEquals(0, scanner.startCallCount)
    }

    @Test
    fun `granted scan collects distinct discovered devices`() {
        viewModel.onPermissionState(BlePermissionState.Granted)

        viewModel.startScan()
        assertTrue(viewModel.uiState.value.isScanning)

        scanner.emitDevice(BleDevice(address = "AA:BB:CC:DD:EE:FF", name = "Wahoo TICKR"))
        scanner.emitDevice(BleDevice(address = "AA:BB:CC:DD:EE:FF", name = "Wahoo TICKR")) // dupe
        scanner.emitDevice(BleDevice(address = "11:22:33:44:55:66", name = null))

        assertEquals(2, viewModel.uiState.value.devices.size)
        assertEquals("AA:BB:CC:DD:EE:FF", viewModel.uiState.value.devices[0].address)
    }

    @Test
    fun `scan failure clears scanning and records the reason`() {
        viewModel.onPermissionState(BlePermissionState.Granted)
        viewModel.startScan()

        scanner.failScan("adapter shut off")

        assertFalse(viewModel.uiState.value.isScanning)
        assertEquals("adapter shut off", viewModel.uiState.value.error)
    }

    @Test
    fun `selecting a device stops scanning and persists it to the active profile`() = runTest {
        val id = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(id)
        viewModel.onPermissionState(BlePermissionState.Granted)
        viewModel.startScan()

        viewModel.selectDevice(BleDevice(address = "AA:BB:CC:DD:EE:FF", name = "Wahoo TICKR"))

        assertFalse(viewModel.uiState.value.isScanning)
        assertEquals(1, scanner.stopCallCount)
        // Await the observed profile row reflecting the write (the persist runs on Room's own
        // executor), then confirm it actually landed in the DB.
        val paired = viewModel.uiState.first { it.pairedAddress == "AA:BB:CC:DD:EE:FF" }
        assertEquals("AA:BB:CC:DD:EE:FF", paired.pairedAddress)
        assertEquals("AA:BB:CC:DD:EE:FF", profileRepository.getProfile(id)?.pairedHrDeviceAddress)
    }

    @Test
    fun `the paired strap leaves the nearby list, named, and reads as connected once sending`() = runTest {
        val strap = FakeManagedHeartRateDataSource("AA:BB:CC:DD:EE:FF")
        val live = HrPairingViewModel(scanner, profileRepository, activeProfileHolder, liveHeartRate = strap)
        val id = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(id)
        live.onPermissionState(BlePermissionState.Granted)
        live.startScan()
        scanner.emitDevice(BleDevice(address = "AA:BB:CC:DD:EE:FF", name = "TICKR 1A2B"))
        scanner.emitDevice(BleDevice(address = "11:22:33:44:55:66", name = null))

        live.selectDevice(BleDevice(address = "AA:BB:CC:DD:EE:FF", name = "TICKR 1A2B"))
        val paired = live.uiState.first { it.pairedAddress == "AA:BB:CC:DD:EE:FF" }
        assertEquals(listOf("11:22:33:44:55:66"), paired.nearbyDevices.map { it.address })
        assertEquals("TICKR 1A2B", paired.pairedName)

        strap.emitBpm(72)
        assertEquals(ConnectionState.Connected, live.uiState.value.strapConnection)
        assertEquals(72, live.uiState.value.strapBpm)
    }

    @Test
    fun `forgetDevice clears the active profile's paired strap`() = runTest {
        val id = profileRepository.createProfile(
            Profile(
                name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null,
                pairedHrDeviceAddress = "AA:BB:CC:DD:EE:FF",
            ),
        )
        activeProfileHolder.setActiveProfile(id)
        // Wait until the view model has observed the initially-paired strap before forgetting,
        // so the null we await afterwards is the clear, not just the pre-observe initial state.
        viewModel.uiState.first { it.pairedAddress == "AA:BB:CC:DD:EE:FF" }

        viewModel.forgetDevice()

        viewModel.uiState.first { it.pairedAddress == null }
        assertNull(profileRepository.getProfile(id)?.pairedHrDeviceAddress)
    }

    private class FakeBleScanner : BleScanner {
        var bluetoothAvailable = true
        var startCallCount = 0
        var stopCallCount = 0
        private var onDeviceFound: ((BleDevice) -> Unit)? = null
        private var onScanFailed: ((String) -> Unit)? = null

        override fun isBluetoothAvailable(): Boolean = bluetoothAvailable

        override fun startScan(onDeviceFound: (BleDevice) -> Unit, onScanFailed: (String) -> Unit) {
            startCallCount++
            this.onDeviceFound = onDeviceFound
            this.onScanFailed = onScanFailed
        }

        override fun stopScan() {
            stopCallCount++
        }

        fun emitDevice(device: BleDevice) = onDeviceFound?.invoke(device)
        fun failScan(reason: String) = onScanFailed?.invoke(reason)
    }

    @Test
    fun `telemetry says bt_off when Bluetooth is off, without the message`() {
        scanner.bluetoothAvailable = false
        viewModel.onPermissionState(BlePermissionState.Granted)

        viewModel.startScan()

        assertEquals(listOf<Any>(HrStrapSelected(HrSelectResult.BT_OFF)), telemetry.events)
    }

    @Test
    fun `telemetry says scan_failed without the reason`() {
        viewModel.onPermissionState(BlePermissionState.Granted)
        viewModel.startScan()

        scanner.failScan("adapter shut off")

        assertEquals(listOf<Any>(HrStrapSelected(HrSelectResult.SCAN_FAILED)), telemetry.events)
        assertEquals(mapOf("result" to "scan_failed"), telemetry.events.single().props())
    }

    @Test
    fun `telemetry says selected when a strap is chosen`() = runTest {
        val id = profileRepository.createProfile(
            Profile(name = "Ed", avatarEmoji = "🚴", avatarColor = 0xFF00AAFF.toInt(), weightKg = null, ftp = null),
        )
        activeProfileHolder.setActiveProfile(id)
        viewModel.onPermissionState(BlePermissionState.Granted)
        viewModel.startScan()

        viewModel.selectDevice(BleDevice(address = "AA:BB:CC:DD:EE:FF", name = "Wahoo TICKR"))
        // The write runs on Room's executor; the event follows it.
        viewModel.uiState.first { it.pairedAddress == "AA:BB:CC:DD:EE:FF" }
        repeat(200) { if (telemetry.events.isEmpty()) Thread.sleep(10) }

        assertEquals(listOf<Any>(HrStrapSelected(HrSelectResult.SELECTED)), telemetry.events)
    }
}
