package dev.digitalducktape.openride.core.sensor

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.onepeloton.affernetservice.BikeData
import com.onepeloton.affernetservice.IBikeCallback
import com.onepeloton.affernetservice.IBikeInterface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import java.time.Duration

/**
 * Rebind-on-binding-death recovery for [PelotonBikeInterfaceDataSource], driven through a
 * [RecordingBindContext] standing in for the system. The off-bike degradation contract is the
 * same as [PelotonBikeDataSource]'s and is covered there.
 */
@RunWith(AndroidJUnit4::class)
class PelotonBikeInterfaceDataSourceTest {

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

    private val frame = BikeData().apply { rpm = 95; power = 21_000; currentResistance = 55 }

    private fun advance(millis: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis))

    @Test
    fun `binding death unbinds, rebinds after backoff and re-registers the callback`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeInterfaceDataSource(ctx)
        dataSource.start()
        val first = FakeBikeService()
        ctx.connection.onServiceConnected(RecordingBindContext.AFFERNET, first)
        first.registered.single().onSensorDataChange(frame)
        assertEquals(ConnectionState.Connected, dataSource.connectionState.value)

        ctx.connection.onBindingDied(RecordingBindContext.AFFERNET)

        assertEquals(ConnectionState.Unavailable, dataSource.connectionState.value)
        assertFalse(dataSource.isServiceBound)
        assertEquals("dead binding must be released", 1, ctx.unbindCount)
        advance(999)
        assertEquals("rebound before the 1 s backoff elapsed", 1, ctx.bindCount)
        advance(1)
        assertEquals(2, ctx.bindCount)

        val second = FakeBikeService()
        ctx.connection.onServiceConnected(RecordingBindContext.AFFERNET, second)
        assertEquals("callback not re-registered on the new binder", 1, second.registered.size)
        second.registered.single().onSensorDataChange(frame)
        assertEquals(ConnectionState.Connected, dataSource.connectionState.value)
    }

    @Test
    fun `null binding is retried with growing backoff`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeInterfaceDataSource(ctx)
        dataSource.start()

        ctx.connection.onNullBinding(RecordingBindContext.AFFERNET)
        assertEquals(1, ctx.unbindCount)
        advance(1_000)
        assertEquals(2, ctx.bindCount)
        ctx.connection.onNullBinding(RecordingBindContext.AFFERNET)
        advance(1_999)
        assertEquals("second retry should wait 2 s", 2, ctx.bindCount)
        advance(1)

        assertEquals(3, ctx.bindCount)
    }

    @Test
    fun `stop cancels a pending rebind`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeInterfaceDataSource(ctx)
        dataSource.start()
        ctx.connection.onBindingDied(RecordingBindContext.AFFERNET)

        dataSource.stop()
        advance(60_000)

        assertEquals(1, ctx.bindCount)
        assertEquals(ConnectionState.Unavailable, dataSource.connectionState.value)
    }
}
