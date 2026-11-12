package dev.digitalducktape.openride.ui.ride

import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.data.RideSample
import dev.digitalducktape.openride.ui.common.TimeFormat

/**
 * The metric tabs on the ride detail screen (v2 metrics spec, after the original bike UI's
 * per-ride view): each tab selects which per-second series the graph draws and which
 * headline stats sit above it. Pure logic — kept out of the composables so it's plain-JUnit
 * testable.
 */
enum class RideMetric(val label: String) {
    Output("OUTPUT"),
    Cadence("CADENCE"),
    Resistance("RESISTANCE"),
    HeartRate("HEART RATE");

    /** This metric's value in one per-second sample, or `null` where it wasn't recorded. */
    fun valueAt(sample: RideSample): Int? = when (this) {
        Output -> sample.power
        Cadence -> sample.cadence
        Resistance -> sample.resistance
        HeartRate -> sample.heartRateBpm
    }

    companion object {
        /** Tabs to offer for a ride: heart rate only appears when the ride recorded any. */
        fun available(samples: List<RideSample>): List<RideMetric> = buildList {
            add(Output)
            add(Cadence)
            add(Resistance)
            if (samples.any { it.heartRateBpm != null }) add(HeartRate)
        }
    }
}

/** One headline stat above the graph ("AVG OUTPUT" / "188" / "WATTS"). */
data class MetricStat(val label: String, val value: String, val unit: String)

object RideMetricStats {

    /** The (tSec, value) series the graph draws for [metric], skipping unrecorded seconds. */
    fun points(metric: RideMetric, samples: List<RideSample>): List<Pair<Int, Int>> =
        samples.mapNotNull { sample -> metric.valueAt(sample)?.let { sample.tSec to it } }

    /**
     * Headline stats for [metric]. Output/cadence/resistance come from the ride's persisted
     * aggregates (exactly what the summary always showed); heart-rate stats are derived from
     * the samples since the ride row doesn't aggregate HR. Resistance has no max aggregate —
     * it shows avg only, same honesty rule as the in-ride bar. A ride imported from another
     * service's history (#83) has no maximums either: its row holds 0, and a maximum below its
     * average can't have been measured, so that stat is left out rather than shown as 0.
     */
    fun stats(metric: RideMetric, ride: Ride, samples: List<RideSample>): List<MetricStat> = when (metric) {
        RideMetric.Output -> listOfNotNull(
            MetricStat("TOTAL OUTPUT", "%.0f".format(ride.outputKj), "KJ"),
            MetricStat("AVG OUTPUT", "${ride.avgPower}", "WATTS"),
            MetricStat("MAX OUTPUT", "${ride.maxPower}", "WATTS").takeIf { ride.maxPower >= ride.avgPower },
        )
        RideMetric.Cadence -> listOfNotNull(
            MetricStat("AVG CADENCE", "${ride.avgCadence}", "RPM"),
            MetricStat("MAX CADENCE", "${ride.maxCadence}", "RPM").takeIf { ride.maxCadence >= ride.avgCadence },
        )
        RideMetric.Resistance -> listOf(
            MetricStat("AVG RESISTANCE", "${ride.avgResistance}", "PERCENT"),
        )
        RideMetric.HeartRate -> {
            val bpm = samples.mapNotNull { it.heartRateBpm }
            if (bpm.isEmpty()) {
                emptyList()
            } else {
                listOf(
                    MetricStat("AVG HEART RATE", "${bpm.sum() / bpm.size}", "BPM"),
                    MetricStat("MAX HEART RATE", "${bpm.max()}", "BPM"),
                )
            }
        }
    }

    /** "Duration · date" header line for the detail screen. */
    fun headerLine(ride: Ride): String = TimeFormat.elapsed(ride.durationSec)
}
