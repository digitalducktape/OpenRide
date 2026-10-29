package dev.digitalducktape.openride.core.trainer

import java.util.UUID
import kotlin.math.roundToInt

/**
 * The Bluetooth SIG Fitness Machine Service (FTMS 1.0) as an indoor bike uses it (issue #68),
 * reimplemented from the public specification: Indoor Bike Data in, Control Point commands out.
 * All integers are little-endian. Pure functions, so it's unit-tested on the JVM (`FtmsProtocolTest`).
 */
object FtmsProtocol {
    val SERVICE_UUID: UUID = uuid16(0x1826)
    val FEATURE_UUID: UUID = uuid16(0x2ACC)
    val INDOOR_BIKE_DATA_UUID: UUID = uuid16(0x2AD2)
    val SUPPORTED_RESISTANCE_RANGE_UUID: UUID = uuid16(0x2AD6)
    val CONTROL_POINT_UUID: UUID = uuid16(0x2AD9)

    /** Control Point op codes. */
    const val OP_REQUEST_CONTROL = 0x00
    const val OP_SET_TARGET_RESISTANCE = 0x04
    const val OP_START_OR_RESUME = 0x07
    const val OP_SET_INDOOR_BIKE_SIMULATION = 0x11
    const val OP_RESPONSE = 0x80

    /** Control Point result codes. */
    const val RESULT_SUCCESS = 0x01
    const val RESULT_INVALID_PARAMETER = 0x03

    /** Target Setting Features bits (the feature characteristic's second word). */
    private const val TARGET_RESISTANCE_SUPPORTED = 1 shl 2
    private const val TARGET_SIMULATION_SUPPORTED = 1 shl 13

    private fun uuid16(short: Int): UUID = UUID.fromString("0000%04X-0000-1000-8000-00805F9B34FB".format(short))

    /**
     * Decodes an Indoor Bike Data notification. Fields are present by flag, in spec order; the
     * one quirk is bit 0, "More Data", whose *clear* state means Instantaneous Speed is present.
     * Returns `null` for a frame too short for the flags it declares.
     */
    fun parseIndoorBikeData(bytes: ByteArray): IndoorBikeData? {
        val r = Reader(bytes)
        val flags = r.u16() ?: return null
        fun has(bit: Int) = flags and (1 shl bit) != 0
        var speed: Double? = null
        var cadence: Double? = null
        var resistance: Int? = null
        var power: Int? = null
        var heartRate: Int? = null
        if (!has(0)) speed = (r.u16() ?: return null) / 100.0 // km/h
        if (has(1)) r.skip(2) ?: return null // average speed
        if (has(2)) cadence = (r.u16() ?: return null) / 2.0 // rpm
        if (has(3)) r.skip(2) ?: return null // average cadence
        if (has(4)) r.skip(3) ?: return null // total distance
        if (has(5)) resistance = r.s16() ?: return null
        if (has(6)) power = r.s16() ?: return null
        if (has(7)) r.skip(2) ?: return null // average power
        if (has(8)) r.skip(5) ?: return null // expended energy: total, per hour, per minute
        if (has(9)) heartRate = r.u8() ?: return null
        return IndoorBikeData(speedKmh = speed, cadenceRpm = cadence, resistanceLevel = resistance, powerWatts = power, heartRateBpm = heartRate)
    }

    /** Which targets the trainer takes, from the Fitness Machine Feature characteristic. */
    fun parseFeatures(bytes: ByteArray): FtmsFeatures? {
        val r = Reader(bytes)
        r.u32() ?: return null // machine features
        val targets = r.u32() ?: return null
        return FtmsFeatures(
            resistanceTarget = targets and TARGET_RESISTANCE_SUPPORTED != 0,
            simulation = targets and TARGET_SIMULATION_SUPPORTED != 0,
        )
    }

    /** The Supported Resistance Level Range: minimum, maximum and step, each in tenths. */
    fun parseResistanceRange(bytes: ByteArray): ResistanceRange? {
        val r = Reader(bytes)
        val min = r.s16() ?: return null
        val max = r.s16() ?: return null
        val step = r.u16() ?: return null
        return if (max > min) ResistanceRange(minTenths = min, maxTenths = max, stepTenths = step.coerceAtLeast(1)) else null
    }

    /** A Control Point response: `[0x80, request op code, result]`, or `null` for anything else. */
    fun parseResponse(bytes: ByteArray): ControlPointResponse? {
        if (bytes.size < 3 || (bytes[0].toInt() and 0xFF) != OP_RESPONSE) return null
        return ControlPointResponse(requestOp = bytes[1].toInt() and 0xFF, result = bytes[2].toInt() and 0xFF)
    }

    fun requestControl(): ByteArray = byteArrayOf(OP_REQUEST_CONTROL.toByte())

    fun startOrResume(): ByteArray = byteArrayOf(OP_START_OR_RESUME.toByte())

    /**
     * Set Target Resistance Level, in tenths. FTMS 1.0 gives the parameter as a UINT8 (0.1
     * resolution); later GATT supplements as an SINT16, and trainers differ. [wide] picks the
     * SINT16 form, which the trainer source falls back to when the short one is refused.
     */
    fun setTargetResistance(tenths: Int, wide: Boolean): ByteArray =
        if (wide) {
            byteArrayOf(OP_SET_TARGET_RESISTANCE.toByte(), tenths.toByte(), (tenths shr 8).toByte())
        } else {
            byteArrayOf(OP_SET_TARGET_RESISTANCE.toByte(), tenths.coerceIn(0, 255).toByte())
        }

    /**
     * Set Indoor Bike Simulation Parameters: no wind, [gradePercent] (0.01 % units), and typical
     * rolling resistance and drag, for trainers that take a grade but no resistance level.
     */
    fun setSimulationGrade(gradePercent: Double): ByteArray {
        val grade = (gradePercent * 100).roundToInt()
        return byteArrayOf(
            OP_SET_INDOOR_BIKE_SIMULATION.toByte(),
            0, 0, // wind speed, 0.001 m/s
            grade.toByte(), (grade shr 8).toByte(),
            40, // Crr 0.0040, in 0.0001
            51, // Cw 0.51 kg/m, in 0.01
        )
    }

    /** Little-endian reads that return `null` past the end. */
    private class Reader(private val bytes: ByteArray) {
        private var i = 0

        private fun byte(at: Int) = bytes[at].toInt() and 0xFF

        fun u8(): Int? = if (i + 1 > bytes.size) null else byte(i).also { i += 1 }

        fun u16(): Int? = if (i + 2 > bytes.size) null else (byte(i) or (byte(i + 1) shl 8)).also { i += 2 }

        fun s16(): Int? = u16()?.let { if (it >= 0x8000) it - 0x10000 else it }

        fun u32(): Int? =
            if (i + 4 > bytes.size) null else (byte(i) or (byte(i + 1) shl 8) or (byte(i + 2) shl 16) or (byte(i + 3) shl 24)).also { i += 4 }

        fun skip(n: Int): Unit? {
            if (i + n > bytes.size) return null
            i += n
            return Unit
        }
    }
}

/** One Indoor Bike Data frame; each field is `null` when the trainer didn't send it. */
data class IndoorBikeData(
    val speedKmh: Double?,
    val cadenceRpm: Double?,
    val resistanceLevel: Int?,
    val powerWatts: Int?,
    val heartRateBpm: Int?,
)

data class FtmsFeatures(val resistanceTarget: Boolean, val simulation: Boolean)

/** A trainer's resistance range, in tenths of its unitless level. */
data class ResistanceRange(val minTenths: Int, val maxTenths: Int, val stepTenths: Int) {
    /** OpenRide's 0-100 % as this trainer's level, in tenths, on its step. */
    fun tenthsFor(percent: Int): Int {
        val raw = minTenths + (maxTenths - minTenths) * percent.coerceIn(0, 100) / 100.0
        val steps = ((raw - minTenths) / stepTenths).roundToInt()
        return (minTenths + steps * stepTenths).coerceIn(minTenths, maxTenths)
    }

    companion object {
        /** For a trainer that doesn't say: 0 to 100.0, in steps of 1.0. */
        val DEFAULT = ResistanceRange(minTenths = 0, maxTenths = 1000, stepTenths = 10)
    }
}

data class ControlPointResponse(val requestOp: Int, val result: Int) {
    val succeeded: Boolean get() = result == FtmsProtocol.RESULT_SUCCESS
}
