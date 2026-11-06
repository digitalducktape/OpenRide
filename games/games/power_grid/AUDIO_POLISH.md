# Power Grid: audio polish

From the audio review (audio-director and sound-designer passes). References:
`tools/music/songs/safe_cracker.py`, `tug_of_war.py`, and an offline render of Keepy Uppy.

No speakers were involved: the checks are `tests/render_game_audio.gd` and
`tools/music/analyze_mix.py`, so **the rider's ear is still the real test of the theme.**

```sh
$GODOT_BIN --headless --fixed-fps 60 --path games -s res://tests/render_game_audio.gd -- --game=power_grid --out=DIR --seconds=90
python games/tools/music/analyze_mix.py DIR --limit
```

## The theme: "Lamplighter"

| | |
| --- | --- |
| Genre | Warm porch folk-soul, the slowest in the family |
| Tempo, key | 92 bpm lightly swung, A-flat major |
| Signature | Muted horn verse, flute doubled on vibes in the chorus, Rhodes and acoustic strum |
| Drums | A new `porch` groove in `arrange.py`: brushes, cross-stick, soft kick, shaker, no tom rolls |
| Form | Intro, verse, chorus, bridge (vibes and piano), last chorus: 32-bar loop, about 83 s |
| Variation | The last chorus adds the flute in thirds and an answering horn |
| Stems | The bed always, the harmony while meeting demand, the lead with the whole town lit |

Compared with Safe Cracker (three sections) and Tug of War (four): the same form depth, 5-6 parts in
the fullest section, fills and a riser into the last chorus, softened for a recovery ride.

## The mix

| Measure | Power Grid | Keepy Uppy |
| --- | --- | --- |
| Mix, integrated | -17.3 LUFS | -17.3 LUFS |
| Music | -20.2 LUFS | -20.8 LUFS |
| Effects | -18.2 LUFS | -19.0 LUFS |
| Clipped samples | 0 | 0 |
| The big moment's cut-through (best / broadband) | strike 13.9 / 12.0 dB, switch-on 21.3 / 12.1 dB | pop 22.5 / 16.1 dB |

## What changed

1. **The music was 2.7 dB too hot** for a calm game (-18.1 LUFS): `lufs_offset` -2 brought it to -20.2.
2. **The warning thunder sat low** (7.0 dB best band): up 2 dB, now 11.0.
3. **The crackle was under the music** (-0.8 dB broadband): up 4 dB, now +1.4.
4. **Drum builds were too loud** for the style: the `porch` groove has its own fills and bridge.
5. **Every warning and moment ducks the music** (`GameMix`). Effects are `grid_*`, in the key.

The dynamo's hum follows the supply in pitch and level; the rain loop follows the storm.

## Left

- The theme needs a human listen; a render can't say whether the tune is good.
- At 1.8 MB the stems are over the usual 0.9-1.4 MB, because the slow tempo makes a long loop.
- The hum's and rain's loop points are checked for level, not by ear.
