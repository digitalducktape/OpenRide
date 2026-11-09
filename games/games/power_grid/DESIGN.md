# Power Grid: design record

> **Retuned 2026-11** (rider feedback: the watts asked were too high). The thresholds below are
> the original design; the current ones, and a before/after table, are in `docs/GAMES.md` under
> this game. The rules' constants and Kotlin's `GameCatalog` params are the source of truth.

> Issue #81 (epic #74). **Status:** built 2026-11-04, ready for a fresh review; bike tuning comes
> after the rider approves. Built against `docs/GAMES.md`. **Owner:** whoever changes the rules.
> Change this file in the same commit as any change to `GridLogic`, the tuning or the Kotlin
> `GameCatalog.POWER_GRID` entry.

Marks below: **(rider)** the rider decided it; **(issue)** the issue's own call, kept; **(my call)** a
call made in this build for the rider to check.

## 1. Overview

Your bike turns the generator for a small valley town at dusk. As the evening goes on demand rises
and the districts come online: houses, street lamps, the funfair, the stadium. Keep up and they stay
lit; fall short and the newest dims, then goes dark, until you catch up. In work, storms take a line
down and a harder ten seconds puts it back. It plays in all four circuit roles and in Just Rides
(minutes and open). It must feel easy in a warm-up and restful in a recovery **(rider)**.

## 2. Player fantasy

*"The town runs on my legs."* MDA aesthetics: **Fantasy** (you are the power station), **Sensation**
(window after window coming on, the dynamo's hum rising with you) and, in work, a gentle
**Challenge**. The micro-loop (10-30 s) is the next district: a callout says what it needs, you hold
it, it lights with a chord. The meso-loop is the evening, dusk to night, ending with the whole town
lit. Competence reads from one bar: the fill against the gold tick. Pillars: **the town is the
score** (you see what you earned), **no cruelty** (nothing is ever taken away), **rest means rest**.

## 3. Detailed rules

**Supply.** Smoothed power: an exponential average with a 2.5 s time constant, about a 5 s average
**(issue)**, seeded with the first reading so a rider already pedalling isn't short at the start
**(my call)**. The ride panel shows this number and no other (`set_power_source`).

**Meeting demand.** The rider meets demand at 90% of it (10% headroom) **(issue)**, and only while
pedalling: cadence at 30 rpm or more and a power reading over 0 **(my call; wave A's lesson)**. The
gate stops scoring on the very frame the pedals stop, though the average still reads high.

**The evening curve** (`GridLogic.curve`), u from 0 to 1 along demand's range:

| Role | Range (% FTP) | Shape |
| --- | --- | --- |
| Work, standard **(issue)** | 45-70 | rises to its peak by 72% of the evening, holds |
| Work, easy / hard **(my call)** | 40-60 / 50-75 | the same |
| Warm-up **(issue)** | 30-50 | rises gently all the way, peak at 85% |
| Cool-down **(issue; shape is my call)** | 30-50 | the warm-up reversed: it starts with the town lit and the town goes to bed |
| Recovery **(my call, inside the issue's 30-50)** | 30-42 | one low swell and back |

Difficulty never moves an easy role. An easy role's demand is clamped under its cap (65%, recovery
60%). `role: free` plays like work.

**Evenings** **(my call)**. A work ride of up to 5 minutes is one evening, however short: a 60 s slot
still reaches the stadium. A longer one is split evenly into evenings of at most 5 minutes (an open
ride, 5-minute evenings without end). Each evening but the last winds down over its last 12%, and
the next starts at dusk with a church bell. Without this a 30-minute ride would be 25 minutes of one
flat line. Easy roles are always one evening.

**Districts** come online at u = 0, 0.3, 0.6, 0.9 **(my call)**. Each is announced 4 s ahead with what
will hold it (the brief's 2 s rule, with room for a 1 Hz bike and a 5 s average).

**Brown-out** **(issue)**. Short for 1 s, and the newest district starts to dim; 3 s later it goes
dark. If the rider stays short the next one starts. Catching up relights one district per 1.5 s.
No points are lost; the score just stops growing. The first 6 s never brown out **(my call)**. In the
easy roles it's 3 s and 5 s **(my call)**: a recovery should never feel like a threat.

**Storms** (work and Just Rides only) **(issue)**. Lightning and a callout warn 3 s ahead. Then the
newest lit district's line goes down. Holding demand's watts plus 15% of FTP for 10 s (`repair_need`,
frozen at the warning so the callout stays true) restores it for 100 points through `award`.
Forgiving **(my call)**: a slip loses a quarter of a second of repair a second, not all of it; after
30 s the line crew fixes it with no bonus and no penalty. The first storm comes 20-32 s in, then
every 50-80 s, never with under 20 s left or as an evening winds down.

**Over the cap (easy roles).** Nothing is lost; the extra just gains nothing. The badge reads EASY,
the note EASE OFF: NO NEED, and the ride panel's watts turn amber. It's a nudge, not a penalty.

**Freezes.** While paused no frames run. While `sensors_ok` is 0 the whole town holds.

**Result.** `won` is null. Stats: `lit_pct`, `districts_max`, `storms_restored`, `avg_power`
**(issue)**, plus `districts_total`, `storms` and `evenings`. The summary shows town lit %, districts
n/4 and lines fixed n/m; an easy ride has no storm stats, so no tile.

## 4. Formulas

```
supply  += (power − supply) × (1 − e^(−dt / 2.5 s))
demand   = lo + (hi − lo) × u(p)                  p = time in the evening / its length
meeting  = cadence ≥ 30 and power > 0 and supply ≥ 0.9 × demand
points/s = 5 × lit × (1.4 in an easy role), while meeting, through Effort.award
repair   = 0.9 × demand + 0.15 × FTP, held 10 s
```

**"Work segments only" (issue).** I read the issue's "through `Effort.award` (work segments only)" as
the multiplier applying in work only, which is how `Effort` works. Easy roles still score, or a
warm-up would end on 0 points and no stars **(my call; check it)**. They have no multiplier, so
`EASY_GAIN` 1.4 stands in for one: a clean easy ride reaches three stars by keeping the lights on,
not by working harder.

**Stars** (points a minute, the same on every difficulty because demand scales instead): 200 / 600 /
1000. A perfect standard ride averages 2.75 districts: about 825 a minute, plus about 35 net from
storms, so 860 at 1.0×, short of three stars; 1.35× reaches 1000 at every length from 60 s to 30
minutes (`grid_logic_test`). Half a ride on target is one star.

## 5. Edge cases

- **Stops pedalling with a high average:** scoring stops at once; a stale power reading with the
  pedals stopped scores nothing and repairs nothing.
- **A district comes online while short:** it stays dark (`district_missed`) until caught up.
- **A storm with nothing lit:** it waits 8 s and tries again.
- **Downed district browned out as well:** `lit()` counts it once.
- **Cool-down:** districts leave as demand falls (`district_rest`), quietly, never as a brown-out.
- **Riding far over demand:** no extra points; the only way to earn more is resistance, through the
  effort multiplier. Mashing has no payoff, which suits a calm game.
- **Sensor loss mid-storm:** the storm's clocks hold with everything else.

## 6. Dependencies

`InputBus` (power, cadence, sensors_ok), `Effort` through `award`, `Hud`, `AudioDirector`, `GameMix`,
Safe Cracker's `SafeMesh` and `SafePlaces.soft_dot` (read only). Kotlin sends `demand_lo_watts`,
`demand_hi_watts` and `storm_watts`, plus the usual `ftp_watts` and `power_cap_watts`.

## 7. Tuning knobs (`GridLogic` constants)

| Knob | Kind | Value | Why |
| --- | --- | --- | --- |
| `HEADROOM` | feel | 0.9 | the issue's 10% |
| `SHORT_SEC`, `DIM_SEC` | feel | 1, 3 (easy 3, 5) | the dim is the 2 s warning |
| `RELIGHT_SEC` | feel | 1.5 | a catch-up should feel quick |
| `STEPS` | curve | 0, 0.3, 0.6, 0.9 | a district about every 15% of the climb |
| `EVENING_MAX` | gate | 300 s | a sawtooth in long rides |
| `POINTS_PER_DISTRICT`, `EASY_GAIN` | curve | 5, 1.4 | set the star table |
| `STORM_*` | gate | see §3 | one storm in a 60 s slot, about one a minute after |

All provisional until the bike.

## 8. Acceptance

- [x] Logic tests: the curve per role, headroom, brown-out and relight, storms (`grid_logic_test`).
- [x] 3 stars needs about 1.3× effort; a perfect 1.0× ride stays short of it.
- [x] A rider never scores without pedalling.
- [ ] On the bike: a warm-up feels easy and a recovery stays restful. **Not tested: the tablet wasn't
  reachable.**

## 9. Patterns (GodotPrompter), picked and rejected

| System | Skill | Picked | Rejected, and why |
| --- | --- | --- | --- |
| Rules | `state-machine`, `godot-testing` | A `RefCounted` class; a three-state enum FSM for the storm, plain timers for the brown-out | Node-based states: no enter/exit logic worth nodes, and rules must run headless |
| Districts | `gdscript-patterns` | A prefix (`powered` of `online`) plus one `down_index` | Four independent district objects: "newest goes first" would need its own ordering, and could disagree with the HUD |
| The scene | `2d-essentials` | Paint everything still into a `SafeMesh` batch, baked by two SubViewports (dusk, night) | Grading one bake in a shader: night would only be a darker dusk. Redrawing per frame: tablet cost |
| Dusk to night | `shader-basics` | One opaque shader sprite mixing the two bakes (`blend_disabled`) | Two stacked sprites with alpha: two screens of blended fill on a fill-bound tablet |
| Lights | `shader-basics`, `godot-optimization` | One mesh, each light's channel and turn in its UV, four uniform levels | Light2D: per-pixel cost in Compatibility. A Node per district with `modulate`: can't come on window by window. SafeMesh: every vertex of a light must share a UV, and it can't |
| Power on the wires | `shader-basics` | A strip mesh with one phase uniform, advanced in GDScript | `TIME` in the shader: a change of speed would jump every dash |
| Small effects | `particles-vfx` | `CPUParticles2D`, as every game here does | GPU particles: not worth a process material for 6-34 sparks on GL Compatibility |
| Callouts | `hud-system` | The game's own `GridBanner` lane, by priority | `hud.show_message`: it sits on the town, the hero |
| Motion | `tween-animation` | Tweens for one-shots; per-frame `move_toward` for levels the logic drives | Tweens for the levels: they'd fight every frame's new target |
| Audio | `audio-system` | Rendered stems through `AudioDirector`; two loop players for what must be pitched or faded | One-shot voices for the hum: they can't change pitch once playing |

## 10. Gate notes

- **TD-FEASIBILITY: VIABLE.** Risks named up front: fill (two bakes, a full-screen sprite), and the
  draw-call budget. The design keeps one opaque screen and small additive meshes; a rain rect is the
  only large blended layer, and only in storms. Unmeasured on the tablet.
- **LP-CODE-REVIEW: CONCERNS, then fixed.** See `GFX_POLISH.md`'s "Code review". Left open:
  `GridValley.gd` is one long file (art data), and some paint functions run past 40 lines, as
  `SafePlaces` and `PumpPlaces` do.
- **QL-TEST-COVERAGE: GAPS.** Rules, layout and scene are covered. No test plays a full session
  through `SessionDirector` for this game, and the on-bike criterion is open.
