package dev.digitalducktape.openride.core.sensor

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Arbitration coverage for [AffernetBikeDataSource] — the part that decides which affernet
 * binder actually feeds the app.
 *
 * Pure JVM, no device and no Robolectric: the two candidate paths are behind
 * [BoundBikeDataSource] / [PollableBikeDataSource], so a fake can drive the exact hardware
 * behaviours that motivated this class (notably "binds, registers, never pushes", which is what
 * `IV1Interface` does on the Bike+).
 */
@OptIn(ExperimentalCoroutinesApi::class)
class AffernetBikeDataSourceTest {

    private class FakeSource(
        /** What a poll returns, or null to model a path that cannot be polled usefully. */
        private val pollResult: BikeMetrics? = null,
    ) : PollableBikeDataSource {
        private val _metrics = MutableStateFlow(BikeMetrics.ZERO)
        override val metrics: StateFlow<BikeMetrics> = _metrics.asStateFlow()

        private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
        override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

        var started = false
            private set
        var stopped = false
            private set
        var pollCount = 0
            private set

        override fun start() { started = true }
        override fun stop() { stopped = true }

        override fun pollBikeData(): BikeMetrics? {
            pollCount++
            val result = pollResult ?: return null
            _metrics.value = result
            _connectionState.value = ConnectionState.Connected
            return result
        }

        /** Models a pushed frame arriving on this path. */
        fun push(frame: BikeMetrics) {
            _metrics.value = frame
            _connectionState.value = ConnectionState.Connected
        }
    }

    private val gen2Frame = BikeMetrics(cadenceRpm = 82, resistancePercent = 40, powerWatts = 150, speedMph = 18.0)
    private val bikePlusFrame = BikeMetrics(cadenceRpm = 95, resistancePercent = 55, powerWatts = 210, speedMph = 21.0)

    @Test
    fun `starts both paths so the board decides, not a device allowlist`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike).start()

        assertTrue("V1 path was never bound", v1.started)
        assertTrue("IBikeInterface path was never bound", bike.started)
    }

    @Test
    fun `first pushed frame wins and the losing path is released`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        v1.push(gen2Frame)
        advanceTimeBy(500)

        assertEquals("IV1Interface", source.activePath)
        assertEquals(gen2Frame, source.metrics.value)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
        assertTrue("losing IBikeInterface bind was left open", bike.stopped)
        assertFalse("winning V1 bind was closed", v1.stopped)
    }

    @Test
    fun `IBikeInterface wins when it is the path that pushes`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        bike.push(bikePlusFrame)
        advanceTimeBy(500)

        assertEquals("IBikeInterface", source.activePath)
        assertEquals(bikePlusFrame, source.metrics.value)
        assertTrue("losing V1 bind was left open", v1.stopped)
    }

    @Test
    fun `a bound but silent board falls back to polling getBikeData`() = runTest {
        // The Bike+ case: both binds succeed, neither ever pushes.
        val v1 = FakeSource()
        val bike = FakeSource(pollResult = bikePlusFrame)
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        // Before the grace period elapses, nothing is polled and nothing is claimed live.
        advanceTimeBy(1_000)
        assertEquals(0, bike.pollCount)
        assertNull(source.activePath)
        assertEquals(ConnectionState.Unavailable, source.connectionState.value)

        advanceTimeBy(5_000)

        assertTrue("getBikeData was never polled", bike.pollCount > 0)
        assertEquals("IBikeInterface", source.activePath)
        assertEquals(bikePlusFrame, source.metrics.value)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
    }

    @Test
    fun `a pushing board is never polled`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource(pollResult = bikePlusFrame)
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        v1.push(gen2Frame)
        advanceTimeBy(30_000)

        assertEquals("IV1Interface", source.activePath)
        assertEquals("a pushing board should never be polled", 0, bike.pollCount)
    }

    @Test
    fun `stays Unavailable when neither path ever produces a frame`() = runTest {
        // No push, and a poll that returns null — an ordinary phone, or a bike with the service
        // present but dead. Must never report Connected or dress zeros up as a live reading.
        val v1 = FakeSource()
        val bike = FakeSource(pollResult = null)
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        advanceTimeBy(30_000)

        assertNull(source.activePath)
        assertEquals(ConnectionState.Unavailable, source.connectionState.value)
        assertEquals(BikeMetrics.ZERO, source.metrics.value)
    }

    @Test
    fun `stop releases both paths`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()
        source.stop()

        assertTrue(v1.stopped)
        assertTrue(bike.stopped)
        assertNull(source.activePath)
        assertEquals(ConnectionState.Unavailable, source.connectionState.value)
    }
}
