# Watt Lane: design record

Watt Lane (#78, epic #74) is a work game, and a low-profile warm-up. A glowing highway at night:
**your power is your place across the road**, and a lane of watts drifts and jumps ahead of you.
Stay inside it. Every jump is announced about 5 s ahead with arrows on the road, a countdown chip
and a chime (rider's decision).

This file is the game's source of truth for rules and tuning. The issue's "(my call)" items were
proposals; where this pass changed one, the change and the reason are under **Changes from the
issue**. The look is in `ART_BIBLE.md`.

## Player fantasy (game-designer pass)

- **Aesthetic (MDA):** sensation and challenge. You are a light on a night highway; holding the
  lane feels like being locked into a groove, and catching a jump feels like a clean lane change at
  speed.
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
| Space | closed neon grid tunnel | open highway under a night sky, horizon and city glow |
| Axis | the orb moves along the road (depth) | you move **across** the road (left = fewer watts, right = more) |
| Target | a box on the floor, beat rings | two light rails that bend ahead: the future lane is visible on the road |
| Palette | magenta / cyan / violet, by workout part | volt lime lane, amber warnings, sodium street lamps, petrol-blue night |
| Music | synth-funk at the cadence | synthwave at a fixed 104 bpm |
| Changes | rider's − and + | the course's drifts and announced jumps |

## Rules

### One number (HUD agreement)

Balloon Pump's slice showed 48 W in the ride panel and 130 W in its own bar. Watt Lane has exactly
one power number: the **smoothed power**, `W = round(3 s average of the power readings)`.

- The ride panel's W column shows it (`RideMetrics.set_power_source`), not the raw reading.
- The rider's place on the road is drawn from it.
- Lane membership compares it: in lane when `lo ≤ W ≤ hi`, inclusive, both integers.
- The lane's bounds are whole watts on a 5 W grid, and the HUD hero shows exactly `lo–hi`.
- The ride panel's W turns gold inside the band the rules use right now (`set_power_band`), so its
  colour never disagrees with the game.
- The countdown chip names the next lane's exact bounds.

### Power to position

- Smoothed power is a **3 s sliding window** over the readings (time-weighted, 0.1 s bins). A step
  in power moves you linearly across the road over 3 s. (Rejected: an exponential filter with a
  3 s constant, which takes about 9 s to settle; the window's mean delay is 1.5 s.)
- The road is a watt scale: `x = (W / FTP − 0.575) × 24 m`, so the road from 15% to 100% of FTP
  is about 20 m wide. Below or above, you ride on the shoulder (clamped).

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

- **5 s ahead** (`ANNOUNCE_SEC`): a chime, the countdown chip ("UP to 175–215 W in 5", then 4, 3,
  2, 1), and amber chevrons on the road in the lane leading into the bend. The bike reports about
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

- **Stopped / 0 W:** you sit on the left shoulder; a "PEDAL" alert; the streak resets after 1 s.
- **Way over:** the right shoulder; "EASE ▼". There is no power cap: a hard effort is the rider's
  call, and the effort multiplier already rewards resistance.
- **Lane at the range's edge:** jumps go to the side with room; the range never puts `lo` under
  25% of FTP's worth of road.
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
10. **The light-trail bike in first person:** you can't see your own trail from the saddle, so
   in play your bike is its glowing nose and the headlight beam (the trail's head) on the road;
   the hub card and the intro picture show the bike and its trail from behind.

## GodotPrompter pattern choices

(Filled in as each system is built; see the end of this file.)
