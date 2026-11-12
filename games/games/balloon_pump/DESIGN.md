# Balloon Pump: design record

> **Retuned 2026-11** (rider feedback: the watts asked were too high). The thresholds below are
> the original design; the current ones, and a before/after table, are in `docs/GAMES.md` under
> this game. The rules' constants and Kotlin's `GameCatalog` params are the source of truth.

> Issue #76 (epic #74). **Status:** the 2D rework, 2026-11-02 (rider: "2D, like Safe Cracker",
> and parity with the wave 1 games' visuals and music; `GFX_POLISH.md`, `UI_POLISH.md`,
> `AUDIO_POLISH.md`). The rules are unchanged from the slice of 2026-11-01. Bike tuning comes
> after the rider approves. Built against `docs/GAMES.md`. **Owner:** whoever changes
> the rules. Change this file in the same commit as any change to `PumpLogic`, the tuning or the
> Kotlin `GameCatalog.BALLOON_PUMP` entry.

The rider's words: *"you are basically powering a pump with the bike that fills the balloons. One
mechanism could be to fill X balloons in Y timeframe. One could be fill as many as you can. Higher
resistance would fill a balloon faster... more work is more points."*

Marks used below: **(rider)** the rider decided it; **(issue)** the issue's own call, kept;
**(my call)** a call made in this slice for the rider to check.

## 1. Overview

The bike drives a big brass air pump at the fair after dark (three places: a fair at dusk,
backstage in a big top, a pier at night; drawn in 2D like Safe Cracker). A balloon sits on the pump's
nozzle; the rider's watts are the air. Each balloon pushes back harder as it fills, so spinning
lightly gets most of the way and the last part asks for the knob or a dig. A full balloon ties
itself off and floats up into a growing bunch over the stall: the bunch is the score you can see.
**Race** fills X balloons within Y seconds; **Max** fills as many as you can before time runs out.

## 2. Player fantasy

*"My legs are the pump."* MDA aesthetics: **Sensation** (the chuff of the pump on every stroke,
the rubber squeak, the pop of the tie-off) and **Challenge** (the last third of a balloon, against
the push line). The micro-loop (10-15 s) is one balloon: easy start, a squeeze at the end, a
satisfying release. The meso-loop is a Race heat (2 minutes) or the growing bunch in Max.
Competence comes from one readable gauge: the needle against the push line. More work is
visibly more points: a bigger, faster-growing bunch.

## 3. Detailed rules

**Air.** The pump's flow follows the rider's power, smoothed over about 2 s (an exponential
average with a 1 s time constant) **(issue)**, because the bike reports about once a second.

**The push line.** A balloon takes air only while the smoothed power is over its push line. The
line rises as the balloon fills, steepest at the end:

- work: from 20% of FTP empty to 45% of FTP full for a medium balloon **(issue)**;
- recovery: 15% to 30% of FTP **(issue)**;
- the curve is `f³` **(my call)**: at 30% of FTP a medium balloon fills to about 74%, at 40% to
  about 93%. A linear line stalled a light spinner at 40% full, which isn't "most of the way".
- Just over the line the valve opens softly: the flow ramps from nothing at the line to full
  at 3% of FTP above it **(my call)**, so a reading hovering on the line doesn't stutter on/off.
- Below the line the balloon **leaks back** slowly (2.5% of a balloon a second), never below
  empty and never popping **(issue)**.
- The gauge on the pump shows the needle (smoothed watts) against the push line (a red-gold
  wedge) **(issue)**. The HUD's status widget repeats it as a bar.

**Balloons** vary **(issue)**: small, medium, large, and the occasional gold one.

| Kind | Air (fill units) | Push line full (work, % FTP) | Points |
| --- | --- | --- | --- |
| Small | 1.0 | 40% | 100 |
| Medium | 1.5 | 45% | 150 |
| Large | 2.0 | 48% | 200 |
| Gold | 1.5 (a medium) | 45% | 450 (×3) |

- Points are 100 × the air, so **points are proportional to the work done** (rider: more work is
  more points). The large's line stops at 48% rather than the issue's "higher" open end, so no
  balloon asks for more than about half of FTP **(my call; the forgiving-watts lesson)**.
- The order is drawn from the segment's seed: the first balloon is always small, so the push line
  is learnt on an easy one (UX pass); then small 35%, medium 40%, large 25%; from the third
  balloon on, each has a 1 in 8 chance to be gold, never two golds in a row **(my call)**.
- The next balloon waits on the rack beside the pump, so a gold or a large is seen a whole
  balloon ahead (the 2 s warning rule).

**A full balloon** ties itself off (1.0 s), is awarded through `Effort.award` (so the resistance
bonus applies on top), and floats up to join the bunch overhead **(issue)**. The next balloon goes
onto the nozzle (0.8 s), then filling resumes.

**Modes** (the Mode option, **rider**). Circuits always play Max **(issue)**.

| | Race | Max |
| --- | --- | --- |
| Timed Just Ride | heats of Y s back to back until the timer ends | one long run until the timer ends |
| Rounds Just Ride | N heats of Y s, then the game ends | N heats of Y s with no target, then the game ends |
| Open Just Ride | heats until the rider ends | one long run until the rider ends |
| Circuit slot | (plays Max) | one run for the slot |

- **A Race heat** is fill X balloons within Y seconds: X is 4 / 5 / 7 on easy / standard /
  hard, Y is 120 s **(issue for 5 in 2:00; my call for 4 and 7)**. Filling the X-th balloon wins
  the heat and awards a **time bonus of 2 points a second left** (through `award`, so the effort
  multiplier applies) **(my call)**. Time out loses the heat (no bonus; balloons already tied
  keep their points).
- Between heats a 4 s break shows the result; the pump rests (no leak) **(my call)**. A balloon
  part-filled at a time-out stays on the nozzle for the next heat.
- 10 s before a Race heat's end the HUD warns "10 s left".

**Recovery** (a circuit's recovery slot): the push line is 15% to 30% of FTP, the flow counts the
power only up to the recovery cap (`power_cap_watts`, 60% of FTP), and the flow is 1.4× a work
segment's **(my call)**, so a comfortable 40% recovery fills like a 56% work ride and pushing
past the cap earns nothing.

**Freezes.** No frames run while paused. While `sensors_ok` is 0 the balloon holds (no fill, no
leak) and `Effort` freezes the score. Cadence under 40 rpm shows "Keep pumping!".

**End.** In a timed slot the segment ends when Kotlin's timer does (a part-filled balloon earns
nothing). In `end_mode: game` the game calls `end_segment()` after the last heat's break.

**Result.** `variant` is `"race"` for Race and `""` for Max **(issue)**. `won` is null in Max; in
Race it is true when more heats were won than lost. Stats: `balloons`, `gold`, `avg_power`,
`peak_power` **(issue)**, plus `heats`, `heats_won` and `fastest_balloon_sec`.

## 4. Formulas

Variables: `P` smoothed power (W), `F` FTP (W), `f` the balloon's fill (0-1), `a` its air units,
`L(f)` its push line (W), `k` the kind's line scale (small 0.8, medium 1.0, large 1.12).

```
P      += (power − P) × (1 − e^(−dt / 1 s))
L(f)    = F × (lo + (hi − lo) × k × f³)          work lo 0.20, hi 0.45; recovery lo 0.15, hi 0.30
open    = smoothstep(L, L + 0.03 F, P)
flow    = K × gain × min(P, cap) / F / a          K = 0.25 /s; gain 1 (work), 1.4 (recovery)
df/dt   = flow × open − LEAK × (P < L)            LEAK = 0.025 /s
points  = 100 × a  (× 3 for gold)  × the effort multiplier
bonus   = 2 × seconds left in a won Race heat  × the effort multiplier
```

Examples (work, F = 200 W): a medium balloon at 100 W (50%) fills in 1.5 / (0.25 × 0.5) = 12 s;
a small at 100 W in 8 s; a large at 100 W in 16 s; a medium at 60 W stalls where
`0.2 + 0.25 f³ = 0.3`, f ≈ 0.74.

**Points a minute** (the star scale; `pump_logic_test` simulates these over 10 minutes, with the
tie-off and the nozzle, gold balloons and the seeded order, for a rider who rides at a share of
FTP and, when a balloon has stalled for 2 s, digs in just past its top line until it ties): Max at
1.0× is about 460 a minute at 30% of FTP, 530 at 40%, 740 at 50%, 870 at 60% and 1120 at 80%. The
same 60% ride at 1.3× (about 48% resistance) makes about 1130. Race (standard) at 60% makes about
940, the time bonus included. A rider who never digs in stalls on the first medium or large
balloon and scores nothing more: the push line is the game.

**Stars** (points a minute, `stars_per_minute`), set so a strong ride at 1.0× stays at 2 stars
and 3 needs about 1.3× (epic #31):

| | 1★ | 2★ | 3★ |
| --- | --- | --- | --- |
| Max: easy / standard / hard | 300 / 350 / 400 | 600 / 650 / 700 | 1000 / 1050 / 1100 |
| Race: easy / standard / hard | 400 / 350 / 300 | 750 / 700 / 650 | 1150 / 1100 / 1050 |

Max's difficulty only moves the bar (the rules are the same). Race's thresholds fall with
difficulty because a bigger target wins fewer heats early, so less time bonus: the same ride
earns the same stars at every difficulty. Every number here is provisional until bike tuning.
**Changed from the issue:** the bonus is 2 points a second, not "a bonus" left open; 5 a second
made Race worth 40% more than Max for the same legs.

## 5. Edge cases

- **Hovering on the line:** the soft valve (3% of FTP) turns a 1 Hz reading that wobbles over
  the line into a slower fill, never a stutter; the leak only starts below the line.
- **No pedalling at all:** the balloon leaks to empty and waits; nothing is lost but time.
- **Grinding** (high resistance, low cadence): the power still fills the balloon; the effort
  multiplier's own guard (60 rpm) keeps the bonus off.
- **Spikes:** the 1 s smoothing means a one-reading spike moves the needle about 60% of the way;
  a 2 s dig is needed to clear a line, by design.
- **A huge FTP or none:** `F` defaults to 150 W (Kotlin's fallback) and is floored at 1 W.
- **A heat won on the last frame:** the bonus is 5 × the seconds left, never negative.
- **Gold degenerate play:** golds are never back to back and are announced a balloon ahead, so
  there is nothing to farm.
- **Sensor loss mid-balloon:** the balloon holds; on return the smoothed power restarts from 0
  (no stale needle).
- **Pause mid tie-off:** frames stop; the tie-off finishes on resume.

## 6. Dependencies

`Effort` (award, multiplier), `InputBus` (power, cadence, sensors_ok), `Session` /
`SessionDirector` (segment, timer, end modes), `GameOptions` (Mode), `AudioDirector` (rendered
theme and effects), `MeshBatch2D` (Safe Cracker's shape batcher, read only) and its static
helpers `MeshBatch2D.rivet`, `MeshBatch2D.soft_dot` and `MeshBatch2D.lit_ring`, Kotlin `GameCatalog.BALLOON_PUMP` (roles, params).

## 7. Tuning knobs

All in `PumpLogic` (constants) or the segment's params (Kotlin, scaled by FTP):

| Knob | Value | Range to try | Where |
| --- | --- | --- | --- |
| Push line empty / full (work) | 20% / 45% FTP | 15-25 / 35-50 | params `push_lo_watts`, `push_hi_watts` |
| Push line empty / full (recovery) | 15% / 30% FTP | | params |
| Line curve exponent | 3 | 2-4 | `LINE_EXP` |
| Soft valve | 3% FTP | 2-6 | `VALVE` |
| Fill rate `K` | 0.25 | 0.18-0.35 | `FILL_K` |
| Leak | 0.025 /s | 0.01-0.05 | `LEAK` |
| Smoothing time constant | 1 s | 0.7-1.5 | `SMOOTH_SEC` |
| Recovery flow gain | 1.4 | 1.2-1.6 | `RECOVERY_GAIN` |
| Race X (easy/standard/hard) | 4 / 5 / 7 | | params `race_balloons` |
| Race Y | 120 s | 90-180 | params `race_sec` |
| Time bonus | 2 /s | 1-5 | `BONUS_PER_SEC` |
| Gold chance | 1 in 8 | | `GOLD_CHANCE` |

## 8. Acceptance criteria

- [x] Logic tests (`tests/unit/pump_logic_test.gd`): fill rate against power, the push line, the
  leak, the tie-off, Race and Max end conditions, stars (1.3× effort for 3 stars, 1.0× short).
- [x] Desktop playable with the keyboard simulator (`-`/`+` cadence, `[`/`]` resistance).
- [ ] On the bike: the last third of a balloon makes the rider reach for the knob without
  grinding. Record the rider's verdict in the PR.

## 9. UX notes (ux-designer, ui-programmer passes)

- **Flow:** intro card (the mode's line, "Push past N W to finish a balloon", the four balloons
  and their points) → a small first balloon → play. Race: "Fill 5 in 2:00!" at each heat, "10 s
  left!" 10 s before the end (also amber on the widget's clock), "Race won! +bonus" or "Time! n
  filled" for the 4 s break.
- **Feedback for every input:** each pedal stroke moves the plunger (and its chuff); over the line
  the balloon swells, squeaks and the badge reads FILLING; under it the badge breathes PUSH!, the
  balloon wobbles and hisses; a tie-off pops, twangs, throws confetti and flies to the bunch.
- **Never colour alone:** every badge is a word, the bar's fill sits left or right of the gold
  tick, balloon kinds differ in size, gold carries a star.
- **Glance budget:** the widget is the hero at the top; the pump's gauge repeats it in the world.
  Messages show in the HUD's centre, above the nozzle's balloon.

## 10. Sound (sound-designer pass)

- **Theme:** "Midnight Carousel" (`songs/balloon_pump.py`; the rework is in `AUDIO_POLISH.md`), a
  swung band-organ carousel, 126 bpm in D minor, 68.6 s with a 7.6 s intro; 1.45 MB with the
  effects. Bed (pop beat, oom-pah root-fifth
  bass) always; harmony (accordion oom-pah, vibes, organ stabs) at intensity 0.5, while the balloon
  takes air; lead (calliope organ, glockenspiel, a flute in the bridge) at 0.85, while the valve is
  wide open (over the push line). Resting and leaking drop to the bed.
- **Effects** (all `pump_` names, since AudioDirector's names are global): a chuff on every pedal
  stroke, pitched up as the balloon fills; a rubber squeak every 1.4 s empty to 0.7 s full while
  it takes air; the tie-off's pop and twang at full level with a 0.6 s music dip (the first mix
  check had it only 3.5 dB over the music; now 14 dB in its best band); a hiss every 0.5 s while
  leaking; a glockenspiel run for gold; the organ's start call, won and lost stings; a tick on each
  of a Race heat's last 5 seconds.
- **Mix** (`tests/render_game_audio.gd --game=balloon_pump`, `analyze_mix.py`): -15.8 LUFS, no
  clipping, true peak -0.8 dBTP after the limiter.

## 11. Gates (2026-11-01, before the slice goes to the rider)

- (These gates were for the 3D slice; the 2D rework's are in §13.)
- **AD-VISUAL: APPROVE.** The captures match the art bible: candy stripes, brass and noon light,
  the nozzle's balloon at the centre, the bunch rising right of it under the status widget. Fixed
  on the way: the sun was behind the stall (maroon stripes), a roof sign with painted balloons
  read as part of the bunch (removed), the plunger's handle hid behind the ride panel (lowered),
  the bunch hid behind the widget (lowered and moved right). Within budget: 51-54 draw calls in
  play on the desktop with the HUD (UI_STYLE §8: 120).
- **LP-CODE-REVIEW: APPROVE** (with `godot-code-review`). Rules in a `RefCounted`, the scene only
  wires; typed GDScript; no `_process` in the widget; labels and the bar change only on a change;
  the Race line formats only when its numbers change; the confetti's amount is fixed (changing it
  reallocated the particles); every sound name is prefixed `pump_`. Kept: `PumpAudio` is a
  preloaded script without `class_name`, Tug's pattern.
- **QL-TEST-COVERAGE: ADEQUATE.** Every issue acceptance item maps to a test: fill rate against
  power, the push line, the leak, the tie-off, Race and Max end conditions and stars
  (`pump_logic_test`, 23 cases); the world (`pump_world_test`, 9), the widget's layout and states
  (`pump_status_test`, 6), the scene's mode, variant, stats and rounds end (`pump_game_test`, 5);
  Kotlin `SessionPlansTest` for the params. Desktop play is shown by `tests/capture_pump.gd`. Gap
  left: the on-bike feel (the issue's third acceptance item) needs the rider.
- **TD-FEASIBILITY: CONCERNS** (viable). The recipe is Tug's and Dodge's, which hold 59-62 fps on
  the tablet; this world is lighter (about 10 draws, no water). Unmeasured on the tablet (the
  tablet lock was held by another agent): the per-pixel balloon shader (small on screen), the sky
  cubemap's first draw and the CPU confetti. If fps drops, the first steps are the render scale
  (0.62 → 0.55, Tug's `RenderScaleStep`) and the balloons' highlight per vertex.

## 12. GodotPrompter patterns

Filled in pass by pass (picked / rejected / why).

| System | Skill | Picked | Rejected | Why |
| --- | --- | --- | --- | --- |
| Rules' phases | `state-machine` | an enum FSM in a `RefCounted` (`PumpLogic.Phase`: LOAD, FILL, TIE, BREAK, OVER) stepped by the scene | node-based states | five states with no per-state nodes, animation or input; nodes would make the rules untestable headless |
| Tests | `godot-testing` | GdUnit4 suites with scripted power (`pump_logic_test`), the repo's framework | GUT | GdUnit4 is vendored and every suite here uses it; a scripted-rider simulation pins the star thresholds |
| Scene tree | `scene-organization` | one game scene (`BalloonPump`) wiring logic, a `PumpStage` Node2D (a baked room and live layers), a `PumpStatus` widget and `PumpAudio`; calls down, events up from the logic's `step` return | separate .tscn per part, or an event bus | each part is used once and owned by the scene; the framework already owns the session's signals |
| 2D look | `2d-essentials` | Safe Cracker's recipe: shapes batched into one `MeshBatch2D` triangle array per layer, the static room, pump and stand baked once per place into a SubViewport texture shown as one sprite, live layers only for what moves | `Polygon2D`/`Line2D` nodes, `Light2D` | each 2D draw call is a batch in Compatibility; `Light2D` draws every lit item again; the bake pays the room's fill once per place |
| Shaders | `shader-basics` | four small `canvas_item` shaders: the balloon (a teardrop SDF lit per pixel, one quad, shared by the nozzle, the flyer and the bunch's MultiMesh), the gauge's push wedge (one uniform), the bulbs' twinkle (phase in UV.x), the pier's sea | balloon sprites per kind and size, redrawn gauges | smooth edges at any size, no textures, no redraws |
| Confetti, hiss, vapour, dust | `particles-vfx` | pooled `CPUParticles2D` one-shots and small continuous emitters | `GPUParticles2D` | Safe Cracker's precedent on the tablet: a few dozen particles, no process-material compile stall |
| The bunch | `godot-optimization` | one `MultiMeshInstance2D` of balloon quads (colour per instance, gold in custom data), swayed by a rotation tween on its parent | a node per balloon | 40 balloons in one draw call; the sway costs a transform |
| Layout guard | `godot-testing` | `pump_layout_test`: the key elements' boxes at their extremes against the stage and every HUD panel | eyeballing captures | the rider caught a clipped handle and a sunk wheel; this can't come back silently |
| HUD widget | `hud-system` | `PumpStatus` in the framework HUD's top-centre slot: a drawn pressure bar (one ShapeBatch), a word badge, count, Race clock and next balloon, updated by setters that touch labels only on a change | a ProgressBar/TextureProgressBar with tweens, or an event-bus score signal | the framework owns the HUD's CanvasLayer and score; the bar needs a push-line tick a ProgressBar can't draw, and per-frame tweens would re-lay out the HUD on the tablet |
| Intro card | `godot-ui` (via hud-system) | `intro_visual()`: the four balloons drawn with their points | text only | the kinds and their worth are learnt before the first one loads |
| Audio | `audio-system` | the framework's `AudioDirector` (buses, the 8-voice SFX pool, stems gated by intensity) with a rendered three-stem OGG theme and OGG one-shots from `games/tools/music`; `PumpAudio` decides when each plays | `AudioStreamSynchronized` or players of the game's own | AudioDirector already owns buses, ducking, the rider's-music rule and the crossfade between games; every shipped game uses this pipeline |
| Desktop hub listing | (framework) | in `LocalHub.ORDER`, on #75's paged hub (this branch is rebased onto `games-75-circuit-pool`) | waiting for a merge | #75 pages the home row 4 at a time, so a sixth game fits |

## 13. Gates for the 2D rework (2026-11-02)

- **AD-ART-BIBLE: APPROVE** and the silhouette check: see `ART_BIBLE.md` §6 and §8.
- **AD-VISUAL: APPROVE** after `GFX_POLISH.md` (the clipped handle, the sunk wheel, the bunch
  off the edge, bulbs over the pump: all fixed and guarded by `pump_layout_test`).
- **LP-CODE-REVIEW: APPROVE.** The rules (`PumpLogic`) and their tests are unchanged; the scene
  talks to its view through the same five calls; no `_process` in the view or the widget; per frame
  only transforms and a few uniforms change.
- **QL-TEST-COVERAGE: ADEQUATE.** `pump_logic_test` (23), `pump_stage_test` (12),
  `pump_layout_test` (5), `pump_status_test` (6), `pump_game_test` (5). Gap: the on-bike feel.
- **TD-FEASIBILITY: CONCERNS** (viable). Safe Cracker's recipe, which the tablet runs; this scene
  has one baked full-screen layer (blended over the sea on the pier) and per-pixel balloons (a fifth
  of the screen at most). Not measured on the tablet in this pass.
