package dev.digitalducktape.openride.core.heartrate

/**
 * Abstraction over BLE scanning for nearby heart-rate straps (PRD P1-4, T17). A narrow
 * interface — same reasoning as [HeartRateDataSource] and
 * [dev.digitalducktape.openride.core.sensor.BikeDataSource] — so the pairing screen's view
 * model is unit-testable against a fake scanner without touching real `android.bluetooth`
 * APIs (which Robolectric only partially shadows, and which this environment has no real
 * adapter/hardware to exercise anyway — see [AndroidBleScanner]'s doc).
 */
interface BleScanner {
    /** `true` if this device has a Bluetooth adapter and it's currently powered on. */
    fun isBluetoothAvailable(): Boolean

    /**
     * Starts scanning for devices advertising the scanner's service (the Heart Rate Service,
     * `0x180D`, unless it was built for another, issue #68). [onDeviceFound]
     * fires once per newly-seen device (by address); [onScanFailed] fires at most once, with a
     * human-readable reason, if the scan can't start or is stopped by the system.
     */
    fun startScan(onDeviceFound: (BleDevice) -> Unit, onScanFailed: (String) -> Unit)

    /** Stops a scan started by [startScan]. Safe to call even if no scan is running. */
    fun stopScan()
}
