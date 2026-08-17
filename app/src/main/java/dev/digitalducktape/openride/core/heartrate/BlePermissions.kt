package dev.digitalducktape.openride.core.heartrate

import android.Manifest
import android.os.Build

/**
 * Which runtime permissions are needed to scan for / connect to BLE heart-rate straps
 * (PRD P1-4, T17), split by API level:
 *
 * - Android 12+ (API 31+) introduced the dedicated `BLUETOOTH_SCAN`/`BLUETOOTH_CONNECT`
 *   runtime permissions.
 * - Everything before that — including this project's actual target hardware, the Bike Gen 2
 *   tablet on Android 10/API 29 or Android 11/API 30 — needs the legacy `ACCESS_FINE_LOCATION` runtime
 *   permission (BLE scans can reveal location on these API levels); `BLUETOOTH`/
 *   `BLUETOOTH_ADMIN` are also required there but are install-time "normal" permissions
 *   (declared in the manifest with `maxSdkVersion="30"`, never requested at runtime).
 *
 * A plain function of [sdkInt] (not `Build.VERSION.SDK_INT` read directly) so the branch is
 * unit-testable on a plain JVM without Robolectric.
 */
fun requiredBlePermissions(sdkInt: Int = Build.VERSION.SDK_INT): Array<String> =
    if (sdkInt >= Build.VERSION_CODES.S) {
        arrayOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
    } else {
        arrayOf(Manifest.permission.ACCESS_FINE_LOCATION)
    }

/**
 * Result of checking/requesting the permissions from [requiredBlePermissions] — drives the
 * pairing screen's "clean rationale + graceful degradation" requirement (PRD P1-4, T17)
 * without the screen needing to re-derive this branching itself.
 */
sealed interface BlePermissionState {
    /** All required permissions are currently granted; scanning/connecting can proceed. */
    data object Granted : BlePermissionState

    /** Never asked yet this session — show the system prompt directly, no rationale needed. */
    data object NotRequested : BlePermissionState

    /** Denied at least once, but Android will still show its own prompt again — show a short
     *  explanation of why the permission is needed before re-asking. */
    data object ShouldShowRationale : BlePermissionState

    /** Denied "don't ask again" (or denied on a fresh install with no rationale ever shown) —
     *  Android won't show its own prompt again; the only path forward is this app's Settings
     *  page. Degrade gracefully here rather than looping a prompt the system will never show. */
    data object PermanentlyDenied : BlePermissionState
}

/**
 * Pure reducer from Android's permission-check/rationale signals to a [BlePermissionState] —
 * the part of the pairing screen's permission handling that's unit-testable without touching
 * real `ContextCompat`/`ActivityCompat` APIs (see `BlePermissionsTest`).
 *
 * @param permissions the permission strings to check, e.g. from [requiredBlePermissions]
 * @param granted this app's current per-permission grant status (post
 *   `ContextCompat.checkSelfPermission`)
 * @param shouldShowRationale Android's per-permission "should show rationale" signal
 *   (`ActivityCompat.shouldShowRequestPermissionRationale`) — `false` both *before* the first
 *   request ever and *after* a permanent denial, which is why [everRequested] is needed to
 *   tell those two apart.
 * @param everRequested whether this screen has already asked at least once this process
 */
fun reduceBlePermissionState(
    permissions: Array<String>,
    granted: (String) -> Boolean,
    shouldShowRationale: (String) -> Boolean,
    everRequested: Boolean,
): BlePermissionState {
    if (permissions.all(granted)) return BlePermissionState.Granted
    if (!everRequested) return BlePermissionState.NotRequested
    return if (permissions.any(shouldShowRationale)) {
        BlePermissionState.ShouldShowRationale
    } else {
        BlePermissionState.PermanentlyDenied
    }
}
