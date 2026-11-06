"""Renders a game's music and effects (#55; the Kart Race renderer, #43, generalised) to OGG
Vorbis, and writes the index the game reads.

  python3 -m venv /tmp/venv && /tmp/venv/bin/pip install numpy scipy soundfile
  /tmp/venv/bin/python games/tools/music/render_music.py dodge_ball [--wav DIR] [--only music|sfx]

Each game is a module in songs/ with:
- SONG: the theme. Its form is a head (an intro, played once) and a body that loops. It renders
  as three stems the game gates by intensity: `bed` (drums, bass, effects), `harmony` (guitars,
  keys, brass, pads) and `lead` (the melody and its harmony, mono).
- SFX: {name: function(rng) -> mono audio}, the game's effects (and stings), each written as
  its own OGG.
- PREFIX: the index script's name (`<Prefix>Music.gd`, next to the game's scene).
- Optional, for music that isn't a game's (the Games hub): DIR, the folder under games/ the
  music and index go in (default `games/<game>`); INDEX, the index's file name (default
  `<Prefix>Music.gd`); CLASS_NAME, a `class_name` for the index.

Deterministic (seeded). Everything is synthesised by this code; no samples, no third-party
material. See README.md here.
"""
import argparse
import importlib
import os
import sys
import time

import numpy as np
import soundfile as sf

sys.path.insert(0, os.path.dirname(__file__))
import dsp  # noqa: E402
from arrange import drums, bass, comp, line, counter  # noqa: E402
import instruments as ins  # noqa: E402
from compose import Song, STEMS, parse_bars, transpose_sym, pc  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
MUSIC_LUFS = -15.0  # the full mix's loudness; the Music bus (0.8) puts it near -17 in game
SFX_PEAK_DB = -4.0  # each game effect's peak (the game sets its level per play), leaving headroom for overlaps
CUE_PEAK_DB = -3.0  # the framework's cues: few, and they must read (Cues ducks the music under them)
## libsndfile's Vorbis compression level per stem (0 best .. 1 smallest).
OGG_LEVEL = {"bed": 0.9, "harmony": 0.92, "lead": 0.92, "sfx": 0.75}

## Each bus's RMS (dB) in the mix, before the master: the balance (see Song.mix).
TARGETS = {"kick": -19, "snare": -21, "hats": -29, "perc": -31, "cym": -32, "bass": -19, "gtr": -24,
           "gtr2": -27, "keys": -24, "brass": -25, "lead": -19.5, "lead2": -25, "pad": -27, "fx": -33}
SENDS = {"snare": {"room": 0.5, "verb": 0.12}, "perc": {"room": 0.3}, "cym": {"verb": 0.1},
         "gtr": {"verb": 0.12, "room": 0.2}, "gtr2": {"room": 0.2}, "keys": {"verb": 0.25},
         "brass": {"verb": 0.25}, "lead": {"verb": 0.22, "delay": 0.18}, "lead2": {"verb": 0.3, "delay": 0.1},
         "pad": {"verb": 0.4}, "fx": {"verb": 0.4}}
SIDECHAIN = {"pad": 0.6, "bass": 0.25, "keys": 0.3, "gtr2": 0.3, "lead2": 0.2}
BASE = {"verse2": "verse", "chorus2": "chorus", "chorus3": "chorus", "bridge2": "bridge", "outro": "intro"}


def render_song(spec, seed):
    """The song as {stem: stereo audio} (the head once, then one pass of the body) and the
    second the body starts at. The body renders twice and the file keeps the second pass, which
    starts with the first pass's tails, so the loop point is seamless."""
    key_pc = pc(spec["key"])
    head, body = spec["form"]
    plan = head + body + body
    total = sum(b for _, b in plan)
    song = Song(spec["bpm"], total, seed, swing=spec.get("swing", 0.0))
    mel = {k: parse_bars(v) for k, v in spec["melody"].items()}
    chords = spec["chords"]
    bar0 = 0
    for si, (name, n) in enumerate(plan):
        # Re-seed per section, the same for both passes of the body: the passes are identical.
        k = si if si < len(head) else len(head) + (si - len(head)) % len(body)
        song.rng = np.random.default_rng(seed * 100 + k)
        rng = np.random.default_rng(seed * 100 + 50 + k)
        base = BASE.get(name, name)
        role = spec.get("roles", {}).get(name, base)
        ch = (chords.get(name) or chords[base])[:n]
        drums(song, bar0, n, spec["drums"], role)
        bass(song, bar0, ch, spec["bass"], role, rng)
        for p in spec["parts"].get(name, []):
            kind = p[0]
            if kind == "comp" and p[2] > 0:
                comp(song, bar0, ch, p[1], role, rng, p[2])
            elif kind == "lead":
                harm = (key_pc, spec["scale"]) if len(p) > 6 and p[6] else None
                line(song, bar0, mel[p[1]][:n], p[2], p[3], rng, shift=p[4], vel=p[5], harmony=harm)
            elif kind == "counter":
                line(song, bar0, counter(ch, *p[4:6]) if len(p) > 4 else counter(ch), p[1], p[2], rng, vel=p[3])
        if "extra" in spec:  # a song's own parts for this section: extra(song, bar0, bars, name, role, rng)
            spec["extra"](song, bar0, n, name, role, rng)
        if name in spec.get("risers", ("intro", "bridge")):
            song.put("fx", (bar0 + n - 1) * 4, ins.riser(4 * song.spb, rng), human=0)
        bar0 += n
    stems = song.mix({**TARGETS, **spec.get("levels", {})}, SENDS, {**SIDECHAIN, **spec.get("sidechain", {})},
                     MUSIC_LUFS + spec.get("lufs_offset", 0.0), spec.get("verb_sec", 1.7), STEMS)
    head_n = song.at(sum(b for _, b in head) * 4)
    body_n = song.at(sum(b for _, b in body) * 4)
    out = {k: np.concatenate([v[:, :head_n], v[:, head_n + body_n: head_n + 2 * body_n]], axis=1) for k, v in stems.items()}
    return out, head_n / dsp.SR


def write_ogg(path, audio, level, wav_dir=None):
    data = audio.T if audio.ndim == 2 else audio
    sf.write(path, data.astype(np.float32), dsp.SR, format="OGG", subtype="VORBIS", compression_level=level)
    if wav_dir:
        sf.write(os.path.join(wav_dir, os.path.basename(path)[:-4] + ".wav"), data.astype(np.float32), dsp.SR, subtype="FLOAT")
    return os.path.getsize(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("game")
    ap.add_argument("--wav", default="")
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    mod = importlib.import_module("songs." + a.game)
    rel_dir = getattr(mod, "DIR", f"games/{a.game}")
    game_dir = os.path.join(ROOT, rel_dir)
    index_path = os.path.join(game_dir, getattr(mod, "INDEX", mod.PREFIX + "Music.gd"))
    music_dir = os.path.join(game_dir, "music")
    spec = mod.SONG
    index = {"stems": {}, "sounds": {}, "loop_from": 0.0}
    if spec is not None and a.only in ("", "music"):
        name = spec["file"]
        os.makedirs(music_dir, exist_ok=True)
        t0 = time.time()
        stems, loop_from = render_song(spec, spec.get("seed", 1))
        full = sum(stems.values())
        total = 0
        for stem, audio in stems.items():
            x = audio.mean(axis=0) if stem == "lead" else audio
            total += write_ogg(os.path.join(music_dir, f"{name}_{stem}.ogg"), x, OGG_LEVEL[stem], a.wav)
            index["stems"][stem] = f"res://{rel_dir}/music/{name}_{stem}.ogg"
        if a.wav:
            sf.write(os.path.join(a.wav, f"{name}_full.wav"), full.T.astype(np.float32), dsp.SR, subtype="FLOAT")
        print(f"  {name}: {full.shape[1] / dsp.SR:.1f} s (loop from {loop_from:.2f}), {dsp.lufs(full):.1f} LUFS, "
              f"TP {dsp.true_peak_db(full):.1f} dBTP, stems {total / 1024:.0f} KB, rendered in {time.time() - t0:.1f} s")
        index["loop_from"] = loop_from
    if a.only in ("", "sfx"):
        rel = getattr(mod, "OUT", f"games/{a.game}/music/sfx")
        sdir = os.path.join(ROOT, rel)
        os.makedirs(sdir, exist_ok=True)
        total = 0
        for i, (sname, fn) in enumerate(mod.SFX.items()):
            x = np.asarray(fn(np.random.default_rng(1000 + i)), dtype=float)
            if x.ndim == 2:
                x = x.mean(axis=0)
            x = dsp.hp(x, 40)
            x = x * 10 ** ((CUE_PEAK_DB if hasattr(mod, "INDEX") else SFX_PEAK_DB) / 20) / (np.abs(x).max() + 1e-9)
            x = dsp.fade_out(x, 6)
            total += write_ogg(os.path.join(sdir, sname + ".ogg"), x, OGG_LEVEL["sfx"], a.wav)
            index["sounds"][sname] = f"res://{rel}/{sname}.ogg"
        print(f"  sfx: {len(mod.SFX)} sounds, {total / 1024:.0f} KB")
    if hasattr(mod, "SEQ") and a.only in ("", "music"):
        import sequencer
        t0 = time.time()
        os.makedirs(music_dir, exist_ok=True)
        score = mod.SEQ()
        bank, spans, tracks = sequencer.build(score)
        gains = sequencer.balance(score, bank, spans, tracks, MUSIC_LUFS)
        size = sequencer.write(score, mod.FILE, bank, spans, tracks, gains, music_dir, f"res://games/{a.game}/music",
                               os.path.join(game_dir, mod.PREFIX + "Music.gd"), mod.TITLE, pc(mod.KEY), a.wav or None)
        print(f"  {mod.FILE}: {len(spans)} samples, bank {bank.shape[1] / dsp.SR:.1f} s, {size / 1024:.0f} KB, "
              f"{sum(len(v) for v in tracks.values())} notes on {len(tracks)} tracks, rendered in {time.time() - t0:.1f} s")
    if not a.only and hasattr(mod, "SEQ"):
        append_sounds(os.path.join(game_dir, mod.PREFIX + "Music.gd"), index)
    if not a.only and spec is None and hasattr(mod, "INDEX"):
        write_cue_index(os.path.join(ROOT, mod.INDEX), a.game, index)
    elif not a.only and spec is not None:
        write_index(index_path, a.game, spec, index, getattr(mod, "CLASS_NAME", ""))
    top = os.path.join(ROOT, mod.OUT) if hasattr(mod, "OUT") else music_dir
    size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(top) for f in fs if f.endswith(".ogg"))
    print(f"{a.game}: music and effects {size / 1024:.0f} KB")


def append_sounds(path, index):
    with open(path) as f:
        text = f.read()
    lines = ["const SOUNDS := {"] + [f"\t\"{k}\": \"{p}\"," for k, p in index["sounds"].items()] + ["}", ""]
    with open(path, "w") as f:
        f.write(text + "\n".join(lines))


def write_cue_index(path, game, index):
    lines = ["extends RefCounted",
             "## The framework's cues, rendered (#55). Written by games/tools/music/render_music.py from",
             f"## songs/{game}.py; don't edit by hand. Cues.gd registers them under these names.",
             "", "const SOUNDS := {"]
    for sname, p in index["sounds"].items():
        lines.append(f"\t\"{sname}\": \"{p}\",")
    lines += ["}", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))


def write_index(path, game, spec, index, class_name=""):
    lines = ([f"class_name {class_name}"] if class_name else []) + ["extends RefCounted",
             f"## {spec['title']}: the game's rendered music and effects (#55). Written by",
             f"## games/tools/music/render_music.py from songs/{game}.py; don't edit by hand.",
             "",
             f"const TITLE := \"{spec['title']}\"",
             f"const BPM := {float(spec['bpm']):.1f}",
             f"const KEY := {pc(spec['key'])}  ## the key's pitch class (0 = C)",
             f"const LOOP_FROM := {index['loop_from']:.4f}  ## seconds: the intro plays once, the rest loops",
             "## The stems: the bed always plays; harmony and lead are gated by the game.",
             "const STEM_FILES := {"]
    for stem, p in index["stems"].items():
        lines.append(f"\t\"{stem}\": \"{p}\",")
    lines += ["}", "const SOUNDS := {"]
    for sname, p in index["sounds"].items():
        lines.append(f"\t\"{sname}\": \"{p}\",")
    lines += ["}", ""]
    with open(path, "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    main()
