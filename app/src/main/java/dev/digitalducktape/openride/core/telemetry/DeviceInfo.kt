package dev.digitalducktape.openride.core.telemetry

/** `ro.product.model` of the two supported bike tablets (docs/DEVICE.md); anything else is [Tablet.OTHER]. */
fun tabletOf(model: String): Tablet = when (model) {
    "PLTN-RB1VQ" -> Tablet.BIKE
    "PLTN-TTR01" -> Tablet.BIKE_PLUS
    else -> Tablet.OTHER
}

/** `Build.DISPLAY` against the allow-list in [Firmware]; an unknown build is [Firmware.OTHER]. */
fun firmwareOf(display: String): Firmware = Firmware.of(display)

fun flavorOf(realSensor: Boolean): Flavor = if (realSensor) Flavor.REAL else Flavor.MOCK
