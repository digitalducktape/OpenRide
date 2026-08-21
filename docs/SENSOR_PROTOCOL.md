# Sensor Protocol — Bike Gen 2 and Bike+ (T3 / #3)

How OpenRide reads live cadence / resistance / power off the Peloton Bike tablet, and how that
was determined. Two boards are covered: the Bike Gen 2, which streams over `IV1Interface`, and
the Bike+, which streams over `IBikeInterface`. This is an **interoperability reconstruction** for the owner's own
hardware: OpenRide binds an exported, unguarded on-device service and reconstructs its binder
interface as AIDL. No Peloton code is copied or redistributed; no DRM is circumvented; no class
content is touched (see the PRD Non-Goals).

## TL;DR

| | |
|---|---|
| **Service package** | `com.onepeloton.affernetservice` (the "affernet" system service) |
| **Component** | `com.onepeloton.affernetservice.AffernetService` — `exported=true`, **no** `android:permission` |
| **Bind Intent** | action = the interface name below, package `com.onepeloton.affernetservice` |
| **Bound interface (Gen 2)** | `IV1Interface` + `IV1Callback` (`oneway`) |
| **Bound interface (Bike+)** | `IBikeInterface` + `IBikeCallback` (`oneway`) |
| **Which one** | decided at runtime — both are bound, first to deliver a frame wins |
| **Model** | callback / push (register a callback, service pushes frames), with a `getBikeData` poll fallback |
| **Frame payload** | `BikeData` Parcelable, delivered to `onSensorDataChange` (callback txn 1), identical on both |

## Why this path (A vs B, IV1 vs IBike)

The recon found two exported unguarded services: `com.peloton.service.SensorData` (legacy,
`Messenger`-based) and `com.onepeloton.affernetservice` (this one). The affernet service exposes
several binder interfaces — `IAffernetService`, `IV1Interface`, `IBikeInterface`,
`IAuroraInterface`, `ITreadInterface`, `ICaesarInterface`, `IAccessoryService`.

`IBikeInterface` looks tempting (it has `getRPM`, `getPower`, `getCurrentResistance`,
`getBikeData`, `registerCallback`) but it is a lower-level, bike-board-specific interface.
The interface that actually streams the compact `BikeData` sensor frame via a simple
register-a-callback model — and the one **grupetto has proven on Gen 2** — is **`IV1Interface`
+ `IV1Callback`**. Both interfaces share the same `BikeData` Parcelable, so the payload decode
is identical either way; OpenRide binds the `IV1Interface` path because it matches grupetto's
field-tested approach exactly.

**That holds on the Gen 2 only.** On the Bike+ (board `topaz`, Android 10) `IV1Interface`
binds, accepts `registerCallback`, and then never pushes a single frame — verified on-device
with a rider actively pedaling. That board streams over `IBikeInterface`, which is also what
the stock Peloton software holds bound there. Since the two boards cannot be told apart
reliably up front, and the wrong guess fails *silently*, OpenRide binds both and keeps
whichever delivers a frame. See "Board arbitration" below.

Speed is intentionally absent from the service. The stock Peloton bike itself synthesises speed
from power; OpenRide reproduces that (see "Speed" below).

## Transaction codes

AIDL assigns binder transaction codes 1..N in method-declaration order, so the reconstructed
`.aidl` files declare methods in the exact order below to match the live service.

### `IV1Interface` (bound binder)

| Code | Method | Used by OpenRide |
|---|---|---|
| 1 | `registerCallback(IV1Callback, String)` | yes — subscribe to frames |
| 2 | `unregisterCallback(IV1Callback, String)` | yes — on stop |
| 3 | `setFakeDataMode(boolean): boolean` | verification only (no-rider frames) |
| 4 | `setCallbackReportRate(int): int` | yes — request ~1 Hz |

(The real interface has codes 5..15 too — calibration/Lxx/power-source calls OpenRide never
uses. Only 1..4 are reconstructed, since declaring more only risks signature drift.)

### `IBikeInterface` (bound binder, Bike+ path)

Codes read directly out of the on-device APK's `IBikeInterface$Stub` `TRANSACTION_*` constants
with `apkanalyzer dex code`, then confirmed identical in OpenRide's own generated stub.

| Code | Method | Used by OpenRide |
|---|---|---|
| 1 | `getRPM(): long` | no (cross-check only) |
| 2 | `getPower(): long` | no (cross-check only) |
| 5 | `getCurrentResistance(): int` | no (cross-check only) |
| 6 | `getTargetResistance(): int` | no |
| 14 | `getBikeData(): BikeData` | yes — synchronous poll fallback |
| 15 | `registerCallback(IBikeCallback, String)` | yes — subscribe to frames |
| 16 | `unregisterCallback(IBikeCallback, String)` | yes — on stop |
| 17 | `setEnableFakeDataMode(int): boolean` | verification only |

Codes 3, 4, 7..13 are declared in the reconstruction purely to hold the numbering. The real
interface continues past 17 (calibration, bootloader, serial numbers, power-zone auto-follow);
OpenRide stops at 17 because every method it uses sits at or below it.

Two differences from `IV1Interface` worth noting: `setEnableFakeDataMode` takes an `int` rather
than a `boolean` and has a separate `setDisableFakeDataMode()` at 18, and `registerCallback`
sits at 15 rather than 1.

### `IBikeCallback` (our callback, `oneway`)

| Code | Method | Handled |
|---|---|---|
| 1 | `onSensorDataChange(in BikeData)` | yes — decode -> `BikeMetrics` |
| 2 | `onSensorError(long)` | yes — mark Disconnected |
| 3 | `onCalibrationStatus(int, boolean, long)` | no-op (kept so codes 1/2 line up) |

Codes 4..7 (`onOTAUpdateStatus`, `onDiagnosticDataChange`, `onMBSerial`, `onLogDataChange`) are
not declared. The service fires them only in response to requests OpenRide never makes; if one
did arrive, the generated stub returns false from `onTransact` and the `oneway` call is dropped.

Confirmed `oneway` from the on-device proxy bytecode, which issues
`transact(code, data, null, 1)` — null reply parcel, `FLAG_ONEWAY` set. It marshals the frame
with `writeTypedObject`, which is exactly AIDL's `[int hasData][payload]` nullable-parcelable
framing, so the payload decode is byte-identical to the V1 path.

### `IV1Callback` (our callback, `oneway`)

| Code | Method | Handled |
|---|---|---|
| 1 | `onSensorDataChange(in BikeData)` | yes — decode -> `BikeMetrics` |
| 2 | `onSensorError(long)` | yes — mark Disconnected |
| 3 | `onCalibrationStatus(int, boolean, long)` | no-op (kept so codes 1/2 line up) |

`onSensorDataChange`'s wire form is `[int hasData][BikeData if hasData != 0]`; AIDL's standard
nullable-parcelable marshalling (`writeInt(1)` + `writeToParcel`, or `writeInt(0)` for null)
reproduces that framing exactly, so the generated stub decodes the service's frames verbatim.

### Board arbitration

`AffernetBikeDataSource` binds both interfaces at launch and adopts **the first one to deliver
a decoded frame**, then unbinds the loser. No build-property check, no device allowlist.

If neither path pushes within 5 s, it polls `IBikeInterface.getBikeData` at 1 Hz. That covers a
board which accepts a callback registration but never fires it — the exact behaviour
`IV1Interface` shows on the Bike+ — since a synchronous read still works in that state.

Measured on the Bike+: adoption of `IBikeInterface` completes ~70 ms after launch, and the
service pushes at roughly 21 Hz, so the poll path stays idle. `ConnectionState.Connected` is
still only ever reported after a real frame decodes, from either path (PRD P0-9).

## `BikeData` payload layout

The Parcelable is large; only the first fields matter to OpenRide and they sit at the very front
(before any variable-length field), so they are captured before anything could desync. Full
read order (matching the service's `writeToParcel`) is implemented and commented in
`app/src/main/java/com/onepeloton/affernetservice/BikeData.kt`. The consumed fields:

| Offset | Field | Type | Meaning |
|---|---|---|---|
| 1 | `mRPM` | `long` | crank cadence, **already RPM** |
| 2 | `mPower` | `long` | output, **centi-watts** (watts x 100) |
| 5 | `mCurrentResistance` | `int` | resistance, **already 0..100** |
| 6 | `mTargetResistance` | `int` | commanded resistance, 0..100 |

Field 57 is a nested `V3BikeData` Parcelable (`readParcelable`), reconstructed in
`V3BikeData.kt` so the outer parcel stays in sync when a V3 sensor-board frame is present. The
error-map arrays are length-prefixed (`BIKE_ERROR_COUNT = 15`).

## Scaling (raw frame -> `BikeMetrics`)

All confirmed against grupetto's Gen 2 decode (`sensor/v1new/`):

| `BikeMetrics` field | Formula | Note |
|---|---|---|
| `cadenceRpm` | `mRPM` | no scaling |
| `powerWatts` | `mPower / 100` | centi-watts -> watts (grupetto: `power / 100f`) |
| `resistancePercent` | `mCurrentResistance` (clamped 0..100) | no scaling |
| `speedMph` | `pelotonSpeedMphFromPower(watts)` | derived; service has no speed field |

### Speed

`PelotonSpeed.kt` implements the piecewise-cubic power->speed fit the PeloMon project
reverse-engineered from the stock bike's own curve
(<https://ihaque.org/posts/2020/12/25/pelomon-part-ib-computing-speed/>), the same one grupetto
uses. Input watts, output mph; clamped at 0.

## Connection state

- `Connected` — set only when the **first real frame** arrives (a successful bind that never
  delivers data does not masquerade as live).
- `Disconnected` — service disconnect or `onSensorError`.
- `Unavailable` — any bind failure, or before `start()`. On any non-bike device the service is
  absent and the source stays `Unavailable`; `start()` never throws (PRD P0-9).

## Reconstructed files

```
app/src/main/aidl/com/onepeloton/affernetservice/
    IV1Interface.aidl      IV1Callback.aidl       (Gen 2 path)
    IBikeInterface.aidl    IBikeCallback.aidl     (Bike+ path)
    BikeData.aidl          V3BikeData.aidl
app/src/main/java/com/onepeloton/affernetservice/
    BikeData.kt            V3BikeData.kt          (Parcelable wire layouts, shared)
app/src/main/java/dev/digitalducktape/openride/core/sensor/
    AffernetBikeDataSource.kt              (binds both, first frame wins)
    PelotonBikeDataSource.kt               (IV1Interface)
    PelotonBikeInterfaceDataSource.kt      (IBikeInterface)
    BoundBikeDataSource.kt                 (the seam that makes arbitration testable)
    BikeDataMapping.kt                     (BikeData -> BikeMetrics, shared by both)
    PelotonSpeed.kt
```

Building the real-sensor APK: the `debugReal` variant sets `USE_REAL_BIKE_SENSOR=true` (so
`AppContainer` wires `AffernetBikeDataSource`) and installs alongside the mock build via a
`.real` applicationId suffix — `./gradlew :app:installDebugReal`.

## On-device verification status

### Bike Gen 2 — `IV1Interface`

Target: `PLTN-RB1VQ`, Android 11, build `RQ.250113.A`.

**Confirmed on the physical bike, stationary, no rider** (via
`SensorBindingInstrumentedTest.bindsAndStreamsFramesOnBike`, run on-device):

- `AffernetService` is `exported=true` with no permission (APK manifest + `dumpsys package`),
  so binding needs no signature permission.
- **Bind succeeds** and `registerCallback` is accepted — the affernet service process (pid
  3693) holds our callbacks (`AffernetService$3`/`$4`), visible in its own logcat at teardown.
- **The service pushes real `BikeData` frames with no rider**, and the reconstructed AIDL +
  `BikeData` Parcelable decode them correctly. The decoded stationary idle frame pulled off the
  bike (`files/t3_verify.txt`):

  ```
  bound=true frames=1 state=Connected
  metrics=BikeMetrics(cadenceRpm=0, resistancePercent=1, powerWatts=0, speedMph=0.0)
  ```

  Cadence / power / speed are 0 (nobody pedaling, as expected) and `resistancePercent=1` is a
  live, non-zero reading of the current resistance-knob position — which is the key proof the
  `BikeData` field offsets are right (resistance is read from the correct place in the parcel,
  not garbage). `ConnectionState` reached `Connected` on the first frame.

  Note: `setFakeDataMode(true)` is *declined* by the service in this state (returns false), so
  verification relies on the real idle frames the service streams once a callback is registered,
  not on synthetic data.

**Confirmed with a rider pedaling** (90 s capture via `LivePedalStreamTest.recordLivePedalStream`,
full log at `docs/t3_live_pedal_capture.txt`) — this closes #3:

- **Cadence tracks pedaling**: `cadenceRpm` moved 21 → 40 → 66 → 78 → peaked **90 rpm** and
  varied back down with actual leg speed — not a static value.
- **Resistance tracks the knob**: `resistancePercent` swept 0 → 5 → 24 → **46** → 4 → ~40 →
  ~30 as the rider turned the knob.
- **Power tracks effort**: `powerWatts` rose with cadence *and* resistance together, peaking at
  **63 W** (cadence 78, resistance 32) and falling to 2–4 W when the rider eased off — the
  expected cadence×resistance relationship, confirming `mPower`'s centi-watt scaling.
- **89 frames over 90 s at ~1 Hz, `Connected` from the first frame, zero dropouts.**

Verified on `PLTN-RB1VQ` / build `RQ.250113.A`. The full field-offset reconstruction is therefore
correct under live load — T3/#3 is fully verified end-to-end.

The automated check is `app/src/androidTest/.../SensorBindingInstrumentedTest.kt`
(`./gradlew :app:connectedDebugAndroidTest`), portable: it self-skips the live assertions on any
device where the affernet service is absent, and treats stationary frame streaming as best-effort
(the bind is the hard assertion) so an asleep bike doesn't make it flaky.

### Bike+ — `IBikeInterface`

Target: `PLTN-TTR01`, board `topaz`, Android 10 (API 29), build `QT.250804.A`.

**First, the negative result.** `IV1Interface` does *not* work on this board. Run twice, once
stationary and once with a rider actively pedaling, both produced the same thing:

```
bound=true frames=0 state=Unavailable
metrics=BikeMetrics(cadenceRpm=0, resistancePercent=0, powerWatts=0, speedMph=0.0)
```

The bind lands and `registerCallback` is accepted, and no frame ever follows.
`setFakeDataMode(true)` returns false. Pedaling changes nothing, so this is not an asleep-bike
artifact. Corroborating evidence from `dumpsys activity services`: the stock Peloton software on
this board holds `IAffernetService` and `IBikeInterface` bound, and never `IV1Interface`.

**Confirmed with a rider pedaling** via `BikeInterfaceBindingInstrumentedTest`:

```
bound=true pushed=true pushFrames=108 state=Connected
poll1=BikeMetrics(cadenceRpm=82, resistancePercent=43, powerWatts=136, speedMph=18.36)
poll2=BikeMetrics(cadenceRpm=81, resistancePercent=43, powerWatts=134, speedMph=18.25)
poll3=BikeMetrics(cadenceRpm=84, resistancePercent=43, powerWatts=141, speedMph=18.62)
poll4=BikeMetrics(cadenceRpm=85, resistancePercent=43, powerWatts=142, speedMph=18.67)
poll5=BikeMetrics(cadenceRpm=84, resistancePercent=43, powerWatts=143, speedMph=18.73)
```

- **Both push and poll work.** 108 pushed frames in ~5 s (roughly 21 Hz), and `getBikeData`
  returns the same live values on demand.
- **Cadence tracks pedaling** across samples, and resistance holds steady at the knob position,
  so the `BikeData` field offsets are right on this board too — the same parcel layout, reached
  through a different binder.
- **Power is consistent with cadence and resistance** (134-143 W at 81-85 rpm and 43%),
  confirming the centi-watt scaling carries over unchanged.

End-to-end in the app, `AffernetBikeDataSource` adopts `IBikeInterface` ~70 ms after launch and
releases the V1 binding:

```
I AffernetBikeSource: sensor path adopted: IBikeInterface (releasing the other binding)
```

Because the board pushes, the poll fallback never engages here. It remains in place for a board
that binds and stays silent, which is exactly what `IV1Interface` does on this hardware.
