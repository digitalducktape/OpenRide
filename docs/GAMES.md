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
| `games/games/` | One folder per game, and `Registry.gd`, which lists them. `demo/` is the reference game. |
| `games/tests/unit/` | GdUnit4 suites (not exported) |
| `games/tests/sim_*.gd` | Headless desktop playthroughs (not exported) |
| `games/addons/gdUnit4/` | GdUnit4 6.2.1 (MIT), vendored for the tests (not exported) |
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
- **The stub.** Until #35, `StubGameSession` plays an open-ended Just Ride of the `demo`
  game. It sends `ride_id: null` and records nothing. Its tracker commands go through
  `TrackerLink` (`games/bridge/`), which `GameSessionManager` should reuse. It sets `effort`
  only for work segments, so its Just Ride shows no effort badge; #35 applies
  `effort_in_just_ride`.
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
  "Can't see you: face the screen", "Lean a little further" or "Other way!".
- **When the tracker needs calibration** (`tracker_state` 1), it offers "Tap to calibrate".
- **When the face is lost** (`tracker_state` 4), it shows a slim "Can't see you" strip.
- **When a calibration ended in `tracker_state` 0** (no face found after two tries), it shows
  a slim "Camera steering is off" strip.

Tapping any of them calls `request_calibration`, and so does the HUD's Recalibrate button;
both run every step. `Session.calibration` holds the session's latest progress, with all six
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
| `play_music(style: Dictionary, tempo_bpm: float, seed := 0)` | `style` belongs to the game and is passed to the generator as is. The one key `AudioDirector` reads is `stem_gates`: `{stem_name: intensity}`, the intensity at which a stem plays (0 by default). The music renders off the main thread, which the intro card covers, then **crossfades in over 2 s**. The old music plays until then. Asking again for the same request changes nothing. Tempo = the segment's target cadence (one beat per pedal stroke). |
| `set_intensity(value: float)` | 0-1. Stems fade in or out over 1.5 s as `value` crosses their gate. |
| `stop_music(fade_sec := 2.0)` | Fades the music out |
| `play_sfx(name, volume_db := 0.0, pitch := 1.0) -> bool` | An effect on `SFX`, from 8 voices. `false` means silence. |
| `play_cue(name) -> bool` | A cue on `Cues`, which ducks the music |

**Cue names the framework plays** (#36 should provide them):

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

`sim_demo_check` plays a three-segment local circuit at 4× speed:

- the intro card and calibration;
- a warm-up played with the arrow keys, which must score;
- a work segment skipped with a tap on the card;
- pause and resume with P;
- Esc to end, then the summary and Done.

## Running on the bike

1. Install with `adb install -r app/build/outputs/apk/debugReal/app-debugReal.apk`. The `-r`
   keeps the rider's data, so never uninstall.
2. On the tablet, open **Profile → Mini-games (preview)**. The Games hub (#38) replaces this
   entry point.
3. The stub's Just Ride plays the demo, a `lean_x` game, so the camera starts and calibrates
   during the first intro card. The camera needs the CAMERA permission. Until the hub asks
   for it (#38), grant it with
   `adb shell pm grant dev.digitalducktape.openride.real android.permission.CAMERA`.

The tablet logs at level W, so Godot's `print` output is invisible until you raise the level:

```sh
adb shell setprop log.tag.godot VERBOSE
adb shell setprop log.tag.OpenRideGames VERBOSE
adb logcat -s godot OpenRideGames GodotActivity Godot
```

What to look for in the log:

- Every signal and call is logged as `OPENRIDE_GAMES <- signal` or `OPENRIDE_GAMES -> method`.
- `SessionDirector` prints an `OPENRIDE_GAMES frame fps=… phase=… game=… cadence=… score=…
  effort=…` line every 5 s.
- `OpenRideGames` lines come from the Kotlin side of the session.

## Originality and licensing

Everything under `games/` is written for this project or permissively licensed. Assets are
listed in `games/assets/SOURCES.md` and third-party code in `THIRD_PARTY_NOTICES.md`; the rule
itself is in the epic (#31). No game may use another game's names, characters, art, UI look,
audio or trademarks.
