# Watt Lane: audio polish

> **Status:** done on `games-78-watt-lane` (2026-11-02), audio-director and sound-designer passes.

## What changed

**The theme: "Night Current" → "Live Wire"** (`games/tools/music/songs/watt_lane.py`).

| | Night Current (slice) | Live Wire (rework) | Safe Cracker's Night Shift (reference) |
| --- | --- | --- | --- |
| Genre | generic synthwave | bright dream-pop electronica | swung spy jazz |
| Tempo, key | 104, F minor | 112, Eb major | 120, C harmonic minor |
| Harmony | triads | major and minor sevenths, sus chords | sevenths, m7b5, 7b9 |
| Form | intro, verse, chorus, bridge, chorus | the same, the bridge half-time then a build, the last chorus with a harmony line and a countermelody | intro, verse, chorus, bridge |
| Signature sounds | pad, pluck, analog lead, supersaw | **glockenspiel hook over a flute**, eighth-note piano, a plucked arpeggio, sleigh-bell sparkle, octave bass; supersaw and brass stabs in the chorus; strings in the bridge | vibes, Rhodes, muted trumpet, sax, spy guitar |
| Parts a section | 3-4 | 4-6 | 3-4 |

Why: the slice's synthwave was genre-generic (triads, a pad and a saw lead) and sat close to
Cadence Karaoke's synth-funk. Live Wire has its own signature (the glockenspiel and flute, the
piano's eighths) and a warmer harmony that suits the abstract lit lane.

**Effects** re-keyed to Eb major: the jump chime (glockenspiel Bb-Eb over a swell), the 3-2-1
tick (a bell on Eb), the lane shift (a rising shimmer and a soft thump), caught (an Eb major
arpeggio), missed, the off-lane buzz and the streak step. **The hum** moved from 87 Hz (F) to
78 Hz (Eb).

**Adaptive music:** the bed always; the harmony from intensity 0.45 (near the lane); the lead at
0.9 (in it). Steps duck the music under the chime (`GameMix.duck_for_moment`).

## The mix against a reference

`tests/render_game_audio.gd` (60-70 s, a scripted rider) and `tools/music/analyze_mix.py`:

| | Watt Lane | Safe Cracker |
| --- | --- | --- |
| Mix, integrated | -15.4 LUFS | -16.6 LUFS |
| Music | -18.3 LUFS | -17.8 LUFS |
| Effects | -14.3 LUFS | -12.9 LUFS |
| Peak before the limiter | -1.4 dBFS, no clipping | -1.6 dBFS, no clipping |
| Duck | 92 of 799 samples, deepest -10 dB | 72 of 799, deepest -10 dB |
| Effect cut-through (best band) | 4.8 to 17.5 dB (count_tick lowest) | 8.0 to 16.4 dB |

Every effect cuts through the music. The count ticks were masked in the slice (-1.6 dB); a
bell-pinged tick at -8 dB now sits at +4.8 dB, quieter on purpose than the chime it follows.

## Rendering

```sh
python3 -m venv ~/openride-scratch-backup/venv && ~/openride-scratch-backup/venv/bin/pip install numpy scipy soundfile
cd games/tools/music && ~/openride-scratch-backup/venv/bin/python render_music.py watt_lane
```

77.1 s (loop from 8.57 s), -15.1 LUFS, three stems 1.5 MB.
