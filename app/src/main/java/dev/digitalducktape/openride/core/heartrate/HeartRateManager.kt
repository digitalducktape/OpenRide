package dev.digitalducktape.openride.core.heartrate

import dev.digitalducktape.openride.core.data.ProfileRepository
import dev.digitalducktape.openride.core.profile.ActiveProfileHolder
import dev.digitalducktape.openride.core.sensor.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.launch

/**
 * Connects/reconnects a [ManagedHeartRateDataSource] to whichever BLE address is paired for
 * the *currently active* profile (PRD P1-4: "remember strap per profile"), and exposes a
 * single live `bpm`/`connectionState` pair the rest of the app (ride screen) can just observe
 * without caring which rider is active or when they switched.
 *
 * This is the piece of the BLE feature that's meaningfully unit-testable without hardware
 * (see `HeartRateManagerTest`): given a fake [connectionFactory], it's straightforward to
 * verify "no pairing -> Unavailable", "pairing appears -> a source gets created and started",
 * and "pairing disappears (e.g. switching to an unpaired rider) -> the old source is stopped
 * and state resets to null/Unavailable" — without touching real `android.bluetooth` APIs.
 *
 * @param connectionFactory builds a (not-yet-started) [ManagedHeartRateDataSource] for a given
 *   BLE address. Production wiring passes `{ address -> BleHeartRateDataSource(context, address) }`;
 *   tests pass a fake.
 * @param wanted whether OpenRide needs the strap right now ([strapWanted]: in front, or riding).
 *   While false the strap is let go, so another app (or OpenRide's other build on the same
 *   tablet) can find and use it: a connected strap stops advertising, and one held by a
 *   backgrounded app couldn't be paired anywhere else (rider, 2026-10-27).
 */
class HeartRateManager(
    activeProfileHolder: ActiveProfileHolder,
    profileRepository: ProfileRepository,
    private val connectionFactory: (address: String) -> ManagedHeartRateDataSource,
    private val scope: CoroutineScope,
    wanted: Flow<Boolean> = flowOf(true),
) : HeartRateDataSource {
    private val _bpm = MutableStateFlow<Int?>(null)
    override val bpm: StateFlow<Int?> = _bpm.asStateFlow()

    private val _connectionState = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    override val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private var currentSource: ManagedHeartRateDataSource? = null
    private var forwardingJob: Job? = null

    private val _connectedAddress = MutableStateFlow<String?>(null)
    /** The BLE address currently connected (or being connected) to. */
    val connectedAddress: StateFlow<String?> = _connectedAddress.asStateFlow()

    private val _strapWanted = MutableStateFlow(true)
    /** Whether OpenRide wants the strap right now (see the `wanted` flow). False means a release is on purpose. */
    val strapWanted: StateFlow<Boolean> = _strapWanted.asStateFlow()

    private val _strapSaved = MutableStateFlow(false)
    /** Whether the active rider has a strap saved, held or not. */
    val strapSaved: StateFlow<Boolean> = _strapSaved.asStateFlow()

    init {
        combine(
            activeProfileHolder.activeProfileId,
            // profileRepository.observeProfiles() is backed by a Room @Query Flow, which
            // (unlike activeProfileId, a plain in-memory StateFlow) doesn't necessarily emit
            // its first value synchronously on collection. onStart seeds an empty list
            // immediately so this combine still resolves right away for the extremely common
            // "no rider active yet" / "active rider has no paired strap" cases, rather than
            // silently sitting uninitialized until Room's first real query result lands.
            profileRepository.observeProfiles().onStart { emit(emptyList()) },
            wanted,
        ) { id, profiles, isWanted ->
            profiles.firstOrNull { it.id == id }?.pairedHrDeviceAddress to isWanted
        }
            // Before reconnect() resets the connection state, so a release reads as on purpose.
            .onEach { (saved, isWanted) ->
                _strapSaved.value = saved != null
                _strapWanted.value = isWanted
            }
            .map { (saved, isWanted) -> saved?.takeIf { isWanted } }
            .distinctUntilChanged()
            .onEach { address -> reconnect(address) }
            .launchIn(scope)
    }

    private fun reconnect(address: String?) {
        forwardingJob?.cancel()
        currentSource?.stop()
        currentSource = null
        _connectedAddress.value = null
        _bpm.value = null
        _connectionState.value = ConnectionState.Unavailable

        if (address == null) return

        val source = connectionFactory(address)
        currentSource = source
        _connectedAddress.value = address
        source.start()

        forwardingJob = scope.launch {
            launch { source.bpm.onEach { _bpm.value = it }.launchIn(this) }
            launch { source.connectionState.onEach { _connectionState.value = it }.launchIn(this) }
        }
    }

    /** Stops whatever source is currently connected, e.g. when the app is being torn down. */
    fun stop() {
        forwardingJob?.cancel()
        currentSource?.stop()
        currentSource = null
        _connectedAddress.value = null
    }
}

/**
 * Whether OpenRide needs the strap: while it's in front ([foreground]), or a ride is recording
 * ([rideActive]) with the music app in front. Letting go waits [grace], so a quick trip to
 * Settings or the music app doesn't cost a reconnect (about 12 s on the bike).
 */
@OptIn(ExperimentalCoroutinesApi::class)
fun strapWanted(foreground: Flow<Boolean>, rideActive: Flow<Boolean>, grace: Duration = 30.seconds): Flow<Boolean> =
    combine(foreground, rideActive) { inFront, riding -> inFront || riding }
        .distinctUntilChanged()
        .transformLatest { wanted ->
            if (!wanted) delay(grace)
            emit(wanted)
        }
        .distinctUntilChanged()
