@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package dev.digitalducktape.openride.core.sensor

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SwitchableBikeDataSourceTest {
    private class FakeSource(watts: Int) : BikeDataSource {
        override val metrics = MutableStateFlow(BikeMetrics(80, 30, watts, 15.0))
        override val connectionState: StateFlow<ConnectionState> = MutableStateFlow(ConnectionState.Connected)
    }

    private class FakeTrainer(val address: String) : ManagedBikeDataSource, ResistanceControl {
        override val metrics = MutableStateFlow(BikeMetrics(90, 25, 200, 18.0))
        override val connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
        override val adjustable = MutableStateFlow(true)
        var started = false
        var stopped = false
        val steps = mutableListOf<Int>()
        override fun start() { started = true }
        override fun stop() { stopped = true }
        override fun stepResistance(steps: Int) { this.steps += steps }
    }

    private var builtinMade = 0
    private val trainers = mutableListOf<FakeTrainer>()

    private fun TestScope.source(store: BikeSourceStore, wanted: MutableStateFlow<Boolean> = MutableStateFlow(true)) =
        SwitchableBikeDataSource(
            store = store,
            builtin = { builtinMade++; FakeSource(watts = 150) },
            trainerFactory = { FakeTrainer(it).also(trainers::add) },
            scope = backgroundScope,
            wanted = wanted,
        ).also { runCurrent() }

    @Test
    fun `the built-in source reads through`() = runTest {
        val bike = source(InMemoryBikeSourceStore())

        assertEquals(150, bike.metrics.value.powerWatts)
        assertEquals(ConnectionState.Connected, bike.connectionState.value)
        assertFalse(bike.adjustable.value)
    }

    @Test
    fun `a trainer is started and reads through, with its resistance control`() = runTest {
        val bike = source(InMemoryBikeSourceStore(BikeSource.Trainer("AA", "KICKR")))

        val trainer = trainers.single()
        assertTrue(trainer.started)
        assertEquals(200, bike.metrics.value.powerWatts)
        assertTrue(bike.adjustable.value)
        assertEquals(0, builtinMade)

        bike.stepResistance(1)
        assertEquals(listOf(1), trainer.steps)
    }

    @Test
    fun `switching back stops the trainer, and the built-in source is made once`() = runTest {
        val store = InMemoryBikeSourceStore()
        val bike = source(store)

        store.set(BikeSource.Trainer("AA", null))
        runCurrent()
        store.set(BikeSource.Builtin)
        runCurrent()

        assertTrue(trainers.single().stopped)
        assertEquals(1, builtinMade)
        assertEquals(150, bike.metrics.value.powerWatts)
        bike.stepResistance(1) // nothing to step: no crash, no trainer call
        assertEquals(emptyList<Int>(), trainers.single().steps)
    }

    @Test
    fun `a trainer is let go while not wanted, and connected again after`() = runTest {
        val wanted = MutableStateFlow(true)
        val bike = source(InMemoryBikeSourceStore(BikeSource.Trainer("AA", null)), wanted)

        wanted.value = false
        runCurrent()
        assertTrue(trainers.single().stopped)
        assertEquals(ConnectionState.Unavailable, bike.connectionState.value)

        wanted.value = true
        runCurrent()
        assertEquals(2, trainers.size)
        assertTrue(trainers.last().started)
    }
}
