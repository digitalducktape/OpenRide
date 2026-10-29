# Mini-games

OpenRide's games are a Godot project (`games/`) embedded in the Android app. Kotlin keeps
everything it already owns: sensors, session timing, ride recording, profiles and the hub UI.
Godot only renders the games and plays their audio. The design is epic
[#31](https://github.com/digitalducktape/openride/issues/31); this page covers the parts every
game and every builder depends on:

- the **Bridge contract** between Kotlin and Godot, which is the source of truth from here on;
- how the engine is hosted;
- the **framework** every game is built on, and how to add a game;
- the **AudioDirector** interface the audio generators plug into;
- how to build, run, test and debug the games.

## Layout

| Where | What |
| --- | --- |
| `games/` | The Godot 4.7.2 project (Compatibility renderer, 1920x1080, landscape) |
| `games/hub/` | The Games hub (`Hub.tscn`): the project's main scene and the idle scene, where the rider picks and starts plans. See "The Games hub on screen". |
| `games/autoload/Stage.gd` | The centred 1920x1080 stage on a wider window (#57): shifts the canvas and layers, and stretches backdrops, shades and 3D views to the whole window |
| `games/autoload/InputBus.gd` | Polls the input frame every frame, or runs the keyboard simulator |
| `games/autoload/Session.gd` | Session signals and methods, with JSON already parsed. Its `SessionDirector` child runs the session on screen. On a desktop, `LocalSession.gd` plays a local plan, and its `LocalHub.gd` plays the hub's visit. |
| `games/autoload/Effort.gd` | Scoring with the effort multiplier: games award points only through it |
| `games/autoload/AudioDirector.gd` | Buses, music stems, effects and cues; the generators (#36) register with it |
| `games/framework/` | `Game` (the base class), `GameInfo` (declarations), `SessionDirector`, `EffortMeter`, `Stars`, the HUD kit (`hud/`) and the intro card, pause, calibration and summary screens (`ui/`) |
| `games/audio/` | Generated audio (#36): `SfxSynth` effects, `MusicGen` music, the styles, and `Cues.gd`, which registers them with `AudioDirector`. See "Generated audio". |
| `games/games/` | One folder per game, and `Registry.gd`, which lists them. `demo/` is the reference game. |
| `games/tests/unit/` | GdUnit4 suites (not exported) |
| `games/tests/sim_*.gd` | Headless desktop playthroughs (not exported) |
| `games/addons/gdUnit4/` | GdUnit4 6.2.1 (MIT), vendored for the tests (not exported) |
| `games/assets/SOURCES.md` | Source, author and licence of every asset |
| `app/.../games/GameHostActivity.kt` | Hosts the engine |
| `app/.../games/bridge/` | The `OpenRideBridge` plugin, the app-scoped `GameBridge`, the input frame and the JSON messages |
| `app/.../games/session/` | `GameSessionManager` (runs and records sessions), `SessionPlan` and its builders, `GameCatalog` (Kotlin's copy of each game's declarations), `GameAudioPrefs` |

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
| 11 | `sensors_ok` | 0 / 1: 0 once the app's one "sensors offline" rule says so (`AppContainer.sensorsOffline`: not Connected, or no frames, for 10 s; issue #56), the same moment as the top bar's notice |
| 12 | `rider_music` | 0 / 1: the rider's own music app has a track, so game music stays off. Added after v1 at the end, so the version stays `1`; `InputBus` reads it only when the frame has it |
| 13 | `controller_steer` | -1 (left) .. +1 (right): an OpenBikeControl controller's steering (#68); `0` while none steers |
| 14 | `controller_steering` | 0 / 1: a connected controller steers. Games that steer by lean use `InputBus.steer_x()`, which is field 13 while this is 1 and `lean_x` otherwise, so a shifter-only controller never takes the steering |
| 15 | `controller_item_presses` | how many times a controller's Use item (Power-up 1-3) has been pressed since the app started. A count, so no press between two polls is lost; `InputBus` emits `controller_item` when it goes up, and takes the first frame's value as its baseline. Fields 13-15 were added after v1 like field 12; `InputBus` reads them only when the frame has them |

**Kotlin → Godot signals:**

- `session_started(plan_json)`: `{kind: circuit | just_ride, plan_id, difficulty, total_sec,
  segments:[{game_id, role, duration_sec}]}`. Sent once; it drives the circuit progress strip.
  `total_sec` includes every intro card, and is `-1` for an open-ended plan.
  - `rider_id`: the active rider's profile id, or null with no active rider. It was added after
    v1 shipped and is optional; games use it only to remember their options per rider
    (`GameOptions`).
  - `rider_name`: the active rider's profile name, trimmed, or null with no active rider or a
    blank name. Also added after v1 and optional (a game must cope with it missing).
    `Session.rider_name()` returns it ("" when absent); the desktop's `LocalSession` sends
    "Alex" unless its plan names someone. Kart Race puts it on the rider's kart
    (`KartRoster.rider_label`: at most 12 characters with an ellipsis, "You" when empty).
    Kotlin fills it from the active profile (`GameSessionManager`'s `profileName`).
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
  - `audio`: `{music, music_volume, sfx_volume}`. `music` is the hub's Game music switch; even
    on, game music stays off while the rider's own music plays (frame field 12, live; see
    **Audio** below).
  - `params` are game-specific and already scaled to FTP and difficulty by Kotlin.
- `segment_ending()`: the timer ran out. The game must call `segment_finished` within 5 s, or Kotlin
  records a zero-score result.
- `session_paused()`, `session_resumed()`: from auto-pause on freewheel, a rider's pause request,
  or a running calibration. Kotlin pauses the session for any calibration (the automatic one,
  a requested one or the depth one) from its start until it completes, falls back
  (`used_default`) or ends unavailable, then resumes by itself. The ride keeps recording through
  a calibration pause. A rider's pause outlasts a calibration that ends under it.
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
  - `ride_id` is null when nothing was recorded (no active rider, or another ride in progress).
  - `results` are the `segment_finished` payloads in plan order, with zero results for games
    that didn't report.
  - `totals`: `{score, stars, segments, elapsed_sec}`; `elapsed_sec` is the ride's duration.
  - `bests`: `{"score": true}` and/or `{"stars": true}` when the session's total beat the rider's
    best at the same plan and difficulty (a first scoring session counts); `{}` otherwise.

**Godot → Kotlin methods:**

- `segment_finished(result_json)`: `{game_id, score, stars (0-3), won (bool|null), skipped (bool),
  stats:{effort_avg, …}, variant}`. `variant` is optional (`""`): a game's own variant, such as
  Dodge Ball's `catch` mode. (Before the hub work Kotlin never read it, so every result was
  recorded with `""`; fixed in v1.1.) A skip is reported as `skipped: true` during the intro card; Kotlin then
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

**Controllers (#68):** OpenBikeControl controllers (shifters, buttons, BikeControl on a phone)
reach the games through fields 13-15 above and through Kotlin. Pause and Resume call the
session's pause and resume as `request_pause()` / `request_resume()` would
(`ControllerRouter`), so games need nothing for them. Kart Race steers with `InputBus.steer_x()`
and fires its item on `InputBus.controller_item`.

**Sensor loss:** while `sensors_ok` is 0, games freeze scoring and show the "sensors not detected"
banner. The ride keeps recording exactly as it does today.

**Desktop simulation:** when the `OpenRideBridge` singleton is absent (the editor on a Mac), `InputBus`
synthesises frames from the keyboard and `Session` plays a local plan (a Just Ride of the open game by default). Arrows = lean x, W/S = lean
depth, `+`/`-` = cadence, `[`/`]` = resistance, Space = stand, P = pause, Esc = end session. Every game must be fully
playable this way.

**Head tracker** (`core/camera/`, #33), as the bridge sees it:

- Fields 6-9 always show the tracker's latest state. They read `0`, with `tracker_state` 0 (off),
  whenever the camera isn't running.
- Every **visit** starts by forgetting the last visit's centre (`TrackerLink.startVisit`). The
  centre is re-taken once per visit, because a silently off-centre calibration was the camera
  spike's worst failure; plans within a visit share it (the Games hub, spec §6).
- The first `set_tracker_mode` with a camera mode in a visit starts a calibration at once
  (`tracker_state` 2). It re-takes only the centre (3 s) if the rider's lean extremes were
  measured earlier the same day, otherwise every step (about 8 s for `lean_x`). Later camera
  games in the visit, in this plan or a later one, track straight away.
- From the hub, `hub_calibrate(mode, full)` turns the camera on and calibrates (`full` forces
  every step); the camera turns off again when that calibration ends, however it ends, or on
  `cancel_calibration`. Between plans the camera is off too (`TrackerLink.planEnded`, which
  keeps the centre). `hub_state.camera.calibrated` and `session_started.calibrated` say what
  the visit's calibration covers: `""`, `lean_x`, or `lean_2d` once a depth calibration has
  completed.
- `lean_2d` games that want depth call `request_calibration("lean_2d")`, unless depth was
  calibrated earlier. Without depth extremes `lean_depth` reads 0 and left/right still work.
- A calibration can't run away: each step gets at most 3 attempts before it falls back
  (`used_default`). The worst case for `lean_x` is about 28 s. The fallback values are used but
  never saved as the rider's.
- The camera stops between plans and when the visit ends (`TrackerLink.endVisit`, which also
  forgets the centre).
- Face lost: the lean holds for 0.5 s, then eases to centre, and `tracker_state` becomes 4 after 3 s.
- Looking away counts as face lost. The detector often keeps the face when the rider turns the head
  from the screen. So a face frame counts as turned away when either:
  - its yaw is more than 25° outside the range seen during calibration (turning right), or
  - its pitch estimate is more than 20° above the calibrated centre (turning left distorts
    the keypoints this way instead).

  A face more than 0.1 of the frame height below the centre is exempt, so looking down at the
  bike doesn't count. When 60% of the last 500 ms of face frames are turned away, steering
  holds and eases to centre, and `tracker_state` becomes 4 as above. It resumes once the rider
  has faced the screen for 300 ms.
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
- **The session engine** is the Games hub visit, `GameVisitManager` (app-scoped), which hands
  each plan to the plan runner, `GameSessionManager`. Tracker commands go through
  `TrackerLink` (`games/bridge/`). See "Sessions and recording" below.
- **Head-tracker fields** come from `AppContainer.headTracker` on every poll
  (`HeadTrackerState.toTrackerReading()`).

### Games hub (v1.1)

The Games hub (spec `docs/superpowers/specs/2026-10-19-games-hub-design.md`, §3) adds to v1
without changing it: every v1 signal and method keeps its name, arguments and meaning *within a
plan*. In a hub visit, `session_*` means "one plan", and the visit holds many plans. The input
frame stays version 1. Kotlin accepts floats for integers and ignores unknown keys; Godot treats
a missing key as its default. `Session` re-emits the new signals with the JSON parsed, and
connects them only if the plugin declares them (so a pack run against an older app still
starts).

**Kotlin → Godot signals (new):**

- `hub_state(state_json)`, as `Session.hub_state_changed(state)`, kept in `Session.hub`: a full
  snapshot every time, never a delta. It is sent on the first input-frame poll of a visit (the
  v1 readiness rule), then after anything in it changes, at most once per 250 ms.
  - `hub_version` (1), `visit_id` (new per visit; `Session.visit_changed` fires on a change),
    `phase` (`hub | plan | saving | ended`).
  - `rider`: `{id, name, avatar_png, avatar_color, ftp_watts, ftp_is_default}`. With no active
    rider, `id` is null and `name` is `""`. `avatar_png` is a 256×256 PNG path, or null.
  - `settings`: `{camera_games, game_music, music_volume, sfx_volume}`; `audio`: the same as a
    segment's (`{music, music_volume, sfx_volume}`), for the hub's own music.
  - `camera`: `{permission: granted | denied | ask, available, calibrated: "" | lean_x |
    lean_2d, same_day_extremes}`.
  - `catalog`: `[{id, title, supports, min_sec, max_sec, min_rounds, max_rounds, round_sec,
    roles, uses_camera, minute_steps, circuit_role}]`, `GameCatalog` without the demo.
  - `circuits`: `[{id, minutes, total_sec, slots: [{game_id, role, duration_sec}]}]`, the
    presets as they would play now (with the camera-off substitution applied).
  - `bests`: `{games: [{game_id, plan_id, difficulty, variant, score, stars, plays}], plans:
    [{plan_id, difficulty, score, stars}]}`, with this visit's finished plans merged in.
  - `visit`: `{recording, ride_sec, gameplay_sec, plans: [{plan_id, difficulty, score, stars,
    game_ids}]}`.
- `plan_rejected(reason_json)`: `{request (as sent), reason: unknown_game | unsupported_mode |
  camera_unavailable | busy | empty_circuit | too_long}`, sent instead of `session_started`.
- `now_playing(json)` (v1.3), as `Session.now_playing_changed(track)`, kept in
  `Session.now_playing`: the rider's music app's track for the music panel, `{title, artist,
  art, playing, can_previous, can_next}` (`art` a PNG path in the app's cache, or ""), or `{}`
  with nothing. Sent when it changes, and again on the first input-frame poll after a session
  attaches (the engine drops signals sent before it runs). Guarded with `has_signal`.
- `visit_ended(result_json)`: `{visit_id, ride_id (or null), saved, discarded_reason: "" |
  too_short | no_pedalling | not_recording, next: app | edit_profile | hub, reason: exit | idle |
  app_resumed | replaced}`. Sent after the ride is saved or discarded. Godot calls nothing after
  it, except that with `next: hub` (the idle guard saved the ride while the hub showed) a tap
  sends `hub_activity()`, which starts a new visit.

**Changes to v1 payloads (additive, only in a visit):**

- `session_started` adds `visit_id`, `plan_index` (0-based count of plans started this visit)
  and `calibrated` (the visit's calibration, as in `hub_state.camera`).
- `session_finished` adds `visit_id`, `plan_index`, `plan_id` and `difficulty`, and its
  `ride_id` is always null: the ride is saved on exit and its id comes in `visit_ended`.
  `totals.elapsed_sec` is the plan's own seconds (pauses excluded).
- Outside a visit none of these keys is sent.

**Godot → Kotlin methods (new):**

| Method | Valid in | Kotlin does |
| --- | --- | --- |
| `start_plan(request_json)` | hub | Builds and runs the plan (`session_started` …), or sends `plan_rejected` |
| `update_setting(key, value_json)` | any | `camera_games` (bool), `game_music` (bool), `music_volume`, `sfx_volume` (0..1, clamped); stores it, then `hub_state`. Unknown keys and bad values are logged and ignored. |
| `hub_calibrate(mode, full)` | hub | Camera on, calibrate (`force = full`), camera off when it ends; `calibration_progress`, then `hub_state`. The hub sends `lean_x`, with `full` false until the visit is calibrated (centre only with today's extremes) and true after (Recalibrate). |
| `cancel_calibration()` | hub | Stops a hub calibration; the visit's earlier calibration stays |
| `request_camera_permission()` | hub | The host shows Android's prompt, then `hub_state` |
| `exit_hub(next)` | hub | `app` or `edit_profile`: ends the visit, saves, `visit_ended`, task to back |
| `show_loading(show)` | any | v1.2: the host covers the engine with its native loading screen (it keeps animating while the GL thread is blocked). `SessionDirector` raises it at `segment_started` and drops it once the game has drawn 3 frames, covering the first-frame shader compile |
| `hub_activity()` | hub | The rider touched the hub (at most once per 60 s): resets the idle guard |
| `music_control(action)` | any | v1.3, the music panel: `play_pause`, `next` or `previous`, sent to the rider's music app as a media button (`NowPlayingFeed`). Unknown words are logged and ignored |

`start_plan` requests: `{kind: "just_ride", game_id, mode: minutes | rounds | open, length,
difficulty}`, `{kind: "circuit", preset_id, difficulty}` or `{kind: "custom", difficulty, slots:
[{game_id, duration_sec}]}`. A missing `difficulty` is `standard`.

`request_exit()` in a visit: in the hub it means `exit_hub("app")`. During a plan it ends the
plan at once and then the visit (v1's "early exit"). The hub's result card returns to the hub
locally and must **not** call it.

## Hosting the engine

`GameHostActivity` extends Godot's `GodotActivity`:

- It is landscape, keeps the screen on and hides the system bars.
- It loads the pack with `--main-pack res://games.pck`.
- It registers the `OpenRideBridgePlugin` host plugin (`Engine.get_singleton("OpenRideBridge")`).
- No Godot splash (#45). `games/project.godot` turns the boot splash image off and sets its
  colour and the default clear colour to the app background (`#0C0C0E`). The host's theme
  (`Theme.OpenRide.GameHost`) uses the same window background. On the engine's first start,
  `GameHostActivity` covers it with a plain "Loading games…" view, which it removes in
  `onGodotMainLoopStarted` (the main scene is loaded and about to draw). Re-entry skips it,
  because the engine is already running. Cold entry on the bike takes about 4.8–5 s from tap to
  the main scene, with or without the view.

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

`GameHostActivity.intent(context)` opens the Games hub: each entry calls
`GameVisitManager.begin` and attaches the visit to the bridge. A visit still live when the host
comes forward again (the rider never reached the app) is kept, and its `hub_state` resent.

- The app's only way in is `launchGames(context)` (`ui/games/GamesLauncherScreen.kt`), from
  the Games tab and the Home card. It carries no request: the rider picks in the hub.
- `EXTRA_AUTOSTART` (dev, adb and headless checks) starts a `start_plan` request (its
  snake_case JSON) as soon as the hub is up. Nothing else outside `games/` builds a
  `SessionRequest`.
- `request_camera_permission` shows Android's prompt from the host
  (`requestPermissions` → `GameVisitManager.onPermissionResult` → `hub_state`). A refusal
  Android won't ask again reads as `denied`.
- Leaving (`exit_hub` / `request_exit`) moves the task to the back once the ride is saved.
  `VisitNavigator` (app-scoped, consumed once by the NavHost) then opens the ride summary, or
  the profile editor for `exit_hub("edit_profile")`.
- `MainActivity.onResume` calls `endIfLive("app_resumed")`, so no visit stays live behind the
  app.

## Sessions and recording

Since the Games hub, entering games starts a **visit** (`GameVisitManager`,
`app/.../games/session/`), and a visit plays any number of **plans** (a Just Ride, a circuit or
a custom circuit), each run by the plan runner (`GameSessionManager`, #35). Both are app-scoped,
so a ride is saved even after the host has gone to the back. **One visit records as one ride.**

- Phases: `IDLE → WAITING → HUB ⇄ PLAN → SAVING → ENDED`. The first frame poll sends
  `hub_state`; `start_plan` is valid only in `HUB` (else `plan_rejected: busy`).
- The runner walks one plan: `session_started`, segments, intro cards, the end modes, the grace
  period and pauses, as below. It no longer touches the ride beyond pausing it for the rider
  (`PlanRide`), and it hands its results to the visit, which sends `session_finished`.
- `HubStateBuilder` builds `hub_state` (a pure function); the visit coalesces sends to one per
  250 ms. `BitmapAvatarRenderer` draws the rider's avatar into
  `cacheDir/games/avatar_<id>.png` once per visit.

**Plans.** When a plan starts, the visit turns the request into a `SessionPlan` with the active
rider's FTP (`SessionPlans`):

| Request | Plan (`plan_id`, also `Ride.gamePlan`) | Segment |
| --- | --- | --- |
| Just Ride, timed N min | `just-ride:<game>:minutes:<N>` | `role: free`, N × 60 s, the game's `timedEndMode` (normally `timer`) |
| Just Ride, N rounds | `just-ride:<game>:rounds:<N>` | `role: free`, N × the game's `roundSec`, `end_mode: game`, `params.rounds = N` |
| Just Ride, open-ended | `just-ride:<game>:open` | `role: free`, `duration_sec: -1`, `end_mode: game` |
| Circuit | `circuit-20`, `circuit-30`, `circuit-45` | the preset's slots (`CircuitPresets`), `end_mode: timer` |
| Custom circuit (hub, v1.1) | `custom:<game>.<sec>,…`, e.g. `custom:cadence_karaoke.180,kart_race.600` | 1-12 slots, each rounded to 30 s and clamped to its game's limits, at most 90 min of play; role = `GameCatalog.circuitRole` (work, else recovery, else `free`), warm-up in the first slot and cool-down in the last for games with those roles; `end_mode` = the game's `timedEndMode`; a `free` slot (Kart Race) is scaled like a Just Ride |

- Lengths are clamped to the game's limits; a mode the game doesn't support is refused.
- Circuit presets are data. Until a preset's games exist, their slots play the demo (#37).
- With camera games unavailable, a custom circuit's camera game goes to the first camera-free
  game of the same circuit role (Dodge Ball becomes Tug of War); a Kart Race slot has none, so
  the request is rejected (`camera_unavailable`).
- `GameLabels.planBadge` reads `custom:…` as "Custom circuit · 15 min" and `visit` (a hub
  visit of several plans) as "Games".
- `effort` is true for work segments, and for Just Rides of games declaring
  `effort_in_just_ride`.
- Kotlin keeps its own copy of each game's declarations in `GameCatalog`. **Adding a game
  means adding its `GameDeclaration` there too**, matching its `info()`.

**Params.** Every segment's `params` carry `ftp_watts` and `ftp_is_default` (true when the
rider has no FTP, so 150 W was used and the hub should nudge), plus one power figure:

- work, and Just Rides of work games: `target_watts` = 90 / 105 / 120 % of FTP for easy /
  standard / hard;
- recovery: `power_cap_watts` = 60 % of FTP; warm-up and cool-down: 65 %. Difficulty never
  moves a cap. Recovery games use their own params for difficulty.

Game-specific params come from the game's `GameDeclaration.params` (the demo sends
`cadence_floor`).

**Audio.** The rider's own music wins (rider, 2026-10-27): game music plays unless the rider's
music app has a track, or they turned Game music off in the hub's Settings (`audio.music`,
`GameAudioPrefs.gameMusic`, on by default). Effects and cues always play. Kotlin puts the
rider's music in input frame field 12 (`rider_music`, `AppContainer.riderMusic`, checked once a
second), and `AudioDirector` follows it every frame: game music fades out over the 2 s
crossfade when the rider's music starts, mid-segment too, and the game's kept request fades
back in when it goes.

- With Now playing access (Profile → Music), the rider's music is the app's mini player having a
  track, playing or paused (`NowPlayingMonitor`, Android's media sessions). An app drops its
  session a while after a pause, and game music comes back then.
- Without it, `OtherMusicDetector` guesses. `AudioManager.isMusicActive()` alone can't tell,
  because Godot's own media player keeps it true, and API 29-34 don't say which app a player
  belongs to (`getClientUid()` is a hidden system API). So it tells players apart by identity:
  the players that exist before the engine starts are other apps', and those that appear in the
  next 10 s are the engine's. Another app's paused player counts as its music while it exists.
- The desktop keyboard simulator toggles `rider_music` with M, and a 132 bpm strap with H
  (`capture_dodge.gd --heart=BPM` sets one for screenshots).

**Recording.** The ride goes through the app's own `RideSessionManager`, so it is an ordinary
ride in History, exports and backups:

- It starts with the visit's **first plan**, not on entry, so a visit with no plan records
  nothing. Its `startEpochMs` is the first plan's start.
- When a plan finishes, the visit pauses the ride *manually* (pedalling in the menu doesn't
  resume it), and the next plan resumes it. So menu time records no seconds and no samples:
  duration, averages and kJ cover plan time (intro cards included), and the samples have no
  gap.
- Freewheel auto-pause applies within a plan. A rider's pause (`request_pause`) pauses the ride
  too. Either kind freezes the plan's clock and sends `session_paused` / `session_resumed`.
- `session_finished` carries `ride_id: null` and the plan's `bests`, compared with the saved
  rides *and* this visit's earlier runs of the same plan and difficulty.
- The visit ends on `exit_hub` or `request_exit` (then the host moves to the back, and for
  `edit_profile` the app opens the profile editor), when the app comes back to the front
  (`MainActivity.onResume` → `endIfLive("app_resumed")`: no visit stays live behind the app),
  or by the **idle guard**: 20 minutes in the hub with no touch (`hub_activity`, or any hub
  call) and no pedalling saves the visit (`visit_ended.next: hub`, `reason: idle`), Godot stays
  in the hub, and the rider's next tap (`hub_activity`) starts a new visit. A plan in progress
  is ended first.
- A visit with under a minute of gameplay across its plans (intro cards don't count), or with
  no pedalling at all, is discarded rather than saved (`visit_ended.saved: false`, with the
  reason). Normal rides have no such rule: they're only ever ended deliberately.
- Otherwise the ride is saved, with `gamePlan` = the plan's id when the visit played exactly
  one plan, else `visit`; then every `game_results` row (`planId`, `planRun` = the plan's index
  in the visit, a visit-wide `segmentIndex`, `startSec` on the ride clock, `durationSec` of
  gameplay). Then the ride manager returns to idle, and `visit_ended` carries the ride id
  (also `GameVisitManager.finishedRideId`, for the ride summary).
- **If the process dies mid-visit, the visit is lost**, as any unsaved ride is today (the
  samples are in memory until the save). Checkpointing after each plan is a follow-up.
- `GameResultDao` answers personal bests per rider (per game, plan and difficulty), the
  household leaderboard per game, and a plan's best session. Skipped segments never count.
- The ride summary lists each segment's result, and History shows a game badge.
- Room schema 6 adds these (`MIGRATION_5_6`), with `Profile.headCalibration` for the head
  tracker's saved extremes.
- Room schema 8 (`MIGRATION_7_8`, the Games hub) adds `game_results.planId` (null in older
  rows) and `planRun` (0 in older rows): a visit's ride holds several plans, so each row names
  its plan. Queries read a row's plan as `COALESCE(planId, rides.gamePlan)`, and a plan's
  session is one run, `(rideId, planRun)`, so two runs of a circuit in one visit are two
  candidates for its best. Backups carry both fields (older backups restore as null and 0).
  `GameResultDao.planBests` lists the rider's best run of every plan per difficulty, for the
  hub's `bests.plans`.

The Godot AAR declares androidx `FileProvider` at `${applicationId}.fileprovider`, and Godot's
`GodotIO` hard-codes that authority. So the app's own provider is the `OpenRideFileProvider`
subclass at `${applicationId}.files`, and each provider keeps its own paths file.

## The framework

Every game is a scene whose root extends `Game`. The framework (#34) does everything around it,
so a game only plays. None of this changes the Bridge contract.

### A session on screen

`Session`'s child `SessionDirector` (`games/framework/SessionDirector.gd`) listens to
`Session`'s signals:

1. **`session_started`**: it clears the last session (the engine is reused, see above).
2. **`segment_started`**: it does the following, in order.
   - It loads `GameRegistry`'s scene for `game_id` and makes it the current scene. An unknown
     `game_id` is reported as skipped.
   - It starts the segment in `Effort` and `AudioDirector` (`segment.effort`, `segment.audio`).
   - It calls `game.prepare(segment)`.
   - Only then, once the game has loaded, it calls `set_tracker_mode` with the game's
     `tracker_mode`, so the rider sees loading, then the calibration, then the game. (A game that
     builds for seconds in `prepare`, like Kart Race, used to freeze the screen while the
     calibration ran and timed out unseen behind it.) The session's first camera
     mode starts the calibration on the Kotlin side (see "Head tracker"), so Godot doesn't
     request one then: a `request_calibration` would force a second, full run. Godot asks only
     when a `lean_2d` game follows a session calibrated for `lean_x` alone (depth needs its own
     extremes), and when the rider taps to recalibrate.
   - It shows the **intro card** for `intro_sec`. The card
     shows "Up next", the role, the game's `how_to` and `target_text()`, the previous result,
     and a countdown ending 3-2-1. A game whose own start counts down (`GameInfo.own_countdown`, set by
     Kart Race for its grid 3-2-1-GO) gets "Get ready" instead, with no countdown cues, so the
     rider sees one countdown, not two.
3. **Skipping**: the card's "Skip this game" button skips the game (`segment_finished` with
   `skipped: true`). It shows only when another segment follows: skipping the last one would end
   the session, so a one-segment Just Ride never offers it. Any other touch on the card does
   nothing. On the bike, a touch on the countdown used to skip a timed Just Ride's only
   segment, which ended the workout.
   - **Only End, then its confirmation, ends a session.** Every touchable screen follows this:
     the intro card, calibration (a tap only recalibrates, and never mid-run), the pause screen,
     the open-ride "Game over" panel (its End asks first) and the summary (Done leaves only
     after the ride is saved). `intro_touch_test.gd` pushes real touches at each of them.
4. **Gameplay**: the HUD shows, `Effort` starts scoring, and it calls `game.start(segment)`.
   `end_mode: game` games end themselves (`end_segment()`). Open-ended segments count the timer
   up, and the game runs until Kotlin ends the session.
5. **`segment_ending`**: it calls `game.request_finish()`, and the game has 5 s to call
   `end_segment()`. After 4.5 s the director reports for it. A `segment_ending` during the intro
   card reports the game as skipped.
6. **The result**: this is `game.finish()`, with `stars` from the game's thresholds.
   `segment_finished` then goes to Kotlin. When an open-ended plan's last game ends, it offers
   **End session**.
7. **Pause**: while the head tracker calibrates, the session is paused (see the contract) and
   the calibration screen stands in for the pause screen, with no pause or resume cue. The
   intro card's countdown waits for the session's first calibration.
   Otherwise `session_paused` shows the pause screen (Resume, End session) and freezes the
   game, whether the rider paused or Kotlin auto-paused. The HUD's Pause button calls
   `request_pause`/`request_resume`. Its End button, and the pause screen's, ask for
   confirmation, then call `request_end`.
8. **`session_finished`**: it goes back to the idle scene (the hub), sets the tracker off, and
   shows the **summary** over an opaque backdrop: each segment's result and stars, the totals,
   and any bests. Its **Done** button (or Android back) calls `request_exit`. **In a hub visit**
   (`Session.visit_id` set) the button reads **Back to games** and returns to the hub locally
   (`SessionDirector.return_to_hub()`); it never calls `request_exit`. The visit's calibration
   (`session_started.calibrated`) carries into the next plan, so a later camera game doesn't
   recalibrate. Circuit mode (#37) adds
   its sections with `SummaryScreen.add_section()` (under the list on a circuit, in the column
   on a one-game summary).

### The Games hub on screen (`res://hub/`)

The hub (spec `docs/superpowers/specs/2026-10-19-games-hub-design.md`, §8) is the project's main
scene and `SessionDirector.IDLE_SCENE`. A visit's first `hub_state` shows it
(`SessionDirector.Phase.HUB`, `hub_entered`); a game's result card returns to it. It runs at
`Engine.max_fps = 30` (`HUB_MAX_FPS`); a segment lifts the cap. Each return logs
`OPENRIDE_GAMES memory static=… objects=… nodes=… orphans=… viewports=…`.

```
Hub (Hub.gd)                 root Control; acts on what screens ask, talks to Session
├ Backdrop                   one gradient (HubTheme.backdrop)
├ Screens                    HubNav's top screen only: HomeScreen, GameScreen, CircuitScreen,
│                            MyCircuitsScreen, BuilderScreen, SettingsScreen
├ Calibration                CalibrationOverlay in hub mode (CanvasLayer 25), built on the first calibration
├ ConfirmDialog, Toast       CanvasLayers 35 and 36
├ Saved                      CanvasLayer 37: "Saving…", and "We saved your ride · Tap to keep playing" (idle guard)
└ HubMusic                   the hub's theme through AudioDirector
```

- **Navigation:** `HubNav` is a stack of screen ids with their args (home at the bottom). Only the
  top screen is built; a screen is freed when left and rebuilt from `Session.hub` and `HubPrefs`
  when shown again. The stack survives a plan (same visit only), so "Back to games" lands on the
  screen the rider started from. Android back (`Session.back()`, and Esc on a desktop) closes a
  dialog, pops a screen, and on home asks to exit; it never exits by itself.
- **Screens** (`hub/screens/`, each a `HubScreen`) never call `Session`: they emit `open`,
  `back`, `start(request)`, `exit_requested`, `set_ftp_requested`, `setting(key, value)` and
  `Hub.gd` acts. Home has the header (`HubHeader`: avatar, name, ride so far, live rpm · W at
  2 Hz, the camera's state, Settings, Exit games), the FTP nudge, a card per game (the catalog
  intersected with `GameRegistry`; a camera game is dimmed when the camera is unavailable and
  explains on a tap), a card per preset circuit, then "My circuits" and "+ Build your own". A game's screen: its options on the left
  (`GameInfo.options` with `where` hub or both, saved in `GameOptions` per rider at each tap;
  see "Game options"), Length (the catalog's modes and `minute_steps` or rounds), Difficulty
  and Start on the right (it waits for `session_started` or `plan_rejected`). A game with
  `kind: cards` options (Kart Race's kart and track) fills its left column with the card grids
  and shows its best under Difficulty; any other game shows its poster (picture, how-to, best),
  then its options as rows. Grouped options sit under "More options" (top right), a panel over
  the left column with Done (Android back closes it too). A circuit's screen: its lineup, Difficulty, its best and
  Start. Settings: camera games, game music On/Off (the rider's own music still turns it off
  while on; see **Audio**), and the music and effects volumes as 10% steppers (heard at once).
- **The rider's music** (rider's ask, 2026-10-27): while their music app has a track
  (`now_playing`), the header shows ♪ between the camera and Settings, and it opens the
  **music panel** (`MusicPanel`, owned by `SessionDirector`, so the hub and every game share
  it): the art, the title (two lines at most), the artist, previous, play/pause and next
  (`music_control`), and Done; a tap outside closes it too. Previous and next stay, faded, when
  the app doesn't offer them. In play, the HUD's button row adds a ♪ button beside Pause | End
  that opens the same panel and pauses the ride until Done (no pause screen over it; a ride
  already paused stays paused). A first try put a card on home's "Play a game"
  line; the rider found it cramped, and its title ran into the artist. To fit ♪, the header's
  items lost a little width each (rider 546, metrics 350, camera 300, Exit 250), and the
  right-hand ones share one row (`hub_layout_test` and `hud_layout_test` check both with the
  music showing).
- **The circuit builder** (`BuilderScreen`, rules in `CircuitBuilder`, plan phase D): "Add a
  game" tiles (an `OptionCards` grid, flatter through `slot_aspect`; a tap adds the game), the
  lineup as `SlotRow`s in a `ScrollContainer` (the role colour and "2 · Work", the length on a
  `Stepper`, move up and down, remove; drag the names or the thick bar to scroll), Difficulty
  (an `OptionRow`), and on the right the total and lineup (one bake), the best for this lineup
  and difficulty, Save, Delete (a saved one) and Start. A new slot takes the game's minimum or
  1:30; steps are 30 s to 5 min, then 1 min; 12 games and 90 minutes at most. Roles, rounding
  and the plan id mirror `SessionPlans.custom` (`custom:<game>.<sec>,…`), and with the camera
  off a slot plays its camera-free stand-in or, with none (Kart Race), Start greys out and says
  why. Save keeps it as "My circuit 1-3" (no keyboard, so no names); with three saved it asks
  which to replace. Replacing, deleting and leaving with unsaved changes are confirmed; ✕ isn't.
  The lineup being built lives in the nav args, so it survives playing it. `MyCircuitsScreen`
  shows the three places as baked cards (lineup, time, games, best); a tap opens one in the
  builder, an empty one builds into it.
- **Calibrating in the hub** (plan phase E, `HubCalibration`, an enum FSM: idle, asking,
  running): the header's camera chip is a button. It reads "Calibrate" (permission granted, not
  calibrated yet), "CAMERA READY · Recalibrate", "Allow" (permission `ask`: a tap calls
  `request_camera_permission` and calibrates once `hub_state` says granted; still `ask` means
  refused), "NOT ALLOWED · How to allow" (explains Android's settings), "CAMERA OFF · Turn on"
  (offers to turn camera games on) or "CAN'T SEE YOU · Try again". A calibration shows the
  framework's `CalibrationOverlay` in hub mode (full screen, Cancel, no strips), ducks the
  music, and ends at the next `hub_state` once the tracker has stopped calibrating (looked at
  again 0.4 s later if the tracker state lags). Taps within 1 s, or mid-run, are ignored;
  Android back cancels. Camera games of the visit then start tracking at once; one never
  calibrated from the hub calibrates by itself on its first camera mode, as before.
- **Confirmations:** Exit games ("Your ride (12:30, 2 games) will be saved", or "Nothing's
  been recorded yet"), Set FTP (it leaves games) and the camera explanations use
  `ConfirmDialog`: the safe button left, the acting one right, far apart.
- **Picks:** `HubPrefs` (`user://hub_prefs.cfg`, section `<rider>/hub`) keeps the last mode,
  length and difficulty per game, the difficulty per circuit, and the saved custom circuits
  (`custom.1`-`custom.3`: `{v, slots, difficulty}`). Not in OpenRide's backup.
- **Look:** the shared kit's house look (`HubTheme` on `GameTheme.house()`), each game's card in
  its accent (`HubTheme.LOOKS`, from UI_STYLE.md §4). Cards show `res://games/<id>/hub_card.png`
  (512x288, rendered from the game's own world by `tests/capture_hub_cards.gd`; re-run it when
  a game's look changes), masked to the card's rounded outline by
  `framework/ui/shaders/rounded_mask.gdshader` (radius R − inset). Bike rules: targets at least
  120 px (cards 180), 24 px apart, text at least 34 px, Exit and Start never on one screen.
- **Cost:** cards, the header's parts, the poster and the circuit's lineup are baked
  (`framework/ui/BakedView.gd` and `BakeQueue.gd`, promoted from Kart Race, whose `KartBaked`
  and `KartBakeQueue` are now aliases): one draw call each, rendered only when they change. No
  screen has a `_process`. Measured on the desktop (`tests/measure_hub.gd`): home 21 draw calls
  (25 with the FTP nudge), a game's screen 48-57 (Kart Race's 53 with its 12 card bakes, 67 with
  More options open), a circuit's 25, Settings 57, and no bake
  renders on an idle frame.
- **Activity:** any touch in the hub sends `hub_activity()` (at most once a minute) for
  Kotlin's idle guard. After `visit_ended` with `next: hub` the hub shows "We saved your ride",
  and a tap sends `hub_activity()`, which starts a new visit.
- **Music:** `HubMusic` plays "Lobby Loop" (`hub/music/`, `HubMusicIndex.gd`, rendered from
  `tools/music/songs/hub.py`): the bed always, the harmony from 0.3 and the lead from 0.7 of an
  intensity that follows pedalling (0 still, 0.5 at 60 rpm, 1 at 90 rpm). It honours
  `hub_state.audio` (`AudioDirector.set_volumes`), puts `GameMix.master_effects()` on Master,
  ducks while a dialog shows and under messages, and crossfades with the games' themes.
- **Measured (phase D, desktop):** the builder 35 draw calls empty and about 147 with a full
  view of rows (its rows aren't baked: they change on every tap), My circuits 13, home 23.

### Adding a game

A game is **one folder and one registry line**:

1. Create `games/games/<game_id>/` with a scene whose root node's script extends `Game`.
   `games/games/demo/` is the reference: `Demo.tscn`, `Demo.gd` (the scene) and `DemoLogic.gd`
   (the rules).
2. Add `"<game_id>": "res://games/<game_id>/<Name>.tscn"` to `GameRegistry.GAMES` in
   `games/games/Registry.gd`.

`registry_test.gd` then checks that the game loads and that its declarations are valid. The
game is also playable on the desktop: run its scene with F6, or play the project.

**Declarations.** `info()` returns a `GameInfo`:

| Field | Meaning |
| --- | --- |
| `id`, `title`, `how_to` | The registry key; the name on cards and the summary; a one-line how-to for the intro card |
| `supports` | Just Ride modes: any of `rounds`, `minutes`, `open` |
| `min_sec`, `max_sec`, `min_rounds`, `max_rounds` | Duration limits |
| `roles` | Circuit roles it can fill: `warmup`, `work`, `recovery`, `cooldown` |
| `tracker_mode` | `off`, `lean_x`, `lean_2d` or `lean_stand`. `Session` sets it for the segment. |
| `effort_in_just_ride` | Whether the effort multiplier applies in a Just Ride |
| `timed_end_mode` | `end_mode` of a timed (`minutes`) Just Ride: `timer` (the default), or `game` for a game that ends on its own terms, like Kart Race on a lap line. Kotlin's `GameDeclaration.timedEndMode` must match; the desktop's local session uses it too. |
| `star_thresholds` | `{easy: [1★, 2★, 3★], standard: […], hard: […]}`: the minimum score for each star |
| `stars_per_minute` | When true, the thresholds are points per minute of gameplay, so one set fits a 90 s slot and a 30-minute ride |
| `variant_star_thresholds` | Star thresholds for the game's variants, by variant (e.g. `{"catch": {…}}`); others use `star_thresholds` |
| `options` | The game's own settings, shown on its hub screen and in the pause screen's **Game options** card: `[{key, label, choices, labels, default}]`, values as strings, plus the optional `where`, `kind`, `cards`, `columns`, `group` and `rider_badge`. See "Game options". |

For work games, set the thresholds so that 3 stars needs about 1.3× effort. A perfect run at
1.0× must stay short of 3 stars (epic #31). `demo_logic_test.gd` checks this for the demo.

**Hooks.** A game overrides the ones it needs. It never overrides `_process`.

| Hook | When |
| --- | --- |
| `_on_prepare(segment)` | The scene is loaded and the intro card shows. `segment`, `params`, `difficulty`, `rng` (seeded from `seed`) and `hud` are set. Build the level, add HUD widgets, ask for music. |
| `_on_start()` | Gameplay begins |
| `_on_frame(delta)` | Every gameplay frame while not paused. Read `InputBus`. |
| `_on_pause()`, `_on_resume()` | The scene's processing is also frozen while paused |
| `_on_option_changed(key, value)` | The rider changed one of the game's options on the pause screen; `option(key)` already returns the new value |
| `_on_finish_requested()` | The timer ran out: wrap up and call `end_segment()` within 5 s. By default the game ends at once. |
| `target_text(segment)` | The intro card's target line, e.g. "Hold 250 W" |

Before `_on_prepare`, `prepare()` loads every `.gdshader` under the game's folder once and keeps
it for the engine's life (`Game.keep_shaders`). The Compatibility renderer compiles per Shader,
so a Shader freed when its game ended was compiled again on the next start (2-4 s of first
frames on the tablet). A shader built in code (`Shader.new()`) is built once, in a static.

**What a game calls:**

- `award(points)` scores through `Effort`. It returns what counted.
- `penalize(points)` takes points off without the multiplier (`Effort.penalize`), for
  penalties such as Dodge Ball's -50. The score never drops below zero.
- `option(key)` reads one of the game's options for the current rider.
- Set `variant` (e.g. Dodge Ball's `"catch"`) when the game has variants. The result carries it,
  stars use the variant's thresholds, and Kotlin keeps bests and leaderboards per variant
  (`game_results.variant`, schema 7).
- Override `how_to_text(segment)` and `intro_visual()` to give the intro card a dynamic how-to
  line and a small picture or animation (Dodge Ball shows its mode).
- Override `ui_theme()` to return the game's `GameTheme` (see "Game UI kit"). The session then
  styles the intro card and the pause screen with it; the game skins the HUD itself in
  `_on_prepare` with `hud.set_skin(theme.hud_skin())`. The default, `null`, keeps the kit's plain
  look.
- `end_segment()` ends the segment. It is honoured in `end_mode: game`, in open-ended
  segments, and after `request_finish`. A game that finishes early in a timed slot starts another
  round instead (epic #31, "Short games fill their slot").
- Set `won` (true / false) for games with a winner, and add counts to `stats`. `effort_avg` and
  `played_sec` are added for you.
- `AudioDirector.play_music()`, `play_sfx()` and `set_intensity()` (see Audio below).

**Rules:**

- Keep the rules in a plain class (`RefCounted`) and test it headless with scripted inputs, like
  `DemoLogic`. The scene only draws it.
- Talk to Kotlin only through `InputBus`, `Session` and the framework. Never call
  `get_tree().quit()`.
- Reset in `_on_prepare`, not `_ready`: every segment gets a fresh instance of the scene, but
  the autoloads live on.

### Game options

A game can declare its own settings in `GameInfo.options`, for example Dodge Ball's scene
lighting and camera tilt. They're generic and framework-owned:

- **Where they show** (`where`): `hub` (the hub's game screen only: a pick made before Start,
  like Kart Race's kart and track), `pause` (the pause screen only) or `both` (the default).
- **On the hub's game screen** (spec §7; `hub/screens/GameScreen.gd`), by `kind`:
  - `cycle` (the default): one button that steps through the choices (`OptionCycle` in an
    `OptionRow`, beside the option's label);
  - `segmented`: every choice side by side (2-4 short ones; `Segmented` in an `OptionRow`);
  - `cards`: a grid of picture cards (`OptionCards`, `columns` across, default 4), one per
    choice from `cards: [{value, title, subtitle, image, accent}]` (`image` a `res://` texture,
    `accent` a Color for the card's edge; a choice without a card shows its label). Each card is
    baked (one draw call); the chosen card has a thicker gold edge and a gold title, and with
    `rider_badge: true` wears the rider's name. A wide picture covers the card's picture slot,
    a narrower one (a portrait) is fitted and centred, and both are inset evenly and masked to
    the card's rounded outline (`rounded_mask.gdshader`, radius `CARD_RADIUS − PICTURE_INSET`).
    Cards are hub-only (`where: hub`; `registry_test` checks it).
  - `group`: any name other than `""` folds the option under the hub's **More options** panel
    (the ones a rider sets once). `GameInfo.validate()` checks every key (`registry_test`).
  The hub writes the pick at once with the hub's rider (`HubPrefs.rider(state)`), which is the
  `rider_id` the game's session then reads.
- The pause screen shows a **Game options** button when the game declares any option with
  `where` pause or both. Its card has one button per such option that steps through the
  choices; **Back** returns to the pause card.
- `GameOptions` (`framework/GameOptions.gd`) stores the choices in `user://game_options.cfg`,
  one section per rider and game (`<rider_id>/<game_id>`, `guest/…` with no active rider).
  Unknown keys and values are ignored, and a missing value reads as the declared default.
- The game reads them with `option(key)`, usually in `_on_prepare`, and hears changes through
  `_on_option_changed`.

### Effort

The `Effort` autoload applies the epic's multiplier (maths in `EffortMeter`):

- **The formula:** `1 + 0.5 × clamp((resistance − 30) / 30, 0, 1)`. It is 1.0× at ≤ 30% resistance
  and 1.5× at ≥ 60%.
- **The grinding guard:** the multiplier only applies while cadence is 60 rpm or more. Below
  that it is 1.0×.
- **`effort: false`:** the multiplier is always 1.0×, and the HUD badge is hidden.

`Effort.award(points)` returns 0 outside gameplay: on the intro card, while paused, while
`sensors_ok` is 0 and after the end. That is how "sensor loss freezes scoring" is enforced.
`stats.effort_avg` is the multiplier's average, weighted by time, over the time scoring
counted.

### HUD kit

`Hud` (`games/framework/hud/`) goes over every game. Every element sits in a container slot,
so nothing overlaps and nothing has a hand-placed position. Everything persistent sits above the
horizon or at the screen's edges, so the playfield (Dodge Ball's road) stays clear from the
horizon down to the bike:

| Row | Left (expands) | Centre | Right (expands) |
| --- | --- | --- | --- |
| sensor banner | (full width, only on sensor loss) | | |
| top bar | ride panel: effort ×, gauge, then rpm · W · % (· bpm with a strap) | the game's own status widgets (`add_widget`), slim | time left over the score, Pause and End under it |
| middle | | a brief, translucent message (`show_message`) | |
| status slot | | the camera strip ("Camera steering is off", …) | |
| bottom bar | | | Recalibrate (camera games) |

The game's title and role aren't shown during play: the intro card names the game (and, for
Dodge Ball, the mode).

- **Ride metrics** (`RideMetrics`) are shared by every game: rpm, watts and resistance in three
  equal columns, each value at the same size with the same small unit underneath (rpm · W · %).
  While a heart-rate strap is sending (`InputBus.heart_rate` ≥ 0), a fourth column shows bpm,
  and all four narrow (140 px) with a 60 px value so the top bar still fits beside the clock
  (rider's ask, 2026-10-27). Kart Race's own ride strip adds a BPM tile the same way.
  A game sets its bands with `hud.metrics.set_cadence_band(low, high)` and
  `set_power_band(low, high)`. The rpm turns green in the band, amber just under it and red well
  under; the watts turn gold at the target. A slim gauge under a banded value fills to the current
  value with a white tick at the floor or target, so no "floor 85" caption is needed.
- `hud_layout_test` lays the HUD out at 1920x1080 while playing, with the power bonus, the
  camera strip, while calibrating and at game over, with the longest texts each element shows.
  It checks that no two elements overlap and that none covers the road. The road keep-clear
  area is derived from Dodge Ball's camera (eye height 1.45 m, pitch −7°, both ends of its 62-72°
  field of view) and road edges (6 m either side, the bike anywhere within 4.4 m of the centre):
  a point is road when its ray meets the ground inside that band. Each element is grown by 12 px
  for the camera's roll. Recalibrate, the camera strip and brief messages are exempt by design.
- Widgets only touch their labels when a value changes: a theme override or new text re-lays
  out the HUD, which cost frame time on the tablet when done every frame.
- **Skins** (`hud.set_skin(skin)`, opt-in, Kart Race only so far): a game with its own look
  restyles the persistent panels (`font`, `outline_color`, `outline_size`, `panel`, `button`,
  `button_pressed`, `end_button`) and can slim the layout: `ride_panel: false` hides the ride
  panel (the game then shows rpm, watts, resistance and the effort multiplier itself, as Kart
  Race's bottom ride strip does), `clock_value_size` shrinks the time left and the score (not
  below `MEDIUM`), and `reserve_right` keeps that many pixels free at the top bar's right end,
  so the clock and Pause | End sit just left of it. A game that needs the bottom right (Kart
  Race's item button) moves the touch targets and the camera strip: `recalibrate_top: true`
  puts Recalibrate in the top bar, left of Pause | End (End keeps the corner), styled by
  `recalibrate_button`; `status_width` narrows the camera strip's row (centred; its text
  wraps) and `reserve_bottom` keeps room under it for the game's own bottom widgets. With
  Recalibrate moved up and no reserve, the empty bottom bar folds away and the strip sits on the
  bottom margin. `set_status_area(width, reserve_bottom)` moves the strip later without a
  re-skin (a re-skin re-lays out every label: about 1 ms on the desktop, 25 on the tablet).
  Two more keys style the centre message: `message_font` (it then pops in whenever it appears
  or its text changes) and `message_outline_color`; `GameTheme.hud_skin()` sets every styling
  key.
  Buttons keep their touch size. `clear_skin()` (and `clear_widgets()`, when the game leaves)
  puts everything back; `hud_layout_test` and `kart_presentation_test` cover both.

It is sized for a 1920x1080 canvas read from about 1 m away (`HudTheme`). Numbers are 96 px,
text is never below 34 px, and buttons are 110 px tall.

**The centred stage (#57).** The bike's window is 1920x1008 (the tablet keeps the hidden nav
bar's strip), so with stretch aspect `keep_height` the canvas is about 2057x1080. Every layout
still uses `HudTheme.W` x `HudTheme.H`: the `Stage` autoload shifts the default canvas and every
root-viewport `CanvasLayer` by `Stage.pad` (68 px on the bike, 0 on a 16:9 window), so (0, 0)
is the stage's top left. Only full-screen pieces cover the whole window:

- a backdrop or shade (a direct child of a layer, a game or the hub): `Stage.bleed(control)`;
- a 3D view: size its SubViewport with `Stage.view_size(scale)`, bleed the image showing it,
  and redo the size on `Stage.changed`; map a projected point back with `Stage.from_view()`;
- painted 2D art: paint past the stage's sides (Safe Cracker's rooms reach `SafePlaces.BLEED`,
  160 px, each side; the props stay on the 1920 stage) and bake it over the wider span.

`stage_test` checks this at 2057x1080, and `hub_layout_test` checks the hub there too.

Games add their own widgets to the top-centre slot with `hud.add_widget()`. Keep them slim (a
row or two of small text, as Dodge Ball's status) so they stay above the horizon, for example a
`TargetBand` (a cadence floor or a power cap) or a `BigNumber`. `StarRow` draws stars as
shapes, so no font needs the glyph. The kit's plain look uses Godot's default font; a game with
a `GameTheme` uses the shared display face.

### Game UI kit

`framework/ui/UI_STYLE.md` is the style guide every game follows: one OFL display face (Lilita
One, `games/assets/fonts/`), ink outlines, badge panels, pill buttons, shared meaning colours
(good, warn, bad, target) with an accent and an ink per game, motion rules, touch targets and
the draw-call budget. `GameTheme` (`framework/ui/GameTheme.gd`) is its kit: labels, gradient hero
text, panel, badge and card styles, buttons, a HUD skin, and `pop` / `slam` / `flash` / `pulse` /
`fade` tweens. Kart Race keeps its own `KartTheme`, which follows the same rules.

- A game opts in through `Game.ui_theme()`. `SessionDirector` calls `IntroCard.apply_theme()`,
  `PauseOverlay.apply_theme()` and `CalibrationOverlay.apply_theme()` with it at each segment
  (the themed countdown slams each 3-2-1 in gold), again whenever the game emits
  `Game.ui_theme_changed` (Cadence Karaoke's colour option), and with `null` when the game
  leaves. Layout, text and touch behaviour don't change.
- **The session summary** takes the look of the game it follows: `SessionDirector.looks` keeps
  each game's last `ui_theme()` by game_id, and `SummaryScreen.show_summary(summary, plan,
  looks)` uses it. One game (a Just Ride) is centred in that game's look: its chip, the title,
  its three stars slamming in one by one, points and time as tiles, the best as a badge (gold
  for a new best, a quiet panel for the one to beat), and Done (560 x 120) at the bottom. A
  circuit is in the house look, `GameTheme.house()`: the title across the top, tiles (points,
  stars, time, games played), the best and a full-width Done on the left, and a card per
  planned game on the right, edged and numbered in its game's accent; the list scrolls when
  it's long. A game with no `ui_theme()` (Kart Race, the demo) gets the house look, a
  periwinkle on deep indigo that sits next to Kart's violet night.
- **The calibration screens** take the game's look too (the house look without one): see
  "Calibration UI".
- The open-ride "Game over" panel stays neutral.
- `HudTheme.style_label` and `HudTheme.style_button` put the plain look back on a restyled node.
- `game_theme_test` covers the kit and the opt-in theming (and that `null` fully undoes it);
  `hud_layout_test` lays the HUD out with a theme skin too. `summary_screen_test` lays out
  both summary shapes (no overlaps, Done's size and place, long names, a list that scrolls,
  the opaque backdrop, the entrance), and `calibration_overlay_test` every calibration step,
  the strips, the taps and the look.
- `tests/capture_ui_states.gd` (needs a window) saves half-size screenshots of any game at its
  intro, play, a high-tension moment, pause and the summary, with each frame's draw calls:
  `$GODOT_BIN --path games -s res://tests/capture_ui_states.gd -- --game=tug_of_war --out=DIR`.
  `tests/capture_framework_screens.gd` does the same for the framework's own screens: every
  calibration step and strip, and the summary in its shapes (one game, a new best, no stars, a
  circuit, one ended early, a long one, Kart Race's house look).

### World look (3D)

The 3D games light their worlds by hand: every world surface is `unshaded, fog_disabled` (the
engine's per-pixel light and fog cost the tablet about a third of its frame), and the colour
grade is folded into each material (a full-screen pass cost about 5 fps). The shared pieces,
generalised from Kart Race (which keeps its own `light.gdshaderinc`):

- `framework/shaders/world_look.gdshaderinc`: the uniforms `sun_dir`, `sun_color`, `sky_color`,
  `ground_color`, `haze_color`, `haze_density`, `haze_max` and `noise_tex`, and `vnoise(p)`,
  `hemi(n)`, `sun_light(n)` (hemisphere plus Lambert sun; call it per vertex for scenery),
  `haze(col, dist)` and `grade(col, SCREEN_UV)`. Each game sets its own grade with
  `#define LOOK_SAT`, `LOOK_CONTRAST`, `LOOK_GAIN`, `LOOK_LIFT`, `LOOK_VIGNETTE` and
  `LOOK_VIGNETTE_TINT` before the `#include`; with none defined the grade is a no-op.
- `WorldLook` (`framework/WorldLook.gd`): `apply(materials, look)` sets those uniforms on a
  list of materials from one Dictionary (unknown keys are ignored, so a time-of-day table can go
  straight in), `sun_dir(elevation, azimuth)` in the time-of-day presets' convention, and
  `noise_texture()`, the same 64×64 noise as Dodge Ball's.
- `world_look_test` compiles the include with and without a game's defines.

Each game's look is in its `ART_BIBLE.md`, and the planned graphics work in its `GFX_POLISH.md`.

### Calibration UI

`CalibrationOverlay` shows only in camera games, in the game's look (and, in hub mode, while
the hub calibrates: see "The Games hub on screen"):

- **While calibrating** (`tracker_state` 2, or `calibration_progress` in the last second), it
  prompts each step on a card: centre, with a 3-2-1 from `fraction`, then left, right, and in /
  back for `lean_2d`. A drawn rider shows the pose (leaning, or bigger for "lean in" and smaller
  for "sit back", with gold arrows) inside a ring that fills with `fraction`; a dot per step
  turns green with a tick as each is done, and a finished step says "Got it!".
  The header reads "Step 2 of 3" (`step_index`, `step_count`; left out for a centre-only
  run), and "Try 2" from `attempt`. `retry_reason` becomes a hint: "Hold still for a moment",
  "Can't see you. Face the screen: is the room bright enough?" (on the bike, a dark room was
  the usual cause), "Lean a little further" or "Other way!". For `used_default` it shows "Using
  your usual range; recalibrate later if steering feels off" (no 3-2-1 over it).
- **When the tracker needs calibration** (`tracker_state` 1), it offers "Tap to calibrate" with
  a "Tap anywhere to start" pill.
- **When the face is lost** (`tracker_state` 4), it shows a slim amber strip with a camera icon:
  "Can't see you: face the camera, and check the room is lit", and "TAP TO RECALIBRATE".
- **When a calibration ended in `tracker_state` 0** (no face found after two tries), it shows
  a slim strip with a crossed-out camera: "Camera steering is off: no face found. Turn a light
  on and face the camera", and "TAP TO TRY AGAIN".

Tapping "tap to calibrate", "can't see you" or "camera off" calls `request_calibration`, and so
does the HUD's Recalibrate button; both run every step. A tap during a running calibration is
ignored (on the bike, stray taps restarted runs mid-step), and requests within 1 s of the last
one are dropped (a double tap sent two). `Session.calibration` holds the session's latest progress, with all six
fields.

## Audio: the `AudioDirector` interface

The `AudioDirector` autoload owns playback, and generators plug into it (#36: `SfxSynth`,
`MusicGen`, under `games/audio/`). **Until something registers, every call plays silence** and
logs `OPENRIDE_GAMES audio: nothing provides '<name>' yet; silent` once per name.

**Buses:** `Master`, then `Music`, `SFX` and `Cues`, which all send to `Master`. They are created
at startup.

- `segment.audio.music_volume` sets `Music`.
- `sfx_volume` sets `SFX` and `Cues`.
- `InputBus.rider_music` (frame field 12) fades the music out while it's set, and back in after.
  A game's `play_music` meanwhile is kept but not played (`set_rider_music`). An older Kotlin's
  `audio.music: false` does the same for that segment.
- `Music` ducks by 10 dB under every cue, and by a game's own `duck_music(db, seconds)`; the deeper duck applies.

### Registration (for generators)

Call these at startup. `res://audio/Cues.gd` is an optional hook: if that script exists,
`AudioDirector` instantiates it once in its `_ready` and calls its `register(director)`, so
generators can register without an autoload of their own.

| Method | Contract |
| --- | --- |
| `register_sound(name: String, stream: AudioStream)` | A named effect or cue, rendered ahead of time. It replaces any earlier sound of that name. |
| `register_sound_factory(factory: Callable)` | `factory(name: String) -> AudioStream` (or `null`). It is asked on the main thread the first time an unregistered name plays, and the answer is cached. Use it for lazy rendering of presets. |
| `register_music_generator(generator: Callable)` | `generator(request: Dictionary) -> Dictionary`, mapping each stem name to a **looping** `AudioStream`, all the same length. `request` is `{style, tempo_bpm, seed}`. It **runs on a `WorkerThreadPool` thread**, so it must not touch the scene tree. Disk caching (`user://audio_cache/`) is the generator's job; `AudioDirector` keeps the last 4 renders in memory, and no more than 64 MB of WAV stems (`MUSIC_CACHE_BYTES`). |

### Playback (for games)

| Method | Behaviour |
| --- | --- |
| `play_music(style: Dictionary, tempo_bpm: float, seed := 0)` | `style` belongs to the game and is passed to the generator as is. The one key `AudioDirector` reads is `stem_gates`: `{stem_name: intensity}`, the intensity at which a stem plays (0 by default). The music renders off the main thread, which the intro card covers, then **crossfades in over 2 s**. The old music plays until then. Asking again for the same request changes nothing. Tempo = the segment's target cadence (one beat per pedal stroke). The same style and seed at a new tempo is a **tempo change**: it swaps in on the next phrase boundary instead (see "Tempo changes on a phrase boundary"). **Pre-rendered music:** a style with `stem_files: {stem: path}` plays those files (OGG Vorbis, say) instead of asking the generator, loaded off the main thread and looping from `loop_from` seconds, so an intro plays once (`AudioDirector.stems_from_files`; every game's theme, see "Rendered music and effects"). **`swap_keeps_place: true`** makes a tempo change carry on from the phrase it swaps in at (the same place in the song) instead of the loop's start (Cadence Karaoke). |
| `set_intensity(value: float)` | 0-1. Stems fade in or out over 1.5 s as `value` crosses their gate. |
| `stop_music(fade_sec := 2.0)` | Fades the music out |
| `play_sfx(name, volume_db := 0.0, pitch := 1.0) -> bool` | An effect on `SFX`, from 8 voices. `false` means silence. |
| `play_cue(name) -> bool` | A cue on `Cues`, which ducks the music |
| `set_bus_effects(bus, effects: Array[AudioEffect])` | The game's own effect chain on `Music`, `SFX` or `Master` (for example a room reverb and a glue compressor, or a limiter on the whole mix), replacing any earlier one. Every segment starts with all three clean. Native effects cost little, unlike offline reverb in GDScript. |
| `duck_music(db: float, seconds: float)` | Ducks `Music` by `db` for `seconds` (Kart Race: -3 dB under its countdown and banners), without a cue. Asking again while it holds extends it. |

**Cue names the framework plays** (#36 provides them; see "Generated audio"):

| Name | When |
| --- | --- |
| `countdown` | Each of the intro card's 3, 2, 1 |
| `go` | Gameplay starts |
| `segment_end` | A segment's result is in |
| `pause`, `resume` | The session pauses and resumes |
| `summary` | The summary appears |

The demo asks for `dodge` and `hit` effects (rendered, from `DemoMusic.SOUNDS`) and for its rendered
theme: `{"name": "warm_up", "stem_files": DemoMusic.STEM_FILES, "loop_from": DemoMusic.LOOP_FROM,
"stem_gates": {"harmony": 0.5, "lead": 0.85}}` at `DemoMusic.BPM`, with `GameMix.master_effects()`
(a -1 dBFS limiter) on `Master`.

`Session` handles the rest:

- `begin_session()` and `begin_segment(segment)` apply the settings above.
- `set_paused()` pauses the music and effects, but not cues.
- `end_session()` fades the music out after the last segment.
- The music keeps playing across the intro card until the next game asks for its own.

`sound_played(name, bus)` and `music_started(key)` are there for tests and debugging.

## Generated audio (`games/audio/`)

All game music and effects are generated in code (#36). Since #39 the generator can also play
a few recorded CC0 one-shots (`audio/samples/`, listed in `assets/SOURCES.md`): see "Sampled
instruments and stem effects". `res://audio/Cues.gd` is the single entry point: `AudioDirector` calls its
`register(director)` at startup, which:

- builds the wavetables and loads the styles on the main thread;
- registers `SfxSynth` as the sound factory, so effects and cues render on first use;
- registers the framework's rendered cues (`CueSounds.gd`, #55), which take the cue presets' place;
- registers `Cues.generate` as the music generator: `SongSequencer` for a style with `song`,
  `MusicGen` for the rest.

Since #55 the games themselves play rendered music and effects instead: see "Rendered music and
effects". `MusicGen` and the presets stay for the gallery, as fallbacks and for new games.

| File | What |
| --- | --- |
| `Cues.gd` | The entry point above. `countdown` maps to the `countdown_beep` preset; every other name is a preset name. |
| `CueSounds.gd`, `cues/*.ogg` | The framework's cues, rendered by `games/tools/music` (#55) |
| `SongSequencer.gd` | Music that follows a tempo, from a sample bank and a score (#55) |
| `GameMix.gd` | The games' shared mix settings: the Master limiter and the sting and moment ducks (#55) |
| `SfxSynth.gd`, `SfxPreset.gd` | The effects generator and its preset resource |
| `sfx/<name>.tres` | The starter presets |
| `MusicGen.gd`, `MusicStyle.gd` | The composer and synth, and the style resource |
| `styles/<name>.tres` | The styles |
| `Dsp.gd` | Shared oscillators, noise, filters and the float → PCM conversion |
| `gallery/StyleGallery.tscn` | The desktop audition scene |
| `tools/make_library.gd` | Regenerates the starter presets and styles from its tables |

### Rendered music and effects (`games/tools/music`, #55)

Every game's theme and effects are produced offline by `games/tools/music/render_music.py`
(numpy, scipy and soundfile; deterministic; all synthesis written for this repo, no samples), one
song module per game in `songs/`. See that folder's README. A game's rendered files live in
`games/games/<game>/music/` and its index, `<Prefix>Music.gd`, is generated next to its scene:
`STEM_FILES`, `LOOP_FROM`, `BPM`, `KEY` and `SOUNDS`. The Games hub's theme, "Lobby Loop"
(`songs/hub.py`), goes to `games/hub/music/` with the index `hub/HubMusicIndex.gd` (the module's
`DIR`, `INDEX` and `CLASS_NAME`).

- **The theme** is a short intro and a loop of about 50-60 s in real song form (verse, chorus,
  bridge; fills, builds and risers), mixed with sends, a kick-keyed pump, glue compression and a
  limiter to -15 LUFS. It ships as **three OGG stems** that sum to the mix: `bed` (drums, bass,
  effects; always on), `harmony` and `lead` (mono), which the game gates by intensity with its
  `stem_gates`. The game plays it with `stem_files` at its own `BPM`, with the same request
  every segment, so it plays on across segments.
- **The effects** are one OGG each, in the theme's key, registered with
  `AudioDirector.register_sound` under the old preset names (the presets stay as SfxSynth's
  fallback), peaking at -4 dBFS so overlaps keep headroom. The framework's cues (`audio/cues/`)
  peak at -3 dBFS.
- **The mix:** each game puts `GameMix.master_effects()` (a hard limiter at -1 dBFS) on `Master`
  and ducks the music under its own stings and banners (`GameMix.duck_for_sting`, -8 dB;
  `duck_for_moment`, -5 dB), as cues do.
- **Size:** 0.9-1.4 MB of OGG per game, about 5.8 MB in all with the cues.

| Game | Theme | Tempo, key | Style | Intensity links |
| --- | --- | --- | --- | --- |
| Dodge Ball | Incoming! | 150 bpm, E minor | Electro-rock: synth bass, chugs, brass stabs, supersaw hook | harmony over the cadence floor, lead over the power target |
| Tug of War | Heave Together | 132 bpm, D minor | Stomp-clap sea shanty: strums, accordion, tin whistle, brass | harmony with the rope tight, lead in a surge |
| Safe Cracker | Night Shift | 120 bpm swung, C minor | Spy jazz: ride and brushes, walking bass, vibes, muted trumpet, sax, spy guitar | harmony and lead while steady; the bed alone while the alarm rings |
| Cadence Karaoke | Neon Lines | the cadence (70-130 bpm), A major | Synth-funk: slap bass, Rhodes, plucks, supersaw hook | the tempo is the target cadence; the lead only in the band |
| Demo | Warm Up | 122 bpm, F major | Easy house: sub bass, off-beat piano, pluck and supersaw | harmony and lead as cadence nears the target |

**Music that follows a tempo (`SongSequencer`).** Cadence Karaoke's music must play at the rider's
target cadence, so it can't be one file. Its song ships as a **sample bank** (`*_bank.ogg`: every
note the song plays, rendered once at the length the slowest tempo needs) and a **score**
(`CadenceMusic.SONG`: per track, each note's beat, sample and gate). `SongSequencer.render` lays
the score out at the tempo on a worker thread:

- The bank is decoded once per session (`AudioStreamPlayback.mix_audio`, native) to 16-bit PCM.
- Each track is monophonic: a note plays until the next on its track, its gate plus the track's
  release, or its end; a note cut short fades over the release. Tracks are built from native
  slices and padding, with a GDScript loop only for those fades.
- Each stem's tracks are summed natively (`AudioStreamSynchronized` through `mix_audio`) into a
  looping 16-bit stereo WAV at 32 kHz.
- Nothing is time-stretched or pitch-shifted, so the instruments sound the same at every tempo.
  Rejected: `pitch_scale` (a 5 rpm step is 1-1.5 semitones), a pre-rendered file per tempo (17
  tempos would be ~15 MB), and MusicGen (its synthesis can't reach this sound).
- **The tempo** is the target cadence from 70 rpm (one beat a stroke); below, it doubles
  (40-65 rpm play at 80-130 bpm, two beats a stroke). A pace change swaps in on a phrase
  boundary with `swap_keeps_place`, so the song carries on where it was.
- **Cost:** on an M-series Mac a 24-bar render takes 220-360 ms on one thread (MusicGen's
  `bright` 16 bars: 174 ms), plus 155 ms to decode the bank once. Expect about 1.5-2 s on the
  tablet's worker thread, within the swap's budget; to be measured there. A render holds 17-31 MB
  of PCM (the cache keeps at most 64 MB) and the decoded bank 20 MB.

**Checking a mix without speakers.** `tests/render_game_audio.gd` plays a game headless with a
scripted rider (or a reel of all its sounds) and mixes every player itself, decoding OGG with
`mix_audio`, to WAVs and an event log. `tools/music/analyze_mix.py` reports loudness, peaks,
clipping, each effect's cut-through over the music and the duck:

```sh
$GODOT_BIN --headless --fixed-fps 60 --path games -s res://tests/render_game_audio.gd -- --game=dodge_ball --out=/tmp/r
python games/tools/music/analyze_mix.py /tmp/r --limit
```

### Effects (`SfxSynth`)

An sfxr-style generator with these settings per `SfxPreset`:

- a sine, triangle, saw, square, pulse or noise oscillator, with optional noise mixed in;
- an attack / sustain / decay envelope with punch;
- a start → end pitch sweep, vibrato and a pitch jump;
- low-pass (swept) and high-pass filters;
- repeats, and seamless looping for continuous sounds such as an engine hum.

Each preset renders once to a 22.05 kHz mono `AudioStreamWAV` and is cached.

- **Starter library:** `whoosh`, `thud`, `click`, `chime`, `alarm_soft`, `boost`,
  `countdown_beep`, `go`.
- **Framework cues:** `segment_end`, `pause`, `resume`, `summary`.
- **Demo:** `dodge`, `hit`.

A game adds its own presets in either of two ways:

```gdscript
SfxSynth.add_preset_dir("res://games/dodge_ball/sfx")  # <name>.tres files; later dirs win
SfxSynth.add_preset("launch_whoosh", preset)           # or in code
AudioDirector.play_sfx("launch_whoosh")
```

Tune presets in the inspector, or by ear in the gallery.

### Music (`MusicGen`)

A game asks for music by style name through `AudioDirector.play_music`. `MusicGen` composes a
seeded 16-bar loop in A A' B A form: four-bar phrases, one chord per bar, the B phrase on its
own progression, and the last phrase the same as the first. It renders four looping stems, all
exactly the same length: `drums`, `bass`, `harmony` and `lead`.

- **Deterministic.** The same style, seed, tempo and bars always give the same samples. The
  tune depends only on the style and the seed, so a tempo change keeps the same tune.
- **Seamless.** Every bar starts and ends at silence, so the loop point never clicks.
- **Stem lengths.** A stem is `bars × round(4 × 60 × 22050 / tempo)` samples; see
  `MusicGen.loop_samples()`.
- **Overrides.** Any other key in the game's style dictionary overrides that `MusicStyle`
  property. For example, `{"name": "racer", "transpose": 2, "energy": 1.0}` gives Kart
  Race's final lap. `bars` sets the loop length (16 by default). `AudioDirector` reads
  `stem_gates` itself.
- **Speed.** A bar that repeats is rendered once and copied. The four stems render in
  parallel on `WorkerThreadPool` threads. Godot's WAV loader converts the float samples to
  16-bit natively.
  - On an M-series Mac, a 16-bar, 4-stem loop at 90 bpm (42.7 s of audio) renders in
    60-125 ms (130-270 ms on one thread).
  - On the Gen 2 tablet (4 cores), with the demo running, each style's 16-bar render at
    90 bpm took 0.78-1.18 s on a `WorkerThreadPool` thread (budget: 5 s). The 14 effects
    took 0.2 s. The game held 56-61 fps throughout (measured 2026-09-30, mock build,
    `user://audio_bench`).
- **Disk cache.** Renders are cached in `user://audio_cache/<sha256>.stems`.
  - The key covers the style's musical content, the tempo, the seed, the bars and
    `MusicGen.VERSION`. Editing a style never plays a stale render; bump `VERSION` when
    the generator's output changes.
  - The cache is pruned to 50 MB, oldest first.

| Style (`styles/*.tres`) | Game | Character |
| --- | --- | --- |
| `drive` | (gallery; was Dodge Ball's) | Minor key, four-on-the-floor, pumping eighth-note bass, stabs |
| `heave` | (gallery; was Tug of War's) | Phrygian, heavy half-time drums, a bass that builds phrase by phrase |
| `noir` | (gallery; was Safe Cracker's) | Harmonic minor sevenths, brushes and ride, walking bass, swung comping, sparse vibes |
| `bright` | (gallery; was Cadence Karaoke's) | Major sevenths, backbeat, root-fifth bass, sixteenth-note arpeggio |
| `racer` | (gallery) | Mixolydian, busy breakbeat, off-beat bass, stabs, detuned saw lead |
| `demo_drive` | (gallery; was the demo's) | Dorian four-on-the-floor with a pad |

Each style's `suggested_gates` is a starting point for the game's `stem_gates`.

#### Tempo: where it comes from and how to tune it

Styles have **no base BPM of their own**. The tempo comes from the game:

1. **The game passes `tempo_bpm`** to `play_music`: the segment's target cadence in rpm,
   so one beat = one pedal stroke. (Since #55 the shipped games play rendered themes at their
   own tempo instead, apart from Cadence Karaoke: see "Rendered music and effects".)
2. **`MusicGen` plays at `tempo_bpm × tempo_scale`**, clamped to 30-240 bpm
   (`MusicGen.music_tempo()`).
   - `tempo_scale` is a property of each style, in `games/audio/styles/<style>.tres`
     (the "Tempo" group in the inspector). It is `1.0` for every style today.
   - `2.0` is double time: one beat per leg, still locked to pedalling.
   - A game can also override it per request, e.g. `{"name": "drive", "tempo_scale": 2.0}`.
3. **`tempo_min` / `tempo_max`** in each style only set the gallery's slider. The gallery
   starts at their midpoint. They don't affect games.

To make a style feel faster everywhere, raise its `tempo_scale` (try `2.0` in the gallery
first). Cadence Karaoke keeps `1.0`, since its target line is the beat.

#### Style gallery

Open `res://audio/gallery/StyleGallery.tscn` in the editor and press F6.

- Pick a style, tempo, tempo scale, seed and length, then **Render and play**. The status
  line shows how long the render took.
- **Intensity** gates the stems at the style's `suggested_gates`; the checkboxes mute stems
  by hand.
- **Change tempo at next phrase** renders the new tempo while the old loop plays, then
  switches on the next phrase boundary, as described below.
- The buttons at the bottom play every effect preset.

It plays through its own players, not `AudioDirector`, so it needs no session.

### Sampled instruments and stem effects

`Samples.gd` decodes recorded one-shots once and caches them as mono floats at 22.05 kHz.
They must be imported uncompressed (`compress/mode=0` in the `.import` file), because GDScript
can't decode QOA. `MusicGen` loads a style's samples before its threaded render starts. A style
uses them through three `MusicStyle` properties:

- `drum_samples`: `{drum: "res://audio/samples/….wav", "gain": 0.8}` replaces those
  synthesised drums with recordings. The others stay synthesised.
- A voice's `sample` and `sample_hz` (in `bass_voice`, `harmony_voice` or `lead_voice`) play a
  recorded tone at any pitch. It is resampled from `sample_hz`, holds on a sustain loop between
  two rising zero crossings, and has the voice's ADSR and swept low-pass (`Dsp.render_sampled_note`).
- `stem_fx`: `{stem: {highpass, lowpass, drive, comp_threshold, comp_ratio, comp_release}}`
  runs one-pole filters, tanh saturation and a peak compressor on each rendered bar
  (`Dsp.apply_fx`), before the bar's edge fades, so loops stay seamless.

Reverb and bus compression are the game's, through `AudioDirector.set_bus_effects`. The `drive`
style (Dodge Ball) uses all of this.

### Tempo changes on a phrase boundary

Between games, new music crossfades in over 2 s as soon as it renders. Within a game, a **tempo
change** lands on a phrase boundary instead, with no gap and the beat grid unbroken. Cadence
Karaoke's target changes and Kart Race's cadence-following rely on this. `AudioDirector` does
it:

1. **A tempo change** is a `play_music` request with the same style and seed as the playing
   music but another `tempo_bpm`. Any other request crossfades as before.
2. **It waits, pending.** When its render is ready, it isn't started: `pending_music_key()`
   returns it.
   - A newer request replaces it; asking for the playing tempo again cancels it.
   - `stop_music()`, the rider's own music (`rider_music`), `audio.music: false` and a new
     session drop it.
3. **The phrase length comes from the playing stream**, not the tempo, because `tempo_scale`
   and per-bar rounding change it: `phrase_seconds() = stem length / (bars / 4)`, with `bars`
   from the style request (16 by default).
4. **Each frame** (not while paused), the director computes the time since the last boundary:
   `fposmod(position + AudioServer.get_time_since_last_mix(), phrase)`. The first frame in
   which it wraps (drops by more than half a phrase, so a few ms of mix jitter doesn't count)
   is just past the boundary.
5. **The swap.** The new tempo starts that far into its loop (`play(since)`), so its beat grid
   starts exactly on the boundary despite frame timing. It crossfades over 30 ms
   (`SWAP_FADE_SEC`), and each stem keeps its current level, with no gate fade-in. The
   director emits `tempo_swapped(key, since_boundary)`, then `music_started(key)`.
6. **In games:** call `play_music` with the new tempo (same style and seed) a few seconds before
   the change is due. The render (about 1 s on the tablet) must finish before the boundary,
   or the swap waits for the next one.

`sim_phrase_swap_check` plays a 4-bar loop at 180 bpm with the real `MusicGen`, then asks for
160 and 170 bpm. The 170 replaces the 160, waits out the phrase and swaps in 5.5 ms after the
boundary. The gallery (`StyleGallery.gd`) does the same with its own players. A live tempo
change is still to be checked on the bike.

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

`games.pck`, `games/.godot/` and `games/reports/` are git-ignored. The pack leaves out
`tests/` and `addons/gdUnit4/` (`games/export_presets.cfg`).

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
`InputBus` shows "keyboard simulator", and the main scene (the hub) starts a desktop visit
(`LocalHub`): a `hub_state` from `GameRegistry` and a desktop catalog, `start_plan` played
through `LocalSession` with the visit's keys, exit (then a new visit after 1.5 s) and the 20
min idle save. A game scene run on its own (F6) still gets a local Just Ride.

| Key | Input |
| --- | --- |
| Left / Right | lean x |
| W / S | lean depth |
| `+` / `-` | cadence |
| `[` / `]` | resistance |
| Space | stand (toggle) |
| P | pause / resume |
| Esc | end session (in the hub and on a visit's result card: as Android back) |

On a desktop:

- The local Just Ride is of the demo game.
- `request_exit()` (the summary's Done) restarts the local plan outside a visit; in the hub it
  exits the visit.
- A game scene run on its own (F6) gets a Just Ride of that game.
- The simulator also stands in for the head tracker and `TrackerLink`. `tracker_state`
  follows the game's tracker mode. The session's first camera mode plays a scripted
  calibration as `calibration_progress`: centre, left and right (plus in and back for
  `lean_2d`), or the centre alone once an earlier run in the same process covered the mode.
  `request_calibration` plays every step.
- Just Rides of games that declare `effort_in_just_ride` have the multiplier.

Under a `-s` script (the headless checks and GdUnit4), the local plan doesn't start by itself.
The script calls `Session._local.start(plan)`.

## Tests

**GdUnit4 suites** (`games/tests/unit/`) cover `Effort` (the curve, the grinding guard at 59
vs. 60 rpm, `effort: false`, `effort_avg`, the freezes), stars, the `Game` base class, the
registry and every game's declarations, the demo's rules, `AudioDirector`, and
`SessionDirector` against the local session. Import once on a fresh checkout, then run them
headless:

```sh
$GODOT_BIN --headless --path games --import
$GODOT_BIN --headless --path games -s -d --remote-debug tcp://127.0.0.1:0 \
  res://addons/gdUnit4/bin/GdUnitCmdTool.gd -a res://tests/unit --ignoreHeadlessMode
```

- The exit code is 0 when everything passes.
- Reports land in `games/reports/`, which is git-ignored.
- `-a` also takes a single suite, e.g. `res://tests/unit/effort_meter_test.gd`.
- The `--remote-debug` address keeps a script error from dropping into Godot's interactive
  debugger. The "Unable to connect" errors it prints are expected.
- `--ignoreHeadlessMode` is needed because the suites simulate no GUI input.

**Headless desktop playthroughs** drive the simulator and print PASS or FAIL:

```sh
$GODOT_BIN --headless --path games -s res://tests/sim_lifecycle_check.gd  # session lifecycle
$GODOT_BIN --headless --path games -s res://tests/sim_keyboard_check.gd   # the keys above
$GODOT_BIN --headless --path games -s res://tests/sim_demo_check.gd       # the demo, end to end
$GODOT_BIN --headless --path games -s res://tests/sim_hub_check.gd        # the Games hub, end to end
```

The Games hub's suites: `local_hub_test` (the desktop visit), `hub_nav_test`, `hub_state_test`
(defaults for an old or partial payload, the helpers, `HubPrefs`), `hub_layout_test` (every
screen at 1920x1080 with long strings: 120 px targets 24 px apart, text at 34 px or more, no
bake overflowing, Exit and Start apart, quiet bakes), `hub_music_test`, and the hub cases in
`session_director_test`. With a window: `tests/capture_hub.gd -- --out=DIR` screenshots every
hub screen, `tests/measure_hub.gd` checks the draw-call budget (run both with
`--resolution 1920x1080`), and `tests/capture_hub_cards.gd` re-renders the games' card pictures.

For generated audio (#36):

- **GdUnit4 suites:**
  - `sfx_synth_test` covers every preset: clean, deterministic, and repeats, loops and
    overrides working.
  - `music_gen_test` checks that the same seed gives the same music, that loops and bar
    joins don't click, that stem lengths fit the tempo and bars, levels and ranges, the form,
    serial vs. parallel renders, overrides and `tempo_scale`, the director contract on a
    worker thread, the phrase clock and the disk cache.
  - `audio_hook_test` plays every framework cue and the demo's music through `AudioDirector`.
  - `audio_director_phrase_test` covers tempo changes: pending until the boundary, the phrase
    length from the stream, jitter, the carried stem levels, replacement, music off, pause, and
    other music still crossfading at once.
- **Headless checks:**

  ```sh
  $GODOT_BIN --headless --path games -s res://tests/sim_gallery_check.gd       # gallery + phrase switch
  $GODOT_BIN --headless --path games -s res://tests/sim_phrase_swap_check.gd   # AudioDirector's tempo swap
  $GODOT_BIN --headless --path games -s res://tests/audio_bench.gd -- --tempo=90 [--wav=DIR]
  ```

  `audio_bench` times every style's 16-bar render, serial and parallel. With `--wav`, it
  writes a mix of each style and every effect as `.wav` files to listen to.
- **On the tablet:** every music render logs
  `OPENRIDE_GAMES music <style> <bpm> bpm <bars> bars: rendered in <ms> ms` (or `cache hit`).
  To time every style with a game running, create the flag file in a debuggable build's
  `user://`, then open the games host:

  ```sh
  adb shell run-as dev.digitalducktape.openride touch files/audio_bench   # mock build
  adb logcat -s godot | grep -E "audio_bench|music|frame fps"
  ```

  15 s after the engine starts, `Cues.gd` deletes the flag and times each style's uncached
  16-bar render at 90 bpm on a `WorkerThreadPool` thread
  (`OPENRIDE_GAMES audio_bench style=… ms=…`). The `frame fps=` lines show the game's frame
  rate meanwhile.

Dodge Ball (#39):

- `dodge_ball_logic_test` covers the rules: collision, the 0.8 s warning, arrival spacing,
  shield drain and refill, the power bonus, lives and runs, circuit penalties, waves, streaks,
  the stars and the time of day.
- `dodge_ball_scene_test` covers pause, per-rider options and the result's stats.
- `dodge_ball_status_test` covers the themed status widget (`DodgeStatus.look`, UI polish
  2026-10-19): with the longest texts it fits the 850 x 120 top-centre budget, its parts don't
  overlap and it keeps the road clear; nothing moves when the caption (SHIELD, PEDAL UP!, NO
  SHIELD) or the ×2 POINTS badge changes; an empty shield throbs without a redraw every frame;
  every label is the display face at 34 px or more.
- `tests/capture_dodge.gd` takes desktop screenshots in each lighting (it needs a window). With
  `--play=SECONDS`, add `--write-movie FILE.avi --fixed-fps 30` to record the game's own mix,
  bus effects included, without playing a sound.

`sim_demo_check` plays a three-segment local circuit at 4× speed:

- the intro card and calibration;
- a warm-up played with the arrow keys, which must score;
- a tap on the work segment's card, which must do nothing, then its "Skip this game" button;
- pause and resume with P;
- Esc to end, then the summary and Done.

## Running on the bike

1. Install with `adb install -r app/build/outputs/apk/debugReal/app-debugReal.apk`. The `-r`
   keeps the rider's data, so never uninstall.
2. On the tablet, tap **Enter Games** (the Games tab, or the Games card on Home). The Games hub
   opens; everything is picked there, and the whole visit records as one ride on Exit games.
3. The hub asks for the CAMERA permission the first time the rider taps the camera chip
   ("Allow") or a camera game's "Allow camera". To skip the prompt in a test, grant it with
   `adb shell pm grant dev.digitalducktape.openride.real android.permission.CAMERA`. A
   permission refused before the process started reads as "Allow" (`ask`) until the host has
   asked once; Android then answers at once and the chip says "Not allowed".

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
- `SessionDirector` prints an `OPENRIDE_GAMES frame fps=… phase=… tracker=… lean_x=…
  lean_depth=… standing=… score=… effort=…` line every 5 s, and every second while the
  camera runs.
- `Session` logs each calibration step as it starts, retries and completes
  (`OPENRIDE_GAMES <- calibration_progress left 2/3 attempt 1 …`).
- `OpenRideGames` lines come from the Kotlin side of the session.

## Dodge Ball (#39)

**Modes** (the per-rider "Mode" option): **Dodge** keeps away from danger-red balls; **Catch**
steers into shimmering gold ones. In Dodge a hit with the shield up drops the shield; with it
down it costs 50 points (a red −50 floats up) and, in a Just Ride, a life too (rider, 2026-10-27:
a Just Ride hit used to take only the life, so the score never showed it). A Just Ride's score is
its best run as that run ended, its hits taken off. A ball caught with the shield down is fumbled (no points,
streak lost); a miss costs the streak, and three in a row a life in a Just Ride. Nothing is ever
taken off in Catch, and every catch ball arrives within reach of the last. The result's
`variant` is the mode played longest (`""` for Dodge, `"catch"`).

**Speed** follows cadence: `0.0018·rpm² + 0.04·rpm` m/s (9 m/s at 60 rpm, 22 at 100, stopped at
0), eased at up to 7 m/s². Cadence rather than power, because it's what the rider feels and it
answers at once; power has its own reward. The view widens a little with speed, streaks rush
past above about 90 rpm, and wind rises with speed. Each ball keeps the approach speed it was
thrown at, so arrivals stay timed in seconds and the 0.8 s warning holds at any speed.

**Stars** (points a minute): a perfect ride at 1.0× reaches 2 stars without the power bonus; 3
stars needs the bonus and some effort multiplier, in 90 s circuit slots and two-minute Just Rides
(`dodge_ball_logic_test`).

### On the tablet

Dodge Ball is the first 3D game. What holding 60 fps on the Gen 2 tablet (PowerVR GX6250,
GL Compatibility) took, measured with the mock build:

- **It is fill-rate bound.** The 3D view renders into a `SubViewport` at 0.67 of 1080p, drawn
  scaled under the HUD, which stays sharp. `Viewport.scaling_3d_scale` below 1 hung the
  renderer on the tablet.
- **No MSAA:** 2x halved the frame rate.
- **The road and verges are unshaded**, lit and fogged by hand. They cover most of the screen,
  and the engine's per-pixel light and fog cost about a third of the frame.
- **Shaders sample a 64×64 noise texture** instead of hashing with `sin()` per pixel.
- **Everything in the world lights itself** with the shared `WorldLook` (Dodge's grade in
  `shaders/look.gdshaderinc`): the road, verges, sky, scenery (per vertex, painted AO, one
  material per surface look shared by every chunk), the far horizon mesh and the handlebars
  (one merged mesh). `DodgeWorld.look_for` builds the look from the time-of-day preset. Only the
  balls use the engine sun. The Kenney kit's metallic materials are dropped for this.
- **Bursts and sparks are one pooled MultiMesh** (`shaders/fx.gdshader`): a burst writes its
  instances once and the vertex shader moves them, so they cost no main-thread simulation.
  The pool hides itself when idle. The fence is one mesh for the whole road, not one a chunk.
- **The full-screen effect overlay is hidden while idle**, and HUD labels only change when
  their value does. A theme override every frame re-laid-out the HUD.
- **Release builds don't check for null.** A GDScript call on a null node crashed the exported
  build with SIGSEGV instead of an error, so test on the tablet as well as the editor.

The render scale is now 0.62, for headroom with face tracking on the bike (it read 55-57 fps
at 0.67 with the effort badge re-laying out the HUD every frame, since fixed).

For measuring, set `DEV_TUNING` in `DodgeBall.gd` (off in every build). The game then logs
`OPENRIDE_GAMES dodge_ball perf game_ms=… process_ms=… draw_calls=…` every 5 s, and if
`user://dodge_tuning.cfg` exists, it overrides the render settings
(`[render] scale=0.67 msaa=0`) and switches parts off (`[world] sky=false road=false
verges=false scenery=false balls=false rig=false fog=false screenfx=false`). Write it with
`adb shell run-as dev.digitalducktape.openride …`.

On the desktop, `tests/capture_dodge.gd` takes the look's captures (`--nohud`, `--scenes=`,
`--mode=catch`, `--close` for a ball near the bars, `--bonus`) and with `--perf` prints each
preset's mean frame time with vsync off, draw calls and triangles. `dodge_world_look_test`
covers the look's materials, meshes and FX packing. The art direction is
`games/dodge_ball/ART_BIBLE.md`.

## Tug of War (#40)

Your watts against a bot's over a rope across a river, in first person. `TugLogic` holds the
rules (headless-tested by `tug_logic_test`), `TugWorld` the 3D view, `TugStatus` the HUD widget
and `TugAudio` the sounds; `TugOfWar.gd` wires them to the framework.

**The rope.** The marker `p` runs from -1 to +1: `dp/dt = 0.25 × (power − bot) / FTP`. Equal
watts is a stalemate, and holding 20% of FTP above the bot wins in 20 s. A round ends when `p`
reaches either end, or at the buzzer (60 s), where `p > 0` wins (a dead heat is a loss).

**The bot** holds 60% of FTP (`bot_watts`; 50% easy, 70% hard) and surges 20% of FTP above that (`surge_watts`) for 5 s, at
most one surge every 12 s, telegraphed a second early by a drum roll and a bracing pose. A surge
counts as answered if `p` never fell more than 0.2 during it (`surges_answered`).

**Modes.** A circuit or timed Just Ride plays rounds back to back until the timer ends. An open
or rounds Just Ride plays the rider's **Mode** option: **Match** (best of 3 or 5, or the rounds
the plan asks for) or **Ladder** (each win faces a bot 5% of FTP stronger, with a new name and
colour; the first loss ends it). A 60 s recovery card between rounds shows the next bot's watts.
The result's `variant` is `"ladder"` for the ladder and `""` otherwise.

**Scoring.** Every round won awards 1000, and every watt over the bot awards 0.15 points a
second, both through `Effort.award`. Stars are points a minute: a perfect ride (15% of FTP over
the bot all the time) earns about 2250 a minute at 1.0×, which is 2 stars, and 3 stars needs
about 1.3× effort (`tug_logic_test` checks this for every difficulty).

**Options** (per rider): Mode, Match length, Scene (time of day, shared with Dodge Ball's
presets) and **Brace lean**.

**Brace lean** is optional and off by default. With it on, leaning in (`lean_depth` above 0.5)
during a surge makes the rope slip at 75% of its speed. It never helps a gain, and it isn't
counted in `effort_avg`. Because the camera should run only for riders who use it, the game
overrides `Game.tracker_mode_for_segment`: `lean_2d` with brace lean on, otherwise `off`.
`SessionDirector` applies that mode (a copy of the declarations from
`GameInfo.with_tracker_mode`) for the segment, and the Calibrate button shows only then.

**Look** (`games/tug_of_war/ART_BIBLE.md`; graphics pass 2026-10-19, `GFX_POLISH.md`). A summer
fairground across a lazy river: the rider's gloves on the rope at the end of a plank pier, a
wind-up tin robot on the far pier, a flag on the rope between them. Winning hauls the bot off its
pier into the river; losing pulls the camera in. It follows the tablet recipe (a scaled
`SubViewport`, no MSAA) on the shared world look (`WorldLook`, Tug's grade in
`shaders/tug_look.gdshaderinc`): every surface is unshaded and lit by hand from one table
(`TugWorld.look_for(preset)`), with no engine lights, fog or post passes.

- `TugMeshes` bakes the statics into one vertex-coloured mesh with painted AO (`KartMeshKit`
  shapes): sloped earth banks, reeds, shore rocks, hills, the nature-kit trees, pier frames,
  pilings, torch posts, masts, bunting, string lights, a striped tent and hay bales.
  `scenery.gdshader` reads `COLOR.a` as 1 − sway, `UV.x` as ground grain and `UV.y` as a bulb's
  glow.
- `deck.gdshader` draws the planks in world space (two noise reads, lines antialiased with
  `fwidth`), with the bot's blob shadow and the torches' warm pools. `water.gdshader` (two reads)
  has glitter along the sun's path, a fresnel to the two-colour sky, foam at the banks and
  pilings, and shade under the piers.
- The bot is one mesh (`bot.gdshader`: body colour as a uniform, the key spun in the vertex
  shader, faster on a telegraph), plus ears or horns, self-lit eyes and chimney steam in a
  telegraph or surge.
- The crowd is a GPU billboard MultiMesh cut from a two-frame sprite drawn in code; the
  flames are additive cards; the flag, bunting, reeds and lily pads all move in their shaders.
  Per frame, GDScript lays out the rope's 22 segments and poses the bot, nothing else.
- **Tablet performance pass** (`GFX_POLISH.md`, Tablet performance; it ran 48 fps in the intro
  and 35 in play with the tracker on). The sky shader runs only in its cubemap pass (256 a face,
  rebuilt when the time of day changes; the sky is set as the reflection source so the cubemap
  stays up to date) and the background samples it. The vignette is painted into the vertex
  colours of the grid that draws the view on screen (`TugMeshes.view_image`, a `MeshInstance2D`),
  not in each shader. The water, deck, riverside and crowd haze per vertex
  (`haze_amount`/`hazed` in `tug_look.gdshaderinc`), and the water's flat light is per vertex.
  `prewarm` draws the steam, ripple and droplets behind the intro card so their shaders compile
  then. The lost-round flash tints the view's image instead of a full-screen overlay.
  `RenderScaleStep` drops the render scale from 0.62 to 0.55 once if a round's 4 s average
  falls under 54 fps (`OPENRIDE_GAMES tug_of_war quality tier=1 fps=… scale=0.55`).

About 13 draw calls for the world (55 before), 57 in play with the HUD (99 before), and 29k
primitives on the desktop. On the tablet it
held 59-62 fps before the pass (mock build, 2026-10-03); re-measure with Brace lean on.
`tests/capture_tug.gd` takes desktop screenshots (`--stats` prints draw calls and frame times)
and, with `--play=SECONDS`, plays rounds for a recording (add `--snaps` for half-size stills of
each HUD state instead of a video). `tests/measure_tug.gd` prints the draw calls and render CPU
in the intro and in play, GDScript per frame, and each world part's A/B frame-time cost at a
scaled-up render size (`--scale`, `--scene`, `--shot`). `tug_world_test` covers the shaders, the look table, the baked
meshes, the per-frame budget, the sky cubemap, the view grid's vignette and the warm-up;
`tug_game_test` the stats at finish, the flash and the quality step; `render_scale_step_test`
the governor.

**UI** (`framework/ui/UI_STYLE.md`; punch list `games/tug_of_war/UI_POLISH.md`). The look is a
rustic riverside fairground: `GameTheme` rope orange `#FF9F1C` on bark `#2A160B`, badges
leaning 0.12, the face upright. `TugStatus` is the hero tug meter: the watts either side of a
420 x 40 rope bar, filled from the centre towards the leader in that team's colour (YOU in the
gloves' blue, BOT in the bot's body colour, lifted for contrast), with a rope knot at `p`; under
it, best-of pips (a "RUNG n" badge on the ladder, "WON n" in an endless ride) and the bot's
name. PEDAL!, SURGE! (breathing) and REST n take the pips' place while they hold. At most
790 x 115 px with the longest texts (`tug_status_layout_test`), no per-frame code, about 14 draw
calls (57 in play on the desktop after the graphics pass, 99-101 before). The intro card shows the first bot (`TugBotPortrait`).

## Safe Cracker (#41)

A recovery game played with the resistance knob: dial it to each number of a combination and
hold it there to click a tumbler. `SafeLogic` holds the rules (headless-tested by
`safe_logic_test`); the picture is 2D shapes drawn in code (`SafePlaces` for the six rooms,
`SafeBackdrop` for their ambient life, `SafeBody`, `SafeDoor` and `SafeDial` for the safe),
`SafeStatus` is the HUD widget, `SafeBanner` the game's callouts and `SafeAudio` the sounds.

**Look** (`framework/ui/UI_STYLE.md`, punch list `games/safe_cracker/UI_POLISH.md`): a noir heist
in brass `#E8B04A` and soot `#14110D`, upright (`SafeCracker.look`, a `GameTheme`, also styles
the HUD, the intro card and the pause screen). The dial's reading is the hero (96 px, green on a
shown target) in the bottom gap the needle never sweeps; the target is on a brass-edged plate
above the bezel; the tumbler lights are a column right of the bezel, and the newest pops. The
status widget is a "VAULT n" badge, a brass pip per safe cracked and "MAX 120 W" ("OVER 120 W"
in amber). The alarm ("ALARM: EASE OFF", breathing, with the safe glowing red) and "CRACKED!
+n" (a gold hero) show in `SafeBanner`, a layer under the HUD between its top bar and the safe,
never in the HUD's centre message, which would cover the dial. `safe_scene_test` checks the
layout (no overlaps, the needle's sweep, the status budget) and the events.

**Graphics** (`games/safe_cracker/ART_BIBLE.md`, punch list `GFX_POLISH.md`): one heavy steel
safe in a pool of light. Every shape goes through `SafeMesh`, which batches a node's shapes into
one `canvas_item_add_triangle_array` with per-vertex colours and a 1.2 px feather for
antialiasing. In Compatibility each `draw_circle`, `draw_colored_polygon` or `draw_arc` is a draw
call of its own (the bank's rivets alone were 168), so a whole room, body or door is one call.
Each place has one key light (`SafePlaces.PLACES[i].light`): a smooth pool drawn in the room's
batch, with the safe's steel (`SafePlaces.steel_shade`), bevels and cast shadow agreeing with it.
The room's batch and the vignette are baked once per place into one texture at the on-screen size
(`SafeBackdrop.bake`, a SubViewport), shown as one opaque sprite. Each place's room and body are
built once (`SafeMesh.built`), the next place's while a cracked door stands open.
The door's layers (`SafeDial` docs) redraw only on a change: the needle is a static drawing turned
by `rotation`; the reading's number has its own text-only layer; the door swing is a perspective
turn about the hinge in `safe_door.gdshader` (a uniform; the door's thickness comes from UV
depth). Ambient life never redraws: rain on the office window and the porthole's sea are
shaders on one rect each, the cabin's lantern sways on a rotation tween, the lab's flasks shimmer
in a shader, and 16 dust motes drift in the key light (`CPUParticles2D`). A crack fires 18 gold
sparkles; the alarm adds a red side wash. `safe_gfx_test` checks the hardware's clearances, the
batches, that the needle and the swing redraw nothing, each place's ambient nodes, that the room
bakes once per place and the next place is built ahead. In play: 47 draw calls on the desktop
with the HUD (86 before the graphics pass; the bank was 258, the lab 125).

**Tablet cost** (`GFX_POLISH.md`, "Tablet performance"). The tablet is fill-bound and 2D is all
blended, so what counts is the pixels shaded a frame, seen or not. `tests/measure_safe.gd`
(needs a window) prints each layer's pixels per place, the batches rebuilt a frame and the build
times. Shapes under opaque ones have holes (`SafeMesh.round_frame`, `holed_round_rect`, the
`hollow` of `glow` and `soft_shadow`), and the vault draws only while the door is open. Play
shades 2.1-2.2 screens a frame (6.9-7.7 before the tablet pass, which read 50 fps on the bike,
31 in the intro), 3.6 at worst (a crack, or under the intro card).

**Rules.** The dial shows the live `resistance` reading (0-100). Hold within the tolerance of
the target for the hold time (easy ±3 and 1.2 s, standard ±2 and 1.5 s, hard ±2 and 2 s) to click
a tumbler. Each number is at least 6 from the one before, drawn from `res_min`-`res_max` (15-40).
The alarm trips when power, smoothed over about a second, stays over 1.25 times `power_cap_watts` (60% of FTP) for 2.5 s; it resets the tumbler. It is easy-going on purpose: the first version tripped for ordinary pedalling.
cadence under `cadence_min` (60) dims the dial and pauses the hold.

**Knob lag.** The reading lags the knob, so a slip off target keeps its progress for 0.4 s
(`SafeLogic.GRACE_SEC`) and then drains at 1.5× the rate it filled. The needle always shows the
reading as received. Tune the grace, tolerance and hold against the lag measured on the bike.

**Safe after safe.** Cracking a safe swings the door open on the gold, then the next one slides
in, in a different random place (a night office, bank vault, museum hall, ship's cabin,
laboratory or old library; never the same twice in a row). Each is harder than the last: a
longer combination (up to 6), a tighter tolerance (down to ±1), a shorter hold (down to 0.9 s),
and the target hidden from the 4th safe (hard hides it from the start). A hidden target is found
by ear: a proximity tick speeds up as the reading closes in. The goal is how many safes you crack.

**Scoring and stars.** Each safe is worth `1000 − 5 × seconds − 100 × alarms` (floor 0) plus 200 for
opening it; there is no effort multiplier. Stars are points a minute, so they follow how many safes
you open: a careful rider turning the knob at 2 units/s earns 2 stars, and a quick, accurate one 3
(`safe_logic_test` models both, with 0.6 s of lag). The thresholds are provisional until tuned on
the bike.

**Options** (per rider): Place (random or one fixed place), Target number (show or hide it) and
Click sounds. Stats: `vaults`, `fastest_crack`, `alarms`, `avg_power`. `tests/capture_safe.gd`
takes desktop screenshots (each with its draw calls; `--nohud` hides the HUD; `--measure=SECONDS`
prints the desktop frame time, render CPU time and draw calls with vsync off) and, with
`--play=SECONDS`, cracks safes with a scripted rider for a recording.

## Cadence Karaoke (#42)

A rhythm game for your legs, in first person down a neon tunnel. Your cadence is an orb that rolls
along the floor. A box is marked on the floor, a translucent lane between two dim gates with a
bright white beat line across its middle, and beat rings fly down the tunnel toward the line, one
landing on it each beat. (The orb sits on the floor so its place against the line reads as plain
up and down the screen; floating in the tunnel made depth hard to judge against the rings.)
Your cadence is an orb with three places. While it matches the target (within the scoring
tolerance, ±5 rpm on standard) the orb sits on the centre line inside the box; **10 rpm or more
above** the target it is in front of the box (further up the floor); **10 or more below** it is
behind the box (nearer you, lower on the screen). In between it travels out through the box's edge, so the box is
exactly where you score. `CadenceLogic` holds the rules (headless-tested by `cadence_logic_test`),
`CadenceWorld` the 3D view, `CadenceStatus` the HUD widget and `CadenceAudio` the sounds.

**The gap.** `gap` is -1 (behind the box) to 1 (in front of it), 0 inside the band, and depends
on the cadence right now and nothing earlier. The target is always a multiple of 5 rpm (60 to start; a circuit's profile moves it in 5-rpm jumps). The HUD widget (`CadenceStatus`) makes the target rpm its hero (96 px, the world's neon
gradient, popping when it changes), with a chip for a pending change ("125 in 12 s"), "In band" and
the streak multiplier (gold, popping on each step, "×2!" slammed at the max), and a WARN badge with a
drawn arrow, "SLOW DOWN" ▼ or "SPEED UP" ▲, when out of the band ("EASE OFF", red and breathing,
over the power cap). The badge flashes on each beat. The look (`ui_theme()`, the HUD skin, the −5 and
+5 rpm buttons at the bottom centre) is rebuilt per segment from `CadenceWorld.theme_color`, ink
`#12052A`, and again when the rider changes the colour option. While a pace change waits for its boundary, whichever of the old and new targets is
nearer the rider's cadence counts, so riding the new pace is never "ahead" of a beat that hasn't
moved. **The bike reports a new cadence about once a second** (once a pedal revolution): the
service streams frames at 5 Hz (`REPORT_RATE_MS` 200) but each rpm repeats for about four, so the
orb steps with the readings. It is eased a little so it doesn't jump.

**Target.** The rider's target cadence starts at 60 rpm (internally the "pace"; the player only
ever sees the target rpm) and can adjust it at any time with the − and + buttons under the view (5 rpm a step; `,` and `.` on the
desktop). The change waits for a phrase boundary: the game asks `AudioDirector` for the music at
the new tempo (same style and seed), and applies the new target on its `tempo_swapped` signal, so
the beat changes with it. The music is "Neon Lines" (`CadenceMusic`, laid out by `SongSequencer`
at the target cadence; two beats a stroke below 70 rpm), and a swap carries on from the same
place in the song (`swap_keeps_place`). A change that hears no swap applies after 16 s, or 1.5 s
with no music. A moving target (a profile) asks for a new tempo every 6 s when it has drifted 3 rpm.

**Circuits.** A circuit segment sends `cadence_profile` (`[{t, rpm}]`: a warm-up ramp 70 to 90, a
recovery of 80 to 85, a cool-down 85 to 65); the rider's adjustment shifts all of it, and it
cycles if the segment runs longer. A Just Ride has no shapes: the target stays where the rider
puts it.

**Scoring.** Inside the band (±5 rpm; ±7 easy, ±4 hard) you earn 10 points a second, 15 in the
±2 bonus band, times a streak multiplier that grows by 0.25 every 10 s to 2.0. The streak
survives 1 s outside the band (the cadence reading is noisy). The music's lead stem plays only
while you are in the band. There is no effort multiplier.

**Power cap.** Warm-up and cool-down 65% of FTP, recovery 60%; a Just Ride caps at 75%
(Endurance). Scoring freezes ("ease off") only when power, smoothed over about a second,
stays over 1.25 times the cap, so ordinary pedalling never trips it.

**Stars** (points a minute, the same for every difficulty): 300, 1000 and 1500. A rider whose
cadence stays within about ±2 rpm of the target earns about 1700, one who wanders by ±6 about
1100-1370, and one by ±12 under 900 (`cadence_logic_test`). Stats: `pct_in_band`, `longest_streak`,
`avg_cadence`, `avg_power`, `pace`.

**Options** (per rider): Metronome (a beat tick, off by default) and Colour (by
workout part, or one fixed colour). The beat visuals run on the target's clock, which the music is
laid out at; check their alignment with the music on the bike. `tests/capture_cadence.gd` plays a
scripted ride for a recording (`--looks=` stills per colour, `--measure=SEC` the 3D view's draw
calls and frame time, `--overdraw` an overdraw still).

**The look** (`games/cadence_karaoke/ART_BIBLE.md`). Everything is unshaded and drawn in its
shaders, with no engine glow or post pass: the tunnel's grid (`grid.gdshaderinc` with floor,
wall and ceiling wrappers) has antialiased lines that fade to their average far away, the
theme's neon on the long lines and its secondary (`CadenceWorld.SECONDARY`) on the cross lines;
the floor reflects the rings and the beat line, the walls carry equaliser columns on the beat's
clock, and a portal closes the far end. The rings are a thin frame mesh (`frame_mesh`, no
`discard`), the orb a white-hot core with its state colour as a rim and an ink outline, a halo
and a pool and trail on the floor. In the bonus band, sparks fly off the line as a ring lands
(a pooled MultiMesh moved by its shader); while scoring is frozen the tunnel desaturates. The
grade is the shared world look's (`cadence_look.gdshaderinc` sets Cadence's defines); additive
layers take only its linear parts. `CadenceWorld.ring_z` places the rings for the MultiMesh and
for the floor's reflections alike (`cadence_world_test`).

## Kart Race (#43)

A Grand Prix of 3-lap races against seven bots on four original tracks. The rider pedals to
drive, leans in front of the camera to steer, leans hard to drift, and taps to use items. The
module contract (interfaces, the scene tree, the signal map, the handling and bot details) is
`games/games/kart_race/DESIGN.md`; this section is the overview.

**How it plays.**

- **Pedal.** Cadence plus resistance drive a virtual bike (85 kg, the road's grade at half
  strength): the measured watts plus a cadence term (0 below 30 rpm, 80 W at 100 rpm), so
  spinning alone cruises and resistance adds speed on top (rider feedback 2026-10-19: 100 rpm
  at low resistance read 18 W and barely moved the kart). Not pedalling coasts to a stop. The
  kart runs at the bike's speed × 2.4. Nothing is rubber-banded: the bots ride at fixed shares
  of the rider's FTP. On a climb the climbing force is capped at what the watts push at
  2.5 m/s, so a weak rider crawls up instead of stalling. Standing on a climb cuts the drag
  20%, and riding 1.5-8 m behind a kart drafts it.
- **Lean.** The lean steers, through a dead zone and a curve. The **assist** (option: off,
  low, high; high by default) adds the road's curvature, a pull back parallel to it and an
  edge guard. When the tracker loses the face, the assist goes to full and no drift starts.
- **Drift.** A hard lean (0.65 or more, held 0.12 s, at 40% of cruise or faster) hops into a
  slide; leaning further in tightens the arc. The charge fills in a corner (a quarter as fast
  on a straight) through three spark tiers. Turning the **resistance knob** up during a drift
  charges it 1.6× faster. Easing the lean releases a mini-turbo by tier.
- **Items.** Rows of pods on each track. The item button (bottom right, a 260 px disc with a
  hit circle 1.25× its radius, at the far end of the screen from End) spins a 0.9 s roulette,
  then fires on a tap. An item held unused for 2 s pulses (a scale tween and a gold rim glow).
  The drift meter is an arc round the button's upper-left edge. The Auto items option uses the bots' policy instead.
- **Grand Prix.** The cup runs Meadow Ring, Canyon Dash, Harbor Lights and Frost Pass in
  order, reversed the second time round. Points per race are 15, 12, 10, 8, 6, 4, 2, 1. A
  timed Just Ride sizes its last race to the time left (1-5 laps), and the game ends the
  segment on that race's finish line (`timed_end_mode = "game"`). An open Just Ride races until
  the rider ends it. A results board follows each race, and the podium follows the last: the
  top three's own karts land on stepped blocks built on the start straight (`KartPodium`)
  under a held camera, with the standings beside them. The title chip and the lap badge read
  "Race n/N" (a timed GP's plan; "Race n" when open-ended).
- **Boosts** also come from boost pads, a rocket start (70 rpm or more while "2" shows) and
  the Turbo Can.

**Tracks** (each 1.0-1.3 km, laid out as route cards of straights and exact arcs; climbs stay
under about 6%, and every track has one climb per direction):

| Track | Theme | Length | Character |
| --- | --- | --- | --- |
| Meadow Ring | green hills, grandstand, windmill | 1,148 m | wide sweepers, a long banked left-hander, a climb to a crest, a winding descent |
| Canyon Dash | red layered rock, mesas, a dry riverbed | 1,278 m | esses through the narrows, a long climb to a hairpin, a sweeping drop |
| Harbor Lights | a seaside town at sunset | 1,033 m | a quay straight, a tight chicane between warehouses, a long right-hander |
| Frost Pass | snowy pines, an ice-blue lake | 1,264 m | three banked downhill turns, a fast sweep along the ice, the climb back |

**Items:** Turbo Can (a 1.2 s boost), Bumper Puck (fired ahead, bounces off walls three times),
Seeker Drone (hits the kart one place ahead), Goo Puddle (dropped behind), Shield Bubble (8 s,
absorbs one hit) and Draft Magnet (3 s pull toward the kart ahead). The odds favour the back of
the pack.

**Racers:** eight original animal drivers in light, medium and heavy karts. Juniper (fox),
Tofu (panda), Pip (frog), Clover (rabbit), Bramble (bear), Ripple (otter), Pebble (penguin) and
Scout (raccoon). The rider picks one (the Driver option), and the other seven become bots with
their own line, drift, item and aggression personas. Bot power (plus the same cadence term): easy
0.40→0.85 of FTP, standard 0.50→1.00, hard 0.60→1.15, so an ordinary ride (80-90 rpm at 30-40%)
sits mid-pack.

**Scoring.** Live awards go through `award()`, so the effort multiplier applies: an overtake
+15, a mini-turbo +10/20/35, an item hit +25, a lap +30, and the race's points × 20 at each
finish. Stars are points a minute (standard 120, 205, 330): mid-pack earns one star, a podium
two, and three takes podiums plus effort.

**The pick.** The kart and the starting track are picked in the Games hub, before Start (plan
phase C, rider request 2026-10-20): the game screen's "Your kart" grid (eight cards: the
racer's baked portrait `ui/portraits/<racer>.png`, name, class, the kart's colour; the chosen
one wears the rider's name) and "Starting track" row (four cards with the baked thumbnails).
Both are `where: hub` `kind: cards` options. Gameplay then goes loading → calibration → the
"Get ready" card → the title fly-over → the grid's 3-2-1-GO, with no picker: `_on_prepare`
builds the chosen track once, behind the intro card. The GP starts at that track and the others
follow in cup order. Re-bake the portraits with `tests/capture_kart_portraits.gd` when a racer's
look changes.

**Options** (per rider): Your kart and Starting track (hub only, picture cards), and Steering
assist, Camera (chase or close) and Auto items (segmented, under the hub's "More options", and on
the pause screen). The rider's kart carries their profile name (`rider_name`). **Stats:**
`position`, `races`, `wins`, `podiums`, `best_lap`, `race_time`, `boosts`, `items_hit`,
`avg_power` and `ghost_trace` (the rider's distance every few seconds, for future ghosts).

### On the tablet

Kart Race is the heaviest game so far: eight skinned karts, four dressed tracks and a full
HUD, with the face tracker running. Here is what holding the frame rate took on the Gen 2
(PowerVR GX6250, GL Compatibility):

- **Render scale 0.66.** The 3D view renders into a `SubViewport` at 0.66 of 1080p (0.62
  before polish pass 2), with no MSAA, and is drawn scaled under the HUD (Dodge Ball's pattern; `scaling_3d_scale` below 1
  hung the tablet). No full-screen pass: the colour grade is folded into every world shader,
  and the speed lines are thin polygons.
- **Cheap surfaces.** The road and terrain are unshaded, with hand-made light and fog.
  Scenery is lit per vertex, repeats go through MultiMesh, and karts get blob shadows. Each
  kart is one mesh, rigged in the vertex shader.
- **Culling.** Trackside dressing sits in cells centred on themselves, with a 230 m
  visibility range. Karts within 4.2 m of the chase camera are hidden, so none fills the
  screen.
- **Baked HUD.** `KartBaked` moves a widget into its own small SubViewport, which renders
  only when something in it changes. On screen it costs one draw call. The lap badge, racer
  list, ride strip and place badge are baked (the HUD went from 74 to 15 draw calls), and so
  are the results board's and the podium's header, rows, plates and pill (122 to 13, and 102
  to 16). Portraits share one atlas and one material. A hidden bake (the race HUD under a
  board) waits until it shows, an idle one doesn't even `_process`, and a board builds its
  bakes when it opens and frees them all when it closes, so the race runs with 6 viewports
  (the screen, the 3D view and the HUD's four bakes), not the 17-20 that piled up after the
  first board.
- **Staggered bakes.** Bakes that share a `KartBakeQueue` take turns: the results board and
  the podium render one bake a frame, the HUD two. When a board appeared, all eleven of its
  bakes rendered in one frame (about 205 draw calls on the tablet; 186 for the board alone on
  the desktop). Now the board alone peaks at 20 on the desktop, and a board frame on the tablet
  peaks at 94-117 with the race behind it.
- **Serial music renders.** Kart Race sets `MusicGen.parallel` off while it runs, so a tempo
  change renders on one worker thread. The parallel render took every core for 1-2.5 s, twice
  per tempo change, and the frame rate fell to 16-30 meanwhile.
- **30 Hz logic, drawn at the frame rate.** The race logic steps at 30 Hz and the views draw
  every frame between the last two ticks (`KartState.draw_into`); contacts are swept over a tick.
  The tracker's lean arrives at 30 Hz anyway.
- **Less to draw-sync.** Karts behind the camera skip posing and exhaust; karts past 18 m pose
  at 30 Hz and past 35 m at 20 Hz (their position still moves every frame); pods beyond 80 m or
  behind keep their last pose; the effects simulate at 30 Hz.
- **Adaptive quality.** `KartQualityGovernor` averages the frame rate over each 4 s of racing.
  Below 56 fps it steps down one tier, at least 4 s apart, and never back up during a session.
  The game's floor is tier 1, half the effects' particle caps. The other tiers (foliage to
  150 m, half the crowd, render scale 0.58) cost the look and saved nothing measurable: tier 0
  against tier 4 with the tracker running, back to back on Meadow at the same clocks, gave
  40.4 and 41.6 fps and 9.3 ms of render CPU each. The tuning file can still force them. Each
  step is printed (`OPENRIDE_GAMES kart_race quality tier=…`), and the dev perf line carries
  `tier=`.

**Where the time goes (2026-10-15, mock build, `DEV_TUNING` on).** The tablet is
**CPU-bound on Godot's main thread, not fill-rate bound.**

- simpleperf on the GL thread (camera on): it is 92% busy. 59% of its samples are in Godot
  (unsymbolised, but the hottest block looks like the GDScript VM), 17% in the GL driver,
  9% in libc and 8% in the kernel.
- `tests/measure_kart_cpu.gd` splits the GDScript per frame on the desktop. Physics is 24%,
  the bots 22%, kart views 17%, effects 14%, item views 7%. The tablet runs it about 5× slower:
  6 ms per 60 Hz tick.
- Fill-rate trims don't move it. Render scale 0.40, no scenery, no HUD, and every tier at once
  each landed within the run-to-run spread (±3 fps).

**The camera's cost.** With the tracker running, the tablet throttles within a few minutes:
CPU0 drops from 1.57 to 1.1 GHz, and cores go offline. Kart Race then falls to about 25-30 fps
whatever is drawn. With the camera off, on the same hot tablet, it holds 53-57 fps, and CPU0
stays at 1.57 GHz.

Analysing only every other frame (15 Hz) didn't help (26 fps). Asking the camera for 15 fps
was ignored (the HAL still delivered 30). The camera stack itself (the legacy HAL, its GL
thread, the RGBA conversion), not the face model, looks like the cost. That's the next thing
to cut; nothing in the game's content will make up 25 fps.

**Measuring the tracker without a rider.** In the mock debug build, the file
`files/tracker_load` keeps the camera and face detection running after a calibration fails for
no face:

```sh
adb shell run-as dev.digitalducktape.openride touch files/tracker_load
adb shell run-as dev.digitalducktape.openride rm files/tracker_load
```

The game still sees the tracker as off ("Camera steering is off", tracker state 0), so it plays
as it does with nobody there, but with the tracker's real load. It's read on each tracker
command, not per frame. Release and `debugReal` builds ignore it
(`DefaultHeadTracker.keepCameraOnNoFace`, `DefaultHeadTrackerTest`).

Measured on 2026-10-15 with the mock build and `DEV_TUNING` on: a 10-minute standard Just Ride,
with `[world] laps=1` so the Grand Prix covers all four tracks (about 60 s each), the boards
and the podium. The HUD was on and the governor on. fps is from the 1 s frame lines; draw
calls are averages, with the most seen in any one frame.

| Track (racing) | Tracker load on: fps min / avg / max | tier | draw calls avg (max in a frame) | Camera off: fps min / avg / max | tier |
| --- | --- | --- | --- | --- | --- |
| Meadow Ring | 12 / 39.5 / 58 | 0 → 4 in 16 s | 92 (131) | 22 / 52.8 / 62 | 0 → 4 in 16 s |
| Canyon Dash | 11 / 25.4 / 55 | 4 | 72 (133) | 14 / 53.0 / 61 | 4 |
| Harbor Lights | 7 / 24.7 / 39 | 4 | 89 (130) | 40 / 57.0 / 62 | 4 |
| Frost Pass | 17 / 26.1 / 44 | 4 | 82 (129) | 39 / 57.4 / 62 | 4 |
| Boards and podium | 16-49 | 4 | 60-86 (94-117) | 23-61 | 4 |

The tracker-on run started on a cool tablet and was throttled from the second race on. A
fixed-tier comparison on Meadow with the camera off (45 s each, the governor off) gave tier 0
51.7 and 48.3, tier 1 50.5, tier 2 54.2, tier 3 54.5, tier 4 49.3 and 54.6. That's a few fps
at most, inside the spread.

**After the CPU pass (2026-10-15 evening, the same switch and ride).**

- **Is the switch fair?** Dodge Ball with `tracker_load` on, on a tablet warm from Kart Race, held
  58.2 fps over 4.7 minutes (58.9 after the first, min 51) while the A72 cores ran at 1.0 GHz.
  The no-face path does no extra work: BlazeFace runs a full detection on every frame either
  way (VIDEO mode has no tracking step), 22-34 ms a frame at about 29 fps.
- **What the tracker costs** (per-thread CPU while racing, % of one core): MediaPipe's four
  inference threads about 75 together, the camera's GL thread 18, MediaPipe's GL runner 9,
  CameraX and the analysis executor 11, about 1.2 cores in all. Godot's main thread was at 98%.
- **Desktop, `measure_kart_cpu.gd`** (us per 60 Hz frame, steady clock): 481 before, 241
  after. Physics 117 → 44, bots 106 → 45, effects 67 → 22, kart views 57 → 31 (+8 for the draw
  copies), item views 34 → 23, items 25 → 19, drafts 20 → 10, HUD 17 → 11, places 10 → 2.
- **On the tablet the tick costs 20-30 times the desktop's**: 4-7 ms a tick at full clocks
  with the tracker on, 7-9 ms once throttled. At 30 Hz that is 3-5 ms a frame. The views take
  2-3 ms, the HUD 0.3, and the render's CPU side (every viewport) 7-9 ms, 13 when throttled: it
  is now as big as the game's GDScript.

| Track (racing) | Tracker load on: fps min / avg / max | tier | Camera off: fps min / avg / max | tier |
| --- | --- | --- | --- | --- |
| Meadow Ring | 26 / 44.3 / 51 | 0 → 4 in 20 s | 26 / 56.8 / 61 | 0 → 4 in 20 s |
| Canyon Dash | 39 / 45.0 / 52 | 4 | 56 / 59.3 / 61 | 4 |
| Harbor Lights | 41 / 45.2 / 51 | 4 | 54 / 59.1 / 61 | 4 |

fps here is per 5 s perf line. The 10-minute ride fitted three races. With the tracker on, the
A72s ran at 1.2 GHz most of the time (the A53s at 1.57); `game_ms` was 6.2-6.4 and render CPU
8.3-9.0 ms. Camera off, at full clocks: `game_ms` 3.3-3.6, render CPU 5.2-6.0. After an hour of
back-to-back runs the A72s sat at 507 MHz and the tracker-on rate fell to 28-31 fps whatever the
tier. The target (50 with the tracker on) isn't met: the remaining cost is the tracker's 1.2
cores on a 4-core, throttling SoC, the render's CPU side, and the GDScript left in the tick.

**After the UX polish pass (2026-10-15, Meadow Ring, 60 s of racing each, 1 s frame lines).**
Tracker load on: 13 / 44.9 / 59 fps, tier 0 → 1, render CPU 5.1-7.8 ms counting only the
viewports that rendered (2.0-2.3 renders a frame: the screen and the 3D view; the HUD's bakes
almost never), 6 viewports. The A72s throttled to 1.1 GHz near the end. Camera off straight
after, still throttled: 22 / 49.5 / 61, render CPU 4.2-7.1 ms. Camera off on the final build
after a cool-down (CPU0 at 1.57 GHz): 31 / 51.3 / 61. The earlier 8.3-9.0 ms summed 17
viewports, idle bakes' stale times included; on the desktop the bakes' real per-frame render
cost was already about zero before this pass (`capture_kart_hud.gd`), so the render's CPU side is
the 3D view and the screen's canvas.

**Polish pass 2: anti-aliasing and the art (2026-10-15/16, mock build, `DEV_TUNING` on, Meadow
Ring, `[governor] enabled=false tier=1`, 60 s of racing per run, 5 s perf lines).** The A72s'
clock is in brackets where it was throttled.

| Run | Tracker load on: fps avg (min) | Camera off: fps avg (min) |
| --- | --- | --- |
| Scale 0.62, no AA (the new art) | 46.4 (35); hot: 28.6, 39.5, 31.9 [1.0-1.4 GHz] | 51.7 (46), 52.6 (31), 52.5 (41) |
| Scale 0.66 | 45.8 (40) | 50.8 (44) |
| Scale 0.72 | 39.4; 27.5 [1.0 GHz] | 47.8 (39), 48.3 (38) |
| MSAA 2x | 26.8, 29.2: the 3D view renders black | 50.9, 46.8: black too |

FXAA (`screen_space_aa`) isn't available in Compatibility (the engine warns and ignores it).
0.72 costs about 4 fps either way, beyond the 2 fps budget; 0.66 costs under 2 and ships
(`RENDER_SCALE`). The art pass itself is GPU and build-time work: with the tracker on and cool
clocks Meadow held 46.4 fps against 44.9 before it, camera off 51.7-52.6 against 51.3.

For measuring, set `DEV_TUNING` in `KartRace.gd` (off in every build). The game then logs
`OPENRIDE_GAMES kart_race perf game_ms=… ticks=… tick_ms=… sync_ms=… hud_ms=… process_ms=…
frame_ms=… frame_max_ms=… game_max_ms=… render_cpu_ms=… render_gpu_ms=… viewports=… vp_renders=… fps=…
draw_calls=… draw_calls_max=…
primitives=… track=… flow=… tracker=… tier=…` every 5 s. `user://kart_tuning.cfg` (strings
quoted) overrides the render settings (`[render] scale=0.62 msaa=0 outlines=true`), switches
parts off (`[world] road=false walls=false ground=false scenery=false foliage=false
props=false woods=false stand=false clouds=false hud=false fx=false`), forces a track or a lap
count (`[world] track="meadow_ring" laps=1`), and fixes a tier with the governor off
(`[governor] enabled=false tier=2`). `ticks` is logic ticks per frame and `tick_ms` their
average; `process_ms` is the whole process step and `frame_ms` the frame (two probe nodes at the
extremes of `process_priority`); `render_cpu_ms` sums the measured render time of every
viewport that rendered that frame, and `vp_renders` counts those renders a frame (2.0 is the
screen and the 3D view alone). A viewport that didn't render (an idle bake) keeps reporting its
last render's time, so before the UX polish pass the sum counted every idle bake's stale time
every frame. `capture_kart_hud.gd` prints the same split per viewport on the desktop
(`CAPTURE render …`), with the stale repeats it left out.

**Tests and captures.**

- GdUnit: `tests/unit/kart_*_test.gd`, covering the track model, physics, handling, camera,
  race logic, GP, scene, bots, items, scoring, racers, presentation, tracks and world.
- `sim_kart_check.gd`: a 5-minute local GP at 4× driven with the keys. It must end on the
  final race's line before the hard stop, with the summary shown.
- Windowed captures:
  - `capture_kart.gd`: `--compose` takes the hero shots; `--play=SECONDS` races for a
    recording, used with `--write-movie FILE.avi --fixed-fps 30`.
  - `capture_world.gd`: every track, the grid, the chase cam and drone views.
  - `capture_kart_hud.gd`: the HUD and the flow screens (the race, the drift meter, the
    results and the 3D podium), with draw-call counts and each viewport's render CPU.
  - `capture_kart_items.gd` and `capture_racers.gd`.
- Measurements: `measure_kart_hud.gd` and `measure_kart_board.gd` count the HUD's and the
  boards' draw calls (the board's also frame by frame as it opens). `measure_kart_cpu.gd`
  times each part of a frame's GDScript, headless, with the logic at the game's tick and back-to-
  back frames (an idle desktop clocks the thread down and swamps the numbers).
- `kart_quality_governor_test` covers the governor (windows, spacing, floor, no step back up,
  racing frames only) and each tier applied to the world, the effects and the view.

**Provisional, to tune on the bike:**

- the star thresholds;
- the bots' FTP shares;
- `drift_resistance` (35 / 40 / 45);
- the drift entry (0.65 lean for 0.12 s) and release (below 0.3 for 0.15 s), against real
  tracker jitter;
- the assist's edge guard;
- the rocket start's 70 rpm;
- the climb crawl floor (2.5 m/s);
- `SPEED_SCALE` (2.4), which sets how fast the karts feel.

## Circuits and the Games hub (#37, #38)

**Circuits.** A circuit is a preset of slots (`CircuitPresets`): a 3 min Cadence Karaoke
warm-up, N blocks of Tug of War 1:00, Safe Cracker 1:30, Dodge Ball 1:30 and Cadence Karaoke
1:30, and a 3 min cool-down, each after a 10 s intro card (20 min = 2 blocks, 18:40; 30 min = 4,
31:00; 45 min = 6, 43:20). It is one `SessionPlan`, recorded as one ride.

- **Progress strip.** From `session_started`, `Hud.circuit_strip` (`CircuitStrip`) shows a pill
  per segment above the game's widgets: as wide as the segment is long, in the role's colour (work
  warm, recovery cool); done pills are dimmed, the current one is outlined and fills as it plays.
  Its line says "3 of 10 · 14:02 left" (the rest of the segment plus every later segment and its
  10 s card). A Just Ride hides it. `circuit_strip_test` pins the pills, the time and the layout.
- **No camera.** `SessionRequest.Circuit.cameraGames = false` (the rider turned camera games off,
  or refused the permission) swaps each camera game's slot for the next game of its role that
  doesn't use the camera (Dodge Ball becomes Tug of War), keeping the slot's role, length and the
  circuit's id.
- **Already there from #34/#35:** the intro card with its Skip button, music across cards, the
  per-segment summary and bests per circuit length (`GameResultDao.planBest`).
- **The summary.** A circuit lists every planned game: the ones the session never reached say "not played", and the heading reads "Session ended early" instead of "Circuit complete". The best line says "New personal best!" (with the best before it) or "Your best: 5400 points, 2 stars"; Kotlin sends `previous_score` and `previous_stars` alongside the beaten flags. A Just Ride shows its one game.
- **Not built yet:** time in each role's target zone and average effort on the circuit summary.

**The Games tab (beta) is a launcher.** The tab stays in the bottom bar, but it only opens the
hub: `GamesLauncherScreen` shows the title, the BETA badge, one line and a big **Enter Games**
button, and "Saving your last games ride…" while `GameVisitManager.saving` is true. The Home
card's button reads "Enter Games" too; both call `launchGames(context)`. Everything the old tab
held (circuits, a Just Ride card per game, difficulty, bests, the FTP nudge, the settings and
the camera permission) lives in the hub. `GamesViewModel`, `GamesScreen` and their test are gone;
what they computed moved to `HubStateBuilder` (the minute steps), `GameVisitManager.updateSetting`
and the hub.

**Custom circuits.** Built in the hub (see "The Games hub on screen"), sent as `start_plan`
`{kind: "custom"}`, planned by `SessionPlans.custom` and recorded like a preset (its own plan id,
so bests follow the lineup). They are saved on the Godot side only.

- **Not built yet:** the household leaderboard per game (the DAO has `leaderboard`).

## Originality and licensing

Everything under `games/` is written for this project or permissively licensed. Assets are
listed in `games/assets/SOURCES.md` and third-party code in `THIRD_PARTY_NOTICES.md`; the rule
itself is in the epic (#31). No game may use another game's names, characters, art, UI look,
audio or trademarks.
