# Mini-games

OpenRide's games are a Godot project (`games/`) embedded in the Android app. Kotlin keeps
everything it already owns: sensors, session timing, ride recording, profiles and the hub UI.
Godot only renders the games and plays their audio. The design is epic
[#31](https://github.com/digitalducktape/openride/issues/31); this page covers the parts every
game and every builder depends on:

- the **Bridge contract** between Kotlin and Godot, which is the source of truth from here on;
- how the engine is hosted;
- how to build, run and debug the games.

## Layout

| Where | What |
| --- | --- |
| `games/` | The Godot 4.7.2 project (Compatibility renderer, 1920x1080, landscape) |
| `games/Main.tscn` | Main scene. For now it is a placeholder that shows the live input frame and drives the session lifecycle by hand. The framework (#34) replaces it. |
| `games/autoload/InputBus.gd` | Polls the input frame every frame, or runs the keyboard simulator |
| `games/autoload/Session.gd` | Session signals and methods, with JSON already parsed. On a desktop, `LocalSession.gd` plays a local plan. |
| `games/tests/` | Headless checks (not exported) |
| `games/assets/SOURCES.md` | Source, author and licence of every asset |
| `app/.../games/GameHostActivity.kt` | Hosts the engine |
| `app/.../games/bridge/` | The `OpenRideBridge` plugin, the app-scoped `GameBridge`, the input frame and the JSON messages |
| `app/.../games/session/StubGameSession.kt` | Walks a plan over the bridge without recording anything, until `GameSessionManager` (#35) replaces it |

Games talk to Kotlin only through the `InputBus` and `Session` autoloads, never through the
`OpenRideBridge` singleton directly.

## Bridge contract (`OpenRideBridge`, v1)

Every game and both sides of the bridge are built against this contract, so parallel work agrees.
GDScript accesses it only through the `InputBus` and `Session` autoloads, never directly.

**Input frame — polled by `InputBus` every frame** via `get_input_frame(): PackedFloat64Array`:

| Index | Field | Units / range |
| --- | --- | --- |
| 0 | `version` | `1` |
| 1 | `cadence` | rpm |
| 2 | `power` | watts |
| 3 | `resistance` | 0-100 |
| 4 | `speed` | mph (existing derived speed) |
| 5 | `heart_rate` | bpm, `-1` if no strap |
| 6 | `lean_x` | -1 (rider's left) .. +1 (right), filtered, calibrated |
| 7 | `lean_depth` | -1 (back) .. +1 (in), filtered; `0` when disabled |
| 8 | `standing` | 0 / 1 |
| 9 | `tracker_state` | 0 off · 1 needs calibration · 2 calibrating · 3 tracking · 4 face lost |
| 10 | `segment_time_left` | seconds, from Kotlin's clock |
| 11 | `sensors_ok` | 0 / 1 (`ConnectionState.Connected`) |

**Kotlin → Godot signals:**

- `session_started(plan_json)`: `{kind: circuit | just_ride, plan_id, difficulty, total_sec,
  segments:[{game_id, role, duration_sec}]}`. Sent once; it drives the circuit progress strip.
- `segment_started(segment_json)`: `{index, count, game_id, duration_sec, intro_sec, end_mode, role,
  difficulty, effort, seed, audio:{music, music_volume, sfx_volume}, params:{…}}`.
  - `intro_sec`: Godot shows the intro card for this long (10 s in circuits and at session start),
    then gameplay begins. `segment_time_left` counts down gameplay time only.
  - `end_mode`: `timer` means Kotlin ends the segment at `duration_sec`. `game` means the game ends it
    by calling `segment_finished` (e.g. Kart Race finishing on a lap line); Kotlin still hard-stops at
    1.5 × `duration_sec`.
  - `duration_sec` is `-1` for an open-ended Just Ride, which ends only through `request_end`.
  - `role` ∈ `warmup | work | recovery | cooldown | free` (`free` = Just Ride).
  - `difficulty` ∈ `easy | standard | hard`.
  - `effort`: whether the effort multiplier applies. True for work segments, and for Just Rides of
    games that declare `effort_in_just_ride` (Dodge Ball, Tug of War, Kart Race).
  - `audio.music` is false when the rider's own music is playing or game music is turned off.
  - `params` are game-specific and already scaled to FTP and difficulty by Kotlin.
- `segment_ending()`: the timer ran out. The game must call `segment_finished` within 5 s, or Kotlin
  records a zero-score result.
- `session_paused()`, `session_resumed()`: from auto-pause on freewheel or a rider's pause request.
- `calibration_progress(step, fraction, step_index, step_count, attempt, retry_reason)`: drives the
  calibration UI, sent as the head tracker's calibration advances (while `tracker_state` is 2).
  - `step` ∈ `centre | left | right | in | back`: the pose to hold ("sit centred", "lean
    left", "lean right", and for `lean_2d` "lean in", "sit back").
  - `fraction`: 0..1 through the current step. It restarts from 0 on a retry.
  - `step_index`, `step_count`: the step's 0-based position in this calibration. `step_count`
    is 1 when only the centre is re-taken (the rider's extremes from earlier today are reused),
    3 for `lean_x` and 5 for `lean_2d`.
  - `attempt`: 1 for the first try at this step, then 2, 3… on retries.
  - `retry_reason`: `""` on a first attempt, otherwise why the step is repeated: `unstable`
    (hold still), `no_face` (look at the screen), `too_small` (lean a bit further) or
    `wrong_direction`.
  - `used_default`: the step failed 3 times, so it won't be retried again. Calibration uses the
    rider's previous value for it (or a default lean) and moves on after this is shown for 1.5 s
    (`fraction` counts through that). Say so, e.g. "Using your usual lean — recalibrate any
    time". No-face failures don't count towards this: two of those end calibration as
    unavailable, as before.
  - Calibration has ended when `tracker_state` leaves 2: 3 (tracking) on success, or 0 when the
    camera is unavailable (no face found after two tries).
- `session_finished(summary_json)`: `{ride_id, results:[…], totals, bests:{…}}`, sent after Kotlin has
  saved the ride. Godot shows the summary, then calls `request_exit()`.

**Godot → Kotlin methods:**

- `segment_finished(result_json)`: `{game_id, score, stars (0-3), won (bool|null), skipped (bool),
  stats:{effort_avg, …}}`. A skip is reported as `skipped: true` during the intro card; Kotlin then
  advances to the next segment.
- `request_calibration(mode)`: `mode` ∈ `lean_x | lean_2d`. The rider asked to recalibrate:
  every step runs again.
- `set_tracker_mode(mode)`: `off | lean_x | lean_2d | lean_stand`, sent by `Session` from each game's
  declaration. The camera only runs when not `off`. The first camera mode of a session starts a
  calibration by itself (see "Head tracker" below).
- `request_pause()`, `request_resume()`: the rider's pause button.
- `request_end()`: the rider ends the session (early, or an open-ended Just Ride). Kotlin stops and saves
  the ride, then sends `session_finished`.
- `request_exit()`: after the summary; the host finishes back to the app.

**Sensor loss:** while `sensors_ok` is 0, games freeze scoring and show the "sensors not detected"
banner. The ride keeps recording exactly as it does today.

**Desktop simulation:** when the `OpenRideBridge` singleton is absent (the editor on a Mac), `InputBus`
synthesises frames from the keyboard and `Session` plays a local plan (a Just Ride of the open game by default). Arrows = lean x, W/S = lean
depth, `+`/`-` = cadence, `[`/`]` = resistance, Space = stand, P = pause, Esc = end session. Every game must be fully
playable this way.

**Head tracker** (`core/camera/`, #33), as the bridge sees it:

- Fields 6-9 always show the tracker's latest state. They read `0`, with `tracker_state` 0 (off),
  whenever the camera isn't running.
- Every session starts by forgetting the last session's centre. The centre is re-taken in every
  session, because a silently off-centre calibration was the camera spike's worst failure.
- The first `set_tracker_mode` with a camera mode in a session starts a calibration at once
  (`tracker_state` 2). It re-takes only the centre (3 s) if the rider's lean extremes were
  measured earlier the same day, otherwise every step (about 8 s for `lean_x`). Later camera
  games in the session track straight away.
- `lean_2d` games that want depth call `request_calibration("lean_2d")`, unless depth was
  calibrated earlier. Without depth extremes `lean_depth` reads 0 and left/right still work.
- A calibration can't run away: each step gets at most 3 attempts before it falls back
  (`used_default`). The worst case for `lean_x` is about 28 s. The fallback values are used but
  never saved as the rider's.
- The camera stops when the session finishes or the rider leaves games.
- Face lost: the lean holds for 0.5 s, then eases to centre, and `tracker_state` becomes 4 after 3 s.
  Standing needs 0.5 s to enter and 1.5 s to leave.

### Implementation notes

These describe how the foundation (#32) implements v1. They don't change the contract.

- **Wire format.** Each JSON payload is one `String` argument, and `Session` parses and
  stringifies it. Godot's JSON parser returns every number as a float (`1.0`), so Kotlin
  accepts whole numbers written either way (`"stars": 3.0`).
  - `calibration_progress` is `(String, float, int, int, int, String)`.
  - Plugin method names are the contract's snake_case names.
- **Readiness.** The contract has no "ready" method. Kotlin sends `session_started` after the
  first `get_input_frame()` poll once a session is attached. By then the autoloads' `_ready`
  has run, so their signal handlers are connected.
- **Open-ended segments** (`duration_sec: -1`) report `segment_time_left = -1`.
- **After the last segment:**
  - A timed plan finishes by itself.
  - An open-ended plan waits for `request_end`.
  - A `request_end` during a segment sends `segment_ending`. The session then finishes when the
    result arrives, or after the 5 s grace period.
- **Early exit.** A `request_exit` before the summary finishes the session first.
- **Android back button:**
  - It never quits (`application/config/quit_on_go_back=false`).
  - During a session it calls `request_pause()`.
  - After the summary it calls `request_exit()`.
- **The stub.** Until #35, `StubGameSession` plays an open-ended Just Ride of the `placeholder`
  game. It sends `ride_id: null` and records nothing. Its tracker commands go through
  `TrackerLink` (`games/bridge/`), which `GameSessionManager` should reuse.
- **Head-tracker fields** come from `AppContainer.headTracker` on every poll
  (`HeadTrackerState.toTrackerReading()`).

## Hosting the engine

`GameHostActivity` extends Godot's `GodotActivity`:

- It is landscape, keeps the screen on and hides the system bars.
- It loads the pack with `--main-pack res://games.pck`.
- It registers the `OpenRideBridgePlugin` host plugin (`Engine.get_singleton("OpenRideBridge")`).

**Godot runs one engine per process, and it can't be restarted.** This was checked on the bike
(Godot 4.7.2). Finishing the host activity destroys the engine. Godot then calls
`ProcessPhoenix.forceQuit`, which kills the whole app process, including a ride in progress.
So the foundation uses the spec's fallback: **the host stays alive for the app's lifetime.**

- The host runs in its own task (`taskAffinity=${applicationId}.games`, `singleTask`).
- `request_exit()` moves that task to the back, which returns the rider to the Compose app.
  The next entry brings the same instance forward (`onNewIntent`) and attaches a fresh session.
- Godot keeps the first plugin instance it registered. So all per-session state lives in the
  app-scoped `GameBridge` (`AppContainer.gameBridge`), never in the plugin.
- The scene tree also persists between entries. Games must reset on `session_started`, not in
  `_ready`.
- Never call `get_tree().quit()`. It ends the engine and the process with it.
- Checked on the bike: 5 × (enter → full lifecycle → exit → back in the app), all in one
  process at 60 fps.
- The game task is deliberately **not** `excludeFromRecents`. When the display times out (30
  min), Peloton's software launches its own `SetupActivity` in a new task. With the game task
  excluded from recents, the system removed it at that moment, and the process died with it.
  Without the flag, the game task and the app survived the same timeout on the bike.
- Anything that removes the background game task still ends the whole process, for example
  swiping it away in recents (the bike has no recents button). Later issues (#35, #38) should
  treat this as a known risk.

The `OpenRideApplication` owns the `AppContainer`, so the games host shares the app's database,
sensor binding and ride session.

The Godot AAR declares androidx `FileProvider` at `${applicationId}.fileprovider`, and Godot's
`GodotIO` hard-codes that authority. So the app's own provider is the `OpenRideFileProvider`
subclass at `${applicationId}.files`, and each provider keeps its own paths file.

## Setting up

1. **Install Godot 4.7.2.** It must be exactly the release of the `org.godotengine:godot`
   library in `gradle/libs.versions.toml`, and the build checks this. Run
   `brew install --cask godot`, or download it from the
   [Godot archive](https://godotengine.org/download/archive/).
2. **Point the build at it.** Set `GODOT_BIN` to the editor binary:
   ```sh
   export GODOT_BIN=/Applications/Godot.app/Contents/MacOS/Godot
   ```
   You can also add `godot.bin=/Applications/Godot.app/Contents/MacOS/Godot` to
   `local.properties`, which helps when Android Studio doesn't see your shell's environment.
3. **Keep Godot from killing adb.** In the Godot editor, open **Editor Settings →
   Export → Android** and turn off **Shutdown ADB on Exit**
   (`export/android/shutdown_adb_on_exit = false`). Otherwise every export stops the adb
   server and drops the bike's wireless connection.

## Building

The Gradle task `exportGamesPack` runs `$GODOT_BIN --headless --path games --import`, then
`--export-pack Android games.pck`. Every variant's assets include the result, so it runs
before asset merging.

**Only builds that package an APK or bundle need Godot:** `assemble*`, `install*`, `bundle*`,
or `exportGamesPack` by name. In those builds the task fails with setup instructions if
`GODOT_BIN` is missing or the version doesn't match. Unit tests don't need the pack, so a
build without packaging skips the export. A contributor without Godot can still run
`./gradlew :app:testDebugUnitTest`.

`games.pck` and `games/.godot/` are git-ignored.

```sh
./gradlew :app:assembleDebugReal   # bike build; exports the pack first
./gradlew :app:exportGamesPack     # just the pack (app/build/generated/assets/exportGamesPack/)
./gradlew :app:testDebugUnitTest   # no Godot needed
```

Packaging:

- Bike builds (`debugReal`, `release`) ship arm64-v8a only. The mock `debug` build adds x86_64
  for emulators.
- Native libraries are stored compressed (`useLegacyPackaging`), so the self-updater's
  download stays small.
- The engine adds about 27 MB to the compressed APK (26.4 MB of it is `libgodot_android.so`):
  `debugReal` went from 27.2 MB to 54.3 MB
  (see the #32 PR). Installed, it takes about 70 MB.

## Running on a desktop

Open `games/project.godot` in the Godot 4.7.2 editor and press Play. With no bridge present,
`InputBus` shows "keyboard simulator" and `Session` starts a local Just Ride.

| Key | Input |
| --- | --- |
| Left / Right | lean x |
| W / S | lean depth |
| `+` / `-` | cadence |
| `[` / `]` | resistance |
| Space | stand (toggle) |
| P | pause / resume |
| Esc | end session |

On a desktop, `request_exit()` restarts the local plan. A scene run on its own (F6) that
declares a `game_id` property gets a Just Ride of that game.

To check the simulator headless (session lifecycle, then the keys above through injected key
events):

```sh
$GODOT_BIN --headless --path games -s res://tests/sim_lifecycle_check.gd
$GODOT_BIN --headless --path games -s res://tests/sim_keyboard_check.gd
```

## Running on the bike

1. Install with `adb install -r app/build/outputs/apk/debugReal/app-debugReal.apk`. The `-r`
   keeps the rider's data, so never uninstall.
2. On the tablet, open **Profile → Mini-games (preview)**. The Games hub (#38) replaces this
   entry point.
3. The placeholder's **Camera** button switches the head tracker between `off` and `lean_x`,
   which calibrates on first use. The camera needs the CAMERA permission. Until the hub asks
   for it (#38), grant it with
   `adb shell pm grant dev.digitalducktape.openride.real android.permission.CAMERA`.

### Capturing logs on the bike

The tablet logs at level W (`getprop log.tag` prints `W`), so every app `Log.i`/`Log.v` and
every Godot `print` is dropped unless its tag is raised. Four things have silently lost a
capture:

- **`log.tag.*` doesn't survive a reboot.** Set the tags after every boot, and check them with
  `getprop`. No app restart is needed: the app and Godot re-check the tag on every line.
- **The ring buffer is 256 KiB, and logd prunes the chattiest app first.** With
  `HeadTrackerFrames` on (30 lines a second), OpenRide is the chattiest app, so a capture taken
  with `logcat -d` after the ride can contain only other apps' W lines. Enlarge the buffer, and
  record while riding.
- **A live `adb logcat` over wireless ADB stops when ADB drops.** Record to a file on the
  tablet instead.
- **`HeadTrackerFrames` exists only in debuggable builds** (`debugReal`, `debug`). A release
  build never writes it.

The recipe, in order:

```sh
# 1. After every boot: raise the tags, then confirm they're set.
adb shell setprop log.tag.godot VERBOSE
adb shell setprop log.tag.OpenRideGames VERBOSE
adb shell setprop log.tag.HeadTracker VERBOSE
adb shell setprop log.tag.HeadTrackerFrames VERBOSE   # per-frame raw/filtered lean + face row
adb shell getprop | grep log.tag

# 2. A bigger ring buffer.
adb logcat -G 16M

# 3. Record on the tablet, so a dropped ADB connection doesn't end the capture.
adb shell 'nohup logcat -v threadtime -f /sdcard/Download/openride-run.log -r 8192 -n 8 \
  godot:V OpenRideGames:V HeadTracker:V HeadTrackerFrames:V GodotActivity:V "*:S" \
  > /dev/null 2>&1 &'

# ... ride ...

# 4. Stop the recorder and pull the files (openride-run.log, .1, .2, ...).
adb shell pkill -f openride-run.log
for f in $(adb shell ls /sdcard/Download/ | grep openride-run.log); do adb pull "/sdcard/Download/$f"; done
```

To follow along live instead, run `adb logcat -s godot OpenRideGames HeadTracker`. It stops
if ADB drops, so keep the on-tablet recorder running too.

`HeadTrackerFrames` lines carry `fixture=<row>` in the `HeadFixtureCsv` format. Collect those
rows into a CSV file under `app/src/test/resources/headtracker/` to replay the ride in the unit
tests.

What to look for in the log:

- Every signal and call is logged as `OPENRIDE_GAMES <- signal` or `OPENRIDE_GAMES -> method`.
- The placeholder prints an `OPENRIDE_GAMES frame fps=… cadence=…` line every 5 s.
- `OpenRideGames` lines come from the Kotlin side of the session.

## Originality and licensing

Everything under `games/` is written for this project or permissively licensed. Assets are
listed in `games/assets/SOURCES.md` and third-party code in `THIRD_PARTY_NOTICES.md`; the rule
itself is in the epic (#31). No game may use another game's names, characters, art, UI look,
audio or trademarks.
