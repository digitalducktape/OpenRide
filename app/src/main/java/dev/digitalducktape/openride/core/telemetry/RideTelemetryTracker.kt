package dev.digitalducktape.openride.core.telemetry

import dev.digitalducktape.openride.core.sensor.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** What a ride's tracker saw, ready for `ride_end`. */
data class RideSummary(
    val hr: HrState,
    val hrDrops: HrDropsBucket,
    val sensor: SensorState,
    val music: RideMusic?,
    val musicControlsUsed: Boolean,
) {
    companion object {
        val EMPTY = RideSummary(HrState.NONE, HrDropsBucket.ZERO, SensorState.NEVER, null, false)
    }
}

/**
 * Collects the per-ride props of `ride_end` (#85) while a ride runs: HR strap drops, bike sensor
 * drop-outs, and music use. [begin] starts watching, [end] stops and summarises. Nothing here
 * throws: a failure leaves the summary at its defaults rather than reaching the ride.
 *
 * Music is sampled by polling [ownMusic] every [MUSIC_SAMPLE_MS] (and once at [end]), since the
 * signal is a plain read of the now-playing state.
 *
 * @param hrConnection the strap's connection state
 * @param strapWanted false while OpenRide has let the strap go on purpose: a disconnect then is no drop
 * @param strapSaved the active rider has a strap saved
 * @param sensorsOffline the app's one bike-offline rule (`null` until known)
 */
class RideTelemetryTracker(
    private val hrConnection: StateFlow<ConnectionState>,
    private val strapWanted: StateFlow<Boolean>,
    private val strapSaved: StateFlow<Boolean>,
    private val sensorsOffline: StateFlow<Boolean?>,
    private val ownMusic: OwnMusicSignal,
    private val scope: CoroutineScope,
) {
    private var jobs: List<Job> = emptyList()
    private var type: RideType = RideType.JUST_RIDE
    private var hrEverConnected = false
    private var hrWasConnected = false
    private var hrDrops = 0
    private var sensorSawData = false
    private var sensorDropped = false
    private var ownMusicPlayed = false
    private var controlsUsed = false

    fun begin(type: RideType) {
        runCatching {
            jobs.forEach { it.cancel() }
            this.type = type
            hrEverConnected = false
            hrWasConnected = false
            hrDrops = 0
            sensorSawData = false
            sensorDropped = false
            ownMusicPlayed = false
            controlsUsed = false
            jobs = listOf(
                scope.launch(start = CoroutineStart.UNDISPATCHED) { hrConnection.collect(::onHr) },
                scope.launch(start = CoroutineStart.UNDISPATCHED) { sensorsOffline.collect(::onSensor) },
                scope.launch(start = CoroutineStart.UNDISPATCHED) {
                    while (isActive) {
                        sampleMusic()
                        delay(MUSIC_SAMPLE_MS)
                    }
                },
            )
        }
    }

    /** The rider used the mini player's buttons during this ride. */
    fun markMusicControl() {
        controlsUsed = true
    }

    fun end(): RideSummary = runCatching {
        sampleMusic()
        jobs.forEach { it.cancel() }
        jobs = emptyList()
        RideSummary(
            hr = when {
                hrEverConnected && hrDrops > 0 -> HrState.DROPPED
                hrEverConnected -> HrState.CONNECTED
                strapSaved.value -> HrState.NEVER_CONNECTED
                else -> HrState.NONE
            },
            hrDrops = TelemetryBuckets.hrDrops(hrDrops),
            sensor = when {
                !sensorSawData -> SensorState.NEVER
                sensorDropped -> SensorState.DROPPED
                else -> SensorState.OK
            },
            music = when (type) {
                RideType.JUST_RIDE -> if (ownMusicPlayed) RideMusic.OWN_MUSIC else RideMusic.NONE
                RideType.CLASS -> RideMusic.NONE // the class's own audio would read as music
                RideType.GAMES -> null
            },
            musicControlsUsed = controlsUsed,
        )
    }.getOrDefault(RideSummary.EMPTY)

    private fun onHr(state: ConnectionState) {
        val connected = state is ConnectionState.Connected
        if (connected) hrEverConnected = true
        else if (hrWasConnected && strapWanted.value) hrDrops++
        hrWasConnected = connected
    }

    private fun onSensor(offline: Boolean?) {
        when (offline) {
            false -> sensorSawData = true
            true -> if (sensorSawData) sensorDropped = true
            null -> Unit
        }
    }

    private fun sampleMusic() {
        if (!ownMusicPlayed && runCatching { ownMusic.trackPlaying() }.getOrDefault(false)) ownMusicPlayed = true
    }

    companion object {
        const val MUSIC_SAMPLE_MS = 5_000L
    }
}
