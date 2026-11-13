package dev.digitalducktape.openride.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Test

class DeviceInfoTest {
    @Test fun tabletOfKnownModels() {
        assertEquals(Tablet.BIKE, tabletOf("PLTN-RB1VQ"))
        assertEquals(Tablet.BIKE_PLUS, tabletOf("PLTN-TTR01"))
    }

    @Test fun tabletOfUnknownIsOther() {
        assertEquals(Tablet.OTHER, tabletOf("SM-T500"))
    }

    @Test fun firmwareOfKnownAndUnknown() {
        assertEquals(Firmware.RQ_250113_A, firmwareOf("RQ.250113.A"))
        assertEquals(Firmware.QT_250804_A, firmwareOf("QT.250804.A"))
        assertEquals(Firmware.OTHER, firmwareOf("XQ.999999.Z"))
    }

    @Test fun flavorOf() {
        assertEquals(Flavor.REAL, flavorOf(true))
        assertEquals(Flavor.MOCK, flavorOf(false))
    }
}
