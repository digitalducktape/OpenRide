# Gate Crasher (#80): design

Show jumping in first person from the saddle. Pedal to canter round a course of fences, and stand
up on the bike at each take-off line to clear it. Issue #80 is the spec, and the epic is #74. This
file records the rules, the tuning, every call the issue left open ("my call") and the patterns.

## Player fantasy (game-designer pass)

- **Aesthetic (MDA):** Sensation and Challenge. The hoofbeats, the count-in, the lift over the rail.
- **Dynamic:** a steady rhythm. Every 6-7 s there's a count of three and a stand, so a round is
  eight short out-of-the-saddle efforts over a steady spin: interval work without calling it that.
- **Competence (SDT):** one readable rule. Stand on the last chime. Three cues say when: the sound,
  the number on screen and the gold line on the ground.
- **Loop:** a fence (micro), a round of eight with a clear-round bonus (meso), rounds in a ride.

## Rules

### Pace

Power is smoothed over 1.5 s (the bike reads about once a second). Under 30 rpm the horse stops.
The canter runs from 4.5 m/s at 10% of `pace_watts` to 8.5 m/s at `pace_watts`, and on to the cap,
10 m/s, at 130%. Faster rides score more (more ground and more fences a minute) but the count
comes round sooner.

### The window, with the lag included

`StandingDetector` reports a stand 0.5 s after it happens, and a sit 1.5 s after. `GateLogic` works
in detection time:

- The rider should stand on the line, the moment the last chime sounds. That reads 0.5 s later.
- The window is centred on that moment: with `window_sec` 1.2 a stand from 0.6 s before the line to
  0.6 s after it is good. In detection time that is 0.1 s before the line to 1.1 s after.
- Only a stand that **starts** in the window counts, so riding out of the saddle clears nothing.
- The line is 18 m before the fence and the horse leaves the ground 4 m before it, so the window
  has closed before take-off even at 10 m/s (the longest window, 1.4 s, closes at 1.2 s: 12 m).

Fences are 54.5 m apart (436 m lap, 8 fences), which is 5.45 s at the 10 m/s cap. `GateLogic` caps
the fence count so this can't drop below 5 s. The latest stand, held 1 s, reads seated 3.1 s after
the line, and the next window opens at 5.35 s.

### Faults

| What | Result |
| --- | --- |
| A stand in the window | Clear: 50 points at the fence |
| Up already when the window opens | "4 faults: too early", the rail falls, -30 |
| No stand by the window's end | "4 faults: too late", the rail falls, -30 |
| Over the fence with the legs stopped | "Keep pedalling!", no points, no faults, no clear round |

A rider who is up at the first beat hears a soft nudge, with 3 s left to sit (the sit takes 1.5 s to
read). A round of eight clears pays 100.

### Lost camera

Any `tracker_state` but tracking (3) starts a circle at once: face lost (4), and also a calibration
that failed (0), which on the tablet faulted every fence until this rule covered it. Nothing is judged, nothing scores, and any fence in
play starts over. The horse circles (7 m radius, 6 m/s) while sliding back along the course, so it
comes out at least 3.2 s at pace from the line, with a whole countdown ahead. Once the rider is seen
the circle finishes its turn (at most about 7 s). Sensor loss freezes the ride.

### Modes

A round is one lap. Rounds ride `rounds` laps and end the segment; timed and open rides go on until
Kotlin or the rider ends them. A lap at pace takes 51 s, so `roundSec` is 65.

### Scoring and stars

Ground covered pays 0.25 a metre, only while pedalling. Everything goes through `award` and
`penalize`. Stars are points a minute. A perfect ride at pace at 1.0x scores about 700; flat out at
1.0x about 840; at pace at 1.3x about 920. So 3 stars are 860 / 880 / 900 (easy, standard, hard):
above the first two, below the third (`gate_crasher_logic_test`).

### Params (all from `GameCatalog`, scaled by FTP)

| Param | Easy | Standard | Hard |
| --- | --- | --- | --- |
| `pace_watts` | 45% FTP | 55% FTP | 65% FTP |
| `window_sec` | 1.4 | 1.2 | 1.2 |
| `stand_lag_sec` | 0.5 | 0.5 | 0.5 |
| `fences` | 8 | 8 | 8 |

## On the tablet

60.4 fps average, 58 minimum, over 52 s of play on the mock build, no render-scale steps. **The camera
was not running** (nobody was on the bike, so calibration failed); Kart Race loses a few fps on
a hot tablet with it on, so re-measure with a rider.

## HUD agreement

The rider's watts appear only in the ride panel, where the pace is the band's tick. The widget has
the fence, the round, the pips and a chip in words. The intro card's numbers all come from the
segment's params.

## Calls for the rider to check (my calls)

1. **Pace share.** 45 / 55 / 65% of FTP is a guess at a comfortable spin with standing efforts.
2. **"Too early" also covers never sitting.** A rider left standing is warned at the first beat.
3. **Stand-to-detect time.** The acceptance items to measure it on the bike, and to check a seated
   rider never triggers a jump, are **not done**: they need a person on the bike. The window assumes
   the detector's configured 0.5 s.
4. **No bike in view.** The rider's direction (view from the saddle) overrides the issue's "in front
   of the bike".
5. **A fence crossed without pedalling** breaks the clear round but isn't a fault.

## GodotPrompter patterns

| System | Skill | Picked | Rejected, and why |
| --- | --- | --- | --- |
| Rules | `state-machine` | Enum phases and zones in a `RefCounted` | Node-based FSM: few states, and the rules run headless |
| World | `3d-essentials` | Baked vertex-colour mesh, hand lit, in a SubViewport | Real lights and imported models: the tablet's fill rate; licensing |
| Course | `3d-essentials` | A closed stadium loop by arc length, in `GateCourse` | `Curve3D` and `PathFollow3D`: a node for maths two arcs and two lines cover, and the rules need only its length |
| HUD | `hud-system` | One slim widget in the kit's top-centre slot; pips drawn only on change | A second panel for pace: the ride panel already has the band |
| Audio | `audio-system` | Rendered stems and one-shots through `AudioDirector`; one stride sample per stride | A looped gallop with `pitch_scale`: pitch would follow pace, not the beat |
| Tests | `godot-testing` | GdUnit logic and scene suites, with a rider model of the detector's lags | Testing the window with raw booleans only: it wouldn't prove the lag sums |

## Roles and gates

`game-designer` (this file's fantasy and loop), `art-director` with `ad-visual` (see ART_BIBLE §10:
the horse was reshaped twice), `audio-director` and `sound-designer` (AUDIO_POLISH.md), `ux-designer`
(UI_POLISH.md), `lp-code-review` and `ql-test-coverage` (the lag model in the tests).
