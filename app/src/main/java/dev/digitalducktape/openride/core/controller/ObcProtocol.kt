package dev.digitalducktape.openride.core.controller

import java.util.UUID

/**
 * The OpenBikeControl wire format (issue #68), reimplemented from the public, MIT-licensed spec
 * at https://github.com/OpenBikeControl/openbikecontrol-protocol (PROTOCOL.md, BLE.md, MDNS.md).
 * BLE and mDNS/TCP carry the same bytes, each message led by its type:
 *
 * - `0x01` button state, controller to app: `[0x01, id, state, id, state, ...]`
 * - `0x02` device status, controller to app (TCP only): `[0x02, battery, connected]`
 * - `0x03` haptic feedback, app to controller: `[0x03, pattern, duration, intensity]`
 * - `0x04` app information, app to controller: who we are and which button ids we act on
 *
 * Pure functions only, so all of it is unit-tested on the JVM (`ObcProtocolTest`).
 */
object ObcProtocol {
    val SERVICE_UUID: UUID = UUID.fromString("d273f680-d548-419d-b9d1-fa0472345229")
    val BUTTON_STATE_UUID: UUID = UUID.fromString("d273f681-d548-419d-b9d1-fa0472345229")
    val HAPTIC_UUID: UUID = UUID.fromString("d273f682-d548-419d-b9d1-fa0472345229")
    val APP_INFO_UUID: UUID = UUID.fromString("d273f683-d548-419d-b9d1-fa0472345229")

    /** The mDNS service type, in the form Android's `NsdManager` takes. */
    const val MDNS_SERVICE_TYPE = "_openbikecontrol._tcp."

    const val TYPE_BUTTON_STATE = 0x01
    const val TYPE_DEVICE_STATUS = 0x02
    const val TYPE_HAPTIC = 0x03
    const val TYPE_APP_INFO = 0x04

    /** Standard button ids (PROTOCOL.md, Button Mapping). Only the ones OpenRide acts on. */
    object Button {
        const val SHIFT_UP = 0x01
        const val SHIFT_DOWN = 0x02
        const val STEER_LEFT = 0x18
        const val STEER_RIGHT = 0x19
        const val STEERING_ANGLE = 0x1B
        const val INCREASE_DIFFICULTY = 0x30
        const val DECREASE_DIFFICULTY = 0x31
        const val PAUSE = 0x33
        const val RESUME = 0x34
        const val POWER_UP_1 = 0x50
        const val POWER_UP_2 = 0x51
        const val POWER_UP_3 = 0x52
    }

    /** Button state values. Anything from `0x02` up is an analog value. */
    const val RELEASED = 0x00
    const val PRESSED = 0x01

    /** Haptic patterns (BLE.md). */
    const val HAPTIC_SHORT = 0x01
    const val HAPTIC_WARNING = 0x06

    /** Steering angle: `0x80` is straight ahead, each step half a degree, clamped to ±63°. */
    private const val ANGLE_CENTRE = 0x80
    private const val ANGLE_MIN = 0x02
    private const val ANGLE_MAX = 0xFE

    /** Device status is always 3 bytes. */
    private const val DEVICE_STATUS_SIZE = 3

    /** App id and version are each at most 32 bytes on the wire. */
    private const val MAX_STRING_BYTES = 32

    /**
     * Decodes one read's worth of bytes: one BLE notification, or what one TCP read returned.
     * TCP may run several messages together. A button state message has no length field and
     * takes the rest of the buffer, as the spec's reference reader does; a device status is a
     * fixed 3 bytes, so whatever follows it is decoded too. An unknown type ends the buffer,
     * since its length can't be known.
     */
    fun decode(bytes: ByteArray): List<ObcMessage> {
        val messages = mutableListOf<ObcMessage>()
        var i = 0
        while (i < bytes.size) {
            when (bytes[i].toInt() and 0xFF) {
                TYPE_BUTTON_STATE -> {
                    val buttons = mutableListOf<ObcButton>()
                    var j = i + 1
                    while (j + 1 < bytes.size) {
                        buttons += ObcButton(id = bytes[j].toInt() and 0xFF, state = bytes[j + 1].toInt() and 0xFF)
                        j += 2
                    }
                    messages += ObcMessage.ButtonState(buttons)
                    return messages
                }
                TYPE_DEVICE_STATUS -> {
                    if (i + DEVICE_STATUS_SIZE > bytes.size) return messages
                    val battery = bytes[i + 1].toInt() and 0xFF
                    messages += ObcMessage.DeviceStatus(
                        batteryPercent = battery.takeIf { it <= 100 },
                        connected = (bytes[i + 2].toInt() and 0xFF) == 0x01,
                    )
                    i += DEVICE_STATUS_SIZE
                }
                else -> return messages
            }
        }
        return messages
    }

    /**
     * The steering angle in degrees (right positive) for a `0x1B` state, or `null` when the
     * controller has no angle (`0x00`: not calibrated or sensor lost) or sent a no-op value.
     */
    fun steeringAngleDegrees(state: Int): Double? =
        if (state < ANGLE_MIN || state > ANGLE_MAX) null else (state - ANGLE_CENTRE) * 0.5

    /**
     * The App Information message: [appId] and [appVersion] (UTF-8, cut to 32 bytes each) and
     * the button ids OpenRide acts on, so a controller can show or remap them.
     */
    fun appInfo(appId: String, appVersion: String, buttonIds: Collection<Int>): ByteArray {
        val id = appId.toByteArray(Charsets.UTF_8).take(MAX_STRING_BYTES)
        val version = appVersion.toByteArray(Charsets.UTF_8).take(MAX_STRING_BYTES)
        val buttons = buttonIds.distinct().take(255)
        return buildList {
            add(TYPE_APP_INFO.toByte())
            add(0x01) // format version
            add(id.size.toByte())
            addAll(id)
            add(version.size.toByte())
            addAll(version)
            add(buttons.size.toByte())
            buttons.forEach { add(it.toByte()) }
        }.toByteArray()
    }

    /** A haptic feedback command, with the controller's default duration and intensity. */
    fun haptic(pattern: Int): ByteArray = byteArrayOf(TYPE_HAPTIC.toByte(), pattern.toByte(), 0, 0)
}

/** One `(button id, state)` pair of a button state message. */
data class ObcButton(val id: Int, val state: Int)

sealed interface ObcMessage {
    /** The buttons whose state changed, all in one message (several ids may be one press). */
    data class ButtonState(val buttons: List<ObcButton>) : ObcMessage

    /** @param batteryPercent 0-100, or `null` for a controller without a battery. */
    data class DeviceStatus(val batteryPercent: Int?, val connected: Boolean) : ObcMessage
}
