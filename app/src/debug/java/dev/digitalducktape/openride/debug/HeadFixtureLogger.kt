package dev.digitalducktape.openride.debug

import dev.digitalducktape.openride.core.camera.FaceObservation
import dev.digitalducktape.openride.core.camera.HeadFixtureCsv
import java.io.BufferedWriter
import java.io.File

/**
 * Debug builds only: records head-tracker fixtures on the bike as [HeadFixtureCsv] — the face
 * box and angles per frame plus cadence, **never images**. Pull one with
 * `adb exec-out run-as <pkg> cat files/headtracker/<name>.csv` and drop it in
 * `app/src/test/resources/headtracker/` to tune against it.
 */
class HeadFixtureLogger(directory: File, private val cadenceRpm: () -> Int) {
    val file: File = File(directory.apply { mkdirs() }, "fixture_${System.currentTimeMillis()}.csv")
    private val writer: BufferedWriter = file.bufferedWriter()
    private var firstTimestampMs: Long? = null

    /** The prompt the rider is following right now (a plain word such as `lean_left`). */
    @Volatile var step: String = "idle"

    init {
        writer.write("# OpenRide head-tracker fixture (numbers only, never images). Recorded by the debug build.\n")
        writer.write(HeadFixtureCsv.HEADER + "\n")
    }

    @Synchronized
    fun record(timestampMs: Long, face: FaceObservation?) {
        val start = firstTimestampMs ?: timestampMs.also { firstTimestampMs = it }
        writer.write(HeadFixtureCsv.format(HeadFixtureCsv.Row(timestampMs - start, step, face, cadenceRpm())))
        writer.write("\n")
    }

    @Synchronized
    fun flush() = writer.flush()

    @Synchronized
    fun close() = writer.close()
}
