package dev.digitalducktape.openride.core.controller

import dev.digitalducktape.openride.core.sensor.ConnectionState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/** A paired controller and how its connection is doing, for the pairing screen. */
data class ControllerStatus(
    val controller: PairedController,
    val connection: ConnectionState,
    val batteryPercent: Int?,
)

/**
 * Keeps every paired OpenBikeControl controller (issue #68) connected while OpenRide [wanted]s
 * them, and turns what they send into one stream of [ControllerAction]s and one steering level.
 *
 * - [events]: presses and releases. Resistance buttons held down repeat ([REPEAT_AFTER_MS], then
 *   every [REPEAT_EVERY_MS]) as further presses, so a long hold climbs like turning a knob.
 * - [steer]: −1..+1 from whichever connected controllers steer (summed, clamped), or `null` when
 *   none does, so games keep steering by head lean.
 *
 * @param scope single-threaded (the main thread in the app): links call back on it, and all of
 *   this manager's state is touched only there.
 * @param linkFactory builds a not-yet-started link; tests pass fakes.
 */
class ControllerManager(
    store: ControllerStore,
    private val linkFactory: (PairedController) -> ObcLink,
    private val scope: CoroutineScope,
    wanted: Flow<Boolean> = flowOf(true),
) {
    private class Connected(val controller: PairedController, val link: ObcLink, val input: ControllerInput) {
        val jobs = mutableListOf<Job>()
        val repeats = mutableMapOf<ControllerAction, Job>()
    }

    private val connected = mutableMapOf<String, Connected>()

    private val _statuses = MutableStateFlow<List<ControllerStatus>>(emptyList())
    val statuses: StateFlow<List<ControllerStatus>> = _statuses.asStateFlow()

    private val _events = MutableSharedFlow<ControllerEvent>(extraBufferCapacity = 64)
    val events: SharedFlow<ControllerEvent> = _events.asSharedFlow()

    private val _steer = MutableStateFlow<Double?>(null)
    val steer: StateFlow<Double?> = _steer.asStateFlow()

    private val _lastPress = MutableStateFlow<ControllerAction?>(null)
    /** The last action pressed, so the pairing screen can show a controller working. */
    val lastPress: StateFlow<ControllerAction?> = _lastPress.asStateFlow()

    init {
        combine(store.paired, wanted) { paired, isWanted -> if (isWanted) paired else emptyList() }
            .distinctUntilChanged()
            .onEach(::reconcile)
            .launchIn(scope)
    }

    /** Sends [pattern] to every connected controller that takes haptics. */
    fun haptic(pattern: Int) {
        connected.values.forEach { it.link.haptic(pattern) }
    }

    private fun reconcile(wantedControllers: List<PairedController>) {
        val wantedKeys = wantedControllers.map(::keyOf).toSet()
        (connected.keys - wantedKeys).toList().forEach(::disconnect)
        wantedControllers.filter { keyOf(it) !in connected }.forEach(::connect)
        publishStatuses()
    }

    private fun connect(controller: PairedController) {
        val link = linkFactory(controller)
        val entry = Connected(controller, link, ControllerInput())
        connected[keyOf(controller)] = entry
        entry.jobs += link.connectionState
            .onEach { state ->
                if (state != ConnectionState.Connected) handle(entry, entry.input.reset())
                publishStatuses()
            }
            .launchIn(scope)
        entry.jobs += link.batteryPercent.onEach { publishStatuses() }.launchIn(scope)
        link.start { message -> scope.launch { onMessage(entry, message) } }
    }

    private fun disconnect(key: String) {
        val entry = connected.remove(key) ?: return
        entry.jobs.forEach { it.cancel() }
        entry.link.stop()
        handle(entry, entry.input.reset())
    }

    private fun onMessage(entry: Connected, message: ObcMessage) {
        if (connected[keyOf(entry.controller)] !== entry) return
        if (message is ObcMessage.ButtonState) handle(entry, entry.input.onButtons(message.buttons))
    }

    private fun handle(entry: Connected, changes: List<ControllerEvent>) {
        for (event in changes) {
            emit(event)
            if (event.action in REPEATING) {
                entry.repeats.remove(event.action)?.cancel()
                if (event.pressed) entry.repeats[event.action] = scope.launch { repeat(event.action) }
            }
        }
        updateSteer()
    }

    private suspend fun repeat(action: ControllerAction) {
        delay(REPEAT_AFTER_MS)
        while (scope.isActive) {
            emit(ControllerEvent(action, pressed = true))
            delay(REPEAT_EVERY_MS)
        }
    }

    private fun emit(event: ControllerEvent) {
        if (event.pressed) _lastPress.value = event.action
        _events.tryEmit(event)
    }

    private fun updateSteer() {
        val levels = connected.values.mapNotNull { it.input.steer }
        _steer.value = if (levels.isEmpty()) null else levels.sum().coerceIn(-1.0, 1.0)
    }

    private fun publishStatuses() {
        _statuses.value = connected.values.map {
            ControllerStatus(it.controller, it.link.connectionState.value, it.link.batteryPercent.value)
        }
    }

    private fun keyOf(controller: PairedController) = "${controller.transport}:${controller.id}"

    companion object {
        const val REPEAT_AFTER_MS = 400L
        const val REPEAT_EVERY_MS = 150L

        /** Held down, these repeat: resistance climbs like a knob turned. */
        val REPEATING = setOf(ControllerAction.RESISTANCE_UP, ControllerAction.RESISTANCE_DOWN)
    }
}
