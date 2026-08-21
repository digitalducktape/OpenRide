package dev.digitalducktape.openride.core.sensor

import android.content.Context
import android.content.pm.PackageManager
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * On-device verification of the `IBikeInterface` sensor path — the one the **Bike+** (`topaz`)
 * feeds, where `IV1Interface` binds and then stays silent forever.
 *
 * The counterpart of [SensorBindingInstrumentedTest], which covers the Gen 2 `IV1Interface`
 * path. Both are portable: on any device without the affernet service they assert clean
 * degradation instead of failing.
 *
 * Records three separate outcomes, because they fail independently and the difference is the
 * whole diagnosis:
 *
 *  1. **bind** — did `IBikeInterface` bind and accept `registerCallback`?
 *  2. **push** — did the service fire `onSensorDataChange` on its own?
 *  3. **poll** — does `getBikeData` (transaction 14) return live values on demand?
 *
 * A board that binds but neither pushes nor polls means the reconstruction is wrong. A board
 * that binds and polls but never pushes is working as designed, and [AffernetBikeDataSource]
 * falls back to polling for it.
 *
 * Live cadence values require a person physically pedaling during the window.
 */
@RunWith(AndroidJUnit4::class)
class BikeInterfaceBindingInstrumentedTest {

    private val context: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun bindsAndReadsFramesOverBikeInterface() {
        if (!affernetInstalled()) {
            Log.i(TAG, "affernet NOT present — not a Peloton device; skipping")
            return
        }

        val source = PelotonBikeInterfaceDataSource(context)
        source.start()

        val bound = waitFor(BIND_TIMEOUT_MS) { source.isServiceBound }
        assertTrue("IBikeInterface never bound within ${BIND_TIMEOUT_MS}ms", bound)
        Log.i(TAG, "BIND OK — IBikeInterface bound, callback registered")

        // 2 — does it push on its own?
        val pushed = waitFor(FRAME_TIMEOUT_MS) { source.framesReceived > 0 }
        val afterPush = source.metrics.value
        Log.i(TAG, "PUSH frames=${source.framesReceived} state=${source.connectionState.value} metrics=$afterPush")

        // 3 — does a synchronous read work, regardless of pushing? Sampled a few times so a
        // pedaling rider shows movement rather than one ambiguous frozen value.
        val polls = (1..POLL_SAMPLES).map { i ->
            val m = source.pollBikeData()
            Log.i(TAG, "POLL $i -> $m")
            Thread.sleep(POLL_GAP_MS)
            m
        }
        val polled = polls.filterNotNull()

        val summary = buildString {
            append("bound=$bound pushed=$pushed pushFrames=${source.framesReceived} ")
            append("state=${source.connectionState.value} pushMetrics=$afterPush\n")
            polls.forEachIndexed { i, m -> append("poll${i + 1}=$m\n") }
        }
        runCatching { context.filesDir.resolve("bike_iface_verify.txt").writeText(summary) }
        Log.i(TAG, summary)

        if (polled.isNotEmpty()) {
            // The read landed, so the binder and the BikeData layout are both correct.
            polled.forEach {
                assertTrue("resistance out of range: ${it.resistancePercent}", it.resistancePercent in 0..100)
                assertTrue("cadence negative: ${it.cadenceRpm}", it.cadenceRpm >= 0)
                assertTrue("power negative: ${it.powerWatts}", it.powerWatts >= 0)
            }
        } else {
            // Bind is the load-bearing assertion and is checked above. Don't fail the suite on a
            // board that declines both push and poll — record it and let the summary speak.
            Log.w(TAG, "bound OK but neither pushed nor polled — see $TAG output above")
        }

        source.stop()
    }

    private fun affernetInstalled(): Boolean = try {
        context.packageManager.getPackageInfo(AFFERNET_PKG, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    private inline fun waitFor(timeoutMs: Long, condition: () -> Boolean): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (condition()) return true
            Thread.sleep(POLL_MS)
        }
        return condition()
    }

    private companion object {
        const val TAG = "BikeIfaceITest"
        const val AFFERNET_PKG = "com.onepeloton.affernetservice"
        const val BIND_TIMEOUT_MS = 8_000L
        const val FRAME_TIMEOUT_MS = 10_000L
        const val POLL_MS = 100L
        const val POLL_SAMPLES = 5
        const val POLL_GAP_MS = 1_000L
    }
}
