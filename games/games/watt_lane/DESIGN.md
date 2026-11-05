# Watt Lane: design record

Watt Lane (#78, epic #74) is a work game, and a low-profile warm-up: **a chevron cursor following
an illuminated horizontal lane.** Your smoothed power is the chevron's height (more watts, higher);
the lane comes in from the right and steps up or down as the target wattage changes. Hold the
wattage, then the next one. Every step is announced about 5 s ahead with chevrons and its new
watts on the lane, a countdown chip and a chime (rider's decision).

**Three looks, two rider decisions (2026-11-02).** The slice was a 3D night highway with power as
your place across the road; the rider found that a lane moving sideways reads as "lean to change
lanes", and asked for 2D and horizontal ("kind of like riding along a music staff"). A power-line
staff with a note-head marker followed; its marker failed the silhouette check (it read as
something inappropriate), and the rider's direction became: "just make it abstract, a chevron
cursor following an illuminated horizontal lane." The rules, the tests, the one power number and
the announcements carried over unchanged through all three.

This file is the game's source of truth for rules and tuning. The issue's "(my call)" items were
proposals; where a pass changed one, the change and the reason are under **Changes from the
issue**. The look is in `ART_BIBLE.md`, the polish in `GFX_POLISH.md`, `UI_POLISH.md` and
`AUDIO_POLISH.md`.

## Player fantasy (game-designer pass)

- **Aesthetic (MDA):** sensation and challenge. You are an arrow of light holding a lit lane;
  holding it feels like being locked into a groove, and catching a step feels like hitting a
  note dead on.
- **Competence (SDT):** every number on screen is the same number the rules use (see **One
  number**), so the rider always knows why they're in or out.
- **Autonomy:** watts are watts. Any mix of cadence and resistance works, so the rider chooses how
  to make the power (unlike Cadence Karaoke, which dictates the cadence).
- **Flow:** long drifts are the "groove"; a jump every ~20 s is the tension spike; the streak
  multiplier is the reason to stay tidy.

## Measured against Cadence Karaoke

Cadence Karaoke is the nearest game (neon, a target to follow). Watt Lane must feel different:

| | Cadence Karaoke | Watt Lane |
| --- | --- | --- |
| Follows | cadence (rpm) | power (W): any cadence and knob mix |
| Space | 3D neon grid tunnel, perspective | flat 2D field, depth from layered motion |
| Axis | the orb moves along the floor (depth) | the chevron moves **up and down** (more watts, higher) |
| Target | a box on the floor, beat rings flying in | a lit horizontal lane coming in from the right, stepping up or down |
| Marker | a glowing orb | an angular chevron (▶) |
| Palette | magenta / cyan / violet neon | warm gold lane in a cool teal-black field, copper UI |
| Music | synth-funk at the cadence | dream-pop electronica at a fixed 112 bpm, glockenspiel hook |
| Changes | rider's − and + | the course's drifts and announced steps |

## Rules

### One number (HUD agreement)

Balloon Pump's slice showed 48 W in the ride panel and 130 W in its own bar. Watt Lane has exactly
one power number: the **smoothed power**, `W = round(3 s average of the power readings)`.

- The ride panel's W column shows it (`RideMetrics.set_power_source`), not the raw reading.
- The chevron's height is drawn from it.
- Lane membership compares it: in lane when `lo ≤ W ≤ hi`, inclusive, both integers.
- The lane's bounds are whole watts on a 5 W grid, and the HUD hero shows exactly `lo–hi`.
- The ride panel's W turns gold inside the band the rules use right now (`set_power_band`), so its
  colour never disagrees with the game.
- The countdown chip names the next lane's exact bounds (the hero's caption says W).

### Power to position

- Smoothed power is a **3 s sliding window** over the readings (time-weighted, 0.1 s bins). A step
  in power moves the chevron linearly over 3 s. (Rejected: an exponential filter with a
  3 s constant, which takes about 9 s to settle; the window's mean delay is 1.5 s.)
- The field is a watt scale: `y = 620 − (W / FTP − 0.60) × 880 px`, a faint guide every 12.5% of
  FTP. The chevron stays between y 372 and 960 (clear of the HUD; clamped).

### The lane

- **Width:** 20% of FTP, at least 40 W (easy 25% / at least 50 W, hard 15% / at least 30 W),
  rounded up to 10 W so its half-width stays on the 5 W grid.
- **Centre:** moves in a seeded course between `lane_min_watts` and `lane_max_watts`:
  - work: easy 40-60%, standard 45-70%, hard 50-75% of FTP;
  - warm-up: 35-55% of FTP at every difficulty, jumps only up until the top, small jumps.
- **Lead-in:** the first 10 s hold the start (a third of the way up the range).
- **Drifts:** between jumps, 10-16 s of slow drift toward a random point in the range, at most
  1% of FTP a second, in 5 W steps (unannounced: the rails show it).
- **Jumps:** a step of 12-20% of FTP (warm-up 6-10%), and always **more than half a lane**
  (`width / 2 + 5 W`), so a rider who stays put is outside the new lane. On the 5 W grid, at
  least 20 s apart (the first 20-24 s in). The direction goes where there's room, and alternates
  when both sides have it (a warm-up climbs while it can).
- **A range too narrow for that** (low FTPs: at 150 W the standard range is 70-105 W, 35 W, and a
  jump must be 25 W either way from its middle) widens to twice the smallest jump, half down
  (never under 30% of FTP) and the rest up. At 150 W standard: 60-110 W.
- Generated ahead in chunks from the segment's seed, so an open-ended ride never runs out and the
  same seed gives the same course.

### Announcing a jump (rider)

- **5 s ahead** (`ANNOUNCE_SEC`): a chime, the countdown chip ("▲ 175–215 in 5", then 4, 3,
  2, 1, NOW), and amber chevrons in the lane leading into the step, with its new watts beside it. The bike reports about
  once a second, so 5 s is well over the 2 s minimum.
- A soft tick on each of 3, 2, 1; a whoosh at the jump.
- **The switch window:** from 1.5 s before the jump to 3.5 s after, **either lane counts** (the
  union of the two). Moving early or late is fine; the ride panel's gold band widens to match.
- A jump is **caught** if the rider is inside the new lane (on its own) at any moment in the 3.5 s
  after it ("Caught it!"); otherwise it's missed when the window closes.
- Catchable on the real lag: a rider who starts pushing when the chip says 2 has their new reading
  1 s later, and the window average crosses into the new lane within about 1.5 s more, at about
  +1 s. One who reacts only at the jump is in by about +2.5 s, inside the 3.5 s window. **To check
  on the bike:** measure the reading lag (the acceptance item) and widen `POST_SEC` if needed.

### Scoring

- Inside the lane: 10 points a second × the streak multiplier, through `Effort.award` (so the
  effort multiplier applies in work segments and Just Rides).
- **Streak:** ×1, then +0.5 every 5 s in the lane, to ×3 at 20 s.
- **Leaving the lane:** scoring stops at once; the streak survives 1 s outside (the reading is
  noisy), then resets ("lane_exit", a soft buzz).
- **Warm-up:** no effort multiplier there, so its points count 1.25× (a clean 3-minute warm-up can
  earn 3 stars).
- Stars are points per minute, the same for every difficulty: **250, 1200, 2000**.

| Rider (modelled in `watt_lane_logic_test`) | Points a minute | Stars |
| --- | --- | --- |
| Perfect, 60 s slot, 1.0× effort | ~1550 | 2 |
| Perfect, 90 s slot, 1.0× | ~1630 | 2 |
| Perfect, long ride, 1.0× | → 1800 | 2 |
| Perfect, 60 s slot, 1.3× (1.15× is short) | ~2015 | 3 |
| Perfect, long ride, 1.3× | ~2340 | 3 |
| Perfect warm-up (3 min, ×1.25) | ~2150 | 3 |
| In the lane 10 s of every 20 | ~300 | 1 |

The streak's 20 s build costs a short slot a third of its minute, so a perfect run's points a
minute grow with the slot's length. 2000 is the one 3-star line that a perfect 1.0× run never
reaches at any length and a 1.3× run reaches even in a 60 s slot; on a long Just Ride about
1.12× is enough. 1 star stays low (250) on purpose: it means "you rode the lane".

### Stats

`in_lane_pct`, `longest_streak_sec`, `avg_power` (the raw readings' average, as the ride's),
`jumps`, `jumps_caught`.

## Declarations

- Roles: `work`, `warmup`. Supports `minutes`, `open`. 60-3600 s. Tracker `off`.
- `effort_in_just_ride: true` (a Just Ride is scaled as work).
- Kotlin (`GameCatalog.WATT_LANE`) sends `lane_min_watts`, `lane_max_watts` and
  `lane_width_watts`, scaled by FTP, role and difficulty. The game falls back to the same maths
  from `ftp_watts` if they are missing.
- Options: none in this slice.

## Edge cases

- **Stopped / 0 W:** the chevron sits at the foot of the field; a "PEDAL" alert; the streak resets
  after 1 s.
- **Way over:** the chevron sits at the top (under the HUD's clear line); "EASE ▼". There is no power cap: a hard effort is the rider's
  call, and the effort multiplier already rewards resistance.
- **Lane at the range's edge:** jumps go to the side with room; the range never puts `lo` under
  25% of FTP.
- **Sensor loss:** `Effort.award` freezes scoring; the logic keeps running.
- **Pause:** the game's frame isn't called, so the course and the countdown wait.
- **Degenerate play:** sitting in the middle of the range doesn't work: the lane is narrower than
  the range and jumps by at least 12% of FTP. Spiking power doesn't work: a 3 s window.

## Tuning knobs

| Knob | Where | Default | Kind |
| --- | --- | --- | --- |
| `SMOOTH_SEC` | logic | 3.0 s | feel |
| `ANNOUNCE_SEC` | logic | 5.0 s | feel |
| `PRE_SEC`, `POST_SEC` | logic | 1.5 s, 3.5 s | feel (bike-tune) |
| `GRACE_SEC` | logic | 1.0 s | feel |
| lane width % and floor | Kotlin params | 25/20/15%, 50/40/30 W | curve |
| centre range | Kotlin params | see above | curve |
| `JUMP_GAP_SEC`, jump sizes | logic | 20 s, 12-20% | gate |
| `POINTS_PER_SEC`, streak | logic | 10, +0.5 / 5 s to ×3 | curve |
| stars | `WattLaneLogic.STARS` | 250 / 1200 / 2000 a minute | curve |

## Changes from the issue (and why)

1. **Lane floor** 30 W → 40 W standard, 50 W easy (30 W hard). The rider's FTP falls back to
   150 W, where 20% is 30 W: ±15 W around a once-a-second reading is too tight for a person (the
   "forgiving thresholds" lesson).
2. **Centre range** 45-75% → easy 40-60%, standard 45-70%, hard 50-75%. Effort games aim at about
   half of FTP; 45-75% for everyone averaged 60%.
3. **"Smoothed (3 s)"** is a 3 s sliding window, not a 3 s exponential (see above).
4. **The switch window** (either lane counts from -1.5 s to +3.5 s) is new: without it the
   announce would make riders leave the old lane early and lose their streak for doing the right
   thing.
5. **The streak's 1 s grace** is new, for the same noisy reading Cadence Karaoke allows for.
6. **Jumps of over half a lane, and a range that widens to allow them** (new): the logic tests
   found that a 20 W jump with a 40 W lane left a rider who stayed put inside the new lane.
7. **Lane bounds on a 5 W grid** and drifts in 5 W steps: the hero number doesn't flicker, and
   "in" means exactly what the numbers say.
8. **Warm-up points ×1.25**, so a warm-up (no effort multiplier) can still earn 3 stars.
9. **The ride panel shows the smoothed power** in this game, so it agrees with everything else.
10. **2D, horizontal, abstract (rider, 2026-11-02):** power is height, not a place across a
    road (a sideways lane reads as "lean"); a chevron cursor and a lit lane, not a staff and a
    note (the silhouette check). See the history above.
11. **The countdown chip reads "▲ 175–215 in 5"** (a drawn arrow), not the issue's "UP to 160 W in 5": it names
    the lane's bounds (the numbers the rules use) and, with "to" and "W" in, a three-digit lane
    overflowed the HUD's 850 px slot (`watt_lane_scene_test`).

## The rework as built

- **Files:** `WattLane.gd`/`.tscn` (the scene), `WattLaneLogic.gd` and `WattLaneCourse.gd` (rules),
  `WattLaneTrack.gd` + `shaders/wl_lane.gdshader` (the lane, the chevron, the step label, the
  path, catch sparks), `WattLaneBackdrop.gd` + `shaders/wl_field.gdshader` (the field),
  `WattLaneStatus.gd` (HUD), `WattLaneAudio.gd` and `WattLaneMusic.gd` (audio; music from
  `games/tools/music/songs/watt_lane.py`), `hub_card.png`.
- **2D on the full 1080p canvas, no SubViewport**, like Safe Cracker: two shader rects (the field
  bleeds to the whole window, the lane spans it), one `SafeMesh` batch for the chevron.
- **Shared code touched:** `RideMetrics.set_power_source` and two-sided power bands (the ride
  panel shows the rules' number and is gold exactly in the band; Dodge Ball's one-sided target is
  unchanged), `arrange.py`'s `synthwave` groove, `pulse` bass and `analog` lead (kept for the
  gallery; Live Wire uses `pop` and `octave`), `capture_hub_cards.gd` calls a game's `showcase()`
  if it has one.
- **Per frame:** three 64-float arrays and a dozen uniforms; no node is laid out or redrawn
  unless the chevron's state changes.
- **Tests:** `watt_lane_logic_test` (26: smoothing, membership, the course, announce timing, the
  switch window, catches, streaks, stars) and `watt_lane_scene_test` (12: the HUD's numbers agree
  every frame, the chip, the widget's budget, the lane follows the course, power is height, the
  step label, the chevron's silhouette, the field follows the lane, stopping, the stats).

## GodotPrompter pattern choices

| System | Skill | Picked | Rejected | Why |
| --- | --- | --- | --- | --- |
| Scene structure | `scene-organization` | One `Game` scene composing plain classes: `WattLaneLogic` (RefCounted rules), `WattLaneBackdrop` and `WattLaneTrack` (2D views), `WattLaneStatus` (HUD widget); the logic returns an event list instead of signals | Child scenes per part (`.tscn` for field, lane, HUD) | The house pattern (Safe, Tug, Cadence): rules testable headless, views built in code, no editor scenes to keep in step |
| Rules data | `scene-organization` / `resource-pattern` | Constants in the logic and FTP-scaled params from Kotlin | A custom `Resource` for tuning | Kotlin's `GameCatalog` is the tuning's source for the bike; a Resource would be a second copy |
| 2D view | `2d-essentials` | Full-canvas 2D, no SubViewport; the field and the lane are canvas shaders on two `ColorRect`s, the chevron a `SafeMesh` batch, the glow a `Sprite2D` with additive `CanvasItemMaterial` | A `SubViewport` render or a `Line2D`/`Polygon2D` lane rebuilt each frame | Safe Cracker's measured recipe: 2D fill is what the tablet pays for, so two rects; the lane's shape changes every frame, which a shader reads from arrays for free |
| The lane's shape | `shader-basics` | Three uniform float arrays (`band_lo`, `band_hi`, `trail`, 64 columns) read in the lane's fragment shader, premultiplied alpha so light adds and strokes cover | Rebuilding a mesh every frame in GDScript | 192 floats a frame instead of hundreds of vertices; the glow, the edges, the beam, the riser and the path all read the same data |
| Effects | `shader-basics` / `particles-vfx` | Chevrons, riser, beam, path and the catch flash in the lane shader; bokeh in the field shader; one `CPUParticles2D` burst for a catch | `GPUParticles2D` for bokeh and sparks | No extra draws for the ambient layers; CPU particles avoid the Compatibility renderer's late particle-shader compile |
| HUD | `hud-system` | A slim `PanelContainer` widget in the HUD's top-centre slot, labels changed only on new values, framework tweens for pop and fade | A `ProgressBar` power meter of the game's own | A second power bar is what made Balloon Pump's numbers disagree; the ride panel's W (fed the same smoothed value) is the meter |
| Audio | `audio-system` | Rendered OGG stems through `AudioDirector` (stem gates by intensity), registered one-shots, and two looping `AudioStreamWAV` hums on the SFX bus crossfaded in code | An `AudioStreamSynchronized`/`AudioStreamInteractive` of the game's own | `AudioDirector` already owns crossfades, ducking and the rider's-music rule; the hum is the only continuous sound, so two players are enough |
| Tests | `godot-testing` | GdUnit4 suites: headless logic with scripted power, and the scene stepped by hand (no InputBus) | GUT; driving the scene through the keyboard simulator | The project's framework; stepping by hand makes the HUD agreement check exact frame by frame |

## Game-studio roles and gates (`.claude/ccgs/`)

| Pass | What it changed |
| --- | --- |
| `game-designer` | The rules: the switch window, the 1 s streak grace, the 5 W grid and the softer lane floor and range; then (from the logic tests) jumps of over half a lane and a range that widens for them, and the stars 250 / 1200 / 2000. The rework kept all of it: only the picture changed |
| `godot-gdscript-specialist`, `lead-programmer` | Rules as two typed `RefCounted` classes returning event lists; 26 headless tests; the Kotlin entry; for the rework, the views split into `WattLaneBackdrop` and `WattLaneTrack` and the scene tests rewritten for height |
| `art-director` + `AD-ART-BIBLE` | `ART_BIBLE.md`, rewritten for the abstract look (APPROVE), with the required silhouette check: every shape passes; the rule "no round head with a tail" is written down |
| `technical-artist` | The 2D recipe: two shader rects on the full canvas, no SubViewport; `GFX_POLISH.md` items 1-8 (a luminous lane body, the far washes from a low mip, the beat pulse, the in-lane state) |
| `ux-designer`, `ui-programmer` | `UI_POLISH.md`: the copper accent (lime read as GOOD), the rider's intro copy, the step's watts on the field, the chip's length, never colour alone |
| `audio-director`, `sound-designer` | `AUDIO_POLISH.md`: "Live Wire" (dream-pop electronica, a glockenspiel hook, real song form, extended harmony) replacing generic synthwave; effects re-keyed to Eb; the mix measured against Safe Cracker's and matched |

**Gates before finishing (rework):**

- **AD-VISUAL: APPROVE.** Matches the art bible; distinct from Cadence Karaoke (flat, horizontal,
  gold on teal-black, no tunnel, no orb); the silhouette check passes. Open on the tablet: the
  gold lane against the amber step marks on its warm panel, and whether the beat flare reads as
  flicker.
- **LP-CODE-REVIEW: APPROVE.** The views only draw; the rules never read `InputBus`; the ride
  panel's power source is a bound method; nothing is laid out or redrawn per frame. Public APIs
  are documented.
- **QL-TEST-COVERAGE: ADEQUATE.** The issue's acceptance items (smoothing, membership, announce
  timing, streaks), the HUD agreement every frame, the lane following the course, power as
  height, the step label and the chevron's silhouette are tested. Not covered: pause (the
  framework's), sensor loss (`Effort`'s) and the on-bike lag (the bike acceptance item).
- **TD-FEASIBILITY: CONCERNS (manageable).** Not measured on the tablet (the lock was held).
  Estimated 1.7 screens of fill (Safe Cracker measures 2.1-2.2 at 60 fps). Risks: uniform-array
  indexing in a fragment shader on the GX6250 (fallback: the arrays as a 64×3 float texture);
  the field's six noise reads a pixel (fallback: drop the far washes); the hum loops rendered in
  GDScript once a process (move them to the offline renderer if the first load stutters).
