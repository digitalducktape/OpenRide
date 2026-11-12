package dev.digitalducktape.openride.core.trainer

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** FTMS byte layouts, from the Fitness Machine Service 1.0 specification. */
class FtmsProtocolTest {
    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

    @Test
    fun `uuids are the SIG's 16-bit ones`() {
        assertEquals("00001826-0000-1000-8000-00805f9b34fb", FtmsProtocol.SERVICE_UUID.toString())
        assertEquals("00002ad2-0000-1000-8000-00805f9b34fb", FtmsProtocol.INDOOR_BIKE_DATA_UUID.toString())
        assertEquals("00002ad9-0000-1000-8000-00805f9b34fb", FtmsProtocol.CONTROL_POINT_UUID.toString())
    }

    @Test
    fun `speed, cadence and power`() {
        // Flags 0x0044: speed present (bit 0 clear), cadence (bit 2), power (bit 6).
        // Speed 30.00 km/h = 3000, cadence 90 rpm = 180 half-rpm, power 250 W.
        val data = FtmsProtocol.parseIndoorBikeData(bytes(0x44, 0x00, 0xB8, 0x0B, 0xB4, 0x00, 0xFA, 0x00))!!

        assertEquals(30.0, data.speedKmh!!, 1e-9)
        assertEquals(90.0, data.cadenceRpm!!, 1e-9)
        assertEquals(250, data.powerWatts)
        assertNull(data.resistanceLevel)
        assertNull(data.heartRateBpm)
    }

    @Test
    fun `more data set means no speed`() {
        // Flags 0x0041: more data (no speed), power.
        val data = FtmsProtocol.parseIndoorBikeData(bytes(0x41, 0x00, 0x64, 0x00))!!

        assertNull(data.speedKmh)
        assertEquals(100, data.powerWatts)
    }

    @Test
    fun `fields after the skipped ones still land, and power is signed`() {
        // Flags 0x03FF: more data (no speed), avg speed, cadence, avg cadence, distance, resistance, power,
        // avg power, energy, heart rate.
        val frame = bytes(
            0xFF, 0x03,
            0x10, 0x27, // avg speed
            0xA0, 0x00, // cadence 80 rpm
            0x9C, 0x00, // avg cadence
            0x01, 0x02, 0x03, // distance
            0x0F, 0x00, // resistance 15
            0xFF, 0xFF, // power -1
            0x64, 0x00, // avg power
            0x01, 0x00, 0x02, 0x00, 0x03, // energy
            0x8C, // heart rate 140
        )
        val data = FtmsProtocol.parseIndoorBikeData(frame)!!

        assertEquals(80.0, data.cadenceRpm!!, 1e-9)
        assertEquals(15, data.resistanceLevel)
        assertEquals(-1, data.powerWatts)
        assertEquals(140, data.heartRateBpm)
    }

    @Test
    fun `a frame shorter than its flags is rejected`() {
        assertNull(FtmsProtocol.parseIndoorBikeData(bytes(0x44, 0x00, 0xB8, 0x0B, 0xB4)))
        assertNull(FtmsProtocol.parseIndoorBikeData(bytes(0x00)))
    }

    @Test
    fun `features read the target settings`() {
        // Machine features anything; targets: bit 2 (resistance) and bit 13 (simulation).
        val both = FtmsProtocol.parseFeatures(bytes(0x00, 0x40, 0x00, 0x00, 0x04, 0x20, 0x00, 0x00))!!
        assertTrue(both.resistanceTarget)
        assertTrue(both.simulation)

        val simOnly = FtmsProtocol.parseFeatures(bytes(0, 0, 0, 0, 0x00, 0x20, 0, 0))!!
        assertFalse(simOnly.resistanceTarget)
        assertTrue(simOnly.simulation)
    }

    @Test
    fun `resistance range reads min, max and step in tenths`() {
        assertEquals(ResistanceRange(0, 1000, 10), FtmsProtocol.parseResistanceRange(bytes(0x00, 0x00, 0xE8, 0x03, 0x0A, 0x00)))
        assertNull(FtmsProtocol.parseResistanceRange(bytes(0x0A, 0x00, 0x0A, 0x00, 0x01, 0x00))) // empty range
    }

    @Test
    fun `percent maps onto the range, on its step`() {
        val range = ResistanceRange(minTenths = 10, maxTenths = 200, stepTenths = 10)

        assertEquals(10, range.tenthsFor(0))
        assertEquals(200, range.tenthsFor(100))
        assertEquals(110, range.tenthsFor(50)) // 105 rounds to the step
        assertEquals(200, range.tenthsFor(150)) // clamped
    }

    @Test
    fun `control point commands`() {
        assertArrayEquals(bytes(0x00), FtmsProtocol.requestControl())
        assertArrayEquals(bytes(0x07), FtmsProtocol.startOrResume())
        assertArrayEquals(bytes(0x04, 0x96), FtmsProtocol.setTargetResistance(150, wide = false))
        assertArrayEquals(bytes(0x04, 0xFF), FtmsProtocol.setTargetResistance(400, wide = false))
        assertArrayEquals(bytes(0x04, 0x90, 0x01), FtmsProtocol.setTargetResistance(400, wide = true))
        // 7.5 % grade = 750 in 0.01 %; Crr 0.004, Cw 0.51.
        assertArrayEquals(bytes(0x11, 0x00, 0x00, 0xEE, 0x02, 0x28, 0x33), FtmsProtocol.setSimulationGrade(7.5))
    }

    @Test
    fun `responses parse, and anything else doesn't`() {
        val ok = FtmsProtocol.parseResponse(bytes(0x80, 0x04, 0x01))!!
        assertEquals(FtmsProtocol.OP_SET_TARGET_RESISTANCE, ok.requestOp)
        assertTrue(ok.succeeded)
        assertEquals(FtmsProtocol.RESULT_INVALID_PARAMETER, FtmsProtocol.parseResponse(bytes(0x80, 0x04, 0x03))!!.result)
        assertNull(FtmsProtocol.parseResponse(bytes(0x04, 0x01, 0x01)))
        assertNull(FtmsProtocol.parseResponse(bytes(0x80, 0x04)))
    }
}
