package dev.digitalducktape.openride.core.route

import androidx.test.ext.junit.runners.AndroidJUnit4
import dev.digitalducktape.openride.core.telemetry.GpxImport
import dev.digitalducktape.openride.core.telemetry.GpxPointsBucket
import dev.digitalducktape.openride.core.telemetry.GpxRouteCleared
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.SuccessResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RouteHolderTest {

    private val telemetry = RecordingTelemetry()
    private val holder = RouteHolder(telemetry = telemetry)

    private val gpx = """
        <gpx><trk><name>Secret hill</name><trkseg>
          <trkpt lat="37.8320" lon="-122.4795"><ele>10</ele></trkpt>
          <trkpt lat="37.8330" lon="-122.4795"><ele>30</ele></trkpt>
          <trkpt lat="37.8340" lon="-122.4795"><ele>60</ele></trkpt>
        </trkseg></trk></gpx>
    """.trimIndent()

    @Test
    fun `loading a route reports gpx_import success with a points bucket`() {
        holder.load(gpx.byteInputStream())

        assertEquals(listOf(GpxImport(SuccessResult.SUCCESS, GpxPointsBucket.LT_500)), telemetry.events)
    }

    @Test
    fun `a file with no usable points reports gpx_import failed`() {
        assertNull(holder.load("<gpx></gpx>".byteInputStream()))

        assertEquals(listOf(GpxImport(SuccessResult.FAILED, GpxPointsBucket.LT_500)), telemetry.events)
    }

    @Test
    fun `an unparseable file reports failed and still throws`() {
        val thrown = runCatching { holder.load("not xml at all <<<".byteInputStream()) }

        assertEquals(true, thrown.isFailure)
        assertEquals(listOf(GpxImport(SuccessResult.FAILED, GpxPointsBucket.LT_500)), telemetry.events)
    }

    @Test
    fun `clearing a loaded route reports gpx_route_cleared once`() {
        holder.load(gpx.byteInputStream())
        telemetry.clear()

        holder.clear()
        holder.clear()

        assertEquals(listOf(GpxRouteCleared), telemetry.events)
    }
}
