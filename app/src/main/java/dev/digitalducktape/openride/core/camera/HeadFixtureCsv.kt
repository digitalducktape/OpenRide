package dev.digitalducktape.openride.core.camera

import java.util.Locale

/**
 * The head tracker's fixture format: one row per analysed camera frame, **numbers only** — the
 * face box and angles, never pixels. Written on the bike by the debug build's fixture logger and
 * read back by the unit tests, so tuning is checked against real riding.
 *
 * Columns: `t_ms` (monotonic, from the start of the recording), `step` (the prompt the rider was
 * following, e.g. `lean_left`), `face` (1/0), `cx`, `cy`, `size`, `pitch`, `yaw` (empty when there
 * is no face), `cadence` (rpm). Lines starting with `#` are comments.
 */
object HeadFixtureCsv {
    const val HEADER = "t_ms,step,face,cx,cy,size,pitch,yaw,cadence"

    data class Row(val timestampMs: Long, val step: String, val face: FaceObservation?, val cadenceRpm: Int)

    fun format(row: Row): String {
        require(row.step.none { it == ',' || it == '\n' || it == '"' }) { "step labels are plain words: ${row.step}" }
        val face = row.face
        val faceColumns = if (face == null) {
            "0,,,,,"
        } else {
            String.format(
                Locale.US,
                "1,%.4f,%.4f,%.4f,%.1f,%.1f",
                face.cx, face.cy, face.size, face.pitchDeg, face.yawDeg,
            )
        }
        return "${row.timestampMs},${row.step},$faceColumns,${row.cadenceRpm}"
    }

    fun parse(lines: Sequence<String>): List<Row> = lines
        .map { it.trim() }
        .filter { it.isNotEmpty() && !it.startsWith("#") && it != HEADER }
        .map { line ->
            val c = line.split(',')
            require(c.size == 9) { "expected 9 columns: $line" }
            val face = if (c[2] == "1") {
                FaceObservation(
                    cx = c[3].toDouble(),
                    cy = c[4].toDouble(),
                    size = c[5].toDouble(),
                    pitchDeg = c[6].toDouble(),
                    yawDeg = c[7].toDouble(),
                )
            } else {
                null
            }
            Row(timestampMs = c[0].toLong(), step = c[1], face = face, cadenceRpm = c[8].toInt())
        }
        .toList()
}
