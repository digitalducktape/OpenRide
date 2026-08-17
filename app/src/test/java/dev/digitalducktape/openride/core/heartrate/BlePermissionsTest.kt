package dev.digitalducktape.openride.core.heartrate

import android.Manifest
import android.os.Build
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Pure-JVM coverage for the BLE permission helpers (PRD P1-4, T17): [requiredBlePermissions]'s
 * per-API-level split and the [reduceBlePermissionState] reducer that the pairing screen leans on
 * instead of re-deriving the branching inline. No Robolectric — these are ordinary functions.
 */
class BlePermissionsTest {

    @Test
    fun `Android 12+ needs the dedicated BLUETOOTH_SCAN and CONNECT runtime permissions`() {
        val permissions = requiredBlePermissions(Build.VERSION_CODES.S)
        assertEquals(
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT),
            permissions.toList(),
        )
    }

    @Test
    fun `Android 11 (the target hardware) needs ACCESS_FINE_LOCATION instead`() {
        val permissions = requiredBlePermissions(Build.VERSION_CODES.R)
        assertEquals(listOf(Manifest.permission.ACCESS_FINE_LOCATION), permissions.toList())
    }

    @Test
    fun `Android 10 (the oldest supported bike firmware) also needs ACCESS_FINE_LOCATION`() {
        val permissions = requiredBlePermissions(Build.VERSION_CODES.Q)
        assertEquals(listOf(Manifest.permission.ACCESS_FINE_LOCATION), permissions.toList())
    }

    @Test
    fun `all permissions granted reduces to Granted`() {
        val state = reduceBlePermissionState(
            permissions = arrayOf("A", "B"),
            granted = { true },
            shouldShowRationale = { false },
            everRequested = true,
        )
        assertEquals(BlePermissionState.Granted, state)
    }

    @Test
    fun `not yet requested reduces to NotRequested even without a rationale signal`() {
        val state = reduceBlePermissionState(
            permissions = arrayOf("A", "B"),
            granted = { false },
            shouldShowRationale = { false },
            everRequested = false,
        )
        assertEquals(BlePermissionState.NotRequested, state)
    }

    @Test
    fun `denied once with a rationale signal reduces to ShouldShowRationale`() {
        val state = reduceBlePermissionState(
            permissions = arrayOf("A", "B"),
            granted = { false },
            shouldShowRationale = { it == "A" },
            everRequested = true,
        )
        assertEquals(BlePermissionState.ShouldShowRationale, state)
    }

    @Test
    fun `denied with no rationale after being requested reduces to PermanentlyDenied`() {
        val state = reduceBlePermissionState(
            permissions = arrayOf("A", "B"),
            granted = { false },
            shouldShowRationale = { false },
            everRequested = true,
        )
        assertEquals(BlePermissionState.PermanentlyDenied, state)
    }

    @Test
    fun `a partial grant is still not Granted`() {
        val state = reduceBlePermissionState(
            permissions = arrayOf("A", "B"),
            granted = { it == "A" }, // B still missing
            shouldShowRationale = { false },
            everRequested = true,
        )
        assertEquals(BlePermissionState.PermanentlyDenied, state)
    }
}
