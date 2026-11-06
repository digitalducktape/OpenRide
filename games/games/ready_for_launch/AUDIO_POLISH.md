# Ready for Launch: audio polish

From the audio review of 2026-11-06 (audio-director and sound-designer passes). References:
`songs/safe_cracker.py`, `songs/tug_of_war.py`, and an offline render of Tug of War.

No speakers were involved: the checks are `tests/render_game_audio.gd` and
`tools/music/analyze_mix.py`, so **the rider's ear is still the real test of the theme.**

```sh
$GODOT_BIN --headless --fixed-fps 60 --path games -s res://tests/render_game_audio.gd -- --game=ready_for_launch --out=DIR --seconds=92
python games/tools/music/analyze_mix.py DIR --limit
```

## The theme: "First Light"

| | |
| --- | --- |
| Genre | Orchestral-synth, apart from the family |
| Tempo, key | 104 bpm, D minor, lifting to D major in the chorus |
| Signature | Low string ostinato and timpani figure (`arrange.py`: new `cinematic` groove and `ostinato` comp), horn line, soaring brass, bells |
| Form | Intro, verse, chorus, second verse, bridge on a riser, final chorus (40-bar loop) |
| Variation | The second verse moves the line to strings with a bell counter line; the final chorus goes to supersaw with harmony and brass under it |
| Parts at the fullest | 7 |
| Stems | Bed always; harmony with fuel flowing and from the count on; lead on the push |

## The mix, against Tug of War

| Measure | First cut | Now | Tug of War |
| --- | --- | --- | --- |
| Mix, integrated | -17.1 LUFS | -17.2 LUFS | -17.4 LUFS |
| Music | -20.6 LUFS | -20.6 LUFS | -20.3 LUFS |
| Effects | -17.0 LUFS | -17.1 LUFS | -17.9 LUFS |
| Peak before the limiter | +0.5 dBFS | -1.3 dBFS | -0.2 dBFS |
| Clipped samples | 6 | 0 | 0 |
| The big moment's cut-through (best / broadband) | ignition 25.8 / 21.3 dB | 23.5 / 19.0 dB | |
| Deepest duck | -10 dB | -10 dB | |

## What changed

1. **Ignition and liftoff clipped together.** They land within a moment of each other: -1 dB and
   -3 dB, which cleared it. The engine came down 2 dB as well.
2. **The countdown is tones only**, a formant-shaped tone that rises a semitone a second, brighter
   with a bell on the last three. No speech.
3. **Every warning ducks the music** (`duck_for_moment`), and ignition takes the sting's duck.
4. **Names are `rfl_*`**, so another game's sounds can't replace ours.
5. `render_game_audio.gd` knows this game: its sounds and a scripted rider through a launch.

## Left

- The theme needs a human listen. A render can't say whether the line is memorable.
- The Moon's fanfare and touchdown aren't in the scripted render (its rider stops at orbit), so
  they're checked for level only by their peak, not against the music.
- The hiss and engine loops are checked for level, not for how the loop point sounds.
