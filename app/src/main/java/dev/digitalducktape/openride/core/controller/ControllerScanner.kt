package dev.digitalducktape.openride.core.controller

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.digitalducktape.openride.core.heartrate.BleScanner

/**
 * Finds OpenBikeControl controllers for the pairing screen (issue #68): over Bluetooth, devices
 * advertising the OpenBikeControl service; on the network, the `_openbikecontrol._tcp` services.
 * A narrow interface so the screen's view model is tested with a fake.
 */
interface ControllerScanner {
    fun isBluetoothAvailable(): Boolean

    /**
     * Starts both searches, or only the network one unless [bluetooth] (no Bluetooth permission
     * yet). [onFound] fires once per controller, on the main thread; [onFailed] when the
     * Bluetooth search can't run (the network one carries on).
     */
    fun start(onFound: (PairedController) -> Unit, onFailed: (String) -> Unit, bluetooth: Boolean = true)

    fun stop()
}

/** The real [ControllerScanner]: [bleScanner] (built for the OpenBikeControl service) plus mDNS. */
class ObcControllerScanner(
    context: Context,
    private val bleScanner: BleScanner,
) : ControllerScanner {
    private val nsd = context.getSystemService(Context.NSD_SERVICE) as? NsdManager
    private val handler = Handler(Looper.getMainLooper())
    private var discovery: NsdManager.DiscoveryListener? = null

    override fun isBluetoothAvailable(): Boolean = bleScanner.isBluetoothAvailable()

    override fun start(onFound: (PairedController) -> Unit, onFailed: (String) -> Unit, bluetooth: Boolean) {
        stop()
        if (!bluetooth) {
            // Nothing to report: the screen is already asking for the permission.
        } else if (bleScanner.isBluetoothAvailable()) {
            bleScanner.startScan(
                onDeviceFound = { device ->
                    handler.post { onFound(PairedController(ControllerTransport.BLUETOOTH, device.address, device.name)) }
                },
                onScanFailed = { reason -> handler.post { onFailed(reason) } },
            )
        } else {
            onFailed("Bluetooth is off, so only controllers on the network can be found")
        }
        startNetworkSearch(onFound)
    }

    override fun stop() {
        bleScanner.stopScan()
        val listener = discovery ?: return
        discovery = null
        runCatching { nsd?.stopServiceDiscovery(listener) }
    }

    private fun startNetworkSearch(onFound: (PairedController) -> Unit) {
        val manager = nsd ?: return
        val seen = mutableSetOf<String>()
        val listener = object : NsdManager.DiscoveryListener {
            override fun onDiscoveryStarted(serviceType: String?) {}
            override fun onDiscoveryStopped(serviceType: String?) {}
            override fun onStartDiscoveryFailed(serviceType: String?, errorCode: Int) {
                Log.w(TAG, "mDNS search failed to start (error $errorCode)")
            }
            override fun onStopDiscoveryFailed(serviceType: String?, errorCode: Int) {}
            override fun onServiceLost(info: NsdServiceInfo?) {}

            override fun onServiceFound(info: NsdServiceInfo?) {
                val name = info?.serviceName ?: return
                handler.post {
                    if (seen.add(name)) onFound(PairedController(ControllerTransport.NETWORK, id = name, name = name))
                }
            }
        }
        try {
            manager.discoverServices(ObcProtocol.MDNS_SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, listener)
            discovery = listener
        } catch (e: RuntimeException) {
            Log.w(TAG, "mDNS search refused", e)
        }
    }

    private companion object {
        const val TAG = "ObcControllerScanner"
    }
}
