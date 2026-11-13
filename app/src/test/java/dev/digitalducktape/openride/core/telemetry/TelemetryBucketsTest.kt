package dev.digitalducktape.openride.core.telemetry

import org.junit.Assert.assertEquals
import org.junit.Test

class TelemetryBucketsTest {
    @Test
    fun rideDurationEdgesAreHalfOpen() {
        assertEquals("<5m", TelemetryBuckets.rideDuration(0).wire)
        assertEquals("<5m", TelemetryBuckets.rideDuration(299).wire)
        assertEquals("5–15m", TelemetryBuckets.rideDuration(300).wire)
        assertEquals("5–15m", TelemetryBuckets.rideDuration(899).wire)
        assertEquals("15–30m", TelemetryBuckets.rideDuration(900).wire)
        assertEquals("15–30m", TelemetryBuckets.rideDuration(1799).wire)
        assertEquals("30–45m", TelemetryBuckets.rideDuration(1800).wire)
        assertEquals("30–45m", TelemetryBuckets.rideDuration(2699).wire)
        assertEquals("45–60m", TelemetryBuckets.rideDuration(2700).wire)
        assertEquals("45–60m", TelemetryBuckets.rideDuration(3599).wire)
        assertEquals("60m+", TelemetryBuckets.rideDuration(3600).wire)
        assertEquals("<5m", TelemetryBuckets.rideDuration(-5).wire)
    }

    @Test
    fun gamePlayedEdges() {
        assertEquals("<1m", TelemetryBuckets.gamePlayed(59).wire)
        assertEquals("1–3m", TelemetryBuckets.gamePlayed(60).wire)
        assertEquals("1–3m", TelemetryBuckets.gamePlayed(179).wire)
        assertEquals("3–5m", TelemetryBuckets.gamePlayed(180).wire)
        assertEquals("3–5m", TelemetryBuckets.gamePlayed(299).wire)
        assertEquals("5–10m", TelemetryBuckets.gamePlayed(300).wire)
        assertEquals("5–10m", TelemetryBuckets.gamePlayed(599).wire)
        assertEquals("10m+", TelemetryBuckets.gamePlayed(600).wire)
    }

    @Test
    fun profilesClampsToOne() {
        assertEquals("1", TelemetryBuckets.profiles(0).wire)
        assertEquals("1", TelemetryBuckets.profiles(1).wire)
        assertEquals("2", TelemetryBuckets.profiles(2).wire)
        assertEquals("3+", TelemetryBuckets.profiles(3).wire)
        assertEquals("3+", TelemetryBuckets.profiles(9).wire)
    }

    @Test
    fun hrDropsEdges() {
        assertEquals("0", TelemetryBuckets.hrDrops(0).wire)
        assertEquals("1", TelemetryBuckets.hrDrops(1).wire)
        assertEquals("2–5", TelemetryBuckets.hrDrops(2).wire)
        assertEquals("2–5", TelemetryBuckets.hrDrops(5).wire)
        assertEquals("6+", TelemetryBuckets.hrDrops(6).wire)
        assertEquals("0", TelemetryBuckets.hrDrops(-1).wire)
    }

    @Test
    fun gamesPlayedEdges() {
        listOf(0, 1, 2, 3, 4).forEach { assertEquals("$it", TelemetryBuckets.gamesPlayed(it).wire) }
        assertEquals("5+", TelemetryBuckets.gamesPlayed(5).wire)
        assertEquals("5+", TelemetryBuckets.gamesPlayed(40).wire)
    }

    @Test
    fun importedEdges() {
        assertEquals("0", TelemetryBuckets.imported(0).wire)
        assertEquals("1–10", TelemetryBuckets.imported(1).wire)
        assertEquals("1–10", TelemetryBuckets.imported(10).wire)
        assertEquals("11–50", TelemetryBuckets.imported(11).wire)
        assertEquals("11–50", TelemetryBuckets.imported(50).wire)
        assertEquals("51–200", TelemetryBuckets.imported(51).wire)
        assertEquals("51–200", TelemetryBuckets.imported(200).wire)
        assertEquals("200+", TelemetryBuckets.imported(201).wire)
    }

    @Test
    fun gpxPointsEdges() {
        assertEquals("<500", TelemetryBuckets.gpxPoints(499).wire)
        assertEquals("500–2k", TelemetryBuckets.gpxPoints(500).wire)
        assertEquals("500–2k", TelemetryBuckets.gpxPoints(1999).wire)
        assertEquals("2k–10k", TelemetryBuckets.gpxPoints(2000).wire)
        assertEquals("2k–10k", TelemetryBuckets.gpxPoints(9999).wire)
        assertEquals("10k+", TelemetryBuckets.gpxPoints(10000).wire)
    }
}
