package dev.digitalducktape.openride.core.importer

import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test

/** The header and row shapes are the export's own (issue #83's sample); the people are made up. */
class WorkoutHistoryCsvTest {

    private val header =
        "Workout Timestamp,Live/On-Demand,Instructor Name,Length (minutes),Fitness Discipline,Type,Title," +
            "Class Timestamp,Total Output,Avg. Watts,Avg. Resistance,Avg. Cadence (RPM),Avg. Speed (mph)," +
            "Distance (mi),Calories Burned,Avg. Heartrate,Avg. Incline,Avg. Pace (min/mi)"

    private val cycling =
        "2021-02-07 21:10 (PST),On Demand,Sam Example,20,Cycling,Beginner,20 min Beginner Ride," +
            "2019-03-21 23:11 (PST),122,101,40%,75,15.88,5.29,165,,,"
    private val stretching =
        "2021-03-02 19:52 (-08),On Demand,Alex Example,5,Stretching,Pre & Post-Ride Stretch,5 min Post-Ride Stretch," +
            "2021-02-26 06:00 (-08),,,,,,,13,,,"
    private val strength =
        "2021-04-12 14:16 (-07),On Demand,Robin O'Example,10,Strength,Arms & Light Weights,10 min Arms & Light Weights," +
            "2021-03-22 17:07 (-07),,,,,,,54,,,"

    private val utc = ZoneOffset.UTC

    private fun epoch(iso: String) = Instant.parse(iso).toEpochMilli()

    @Test
    fun `a cycling row becomes a ride with its totals and averages`() {
        val history = WorkoutHistoryCsv.parse(listOf(header, cycling).joinToString("\n"), utc)

        assertEquals(
            listOf(
                ImportedWorkout(
                    startEpochMs = epoch("2021-02-08T05:10:00Z"),
                    durationSec = 1200,
                    avgCadence = 75,
                    avgPower = 101,
                    avgResistance = 40,
                    outputKj = 122.0,
                    calories = 165,
                ),
            ),
            history.rides,
        )
        assertEquals(0, history.otherWorkouts)
        assertEquals(0, history.unreadableRows)
    }

    @Test
    fun `other disciplines are counted and left out`() {
        val history = WorkoutHistoryCsv.parse(listOf(header, cycling, stretching, strength).joinToString("\r\n") + "\r\n", utc)

        assertEquals(1, history.rides.size)
        assertEquals(2, history.otherWorkouts)
    }

    @Test
    fun `columns are found by name, in any order, whatever the case`() {
        val csv = """
            Fitness Discipline,TOTAL OUTPUT,workout timestamp,Length (minutes),Something New
            Cycling,250,2026-10-01 07:30 (-07),30,x
        """.trimIndent()

        val ride = WorkoutHistoryCsv.parse(csv, utc).rides.single()

        assertEquals(epoch("2026-10-01T14:30:00Z"), ride.startEpochMs)
        assertEquals(1800, ride.durationSec)
        assertEquals(250.0, ride.outputKj, 0.0)
        assertEquals(0, ride.avgPower)
        assertNull(ride.calories)
    }

    @Test
    fun `quoted fields may hold commas, quotes and line breaks`() {
        val row = "2021-02-07 21:10 (EST),On Demand,\"Example, Sam\",30,Cycling,Theme," +
            "\"30 min \"\"Climb, Sprint\"\"\nRide\",2019-03-21 23:11 (EST),300,166,45%,80,17,8.5,310,,,"

        val history = WorkoutHistoryCsv.parse("﻿$header\n$row\n", utc)

        assertEquals(epoch("2021-02-08T02:10:00Z"), history.rides.single().startEpochMs)
        assertEquals(300.0, history.rides.single().outputKj, 0.0)
        assertEquals(0, history.otherWorkouts + history.unreadableRows)
    }

    @Test
    fun `timestamps read abbreviations, numeric offsets and no zone at all`() {
        val tokyo = ZoneId.of("Asia/Tokyo")
        fun at(value: String) = WorkoutHistoryCsv.parseTimestamp(value, tokyo)

        assertEquals(epoch("2021-07-01T16:00:00Z"), at("2021-07-01 09:00 (PDT)"))
        assertEquals(epoch("2021-07-01T16:00:00Z"), at("2021-07-01 09:00 (-07)"))
        assertEquals(epoch("2021-07-01T03:30:00Z"), at("2021-07-01 09:00 (+05:30)"))
        assertEquals(epoch("2021-07-01T03:30:00Z"), at("2021-07-01 09:00 (+0530)"))
        assertEquals(epoch("2021-07-01T08:00:00Z"), at("2021-07-01 09:00 (BST)"))
        // No zone, or one nobody knows: the bike's own.
        assertEquals(epoch("2021-07-01T00:00:00Z"), at("2021-07-01 09:00"))
        assertEquals(epoch("2021-07-01T00:00:00Z"), at("2021-07-01 09:00 (XYZT)"))
        assertNull(at("yesterday"))
        assertNull(at("2021-13-40 09:00 (PST)"))
    }

    @Test
    fun `a ride without a class length takes the time its output took`() {
        val csv = "$header\n2022-01-01 08:00 (UTC),,,,Cycling,Just Ride,Just Ride,,180,150,35%,80,16,6,200,,,"

        assertEquals(1200, WorkoutHistoryCsv.parse(csv, utc).rides.single().durationSec)
    }

    @Test
    fun `cycling rows without a date or any length are counted as unreadable`() {
        val csv = listOf(
            header,
            ",On Demand,Sam Example,20,Cycling,Beginner,Ride,,122,101,40%,75,15.88,5.29,165,,,",
            "2022-01-01 08:00 (UTC),,,,Cycling,Just Ride,Just Ride,,,,,,,,,,,",
            cycling,
        ).joinToString("\n")

        val history = WorkoutHistoryCsv.parse(csv, utc)

        assertEquals(1, history.rides.size)
        assertEquals(2, history.unreadableRows)
    }

    @Test
    fun `a file that isn't the export is refused`() {
        assertThrows(IllegalArgumentException::class.java) { WorkoutHistoryCsv.parse("date,duration_sec\n2021-01-01,60\n", utc) }
        assertThrows(IllegalArgumentException::class.java) { WorkoutHistoryCsv.parse("", utc) }
        assertThrows(IllegalArgumentException::class.java) { WorkoutHistoryCsv.parse("{\"profiles\": []}", utc) }
    }

    @Test
    fun `an export with only its header has no rides`() {
        assertEquals(WorkoutHistory(emptyList(), 0, 0), WorkoutHistoryCsv.parse("$header\n", utc))
    }

    @Test
    fun `an imported ride has no maximums`() {
        val ride = WorkoutHistoryCsv.parse("$header\n$cycling", utc).rides.single().toRide(profileId = 7)

        assertEquals(7, ride.profileId)
        assertEquals(101, ride.avgPower)
        assertEquals(0, ride.maxPower)
        assertEquals(0, ride.maxCadence)
        assertNull(ride.videoId)
    }
}
