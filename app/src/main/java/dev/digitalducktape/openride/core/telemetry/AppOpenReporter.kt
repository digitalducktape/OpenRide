package dev.digitalducktape.openride.core.telemetry

import android.os.Build
import dev.digitalducktape.openride.BuildConfig
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

/**
 * Sends `app_open` once per process: the first time the app is in the foreground with consent
 * granted. If the rider grants consent while already in the foreground, it fires then; either
 * way never twice. Call [start] once, then [onForeground] on each process foreground.
 */
class AppOpenReporter(
    private val telemetry: Telemetry,
    private val consent: TelemetryConsentStore,
    private val profileCount: suspend () -> Int,
    private val scope: CoroutineScope,
    private val tablet: Tablet = tabletOf(Build.MODEL.orEmpty()),
    private val firmware: Firmware = firmwareOf(Build.DISPLAY.orEmpty()),
    private val flavor: Flavor = flavorOf(BuildConfig.USE_REAL_BIKE_SENSOR),
) {
    private var foreground = false
    private var granted = false
    private var fired = false

    fun start() {
        scope.launch {
            consent.consent.collect {
                granted = it == Consent.Granted
                maybeFire()
            }
        }
    }

    fun onForeground() {
        foreground = true
        maybeFire()
    }

    private fun maybeFire() {
        if (fired || !granted || !foreground) return
        fired = true
        scope.launch {
            // A failing count (Room) must not reach the process: report one profile instead.
            val profiles = try {
                profileCount()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                1
            }
            telemetry.trackSafely { AppOpen(tablet, firmware, TelemetryBuckets.profiles(profiles), flavor) }
        }
    }
}
