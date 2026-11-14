package dev.digitalducktape.openride.games.session

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

/**
 * A [PlanRide] like `RideSessionManager`: a 1 Hz clock that stops while paused, a manual pause
 * from [pause], and a freewheel auto-pause the test drives with [autoPause] / [pedalAgain].
 */
class FakePlanRide(scope: CoroutineScope) : PlanRide {
    val calls = mutableListOf<String>()
    private val paused = MutableStateFlow(false)
    private var auto = false

    override var elapsedSec = 0
        private set
    override val isPaused: Boolean get() = paused.value
    override val pausedChanges: Flow<Boolean> = paused

    /** As the real ride: turning it off ends an auto-pause in force. */
    override var autoPauseAllowed = true
        set(value) {
            field = value
            if (!value && auto) {
                auto = false
                paused.value = false
            }
        }

    init {
        scope.launch {
            while (isActive) {
                delay(1_000)
                if (!paused.value) elapsedSec++
            }
        }
    }

    override fun pause() {
        calls += "pause"
        auto = false
        paused.value = true
    }

    override fun resume() {
        calls += "resume"
        auto = false
        paused.value = false
    }

    /** The rider stopped pedalling. */
    fun autoPause() {
        if (paused.value) return
        auto = true
        paused.value = true
    }

    /** The rider pedals again: only an auto-pause ends. */
    fun pedalAgain() {
        if (auto) {
            auto = false
            paused.value = false
        }
    }
}
