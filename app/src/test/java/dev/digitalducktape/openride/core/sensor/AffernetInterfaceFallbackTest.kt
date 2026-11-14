package dev.digitalducktape.openride.core.sensor

import android.os.Looper
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.onepeloton.affernetservice.BikeData
import com.onepeloton.affernetservice.IBikeCallback
import com.onepeloton.affernetservice.IBikeInterface
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import org.robolectric.shadows.ShadowLog
import java.time.Duration

/**
 * Interface fallback (#63) through the *real* binder sources: [AffernetBikeDataSource] over a
 * [PelotonBikeDataSource] and a [PelotonBikeInterfaceDataSource], each bound through its own
 * [RecordingBindContext] so a test plays the system's part — a null binding, a bind that throws,
 * a live binder that pushes frames.
 *
 * [AffernetBikeDataSourceTest] covers the arbitration with plain fakes; this covers what only the
 * real sources can show: that a denial becomes a [BoundBikeDataSource.bindFailure], that the
 * denied binding's retries stop once the other interface wins (no leaked ServiceConnection), and
 * that the failure is logged once rather than on every retry.
 */
@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(AndroidJUnit4::class)
class AffernetInterfaceFallbackTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    private class FakeBikeService : IBikeInterface.Stub() {
        val registered = mutableListOf<IBikeCallback>()
        override fun registerCallback(callback: IBikeCallback, identifier: String?) {
            registered += callback
        }
        override fun unregisterCallback(callback: IBikeCallback?, identifier: String?) = Unit
        override fun getRPM() = 0L
        override fun getPower() = 0L
        override fun getStepperMotorPosition() = 0L
        override fun getLoadCellVolume() = 0L
        override fun getCurrentResistance() = 0
        override fun getTargetResistance() = 0
        override fun setResistance(resistance: Int) = Unit
        override fun getFWVersion(): String? = null
        override fun getPacketData(): ByteArray? = null
        override fun getPacketTime(): String? = null
        override fun getStepperMotorStartPosition() = 0
        override fun getStepperMotorEndPosition() = 0
        override fun getCalibrationState() = 0
        override fun getBikeData(): BikeData? = null
        override fun setEnableFakeDataMode(mode: Int) = false
    }

    private val frame = BikeData().apply { rpm = 70; power = 12_000; currentResistance = 35 }

    private fun idleMain(millis: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis))

    private fun warnings(tag: String, containing: String) =
        ShadowLog.getLogsForTag(tag).filter { it.type == Log.WARN && containing in it.msg }

    @Before
    fun clearLogs() = ShadowLog.reset()

    @Test
    fun `g700 - V1 null binding, IBikeInterface streams, V1 retries stop once it is released`() = runTest {
        val v1Ctx = RecordingBindContext(context)
        val bikeCtx = RecordingBindContext(context)
        val v1 = PelotonBikeDataSource(v1Ctx)
        val bike = PelotonBikeInterfaceDataSource(bikeCtx)
        val source = AffernetBikeDataSource(backgroundScope, v1, bike)
        source.start()

        // The g700 answers the V1 bind with a null binding ("requested binder for V1 while
        // attached to TITAN"), every time it is asked.
        v1Ctx.connection.onNullBinding(RecordingBindContext.AFFERNET)
        assertTrue(v1.bindFailure.orEmpty().contains("null binding"))
        repeat(3) {
            idleMain(30_000)
            v1Ctx.connection.onNullBinding(RecordingBindContext.AFFERNET)
        }
        assertEquals("the null-binding warning must be logged once, not per retry",
            1, warnings("PelotonBikeDataSource", "null binding").size)

        val service = FakeBikeService()
        bikeCtx.connection.onServiceConnected(RecordingBindContext.AFFERNET, service)
        service.registered.single().onSensorDataChange(frame)
        advanceTimeBy(300)

        assertEquals("IBikeInterface", source.activePath)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
        assertEquals(70, source.metrics.value.cadenceRpm)
        assertEquals("arbiter must say once that V1 is out", 1,
            warnings("AffernetBikeSource", "IV1Interface unavailable").size)

        val bindsAtRelease = v1Ctx.bindCount
        idleMain(120_000)
        assertEquals("a released V1 binding kept retrying", bindsAtRelease, v1Ctx.bindCount)
        assertEquals(0, bikeCtx.unbindCount)
    }

    @Test
    fun `a bind that throws SecurityException is a recorded failure, and the other interface carries on`() = runTest {
        val v1Ctx = RecordingBindContext(context).apply {
            bindThrows = SecurityException("Not allowed to bind to service Intent")
        }
        val bikeCtx = RecordingBindContext(context)
        val v1 = PelotonBikeDataSource(v1Ctx)
        val bike = PelotonBikeInterfaceDataSource(bikeCtx)
        val source = AffernetBikeDataSource(backgroundScope, v1, bike)

        source.start() // must not throw

        assertTrue(v1.bindFailure.orEmpty().contains("SecurityException"))
        assertEquals(ConnectionState.Unavailable, v1.connectionState.value)

        val service = FakeBikeService()
        bikeCtx.connection.onServiceConnected(RecordingBindContext.AFFERNET, service)
        assertNull(bike.bindFailure)
        service.registered.single().onSensorDataChange(frame)
        advanceTimeBy(300)

        assertEquals("IBikeInterface", source.activePath)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
    }

    @Test
    fun `both denied - one log line names both reasons, once`() = runTest {
        val v1Ctx = RecordingBindContext(context)
        val bikeCtx = RecordingBindContext(context).apply {
            bindThrows = SecurityException("Not allowed to bind to service Intent")
        }
        val v1 = PelotonBikeDataSource(v1Ctx)
        val bike = PelotonBikeInterfaceDataSource(bikeCtx)
        val source = AffernetBikeDataSource(backgroundScope, v1, bike)
        source.start()

        v1Ctx.connection.onNullBinding(RecordingBindContext.AFFERNET)
        advanceTimeBy(1_000)
        repeat(3) {
            idleMain(30_000)
            v1Ctx.connection.onNullBinding(RecordingBindContext.AFFERNET)
            advanceTimeBy(1_000)
        }

        val both = warnings("AffernetBikeSource", "no sensor interface available")
        assertEquals(1, both.size)
        val line = both.single().msg
        assertTrue(line, "IV1Interface" in line && "null binding" in line)
        assertTrue(line, "IBikeInterface" in line && "SecurityException" in line)
        assertNull(source.activePath)
        assertEquals(ConnectionState.Unavailable, source.connectionState.value)
    }

    @Test
    fun `a bike interface bind that throws at start is not retried, like a refused bind`() = runTest {
        // Off-bike (and on any board that denies the bind outright) the start-up bind fails
        // synchronously. That has never been retried, and still is not: no retry loop, no spam.
        val bikeCtx = RecordingBindContext(context).apply { bindThrows = SecurityException("denied") }
        val bike = PelotonBikeInterfaceDataSource(bikeCtx)
        bike.start()
        idleMain(120_000)

        assertEquals(1, bikeCtx.bindCount)
        assertEquals(1, warnings("PelotonBikeIface", "denied").size)
    }
}
