package dev.digitalducktape.openride.core.telemetry

import dev.digitalducktape.openride.core.sensor.ConnectionState
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class RideTelemetryTrackerTest {
    private val hr = MutableStateFlow<ConnectionState>(ConnectionState.Unavailable)
    private val wanted = MutableStateFlow(true)
    private val saved = MutableStateFlow(true)
    private val offline = MutableStateFlow<Boolean?>(null)
    private var playing = false

    private fun TestScope.tracker() = RideTelemetryTracker(hr, wanted, saved, offline, { playing }, backgroundScope)

    private fun TestScope.begun(type: RideType = RideType.JUST_RIDE) = tracker().also { it.begin(type); runCurrent() }

    private suspend fun TestScope.dropHr() {
        hr.value = ConnectionState.Disconnected; runCurrent()
        hr.value = ConnectionState.Connected; runCurrent()
    }

    @Test fun hrStrapReleasedOnPurposeIsNotADrop() = runTest {
        val t = begun()
        hr.value = ConnectionState.Connected; runCurrent()
        wanted.value = false
        hr.value = ConnectionState.Unavailable; runCurrent()
        val s = t.end()
        assertEquals(HrState.CONNECTED, s.hr)
        assertEquals(HrDropsBucket.ZERO, s.hrDrops)
    }

    @Test fun hrThreeDropsBuckets2to5() = runTest {
        val t = begun()
        hr.value = ConnectionState.Connected; runCurrent()
        repeat(3) { dropHr() }
        val s = t.end()
        assertEquals(HrState.DROPPED, s.hr)
        assertEquals(HrDropsBucket.TWO_5, s.hrDrops)
    }

    @Test fun savedStrapNeverConnects() = runTest {
        assertEquals(HrState.NEVER_CONNECTED, begun().end().hr)
    }

    @Test fun noStrapSavedIsNone() = runTest {
        saved.value = false
        assertEquals(HrState.NONE, begun().end().hr)
    }

    @Test fun sensorDroppedAfterData() = runTest {
        val t = begun()
        offline.value = false; runCurrent()
        offline.value = true; runCurrent()
        offline.value = false; runCurrent()
        assertEquals(SensorState.DROPPED, t.end().sensor)
    }

    @Test fun sensorOkAndNever() = runTest {
        val t = begun()
        offline.value = false; runCurrent()
        assertEquals(SensorState.OK, t.end().sensor)
        offline.value = true
        assertEquals(SensorState.NEVER, begun().end().sensor)
    }

    @Test fun classRideMusicIsNone() = runTest {
        val t = begun(RideType.CLASS)
        playing = true
        advanceTimeBy(RideTelemetryTracker.MUSIC_SAMPLE_MS * 2); runCurrent()
        assertEquals(RideMusic.NONE, t.end().music)
    }

    @Test fun gamesRideMusicIsOmitted() = runTest {
        assertEquals(null, begun(RideType.GAMES).end().music)
    }

    @Test fun justRideOwnMusicWhenTrackPlayed() = runTest {
        val t = begun()
        advanceTimeBy(RideTelemetryTracker.MUSIC_SAMPLE_MS); runCurrent()
        playing = true
        advanceTimeBy(RideTelemetryTracker.MUSIC_SAMPLE_MS); runCurrent()
        playing = false
        assertEquals(RideMusic.OWN_MUSIC, t.end().music)
    }

    @Test fun justRideNoMusicWhenNothingPlayed() = runTest {
        val t = begun()
        advanceTimeBy(RideTelemetryTracker.MUSIC_SAMPLE_MS * 3); runCurrent()
        assertEquals(RideMusic.NONE, t.end().music)
    }

    @Test fun musicControlsAreMarkedAndResetPerRide() = runTest {
        val t = begun()
        t.markMusicControl()
        assertEquals(true, t.end().musicControlsUsed)
        t.begin(RideType.JUST_RIDE)
        assertEquals(false, t.end().musicControlsUsed)
    }

    @Test fun aThrowingMusicSignalNeverEscapes() = runTest {
        val t = RideTelemetryTracker(hr, wanted, saved, offline, { error("boom") }, backgroundScope)
        t.begin(RideType.JUST_RIDE)
        assertEquals(RideMusic.NONE, t.end().music)
    }
}
