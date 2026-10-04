package dev.digitalducktape.openride.core.sensor

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.IBinder
import android.os.RemoteException
import android.util.Log
import com.onepeloton.affernetservice.BikeData
import com.onepeloton.affernetservice.IV1Callback
import com.onepeloton.affernetservice.IV1Interface
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Real [BikeDataSource] for the Peloton Bike Gen 2's onboard sensors (PRD P0-2, issue #3).
 *
 * Verified streaming on the Gen 2 (`RB1VQ`, Android 11). It does **not** stream on the Bike+
 * (`topaz`, Android 10), where the bind and `registerCallback` both succeed and no frame ever
 * follows — that board feeds [PelotonBikeInterfaceDataSource] instead. Neither class picks a
 * board; [AffernetBikeDataSource] runs both and keeps whichever delivers a frame.
 *
 * Reads cadence / resistance / power off the flywheel by binding the tablet's on-device
 * **affernet system service** (`com.onepeloton.affernetservice`) — an exported, unguarded
 * service any app may bind, independent of Peloton subscription state. This is the technique
 * grupetto proved on Gen 2; OpenRide reconstructs the interface as proper AIDL rather than
 * copying grupetto's code (see docs/SENSOR_PROTOCOL.md for the full protocol write-up).
 *
 * ## Protocol (verified against the on-device service and grupetto)
 *
 * - **Bind**: `Intent(action = "com.onepeloton.affernetservice.IV1Interface")`,
 *   `package = "com.onepeloton.affernetservice"`. The returned binder speaks
 *   [IV1Interface] (descriptor `...IV1Interface`).
 * - **Model**: callback / push, not polling. We [IV1Interface.registerCallback] an
 *   [IV1Callback]; the service then invokes [IV1Callback.onSensorDataChange] with a
 *   [BikeData] frame on every update (transaction code 1), and
 *   [IV1Callback.onSensorError] on a sensor fault (code 2).
 * - **Frame -> BikeMetrics scaling** (all confirmed against grupetto's Gen 2 decode):
 *     - `cadenceRpm`        = `BikeData.rpm`               (raw long, already RPM)
 *     - `powerWatts`        = `BikeData.power / 100`       (raw is centi-watts)
 *     - `resistancePercent` = `BikeData.currentResistance` (raw int, already 0..100)
 *     - `speedMph`          = derived from watts via [pelotonSpeedMphFromPower]
 *       (the service reports no speed field; stock Peloton also synthesises it from power).
 *
 * ## Connection state
 *
 * - [ConnectionState.Connected]    once the first frame arrives (proof the link is live).
 * - [ConnectionState.Disconnected] on binder death / service disconnect / sensor error.
 * - [ConnectionState.Unavailable]  on any bind failure, or before [start]. On an emulator or
 *   any non-bike device the service package is absent and we stay Unavailable — [start] never
 *   throws, and we never fabricate a zero/idle frame dressed up as a live reading (PRD P0-9).
 *
 * Binding is only Connected after a real frame is observed, so a successful bind that never
 * delivers data does not masquerade as live.
 *
 * ## Recovery
 *
 * If the affernet process is force-stopped or crashes, Android reports `onBindingDied` and does
 * not reconnect that binding by itself; a null binder (`onNullBinding`) is likewise stuck. Both
 * release the binding and rebind with capped exponential backoff ([ServiceRebinder]); the
 * reconnect re-registers the callback and the next frame restores Connected. [stop] cancels any
 * pending retry.
 */
class PelotonBikeDataSource(
    private val context: Context,
) : BoundBikeDataSource {

    private val _metrics = MutableStateFlow(BikeMetrics.ZERO)
    override val metrics: StateFlow<BikeMetrics> = _metrics.asStateFlow()

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private var service: IV1Interface? = null

    /**
     * True once the service is bound and the [IV1Interface] proxy is available (i.e.
     * `registerCallback` has been issued). Distinct from [connectionState], which only reports
     * [ConnectionState.Connected] after a real frame arrives. Exposed for on-device
     * verification (T3/#3) — lets a test confirm the bind/register step independently of
     * whether the stationary bike happens to be streaming frames yet.
     */
    val isServiceBound: Boolean get() = service != null

    /** Count of sensor frames decoded since [start]. Exposed for on-device verification. */
    @Volatile
    var framesReceived: Long = 0L
        private set

    /** True between [start] and [stop]; a rebind that fires outside that window does nothing. */
    @Volatile
    private var started = false

    private val rebinder = ServiceRebinder { rebind() }

    /**
     * Callback the service pushes frames to. Generated by the reconstructed AIDL, so the
     * transaction codes / interface descriptor / Parcel marshalling are correct by
     * construction (no hand-rolled `Parcel.transact`).
     */
    private val callback = object : IV1Callback.Stub() {
        override fun onSensorDataChange(bikeData: BikeData?) {
            if (bikeData == null) return
            framesReceived++
            _metrics.value = bikeData.toBikeMetrics()
            // First real frame is the only honest signal that the link is live.
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
            Log.i(TAG, "affernet sensor service connected: $name")
            val iface = IV1Interface.Stub.asInterface(binder)
            if (iface == null) {
                _connectionState.value = ConnectionState.Unavailable
                return
            }
            service = iface
            try {
                iface.registerCallback(callback, CLIENT_ID)
                rebinder.reset()
                // Ask for a ~1 Hz-ish frame rate; the service returns the rate it applied.
                // Best-effort — some firmware ignores this and streams at its own cadence.
                runCatching { iface.setCallbackReportRate(REPORT_RATE_MS) }
                // Stay Unavailable until the first frame actually arrives (see onSensorDataChange).
            } catch (e: RemoteException) {
                Log.w(TAG, "registerCallback failed", e)
                _connectionState.value = ConnectionState.Unavailable
            }
        }

        override fun onServiceDisconnected(name: ComponentName?) {
            Log.w(TAG, "affernet sensor service disconnected: $name")
            service = null
            _connectionState.value = ConnectionState.Disconnected
        }

        override fun onBindingDied(name: ComponentName?) {
            Log.w(TAG, "affernet sensor service binding died: $name")
            service = null
            _connectionState.value = ConnectionState.Unavailable
            // Android never revives a dead binding; it has to be released and bound afresh.
            scheduleRebind()
        }

        override fun onNullBinding(name: ComponentName?) {
            Log.w(TAG, "affernet sensor service returned a null binding: $name")
            _connectionState.value = ConnectionState.Unavailable
            scheduleRebind()
        }
    }

    /**
     * Binds the sensor service. Safe on any device — if the service package is absent (every
     * emulator / non-bike environment) or the bind is denied, this degrades to
     * [ConnectionState.Unavailable] instead of throwing. Call once; call [stop] to release.
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
            Log.w(TAG, "Bind denied for affernet sensor service", e)
            _connectionState.value = ConnectionState.Unavailable
        } catch (e: Exception) {
            Log.w(TAG, "Unexpected failure binding affernet sensor service", e)
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
     * Enables the service's synthetic-data mode: the service streams fake sensor frames with
     * NO rider pedaling. Intended ONLY for on-device verification of the bind/decode pipeline
     * (see docs/SENSOR_PROTOCOL.md), never for production use. Returns whether the service
     * accepted the request; `false` if not bound or the call failed.
     */
    fun setFakeDataModeForVerification(enabled: Boolean): Boolean =
        runCatching { service?.setFakeDataMode(enabled) ?: false }.getOrDefault(false)

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
        const val TAG = "PelotonBikeDataSource"

        // Bind target — the exported, unguarded affernet service. Binding with the
        // IV1Interface action returns the IV1Interface binder.
        const val SERVICE_PACKAGE = "com.onepeloton.affernetservice"
        const val SERVICE_ACTION = "com.onepeloton.affernetservice.IV1Interface"

        /** Free-form client tag the service logs against the registration. */
        const val CLIENT_ID = "OpenRide"

        /** Requested frame interval; ~1 Hz is plenty for the in-ride metrics UI. */
        const val REPORT_RATE_MS = 1000
    }
}
