package dev.digitalducktape.openride.core.sensor

import android.os.Handler
import android.os.Looper
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Shadows.shadowOf
import java.time.Duration

@RunWith(AndroidJUnit4::class)
class ServiceRebinderTest {

    private var rebinds = 0
    private val rebinder = ServiceRebinder(Handler(Looper.getMainLooper())) { rebinds++ }

    @Test
    fun `backoff doubles from one second and caps at thirty`() {
        val delays = List(7) { rebinder.schedule() }

        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L, 16_000L, 30_000L, 30_000L), delays)
    }

    @Test
    fun `reset starts the backoff over`() {
        repeat(3) { rebinder.schedule() }

        rebinder.reset()

        assertEquals(1_000L, rebinder.schedule())
    }

    @Test
    fun `a newer schedule replaces the pending retry`() {
        rebinder.schedule()
        rebinder.schedule()

        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(60))

        assertEquals(1, rebinds)
    }

    @Test
    fun `cancel drops the pending retry`() {
        rebinder.schedule()

        rebinder.cancel()
        shadowOf(Looper.getMainLooper()).idleFor(Duration.ofSeconds(60))

        assertEquals(0, rebinds)
        assertEquals(1_000L, rebinder.schedule())
    }
}
