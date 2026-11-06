# Game music renderer (#43, #55)

Renders the games' music and effects offline to OGG Vorbis, and writes the index each game
reads. Everything is original and synthesised here: no samples, no soundfonts, no third-party
material. Generalised from Kart Race's renderer (#43).

```
python3 -m venv /tmp/music && /tmp/music/bin/pip install numpy scipy soundfile
cd games/tools/music
/tmp/music/bin/python render_music.py dodge_ball      # or tug_of_war, safe_cracker, demo, cadence_karaoke, cues
```

`--only music` or `--only sfx` renders one half; `--wav DIR` also writes float WAVs (and, for
Cadence Karaoke, previews at 70, 100 and 130 bpm). The output is deterministic. Re-run Godot's
import afterwards. A theme takes 4-8 s to render.

## Files

- `songs/<game>.py`: one module per game.
  - `SONG`: the theme (chords, melodies, form, parts per section, drum and bass styles).
  - `SFX`: `{name: function(rng)}`, the game's effects, in the theme's key.
  - `PREFIX`: the index is `games/games/<game>/<PREFIX>Music.gd`.
  - Optional in `SONG`: `extra(song, bar0, bars, name, role, rng)`, the song's own parts for a
    section, called after its stock ones (Gate Crasher's clip-clop and pickups).
  - Cadence Karaoke has `SEQ` (a score for the sequencer) instead of `SONG`; `cues.py` has only
    effects, written to `audio/cues/` with the index `audio/CueSounds.gd`.
  - `hub.py` is the Games hub's theme, not a game's: its `DIR`, `INDEX` and `CLASS_NAME` put the
    stems in `hub/music/` and the index in `hub/HubMusicIndex.gd`
    (`render_music.py hub`).
- `render_music.py`: renders a song module.
- `compose.py`: theory helpers and `Song`, which schedules notes onto buses and mixes them into
  stems (`bed`, `harmony`, `lead`) that sum to the mastered mix.
- `arrange.py`: drum grooves (funk, drive, disco, pop, stomp, spy, house), bass lines (slap,
  picked, octave, synth, walking, root-fifth, sub), comping and lines.
- `instruments.py`: drums, bass, guitars, keys, vibes, accordion, horns, whistle, synths.
- `dsp.py`: oscillators, filters, chorus, delay, convolution reverb, compression, a limiter,
  BS.1770 loudness.
- `sfx.py`: building blocks for effects (whooshes, thuds, zaps, creaks, splashes, crowds,
  fanfares).
- `sequencer.py`: songs that play at any tempo (Cadence Karaoke): a sample bank and a score,
  laid out at runtime by `res://audio/SongSequencer.gd`. See docs/GAMES.md, "Rendered music and
  effects".
- `analyze_mix.py`: analyses a game's offline render from `tests/render_game_audio.gd`.

## Form and loops

A theme is an intro (played once) and a body (verse, chorus, bridge, chorus) that loops. The
body is rendered twice and the file keeps the intro plus the second pass, which starts with the
first pass's tails; both passes use the same seeds, so the loop point is seamless. `LOOP_FROM`
in the index is where the body starts.
