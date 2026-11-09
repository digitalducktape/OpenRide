# Ready for Launch: design record

> **Retuned 2026-11** (rider feedback: the watts asked were too high). The thresholds below are
> the original design; the current ones, and a before/after table, are in `docs/GAMES.md` under
> this game. The rules' constants and Kotlin's `GameCatalog` params are the source of truth.

> Issue #82, epic #74. 2D, like Safe Cracker (rider, 2026-11-02). The rider's calls are marked;
> everything else is the builder's, for the rider to check. Rules: `LaunchLogic.gd`
> (`launch_logic_test`); the scene and frame: `launch_scene_test`. The look: `ART_BIBLE.md`.

## Overview

Each round is one rocket launch of about 90 s. Fuel it with a steady effort, keep spinning through
the count, then push all out at liftoff. The climb is power × the fuel multiplier, through the
clouds, the edge of space, orbit and the Moon. A 1:30 circuit slot plays one launch; a longer ride
flies more, each a bigger rocket on a new pad.

**Player fantasy (MDA: sensation, challenge).** The build-up and the release: patience on the pad,
tension on the count, then your own legs throwing a rocket at the Moon. Interval training in
disguise: a long steady block, then a short hard sprint, then recovery.

**The loops.** Micro: the tank rising under a steady effort, the gold mark on the watts. Launch:
fuel, count, push, coast, a result to beat. Ride: a bigger rocket, a new pad, your best altitude.

## Rules

| Phase | Seconds | What happens |
| --- | --- | --- |
| Fuel | 45 | Fuel flows while smoothed power is over the line. Holding `fuel_full_watts` fills the tank |
| Count | 10 | Keep spinning. The tank is locked. T-10 to T-1 on the clock and in tones |
| Push | 18 | Climb a second = power share of the target (capped at 1.3) × the fuel multiplier |
| Coast | 15 | Momentum fades (τ 3 s). An easy spin keeps climbing; stopping stops it |
| Result | 2 | The launch's altitude; then the next launch |

**Params** (Kotlin, `GameCatalog.READY_FOR_LAUNCH`): `fuel_line_watts` 45 / 50 / 55% of FTP and
`fuel_full_watts` 55 / 60 / 65% for easy / standard / hard, plus the plan's `target_watts` (90 / 105
/ 120%) as the push's 1.0. The issue's numbers are the standard ones.

**Formulas**
- Smoothed power: first order, τ 1 s (a step is 86% in after 2 s). The ride panel shows this figure
  through `RideMetrics.set_power_source`, so the HUD is what the rules use.
- Fuel a second = (P − line) / (full − line) / (fuel_sec × 0.9), capped at 1.25 × the rate at `full`.
  The 0.9 is headroom: a little under "full" on average still fills it. The cap makes it a steady
  effort: a 10 s sprint then rest can't fill the tank.
- Fuel multiplier = 0.5 empty to 1.5 full, so a full tank flies three times as far.
- Share = smoothed / target, at most 1.3. Speed eases to share × multiplier with τ 0.6 s.
- The clamps let go at a quarter of the target, so a weak push still flies.
- Kilometres (`km_for`): linear to 12 km, then a geometric step between milestones.

**Milestones**

| Milestone | Climb | km | Bonus | Stage |
| --- | --- | --- | --- | --- |
| Clouds | 5 | 12 | 100 | the booster drops |
| Edge of space | 12 | 100 | 200 | the middle stage (Mk II, III) |
| Orbit | 22 | 400 | 300 | the upper stage: the capsule flies on |
| The Moon | 34 | 384,400 | 500 | it lands; the climb stops there |

## Scoring

- 40 points a climb unit, through `Game.award` (the effort multiplier applies), plus the bonuses.
- **Nothing scores without pedalling.** Points come only from climb, and climb needs a raw reading
  of at least 10% of FTP. Fuelling and the count score nothing. `launch_logic_test` and
  `launch_scene_test` ride a whole launch at 0 W: no points, the launch is scrubbed.
- A launch is capped at 34 × 40 + 1100 = 2460 points.
- **Stars are points a minute** (300 / 950 / 2000, all difficulties, because watts carry the
  difficulty): an empty tank and the target about 330 (1 star); a full tank and the target reach
  orbit, about 1230 (2 stars); a perfect Moon launch at 1.0× is 1640, short of 3; at 1.3× it is
  2130. Tested.

## Slots and rounds

- Launches share a timed slot evenly: `planned = floor(sec / 90)`, `launch_sec = sec / planned`. The
  spare time goes 60% to fuelling, 40% to the coast, and points scale by `launch_sec / 90`, so stars
  a minute hold. A 5-minute ride is three launches of 100 s; no launch is ever cut short.
- `min_sec` is 90, so the circuit draw leaves it out of 60 s work slots and it plays the 90 s ones. Rounds: one launch a round, 90 s, and the game ends itself. Open: until the rider
  ends it. After a timed slot's last launch the result holds for Kotlin's timer.
- A single-launch slot gets any rocket; a longer ride starts at Mk I and builds up, then repeats.

## Edge cases

| Case | What happens |
| --- | --- |
| Never pedals | No fuel, no lift, no points; "Scrubbed" at the end of the push |
| Stops mid-push or in the coast | The climb and points stop at once (raw reading); the rocket hangs |
| Fuels hard early | The tank fills early: "Tank full! Ease off, save your legs" |
| Sprints in the fuelling | The flow cap: it can't fill in a sprint |
| Over-pushes | Share caps at 1.3 × target: more watts past that add nothing |
| Moon before the push ends | The rest of the push turns into coast; the launch keeps its length |
| Sensors lost | Fuel and climb freeze; the clock runs, so a slot keeps its timing |
| Warning time | The push is announced 10 s ahead, its end 3 s ahead (the rule asks 2 s) |

## Tuning knobs

Feel: `SMOOTH_TAU`, `SPEED_TAU`, `COAST_TAU`. Curve: `MILESTONES`, `POINTS_PER_CLIMB`, `PUSH_CAP`,
`FUEL_MIN_MULT`, `FUEL_MAX_MULT`. Gate: the phase lengths, `FILL_SHARE`, `FLOW_CAP`, `LIFT_SHARE`.
**On the bike:** that the sprint is hard but short, that 60% of FTP is comfortable, that the Moon is
earned (at standard it takes about 1.1 × the target with a full tank).

## Calls for the rider

- Difficulty moves the fuel lines by 5% of FTP each way and uses the plan's target for the push.
- Fuelling and the count score nothing, as the issue says (altitude scores). So the HUD's score is
  still for the first minute of a launch; the tank is the progress there.
- The Moon ends the climb. A rider over the top gets the landing, not extra points.
- Launch sites: three, one per rocket on a ride: the issue's coast at first light, desert flats at
  dusk and a polar shelf at night (a **Launch site** option under More options).

## Patterns (GodotPrompter)

| System | Skill | Picked | Rejected, and why |
| --- | --- | --- | --- |
| Rules | state-machine | Enum FSM in a `RefCounted` | Node states: one shared clock, must run headless |
| The picture | 2d-essentials | `SafeMesh` batches; the place baked once by a SubViewport | `_draw` per frame (a call per shape); texture art (the rider's approach is drawn in code) |
| The camera ride | 2d-essentials | The climb scrolls and scales layers by hand | `Camera2D`: it would fight `Stage`'s canvas transform |
| Sky, sea, aurora, flame, plume, hose | shader-basics | Small `canvas_item` shaders on one rect each | Per-frame mesh rebuilds |
| The Earth | shader-basics | A sphere shader over an original generated map | Mesh blobs (the rider: "earth doesn't even look like earth"); a photo (not original) |
| Smoke, steam, snow, dust | particles-vfx | `CPUParticles2D`, 12-60 each | `GPUParticles2D`: no trails in Compatibility, and CPU matches the other 2D games |
| HUD | hud-system | One slim top-centre widget, values change only on a change | A second panel; watts in the widget (once only, in the ride panel) |
| Motion | tween-animation | Tweens for one-offs (arms, hose, legs, shutter); per-frame framing eased by the logic | An AnimationPlayer: nothing is keyframed |
| Audio | audio-system | Rendered stems gated by phase; two loop players; `play_sfx` one-shots | MusicGen, `AudioStreamInteractive`: the framework's stems are enough |
| Tests | godot-testing | gdUnit4: logic headless, scene with the real HUD | Pixel tests: brittle; the rects drive the frame check |
| Budget | godot-optimization | No redraws in play, few vertices per frame | Baking the cloud decks: cheaper to cut vertices 6× |

## Reviews

- **TD-FEASIBILITY: VIABLE.** Risks: the full-frame sky and the Earth shader's fill on the GX6250.
  The sky is one opaque rect, shown only in flight, when the baked place is off screen. The Earth
  covers part of the screen for about ten seconds of a launch. Fallback if it drops frames: the same
  map on a smaller quad, or `lod` raised. **Not measured on the tablet.**
- **QL-TEST-COVERAGE: ADEQUATE.** See `launch_logic_test` and `launch_scene_test`: every item of the
  issue's acceptance list has a test but the bike's feel, which needs the bike.
- **LP-CODE-REVIEW: CONCERNS, addressed.** See the end of `GFX_POLISH.md`.
