package dev.digitalducktape.openride.core.controller

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** How OpenRide reaches a controller: OpenBikeControl's two transports (issue #68). */
enum class ControllerTransport { BLUETOOTH, NETWORK }

/**
 * A controller the rider paired. The bike's, not a rider's: a shifter or a BikeControl phone is
 * part of the setup, so every rider gets it.
 *
 * @param id the BLE address, or the mDNS service name (a network controller's address can change
 *   between sessions, its name doesn't).
 */
@Serializable
data class PairedController(
    val transport: ControllerTransport,
    val id: String,
    val name: String? = null,
)

/** Where the paired controllers live. */
interface ControllerStore {
    val paired: StateFlow<List<PairedController>>
    fun add(controller: PairedController)
    fun remove(controller: PairedController)
}

/** Keeps controllers in memory, for tests. */
class InMemoryControllerStore(initial: List<PairedController> = emptyList()) : ControllerStore {
    private val state = MutableStateFlow(initial)
    override val paired: StateFlow<List<PairedController>> = state.asStateFlow()
    override fun add(controller: PairedController) { state.value = state.value.withAdded(controller) }
    override fun remove(controller: PairedController) { state.value = state.value.withRemoved(controller) }
}

/** The real store: SharedPreferences, so pairings survive restarts. */
class SharedPrefsControllerStore(context: Context) : ControllerStore {
    private val prefs = context.applicationContext.getSharedPreferences("controllers", Context.MODE_PRIVATE)
    private val state = MutableStateFlow(read())
    override val paired: StateFlow<List<PairedController>> = state.asStateFlow()

    override fun add(controller: PairedController) = write(state.value.withAdded(controller))
    override fun remove(controller: PairedController) = write(state.value.withRemoved(controller))

    private fun write(next: List<PairedController>) {
        prefs.edit().putString(KEY_PAIRED, Json.encodeToString(next)).apply()
        state.value = next
    }

    private fun read(): List<PairedController> =
        prefs.getString(KEY_PAIRED, null)
            ?.let { runCatching { Json.decodeFromString<List<PairedController>>(it) }.getOrNull() }
            .orEmpty()

    private companion object {
        const val KEY_PAIRED = "paired"
    }
}

/** Adds [controller], replacing an earlier pairing of the same one (its name may have changed). */
internal fun List<PairedController>.withAdded(controller: PairedController): List<PairedController> =
    filterNot { it.sameAs(controller) } + controller

internal fun List<PairedController>.withRemoved(controller: PairedController): List<PairedController> =
    filterNot { it.sameAs(controller) }

fun PairedController.sameAs(other: PairedController): Boolean = transport == other.transport && id == other.id
