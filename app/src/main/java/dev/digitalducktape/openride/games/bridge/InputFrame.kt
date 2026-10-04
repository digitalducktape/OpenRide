package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.ConnectionState

/** Head-tracker state, input frame index 9 (Bridge contract v1, docs/GAMES.md). */
enum class TrackerState(val code: Int) {
    OFF(0),
    NEEDS_CALIBRATION(1),
    CALIBRATING(2),
    TRACKING(3),
    FACE_LOST(4),
}

/**
 * The head tracker's contribution to the input frame (indices 6-9): filtered, calibrated lean
 * and posture. The camera tracker (#33) supplies these; until then every frame reads [OFF].
 */
data class TrackerReading(
    /** -1 (rider's left) .. +1 (right). */
    val leanX: Double,
    /** -1 (back) .. +1 (in); 0 when the depth axis is disabled. */
    val leanDepth: Double,
    val standing: Boolean,
    val state: TrackerState,
) {
    companion object {
        val OFF = TrackerReading(leanX = 0.0, leanDepth = 0.0, standing = false, state = TrackerState.OFF)
    }
}

/**
 * The v1 input frame that `InputBus` polls every frame via `get_input_frame()`, arriving in
 * GDScript as a `PackedFloat64Array`. The index layout is the Bridge contract in
 * `docs/GAMES.md` and must only change together with that file (and [VERSION]).
 */
object InputFrame {
    const val VERSION = 1

    const val VERSION_INDEX = 0
    const val CADENCE = 1
    const val POWER = 2
    const val RESISTANCE = 3
    const val SPEED = 4
    const val HEART_RATE = 5
    const val LEAN_X = 6
    const val LEAN_DEPTH = 7
    const val STANDING = 8
    const val TRACKER_STATE = 9
    const val SEGMENT_TIME_LEFT = 10
    const val SENSORS_OK = 11

    const val SIZE = 12

    /** [HEART_RATE] when no strap is connected. */
    const val NO_HEART_RATE = -1.0

    fun pack(
        metrics: BikeMetrics,
        connection: ConnectionState,
        heartRateBpm: Int?,
        tracker: TrackerReading,
        segmentTimeLeftSec: Double,
    ): DoubleArray = DoubleArray(SIZE).apply {
        this[VERSION_INDEX] = VERSION.toDouble()
        this[CADENCE] = metrics.cadenceRpm.toDouble()
        this[POWER] = metrics.powerWatts.toDouble()
        this[RESISTANCE] = metrics.resistancePercent.toDouble()
        this[SPEED] = metrics.speedMph
        this[HEART_RATE] = heartRateBpm?.toDouble() ?: NO_HEART_RATE
        this[LEAN_X] = tracker.leanX.coerceIn(-1.0, 1.0)
        this[LEAN_DEPTH] = tracker.leanDepth.coerceIn(-1.0, 1.0)
        this[STANDING] = if (tracker.standing) 1.0 else 0.0
        this[TRACKER_STATE] = tracker.state.code.toDouble()
        this[SEGMENT_TIME_LEFT] = segmentTimeLeftSec
        this[SENSORS_OK] = if (connection == ConnectionState.Connected) 1.0 else 0.0
    }
}
