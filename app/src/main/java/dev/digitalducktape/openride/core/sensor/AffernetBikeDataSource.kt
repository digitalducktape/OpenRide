package dev.digitalducktape.openride.core.sensor

import android.content.Context
import android.util.Log
import dev.digitalducktape.openride.core.telemetry.BikeSensor
import dev.digitalducktape.openride.core.telemetry.BikeSensorState
import dev.digitalducktape.openride.core.telemetry.NoOpTelemetry
import dev.digitalducktape.openride.core.telemetry.SensorPath
import dev.digitalducktape.openride.core.telemetry.Telemetry
import dev.digitalducktape.openride.core.telemetry.trackSafely
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.atomic.AtomicBoolean

/**
 * The real [BikeDataSource] for Peloton hardware: binds *both* affernet sensor interfaces and
 * keeps whichever one the board actually feeds.
 *
 * ## Why arbitration is needed
 *
 * The affernet service exposes two binders that carry the identical `BikeData` frame, and which
 * one streams depends on the board:
 *
 * | Board | Android | Streams over |
 * |---|---|---|
 * | Bike Gen 2 (`RB1VQ`) | 11 | `IV1Interface` ([PelotonBikeDataSource]) |
 * | Bike+ (`topaz`) | 10 | `IBikeInterface` ([PelotonBikeInterfaceDataSource]) |
 * | `g700` (`PLTN-RTR01`, TITAN sensor board) | 13 | `IBikeInterface`; the V1 bind returns null (#63) |
 *
 * There is no reliable way to tell them apart up front. A build-property check would be a guess,
 * and the failure mode is silent: on the Bike+ the `IV1Interface` bind *succeeds* and
 * `registerCallback` is *accepted*, and then no frame ever arrives — confirmed on-device with a
 * rider pedaling. So instead of predicting, this source starts both and lets the hardware
 * answer: **the first path to deliver a real frame wins**, and the other is unbound.
 *
 * ## One interface refused is a normal outcome (#63)
 *
 * Losing one interface is expected, not an error: the g700 answers every `IV1Interface` bind
 * with a null binding ("requested binder for V1 while attached to TITAN") and streams on
 * `IBikeInterface`. Whatever stops a path — a null binding, `bindService` refused, a bind that
 * throws `SecurityException`, a dead binding, a failed `registerCallback` — shows up as that
 * path's [BoundBikeDataSource.bindFailure]. The race logs it once, keeps waiting on the other
 * interface, and never settles on a failed path. Only when *both* have failed does it log one
 * line naming both reasons; the state stays [ConnectionState.Unavailable] (what an ordinary
 * phone reads, and what the app's offline rule turns into "sensors offline"), and both paths
 * keep their own capped rebind going, so a service that recovers is still picked up.
 *
 * ## Both answering
 *
 * The race looks at both paths every [RACE_POLL_MS]; if both have a frame by the same look,
 * `IV1Interface` wins (a fixed order, so the outcome never depends on scheduling). The loser is
 * stopped — callback unregistered, `unbindService`, pending rebind cancelled — and nothing it
 * publishes afterwards reaches [metrics], which only ever follows the adopted path.
 *
 * ## The adopted path dies
 *
 * The adopted source rebinds itself first ([ServiceRebinder]); an affernet restart normally
 * comes back within a few seconds. If its own state stays off [ConnectionState.Connected] for
 * [SensorOfflineAfter] — the same window after which the app calls the sensors offline (#56) —
 * the race reopens: the released interface is bound again, the poll fallback is re-armed, and
 * the first path to deliver a frame is adopted, exactly as at start. A board that goes *quiet*
 * behind a live binding is not a dead path (both interfaces carry the same board, so rebinding
 * fixes nothing): [watchFrames] reports it [ConnectionState.Disconnected] and the path is kept.
 *
 * That also means adding a board costs nothing here. A future variant that feeds some third
 * binder needs a new [BoundBikeDataSource] and one more entry in the race, not a device
 * allowlist.
 *
 * ## Poll fallback
 *
 * If neither path pushes within [PUSH_GRACE_MS], this polls `IBikeInterface.getBikeData`
 * (transaction 14) at [POLL_INTERVAL_MS]. A board that accepts a callback registration but never
 * fires it still answers a synchronous read, so polling turns "bound but silent" from a dead end
 * into working metrics. Polling only ever starts if pushing has already failed, and a successful
 * poll marks that path Connected through the same first-frame-wins race.
 *
 * ## Honesty contract
 *
 * [ConnectionState.Connected] is reported only once a real frame has been decoded, from either
 * path. A bind that never produces data leaves this [ConnectionState.Unavailable] rather than
 * showing zeros as if they were live readings (PRD P0-9). Once adopted, a path that stops
 * delivering frames for [SENSOR_SILENT_AFTER_MS] reads [ConnectionState.Disconnected] until they
 * return ([watchFrames], issue #56).
 */
class AffernetBikeDataSource(
    private val scope: CoroutineScope,
    private val v1: BoundBikeDataSource,
    private val bikeInterface: PollableBikeDataSource,
    private val telemetry: Telemetry = NoOpTelemetry,
) : BikeDataSource {

    /** Production wiring: the two real affernet binder paths. */
    constructor(context: Context, scope: CoroutineScope, telemetry: Telemetry = NoOpTelemetry) : this(
        scope = scope,
        v1 = PelotonBikeDataSource(context),
        bikeInterface = PelotonBikeInterfaceDataSource(context),
        telemetry = telemetry,
    )

    private val _metrics = MutableStateFlow(BikeMetrics.ZERO)
    override val metrics: StateFlow<BikeMetrics> = _metrics.asStateFlow()

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    /**
     * Which binder ended up feeding metrics, or `null` while the race is open (at start, or
     * reopened after the adopted path died). Exposed for on-device verification and diagnostics.
     */
    @Volatile
    var activePath: String? = null
        private set

    /** Everything [start] launches, so [stop] can take it all down. */
    private val jobs = mutableListOf<Job>()

    /** What [adopt] launches for the current winner; cancelled when the race reopens. */
    private val adoptJobs = mutableListOf<Job>()
    private var pollJob: Job? = null
    private var silenceJob: Job? = null

    /** Paths whose failure this race round has logged already, and whether "both" has been. */
    private val failuresLogged = mutableSetOf<String>()
    private var bothFailedLogged = false

    /** `bike_sensor` goes out once for this source (once per process: the container owns one). */
    private val connectedReported = AtomicBoolean(false)
    private val unavailableReported = AtomicBoolean(false)

    /** Binds both interfaces and starts the race. Safe on any device; never throws. */
    fun start() {
        v1.start()
        bikeInterface.start()

        // No frame at all in the first SENSOR_UNAVAILABLE_AFTER_MS: report it. Cancelled the moment a path wins.
        silenceJob = scope.launch {
            delay(SENSOR_UNAVAILABLE_AFTER_MS)
            if (activePath == null && !connectedReported.get() && unavailableReported.compareAndSet(false, true)) {
                telemetry.trackSafely { BikeSensor(BikeSensorState.UNAVAILABLE, null) }
            }
        }.also { jobs += it }
        openRace()
    }

    /** Starts (or restarts) the race and arms the poll fallback. Both paths must be started. */
    private fun openRace() {
        failuresLogged.clear()
        bothFailedLogged = false
        jobs += scope.launch { race() }
        jobs += scope.launch {
            // Give the push paths a fair chance before falling back to polling, so a board that
            // does push is never polled needlessly.
            delay(PUSH_GRACE_MS)
            if (activePath == null) startPolling()
        }
    }

    /** Unbinds both interfaces and stops all polling and observation. Safe before [start]. */
    fun stop() {
        jobs.forEach { it.cancel() }
        jobs.clear()
        adoptJobs.forEach { it.cancel() }
        adoptJobs.clear()
        pollJob = null
        silenceJob = null
        v1.stop()
        bikeInterface.stop()
        activePath = null
        _connectionState.value = ConnectionState.Unavailable
    }

    /**
     * Waits for the first path to report [ConnectionState.Connected] — which each source does
     * only on a decoded frame — then latches onto it and releases the other. A path with a
     * [BoundBikeDataSource.bindFailure] is never Connected, so it can't win; it is only logged.
     */
    private suspend fun race() {
        while (activePath == null) {
            noteFailures()
            when {
                v1.connectionState.value == ConnectionState.Connected ->
                    adopt(v1, PATH_V1, loser = bikeInterface)

                bikeInterface.connectionState.value == ConnectionState.Connected ->
                    adopt(bikeInterface, PATH_BIKE, loser = v1)

                else -> delay(RACE_POLL_MS)
            }
        }
    }

    private fun adopt(winner: BoundBikeDataSource, path: String, loser: BoundBikeDataSource) {
        activePath = path
        silenceJob?.cancel()
        silenceJob = null
        // A board that only answers polls wins the race on the bike interface too: say which fed it.
        val reported = if (path == PATH_V1) SensorPath.IV1_INTERFACE
        else if (pollJob != null) SensorPath.POLLING else SensorPath.BIKE_INTERFACE
        if (connectedReported.compareAndSet(false, true)) {
            telemetry.trackSafely { BikeSensor(BikeSensorState.CONNECTED, reported) }
        }
        // The single most useful line in a field bug report: which binder this board feeds.
        val how = if (reported == SensorPath.POLLING) "polling getBikeData" else "push"
        val loserName = if (path == PATH_V1) PATH_BIKE else PATH_V1
        val loserNote = loser.bindFailure?.let { "; $loserName was unavailable: $it" } ?: ""
        Log.i(TAG, "sensor path adopted: $path ($how); releasing $loserName$loserNote")
        loser.stop()
        // Polling only feeds the IBikeInterface path; if V1 won, stand it down.
        if (path == PATH_V1) {
            pollJob?.cancel()
            pollJob = null
        }
        adoptJobs += scope.launch { winner.metrics.collect { _metrics.value = it } }
        // The winner's own state, but a board gone quiet behind a live binding reads Disconnected.
        adoptJobs += scope.watchFrames(winner.connectionState, { winner.framesReceived }, _connectionState)
        // A winner whose binding stays down for the offline window: reopen the race (#63).
        adoptJobs += scope.launch {
            winner.connectionState.collectLatest { state ->
                if (state != ConnectionState.Connected) {
                    delay(SensorOfflineAfter)
                    reopen(winner, path, loser)
                }
            }
        }
    }

    /**
     * The adopted [winner] has been off [ConnectionState.Connected] for [SensorOfflineAfter]:
     * bind the released interface again and race both, as at start. The winner keeps its own
     * rebind running, so whichever path delivers a frame first is adopted and the other released.
     * [connectionState] keeps its last value (not Connected) until then.
     */
    private fun reopen(winner: BoundBikeDataSource, path: String, loser: BoundBikeDataSource) {
        // First: stops the old winner's collectors (this call runs inside one of them; it is not
        // suspending, so it finishes), and a new adoption can't be cancelled by mistake.
        adoptJobs.forEach { it.cancel() }
        adoptJobs.clear()
        Log.w(
            TAG,
            "sensor path $path lost (${winner.bindFailure ?: winner.connectionState.value}) for " +
                "${SensorOfflineAfter.inWholeSeconds} s; reopening the race on both interfaces",
        )
        activePath = null
        loser.start()
        openRace()
    }

    /**
     * Logs each path's bind failure once per race round, and — when both have failed — one line
     * naming both reasons: the line a bug report from new hardware needs (#63).
     */
    private fun noteFailures() {
        val v1Failure = v1.bindFailure
        val bikeFailure = bikeInterface.bindFailure
        if (v1Failure != null && failuresLogged.add(PATH_V1) && bikeFailure == null) {
            Log.w(TAG, "$PATH_V1 unavailable: $v1Failure; continuing on $PATH_BIKE")
        }
        if (bikeFailure != null && failuresLogged.add(PATH_BIKE) && v1Failure == null) {
            Log.w(TAG, "$PATH_BIKE unavailable: $bikeFailure; continuing on $PATH_V1")
        }
        if (v1Failure != null && bikeFailure != null && !bothFailedLogged) {
            bothFailedLogged = true
            Log.w(
                TAG,
                "no sensor interface available: $PATH_V1: $v1Failure; $PATH_BIKE: $bikeFailure. " +
                    "Sensors stay unavailable; both bindings keep retrying",
            )
        }
    }

    /**
     * Reads `getBikeData` on a fixed interval. Started only when neither path has pushed. Keeps
     * running once started, because a board that does not push will not start doing so — the
     * poll *is* the feed from then on.
     */
    private fun startPolling() {
        if (pollJob != null) return
        val job = scope.launch {
            while (isActive) {
                bikeInterface.pollBikeData()
                delay(POLL_INTERVAL_MS)
            }
        }
        pollJob = job
        jobs += job
    }

    private companion object {
        const val TAG = "AffernetBikeSource"

        const val PATH_V1 = "IV1Interface"
        const val PATH_BIKE = "IBikeInterface"

        /** How long to wait for a pushed frame before polling instead. */
        const val PUSH_GRACE_MS = 5_000L

        /** Poll cadence once pushing has been ruled out; ~1 Hz suits the in-ride metrics UI. */
        const val POLL_INTERVAL_MS = 1_000L

        /** How often the race checks for a winner. Short enough to feel instant at ride start. */
        const val RACE_POLL_MS = 100L

        /** No frame this long after start reads as `bike_sensor` unavailable. */
        const val SENSOR_UNAVAILABLE_AFTER_MS = 30_000L
    }
}
