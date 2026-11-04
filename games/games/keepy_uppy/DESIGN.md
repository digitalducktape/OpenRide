# Keepy Uppy: design record (#77)

Keep a balloon in the air over a fan your pedalling drives. The weather tries to push it down.
This is the game's source of truth for its rules and tuning. The issue (#77) is the spec; every
change from it is listed under **Changes from the issue**. The look is in `ART_BIBLE.md`; the
polish records are `GFX_POLISH.md`, `UI_POLISH.md` and `AUDIO_POLISH.md`.

**2D rework (rider, 2026-11-02):** the game is 2D, like Safe Cracker: the balloon near the centre
of the screen above an illustrated pedal fan, in four lit outdoor places. The rules, their tests
and the Steer option didn't change. Only the picture, the UI colours and the music did.

- Game id `keepy_uppy`, role **work**, effort multiplier on (also in Just Rides).
- Tracker `off`, or `lean_x` with the **Steer** option on (`tracker_mode_for_segment`, Tug of
  War's brace-lean precedent). The camera never runs for a rider who doesn't steer.
- Supports minutes, rounds and open. `variant` is always `""`.

## Player experience (MDA)

- **Aesthetics:** sensation (a bright balloon riding a column of air you make), gentle
  challenge, and a little comedy (birds perching, the pop). A **calm** effort game: the rider
  should feel in control at an easy pace and choose when to push.
- **Dynamics:** find the power that holds the balloon in a band, read the sky for what's coming,
  and answer it early: spin up before the downdraft, lift to the high band to shake the birds.
- **Mechanics:** below.

Micro-loop (seconds): hold a height. Meso-loop (a minute): read and answer each pushing force,
decide when to ride high for 3× points. Session: points a minute, stars, pops.

## Rules

### Lift and height

- `power` is the bike's watts **smoothed over about 2 s** (an exponential average, time
  constant `SMOOTH_TAU` 1.0 s, so a step is 86% in after 2 s). The bike reports about once a
  second, so the balloon never jumps with a reading.
- The balloon's **weight** `W` is 40% of FTP (easy 30%, hard 50%), sent by Kotlin as
  `weight_watts`. A rain cloud and birds add to it (below).
- `h` is the balloon's height, 0 (the ground) to 1 (the top of the air column).
- **The column weakens with height** (my call, see Changes): the fan's lift at height `h` is
  `lift = power × steer_efficiency × (1 − FALLOFF × h)`, `FALLOFF = 0.45`.
- The balloon climbs or sinks at `rate = clamp((lift − W) / W, −SINK_MAX, CLIMB_MAX)` per
  second, `SINK_MAX = 0.15`, `CLIMB_MAX = 0.25`. Balloons are floaty: from the middle of the mid
  band with the pedals stopped it takes about 3.3 s (plus the smoothing) to reach the ground.
- So every steady power has a **resting height**: `h* = (1 − W / power) / FALLOFF`. On
  standard (W = 40% FTP):

| Power (% FTP) | Resting height | Band |
| --- | --- | --- |
| 40 or less | 0 (ground: pop) | |
| 45 | 0.25 | low |
| 47 | 0.35 | mid starts |
| 51 | 0.50 | mid, the middle |
| 57 | 0.65 | high starts |
| 60 | 0.74 | high |
| 65 | 0.86 | high |
| 70 | 0.95 | high, near the top |

  Holding the mid band is about **half of FTP**, with ±5% of FTP of slack either way: forgiving.
  The high band starts at 57% and its comfortable middle is 60-65%: work, not a sprint.

### Bands and scoring

- **Low** `h < 0.35` scores 1×, **mid** `0.35-0.65` 2×, **high** `≥ 0.65` 3× of
  `BASE_POINTS = 10` a second, awarded every frame through `award()` (the effort multiplier
  applies). Nothing scores while a new balloon is on its way.
- Stars are points a minute (`stars_per_minute`), the same for every difficulty because the
  weight already scales with it: **500 / 1100 / 2000**.
  - Modelled over 5 minutes with the weather on (`keepy_logic_test`, three seeds):

| Rider | Points a minute at 1.0× | Stars at 1.0× | At 1.3× |
| --- | --- | --- | --- |
| 45% of FTP, ignoring the weather (low band, pops 12-15 times) | 430-470 | 0 | 1 |
| 51% of FTP, ignoring the weather (pops 3-4 times, mostly to rain) | 820-880 | 1 | 2 |
| 51% of FTP, answering rain and birds (steady mid) | 1190-1200 | 2 | 2 |
| 65% of FTP, answering the weather (high almost all the time) | 1795 | 2 | **3** (2330) |
| As high as the column goes, all the time (a perfect run) | 1798 | 2 | 3 |

  So a perfect run at 1.0× stays **short of 3 stars** (epic #31), and 3 stars takes riding
  high with about 1.3× effort.

### The ceiling's gusts

- In the high band the air is gusty (my call: "the ceiling has gusts"). While the balloon is
  high, a **gust** comes every 6-10 s, telegraphed **2 s** ahead (the streamers on the height
  pole whip and a whoosh builds), then knocks the balloon down at 0.2 a second for 0.6 s
  (0.12 of height: from 0.75 into the top of mid, never to the ground). Leaving the high band
  calls the pending gust off. A gust only costs a little time at 3×.

### Pushing forces (one at a time, each telegraphed at least 2 s ahead)

The weather sends one force at a time: the first 8-14 s in, then every 10-16 s after the last
one ends (seeded from the segment). The pick is weighted rain 35%, bird 40%, downdraft 25%;
with three birds already perched, no more birds.

- **Rain cloud.** Telegraph **3 s**: the cloud sails in from the right and its shadow
  creeps across the ground toward the fan ("Rain cloud coming"). Then 8-12 s overhead, with
  rain: the balloon is **heavier by 10% of FTP** (`rain_watts`). Answer: about 10% of FTP more,
  or ride it out a band lower.
- **Birds.** Telegraph **2.5 s**: a bird flies in from the side ("Bird incoming"). It lands
  on the balloon: **+5% of FTP** each (`bird_watts`), up to three. **Shake them off**: hold the
  high band for 3 s in a row and every bird flies off (`birds_shaken` counts them). A pop also
  scares them off, and they get bored and leave by themselves 20 s after the last one landed
  (`BIRD_STAY`; neither is counted), so a rider who never rides high isn't buried under them.
- **Downdraft.** Telegraph **2.5 s**: a curtain of dark slanting air sweeps in from the right and
  a low whoosh builds ("Downdraft! Push!"). Then for 1.5 s the air pushes down: the balloon sinks at
  up to `DOWNDRAFT_SINK = 0.25` a second (the floaty limit is lifted) and the lift is pushed down
  by 20% of FTP (`downdraft_watts`). Unanswered, it drops a balloon from the middle of the mid
  band (0.5) to about 0.13, low but alive; from the low band it pops. Spinning up during the
  warning carries it through. `downdrafts_beaten` counts the ones the balloon came out of
  without losing a band.

### The ground (rider)

- When `h` reaches 0 the balloon **pops**: **−50 points** through `penalize()` (no
  multiplier; the score never drops below zero), `pops` +1, the birds scatter.
- A **new balloon is dispatched after 3 s**: it drifts in from the side and settles into the
  column at `h = 0.4` (just into mid), and the game goes on. The weather's next force waits
  until it has arrived, plus 4 s.
- There are no lives: a pop costs points and time, never the game.

### Steer (rider option, off by default)

The rider's words: "if you lean, you could miss keeping the balloon up... the balloon stays in
the center of the screen but might move."

- With Steer on, **wind** drifts the balloon left and right. The fan slides on a short rail in
  front of the bike, and the rider leans to put it back under the balloon.
- **The wind carries the balloon** toward `wind` metres off the middle (at most `WIND_MAX` =
  0.8 m), easing there with a 2 s time constant, while the column pulls it a little toward the
  fan's centre: `dx/dt = (wind − x) / 2 + 0.15 × (fan_x − x)`. With the fan left in the middle,
  a full wind holds the balloon about 0.6 m off it (about a fifth of the lift lost, a band's
  drop); with the fan slid under it, nothing is lost. (A first version had the column hold the
  balloon at a fixed offset from wherever the fan was, so leaning could never win the lift
  back; the test caught it.)
- **Lift loss in proportion to the offset**, past a free zone: `steer_efficiency = 1 −
  MAX_LOSS × clamp((|x − fan_x| − FREE) / (EDGE − FREE), 0, 1)`, `FREE = 0.25 m`,
  `EDGE = 1.2 m`, `MAX_LOSS = 0.5`. A fan fully out from under the balloon halves its lift,
  which sinks it from anywhere. Leaning the wrong way makes the offset bigger: that is how a
  lean "could miss keeping the balloon up".
- **The wind** changes every 6-10 s and eases to its new strength over up to 3 s; the streamers
  on the height pole and the HUD's wind arrow show the new wind as soon as it's chosen, and the
  balloon's 2 s drift lag adds to that, so the rider sees it coming. Holding a full wind takes
  a moderate lean (about 0.6 of the tracker's range, less with the free zone).
- **The balloon stays near the centre of the screen**: 140 px a metre, drawn at most 1.6 m
  (224 px) either side, so its drift reads against the fan on its rails and it never reaches a
  HUD panel.
- **Without a face** (`tracker_state` not tracking: face lost, camera off, calibrating) the
  wind dies away over 2 s and the fan glides back to the centre, so a lost camera never drops
  the balloon.

**Forgiving lean (issue #71: "too sensitive and hard to return to centre").** The tracker
already applies a 0.15 dead zone with a ramp. On top, the game:

1. **Dead zone** `LEAN_DEAD = 0.12` of the tracker's lean, then a **soft curve** (`t^1.6`
   of the rest), so small sways move the fan by centimetres, not tens of them.
2. **Position, not speed**: the lean sets where the fan wants to be (`FAN_RANGE = ±1.6 m` at
   full lean), so sitting up straight always brings it back to the centre: no hunting for
   neutral.
3. **Smoothed and rate-limited**: the fan eases to that place with a 0.35 s time constant and
   at most 1.6 m/s, so tracker jitter never shakes it.
4. **A free zone** of 0.25 m either side where the balloon loses no lift at all, wider than the
   fan's jitter.

These are tested in `keepy_logic_test` (the dead zone, returning to centre, the rate limit, the
loss curve). Tune them on the bike.

### Lengths and modes

- **Minutes** (and circuits): the timer ends it. **Open**: until the rider ends it. **Rounds**:
  a round is 60 s of air time (`ROUND_SEC`), so `rounds` N plays N minutes and the game ends
  itself (`end_mode: game`). The HUD names the round in a rounds ride.
- `min_sec` 60, `max_sec` 3600, rounds 1-10.

## Stats

`pops`, `seconds_high`, `birds_shaken`, `avg_power` (the issue's), plus `downdrafts`,
`downdrafts_beaten` and `best_air` (the longest time one balloon stayed up, in seconds).

## Tuning knobs

| Knob | Value | Kind | Why |
| --- | --- | --- | --- |
| `weight_watts` (Kotlin) | 30/40/50% FTP | gate | The issue's numbers; the mid band then sits at about half of FTP |
| `FALLOFF` | 0.45 | curve | Puts mid at 47-57% and high at 57%+ on standard |
| `SINK_MAX`, `CLIMB_MAX` | 0.15, 0.25 /s | feel | Floaty; with the 2 s smoothing a slip is always recoverable in time |
| `SMOOTH_TAU` | 1.0 s | feel | "Smoothed power (2 s)" |
| Bands | 0.35, 0.65 | gate | Three equal-ish bands; the low band is the warning zone |
| `BASE_POINTS` | 10 /s | curve | Mid a minute = 1200 |
| Stars | 500/1100/2000 | gate | Epic #31 rule, see Scoring |
| Rain | +10% FTP, 8-12 s, 3 s warning | feel | The issue's |
| Bird | +5% FTP, 2.5 s warning, shake 3 s high | feel | The issue's |
| Downdraft | +20% FTP, 1.5 s, sink 0.25/s, 2.5 s warning | feel | Survivable from mid without answering |
| Force gap | first 8-14 s, then 10-16 s | gate | About four forces a minute is too busy; one every ~15 s keeps it calm |
| Gust | 6-10 s while high, 2 s warning, −0.12 | feel | High pays 3×, so it gets a small tax |
| Pop | −50, 3 s, respawn at 0.4 | gate | The rider's rule |
| Steer | dead 0.12, curve 1.6, ±1.6 m, 0.35 s, 1.6 m/s, free 0.25 m, wind 0.8 m | feel | #71 |
| Birds' stay | 20 s | feel | A rider who never rides high isn't buried under birds |

Every value lives in `KeepyLogic`'s constants or the segment's params; Kotlin sends the watts.

## Edge cases

- **Power at 0** (freewheeling): the framework auto-pauses the session; if not, the balloon
  floats down and pops, as any rider would expect.
- **FTP missing**: Kotlin falls back to 150 W (`ftp_is_default`).
- **Sensors lost**: `Effort.award` returns 0 while `sensors_ok` is 0; the balloon also holds
  still (the logic is told to freeze), so a dropout never pops it.
- **Over-pedalling**: the balloon rests near the top; nothing breaks, gusts nudge it down.
- **Birds and a pop**: the birds scatter, unscored.
- **A force while respawning**: none is scheduled until 4 s after the balloon arrives.
- **Degenerate play**: sitting at the top all the time is the intended reward (3×), not an
  exploit; it costs 60-70% of FTP, and gusts keep it from being free.

## Changes from the issue, and my calls

- **The column weakens with height** (`FALLOFF`). The issue says "above the weight the balloon
  climbs; below it, it sinks". Taken literally, any surplus climbs to the ceiling, so holding
  the mid band means holding exactly 40% of FTP, a balancing act on a reading that updates once
  a second. With the falloff the balloon still climbs above its weight and sinks below it near
  the ground, but each power has a resting height, so the bands map to power ranges: mid about
  47-57% of FTP. This is what makes "holding mid at about half of FTP feels comfortable".
- **Gusts** are my reading of "the ceiling has gusts": small, telegraphed knocks in the high
  band only.
- **Downdraft** numbers are mine: +20% of FTP for 1.5 s, survivable from mid.
- **Respawn height** 0.4 (just into mid) and **a 4 s calm** after a new balloon arrives. The
  3 s is pop to back in the air: the pieces fall for 1.2 s, then the new balloon is dispatched
  and drifts in for 1.8 s. Each new balloon (and the first) holds its height for a moment
  (1.5 s; the first 3 s) while the rider gets going.
- **Birds leave by themselves** after 20 s: without it a half-FTP rider who never rides high
  collected three birds and popped about once a minute.
- **A rider ignoring the rain pops**: at exactly 51% of FTP the rain's +10% sinks the balloon
  in about 3 s. That's the issue's number and the point of the 3 s warning; the comfortable
  answer is about 10% of FTP more for 8-12 s. Revisit on the bike if it feels harsh.
- **Rounds** are 60 s of air time.
- **Shake off**: "a 3 s push above the high band" read as 3 s in a row in the high band.
- **Steer details** (the centring column, the free zone, the dead zone and curve) are mine,
  for #71.
- **Extra stats**: `downdrafts`, `downdrafts_beaten`, `best_air`.

## Desktop and hub notes

- Play it on the desktop by running `KeepyUppy.tscn` (F6), which gives a local Just Ride with the
  keyboard simulator (`+`/`-` cadence, `[`/`]` resistance, arrows to lean with Steer on), or
  `tests/capture_keepy.gd` (`--play=SECONDS` rides with a scripted rider).
- It's in the desktop hub and the bike's: #75's paged home row shows it (`LocalHub.order()`
  adds any registered game after the first five). With six games the home row now pages: four
  cards, then two.

### Places

The **Place** option (under More options; random by default) picks one of four places, or keeps
one. On random, the place changes every 3 minutes of play with a 1.6 s cross-fade, waiting for
calm weather and a balloon in the air. My call, so a long ride stays fresh as Safe Cracker's does.

## Gate reviews (ccgs, for the 2D rework)

- **AD-VISUAL: APPROVE.** One coral hero near the centre, an illustrated fan, four distinct lit
  places, no fairground props (distinct from Balloon Pump), every force visible before it acts,
  and the silhouette check recorded in ART_BIBLE §3: the balloon's old curly string is gone. It
  changed the build: GFX_POLISH items 1-6, and a smaller, lower rain cloud clear of the status
  widget.
- **LP-CODE-REVIEW: APPROVE, with one concern.** Rules untouched in a `RefCounted`; the scene only
  wires; shapes drawn once, labels set on change. Concern: the game reuses Safe Cracker's
  `SafeMesh` and `SafeDial.Layer`, so it depends on another game's classes (as Tug does on Kart's
  mesh kit). Promoting them to the framework is a job for a later pass.
- **QL-TEST-COVERAGE: ADEQUATE.** `keepy_logic_test` covers every rule in #77; `keepy_scene_test`
  adds the frame check (the balloon, fan and pole against the stage, the grille and the HUD at
  its tallest), the callout lane, the intro copy word for word with its numbers from the segment,
  no redraws in play and one bake a place; `KeepyUppyCatalogTest` covers Kotlin. Gaps, for the
  bike: how the thresholds and Steer feel, which no test can say.
- **TD-FEASIBILITY: APPROVE.** Safe Cracker's 2D recipe: no 3D view, one baked opaque sprite,
  batched layers, nothing redrawn in play. Desktop: 56-73 draw calls with the HUD, 15-24k
  primitives. Tablet (Gen 2, mock build, 2026-11-04): 60-62 fps for a minute with Steer off, and
  60-61 fps for 75 s of play with Steer on and the camera's load running (`tracker_load`, no
  face, so no wind). Not measured: a place's cross-fade (it comes after 3 minutes), rain and the
  downdraft specifically, or a rider's face tracked for a long, hot ride.

## GodotPrompter patterns (picked, rejected, why)

| System | Skill | Picked | Rejected | Why |
| --- | --- | --- | --- | --- |
| Rules | `gdscript-patterns`, `state-machine` | A `RefCounted` logic class with an enum FSM for the balloon (flying, popped, arriving) and the weather (idle, telegraph, active) | Node-based states | Two small machines with a handful of states; enum `match` is headless-testable and allocation-free, as `TugLogic` |
| Tests | `godot-testing` | GdUnit4 suites driving the logic with scripted power at 60 Hz | Scene-level sims for the rules | The rules are deterministic and fast to test without a tree; one scene test covers the wiring |
| Scene | `scene-organization` | One `Game` root over small Node2D parts (backdrop, rig, balloon, weather), each owning its layers | One big `_draw` | Safe Cracker's structure: static layers never redraw, only positions move |
| 2D drawing | `2d-essentials`, `shader-basics` | Shapes batched by `SafeMesh`, the place baked once into a SubViewport texture, life in small canvas shaders | `Parallax2D` layers and `PointLight2D` | 2D is all blended on a fill-bound tablet: one opaque sprite costs one screen; live layers and 2D lights cost several |
| Effects | `particles-vfx` | `CPUParticles2D` for the pop, butterflies and leaves; rain and the downdraft in a streak shader on one rect each | `GPUParticles2D` | Tiny counts (10-26), and Safe Cracker's dust and sparkles already work this way on the tablet |
| HUD | `hud-system` | One themed `PanelContainer` widget in the top-centre slot, labels set only on change, and callouts in the game's own banner lane | The HUD's centre message | It sits on the balloon; Safe Cracker's banner solved the same problem |
| Motion | `tween-animation` | Tweens for one-offs (the pop's ring, the cross-fade, callouts); the balloon's bob and squash set each frame from the logic | AnimationPlayer | Motion follows the logic; nothing is keyframed |
| Audio | `audio-system` | Rendered OGG theme with three stems gated by height, effects registered by name, fan hum as a looping sfx pitched to lift | MusicGen at runtime | The family's #55 pipeline |
