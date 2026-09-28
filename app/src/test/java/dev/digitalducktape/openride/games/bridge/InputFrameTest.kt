package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.ConnectionState
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Test

/** The v1 input frame layout from the Bridge contract (docs/GAMES.md), index by index. */
class InputFrameTest {
    private val metrics = BikeMetrics(cadenceRpm = 92, resistancePercent = 41, powerWatts = 187, speedMph = 17.5)

    @Test
    fun `packs every field at its contract index`() {
        val frame = InputFrame.pack(
            metrics = metrics,
            connection = ConnectionState.Connected,
            heartRateBpm = 143,
            tracker = TrackerReading(leanX = -0.5, leanDepth = 0.25, standing = true, state = TrackerState.TRACKING),
            segmentTimeLeftSec = 42.0,
        )

        assertArrayEquals(
            doubleArrayOf(1.0, 92.0, 187.0, 41.0, 17.5, 143.0, -0.5, 0.25, 1.0, 3.0, 42.0, 1.0),
            frame,
            0.0,
        )
    }

    @Test
    fun `indices match the contract table`() {
        assertEquals(0, InputFrame.VERSION_INDEX)
        assertEquals(1, InputFrame.CADENCE)
        assertEquals(2, InputFrame.POWER)
        assertEquals(3, InputFrame.RESISTANCE)
        assertEquals(4, InputFrame.SPEED)
        assertEquals(5, InputFrame.HEART_RATE)
        assertEquals(6, InputFrame.LEAN_X)
        assertEquals(7, InputFrame.LEAN_DEPTH)
        assertEquals(8, InputFrame.STANDING)
        assertEquals(9, InputFrame.TRACKER_STATE)
        assertEquals(10, InputFrame.SEGMENT_TIME_LEFT)
        assertEquals(11, InputFrame.SENSORS_OK)
        assertEquals(12, InputFrame.SIZE)
        assertEquals(1, InputFrame.VERSION)
    }

    @Test
    fun `no heart-rate strap reads -1`() {
        val frame = InputFrame.pack(metrics, ConnectionState.Connected, null, TrackerReading.OFF, 0.0)

        assertEquals(-1.0, frame[InputFrame.HEART_RATE], 0.0)
    }

    @Test
    fun `sensors_ok is 1 only while Connected`() {
        fun sensorsOk(state: ConnectionState) =
            InputFrame.pack(metrics, state, null, TrackerReading.OFF, 0.0)[InputFrame.SENSORS_OK]

        assertEquals(1.0, sensorsOk(ConnectionState.Connected), 0.0)
        assertEquals(0.0, sensorsOk(ConnectionState.Disconnected), 0.0)
        assertEquals(0.0, sensorsOk(ConnectionState.Unavailable), 0.0)
    }

    @Test
    fun `tracker off reads zero lean, seated, state 0`() {
        val frame = InputFrame.pack(metrics, ConnectionState.Connected, null, TrackerReading.OFF, 0.0)

        assertEquals(0.0, frame[InputFrame.LEAN_X], 0.0)
        assertEquals(0.0, frame[InputFrame.LEAN_DEPTH], 0.0)
        assertEquals(0.0, frame[InputFrame.STANDING], 0.0)
        assertEquals(0.0, frame[InputFrame.TRACKER_STATE], 0.0)
    }

    @Test
    fun `lean is clamped to -1 to 1`() {
        val frame = InputFrame.pack(
            metrics, ConnectionState.Connected, null,
            TrackerReading(leanX = 1.4, leanDepth = -3.0, standing = false, state = TrackerState.TRACKING),
            0.0,
        )

        assertEquals(1.0, frame[InputFrame.LEAN_X], 0.0)
        assertEquals(-1.0, frame[InputFrame.LEAN_DEPTH], 0.0)
    }

    @Test
    fun `tracker state codes`() {
        assertEquals(
            listOf(0, 1, 2, 3, 4),
            listOf(
                TrackerState.OFF, TrackerState.NEEDS_CALIBRATION, TrackerState.CALIBRATING,
                TrackerState.TRACKING, TrackerState.FACE_LOST,
            ).map { it.code },
        )
    }
}
