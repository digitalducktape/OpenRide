# Balloon Pump: design record

> Issue #76 (epic #74). **Status:** the look-and-sound slice, 2026-11-01, awaiting the rider's
> approval; bike tuning comes after it. Built against `docs/GAMES.md`. **Owner:** whoever changes
> the rules. Change this file in the same commit as any change to `PumpLogic`, the tuning or the
> Kotlin `GameCatalog.BALLOON_PUMP` entry.

The rider's words: *"you are basically powering a pump with the bike that fills the balloons. One
mechanism could be to fill X balloons in Y timeframe. One could be fill as many as you can. Higher
resistance would fill a balloon faster... more work is more points."*

Marks used below: **(rider)** the rider decided it; **(issue)** the issue's own call, kept;
**(my call)** a call made in this slice for the rider to check.

## 1. Overview

The bike drives a big brass air pump at a daylight fairground stall. A balloon sits on the pump's
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
- The order is drawn from the segment's seed: small 35%, medium 40%, large 25%; from the third
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
  the heat and awards a **time bonus of 5 points a second left** (through `award`, so the effort
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
bonus   = 5 × seconds left in a won Race heat  × the effort multiplier
```

Examples (work, F = 200 W): a medium balloon at 100 W (50%) fills in 1.5 / (0.25 × 0.5) = 12 s;
a small at 100 W in 8 s; a large at 100 W in 16 s; a medium at 60 W stalls where
`0.2 + 0.25 f³ = 0.3`, f ≈ 0.74.

**Points a minute** (the star scale; `pump_logic_test` simulates these, with the tie-off and the
nozzle, gold balloons and the seeded order): about 600 a minute at 40% of FTP, 780 at 50%,
950 at 60%, at 1.0×. A rider at 60% with the 1.3× multiplier (about 48% resistance) makes about
1230.

**Stars** (points a minute, `stars_per_minute`), set so a strong ride at 1.0× stays at 2 stars
and 3 needs about 1.3× (epic #31):

| | 1★ | 2★ | 3★ |
| --- | --- | --- | --- |
| Max: easy / standard / hard | 350 / 400 / 450 | 650 / 700 / 750 | 1100 / 1150 / 1200 |
| Race | as Max + 100 | as Max + 150 | as Max + 200 |

The Race thresholds sit higher because the time bonus adds about 150-300 a minute for a rider who
wins heats. Every number here is provisional until bike tuning.

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
theme and effects), `WorldLook` and the shared `world_look.gdshaderinc`, `KartMeshKit` (read
only, for baking meshes), Kotlin `GameCatalog.BALLOON_PUMP` (roles, params).

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
| Time bonus | 5 /s | 2-8 | `BONUS_PER_SEC` |
| Gold chance | 1 in 8 | | `GOLD_CHANCE` |

## 8. Acceptance criteria

- [x] Logic tests (`tests/unit/pump_logic_test.gd`): fill rate against power, the push line, the
  leak, the tie-off, Race and Max end conditions, stars (1.3× effort for 3 stars, 1.0× short).
- [x] Desktop playable with the keyboard simulator (`-`/`+` cadence, `[`/`]` resistance).
- [ ] On the bike: the last third of a balloon makes the rider reach for the knob without
  grinding. Record the rider's verdict in the PR.

## 9. GodotPrompter patterns

Filled in pass by pass (picked / rejected / why).

| System | Skill | Picked | Rejected | Why |
| --- | --- | --- | --- | --- |
