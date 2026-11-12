package dev.digitalducktape.openride.ui.ride

import androidx.lifecycle.ViewModel
import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.data.Ride
import dev.digitalducktape.openride.core.heartrate.HeartRateManager
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.ride.LiveAggregates
import dev.digitalducktape.openride.core.ride.PowerZone
import dev.digitalducktape.openride.core.ride.RideGoal
import dev.digitalducktape.openride.core.ride.RideSessionManager
import dev.digitalducktape.openride.core.ride.RideSessionState
import dev.digitalducktape.openride.core.route.Route
import dev.digitalducktape.openride.core.route.RouteHolder
import dev.digitalducktape.openride.core.route.RoutePosition
import dev.digitalducktape.openride.core.sensor.BikeDataSource
import dev.digitalducktape.openride.core.sensor.BikeMetrics
import dev.digitalducktape.openride.core.sensor.ConnectionState
import dev.digitalducktape.openride.core.sensor.ResistanceControl
import dev.digitalducktape.openride.core.sensor.offlineFor
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.scan

/**
 * Combined snapshot the in-ride screen renders from. Kept as one immutable value (rather
 * than the screen collecting five separate flows) so a single [combine] is the only place
 * that has to reason about how the pieces line up.
 *
 * @param sensorsOffline the app's one "sensors offline" rule said so (issue #56: anything but
 *   Connected, a silent board included, for 10 s): the screen shows the "Sensors not
 *   detected" banner and blank tiles (PRD P0-9) — never a fake zero reading.
 * @param goal the rider's pre-ride target (PRD P1-3), or [RideGoal.None].
 * @param ftp the active rider's FTP in watts, or `null` if not set — drives [currentZone].
 * @param heartRateBpm live bpm from the active profile's paired strap (PRD P1-4, T17), or
 *   `null` if either no strap is paired or it hasn't delivered a reading yet.
 * @param heartRatePaired whether the active profile has a strap paired at all — distinct
 *   from [heartRateBpm] being non-null, since a paired-but-not-yet-connected strap should
 *   still show its tile (as "--"), not hide it entirely.
 * @param heartRateConnectionState the paired strap's live connection state, `Unavailable` if
 *   none is paired.
 */
data class InRideUiState(
    val elapsedSec: Int = 0,
    val sessionState: RideSessionState = RideSessionState.Idle,
    val metrics: BikeMetrics = BikeMetrics.ZERO,
    val aggregates: LiveAggregates = LiveAggregates(),
    val sensorsOffline: Boolean = false,
    val distanceMiles: Double = 0.0,
    val goal: RideGoal = RideGoal.None,
    val ftp: Int? = null,
    val heartRateBpm: Int? = null,
    val heartRatePaired: Boolean = false,
    val heartRateConnectionState: ConnectionState = ConnectionState.Unavailable,
    val autoPaused: Boolean = false,
    /** The source's resistance is OpenRide's to set (a smart trainer, #68): the tile gets − and +. */
    val resistanceAdjustable: Boolean = false,
    val route: Route? = null,
    val routePosition: RoutePosition? = null,
) {
    val sensorsAvailable: Boolean get() = !sensorsOffline
    val isPaused: Boolean get() = sessionState == RideSessionState.Paused

    /** Whether the BPM tile should be shown at all (PRD P1-4, T17) — only once a strap is
     *  paired for the active rider, regardless of whether it's currently connected. */
    val heartRateTileVisible: Boolean get() = heartRatePaired

    /** Whether the paired strap is actually live right now (vs. paired but not yet connected). */
    val heartRateConnected: Boolean get() = heartRateConnectionState == ConnectionState.Connected

    /**
     * Live running output in kilojoules. `avgPower * elapsedSec` reconstructs the summed
     * joules exactly (avgPower is already `sum / elapsedSec`), matching
     * [RideSessionManager.stop]'s own `outputKj` math without needing a second running sum
     * threaded through the manager.
     */
    val liveOutputKj: Double get() = aggregates.avgPower * elapsedSec / 1000.0

    /** The live power zone (PRD P1-3), or `null` while sensors are down or FTP is unset. */
    val currentZone: PowerZone? get() = if (sensorsAvailable) PowerZone.forPower(metrics.powerWatts, ftp) else null

    /**
     * Fractional progress (0.0-1.0, clamped) toward [goal], or `null` when no goal is set or
     * the goal's target isn't a usable positive value.
     */
    val goalProgress: Double?
        get() = when (val g = goal) {
            RideGoal.None -> null
            is RideGoal.Duration -> (g.targetSec.takeIf { it > 0 })
                ?.let { (elapsedSec.toDouble() / it).coerceIn(0.0, 1.0) }
            is RideGoal.Output -> (g.targetKj.takeIf { it > 0.0 })
                ?.let { (liveOutputKj / it).coerceIn(0.0, 1.0) }
        }
}

/**
 * In-ride screen (PRD P0-7/P0-9/P0-10/P1-3): the core screen, showing live cadence/resistance/
 * output tiles, the elapsed timer, live power-zone and goal progress, and pause/end controls,
 * sourced from [RideSessionManager] (timer/aggregates/goal), [BikeDataSource] (live sensor
 * feed + connectivity), and the active rider's FTP (for power-zone display).
 */
class InRideViewModel(
    private val rideSessionManager: RideSessionManager,
    private val bikeDataSource: BikeDataSource,
    profileRepository: ProfileRepository,
    activeProfileHolder: ActiveProfileHolder,
    private val heartRateManager: HeartRateManager? = null,
    routeHolder: RouteHolder? = null,
    /** The app's one "sensors offline" rule ([dev.digitalducktape.openride.AppContainer.sensorsOffline]); `null` = not known yet. */
    sensorsOffline: Flow<Boolean?> = bikeDataSource.connectionState.offlineFor(),
    /** A trainer's virtual resistance (#68); the source itself when it is one. */
    private val resistanceControl: ResistanceControl? = bikeDataSource as? ResistanceControl,
) : ViewModel() {
    // profileRepository.observeProfiles() is backed by a Room @Query Flow, which (unlike the
    // rest of this view model's plain in-memory StateFlows) doesn't necessarily emit its first
    // value synchronously on collection. onStart seeds an empty list immediately so the
    // combine below still emits right away (ftp = null until the real query result lands),
    // matching every other input to this screen's uiState combine.
    private val ftpFlow: Flow<Int?> = combine(
        activeProfileHolder.activeProfileId,
        profileRepository.observeProfiles().onStart { emit(emptyList()) },
    ) { id, profiles -> profiles.firstOrNull { it.id == id }?.ftp }

    private val coreFlow: Flow<CoreRideFlow> = combine(
        rideSessionManager.elapsedSec,
        rideSessionManager.state,
        bikeDataSource.metrics,
        rideSessionManager.liveAggregates,
        // An unknown start counts as online: the banner waits for the rule, like the top bar.
        sensorsOffline.onStart { emit(null) },
    ) { elapsedSec, sessionState, metrics, aggregates, offline ->
        CoreRideFlow(elapsedSec, sessionState, metrics, aggregates, offline == true)
    }

    // Live heart rate from the active profile's paired strap (PRD P1-4, T17). When no manager
    // is wired (tests, or a build without the BLE layer), this is a single static "no strap"
    // snapshot so the combine below still emits and the HR tile simply stays hidden.
    private val heartRateFlow: Flow<HeartRateSnapshot> =
        if (heartRateManager == null) {
            flowOf(HeartRateSnapshot(bpm = null, paired = false, state = ConnectionState.Unavailable))
        } else {
            combine(
                heartRateManager.bpm,
                heartRateManager.connectionState,
                heartRateManager.connectedAddress,
            ) { bpm, state, address ->
                HeartRateSnapshot(bpm = bpm, paired = address != null, state = state)
            }
        }

    private val routeFlow: Flow<Route?> = routeHolder?.activeRoute ?: flowOf(null)

    // Heart rate + auto-pause + active route folded into one flow so the outer combine stays
    // within combine()'s 5-arg typed limit.
    private val secondaryFlow: Flow<SecondaryFlow> = combine(
        heartRateFlow,
        rideSessionManager.autoPaused,
        routeFlow,
        resistanceControl?.adjustable ?: flowOf(false),
    ) { hr, autoPaused, route, adjustable ->
        SecondaryFlow(hr, autoPaused, route, adjustable)
    }

    val uiState: Flow<InRideUiState> = combine(
        coreFlow,
        rideSessionManager.goal,
        ftpFlow,
        secondaryFlow,
    ) { core, goal, ftp, secondary ->
        InRideUiState(
            elapsedSec = core.elapsedSec,
            sessionState = core.sessionState,
            metrics = core.metrics,
            aggregates = core.aggregates,
            sensorsOffline = core.sensorsOffline,
            goal = goal,
            ftp = ftp,
            heartRateBpm = secondary.hr.bpm,
            heartRatePaired = secondary.hr.paired,
            heartRateConnectionState = secondary.hr.state,
            autoPaused = secondary.autoPaused,
            resistanceAdjustable = secondary.resistanceAdjustable,
            route = secondary.route,
        )
    }.scan(InRideUiState()) { previous, next ->
        // Distance has no dedicated field on BikeMetrics/RideSample (PRD only requires
        // cadence/resistance/power to be persisted) — it's accumulated here purely for
        // display, one elapsedSec tick at a time, and only while the ride is actually
        // advancing (never during Paused/Idle, and never double-counted across ticks).
        val tickedForward = next.elapsedSec > previous.elapsedSec
        val addedMiles = if (tickedForward && next.sessionState == RideSessionState.Active) {
            val deltaSec = next.elapsedSec - previous.elapsedSec
            next.metrics.speedMph / 3600.0 * deltaSec
        } else {
            0.0
        }
        val distanceMiles = previous.distanceMiles + addedMiles
        // Map accumulated distance onto the active route for the grade/progress overlay (T21).
        val routePosition = next.route?.positionAt(distanceMiles * METERS_PER_MILE)
        next.copy(distanceMiles = distanceMiles, routePosition = routePosition)
    }

    fun pause() = rideSessionManager.pause()

    fun resume() = rideSessionManager.resume()

    /** The tile's − and + (#68): a step of the trainer's resistance. */
    fun stepResistance(steps: Int) {
        resistanceControl?.stepResistance(steps)
    }

    /**
     * Stops the ride and persists it. Deliberately does *not* call
     * [RideSessionManager.reset] — that happens when the summary screen this navigates to is
     * dismissed, so [RideSessionState.Finished] survives long enough for that screen (T8) to
     * rely on it if needed.
     */
    suspend fun endRide(): Ride? = rideSessionManager.stop()

    private data class CoreRideFlow(
        val elapsedSec: Int,
        val sessionState: RideSessionState,
        val metrics: BikeMetrics,
        val aggregates: LiveAggregates,
        val sensorsOffline: Boolean,
    )

    private data class HeartRateSnapshot(
        val bpm: Int?,
        val paired: Boolean,
        val state: ConnectionState,
    )

    private data class SecondaryFlow(
        val hr: HeartRateSnapshot,
        val autoPaused: Boolean,
        val route: Route?,
        val resistanceAdjustable: Boolean,
    )

    private companion object {
        /** Exact international-mile conversion, for mapping display miles onto route metres. */
        const val METERS_PER_MILE = 1609.344
    }
}
