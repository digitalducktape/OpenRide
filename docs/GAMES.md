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
| `games/Main.tscn` | The idle scene: shown before a session's first game loads and behind the summary |
| `games/autoload/InputBus.gd` | Polls the input frame every frame, or runs the keyboard simulator |
| `games/autoload/Session.gd` | Session signals and methods, with JSON already parsed. Its `SessionDirector` child runs the session on screen. On a desktop, `LocalSession.gd` plays a local plan. |
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
| 11 | `sensors_ok` | 0 / 1 (`ConnectionState.Connected`) |

**Kotlin → Godot signals:**

- `session_started(plan_json)`: `{kind: circuit | just_ride, plan_id, difficulty, total_sec,
  segments:[{game_id, role, duration_sec}]}`. Sent once; it drives the circuit progress strip.
  `total_sec` includes every intro card, and is `-1` for an open-ended plan.
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
  - `ride_id` is null when nothing was recorded (no active rider, or another ride in progress).
  - `results` are the `segment_finished` payloads in plan order, with zero results for games
    that didn't report.
  - `totals`: `{score, stars, segments, elapsed_sec}`; `elapsed_sec` is the ride's duration.
  - `bests`: `{"score": true}` and/or `{"stars": true}` when the session's total beat the rider's
    best at the same plan and difficulty (a first scoring session counts); `{}` otherwise.

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
- **The session engine** is `GameSessionManager` (app-scoped, #35). Its tracker commands go
  through `TrackerLink` (`games/bridge/`). See "Sessions and recording" below.
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

`GameHostActivity.intent(context, request)` starts games with a `SessionRequest` (a Just Ride
or a circuit, and a difficulty). Each entry calls `GameSessionManager.begin(request)` and
attaches it to the bridge. A session still running when games are entered again is finished
and its ride saved first.

## Sessions and recording

`GameSessionManager` (`app/.../games/session/`, #35) is the Kotlin side of every session. It
is app-scoped, so a ride is saved even after the host has gone to the back.

**Plans.** When Godot is ready, it turns the request into a `SessionPlan` with the active
rider's FTP (`SessionPlans`):

| Request | Plan (`plan_id`, also `Ride.gamePlan`) | Segment |
| --- | --- | --- |
| Just Ride, timed N min | `just-ride:<game>:minutes:<N>` | `role: free`, N × 60 s, the game's `timedEndMode` (normally `timer`) |
| Just Ride, N rounds | `just-ride:<game>:rounds:<N>` | `role: free`, N × the game's `roundSec`, `end_mode: game`, `params.rounds = N` |
| Just Ride, open-ended | `just-ride:<game>:open` | `role: free`, `duration_sec: -1`, `end_mode: game` |
| Circuit | `circuit-20`, `circuit-30`, `circuit-45` | the preset's slots (`CircuitPresets`), `end_mode: timer` |

- Lengths are clamped to the game's limits; a mode the game doesn't support is refused.
- Circuit presets are data. Until a preset's games exist, their slots play the demo (#37).
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

**Audio.** `segment.audio` is decided at each segment's start from `GameAudioPrefs`, so music
the rider starts or stops mid-session counts from the next segment. With game music on "auto"
(the default), `music` is false while another app's music plays. Effects always play.

- `AudioManager.isMusicActive()` alone can't tell, because Godot's own media player keeps it
  true, and API 29-34 don't say which app a player belongs to (`getClientUid()` is a hidden
  system API).
- So `OtherMusicDetector` tells players apart by identity. The players that exist before the
  engine starts are other apps'. Those that appear in the next 10 s are the engine's.
- Known limit: another app's paused player still counts as its music while it exists. The hub (#38) will store the setting and volumes; until then the defaults apply.

**Recording.** The ride goes through the app's own `RideSessionManager`, so it is an ordinary
ride in History, exports and backups:

- It starts when the session starts and records through intro cards.
- Freewheel auto-pause applies. A rider's pause (`request_pause`) pauses the ride too. Either
  kind freezes the session clock and sends `session_paused` / `session_resumed`.
- A session with under a minute of gameplay (intro cards don't count), or with no pedalling
  at all, is discarded rather than saved, and `session_finished` carries `ride_id: null`.
  Normal rides have no such rule: they're only ever ended deliberately.
- Otherwise, when the session finishes, the ride is saved with `gamePlan`, then one `game_results` row
  per segment (`startSec` on the session clock, `durationSec` of gameplay). Then the ride
  manager returns to idle, so the app's next ride can start.
- `GameResultDao` answers personal bests per rider (per game, plan and difficulty), the
  household leaderboard per game, and a plan's best session. Skipped segments never count.
- The ride summary lists each segment's result, and History shows a game badge.
- Room schema 6 adds these (`MIGRATION_5_6`), with `Profile.headCalibration` for the head
  tracker's saved extremes.

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
   - It calls `set_tracker_mode` with the game's `tracker_mode`. The session's first camera
     mode starts the calibration on the Kotlin side (see "Head tracker"), so Godot doesn't
     request one then: a `request_calibration` would force a second, full run. Godot asks only
     when a `lean_2d` game follows a session calibrated for `lean_x` alone (depth needs its own
     extremes), and when the rider taps to recalibrate.
   - It starts the segment in `Effort` and `AudioDirector` (`segment.effort`, `segment.audio`).
   - It calls `game.prepare(segment)`, then shows the **intro card** for `intro_sec`. The card
     shows "Up next", the role, the game's `how_to` and `target_text()`, the previous result,
     and a countdown ending 3-2-1.
3. **Intro card tap**: this skips the game (`segment_finished` with `skipped: true`). The one
   exception is the last segment of an open-ended plan, which would leave nothing to play.
4. **Gameplay**: the HUD shows, `Effort` starts scoring, and it calls `game.start(segment)`.
   `end_mode: game` games end themselves (`end_segment()`). Open-ended segments count the timer
   up, and the game runs until Kotlin ends the session.
5. **`segment_ending`**: it calls `game.request_finish()`, and the game has 5 s to call
   `end_segment()`. After 4.5 s the director reports for it. A `segment_ending` during the intro
   card reports the game as skipped.
6. **The result**: this is `game.finish()`, with `stars` from the game's thresholds.
   `segment_finished` then goes to Kotlin. When an open-ended plan's last game ends, it offers
   **End session**.
7. **Pause**: `session_paused` shows the pause screen (Resume, End session) and freezes the
   game, whether the rider paused or Kotlin auto-paused. The HUD's Pause button calls
   `request_pause`/`request_resume`. Its End button, and the pause screen's, ask for
   confirmation, then call `request_end`.
8. **`session_finished`**: it goes back to the idle scene, sets the tracker off, and shows the
   **summary**: each segment's result and stars, the totals, and any bests. Its **Done** button
   (or Android back) calls `request_exit`. Circuit mode (#37) adds its sections with
   `SummaryScreen.add_section()`.

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
| `star_thresholds` | `{easy: [1★, 2★, 3★], standard: […], hard: […]}`: the minimum score for each star |
| `stars_per_minute` | When true, the thresholds are points per minute of gameplay, so one set fits a 90 s slot and a 30-minute ride |

For work games, set the thresholds so that 3 stars needs about 1.3× effort. A perfect run at
1.0× must stay short of 3 stars (epic #31). `demo_logic_test.gd` checks this for the demo.

**Hooks.** A game overrides the ones it needs. It never overrides `_process`.

| Hook | When |
| --- | --- |
| `_on_prepare(segment)` | The scene is loaded and the intro card shows. `segment`, `params`, `difficulty`, `rng` (seeded from `seed`) and `hud` are set. Build the level, add HUD widgets, ask for music. |
| `_on_start()` | Gameplay begins |
| `_on_frame(delta)` | Every gameplay frame while not paused. Read `InputBus`. |
| `_on_pause()`, `_on_resume()` | The scene's processing is also frozen while paused |
| `_on_finish_requested()` | The timer ran out: wrap up and call `end_segment()` within 5 s. By default the game ends at once. |
| `target_text(segment)` | The intro card's target line, e.g. "Hold 250 W" |

**What a game calls:**

- `award(points)` scores through `Effort`. It returns what counted.
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

`Hud` (`games/framework/hud/`) goes over every game. It shows:

- the game's title and role;
- the effort badge (`EffortBadge`: "Effort ×1.3" and a resistance gauge that marks 30% and 60%);
- the segment timer (`SegmentTimer`);
- the score, with Pause and End;
- Recalibrate, for camera games;
- the sensor banner (`SensorBanner`).

It is sized for a 1920x1080 canvas read from about 1 m away (`HudTheme`). Numbers are 96 px,
text is never below 34 px, and buttons are 110 px tall.

Games add their own widgets under the timer with `hud.add_widget()`, for example a
`TargetBand` (a cadence floor or a power cap) or a `BigNumber`. `StarRow` draws stars as
shapes, so no font needs the glyph. Everything uses Godot's default font.

### Calibration UI

`CalibrationOverlay` shows only in camera games:

- **While calibrating** (`tracker_state` 2, or `calibration_progress` in the last second), it
  prompts each step: centre, with a 3-2-1 from `fraction`, then left, right, and in / back for
  `lean_2d`. It shows a progress bar.
  The header reads "Step 2 of 3" (`step_index`, `step_count`; left out for a centre-only
  run), and "Try 2" from `attempt`. `retry_reason` becomes a hint: "Hold still for a moment",
  "Can't see you. Face the screen: is the room bright enough?" (on the bike, a dark room was
  the usual cause), "Lean a little further" or "Other way!". For `used_default` it shows "Using
  your usual range; recalibrate later if steering feels off" (no 3-2-1 over it).
- **When the tracker needs calibration** (`tracker_state` 1), it offers "Tap to calibrate".
- **When the face is lost** (`tracker_state` 4), it shows a slim "Can't see you" strip.
- **When a calibration ended in `tracker_state` 0** (no face found after two tries), it shows
  a slim "Camera steering is off" strip.

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
- `audio.music: false` fades the music out for that segment. A game's `play_music` is then kept
  but not played.
- `Music` ducks by 10 dB under every cue.

### Registration (for generators)

Call these at startup. `res://audio/Cues.gd` is an optional hook: if that script exists,
`AudioDirector` instantiates it once in its `_ready` and calls its `register(director)`, so
generators can register without an autoload of their own.

| Method | Contract |
| --- | --- |
| `register_sound(name: String, stream: AudioStream)` | A named effect or cue, rendered ahead of time. It replaces any earlier sound of that name. |
| `register_sound_factory(factory: Callable)` | `factory(name: String) -> AudioStream` (or `null`). It is asked on the main thread the first time an unregistered name plays, and the answer is cached. Use it for lazy rendering of presets. |
| `register_music_generator(generator: Callable)` | `generator(request: Dictionary) -> Dictionary`, mapping each stem name to a **looping** `AudioStream`, all the same length. `request` is `{style, tempo_bpm, seed}`. It **runs on a `WorkerThreadPool` thread**, so it must not touch the scene tree. Disk caching (`user://audio_cache/`) is the generator's job; `AudioDirector` keeps the last 4 renders in memory. |

### Playback (for games)

| Method | Behaviour |
| --- | --- |
| `play_music(style: Dictionary, tempo_bpm: float, seed := 0)` | `style` belongs to the game and is passed to the generator as is. The one key `AudioDirector` reads is `stem_gates`: `{stem_name: intensity}`, the intensity at which a stem plays (0 by default). The music renders off the main thread, which the intro card covers, then **crossfades in over 2 s**. The old music plays until then. Asking again for the same request changes nothing. Tempo = the segment's target cadence (one beat per pedal stroke). The same style and seed at a new tempo is a **tempo change**: it swaps in on the next phrase boundary instead (see "Tempo changes on a phrase boundary"). |
| `set_intensity(value: float)` | 0-1. Stems fade in or out over 1.5 s as `value` crosses their gate. |
| `stop_music(fade_sec := 2.0)` | Fades the music out |
| `play_sfx(name, volume_db := 0.0, pitch := 1.0) -> bool` | An effect on `SFX`, from 8 voices. `false` means silence. |
| `play_cue(name) -> bool` | A cue on `Cues`, which ducks the music |

**Cue names the framework plays** (#36 provides them; see "Generated audio"):

| Name | When |
| --- | --- |
| `countdown` | Each of the intro card's 3, 2, 1 |
| `go` | Gameplay starts |
| `segment_end` | A segment's result is in |
| `pause`, `resume` | The session pauses and resumes |
| `summary` | The summary appears |

The demo asks for `dodge` and `hit` effects and for music with the style
`{"name": "demo_drive", "stem_gates": {"harmony": 0.5, "lead": 0.85}}`.

`Session` handles the rest:

- `begin_session()` and `begin_segment(segment)` apply the settings above.
- `set_paused()` pauses the music and effects, but not cues.
- `end_session()` fades the music out after the last segment.
- The music keeps playing across the intro card until the next game asks for its own.

`sound_played(name, bus)` and `music_started(key)` are there for tests and debugging.

## Generated audio (`games/audio/`)

All game music and effects are generated in code (#36). There are no recorded samples and
nothing to license. `res://audio/Cues.gd` is the single entry point: `AudioDirector` calls its
`register(director)` at startup, which:

- builds the wavetables and loads the styles on the main thread;
- registers `SfxSynth` as the sound factory, so effects and cues render on first use;
- registers `MusicGen.generate` as the music generator.

| File | What |
| --- | --- |
| `Cues.gd` | The entry point above. `countdown` maps to the `countdown_beep` preset; every other name is a preset name. |
| `SfxSynth.gd`, `SfxPreset.gd` | The effects generator and its preset resource |
| `sfx/<name>.tres` | The starter presets |
| `MusicGen.gd`, `MusicStyle.gd` | The composer and synth, and the style resource |
| `styles/<name>.tres` | The styles |
| `Dsp.gd` | Shared oscillators, noise, filters and the float → PCM conversion |
| `gallery/StyleGallery.tscn` | The desktop audition scene |
| `tools/make_library.gd` | Regenerates the starter presets and styles from its tables |

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
| `drive` | Dodge Ball | Minor key, four-on-the-floor, pumping eighth-note bass, stabs |
| `heave` | Tug of War | Phrygian, heavy half-time drums, a bass that builds phrase by phrase |
| `noir` | Safe Cracker | Harmonic minor sevenths, brushes and ride, walking bass, swung comping, sparse vibes |
| `bright` | Cadence Karaoke | Major sevenths, backbeat, root-fifth bass, sixteenth-note arpeggio |
| `racer` | Kart Race | Mixolydian, busy breakbeat, off-beat bass, stabs, detuned saw lead |
| `demo_drive` | the demo | Dorian four-on-the-floor with a pad |

Each style's `suggested_gates` is a starting point for the game's `stem_gates`.

#### Tempo: where it comes from and how to tune it

Styles have **no base BPM of their own**. The tempo comes from the game:

1. **The game passes `tempo_bpm`** to `play_music`: the segment's target cadence in rpm,
   so one beat = one pedal stroke. The demo passes `cadence_floor + 20`
   (`games/games/demo/Demo.gd`).
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
   - `stop_music()`, `audio.music: false` and a new session drop it.
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

On a desktop:

- The local Just Ride is of the demo game.
- `request_exit()` (the summary's Done) restarts the local plan.
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
```

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

`sim_demo_check` plays a three-segment local circuit at 4× speed:

- the intro card and calibration;
- a warm-up played with the arrow keys, which must score;
- a work segment skipped with a tap on the card;
- pause and resume with P;
- Esc to end, then the summary and Done.

## Running on the bike

1. Install with `adb install -r app/build/outputs/apk/debugReal/app-debugReal.apk`. The `-r`
   keeps the rider's data, so never uninstall.
2. On the tablet, open **Profile → Mini-games (preview)** and pick a Just Ride of the demo
   (20 minutes or open-ended). Both record a ride for the active rider. The Games hub (#38)
   replaces this entry point.
3. The demo is a `lean_x` game, so the camera starts and calibrates during the first intro
   card. The camera needs the CAMERA permission. Until the hub asks
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
- `SessionDirector` prints an `OPENRIDE_GAMES frame fps=… phase=… tracker=… lean_x=…
  lean_depth=… standing=… score=… effort=…` line every 5 s, and every second while the
  camera runs.
- `Session` logs each calibration step as it starts, retries and completes
  (`OPENRIDE_GAMES <- calibration_progress left 2/3 attempt 1 …`).
- `OpenRideGames` lines come from the Kotlin side of the session.

## Originality and licensing

Everything under `games/` is written for this project or permissively licensed. Assets are
listed in `games/assets/SOURCES.md` and third-party code in `THIRD_PARTY_NOTICES.md`; the rule
itself is in the epic (#31). No game may use another game's names, characters, art, UI look,
audio or trademarks.
