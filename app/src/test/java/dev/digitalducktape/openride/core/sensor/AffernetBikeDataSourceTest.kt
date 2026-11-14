package dev.digitalducktape.openride.core.sensor

import dev.digitalducktape.openride.core.telemetry.BikeSensor
import dev.digitalducktape.openride.core.telemetry.BikeSensorState
import dev.digitalducktape.openride.core.telemetry.RecordingTelemetry
import dev.digitalducktape.openride.core.telemetry.SensorPath
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
        var startCount = 0
            private set
        var stopCount = 0
            private set
        var pollCount = 0
            private set
        override var framesReceived = 0L
            private set

        /** Set by a test to model a bind the service denied, refused or threw on. */
        override var bindFailure: String? = null

        override fun start() {
            started = true
            startCount++
        }

        /** Like the real sources: closing the binding drops the path to Unavailable. */
        override fun stop() {
            stopped = true
            stopCount++
            _connectionState.value = ConnectionState.Unavailable
        }

        /** Models the service refusing this interface (null binding, SecurityException, ...). */
        fun deny(reason: String) {
            bindFailure = reason
            _connectionState.value = ConnectionState.Unavailable
        }

        /** Models the binder dying under a live path (affernet killed or updated). */
        fun die() {
            bindFailure = "binding died"
            _connectionState.value = ConnectionState.Unavailable
        }

        override fun pollBikeData(): BikeMetrics? {
            pollCount++
            val result = pollResult ?: return null
            framesReceived++
            _metrics.value = result
            _connectionState.value = ConnectionState.Connected
            return result
        }

        /** Models a pushed frame arriving on this path. */
        fun push(frame: BikeMetrics) {
            framesReceived++
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
    fun `a board that goes quiet behind a live binding reads Disconnected, then recovers (issue 56)`() = runTest {
        // 2026-10-19: the service stayed bound and the callback registered, but the board stopped
        // answering, so frames simply stopped. The path's own state never left Connected.
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()
        repeat(20) {
            v1.push(gen2Frame)
            advanceTimeBy(50)
        }
        assertEquals(ConnectionState.Connected, source.connectionState.value)

        advanceTimeBy(2_000)
        assertEquals("a short gap is not silence", ConnectionState.Connected, source.connectionState.value)
        advanceTimeBy(1_500)
        assertEquals(ConnectionState.Connected, v1.connectionState.value)
        assertEquals(ConnectionState.Disconnected, source.connectionState.value)

        v1.push(gen2Frame)
        advanceTimeBy(300)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
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

    // --- Interface fallback (#63): one interface denied, both answering, both denied, winner lost ---

    private val g700Frame = BikeMetrics(cadenceRpm = 70, resistancePercent = 35, powerWatts = 120, speedMph = 16.0)

    @Test
    fun `g700 - V1 bind denied with a null binding, IBikeInterface streams and is adopted`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        v1.deny("null binding")
        advanceTimeBy(300)
        assertNull("a denied V1 alone must not settle the race", source.activePath)
        bike.push(g700Frame)
        advanceTimeBy(300)

        assertEquals("IBikeInterface", source.activePath)
        assertEquals(g700Frame, source.metrics.value)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
        assertEquals("denied V1 binding (and its retries) not released", 1, v1.stopCount)
        assertEquals(0, bike.stopCount)
    }

    @Test
    fun `IBikeInterface denied, V1 streams and is adopted`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        bike.deny("bind denied: SecurityException")
        advanceTimeBy(300)
        v1.push(gen2Frame)
        advanceTimeBy(300)

        assertEquals("IV1Interface", source.activePath)
        assertEquals(gen2Frame, source.metrics.value)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
        assertEquals(1, bike.stopCount)
        assertEquals(0, v1.stopCount)
    }

    @Test
    fun `a bind that throws SecurityException on V1 still leaves IBikeInterface running`() = runTest {
        // The real sources catch the throw and report it as bindFailure (see
        // AffernetInterfaceFallbackTest for that half); here: the arbiter carries on regardless.
        val v1 = FakeSource().apply { deny("bind denied: java.lang.SecurityException: Not allowed to bind") }
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        bike.push(g700Frame)
        advanceTimeBy(300)

        assertEquals("IBikeInterface", source.activePath)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
    }

    @Test
    fun `both answering in the same tick - V1 wins deterministically, loser released once, no stray frames`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()

        // Both deliver before the race next looks: the tie always goes to IV1Interface.
        bike.push(bikePlusFrame)
        v1.push(gen2Frame)
        advanceTimeBy(300)

        assertEquals("IV1Interface", source.activePath)
        assertEquals(gen2Frame, source.metrics.value)
        assertEquals("loser must be unbound exactly once", 1, bike.stopCount)
        assertEquals(0, v1.stopCount)

        // A frame already in flight on the released binding must never reach consumers.
        val stray = BikeMetrics(cadenceRpm = 1, resistancePercent = 1, powerWatts = 1, speedMph = 1.0)
        bike.push(stray)
        advanceTimeBy(300)
        assertEquals(gen2Frame, source.metrics.value)
        assertEquals("IV1Interface", source.activePath)

        val next = gen2Frame.copy(cadenceRpm = 90)
        v1.push(next)
        advanceTimeBy(300)
        assertEquals(next, source.metrics.value)
    }

    @Test
    fun `both denied - stays Unavailable, never Connected, reports unavailable once, keeps both retrying`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource(pollResult = null)
        val telemetry = RecordingTelemetry()
        val source = AffernetBikeDataSource(backgroundScope, v1, bike, telemetry)
        source.start()

        v1.deny("null binding")
        bike.deny("bind denied: SecurityException")
        advanceTimeBy(60_000)

        assertNull(source.activePath)
        assertEquals(ConnectionState.Unavailable, source.connectionState.value)
        assertEquals(BikeMetrics.ZERO, source.metrics.value)
        assertEquals(listOf<Any>(BikeSensor(BikeSensorState.UNAVAILABLE, null)), telemetry.events)
        // Neither is torn down: each source's own rebinder keeps trying, so a service that
        // recovers is still picked up.
        assertEquals(0, v1.stopCount)
        assertEquals(0, bike.stopCount)

        bike.bindFailure = null
        bike.push(g700Frame)
        advanceTimeBy(300)
        assertEquals("IBikeInterface", source.activePath)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
    }

    @Test
    fun `winner dies after selection - the race reopens and the other interface takes over`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()
        v1.push(gen2Frame)
        advanceTimeBy(300)
        assertEquals("IV1Interface", source.activePath)
        assertEquals(1, bike.stopCount)

        v1.die()
        advanceTimeBy(9_000)
        assertEquals("V1 should get the offline window to rebind itself first", 1, bike.startCount)
        assertEquals(ConnectionState.Unavailable, source.connectionState.value)

        advanceTimeBy(2_000)
        assertEquals("the released interface was not re-bound", 2, bike.startCount)
        assertNull(source.activePath)

        bike.push(bikePlusFrame)
        advanceTimeBy(300)
        assertEquals("IBikeInterface", source.activePath)
        assertEquals(bikePlusFrame, source.metrics.value)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
        assertEquals("the dead winner must be released once the other path wins", 1, v1.stopCount)

        // The old winner's collector is gone: nothing it publishes reaches consumers now.
        v1.push(gen2Frame)
        advanceTimeBy(300)
        assertEquals(bikePlusFrame, source.metrics.value)
    }

    @Test
    fun `winner dies and the reopened race falls back to polling the other interface`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource(pollResult = bikePlusFrame)
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()
        v1.push(gen2Frame)
        advanceTimeBy(300)

        v1.die()
        advanceTimeBy(11_000 + 6_000)

        assertTrue("getBikeData was never polled after the race reopened", bike.pollCount > 0)
        assertEquals("IBikeInterface", source.activePath)
        assertEquals(ConnectionState.Connected, source.connectionState.value)
    }

    @Test
    fun `a winner that rebinds itself within the offline window keeps the path`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()
        v1.push(gen2Frame)
        advanceTimeBy(300)

        v1.die()
        advanceTimeBy(3_000)
        v1.bindFailure = null
        v1.push(gen2Frame)
        advanceTimeBy(30_000)

        assertEquals("IV1Interface", source.activePath)
        assertEquals("a quick self-rebind must not disturb the released path", 1, bike.startCount)
        assertEquals(0, v1.stopCount)
    }

    @Test
    fun `a board gone quiet behind a live binding does not reopen the race`() = runTest {
        // Silence (#56) is the board, not the binder: both interfaces carry the same board, so
        // re-binding fixes nothing. The watchdog reports Disconnected; the path is kept.
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()
        v1.push(gen2Frame)
        advanceTimeBy(60_000)

        assertEquals(ConnectionState.Disconnected, source.connectionState.value)
        assertEquals("IV1Interface", source.activePath)
        assertEquals(1, bike.startCount)
    }

    @Test
    fun `stop after the race reopened releases both paths and stays down`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val source = AffernetBikeDataSource(scope = backgroundScope, v1 = v1, bikeInterface = bike)
        source.start()
        v1.push(gen2Frame)
        advanceTimeBy(300)
        v1.die()
        advanceTimeBy(11_000)

        source.stop()
        bike.push(bikePlusFrame)
        advanceTimeBy(60_000)

        assertNull(source.activePath)
        assertEquals(ConnectionState.Unavailable, source.connectionState.value)
        assertEquals(2, bike.startCount)
        assertEquals(2, bike.stopCount)
        assertEquals(1, v1.stopCount)
    }

    // --- telemetry (#85): bike_sensor ---

    @Test
    fun `reports connected with the iv1 path, once`() = runTest {
        val v1 = FakeSource()
        val bike = FakeSource()
        val telemetry = RecordingTelemetry()
        AffernetBikeDataSource(backgroundScope, v1, bike, telemetry).start()

        v1.push(gen2Frame)
        advanceTimeBy(40_000)
        v1.push(gen2Frame)
        advanceTimeBy(500)

        assertEquals(listOf<Any>(BikeSensor(BikeSensorState.CONNECTED, SensorPath.IV1_INTERFACE)), telemetry.events)
    }

    @Test
    fun `reports the bike interface path when it pushes`() = runTest {
        val bike = FakeSource()
        val telemetry = RecordingTelemetry()
        AffernetBikeDataSource(backgroundScope, FakeSource(), bike, telemetry).start()

        bike.push(bikePlusFrame)
        advanceTimeBy(500)

        assertEquals(listOf<Any>(BikeSensor(BikeSensorState.CONNECTED, SensorPath.BIKE_INTERFACE)), telemetry.events)
    }

    @Test
    fun `reports polling when only polls feed the bike`() = runTest {
        val bike = FakeSource(pollResult = bikePlusFrame)
        val telemetry = RecordingTelemetry()
        AffernetBikeDataSource(backgroundScope, FakeSource(), bike, telemetry).start()

        advanceTimeBy(6_500)

        assertEquals(listOf<Any>(BikeSensor(BikeSensorState.CONNECTED, SensorPath.POLLING)), telemetry.events)
    }

    @Test
    fun `reports unavailable after 30 seconds with no data, and only then`() = runTest {
        val telemetry = RecordingTelemetry()
        AffernetBikeDataSource(backgroundScope, FakeSource(), FakeSource(), telemetry).start()

        advanceTimeBy(29_900)
        assertTrue(telemetry.events.isEmpty())
        advanceTimeBy(200)
        assertEquals(listOf<Any>(BikeSensor(BikeSensorState.UNAVAILABLE, null)), telemetry.events)
        advanceTimeBy(120_000)
        assertEquals(1, telemetry.events.size)
    }

    @Test
    fun `data before 30 seconds cancels the unavailable timer`() = runTest {
        val v1 = FakeSource()
        val telemetry = RecordingTelemetry()
        AffernetBikeDataSource(backgroundScope, v1, FakeSource(), telemetry).start()

        advanceTimeBy(10_000)
        v1.push(gen2Frame)
        advanceTimeBy(60_000)

        assertEquals(1, telemetry.events.size)
        assertEquals(BikeSensorState.CONNECTED, (telemetry.events.single() as BikeSensor).state)
    }
}
