package dev.digitalducktape.openride.core.controller

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.digitalducktape.openride.core.ble.BleConnection
import dev.digitalducktape.openride.core.sensor.ConnectionState
import java.io.IOException
import java.io.InputStream
import java.io.OutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.UUID
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * One paired controller's connection (issue #68), over either OpenBikeControl transport. From
 * [start] to [stop] it keeps reconnecting; [onMessage] gets every decoded message, on the main
 * thread.
 *
 * [connectionState] is [ConnectionState.Connected] once button notifications are subscribed (BLE)
 * or the TCP socket is open: a controller only speaks when a button is pressed, so waiting for a
 * first message, as the bike and the strap do, would show a working controller as offline.
 */
interface ObcLink {
    val connectionState: StateFlow<ConnectionState>

    /** The controller's battery, when it reports one (network controllers only, by the spec). */
    val batteryPercent: StateFlow<Int?>

    fun start(onMessage: (ObcMessage) -> Unit)
    fun stop()

    /** Sends a haptic pattern ([ObcProtocol.haptic]); dropped if the controller can't take it. */
    fun haptic(pattern: Int)
}

/** The App Information OpenRide sends each controller on connecting. */
internal fun openRideAppInfo(appVersion: String): ByteArray =
    ObcProtocol.appInfo(appId = "openride", appVersion = appVersion, buttonIds = ControllerAction.supportedButtonIds)

/**
 * A controller over BLE (BLE.md): subscribe to Button State, then write App Information. Haptic
 * Feedback is written without a response. Controllers that lack App Information or Haptic
 * Feedback still work: both are optional for us.
 */
class BleObcLink(
    context: Context,
    address: String,
    private val appVersion: String,
) : ObcLink {
    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()
    override val batteryPercent: StateFlow<Int?> = MutableStateFlow(null)

    private var onMessage: (ObcMessage) -> Unit = {}
    private var hapticCharacteristic: BluetoothGattCharacteristic? = null

    private val connection: BleConnection = BleConnection(
        context = context,
        address = address,
        tag = TAG,
        listener = object : BleConnection.Listener {
            override fun onServicesReady(gatt: BluetoothGatt): Boolean {
                val service = gatt.getService(ObcProtocol.SERVICE_UUID) ?: return false
                val buttons = service.getCharacteristic(ObcProtocol.BUTTON_STATE_UUID) ?: return false
                hapticCharacteristic = service.getCharacteristic(ObcProtocol.HAPTIC_UUID)
                // First, so App Information (30-odd bytes) goes in one write, not fragments.
                connection.requestMtu { ok -> if (!ok) Log.w(TAG, "Controller $address kept the default MTU") }
                connection.enableNotifications(buttons) { ok ->
                    if (ok) {
                        Log.w(TAG, "Controller $address connected")
                        _connectionState.value = ConnectionState.Connected
                    } else {
                        connection.reconnect("button notifications refused")
                    }
                }
                service.getCharacteristic(ObcProtocol.APP_INFO_UUID)?.let {
                    connection.write(it, openRideAppInfo(appVersion)) { ok ->
                        Log.w(TAG, "Controller $address: App Information ${if (ok) "sent" else "write failed"}")
                    }
                }
                return true
            }

            override fun onNotification(characteristic: UUID, value: ByteArray) {
                if (characteristic == ObcProtocol.BUTTON_STATE_UUID) ObcProtocol.decode(value).forEach(onMessage)
            }

            override fun onLinkDown() {
                hapticCharacteristic = null
                _connectionState.value = ConnectionState.Disconnected
            }
        },
    )

    override fun start(onMessage: (ObcMessage) -> Unit) {
        this.onMessage = onMessage
        connection.start()
    }

    override fun stop() {
        connection.stop()
        hapticCharacteristic = null
        _connectionState.value = ConnectionState.Unavailable
    }

    override fun haptic(pattern: Int) {
        val characteristic = hapticCharacteristic ?: return
        if (connection.isReady) connection.write(characteristic, ObcProtocol.haptic(pattern), withResponse = false)
    }

    private companion object {
        const val TAG = "BleObcLink"
    }
}

/**
 * A controller on the local network (MDNS.md): find the mDNS service named [serviceName], open a
 * TCP connection to it, send App Information, and read messages until it closes. Then it looks
 * the service up again, since the controller (a BikeControl phone, say) may have a new address.
 *
 * The socket runs on its own thread; [onMessage] and the state are posted to the main thread.
 */
class NetworkObcLink(
    context: Context,
    private val serviceName: String,
    private val appVersion: String,
) : ObcLink {
    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()
    private val _batteryPercent = MutableStateFlow<Int?>(null)
    override val batteryPercent: StateFlow<Int?> = _batteryPercent.asStateFlow()

    private val nsd = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val handler = Handler(Looper.getMainLooper())
    private var onMessage: (ObcMessage) -> Unit = {}

    // Main thread only.
    private var running = false
    private var discovery: NsdManager.DiscoveryListener? = null
    private var resolving = false
    private var worker: Thread? = null

    /** Bumped by each connect and by [stop], so a closed socket from an earlier one is ignored. */
    private var generation = 0

    @Volatile
    private var socket: Socket? = null

    override fun start(onMessage: (ObcMessage) -> Unit) {
        this.onMessage = onMessage
        handler.post {
            if (running) return@post
            running = true
            discover()
        }
    }

    override fun stop() {
        handler.post {
            running = false
            handler.removeCallbacksAndMessages(null)
            generation++
            stopDiscovery()
            closeSocket()
            worker = null
            _batteryPercent.value = null
            _connectionState.value = ConnectionState.Unavailable
        }
    }

    override fun haptic(pattern: Int) {
        val s = socket ?: return
        // Off the main thread: a socket write may block.
        Thread { runCatching { s.getOutputStream().apply { write(ObcProtocol.haptic(pattern)); flush() } } }.start()
    }

    private fun discover() {
        if (!running || discovery != null || worker != null) return
        val manager = nsd ?: run {
            Log.w(TAG, "No network service discovery on this device")
            return
        }
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String?) {}
            override fun onDiscoveryStopped(serviceType: String?) {}

            override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
                Log.w(TAG, "mDNS discovery failed to start (error $errorCode)")
                handler.post {
                    discovery = null
                    retryLater()
                }
            }

            override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {}

            override fun onServiceFound(info: NsdServiceInfo?) {
                if (info?.serviceName == serviceName) handler.post { resolve(info) }
            }

            override fun onServiceLost(info: NsdServiceInfo?) {}
        }
        try {
            manager.discoverServices(ObcProtocol.MDNS_SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            discovery = listener
        } catch (e: RuntimeException) {
            Log.w(TAG, "mDNS discovery refused", e)
            retryLater()
        }
    }

    private fun resolve(info: NsdServiceInfo) {
        if (!running || resolving || worker != null) return
        val manager = nsd ?: return
        resolving = true
        @Suppress("DEPRECATION") // resolveService is the form API 29-33 have.
        manager.resolveService(
            info,
            object : NsdManager.ResolveListener {
                override fun onResolveFailed(serviceInfo: NsdServiceInfo?, errorCode: Int) {
                    Log.w(TAG, "Couldn't resolve $serviceName (error $errorCode)")
                    handler.post {
                        resolving = false
                        // Discovery reports the service again; until then, a timed retry.
                        retryLater()
                    }
                }

                override fun onServiceResolved(serviceInfo: NsdServiceInfo?) {
                    @Suppress("DEPRECATION") // host is the form API 29-33 have.
                    val host = serviceInfo?.host
                    val port = serviceInfo?.port ?: 0
                    handler.post {
                        resolving = false
                        if (host != null && port > 0) connect(host.hostAddress ?: return@post, port) else retryLater()
                    }
                }
            },
        )
    }

    private fun connect(host: String, port: Int) {
        if (!running || worker != null) return
        stopDiscovery()
        val gen = ++generation
        // Made here, not on the thread, so a stop() that comes first still closes it.
        val s = Socket()
        socket = s
        val thread = Thread({ readLoop(s, host, port, gen) }, "obc-$serviceName")
        worker = thread
        thread.start()
    }

    private fun readLoop(s: Socket, host: String, port: Int, gen: Int) {
        try {
            s.tcpNoDelay = true
            s.connect(InetSocketAddress(host, port), CONNECT_TIMEOUT_MS)
            val output: OutputStream = s.getOutputStream()
            output.write(openRideAppInfo(appVersion))
            output.flush()
            Log.w(TAG, "Controller $serviceName connected at $host:$port")
            handler.post { if (gen == generation) _connectionState.value = ConnectionState.Connected }
            val input: InputStream = s.getInputStream()
            val buffer = ByteArray(READ_BUFFER)
            while (true) {
                val n = input.read(buffer)
                if (n < 0) break
                if (n == 0) continue
                val messages = ObcProtocol.decode(buffer.copyOf(n))
                handler.post { if (gen == generation) messages.forEach(::deliver) }
            }
            Log.w(TAG, "Controller $serviceName closed the connection")
        } catch (e: IOException) {
            Log.w(TAG, "Controller $serviceName: ${e.message}")
        } finally {
            runCatching { s.close() }
            handler.post { onSocketClosed(s, gen) }
        }
    }

    private fun deliver(message: ObcMessage) {
        if (message is ObcMessage.DeviceStatus) _batteryPercent.value = message.batteryPercent
        onMessage(message)
    }

    private fun onSocketClosed(s: Socket, gen: Int) {
        if (socket === s) socket = null
        if (gen != generation) return
        worker = null
        if (_connectionState.value == ConnectionState.Connected) _connectionState.value = ConnectionState.Disconnected
        retryLater()
    }

    private fun retryLater() {
        if (running) handler.postDelayed({ discover() }, RETRY_MS)
    }

    private fun stopDiscovery() {
        val listener = discovery ?: return
        discovery = null
        runCatching { nsd?.stopServiceDiscovery(listener) }
    }

    private fun closeSocket() {
        val s = socket ?: return
        socket = null
        runCatching { s.close() }
    }

    private companion object {
        const val TAG = "NetworkObcLink"
        const val RETRY_MS = 5_000L
        const val CONNECT_TIMEOUT_MS = 5_000
        const val READ_BUFFER = 256
    }
}
