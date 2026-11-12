package dev.digitalducktape.openride.ui.profile

import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.BikeSource
import dev.digitalducktape.openride.core.sensor.ConnectionState
import org.junit.Assert.assertEquals
import org.junit.Test

class BikeSourceLabelsTest {
    @Test
    fun `the built-in source is the Peloton or the simulation`() {
        assertEquals("Peloton bike", BikeSourceLabels.builtinName(realBike = true))
        assertEquals("Simulated bike", BikeSourceLabels.builtinName(realBike = false))
    }

    @Test
    fun `the profile row names the trainer, or its address`() {
        assertEquals("Peloton bike", BikeSourceLabels.profileRow(BikeSource.Builtin, realBike = true))
        assertEquals("Smart trainer: KICKR", BikeSourceLabels.profileRow(BikeSource.Trainer("AA:BB", "KICKR"), realBike = true))
        assertEquals("Smart trainer: AA:BB", BikeSourceLabels.profileRow(BikeSource.Trainer("AA:BB", null), realBike = true))
    }

    @Test
    fun `a connected trainer shows its numbers and whether OpenRide sets its resistance`() {
        val metrics = BikeMetrics(cadenceRpm = 88, resistancePercent = 35, powerWatts = 182, speedMph = 18.0)

        assertEquals(
            "Connected  •  182 W  •  88 rpm  •  OpenRide sets the resistance",
            BikeSourceLabels.trainerStatus(ConnectionState.Connected, metrics, adjustable = true),
        )
        assertEquals("Reconnecting…", BikeSourceLabels.trainerStatus(ConnectionState.Disconnected, metrics, adjustable = false))
    }
}
