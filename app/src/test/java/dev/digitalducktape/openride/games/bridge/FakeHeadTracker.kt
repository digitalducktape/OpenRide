package dev.digitalducktape.openride.games.bridge

import dev.digitalducktape.openride.core.camera.CalibrationProgress
import dev.digitalducktape.openride.core.camera.CalibrationStep
import dev.digitalducktape.openride.core.camera.HeadTracker
import dev.digitalducktape.openride.core.camera.HeadTrackerState
import dev.digitalducktape.openride.core.camera.TrackerMode
import dev.digitalducktape.openride.core.camera.TrackerState
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * A [HeadTracker] that records its commands and models only what the bridge relies on: a camera
 * mode needs calibrating until this session has calibrated once, and [resetSession] forgets that.
 */
class FakeHeadTracker : HeadTracker {
    val calls = mutableListOf<String>()
    val mutableState = MutableStateFlow(HeadTrackerState())
    override val state: StateFlow<HeadTrackerState> = mutableState

    private var calibratedThisSession = false

    override fun setMode(mode: TrackerMode) {
        calls += "setMode:${mode.wireName}"
        // As HeadTrackingEngine: the same mode changes nothing, and a calibration in progress
        // carries on through a change between camera modes; only "off" cancels it.
        val current = mutableState.value
        if (mode == current.mode) return
        mutableState.value = if (mode != TrackerMode.OFF && current.trackerState == TrackerState.CALIBRATING) {
            current.copy(mode = mode)
        } else {
            HeadTrackerState(mode = mode, trackerState = idleState(mode))
        }
    }

    override fun calibrate(mode: TrackerMode, force: Boolean) {
        calls += "calibrate:${mode.wireName}:force=$force"
        mutableState.value = HeadTrackerState(
            mode = mode,
            trackerState = TrackerState.CALIBRATING,
            calibration = CalibrationProgress(CalibrationStep.CENTRE, 0, 3, 0.0, 1, null),
        )
    }

    /** The calibration in progress completes. */
    fun finishCalibration() {
        calibratedThisSession = true
        mutableState.value = HeadTrackerState(mode = mutableState.value.mode, trackerState = TrackerState.TRACKING)
    }

    /** The calibration in progress ends as unavailable (no face after two tries): camera off. */
    fun failCalibration() {
        mutableState.value = HeadTrackerState(mode = mutableState.value.mode, trackerState = TrackerState.OFF)
    }

    override fun resetSession() {
        calls += "resetSession"
        calibratedThisSession = false
        val mode = mutableState.value.mode
        mutableState.value = HeadTrackerState(mode = mode, trackerState = idleState(mode))
    }

    override fun setCameraGamesEnabled(enabled: Boolean) { calls += "setCameraGamesEnabled:$enabled" }

    override fun refreshPermission() { calls += "refreshPermission" }

    private fun idleState(mode: TrackerMode) = when {
        mode == TrackerMode.OFF -> TrackerState.OFF
        calibratedThisSession -> TrackerState.TRACKING
        else -> TrackerState.NEEDS_CALIBRATION
    }
}
