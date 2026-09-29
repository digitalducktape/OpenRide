package dev.digitalducktape.openride.core.camera

import java.time.LocalDateTime
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HeadCalibrationTest {

    private val zone = ZoneId.of("America/Los_Angeles")
    private fun epochMs(text: String) = LocalDateTime.parse(text).atZone(zone).toInstant().toEpochMilli()

    private val leanOnly = HeadCalibration(leftDx = -0.16, rightDx = 0.18, calibratedAtEpochMs = 1_790_000_000_000L)
    private val withDepth = leanOnly.copy(inRatio = 1.22, backRatio = 0.86)

    @Test
    fun `JSON round-trips lean-only and depth calibrations`() {
        assertEquals(leanOnly, HeadCalibration.fromJson(leanOnly.toJson()))
        assertEquals(withDepth, HeadCalibration.fromJson(withDepth.toJson()))
    }

    @Test
    fun `JSON carries a schema version`() {
        assertTrue(leanOnly.toJson().contains("\"version\":1"))
    }

    @Test
    fun `missing or malformed JSON reads as no calibration`() {
        assertNull(HeadCalibration.fromJson(null))
        assertNull(HeadCalibration.fromJson(""))
        assertNull(HeadCalibration.fromJson("{not json"))
        assertNull(HeadCalibration.fromJson("{\"version\":1}"))
    }

    @Test
    fun `a newer schema version is ignored rather than misread`() {
        val future = leanOnly.toJson().replace("\"version\":1", "\"version\":2")
        assertNull(HeadCalibration.fromJson(future))
    }

    @Test
    fun `unknown fields from a later build are tolerated`() {
        val extra = leanOnly.toJson().dropLast(1) + ",\"somethingNew\":3}"
        assertEquals(leanOnly, HeadCalibration.fromJson(extra))
    }

    @Test
    fun `extremes are fresh for the rest of the same local day`() {
        val c = leanOnly.copy(calibratedAtEpochMs = epochMs("2026-09-27T07:30:00"))
        assertTrue(c.isFreshAt(epochMs("2026-09-27T23:59:00"), zone))
        assertFalse(c.isFreshAt(epochMs("2026-09-28T00:01:00"), zone))
        assertFalse(c.isFreshAt(epochMs("2026-09-26T23:00:00"), zone))
    }

    @Test
    fun `lean extremes cover lean_x and lean_stand but only depth extremes cover lean_2d`() {
        assertTrue(leanOnly.covers(TrackerMode.LEAN_X))
        assertTrue(leanOnly.covers(TrackerMode.LEAN_STAND))
        assertFalse(leanOnly.covers(TrackerMode.LEAN_2D))
        assertTrue(withDepth.covers(TrackerMode.LEAN_2D))
    }

    @Test
    fun `the in-memory store keeps one calibration per profile`() = runTest {
        val store = InMemoryHeadCalibrationStore()
        assertNull(store.load(1L))
        store.save(1L, leanOnly)
        store.save(2L, withDepth)
        assertEquals(leanOnly, store.load(1L))
        assertEquals(withDepth, store.load(2L))
        store.save(1L, withDepth)
        assertEquals(withDepth, store.load(1L))
    }
}
