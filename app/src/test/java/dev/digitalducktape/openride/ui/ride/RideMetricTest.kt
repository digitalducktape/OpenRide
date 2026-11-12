package dev.digitalducktape.openride.ui.ride

import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideSample
import org.junit.Assert.assertEquals
import org.junit.Test

class RideMetricTest {

    private val ride = Ride(
        id = 1,
        profileId = 1,
        startEpochMs = 0,
        durationSec = 600,
        avgCadence = 72,
        maxCadence = 95,
        avgPower = 188,
        maxPower = 437,
        avgResistance = 42,
        outputKj = 503.4,
        calories = null,
    )

    private fun sample(tSec: Int, power: Int = 100, hr: Int? = null) =
        RideSample(rideId = 1, tSec = tSec, cadence = 70, resistance = 40, power = power, heartRateBpm = hr)

    @Test
    fun `heart rate tab only offered when a ride recorded any`() {
        val without = listOf(sample(0), sample(1))
        val with = listOf(sample(0), sample(1, hr = 140))

        assertEquals(
            listOf(RideMetric.Output, RideMetric.Cadence, RideMetric.Resistance),
            RideMetric.available(without),
        )
        assertEquals(
            listOf(RideMetric.Output, RideMetric.Cadence, RideMetric.Resistance, RideMetric.HeartRate),
            RideMetric.available(with),
        )
    }

    @Test
    fun `heart rate points skip seconds without a reading`() {
        val samples = listOf(sample(0, hr = 130), sample(1), sample(2, hr = 150))

        assertEquals(listOf(0 to 130, 2 to 150), RideMetricStats.points(RideMetric.HeartRate, samples))
    }

    @Test
    fun `output stats come from the ride's persisted aggregates`() {
        val stats = RideMetricStats.stats(RideMetric.Output, ride, emptyList())

        assertEquals(
            listOf(
                MetricStat("TOTAL OUTPUT", "503", "KJ"),
                MetricStat("AVG OUTPUT", "188", "WATTS"),
                MetricStat("MAX OUTPUT", "437", "WATTS"),
            ),
            stats,
        )
    }

    @Test
    fun `resistance shows avg only`() {
        assertEquals(
            listOf(MetricStat("AVG RESISTANCE", "42", "PERCENT")),
            RideMetricStats.stats(RideMetric.Resistance, ride, emptyList()),
        )
    }

    @Test
    fun `heart rate stats derive from samples`() {
        val samples = listOf(sample(0, hr = 130), sample(1), sample(2, hr = 150))

        assertEquals(
            listOf(
                MetricStat("AVG HEART RATE", "140", "BPM"),
                MetricStat("MAX HEART RATE", "150", "BPM"),
            ),
            RideMetricStats.stats(RideMetric.HeartRate, ride, samples),
        )
    }

    @Test
    fun `a ride without maximums, as an imported one is, shows no max stats`() {
        val imported = ride.copy(maxPower = 0, maxCadence = 0)

        assertEquals(
            listOf("TOTAL OUTPUT", "AVG OUTPUT"),
            RideMetricStats.stats(RideMetric.Output, imported, emptyList()).map { it.label },
        )
        assertEquals(
            listOf("AVG CADENCE"),
            RideMetricStats.stats(RideMetric.Cadence, imported, emptyList()).map { it.label },
        )
    }
}
