# Keepy Uppy: audio polish

From the audio review of 2026-11-02 to 11-04 (audio-director and sound-designer passes), after the
rider's note that the music wasn't at the level of the other games. References:
`tools/music/songs/safe_cracker.py`, `tug_of_war.py`, and an offline render of Tug of War.

No speakers were involved: the checks are `tests/render_game_audio.gd` and
`tools/music/analyze_mix.py`, so **the rider's ear is still the real test of the theme.**

```sh
$GODOT_BIN --headless --fixed-fps 60 --path games -s res://tests/render_game_audio.gd -- --game=keepy_uppy --out=DIR --seconds=80
python games/tools/music/analyze_mix.py DIR --limit
```

## The theme: "Meadow Breeze" replaced by "Updraft"

| | Before ("Meadow Breeze") | After ("Updraft") |
| --- | --- | --- |
| Genre | Light acoustic pop | Summer indie-pop |
| Tempo, key | 112 bpm, G major | 118 bpm, B-flat major |
| Signature | Whistle and flute over strums: too near Tug's shanty | **Glockenspiel hook**, eighth-note piano, soft strings under the bells |
| Bass | Root-fifth | Bouncy octaves |
| Form | Intro, verse, chorus, bridge, chorus (32-bar loop) | Intro, verse, chorus, **second verse**, bridge, final chorus (40-bar loop, about 81 s) |
| Variation | The second chorus only | The second verse adds a string counter line and an arpeggio; the bridge drops to piano and builds on a riser; the final chorus adds harmony and a plucked counter line |
| Parts in the fullest section | 5 | 6 |

Stems as before: the bed always, the harmony from the mid band, the lead in the high band.
The genre sits apart from the family: Dodge's electro-rock, Tug's shanty, Safe's spy jazz,
Cadence's synth-funk, the demo's house.

## The mix, against Tug of War

| Measure | Keepy before | Keepy after | Tug of War |
| --- | --- | --- | --- |
| Mix, integrated | -17.0 LUFS | -16.8 LUFS | -17.5 LUFS |
| Music | -20.5 LUFS | -21.0 LUFS | -20.2 LUFS |
| Effects | -19.2 LUFS | -17.9 LUFS | -18.2 LUFS |
| Peak before the limiter | -1.6 dBFS | -1.9 dBFS | -0.2 dBFS |
| Clipped samples | 0 | 0 | 0 |
| The big moment's cut-through (best band / broadband) | pop 10.2 / 8.6 dB | pop 23.7 / 14.0 dB | lose sting 24.7 / 10.3 dB |

The weather isn't seeded in the render, so a run's events differ, and the warnings' figures move
between runs. Across the last three renders: rain warning 3-12 dB best band, gust 3-15, bird
flutter 6-15 (the low end includes the quiet "birds leave" flutter).

## What changed in the effects and the mix

1. **The pop was too small for the game's one penalty.** It's now a crack, a slap, a low thump and
   a falling three-note "aww" on the glockenspiel, at +1 dB.
2. **The warnings hid under the music.** Every warning now ducks it (`GameMix.duck_for_moment`), as
   the downdraft's already did. Each is also clearer: the downdraft has two falling low tones, the
   gust a flap of cloth at its peak, the rain cloud the first drops tapping on the crate, the bird
   a third chirp.
3. **The fan's hum sat on the music.** It's down 5 dB at full lift (-14 dB) and now tuned to the
   new key.
4. **Effects re-keyed** to B-flat (the pop, the birds shaken, the new balloon, the chime).
5. **Names are `keepy_*`**, so another game's "pop" can't replace ours.

`render_game_audio.gd` now knows Keepy Uppy (its sounds, a scripted rider through every band and
a pop), and copes with a game's own player being freed with its scene.

## Left

- The theme needs a human listen. A render can't say whether the hook is catchy.
- The rain's loop and the fan's hum are checked for level, not for how the loop point sounds.
