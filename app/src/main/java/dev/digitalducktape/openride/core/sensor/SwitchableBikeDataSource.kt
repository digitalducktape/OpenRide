package dev.digitalducktape.openride.core.sensor

import android.content.Context
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.flow.stateIn

/**
 * Where the bike's numbers come from (issue #68): the [Builtin] source (the Peloton's own
 * sensors, or the simulation in the mock build), or a smart [Trainer] over FTMS.
 */
sealed interface BikeSource {
    data object Builtin : BikeSource

    /** @param address the trainer's BLE address; [name] as it advertised, if it did. */
    data class Trainer(val address: String, val name: String?) : BikeSource
}

/** Where the [BikeSource] choice lives. */
interface BikeSourceStore {
    val source: StateFlow<BikeSource>
    fun set(source: BikeSource)
}

class InMemoryBikeSourceStore(initial: BikeSource = BikeSource.Builtin) : BikeSourceStore {
    private val state = MutableStateFlow(initial)
    override val source: StateFlow<BikeSource> = state.asStateFlow()
    override fun set(source: BikeSource) { state.value = source }
}

/** The real store: SharedPreferences, so the choice survives restarts. The bike's, not a rider's. */
class SharedPrefsBikeSourceStore(context: Context) : BikeSourceStore {
    private val prefs = context.applicationContext.getSharedPreferences("bike_source", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(read())
    override val source: StateFlow<BikeSource> = state.asStateFlow()

    override fun set(source: BikeSource) {
        prefs.edit().apply {
            when (source) {
                BikeSource.Builtin -> remove(KEY_TRAINER_ADDRESS).remove(KEY_TRAINER_NAME)
                is BikeSource.Trainer -> putString(KEY_TRAINER_ADDRESS, source.address).putString(KEY_TRAINER_NAME, source.name)
            }
        }.apply()
        state.value = source
    }

    private fun read(): BikeSource =
        prefs.getString(KEY_TRAINER_ADDRESS, null)?.let { BikeSource.Trainer(it, prefs.getString(KEY_TRAINER_NAME, null)) }
            ?: BikeSource.Builtin

    private companion object {
        const val KEY_TRAINER_ADDRESS = "trainer_address"
        const val KEY_TRAINER_NAME = "trainer_name"
    }
}

/**
 * The app's one [BikeDataSource] (issue #68): it reads through to whichever [BikeSource] is
 * chosen, so the ride, the screens, the games and the "sensors offline" rule never know which.
 *
 * - The [builtin] source is made the first time it's chosen and then kept running: the
 *   Peloton's binding is made once per process, and a switch back to it is instant.
 * - A trainer is connected only while it's chosen and OpenRide [wanted]s it (in front, or
 *   recording a ride), so another app can use it the rest of the time, like the strap.
 *
 * It's a [ResistanceControl] too, adjustable while the current source is (a trainer that
 * took control); otherwise stepping does nothing.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class SwitchableBikeDataSource(
    store: BikeSourceStore,
    builtin: () -> BikeDataSource,
    private val trainerFactory: (address: String) -> ManagedBikeDataSource,
    scope: CoroutineScope,
    wanted: Flow<Boolean> = flowOf(true),
) : BikeDataSource, ResistanceControl {
    private val builtinSource by lazy(builtin)
    private var trainer: ManagedBikeDataSource? = null
    private val current = MutableStateFlow<BikeDataSource?>(null)

    override val metrics: StateFlow<BikeMetrics> =
        current.flatMapLatest { it?.metrics ?: flowOf(BikeMetrics.ZERO) }.stateIn(scope, SharingStarted.Eagerly, BikeMetrics.ZERO)

    override val connectionState: StateFlow<ConnectionState> =
        current.flatMapLatest { it?.connectionState ?: flowOf(ConnectionState.Unavailable) }
            .stateIn(scope, SharingStarted.Eagerly, ConnectionState.Unavailable)

    override val adjustable: StateFlow<Boolean> =
        current.flatMapLatest { (it as? ResistanceControl)?.adjustable ?: flowOf(false) }
            .stateIn(scope, SharingStarted.Eagerly, false)

    init {
        combine(store.source, wanted) { source, isWanted -> source to isWanted }
            .distinctUntilChanged()
            .onEach { (source, isWanted) -> switchTo(source, isWanted) }
            .launchIn(scope)
    }

    override fun stepResistance(steps: Int) {
        (current.value as? ResistanceControl)?.stepResistance(steps)
    }

    private fun switchTo(source: BikeSource, isWanted: Boolean) {
        trainer?.stop()
        trainer = null
        current.value = when (source) {
            BikeSource.Builtin -> builtinSource
            is BikeSource.Trainer -> if (isWanted) trainerFactory(source.address).also { it.start(); trainer = it } else null
        }
    }
}
