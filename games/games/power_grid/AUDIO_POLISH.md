# Power Grid: audio polish

**Nobody has listened to this.** The rider heard the first theme, "Lamplighter", and said it "sounds very
basic". "Evening Current" replaces it, but every check below is a measurement, not an ear. The rider's
ear is the real test.

Run through the team-audio pipeline with one agent wearing the audio-director and sound-designer
roles (no subagents, and no sound bible exists in this repo). References: `songs/safe_cracker.py`
("Night Shift") and `songs/tug_of_war.py` ("Heave Together"), the rider's favourites.

```sh
$GODOT_BIN --headless --fixed-fps 60 --path games -s res://tests/render_game_audio.gd -- --game=power_grid --out=DIR --seconds=90
python games/tools/music/analyze_mix.py DIR --limit
```

## Why the references are rich, and Lamplighter wasn't

| What the rider likes | Night Shift, Heave Together | Lamplighter | Evening Current |
| --- | --- | --- | --- |
| Genre commitment | Spy jazz, stomp-clap shanty: you name it in two bars | "Calm folk-soul": no identity | Bossa nova: guitar pattern, two-feel bass, clave |
| Signature instruments | Spy guitar and sax; whistle and accordion | A filtered-saw muted horn | Nylon guitar, flugelhorn, flute, voices, strings |
| A singable hook | Short motifs, repeated and answered | Long stepwise notes, nothing to hum | Three notes over the bar, said three times, climbing |
| Rhythm | Swung ride; stomps and claps | Slow brushes, 92 bpm | Syncopated guitar against a two-bar clave |
| Section contrast | Chorus changes the lead and the comp | Little changed | Each section has its own lead, comp and drums |
| Counter-melody | Horn answers, whistle over brass | One late counter line | Flute answers in the verse's rests; thirds and a counter line at the end |
| Harmonic movement | Chromatic lines, a real bridge | Diatonic, four-chord feel | Ninths and thirteenths, a backdoor turn, a bridge a third away in E |
| Loop | 50-60 s | 83 s | 58 s |

## The theme: "Evening Current"

| | |
| --- | --- |
| Genre | Bossa nova, new to the family, and relaxed at any effort |
| Tempo, key | 132 bpm (felt in two), A-flat major, so the effects stay in key |
| Form | Intro, verse, chorus, bridge, last chorus: 32-bar loop, 58 s |
| Intro | The guitar alone, then shaker, then clave, with a flute tag of the refrain |
| Verse | Flugelhorn hook, flute answering in the rests, Rhodes in the gaps, brushes |
| Chorus | Flugelhorn and flute in octaves, wordless voices, strings, congas, ride, tambourine |
| Bridge | Down to E: Rhodes solo over guitar, vibes and clave alone, then strings and a riser climb back |
| Last chorus | Everything, the flute in thirds, strings an octave up, muted horns, a vibes counter line |
| Stems | As before: the bed always, the harmony while meeting demand, the lead with the whole town lit |

**New in `instruments.py`:** `nylon`, `upright`, `flugel` (additive, brightness swelling with the breath),
`silver_flute`, `string_section` (six detuned players), `oohs` (formant voices). **New in `arrange.py`:**
the `bossa` drum and bass styles and comp patterns. They replace Lamplighter's `porch` groove.

## Checks

- **Harmony:** a script walked every melody against its chords: no strong or long note a half step
  above a chord tone.
- **Sections** (per-stem RMS): the first render had the verse's lead level with the harmony and the
  bridge no quieter. Now the verse's lead sits 5.4 dB over the harmony (Night Shift 8.2, Heave
  Together 6.0), and the bridge drops 1.4 dB with a much darker spectrum.

| Measure | Evening Current | Tug of War |
| --- | --- | --- |
| Mix, integrated | -16.9 LUFS | -17.7 LUFS |
| Music | -19.4 LUFS (harmony up 87% of the time, lead 61%) | -20.6 LUFS (41%, 20%) |
| Effects | -18.1 LUFS | -18.1 LUFS |
| Clipped samples | 0 | 0 |
| Strike's cut-through (best / broadband) | 20.1 / 12.8 dB | |
| A switch-on's cut-through | 23.1 / 17.0 dB | |

Mix changes: no kick-keyed pump (bossa doesn't pump); shaker and ride raised for air; music down 1.5
dB, since a rider here spends most of the time with every stem up. The stems shrank to 1.25 MB.

## Effects

Kept: they measure well and the rider only named the music. They stay in key. The flicker's crackle
went up 3 dB.

## Left

- **It needs a human listen**: whether the hook is catchy, and whether `flugel`, `oohs` and
  `string_section` sound real or synthetic. No render can say.
- The top two bands sit 3-4 dB under Tug of War's. Bossa is darker, but it may want more air.
- The crackle is still under the music broadband (-2.6 dB). The lights' flicker carries that warning.
- The hum's and rain's loop points are checked for level, not by ear.
