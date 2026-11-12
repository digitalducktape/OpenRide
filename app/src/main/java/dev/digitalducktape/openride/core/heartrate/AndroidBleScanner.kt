package dev.digitalducktape.openride.core.heartrate

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.ParcelUuid
import android.util.Log
import java.util.UUID

/**
 * Real [BleScanner] over `android.bluetooth`'s BLE scanning APIs, filtered to the standard
 * Heart Rate Service UUID (`0x180D`) so the pairing screen only lists relevant straps rather
 * than every BLE device in range (PRD P1-4, T17).
 *
 * **Hardware caveat (T17/#17)**: this project has no physical BLE heart-rate strap to test
 * against, so this class is built correctly *per the public Android BLE APIs and Bluetooth SIG
 * spec* but is **not verified against a real device**. Every failure path (adapter null/off,
 * scanner unavailable, missing runtime permission, scan-start failure) degrades to
 * [onScanFailed] rather than throwing, matching the same "never crash, report unavailable"
 * contract [dev.digitalducktape.openride.core.sensor.PelotonBikeDataSource] uses for the bike
 * sensor — but confirming an actual strap shows up in [startScan]'s results requires real
 * hardware in real proximity, which someone with a strap needs to verify.
 */
class AndroidBleScanner(
    private val context: Context,
    /** The service the scan looks for: heart rate here, and the controllers' and trainers' (#68). */
    private val serviceUuid: UUID = HEART_RATE_SERVICE_UUID,
    /** Offer LE devices already connected to the tablet, which have stopped advertising (see [startScan]). */
    private val offerConnected: Boolean = true,
) : BleScanner {

    private val bluetoothAdapter: BluetoothAdapter? by lazy {
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    }

    private var scanCallback: ScanCallback? = null

    override fun isBluetoothAvailable(): Boolean =
        bluetoothAdapter?.isEnabled == true

    override fun startScan(onDeviceFound: (BleDevice) -> Unit, onScanFailed: (String) -> Unit) {
        val adapter = bluetoothAdapter
        if (adapter == null) {
            onScanFailed("This device has no Bluetooth adapter")
            return
        }
        if (!adapter.isEnabled) {
            onScanFailed("Bluetooth is turned off")
            return
        }
        val scanner = adapter.bluetoothLeScanner
        if (scanner == null) {
            onScanFailed("BLE scanning is unavailable on this device")
            return
        }

        val seenAddresses = mutableSetOf<String>()
        // A strap already connected to this tablet (by OpenRide's other build, say) stops
        // advertising, so no scan finds it (rider, 2026-10-27). Android shares that link with
        // any app that connects, so it's offered too.
        if (offerConnected) connectedDevices().forEach { device ->
            if (seenAddresses.add(device.address)) onDeviceFound(device)
        }
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val device = result?.device ?: return
                val address = device.address ?: return
                if (!seenAddresses.add(address)) return // already reported
                val name = try {
                    device.name
                } catch (_: SecurityException) {
                    null // BLUETOOTH_CONNECT not granted — address is still usable for pairing
                }
                onDeviceFound(BleDevice(address = address, name = name))
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "BLE scan failed with error code $errorCode")
                onScanFailed("Scan failed (error code $errorCode)")
            }
        }
        scanCallback = callback

        val filter = ScanFilter.Builder()
            .setServiceUuid(ParcelUuid(serviceUuid))
            .build()
        val settings = ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .build()

        try {
            scanner.startScan(listOf(filter), settings, callback)
        } catch (e: SecurityException) {
            // Missing BLUETOOTH_SCAN (API 31+) or ACCESS_FINE_LOCATION (API <=30) at runtime —
            // the pairing screen is expected to request permissions before calling startScan,
            // but a race (permission revoked mid-session) shouldn't crash the app.
            Log.w(TAG, "BLE scan denied — missing runtime permission", e)
            scanCallback = null
            onScanFailed("Missing Bluetooth permission")
        }
    }

    /** LE devices already connected to the tablet by any app, or none if that can't be read. */
    private fun connectedDevices(): List<BleDevice> = try {
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)
            ?.getConnectedDevices(BluetoothProfile.GATT)
            .orEmpty()
            .map { BleDevice(address = it.address, name = it.name) }
    } catch (e: SecurityException) {
        Log.w(TAG, "Can't list connected devices — missing Bluetooth permission", e)
        emptyList()
    }

    override fun stopScan() {
        val adapter = bluetoothAdapter ?: return
        val scanner = adapter.bluetoothLeScanner ?: return
        val callback = scanCallback ?: return
        try {
            scanner.stopScan(callback)
        } catch (_: SecurityException) {
            // Same permission race as startScan; nothing to clean up beyond forgetting the
            // callback reference below.
        }
        scanCallback = null
    }

    companion object {
        private const val TAG = "AndroidBleScanner"

        /** Standard Bluetooth SIG Heart Rate Service UUID (0x180D), 16-bit UUID base form. */
        val HEART_RATE_SERVICE_UUID: UUID = UUID.fromString("0000180D-0000-1000-8000-00805F9B34FB")
    }
}
