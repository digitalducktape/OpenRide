package dev.digitalducktape.openride.core.controller

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The OpenBikeControl wire format, against the spec's own examples (PROTOCOL.md, BLE.md, MDNS.md). */
class ObcProtocolTest {
    private fun bytes(vararg values: Int) = ByteArray(values.size) { values[it].toByte() }

    @Test
    fun `decodes a single press`() {
        assertEquals(
            listOf(ObcMessage.ButtonState(listOf(ObcButton(0x01, 0x01)))),
            ObcProtocol.decode(bytes(0x01, 0x01, 0x01)),
        )
    }

    @Test
    fun `decodes several buttons in one message`() {
        assertEquals(
            listOf(ObcMessage.ButtonState(listOf(ObcButton(0x01, 0x01), ObcButton(0x02, 0x00)))),
            ObcProtocol.decode(bytes(0x01, 0x01, 0x01, 0x02, 0x00)),
        )
    }

    @Test
    fun `a dangling odd byte is dropped`() {
        assertEquals(
            listOf(ObcMessage.ButtonState(listOf(ObcButton(0x30, 0x01)))),
            ObcProtocol.decode(bytes(0x01, 0x30, 0x01, 0x31)),
        )
    }

    @Test
    fun `decodes device status, and no battery as null`() {
        assertEquals(listOf(ObcMessage.DeviceStatus(85, connected = true)), ObcProtocol.decode(bytes(0x02, 0x55, 0x01)))
        assertEquals(listOf(ObcMessage.DeviceStatus(null, connected = true)), ObcProtocol.decode(bytes(0x02, 0xFF, 0x01)))
    }

    @Test
    fun `a status run together with a button state, as one TCP read, decodes both`() {
        assertEquals(
            listOf(
                ObcMessage.DeviceStatus(50, connected = true),
                ObcMessage.ButtonState(listOf(ObcButton(0x02, 0x01))),
            ),
            ObcProtocol.decode(bytes(0x02, 0x32, 0x01, 0x01, 0x02, 0x01)),
        )
    }

    @Test
    fun `an unknown or short message decodes to nothing`() {
        assertEquals(emptyList<ObcMessage>(), ObcProtocol.decode(bytes(0x7F, 0x01, 0x01)))
        assertEquals(emptyList<ObcMessage>(), ObcProtocol.decode(bytes(0x02, 0x50)))
        assertEquals(emptyList<ObcMessage>(), ObcProtocol.decode(ByteArray(0)))
    }

    @Test
    fun `steering angle follows the spec's examples`() {
        assertEquals(10.0, ObcProtocol.steeringAngleDegrees(0x94)!!, 0.0)
        assertEquals(-4.5, ObcProtocol.steeringAngleDegrees(0x77)!!, 0.0)
        assertEquals(0.0, ObcProtocol.steeringAngleDegrees(0x80)!!, 0.0)
        assertEquals(63.0, ObcProtocol.steeringAngleDegrees(0xFE)!!, 0.0)
        assertEquals(-63.0, ObcProtocol.steeringAngleDegrees(0x02)!!, 0.0)
        assertNull(ObcProtocol.steeringAngleDegrees(0x00))
        assertNull(ObcProtocol.steeringAngleDegrees(0x01))
        assertNull(ObcProtocol.steeringAngleDegrees(0xFF))
    }

    @Test
    fun `app info matches the spec's example`() {
        val expected = byteArrayOf(0x04, 0x01, 0x05) + "zwift".toByteArray() + byteArrayOf(0x06) + "1.52.0".toByteArray() +
            byteArrayOf(0x04, 0x01, 0x02, 0x10, 0x14)

        assertArrayEquals(expected, ObcProtocol.appInfo("zwift", "1.52.0", listOf(0x01, 0x02, 0x10, 0x14)))
    }

    @Test
    fun `app info cuts long strings to 32 bytes`() {
        val info = ObcProtocol.appInfo("a".repeat(40), "1", emptyList())

        assertEquals(32, info[2].toInt())
        assertEquals(1 + 1 + 1 + 32 + 1 + 1 + 1, info.size)
    }

    @Test
    fun `haptic uses the controller's default duration and intensity`() {
        assertArrayEquals(bytes(0x03, 0x01, 0x00, 0x00), ObcProtocol.haptic(ObcProtocol.HAPTIC_SHORT))
    }
}
