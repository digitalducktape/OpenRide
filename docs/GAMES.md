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
- `calibration_progress(step, fraction)`: drives the calibration UI.
- `session_finished(summary_json)`: `{ride_id, results:[…], totals, bests:{…}}`, sent after Kotlin has
  saved the ride. Godot shows the summary, then calls `request_exit()`.

**Godot → Kotlin methods:**

- `segment_finished(result_json)`: `{game_id, score, stars (0-3), won (bool|null), skipped (bool),
  stats:{effort_avg, …}}`. A skip is reported as `skipped: true` during the intro card; Kotlin then
  advances to the next segment.
- `request_calibration(mode)`: `mode` ∈ `lean_x | lean_2d`.
- `set_tracker_mode(mode)`: `off | lean_x | lean_2d | lean_stand`, sent by `Session` from each game's
  declaration. The camera only runs when not `off`.
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


### Proposed additions (pending spec update)

These come from the HeadTracker work (#33). They are **not part of v1 yet**. The foundation
does not implement them, and nothing may depend on them until the contract above is edited to
include them.

- `calibration_progress(step, fraction)` sends `step` as a string: `centre`, `left`, `right`,
  `in` or `back`.
- It should also carry:
  - `step_index`
  - `step_count`
  - `attempt`
  - `retry_reason`: `unstable`, `no_face`, `too_small` or `wrong_direction`

Until the HeadTracker is wired in, bridge fields 6-9 read `0` and `tracker_state` reads `0` (off).

### Implementation notes

These describe how the foundation (#32) implements v1. They don't change the contract.

- **Wire format.** Each JSON payload is one `String` argument, and `Session` parses and
  stringifies it. Godot's JSON parser returns every number as a float (`1.0`), so Kotlin
  accepts whole numbers written either way (`"stars": 3.0`).
  - `calibration_progress` is `(String, float)`.
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
  game. It sends `ride_id: null` and records nothing. `request_calibration` and
  `set_tracker_mode` are logged, not acted on. It sets `effort` only for work segments, so its
  Just Ride shows no effort badge; #35 applies `effort_in_just_ride`.

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
   - It calls `set_tracker_mode` with the game's `tracker_mode`.
   - It calls `request_calibration` once per session, at the first camera game. Kotlin chooses
     centre-only or the full flow.
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
- **When the tracker needs calibration** (`tracker_state` 1), it offers "Tap to calibrate".
- **When the face is lost** (`tracker_state` 4), it shows a slim "Can't see you" strip.

Tapping any of them calls `request_calibration`, and so does the HUD's Recalibrate button.
`Session.calibration` holds the latest progress. The overlay shows the #33 proposal's
`step_index`, `step_count`, `attempt` and `retry_reason` when they are present, and works
without them. The v1 bridge doesn't carry them yet.

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
  - The tablet figure is pending the on-bike check.
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

### Tempo changes on a phrase boundary (proposed `AudioDirector` hook)

`AudioDirector` crossfades new music in over 2 s as soon as its render finishes, which is right
between games. Within a game, a tempo change should land on a phrase boundary with no gap and
the beat grid unbroken. This matters for Cadence Karaoke's target changes and Kart Race's
cadence-following. `MusicGen` renders the next tempo ahead and the gallery demonstrates the
switch (`StyleGallery.gd`, `_process` and `_seconds_into_phrase`). The switch itself needs the
following change in `AudioDirector` (#34 owns it).

1. **Recognise a tempo change.** A new request with the same style and seed but a different
   `tempo_bpm`, while music is playing. An explicit `play_music(..., at_phrase := true)`
   would also do.
2. **Hold the finished render.** When it arrives in `_collect_render`, keep it as *pending*
   instead of calling `_start`. A newer request replaces the pending one, and `music: false`
   drops it.
3. **Find the playing loop's phrase length** from the stream itself, not from the tempo.
   `tempo_scale` and per-bar rounding make the stream the only exact source.
   - `phrase_sec = stem.get_length() / (bars / 4)`, with `bars` from the style request
     (16 by default).
4. **Track the phrase position each frame.**
   - `since = fposmod(deck.get_playback_position() + AudioServer.get_time_since_last_mix(), phrase_sec)`.
   - When `since` wraps (drops by more than half a phrase), the boundary has just passed.
   - Don't switch while paused.
5. **Switch in that frame.**
   - Start the new deck with `player.play(since)`, so its beat grid starts exactly on the
     boundary despite frame timing.
   - Crossfade over about 30 ms, not 2 s.
   - Give the new stems the current stem levels at once, with no 1.5 s gate fade-in.
   - Optionally, start at the same phrase of the form: `from = next_phrase_index × new_phrase_sec + since`.
6. **In games:** call `play_music` with the new tempo (same style and seed) a few seconds before
   the change is due. The render (under 0.2 s on a Mac) needs to finish before the boundary.

`sim_gallery_check` measures the gallery's switch: it lands 7.7 ms after the boundary, and the
old loop plays its phrase out. The switch is frame-quantised, but `play(since)` compensates, so
the new beat grid is exact. On the bike this needs checking with a live tempo change.

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
- The simulator also stands in for the head tracker. `tracker_state` follows the game's
  tracker mode, and `request_calibration` plays a scripted centre, left and right run (plus in
  and back for `lean_2d`) as `calibration_progress`.
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
- **Headless checks:**

  ```sh
  $GODOT_BIN --headless --path games -s res://tests/sim_gallery_check.gd  # gallery + phrase switch
  $GODOT_BIN --headless --path games -s res://tests/audio_bench.gd -- --tempo=90 [--wav=DIR]
  ```

  `audio_bench` times every style's 16-bar render, serial and parallel. With `--wav`, it
  writes a mix of each style and every effect as `.wav` files to listen to.

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
