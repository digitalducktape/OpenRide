package dev.digitalducktape.openride.core.trainer

import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCharacteristic
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import dev.digitalducktape.openride.core.ble.BleConnection
import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.core.sensor.ManagedBikeDataSource
import dev.digitalducktape.openride.core.sensor.ResistanceControl
import dev.digitalducktape.openride.core.sensor.pelotonSpeedMphFromPower
import java.util.UUID
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * A smart trainer or smart bike over the Bluetooth Fitness Machine Service (FTMS, issue #68), as
 * the bike source: Indoor Bike Data gives cadence, power and speed, and OpenRide's virtual
 * resistance goes back to the trainer through the Control Point.
 *
 * ## Resistance
 * The trainer has no knob OpenRide can read, so resistance is a 0-100 % that the rider steps
 * ([stepResistance]: on-screen buttons, or a controller's shifters) and that [metrics] reports,
 * so games and screens read it as they read a Peloton's knob. It's sent as
 * - **Set Target Resistance Level**, mapped onto the trainer's Supported Resistance Level Range,
 *   when the trainer takes a resistance target. The parameter's width differs between FTMS
 *   revisions (UINT8 in 1.0, SINT16 later), so the short form is tried first and the wide one
 *   after an Invalid Parameter;
 * - else **Set Indoor Bike Simulation Parameters**, as a grade from 0 to [MAX_GRADE_PERCENT],
 *   for trainers that only simulate a road.
 *
 * One command is in flight at a time (the Control Point answers each with an indication); steps
 * taken meanwhile collapse into the latest target.
 *
 * ## Connection state
 * [ConnectionState.Connected] once a real Indoor Bike Data frame has been decoded, as for the
 * Peloton and the strap, and [ConnectionState.Disconnected] after a live link drops. Frames
 * aren't watched for silence ([dev.digitalducktape.openride.core.sensor.watchFrames]): some
 * trainers stop notifying while nobody pedals, and that isn't a fault.
 *
 * **Hardware caveat:** built to the public FTMS specification and unit-tested against its byte
 * layouts (`FtmsProtocolTest`), not yet ridden on a trainer.
 */
class FtmsBikeDataSource(
    context: Context,
    private val address: String,
) : ManagedBikeDataSource, ResistanceControl {

    private val _metrics = MutableStateFlow(BikeMetrics.ZERO.copy(resistancePercent = DEFAULT_RESISTANCE_PERCENT))
    override val metrics: StateFlow<BikeMetrics> = _metrics.asStateFlow()

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _adjustable = MutableStateFlow(false)
    override val adjustable: StateFlow<Boolean> = _adjustable.asStateFlow()

    private enum class Mode { RESISTANCE, SIMULATION, NONE }

    // Main thread only, like BleConnection's callbacks.
    private val handler = Handler(Looper.getMainLooper())
    private var targetPercent = DEFAULT_RESISTANCE_PERCENT
    private var controlPoint: BluetoothGattCharacteristic? = null
    private var mode = Mode.RESISTANCE
    private var range = ResistanceRange.DEFAULT
    private var wideResistance = false
    private var hasControl = false
    private var commandInFlight = false
    private var targetPending = false
    private val commandTimeout = Runnable { onCommandDone() }

    private val connection: BleConnection = BleConnection(
        context = context,
        address = address,
        tag = TAG,
        listener = object : BleConnection.Listener {
            override fun onServicesReady(gatt: BluetoothGatt): Boolean = setUp(gatt)

            override fun onNotification(characteristic: UUID, value: ByteArray) = when (characteristic) {
                FtmsProtocol.INDOOR_BIKE_DATA_UUID -> onBikeData(value)
                FtmsProtocol.CONTROL_POINT_UUID -> onControlPoint(value)
                else -> Unit
            }

            override fun onLinkDown() {
                resetControl()
                if (_connectionState.value == ConnectionState.Connected) _connectionState.value = ConnectionState.Disconnected
                _metrics.value = BikeMetrics.ZERO.copy(resistancePercent = targetPercent)
            }
        },
    )

    override fun start() = connection.start()

    override fun stop() {
        connection.stop()
        handler.post {
            handler.removeCallbacksAndMessages(null)
            resetControl()
            _connectionState.value = ConnectionState.Unavailable
        }
    }

    override fun stepResistance(steps: Int) {
        handler.post {
            if (!_adjustable.value) return@post
            val next = (targetPercent + steps * ResistanceControl.RESISTANCE_STEP_PERCENT).coerceIn(0, 100)
            if (next == targetPercent) return@post
            targetPercent = next
            _metrics.value = _metrics.value.copy(resistancePercent = next)
            sendTarget()
        }
    }

    /** Queues the setup: what the trainer takes, its range, then data and the Control Point. */
    private fun setUp(gatt: BluetoothGatt): Boolean {
        val service = gatt.getService(FtmsProtocol.SERVICE_UUID) ?: return false
        val bikeData = service.getCharacteristic(FtmsProtocol.INDOOR_BIKE_DATA_UUID) ?: return false
        resetControl()
        service.getCharacteristic(FtmsProtocol.FEATURE_UUID)?.let { feature ->
            connection.read(feature) { bytes ->
                val features = bytes?.let(FtmsProtocol::parseFeatures) ?: return@read
                mode = when {
                    features.resistanceTarget -> Mode.RESISTANCE
                    features.simulation -> Mode.SIMULATION
                    else -> Mode.NONE
                }
                Log.w(TAG, "Trainer $address takes $mode targets")
            }
        }
        service.getCharacteristic(FtmsProtocol.SUPPORTED_RESISTANCE_RANGE_UUID)?.let { rangeCharacteristic ->
            connection.read(rangeCharacteristic) { bytes -> bytes?.let(FtmsProtocol::parseResistanceRange)?.let { range = it } }
        }
        connection.enableNotifications(bikeData)
        val cp = service.getCharacteristic(FtmsProtocol.CONTROL_POINT_UUID)
        if (cp != null) {
            controlPoint = cp
            connection.enableNotifications(cp, indicate = true) { ok ->
                if (ok && mode != Mode.NONE) connection.write(cp, FtmsProtocol.requestControl())
            }
        }
        return true
    }

    private fun onBikeData(bytes: ByteArray) {
        val data = FtmsProtocol.parseIndoorBikeData(bytes)
        if (data == null) {
            Log.w(TAG, "Malformed Indoor Bike Data, dropping")
            return
        }
        val power = data.powerWatts?.coerceAtLeast(0) ?: 0
        _metrics.value = BikeMetrics(
            cadenceRpm = data.cadenceRpm?.roundToInt() ?: 0,
            resistancePercent = if (_adjustable.value) targetPercent else reportedPercent(data.resistanceLevel) ?: targetPercent,
            powerWatts = power,
            speedMph = data.speedKmh?.let { it * MPH_PER_KMH } ?: pelotonSpeedMphFromPower(power.toDouble()),
        )
        if (_connectionState.value != ConnectionState.Connected) {
            Log.w(TAG, "Trainer $address connected")
            _connectionState.value = ConnectionState.Connected
        }
    }

    /** A trainer we can't set reports its own level now and then: as a % of its range. */
    private fun reportedPercent(level: Int?): Int? {
        level ?: return null
        val tenths = level * 10
        return ((tenths - range.minTenths) * 100 / (range.maxTenths - range.minTenths)).coerceIn(0, 100)
    }

    private fun onControlPoint(bytes: ByteArray) {
        val response = FtmsProtocol.parseResponse(bytes) ?: return
        when (response.requestOp) {
            FtmsProtocol.OP_REQUEST_CONTROL -> {
                if (!response.succeeded) {
                    Log.w(TAG, "Trainer $address refused control (result ${response.result})")
                    return
                }
                hasControl = true
                _adjustable.value = true
                _metrics.value = _metrics.value.copy(resistancePercent = targetPercent)
                controlPoint?.let { connection.write(it, FtmsProtocol.startOrResume()) }
                sendTarget()
            }
            FtmsProtocol.OP_SET_TARGET_RESISTANCE -> {
                if (response.result == FtmsProtocol.RESULT_INVALID_PARAMETER && !wideResistance) {
                    Log.w(TAG, "Trainer $address wants the wide resistance target; resending")
                    wideResistance = true
                    targetPending = true
                } else if (!response.succeeded) {
                    Log.w(TAG, "Trainer $address refused a resistance target (result ${response.result})")
                }
                onCommandDone()
            }
            FtmsProtocol.OP_SET_INDOOR_BIKE_SIMULATION -> onCommandDone()
        }
    }

    private fun sendTarget() {
        val cp = controlPoint ?: return
        if (!hasControl) return
        if (commandInFlight) {
            targetPending = true
            return
        }
        val command = when (mode) {
            Mode.RESISTANCE -> FtmsProtocol.setTargetResistance(range.tenthsFor(targetPercent), wideResistance)
            Mode.SIMULATION -> FtmsProtocol.setSimulationGrade(targetPercent * MAX_GRADE_PERCENT / 100.0)
            Mode.NONE -> return
        }
        commandInFlight = true
        targetPending = false
        handler.postDelayed(commandTimeout, COMMAND_TIMEOUT_MS)
        connection.write(cp, command) { ok -> if (!ok) onCommandDone() }
    }

    private fun onCommandDone() {
        handler.removeCallbacks(commandTimeout)
        commandInFlight = false
        if (targetPending) sendTarget()
    }

    private fun resetControl() {
        handler.removeCallbacks(commandTimeout)
        controlPoint = null
        hasControl = false
        commandInFlight = false
        targetPending = false
        mode = Mode.RESISTANCE
        _adjustable.value = false
    }

    companion object {
        private const val TAG = "FtmsBikeDataSource"

        /** Where a ride starts: light, like a Peloton's knob at the start of a warm-up. */
        const val DEFAULT_RESISTANCE_PERCENT = 25

        /** 100 % on a trainer that only simulates grade: a steep climb. */
        const val MAX_GRADE_PERCENT = 15.0

        /** A command the Control Point hasn't answered by then is given up on. */
        const val COMMAND_TIMEOUT_MS = 2_000L

        private const val MPH_PER_KMH = 0.621371
    }
}
