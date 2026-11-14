# Target devices

The physical hardware this project is verified against, plus tablets the community has
reported working.

| Property | Bike Gen 2 | Bike+ | `g700` tablet |
|---|---|---|---|
| Status | verified | verified | **reported working (community, #63)** |
| Model / SKU | PLTN-RB1VQ | PLTN-TTR01 | PLTN-RTR01 (`ro.boot.product.hardware.sku`) |
| Device codename (`ro.product.device`) | RB1VQ | TTR01 | g700 |
| Board (`ro.product.board`) | — | topaz | g700 (MediaTek `mt8390`, TITAN sensor board) |
| Android release | 11 | 10 | 13 |
| API level | 30 | 29 | 33 |
| Firmware build (`ro.build.display.id`) | `RQ.250113.A` | `QT.250804.A` | `TA.260520.H` (Peloton OS `13.15.2008`) |
| Sensor binder | `IV1Interface` | `IBikeInterface` | `IBikeInterface` (the `IV1Interface` bind is refused) |

The `g700` column comes from a rider's report on #63 (OpenRide 1.0.0, AffernetService 3.2.1), not
from a unit we have tested ourselves. On that tablet the sensor service refuses the V1 binder
(`Denied: requested binder for V1 while attached to TITAN`, a null binding on our side) and
`IBikeInterface` streams live cadence, power and resistance; OpenRide's interface fallback picks
that up with no device-specific code (see "Board arbitration" in `docs/SENSOR_PROTOCOL.md`).

**Known caveat on the `g700` (reported, not fixed):** a few minutes after boot the stock Peloton
app draws a full-screen overlay (for example a "subscription cancelled" banner) over the home
screen, even with OpenRide set as home. It is a system overlay window, not a launcher, so
OpenRide's home-screen setting can't stop it. The reporter's workaround is to disable the
Peloton app; see `docs/INSTALL.md`.

Note that `ro.product.model` on the Bike+ reads `PLTN-TTR01`, which looks like a
Tread string and is not. The board is `topaz` and the live sensor path is the
bike one; the affernet APK is a single universal build shipped fleet-wide, so
the presence of `TreadData`/`ITreadInterface` classes on a unit proves nothing
about what that unit is.

## Why this matters

Real sensor binding via the internal system service is only valid against a
known firmware. Those are the builds the app is installed and tested on. If an
OTA changes a build string, the system-service interface may change and the
binding must be re-verified — which is why blocking OTA updates is part of the
pre-cancellation checklist (see PRD "Risks" and `docs/INSTALL.md`).

The boards do **not** feed the same binder. See `docs/SENSOR_PROTOCOL.md`.
The app does not decide from a build property: it binds both and keeps whichever
one delivers a frame, so a new board needs no device allowlist entry. A board
that refuses one of the two binders outright (the `g700`) is an expected case,
not an error.

## Supported Android versions

`minSdk` is **29** (Android 10). Some Gen 2 bikes sit on an Android 10 firmware
and cannot take an OTA, so the app must install there too.

The app calls no framework API above 29. Audit of every `android.*` API in use:

| Area | API used | Added in |
|---|---|---|
| Auto-backup to `Download/OpenRide/` | `MediaStore.Downloads`, `RELATIVE_PATH`, `IS_PENDING` | 29 |
| Heart-rate strap | `BluetoothLeScanner`, `BluetoothGatt` | 21 |
| Full-screen kiosk mode | `WindowInsetsControllerCompat`, `enableEdgeToEdge` | compat, 21 |
| Self-updater | `REQUEST_INSTALL_PACKAGES`, `FileProvider` | 26 / 24 |
| Class player | `WebView` + JS bridge | 1 |
| Sensor binding | `bindService` + AIDL | 1 |

Two things behave differently on 29 but need no code change:

- `<queries>` is ignored below API 30. Package visibility filtering does not
  exist there, so the camera intent for profile photos resolves either way.
- `ACCESS_FINE_LOCATION` is the BLE scan permission on both 29 and 30, so
  `requiredBlePermissions` already returns the right set (see `BlePermissions.kt`).

Verified on the Bike+ (Android 10): the app installs, launches, renders at
1920×1080, and reads live sensor data. Its WebView is Chromium `127.0.6533.9`,
new enough for the YouTube IFrame player.

## Install verified

### Bike Gen 2, build `RQ.250113.A`

- `adb install -r` of the debug APK: **Success**
- App launches to the profile-select screen, renders correctly at 1920×1080 landscape
- Launcher alias (`.HomeLauncherAlias`) remains **disabled** — installing did not alter stock HOME behavior

### Bike+, build `QT.250804.A`

- `adb install -r` of the `debugReal` APK: **Success**
- App launches to the profile-select screen, renders correctly at 1920×1080 landscape
- `AffernetBikeDataSource` adopts `IBikeInterface` ~70 ms after launch and releases the V1 binding
- Live values with a rider pedaling, via `BikeInterfaceBindingInstrumentedTest`:
  cadence 81-85 rpm, resistance 43%, power 134-143 W, speed ~18.4 mph
- The service pushes at roughly 21 Hz on this board, so the poll fallback stays idle
