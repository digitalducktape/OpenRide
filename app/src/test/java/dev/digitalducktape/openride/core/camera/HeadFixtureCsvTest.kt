package dev.digitalducktape.openride.core.camera

import java.util.Locale
import org.junit.Assert.assertEquals
import org.junit.Test

class HeadFixtureCsvTest {

    @Test
    fun `rows round-trip with and without a face`() {
        val face = FaceObservation(cx = 0.4688, cy = 0.6271, size = 0.2896, pitchDeg = -6.3, yawDeg = 2.1)
        val rows = listOf(
            HeadFixtureCsv.Row(0L, "easy_centre", face, 82),
            HeadFixtureCsv.Row(33L, "easy_centre", null, 82),
        )
        val text = sequenceOf("# comment", HeadFixtureCsv.HEADER) + rows.map(HeadFixtureCsv::format)
        assertEquals(rows, HeadFixtureCsv.parse(text))
    }

    @Test
    fun `numbers are written with a dot whatever the device locale`() {
        val previous = Locale.getDefault()
        Locale.setDefault(Locale.GERMANY)
        try {
            val line = HeadFixtureCsv.format(
                HeadFixtureCsv.Row(5L, "stand", FaceObservation(0.5, 0.25, 0.3, -1.0, 2.0), 90),
            )
            assertEquals("5,stand,1,0.5000,0.2500,0.3000,-1.0,2.0,90", line)
        } finally {
            Locale.setDefault(previous)
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun `step labels cannot break the CSV`() {
        HeadFixtureCsv.format(HeadFixtureCsv.Row(0L, "lean, left", null, 0))
    }
}
