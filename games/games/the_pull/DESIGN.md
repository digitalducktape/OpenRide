# The Pull (#79): design

A sled pull at a county fair, in first person from the bike. A chain runs from the bike to a
heavy steel sled. As the sled moves, its weight box slides forward along the pan, so every metre
needs more watts than the last. Pull until you max out. Distance is the score.

Issue #79 is the spec, and the epic is #74. This file records the rules, the tuning, every call
the issue left open ("my call") and what became of it, and the GodotPrompter pattern choices.
The rider's words: *"This is kinda like a tractor race, so you are pulling a sled of weight.
Distance not altitude."* *It is a pure game, not an FTP test.*

## Player fantasy (game-designer pass)

- **Aesthetic (MDA):** Challenge and Sensation. You lean into a load that grows heavier, hear
  the motor strain and the box scrape, and see the boards go by more slowly. The tension peaks
  near your own best flag, with the crowd rising.
- **Dynamic:** pacing hardly matters. The distance is set by the watts you can still push when
  the drag catches up with you. That makes it a dig-deep finisher, not a pacing puzzle, and a
  hard start doesn't waste the pull.
- **Competence (SDT):** one readable rule. The sled needs N watts here; the sled-need tick on the
  ride metrics' watts gauge shows N, and your watts go gold while you beat it.
- **Loop:** a pull of 1-5 minutes (the micro and meso loop), a recovery card, then the next pull
  with your best flag further down the track (the sawtooth).

## Rules

### The pull

| Phase | What happens |
| --- | --- |
| `SET` (3.5 s) | The view looks back over the shoulder at the sled and chain. "Get set…" shows at once, and the horn sounds at the end, so the start is announced 3.5 s ahead. Pedalling doesn't move the sled. |
| `PULL` | The sled moves (below). It ends in a **stall**, a **Full Pull** or **time** (the overtime guard). |
| `RESULT` (4 s) | The distance and how it ended show. A new best plants the flag. |
| `RECOVERY` | A rest card with a countdown, then the next pull's `SET`. 60 s in rounds and open rides, 30 s in a timed ride. |
| `DONE` | No more pulls. The scene ends the segment. |

### Drag, from the issue

`required(d) = FTP × (0.30 + 0.70 × d / d_ref)` watts. At `d_ref` the sled needs exactly FTP.

### Speed (my call, refined)

The issue asks for speed from the gap between smoothed power and drag, easing to zero and never
going backwards. In a linear model (speed ∝ gap), a rider holding steady watts approaches the
stall point exponentially and never quite stops. The stall then depends on the crawl threshold
rather than on the rider. So speed follows the **square root** of the gap, which reaches zero in
finite time, the way a real sled bogs down at the end:

```
gap      = (P_smoothed − required(d)) / FTP
v_target = V_MAX × sqrt(clamp(gap / G_FULL, 0, G_CAP))
v       → v_target at most ACCEL (0.6 m/s²) up, DECEL (0.5 m/s²) down, never below 0
d       += v × dt
```

- `P_smoothed`: an exponential average of the bike's power, time constant 1.5 s. The bike sends
  a new reading about once a second.
- `V_MAX` = 2.5 m/s, the speed at the start for a rider at FTP. `G_FULL` = 0.70 is that rider's
  gap at the start.
- `G_CAP` = 1.5 lets a sprint go up to 1.22 × `V_MAX`, so it isn't wasted, but it can't bank
  much distance: the distance is set by the end of the pull.

### Stall (forgiving, my call)

- The stall clock only runs once the sled has rolled 1 m, or 15 s after the horn, so a slow
  start isn't punished.
- The pull ends when the sled has crawled below 0.2 m/s for **5 s** in a row. Any moment at or
  above crawl resets the clock.
- **Dig in!** shows (with a bell) after 1.5 s below crawl, so the warning comes 3.5 s before the
  stall (the brief asks for 2 s or more).
- Readings arrive once a second. A missed or low reading eases the sled down at 0.5 m/s² and
  doesn't stop it. In the model, ±15% random noise on 1 Hz readings stalled no earlier than
  steady power did (`the_pull_logic_test`).
- While `sensors_ok` is 0, or the session is paused, the logic doesn't step: the sled and the
  stall clock freeze.

### Full Pull

A line at `FULL_FACTOR` × `d_ref` (1.12). There the sled needs 108% of FTP. Crossing it ends the
pull as a Full Pull, with a +500 bonus. "Full Pull" is a generic sport term.

### Modes (`timed_end_mode: game`)

- **Rounds:** N pulls (1-5) with a 60 s recovery card between them, then `end_segment()`.
  Kotlin's `roundSec` is 300 (a pull plus its rest), so N rounds are `N × 300` s.
- **Minutes:** new pulls until the timer ends. With `end_mode: game`, Kotlin doesn't cut the
  segment at its length. The game lets the pull in progress finish, then ends. It doesn't start a
  new pull with under 60 s left (`MIN_PULL_LEFT`). Kotlin hard-stops at 1.5 × the length, so a
  pull still going at 1.45 × ends as **Time!** with its distance kept (the overtime guard, which
  applies in every mode with a length). Between pulls the rest is 30 s.
- **Open:** pulls, each with a 60 s rest, until the rider ends the session.
- **Custom circuit:** The Pull has **no circuit role**. A custom circuit plays it as a `free`
  slot (like Kart Race), with `end_mode: game` from `timedEndMode`, so it behaves as a timed
  ride.

### Scoring and stars

- 10 points a metre, awarded as the sled moves, through `award()` (Effort's multiplier).
- A Full Pull adds 500 through `award()`.
- `effort_in_just_ride` is true.
- **Stars come from the best pull's points** (my refinement). The issue says stars come from
  distance per difficulty, not per minute. Summing every pull would let a long ride's count of
  pulls buy stars, so the game sets the result's stars from its best single pull (its points,
  multiplier included). The score is still every pull's points added up.
- Thresholds (best-pull points) scale with `d_ref`, so the same share of FTP earns the same stars
  at every difficulty:

| Difficulty | `d_ref` | FTP pull lasts | 1★ | 2★ | 3★ |
| --- | --- | --- | --- | --- | --- |
| easy | 360 m | ~4.5 min | 720 | 2400 | 4320 |
| standard | 300 m | ~3.8 min | 600 | 2000 | 3600 |
| hard | 250 m | ~3.2 min | 500 | 1670 | 3000 |

- What riders earn on standard, from the model:
  - A steady half of FTP at 1.0× goes about 85 m (850 points): 1★.
  - Three quarters of FTP goes about 190 m: 1★. About 0.78 × FTP (205 m) earns 2★.
  - A steady FTP at 1.0× goes about 299 m (≈ 2990 points): 2★, short of 3★, as the brief requires.
  - The same pull at 1.3× (resistance 48% or more) earns ≈ 3890 points: 3★.
  - A Full Pull (≥ 108% of FTP at the end) earns 3★ by itself (3360 + 500), since it is more
    than the reference effort.

### Stats

`distance_m` (the best pull's distance), `best_distance_m` (the rider's best ever at this
difficulty, this ride's included), `peak_power` (the highest **raw** reading, which is what the
ride metrics showed), `pull_sec` (the best pull's duration), plus `pulls` and `full_pulls`.

## HUD agreement (rider's ask)

An earlier slice showed one watts figure in the ride metrics and another in the game's own bar
in the same capture. Here:

- The game's widget **never shows the rider's watts**. The ride metrics (raw `InputBus.power`)
  are the only place they appear.
- The sled's need is computed once (`PullLogic.required_watts()`, rounded) and shown in two
  places from that one value: the widget's **SLED NEEDS n W** chip, and the ride metrics' power
  band (`set_power_band(n)`), whose tick marks n on the watts gauge and turns the watts gold
  at n or more.
- The distance (hero), the best flag and the progress bar all read `PullLogic.distance` and
  `best_distance`, floored to whole metres the same way (`PullLogic.shown_m`).
- The gold watts are raw and the sled's speed follows smoothed power, so for about 1-2 s after a
  change in effort they can disagree. That reads as the sled's inertia, and nothing shows a
  number that contradicts another.

## Edge cases

- **No pedalling at the horn:** the sled stays put. The stall clock starts 15 s after the horn,
  so a rider who never pedals stalls at 0 m after 20 s.
- **Stops pedalling mid-pull:** the sled slows at 0.5 m/s² and, at about 2 m/s, takes about 4 s
  to fall below crawl, then 5 s more to stall. The rider has ~9 s to restart.
- **Sprint at the start:** capped at 1.22 × `V_MAX`. It gives a little time back, not distance.
- **Sensor loss or pause:** frozen, as above. Effort freezes the score.
- **A pull in progress when the timer ends:** it carries on, up to the 1.45 × overtime guard.
- **Open ride ended mid-pull:** the points so far count. The pull's distance counts for the stats
  and the best.
- **Below 60 rpm:** no effort multiplier (Effort's grinding guard). The sled doesn't care about
  cadence, only watts.

## Tuning knobs

| Knob | Kind | Value | Range | Why |
| --- | --- | --- | --- | --- |
| `d_ref_m` (Kotlin param) | curve | 360 / 300 / 250 | 200-450 | FTP pull of 3-5 min (acceptance) |
| `V_MAX` | feel | 2.5 m/s | 2-3.5 | boards pass every ~10 s at the start |
| `FULL_FACTOR` | gate | 1.12 | 1.05-1.2 | needs 108% FTP at the end |
| `CRAWL` | feel | 0.2 m/s | 0.1-0.3 | below it the sled reads as stopped |
| `STALL_SEC` | feel | 5 s | 4-8 | forgiving of 1 Hz readings |
| `WARN_SEC` | feel | 1.5 s | 1-2 | gives ≥ 2 s of warning |
| `POWER_TAU` | feel | 1.5 s | 1-2.5 | smooths 1 Hz steps |
| rests | gate | 60 / 30 s | | rounds and open / timed |

The Kotlin params carry `d_ref_m` and `full_factor`, so a tuning change on the bike needs no new
game build.

## Acceptance criteria and tests

- Drag curve, speed integration, stall detection (forgiving with 1 Hz readings and noise), the
  warning ahead of the stall, Full Pull, rounds, minutes, open and the overtime guard: all in
  `tests/unit/the_pull_logic_test.gd`.
- A steady FTP pull lasts 3-5 minutes at every difficulty (checked by the test with 1 Hz
  readings; still to confirm on the bike).
- Stars: FTP at 1.0× stays short of 3★, and FTP at 1.3× reaches it, at every difficulty.
- HUD agreement: `the_pull_scene_test.gd` checks that the widget's need equals the metrics'
  power band and that the widget shows no rider watts.

## My calls the rider should check

1. Speed follows the square root of the gap (a finite bog-down), not a straight line.
2. Stars come from the best single pull, not the session's sum.
3. A timed ride rests 30 s between pulls, not 60 s, so a 10-minute ride fits more pulls.
4. A pull may run past a timed ride's end, up to 1.45 × its length.
5. The Full Pull line sits at 1.12 × `d_ref` (108% FTP at the end).
6. The sled is seen in a handlebar mirror and in a look back over the shoulder at each pull's
   `SET`.

## Audio (sound-designer pass)

All original and synthesised by `games/tools/music/songs/the_pull.py` (no samples). The music is
"Heavy Haul", a county-fair boogie at 116 bpm in E: driving drums, octave bass, chugs and power
chords, a twang guitar lead, then brass and piano in the chorus. Its stem gates are harmony at
0.5 (the sled is rolling) and lead at 0.85 (within 15 m of the best flag, or 20 m of the Full
Pull line). The intensity is 0.4 while setting, 0.6 while pulling and 0.3 at rest.

| Event | Sound | Level | Notes |
| --- | --- | --- | --- |
| Horn (GO) | `pull_horn`: two air-horn blasts | -2 dB, 1 s moment duck | announced 3.5 s ahead by the look back and "Get set" |
| Every 25 m board | `board_pass`: a dry wooden clack | -1 dB | subtle by design; the loops mask it a little (cut-through ≈ 0 dB) |
| Dig in! | `dig_in`: two bell knocks | -3 dB | 3.5 s before the stall |
| Near the best | `crowd_swell` | -6 dB | the crowd jumps too |
| Past the best | `best_pass`: a rising brass call | -3 dB, sting duck | |
| Full Pull | `full_pull` fanfare and `crowd_swell` | 0 / -2 dB, sting duck 2.5 s | confetti and a floodlight flare |
| Stall | `stall_horn`: a falling horn and a clank | -3 dB, 1.5 s moment duck | the view dips |
| Time! | `stall_horn` | -8 dB | |
| Loop: motor | `engine_drone` | -26 dB idle → -9 dB at FTP; pitch 0.7-1.6× with watts / FTP | the issue's "engine-like drone pitched to power" |
| Loop: chain | `chain_strain` | silent → -8 dB with strain | strain = how far the speed has dropped under 1 m/s with power on |
| Loop: box | `box_scrape` | silent → -11 dB with speed | the weight box grinding |

The loops play on the game's own players on the SFX bus, eased over 0.25 s so the 1 Hz readings
don't step them, and paused with the game. The bus effects are an outdoor reverb and a glue
compressor on the music, a reverb and a limiter on the effects, and the shared -1 dBFS Master
limiter. An offline render (`tests/render_game_audio.gd --game=the_pull`, 90 s) measured the mix
at -18.4 LUFS with a -2.5 dBFS peak before the limiter and no clipping. The horn cuts through by
14 dB broadband, and the stall horn by 10 dB.

## GodotPrompter pattern choices

Filled in at each pass. The pattern picked, the alternative rejected, and why.

| System | Skill | Picked | Rejected | Why |
| --- | --- | --- | --- | --- |
| Pull phases | `state-machine` | enum FSM in the `RefCounted` logic | node-based states | 5 small states with no enter/exit animation of their own; the logic must test headless |
| Logic tests | `godot-testing` | GdUnit4 suite driving `PullLogic.step` with scripted 1 Hz readings | scene runner | the repo's suites are GdUnit4; the rules don't need a tree |
