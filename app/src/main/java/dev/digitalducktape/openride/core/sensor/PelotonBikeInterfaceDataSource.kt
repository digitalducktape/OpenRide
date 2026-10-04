package dev.digitalducktape.openride.core.sensor

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.os.RemoteException
import android.util.Log
import com.onepeloton.affernetservice.BikeData
import com.onepeloton.affernetservice.IBikeCallback
import com.onepeloton.affernetservice.IBikeInterface
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Real [BikeDataSource] for boards that stream over the affernet `IBikeInterface` binder —
 * notably the **Bike+** (`ro.product.board=topaz`, Android 10).
 *
 * The sibling of [PelotonBikeDataSource], which speaks `IV1Interface`. Both bind the same
 * exported, unguarded `AffernetService` and both receive the same [BikeData] parcelable; only
 * the binder action and callback type differ. Which one a given board actually feeds is not
 * discoverable ahead of time, so [AffernetBikeDataSource] runs both and keeps whichever
 * delivers a frame.
 *
 * ## Why this path exists
 *
 * On the Gen 2 (`RB1VQ`, Android 11) `IV1Interface` streams frames stationary with no rider.
 * On the Bike+ it does not: the bind lands, `registerCallback` is accepted, and nothing ever
 * arrives — verified on-device with a rider actively pedaling. The stock Peloton software on
 * that board holds `IBikeInterface` bound instead. See docs/SENSOR_PROTOCOL.md.
 *
 * ## Protocol
 *
 * - **Bind**: `Intent(action = "com.onepeloton.affernetservice.IBikeInterface")`,
 *   `package = "com.onepeloton.affernetservice"`.
 * - **Model**: callback / push. [IBikeInterface.registerCallback] an [IBikeCallback]; the
 *   service invokes [IBikeCallback.onSensorDataChange] with a [BikeData] frame (transaction 1)
 *   and [IBikeCallback.onSensorError] on a fault (transaction 2).
 * - **Poll fallback**: [pollBikeData] reads [IBikeInterface.getBikeData] (transaction 14)
 *   synchronously. Same struct, no callback registration involved — used to tell "the board
 *   does not push" apart from "the reconstructed callback is wrong".
 * - **Decode**: shared with the V1 path via [toBikeMetrics].
 *
 * ## Connection state
 *
 * Identical contract to [PelotonBikeDataSource]: [ConnectionState.Connected] only once a real
 * frame arrives, so a successful bind that never delivers data cannot masquerade as live
 * (PRD P0-9). [start] never throws on a non-bike device. A dead or null binding is released and
 * rebound with backoff, exactly as described there.
 */
class PelotonBikeInterfaceDataSource(
    private val context: Context,
) : PollableBikeDataSource {

    private val _metrics = MutableStateFlow(BikeMetrics.ZERO)
    override val metrics: StateFlow<BikeMetrics> = _metrics.asStateFlow()

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private var service: IBikeInterface? = null

    /** True once the service is bound and the [IBikeInterface] proxy is available. */
    val isServiceBound: Boolean get() = service != null

    /** Count of sensor frames decoded since [start]. Exposed for on-device verification. */
    @Volatile
    var framesReceived: Long = 0L
        private set

    /** True between [start] and [stop]; a rebind that fires outside that window does nothing. */
    @Volatile
    private var started = false

    private val rebinder = ServiceRebinder { rebind() }

    private val callback = object : IBikeCallback.Stub() {
        override fun onSensorDataChange(bikeData: BikeData?) {
            if (bikeData == null) return
            framesReceived++
            _metrics.value = bikeData.toBikeMetrics()
            if (_connectionState.value != ConnectionState.Connected) {
                _connectionState.value = ConnectionState.Connected
            }
        }

        override fun onSensorError(errorCode: Long) {
            Log.w(TAG, "Peloton sensor service reported sensor error: $errorCode")
            _connectionState.value = ConnectionState.Disconnected
        }

        override fun onCalibrationStatus(status: Int, success: Boolean, timestamp: Long) {
            // Not used — OpenRide never triggers calibration.
        }
    }

    private val serviceConnection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, binder: IBinder?) {
            Log.i(TAG, "affernet IBikeInterface connected: $name")
            val iface = IBikeInterface.Stub.asInterface(binder)
            if (iface == null) {
                _connectionState.value = ConnectionState.Unavailable
                return
            }
            service = iface
            try {
                iface.registerCallback(callback, CLIENT_ID)
                rebinder.reset()
                // Stay Unavailable until the first frame actually arrives.
            } catch (e: RemoteException) {
                Log.w(TAG, "registerCallback failed", e)
                _connectionState.value = ConnectionState.Unavailable
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.w(TAG, "affernet IBikeInterface disconnected: $name")
            service = null
            _connectionState.value = ConnectionState.Disconnected
        }

        override fun onBindingDied(name: ComponentName?) {
            Log.w(TAG, "affernet IBikeInterface binding died: $name")
            service = null
            _connectionState.value = ConnectionState.Unavailable
            // Android never revives a dead binding; it has to be released and bound afresh.
            scheduleRebind()
        }

        override fun onNullBinding(name: ComponentName?) {
            Log.w(TAG, "affernet IBikeInterface returned a null binding: $name")
            _connectionState.value = ConnectionState.Unavailable
            scheduleRebind()
        }
    }

    /**
     * Binds the sensor service. Safe on any device — if the service package is absent or the
     * bind is denied, this degrades to [ConnectionState.Unavailable] instead of throwing.
     */
    override fun start() {
        started = true
        bind()
    }

    /** Issues the bind. Returns whether Android accepted it; on refusal the state is Unavailable. */
    private fun bind(): Boolean {
        try {
            val intent = Intent(SERVICE_ACTION).apply { setPackage(SERVICE_PACKAGE) }
            val bound = context.bindService(intent, serviceConnection, Context.BIND_AUTO_CREATE)
            if (!bound) {
                Log.w(TAG, "bindService returned false for $SERVICE_PACKAGE — service unavailable")
                _connectionState.value = ConnectionState.Unavailable
            }
            return bound
        } catch (e: SecurityException) {
            Log.w(TAG, "Bind denied for affernet IBikeInterface", e)
            _connectionState.value = ConnectionState.Unavailable
        } catch (e: Exception) {
            Log.w(TAG, "Unexpected failure binding affernet IBikeInterface", e)
            _connectionState.value = ConnectionState.Unavailable
        }
        return false
    }

    /**
     * Releases the dead or null binding and schedules a fresh bind with capped exponential
     * backoff (see [ServiceRebinder]). The backoff resets once a rebind registers its callback.
     */
    private fun scheduleRebind() {
        unbindQuietly()
        if (!started) return
        val delayMs = rebinder.schedule()
        Log.i(TAG, "rebinding $SERVICE_PACKAGE in ${delayMs}ms")
    }

    private fun rebind() {
        if (!started) return
        // A refused bind during recovery (service package mid-restart) is retried too.
        if (!bind()) scheduleRebind()
    }

    private fun unbindQuietly() {
        try {
            context.unbindService(serviceConnection)
        } catch (_: IllegalArgumentException) {
            // Not currently bound — already released, or never bound (common off-bike).
        }
    }

    /**
     * Reads one frame synchronously via `getBikeData` (transaction 14) and publishes it, exactly
     * as a pushed frame would be. Returns the decoded metrics, or `null` if not bound or the
     * call failed.
     *
     * This is the poll half of the source. It exists because "bound but silent" is a real board
     * behaviour (it is precisely what `IV1Interface` does on the Bike+), and a poll that returns
     * live values proves the binder and the [BikeData] layout are both correct even when nothing
     * is being pushed. [AffernetBikeDataSource] uses it as a last resort before giving up.
     */
    override fun pollBikeData(): BikeMetrics? {
        val frame = runCatching { service?.bikeData }.getOrNull() ?: return null
        val decoded = frame.toBikeMetrics()
        framesReceived++
        _metrics.value = decoded
        if (_connectionState.value != ConnectionState.Connected) {
            _connectionState.value = ConnectionState.Connected
        }
        return decoded
    }

    /**
     * Enables the service's synthetic-data mode for on-device verification only, never
     * production. Returns whether the service accepted the request.
     */
    fun setFakeDataModeForVerification(enabled: Boolean): Boolean = runCatching {
        val iface = service ?: return false
        if (enabled) iface.setEnableFakeDataMode(FAKE_DATA_MODE_ON) else false
    }.getOrDefault(false)

    /** Unbinds the service. Safe to call even if [start] never bound. */
    override fun stop() {
        started = false
        rebinder.cancel()
        runCatching { service?.unregisterCallback(callback, CLIENT_ID) }
        unbindQuietly()
        service = null
        _connectionState.value = ConnectionState.Unavailable
    }

    private companion object {
        const val TAG = "PelotonBikeIface"

        const val SERVICE_PACKAGE = "com.onepeloton.affernetservice"
        const val SERVICE_ACTION = "com.onepeloton.affernetservice.IBikeInterface"

        /** Free-form client tag the service logs against the registration. */
        const val CLIENT_ID = "OpenRide"

        /**
         * `setEnableFakeDataMode` takes an int mode rather than a boolean. 1 is the ordinary
         * "on" value; the interface has a separate `setDisableFakeDataMode()` for the off case,
         * which OpenRide does not declare (it stops at transaction 17).
         */
        const val FAKE_DATA_MODE_ON = 1
    }
}
