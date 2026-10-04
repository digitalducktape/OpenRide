package dev.digitalducktape.openride.core.sensor

import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.onepeloton.affernetservice.BikeData
import com.onepeloton.affernetservice.IV1Callback
import com.onepeloton.affernetservice.IV1Interface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import java.time.Duration

/**
 * [PelotonBikeDataSource] can't be meaningfully tested without the physical bike (see its
 * class doc / issue #3) — these tests only cover what's verifiable in Robolectric: that it
 * never crashes when the real Peloton service isn't present (true of every dev/CI
 * environment) and degrades to [ConnectionState.Unavailable] rather than fabricating a
 * connected/live state — plus the rebind-on-binding-death recovery, driven through a
 * [RecordingBindContext] standing in for the system.
 */
@RunWith(AndroidJUnit4::class)
class PelotonBikeDataSourceTest {

    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @Test
    fun `starts in Unavailable state before start() is called`() {
        val dataSource = PelotonBikeDataSource(context)

        assertEquals(ConnectionState.Unavailable, dataSource.connectionState.value)
        assertEquals(BikeMetrics.ZERO, dataSource.metrics.value)
    }

    @Test
    fun `start does not throw when the Peloton service package is absent`() {
        val dataSource = PelotonBikeDataSource(context)

        dataSource.start()

        // No real Peloton service exists in this (or any non-bike) environment, so this
        // must never resolve to Connected — Unavailable is the only honest state here.
        assertEquals(ConnectionState.Unavailable, dataSource.connectionState.value)
    }

    @Test
    fun `stop is a no-op when start was never called`() {
        val dataSource = PelotonBikeDataSource(context)

        dataSource.stop()

        assertEquals(ConnectionState.Unavailable, dataSource.connectionState.value)
    }

    @Test
    fun `stop after start does not throw`() {
        val dataSource = PelotonBikeDataSource(context)

        dataSource.start()
        dataSource.stop()

        assertEquals(ConnectionState.Unavailable, dataSource.connectionState.value)
    }

    // --- Recovery when the affernet process dies (onBindingDied / onNullBinding) ---

    private class FakeV1Service : IV1Interface.Stub() {
        val registered = mutableListOf<IV1Callback>()
        override fun registerCallback(callback: IV1Callback, identifier: String?) {
            registered += callback
        }
        override fun unregisterCallback(callback: IV1Callback?, identifier: String?) = Unit
        override fun setFakeDataMode(enabled: Boolean) = false
        override fun setCallbackReportRate(rateMillis: Int) = rateMillis
    }

    private val frame = BikeData().apply { rpm = 80; power = 15_000; currentResistance = 40 }

    private fun advance(millis: Long) = shadowOf(Looper.getMainLooper()).idleFor(Duration.ofMillis(millis))

    @Test
    fun `binding death unbinds, rebinds after backoff and re-registers the callback`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeDataSource(ctx)
        dataSource.start()
        val first = FakeV1Service()
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

        val second = FakeV1Service()
        ctx.connection.onServiceConnected(RecordingBindContext.AFFERNET, second)
        assertEquals("callback not re-registered on the new binder", 1, second.registered.size)
        second.registered.single().onSensorDataChange(frame)
        assertEquals(ConnectionState.Connected, dataSource.connectionState.value)
    }

    @Test
    fun `repeated failures back off exponentially and a successful connect resets it`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeDataSource(ctx)
        dataSource.start()

        ctx.connection.onNullBinding(RecordingBindContext.AFFERNET)
        advance(1_000)
        assertEquals(2, ctx.bindCount)

        ctx.connection.onBindingDied(RecordingBindContext.AFFERNET)
        advance(1_999)
        assertEquals("second retry should wait 2 s", 2, ctx.bindCount)
        advance(1)
        assertEquals(3, ctx.bindCount)

        ctx.connection.onServiceConnected(RecordingBindContext.AFFERNET, FakeV1Service())
        ctx.connection.onBindingDied(RecordingBindContext.AFFERNET)
        advance(1_000)
        assertEquals("backoff not reset by a successful connect", 4, ctx.bindCount)
    }

    @Test
    fun `a refused rebind is retried`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeDataSource(ctx)
        dataSource.start()
        ctx.connection.onBindingDied(RecordingBindContext.AFFERNET)
        ctx.bindResult = false

        advance(1_000)
        assertEquals(2, ctx.bindCount)
        ctx.bindResult = true
        advance(2_000)

        assertEquals(3, ctx.bindCount)
    }

    @Test
    fun `stop cancels a pending rebind`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeDataSource(ctx)
        dataSource.start()
        ctx.connection.onBindingDied(RecordingBindContext.AFFERNET)

        dataSource.stop()
        advance(60_000)

        assertEquals(1, ctx.bindCount)
        assertEquals(ConnectionState.Unavailable, dataSource.connectionState.value)
    }

    @Test
    fun `binding death after stop does not rebind`() {
        val ctx = RecordingBindContext(context)
        val dataSource = PelotonBikeDataSource(ctx)
        dataSource.start()
        val connection = ctx.connection
        dataSource.stop()

        connection.onBindingDied(RecordingBindContext.AFFERNET)
        advance(60_000)

        assertEquals(1, ctx.bindCount)
    }
}
