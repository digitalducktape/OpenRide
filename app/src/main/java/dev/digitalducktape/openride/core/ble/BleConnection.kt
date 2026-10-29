package dev.digitalducktape.openride.core.ble

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanFilter
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import java.util.UUID

/**
 * A GATT client for one BLE device that stays connected from [start] to [stop], and runs GATT
 * operations one at a time (Android drops a second operation issued before the first's callback).
 * Shared by the OpenBikeControl controllers and the FTMS trainers (issue #68).
 *
 * It reconnects the way [dev.digitalducktape.openride.core.heartrate.BleHeartRateDataSource]
 * learned to on the bike: a background connect (`autoConnect`, which also joins a link another
 * app holds) plus a scan for the device's address, which catches it as it starts advertising
 * and connects directly (after a reboot only a scan teaches the stack the address type). A
 * dropped live link retries at once, a failed attempt after [RETRY_MS]; scans stay [RETRY_MS]
 * apart, under Android's five-per-30-s limit.
 *
 * Every callback to [listener] arrives on the main thread, where all of this runs.
 */
class BleConnection(
    private val context: Context,
    private val address: String,
    private val tag: String,
    private val listener: Listener,
) {
    interface Listener {
        /**
         * The link is up and its services are discovered: look up the characteristics and queue
         * the setup ([enableNotifications], [write], [read]). Return `false` if the device isn't
         * the kind expected (the service is missing), and the link is dropped and retried.
         */
        fun onServicesReady(gatt: BluetoothGatt): Boolean

        fun onNotification(characteristic: UUID, value: ByteArray)

        /** The link dropped (or an attempt failed after [onServicesReady]); a retry follows. */
        fun onLinkDown()
    }

    private val handler = Handler(Looper.getMainLooper())
    private val adapter: BluetoothAdapter? by lazy {
        (context.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
    }
    private var running = false
    private var gatt: BluetoothGatt? = null
    private var ready = false
    private var finder: ScanCallback? = null
    private var lastFinderStart = Long.MIN_VALUE / 2

    private val queue = ArrayDeque<Op>()
    private var current: Op? = null
    private val opTimeout = Runnable { finishOp(BluetoothGatt.GATT_FAILURE, null) }

    /** One GATT operation; [onDone] gets the status and, for reads, the value. */
    private class Op(val run: (BluetoothGatt) -> Boolean, val onDone: (status: Int, value: ByteArray?) -> Unit)

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt?, status: Int, newState: Int) {
            handler.post { onConnectionChanged(g, status, newState) }
        }

        override fun onServicesDiscovered(g: BluetoothGatt?, status: Int) {
            handler.post { onDiscovered(g, status) }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicChanged(g: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?) {
            // The pre-API-33 signature, which the platform still calls on 33+ (as the strap does).
            val uuid = characteristic?.uuid ?: return
            val bytes = characteristic.value?.copyOf() ?: return
            handler.post { if (g === gatt) listener.onNotification(uuid, bytes) }
        }

        @Suppress("DEPRECATION")
        override fun onCharacteristicRead(g: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?, status: Int) {
            val bytes = characteristic?.value?.copyOf()
            handler.post { if (g === gatt) finishOp(status, bytes) }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt?, characteristic: BluetoothGattCharacteristic?, status: Int) {
            handler.post { if (g === gatt) finishOp(status, null) }
        }

        override fun onDescriptorWrite(g: BluetoothGatt?, descriptor: BluetoothGattDescriptor?, status: Int) {
            handler.post { if (g === gatt) finishOp(status, null) }
        }

        override fun onMtuChanged(g: BluetoothGatt?, mtu: Int, status: Int) {
            handler.post { if (g === gatt) finishOp(status, null) }
        }
    }

    /** Starts connecting, and keeps reconnecting until [stop]. */
    fun start() {
        handler.post {
            if (running) return@post
            running = true
            connect()
        }
    }

    /** Disconnects and releases the GATT client. Safe to call at any time. */
    fun stop() {
        handler.post {
            running = false
            handler.removeCallbacksAndMessages(null)
            stopFinder()
            release()
        }
    }

    /** Whether the link is up with its services discovered. */
    val isReady: Boolean get() = ready

    /** Subscribes to [characteristic]: notifications, or indications when [indicate]. */
    fun enableNotifications(
        characteristic: BluetoothGattCharacteristic,
        indicate: Boolean = false,
        onDone: (Boolean) -> Unit = {},
    ) = enqueue(
        Op(
            run = { g ->
                g.setCharacteristicNotification(characteristic, true)
                val cccd = characteristic.getDescriptor(CLIENT_CHARACTERISTIC_CONFIG_UUID)
                if (cccd == null) {
                    false
                } else {
                    // The pre-API-33 descriptor write, which works across this app's whole range.
                    @Suppress("DEPRECATION")
                    cccd.value = if (indicate) BluetoothGattDescriptor.ENABLE_INDICATION_VALUE else BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    g.writeDescriptor(cccd)
                }
            },
            onDone = { status, _ -> onDone(status == BluetoothGatt.GATT_SUCCESS) },
        ),
    )

    /** Writes [value] to [characteristic], with a response unless [withResponse] is false. */
    fun write(
        characteristic: BluetoothGattCharacteristic,
        value: ByteArray,
        withResponse: Boolean = true,
        onDone: (Boolean) -> Unit = {},
    ) = enqueue(
        Op(
            run = { g ->
                @Suppress("DEPRECATION")
                run {
                    characteristic.writeType = if (withResponse) {
                        BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
                    } else {
                        BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    }
                    characteristic.value = value
                    g.writeCharacteristic(characteristic)
                }
            },
            onDone = { status, _ -> onDone(status == BluetoothGatt.GATT_SUCCESS) },
        ),
    )

    /**
     * Asks for a larger MTU. Without one a write carries at most 20 bytes, and a longer one goes as
     * a prepared ("long") write, which some peripherals receive as separate fragments: BikeControl
     * on a phone took OpenRide's 30-byte App Information that way and never parsed it (#68).
     * [onDone] gets whether the stack agreed; writes work either way.
     */
    fun requestMtu(mtu: Int = PREFERRED_MTU, onDone: (Boolean) -> Unit = {}) = enqueue(
        Op(
            run = { g -> g.requestMtu(mtu) },
            onDone = { status, _ -> onDone(status == BluetoothGatt.GATT_SUCCESS) },
        ),
    )

    /** Reads [characteristic]; [onDone] gets its value, or `null` if the read failed. */
    fun read(characteristic: BluetoothGattCharacteristic, onDone: (ByteArray?) -> Unit) = enqueue(
        Op(
            run = { g -> g.readCharacteristic(characteristic) },
            onDone = { status, value -> onDone(value.takeIf { status == BluetoothGatt.GATT_SUCCESS }) },
        ),
    )

    /** Drops the link and starts over, e.g. when the device answered nonsense. */
    fun reconnect(reason: String) = handler.post { dropAndRetry(reason) }

    // --- Operations ---------------------------------------------------------------------------

    private fun enqueue(op: Op) {
        handler.post {
            if (gatt == null || !ready) {
                op.onDone(BluetoothGatt.GATT_FAILURE, null)
                return@post
            }
            queue.addLast(op)
            if (current == null) next()
        }
    }

    private fun next() {
        val g = gatt ?: return
        val op = queue.removeFirstOrNull() ?: return
        current = op
        val started = try {
            op.run(g)
        } catch (e: SecurityException) {
            Log.w(tag, "GATT operation denied — missing Bluetooth permission", e)
            false
        }
        if (started) {
            handler.postDelayed(opTimeout, OP_TIMEOUT_MS)
        } else {
            finishOp(BluetoothGatt.GATT_FAILURE, null)
        }
    }

    private fun finishOp(status: Int, value: ByteArray?) {
        val op = current ?: return
        current = null
        handler.removeCallbacks(opTimeout)
        op.onDone(status, value)
        next()
    }

    private fun clearOps() {
        handler.removeCallbacks(opTimeout)
        val pending = listOfNotNull(current) + queue
        current = null
        queue.clear()
        pending.forEach { it.onDone(BluetoothGatt.GATT_FAILURE, null) }
    }

    // --- Connecting ---------------------------------------------------------------------------

    private fun connect() {
        if (!running || gatt != null) return
        val adapter = adapter
        if (adapter == null || !adapter.isEnabled) {
            Log.w(tag, "Bluetooth is off or missing; trying again shortly")
            retryLater()
            return
        }
        try {
            gatt = adapter.getRemoteDevice(address).connectGatt(context, true, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: SecurityException) {
            Log.w(tag, "Connect denied — missing BLUETOOTH_CONNECT permission", e)
            return
        } catch (e: IllegalArgumentException) {
            Log.w(tag, "Invalid BLE device address: $address", e)
            return
        }
        if (gatt == null) {
            retryLater()
            return
        }
        startFinder(adapter)
    }

    private fun onConnectionChanged(g: BluetoothGatt?, status: Int, newState: Int) {
        if (g == null || g !== gatt) return
        if (newState == BluetoothProfile.STATE_CONNECTED && status == BluetoothGatt.GATT_SUCCESS) {
            stopFinder()
            try {
                if (!g.discoverServices()) dropAndRetry("discoverServices refused")
            } catch (e: SecurityException) {
                Log.w(tag, "discoverServices denied", e)
                dropAndRetry("discoverServices denied")
            }
        } else {
            dropAndRetry("link down (status=$status, state=$newState)")
        }
    }

    private fun onDiscovered(g: BluetoothGatt?, status: Int) {
        if (g == null || g !== gatt) return
        if (status != BluetoothGatt.GATT_SUCCESS) {
            dropAndRetry("service discovery failed (status=$status)")
            return
        }
        ready = true
        if (!listener.onServicesReady(g)) dropAndRetry("expected service not found")
    }

    private fun dropAndRetry(reason: String) {
        val wasReady = ready
        Log.w(tag, "$address: $reason; retrying ${if (wasReady) "now" else "in ${RETRY_MS / 1000} s"}")
        stopFinder()
        release()
        if (wasReady) listener.onLinkDown()
        if (wasReady) handler.post { connect() } else retryLater()
    }

    private fun retryLater() {
        if (running) handler.postDelayed({ connect() }, RETRY_MS)
    }

    private fun startFinder(adapter: BluetoothAdapter) {
        if (finder != null) return
        val wait = lastFinderStart + RETRY_MS - SystemClock.elapsedRealtime()
        if (wait > 0) {
            handler.postDelayed({ if (gatt != null && !ready) startFinder(adapter) }, wait)
            return
        }
        val scanner = adapter.bluetoothLeScanner ?: return
        val callback = object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult?) {
                val device = result?.device ?: return
                handler.post { onDeviceSeen(device) }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(tag, "Scan failed (error $errorCode); relying on the background connect")
                handler.post { finder = null }
            }
        }
        val filter = ScanFilter.Builder().setDeviceAddress(address).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_BALANCED).build()
        try {
            scanner.startScan(listOf(filter), settings, callback)
            finder = callback
            lastFinderStart = SystemClock.elapsedRealtime()
        } catch (e: SecurityException) {
            Log.w(tag, "Scan denied — missing permission; relying on the background connect", e)
        }
    }

    private fun onDeviceSeen(device: BluetoothDevice) {
        if (!running || finder == null || ready) return
        stopFinder()
        release()
        try {
            gatt = device.connectGatt(context, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
        } catch (e: SecurityException) {
            Log.w(tag, "Connect denied — missing BLUETOOTH_CONNECT permission", e)
        }
        if (gatt == null) retryLater()
    }

    private fun stopFinder() {
        val callback = finder ?: return
        finder = null
        try {
            adapter?.bluetoothLeScanner?.stopScan(callback)
        } catch (_: SecurityException) {
            // Permission revoked mid-session; the scan dies with it.
        }
    }

    private fun release() {
        ready = false
        clearOps()
        val g = gatt ?: return
        gatt = null
        try {
            g.disconnect()
            g.close()
        } catch (_: SecurityException) {
            // Permission revoked mid-session: just drop the reference.
        }
    }

    companion object {
        /** Between attempts, and between scan starts (Android allows five per 30 s). */
        const val RETRY_MS = 8_000L

        /** The MTU to ask for: the most a BLE 4.2+ link carries in one packet. */
        const val PREFERRED_MTU = 247

        /** A GATT operation with no callback by then is given up, so the queue never sticks. */
        const val OP_TIMEOUT_MS = 5_000L

        /** The standard Client Characteristic Configuration Descriptor, 0x2902. */
        val CLIENT_CHARACTERISTIC_CONFIG_UUID: UUID = UUID.fromString("00002902-0000-1000-8000-00805F9B34FB")
    }
}
