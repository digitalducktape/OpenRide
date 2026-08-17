package dev.digitalducktape.openride.core.sensor

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

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
 *
 * There is no reliable way to tell them apart up front. A build-property check would be a guess,
 * and the failure mode is silent: on the Bike+ the `IV1Interface` bind *succeeds* and
 * `registerCallback` is *accepted*, and then no frame ever arrives — confirmed on-device with a
 * rider pedaling. So instead of predicting, this source starts both and lets the hardware
 * answer: **the first path to deliver a real frame wins**, and the other is unbound.
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
 * showing zeros as if they were live readings (PRD P0-9).
 */
class AffernetBikeDataSource(
    private val scope: CoroutineScope,
    private val v1: BoundBikeDataSource,
    private val bikeInterface: PollableBikeDataSource,
) : BikeDataSource {

    /** Production wiring: the two real affernet binder paths. */
    constructor(context: Context, scope: CoroutineScope) : this(
        scope = scope,
        v1 = PelotonBikeDataSource(context),
        bikeInterface = PelotonBikeInterfaceDataSource(context),
    )

    private val _metrics = MutableStateFlow(BikeMetrics.ZERO)
    override val metrics: StateFlow<BikeMetrics> = _metrics.asStateFlow()

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    /**
     * Which binder ended up feeding metrics, or `null` while the race is still open. Exposed for
     * on-device verification and for diagnostics.
     */
    @Volatile
    var activePath: String? = null
        private set

    /** Everything [start] launches, so [stop] can take it all down. */
    private val jobs = mutableListOf<Job>()
    private var pollJob: Job? = null

    /** Binds both interfaces and starts the race. Safe on any device; never throws. */
    fun start() {
        v1.start()
        bikeInterface.start()

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
        pollJob = null
        v1.stop()
        bikeInterface.stop()
        activePath = null
        _connectionState.value = ConnectionState.Unavailable
    }

    /**
     * Waits for the first path to report [ConnectionState.Connected] — which each source does
     * only on a decoded frame — then latches onto it and releases the other.
     */
    private suspend fun race() {
        while (activePath == null) {
            when {
                v1.connectionState.value == ConnectionState.Connected ->
                    adopt(v1, PATH_V1, loser = bikeInterface)

                bikeInterface.connectionState.value == ConnectionState.Connected ->
                    adopt(bikeInterface, PATH_BIKE, loser = v1)

                else -> delay(RACE_POLL_MS)
            }
        }
    }

    private fun adopt(winner: BikeDataSource, path: String, loser: BoundBikeDataSource) {
        activePath = path
        // The single most useful line in a field bug report: which binder this board feeds.
        Log.i(TAG, "sensor path adopted: $path (releasing the other binding)")
        loser.stop()
        // Polling only feeds the IBikeInterface path; if V1 won, stand it down.
        if (path == PATH_V1) {
            pollJob?.cancel()
            pollJob = null
        }
        jobs += scope.launch { winner.metrics.collect { _metrics.value = it } }
        jobs += scope.launch { winner.connectionState.collect { _connectionState.value = it } }
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
    }
}
