package dev.digitalducktape.openride.core.sensor

import com.onepeloton.affernetservice.BikeData

/**
 * Raw affernet sensor frame -> [BikeMetrics].
 *
 * Shared by both binder paths ([PelotonBikeDataSource] on `IV1Interface`, and
 * [PelotonBikeInterfaceDataSource] on `IBikeInterface`) because they carry the *same* BikeData
 * parcelable — only the interface that delivers it differs by board. Keeping the scaling in one
 * place means a correction here can never apply to one board and not the other.
 *
 * Scaling (all confirmed against grupetto's Gen 2 decode, see docs/SENSOR_PROTOCOL.md):
 *
 * - `cadenceRpm`        = `rpm`                (raw long, already RPM)
 * - `powerWatts`        = `power / 100`        (raw is centi-watts)
 * - `resistancePercent` = `currentResistance`  (raw int, already 0..100)
 * - `speedMph`          = derived from watts via [pelotonSpeedMphFromPower] (the service
 *   reports no speed field; stock Peloton also synthesises it from power)
 */
internal fun BikeData.toBikeMetrics(): BikeMetrics {
    val watts = (power / POWER_SCALE).toInt()
    return BikeMetrics(
        cadenceRpm = rpm.toInt(),
        resistancePercent = currentResistance.coerceIn(0, 100),
        powerWatts = watts,
        speedMph = pelotonSpeedMphFromPower(watts.toDouble()),
    )
}

/** Raw power is centi-watts (watts x 100). */
private const val POWER_SCALE = 100L
