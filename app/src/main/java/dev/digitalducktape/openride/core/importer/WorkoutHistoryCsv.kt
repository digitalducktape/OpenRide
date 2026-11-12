package dev.digitalducktape.openride.core.importer

import dev.digitalducktape.openride.core.data.Ride
import java.time.DateTimeException
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeParseException
import java.util.Locale
import kotlin.math.roundToInt

/**
 * One past ride read from a workout-history export (#83). The export is a summary per workout,
 * so there is no per-second series and no maximums: an imported ride has its totals and
 * averages only.
 */
data class ImportedWorkout(
    val startEpochMs: Long,
    val durationSec: Int,
    val avgCadence: Int,
    val avgPower: Int,
    val avgResistance: Int,
    val outputKj: Double,
    val calories: Int?,
) {
    /**
     * As a [Ride] for [profileId]. The maximums are 0, which the ride detail reads as "not
     * recorded" (a maximum below its average can't have been measured) and leaves out.
     */
    fun toRide(profileId: Long): Ride = Ride(
        profileId = profileId,
        startEpochMs = startEpochMs,
        durationSec = durationSec,
        avgCadence = avgCadence,
        maxCadence = 0,
        avgPower = avgPower,
        maxPower = 0,
        avgResistance = avgResistance,
        outputKj = outputKj,
        calories = calories,
    )
}

/**
 * What [WorkoutHistoryCsv.parse] made of a file.
 *
 * @param otherWorkouts rows for another discipline (strength, stretching, …), left out: OpenRide's
 *   history is rides.
 * @param unreadableRows cycling rows without a usable date or length.
 */
data class WorkoutHistory(
    val rides: List<ImportedWorkout>,
    val otherWorkouts: Int,
    val unreadableRows: Int,
)

/**
 * Reads the workout-history CSV a Peloton member can download from their profile (#83), by
 * column name, so a reordered or extended export still reads. The columns used:
 *
 * `Workout Timestamp` (`2021-02-07 21:10 (PST)` or `2021-03-02 19:52 (-08)`), `Length (minutes)`,
 * `Fitness Discipline` (only `Cycling` rows become rides), `Total Output` (kJ), `Avg. Watts`,
 * `Avg. Resistance` (`40%`), `Avg. Cadence (RPM)` and `Calories Burned`.
 *
 * Pure text in, values out: no Android, plain-JUnit testable.
 */
object WorkoutHistoryCsv {
    private const val COL_TIMESTAMP = "workout timestamp"
    private const val COL_LENGTH = "length (minutes)"
    private const val COL_DISCIPLINE = "fitness discipline"
    private const val COL_OUTPUT = "total output"
    private const val COL_WATTS = "avg. watts"
    private const val COL_RESISTANCE = "avg. resistance"
    private const val COL_CADENCE = "avg. cadence (rpm)"
    private const val COL_CALORIES = "calories burned"

    /** Without these a file isn't this export at all. */
    private val REQUIRED = listOf(COL_TIMESTAMP, COL_LENGTH, COL_DISCIPLINE)

    private const val CYCLING = "cycling"

    private val TIMESTAMP = Regex("""^(\d{4}-\d{2}-\d{2})[ T](\d{1,2}:\d{2})(?::\d{2})?\s*(?:\(([^)]*)\))?$""")
    private val OFFSET = Regex("""^([+-])(\d{1,2})(?::?(\d{2}))?$""")
    private val LOCAL = DateTimeFormatter.ofPattern("yyyy-MM-dd H:mm", Locale.US)

    /**
     * The zone abbreviations the export writes for older workouts, as fixed offsets in minutes.
     * An abbreviation names the offset in force at that moment (PST or PDT), so each is one offset.
     */
    private val ABBREVIATIONS: Map<String, ZoneOffset> = mapOf(
        "UTC" to 0, "GMT" to 0, "Z" to 0, "WET" to 0,
        "HST" to -600, "AKST" to -540, "AKDT" to -480,
        "PST" to -480, "PDT" to -420, "MST" to -420, "MDT" to -360,
        "CST" to -360, "CDT" to -300, "EST" to -300, "EDT" to -240,
        "AST" to -240, "ADT" to -180, "NST" to -210, "NDT" to -150,
        "BST" to 60, "WEST" to 60, "CET" to 60, "CEST" to 120, "EET" to 120, "EEST" to 180,
        "AWST" to 480, "ACST" to 570, "ACDT" to 630, "AEST" to 600, "AEDT" to 660,
        "NZST" to 720, "NZDT" to 780,
    ).mapValues { ZoneOffset.ofTotalSeconds(it.value * 60) }

    /**
     * Parses [text]. Rows that can't become a ride are counted, not thrown.
     *
     * @param fallbackZone the zone for a timestamp that names none, or one this doesn't know.
     * @throws IllegalArgumentException when [text] isn't a workout-history export (its header
     *   lacks the date, length or discipline column).
     */
    fun parse(text: String, fallbackZone: ZoneId = ZoneId.systemDefault()): WorkoutHistory {
        val rows = parseRows(text.removePrefix("﻿")).filter { row -> row.any { it.isNotBlank() } }
        val header = rows.firstOrNull()?.map { it.trim().lowercase(Locale.US) }.orEmpty()
        require(REQUIRED.all { it in header }) { "not a workout-history CSV" }
        val index = header.withIndex().associate { (i, name) -> name to i }

        val rides = mutableListOf<ImportedWorkout>()
        var other = 0
        var unreadable = 0
        for (row in rows.drop(1)) {
            fun cell(column: String): String = index[column]?.let(row::getOrNull)?.trim().orEmpty()
            if (!cell(COL_DISCIPLINE).equals(CYCLING, ignoreCase = true)) {
                other++
                continue
            }
            val start = parseTimestamp(cell(COL_TIMESTAMP), fallbackZone)
            val outputKj = number(cell(COL_OUTPUT))
            val watts = number(cell(COL_WATTS))
            val durationSec = durationSec(number(cell(COL_LENGTH)), outputKj, watts)
            if (start == null || durationSec == null) {
                unreadable++
                continue
            }
            rides += ImportedWorkout(
                startEpochMs = start,
                durationSec = durationSec,
                avgCadence = number(cell(COL_CADENCE))?.roundToInt() ?: 0,
                avgPower = watts?.roundToInt() ?: 0,
                avgResistance = number(cell(COL_RESISTANCE))?.roundToInt() ?: 0,
                outputKj = outputKj ?: 0.0,
                calories = number(cell(COL_CALORIES))?.roundToInt(),
            )
        }
        return WorkoutHistory(rides = rides, otherWorkouts = other, unreadableRows = unreadable)
    }

    /**
     * The class length; or, for a row without one (a free ride), the time its output took at
     * its average power. `null` when neither gives a positive duration.
     */
    private fun durationSec(lengthMinutes: Double?, outputKj: Double?, watts: Double?): Int? {
        if (lengthMinutes != null && lengthMinutes > 0) return (lengthMinutes * 60).roundToInt()
        if (outputKj != null && outputKj > 0 && watts != null && watts > 0) return (outputKj * 1000 / watts).roundToInt()
        return null
    }

    /** `2021-02-07 21:10 (PST)` as epoch milliseconds, or `null` if it isn't a timestamp. */
    internal fun parseTimestamp(value: String, fallbackZone: ZoneId): Long? {
        val match = TIMESTAMP.matchEntire(value.trim()) ?: return null
        val local = try {
            LocalDateTime.parse("${match.groupValues[1]} ${match.groupValues[2]}", LOCAL)
        } catch (_: DateTimeParseException) {
            return null
        }
        return local.atZone(zone(match.groupValues[3].trim(), fallbackZone)).toInstant().toEpochMilli()
    }

    private fun zone(token: String, fallbackZone: ZoneId): ZoneId {
        if (token.isEmpty()) return fallbackZone
        OFFSET.matchEntire(token)?.let { match ->
            val sign = if (match.groupValues[1] == "-") -1 else 1
            val hours = match.groupValues[2].toInt()
            val minutes = match.groupValues[3].ifEmpty { "0" }.toInt()
            return try {
                ZoneOffset.ofHoursMinutes(sign * hours, sign * minutes)
            } catch (_: DateTimeException) {
                fallbackZone
            }
        }
        ABBREVIATIONS[token.uppercase(Locale.US)]?.let { return it }
        // A region id such as "Europe/London", should an export ever write one.
        return try {
            ZoneId.of(token)
        } catch (_: DateTimeException) {
            fallbackZone
        }
    }

    /** `101`, `15.88` or `40%` as a number; blank or anything else is `null`. */
    private fun number(cell: String): Double? =
        cell.removeSuffix("%").trim().toDoubleOrNull()?.takeIf { it.isFinite() && it >= 0 }

    /** RFC 4180 rows: quoted fields may hold commas, line breaks and doubled quotes. */
    internal fun parseRows(text: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var quoted = false
        var i = 0
        fun endRow() {
            row += field.toString()
            field.setLength(0)
            rows += row
            row = mutableListOf()
        }
        while (i < text.length) {
            val c = text[i]
            when {
                quoted && c == '"' && text.getOrNull(i + 1) == '"' -> {
                    field.append('"')
                    i++
                }
                c == '"' -> quoted = !quoted
                quoted -> field.append(c)
                c == ',' -> {
                    row += field.toString()
                    field.setLength(0)
                }
                c == '\r' -> if (text.getOrNull(i + 1) != '\n') endRow()
                c == '\n' -> endRow()
                else -> field.append(c)
            }
            i++
        }
        if (field.isNotEmpty() || row.isNotEmpty()) endRow()
        return rows
    }
}
