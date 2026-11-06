"""Power Grid (#81, the music rework): "Evening Current", a bossa nova at 132 bpm in A-flat major,
for a valley town coming on at dusk. Committed to the genre: a nylon guitar's syncopated two-bar
pattern with its thumb on the bass, an upright in the dotted two-feel, a cross-stick clave, shaker
and brushes. A flugelhorn sings the verse's three-note hook, answered by the flute in the gaps; the
chorus opens with flugelhorn and flute together over wordless voices and a small string section,
with congas and a ride. The bridge drops a major third to E for a Rhodes solo over guitar and
clave alone, then strings and a riser climb back for a last chorus with the flute in thirds and a
horn answering. Nothing in the family sounds like it: no spy jazz (Safe), shanty (Tug), boogie (The
Pull), band organ (Balloon Pump) or indie-pop (Keepy Uppy), and bossa stays relaxed at any effort.

The harmony comes in while the rider meets demand, the lead with the whole town lit.

Effects, in the key: the dynamo's hum (a seamless loop the game pitches to the supply), four
district switch-on chords climbing through the key, the flicker's crackle, the power-down of a
district going dark, its relight, far thunder and the storm's rain (a seamless loop), the strike, the
repair's rising chord, the crew's quiet fix, the full town's cheer and fireworks, and the church
bell that opens a new evening. Written for this repo; no existing tune is quoted."""
import numpy as np

import dsp
import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, hp, bp

PREFIX = "Grid"

SONG = dict(
    file="evening_current", title="Evening Current", bpm=132, key="Ab", scale=[0, 2, 4, 5, 7, 9, 11], seed=181,
    drums="bossa", bass="bossa", verb_sec=1.9,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Abmaj9", "Abmaj9", "Dbmaj9", "Bbm7 Eb13"],
        verse=["Abmaj9", "Bbm9 Eb13", "Abmaj9", "Ebm7 Ab13", "Dbmaj9", "Dbm7 Gb13", "Cm7 F7b9", "Bbm7 Eb13"],
        chorus=["Dbmaj9", "Eb13", "Cm7", "F7b9", "Bbm9", "Eb13", "Abmaj9", "Ebm7 Ab13"],
        bridge=["Emaj9", "C#m7", "F#m9", "B13", "Emaj9", "Am9 D13", "Bbm9", "Ebm7 Ab13"],
    ),
    melody=dict(
        intro="r:4 | r:4 | r:0.5 Ab5:0.5 C6:1.5 Bb5:0.5 Ab5:1 | F5:1.5 G5:1.5 r:1",
        # The hook: a pickup and three notes leaning over the bar (C, E-flat, F), said three times,
        # a step higher each time, and a chromatic drop in bar 6 to turn the corner.
        verse="r:0.5 C5:0.5 Eb5:0.5 F5:1 Eb5:0.5 C5:1 | Db5:0.5 Eb5:0.5 Bb4:1 r:0.5 G4:0.5 Bb4:1 |"
              " r:0.5 C5:0.5 Eb5:0.5 Ab5:1 G5:0.5 Eb5:1 | Gb5:0.5 F5:0.5 Eb5:1 r:0.5 C5:0.5 Eb5:1 |"
              " r:0.5 F5:0.5 Ab5:0.5 C6:1 Bb5:0.5 Ab5:1 | Ab5:1 Fb5:1 Eb5:1 Bb4:1 |"
              " G5:0.5 Eb5:0.5 C5:1 A5:1 Gb5:1 | F5:1.5 Db5:0.5 C5:1 Bb4:1",
        # The flute answers in the rests.
        verse_fill="r:4 | r:2.5 Eb6:0.5 C6:0.5 Bb5:0.5 | r:4 | r:2.5 Bb5:0.5 Ab5:0.5 Gb5:0.5 | r:4 | r:3 Db6:0.5 Bb5:0.5 |"
                   " r:4 | r:3 Eb6:0.5 Db6:0.5",
        # The refrain: the hook's rhythm stretched, up a sixth, ending on a held tonic.
        chorus="r:0.5 Ab5:0.5 C6:1.5 Bb5:0.5 Ab5:1 | Bb5:1.5 G5:1.5 Eb5:1 | r:0.5 G5:0.5 C6:1.5 Bb5:0.5 G5:1 |"
               " A5:1.5 C6:0.5 Eb6:2 | Db6:1.5 C6:0.5 Bb5:1 F5:1 | G5:1 Bb5:1 Eb6:1.5 Db6:0.5 |"
               " C6:2.5 Ab5:0.5 Eb5:1 | F5:0.5 G5:0.5 Ab5:1 r:2",
        # The strings' long line over the refrain.
        chorus_str="F5:4 | G5:4 | Eb5:4 | Eb5:4 | Db5:4 | Db5:2 Eb5:2 | C5:4 | Db5:2 C5:2",
        bridge="G#5:1.5 B5:0.5 E5:2 | G#5:1 E5:1 C#5:2 | A5:1.5 C#6:0.5 G#5:2 | F#5:1 D#5:1 A5:2 |"
               " B5:1.5 G#5:0.5 D#6:2 | C6:1 A5:1 F#5:1 C6:1 | Db6:1 Bb5:1 Ab5:1 F5:1 | Gb5:1 Bb5:1 Eb6:1 C6:1",
        # The strings climb back in the bridge's second half.
        bridge_str="r:4 | r:4 | r:4 | r:4 | G#4:4 | A4:2 C5:2 | Db5:4 | Eb5:2 Gb5:2",
    ),
    parts=dict(
        intro=[("comp", "bossa", 0.85), ("lead", "intro", "silver", "lead2", 0, 0.6)],
        verse=[("comp", "bossa", 0.72), ("comp", "ep_bossa", 0.35), ("lead", "verse", "flugel", "lead", 0, 1.3),
               ("lead", "verse_fill", "silver", "lead2", 0, 0.8)],
        chorus=[("comp", "bossa", 1.0), ("comp", "ep_bossa", 0.45), ("comp", "oohs", 0.95),
                ("lead", "chorus_str", "section", "pad", 0, 0.8), ("lead", "chorus", "flugel", "lead", 0, 0.9),
                ("lead", "chorus", "silver", "lead2", 12, 0.5)],
        bridge=[("comp", "bossa", 0.62), ("comp", "vibes", 0.42), ("lead", "bridge_str", "section", "pad", 0, 0.8),
                ("lead", "bridge", "ep", "lead", 0, 0.62)],
        chorus2=[("comp", "bossa", 1.05), ("comp", "ep_bossa", 0.45), ("comp", "oohs", 1.1), ("comp", "muted_stabs", 0.45),
                 ("lead", "chorus_str", "section", "pad", 12, 0.75), ("lead", "chorus", "flugel", "lead", 0, 0.9),
                 ("lead", "chorus", "silver", "lead2", 12, 0.55, True), ("counter", "vibes", "lead2", 0.35)],
    ),
    roles={"chorus2": "chorus"},
    risers=("bridge",),
    levels={"cym": -32, "perc": -29, "snare": -25, "kick": -24, "hats": -27, "bass": -19, "gtr": -22, "keys": -27,
            "pad": -25, "brass": -29, "lead": -20, "lead2": -24, "fx": -36},
    sidechain={"pad": 0.0, "bass": 0.0, "keys": 0.0, "gtr2": 0.0, "lead2": 0.0},
    lufs_offset=-1.5,
)

BEAT = 60 / 132
AB = note("Ab2")


def _loop(x, fade_sec=0.3):
    """A seamless loop of `x`: its tail crossfaded into its head (equal power), the tail cut."""
    f = secs(fade_sec)
    body = x[:-f].copy()
    ramp = np.linspace(0.0, 1.0, f)
    body[:f] = x[:f] * np.sqrt(ramp) + x[-f:] * np.sqrt(1.0 - ramp)
    return body


def hum(rng):
    # The dynamo: a warm mains hum on A-flat with a little brush noise, beating slowly. A 3 s loop
    # the game pitches and fades with the supply.
    n = secs(3.3)
    t = np.arange(n) / SR
    f = 103.83
    tone = (np.sin(2 * np.pi * f * t) * 0.6 + np.sin(2 * np.pi * f * 2 * t) * 0.32
            + np.sin(2 * np.pi * f * 3.003 * t) * 0.14 + np.sin(2 * np.pi * f * 4 * t) * 0.07)
    tone *= 0.85 + 0.15 * np.sin(2 * np.pi * 1.5 * t)
    brush = bp(rng.uniform(-1, 1, n), 900, 3800) * (0.3 + 0.1 * np.sin(2 * np.pi * 6.0 * t))
    return _loop(tone * 0.75 + brush * 0.16)


def rain(rng):
    # The storm's rain: a soft hiss with scattered drops on the tin roof. A 3 s loop.
    n = secs(3.3)
    hiss = lp(hp(rng.uniform(-1, 1, n), 800), 6500) * 0.34
    drops = np.zeros(n)
    for _ in range(170):
        at = rng.integers(0, n - secs(0.03))
        d = secs(0.02)
        tt = np.arange(d) / SR
        drops[at:at + d] += np.sin(2 * np.pi * rng.uniform(1200, 3600) * tt) * np.exp(-tt / 0.004) * rng.uniform(0.1, 0.5)
    return _loop(hiss + drops)


def _switch(rng):
    # A knife switch closing: a clack, a small arc.
    return fx.mix((0, fx.tick(1800, 0.05, rng)), (0, fx.thud(0.09, 240, 120, rng, 1.0) * 0.5))


def _on(names, instr_gain, rng):
    # A district comes on: the switch, then a rising chord on vibes and bells over a soft pad.
    notes = [note(n) for n in names]
    bells = fx.arp(notes, 0.075, "bells", 0.5, 0.75, rng)
    pad = ins.pad(notes[:3], 1.2, 0.5, rng)
    pad = pad.mean(axis=0) if pad.ndim == 2 else pad
    return fx.mix((0, _switch(rng) * 0.7), (0.04, bells * instr_gain), (0.05, pad * 0.5))


def on_houses(rng):
    return _on(["Ab4", "C5", "Eb5"], 0.8, rng)


def on_streets(rng):
    return _on(["Bb4", "Eb5", "G5"], 0.85, rng)


def on_funfair(rng):
    return _on(["C5", "F5", "Ab5", "C6"], 0.9, rng)


def on_stadium(rng):
    return _on(["Eb5", "Ab5", "C6", "Eb6"], 1.0, rng)


def crackle(rng):
    # A flicker: dry electric snaps, uneven, thinning out.
    n = secs(0.8)
    x = np.zeros(n)
    t = 0.0
    while t < 0.72:
        at = secs(t)
        d = min(secs(0.012), n - at)
        tt = np.arange(d) / SR
        x[at:at + d] += hp(rng.uniform(-1, 1, d), 1800) * np.exp(-tt / 0.003) * rng.uniform(0.4, 1.0)
        t += rng.uniform(0.02, 0.12)
    return x + bp(rng.uniform(-1, 1, n), 2500, 6000) * 0.05


def out(rng):
    # A district goes dark: the hum sagging away, and a low soft thud as the breaker drops.
    sag = fx.env(fx.sweep(0.9, 330, 70, "saw"), 0.01, 0.35) * 0.5
    sag = lp(sag, 1600)
    return fx.mix((0, sag), (0.72, fx.thud(0.24, 90, 50, rng, 0.8)))


def relit(rng):
    # Back on: the sag in reverse and a bright pair of bells.
    rise = lp(fx.env(fx.sweep(0.42, 90, 300, "saw"), 0.05, 0.08), 1500) * 0.4
    return fx.mix((0, rise), (0.34, _switch(rng) * 0.5), (0.36, fx.arp([note("Eb5"), note("Ab5")], 0.08, "bells", 0.5, 0.8, rng)))


def thunder(rng):
    # Far thunder: the warning, a long low roll with a nearer swell, three seconds.
    n = secs(3.0)
    t = np.arange(n) / SR
    roll = lp(rng.uniform(-1, 1, n), 130) * 2.2
    shape = np.exp(-((t - 0.5) / 0.3) ** 2) * 0.7 + np.exp(-((t - 1.5) / 0.55) ** 2) + 0.25 * np.exp(-t / 1.6)
    mid = bp(rng.uniform(-1, 1, n), 120, 500) * np.exp(-((t - 1.4) / 0.4) ** 2) * 0.5
    return roll * shape + mid


def strike(rng):
    # The strike: a sharp crack, an electric spit, and the thunder right on top of it.
    n = secs(1.6)
    t = np.arange(n) / SR
    crack = hp(rng.uniform(-1, 1, n), 1500) * np.exp(-t / 0.03) * 1.6
    boom = lp(rng.uniform(-1, 1, n), 170) * np.exp(-t / 0.5) * 2.0
    return fx.mix((0, crack), (0.006, fx.zap(0.3, 2600, 300, rng) * 0.7), (0.02, boom), (0, fx.thud(0.6, 62, 40, rng, 1.0)))


def restored(rng):
    # The line's back: a rising fanfare on muted horn and bells.
    arp = fx.arp([note("Ab4"), note("C5"), note("Eb5"), note("Ab5"), note("C6")], 0.09, "bells", 0.5, 0.9, rng)
    return fx.mix((0, _switch(rng) * 0.7), (0.03, arp), (0.2, fx.fanfare([(0, 1, note("Eb5")), (1, 2, note("Ab5"))], 0.14, "brass", rng, 2.0, 0.5)))


def crew_fixed(rng):
    # The crew got it: a quiet two-note all-clear.
    return fx.arp([note("Eb5"), note("Ab4")], 0.16, "vibes", 0.6, 0.6, rng)


def full_town(rng):
    # The whole town lit: a cheer from the stadium under a wide A-flat chord.
    cheer = fx.crowd(2.0, rng) * 0.6
    arp = fx.arp([note("Ab4"), note("Eb5"), note("Ab5"), note("C6"), note("Eb6")], 0.07, "bells", 0.8, 0.9, rng)
    return fx.mix((0, cheer), (0.05, arp))


def firework(rng):
    # A firework: a soft thump, a pause, a wide crackling bloom.
    n = secs(1.2)
    t = np.arange(n) / SR
    bloom = bp(rng.uniform(-1, 1, n), 700, 5000) * np.exp(-t / 0.28) * 0.5
    grains = np.zeros(n)
    for _ in range(40):
        at = rng.integers(secs(0.1), n - secs(0.02))
        d = secs(0.01)
        grains[at:at + d] += hp(rng.uniform(-1, 1, d), 2500) * rng.uniform(0.2, 0.7)
    return fx.mix((0, fx.thud(0.3, 110, 60, rng, 0.7) * 0.6), (0.12, bloom + grains))


def bell(rng):
    # The church bell that opens a new evening: one low stroke with its hum note and strike tone.
    n = secs(2.4)
    t = np.arange(n) / SR
    f = 207.65
    partials = [(0.5, 0.5, 1.6), (1.0, 1.0, 1.1), (1.19, 0.5, 0.8), (1.5, 0.35, 0.6), (2.0, 0.5, 0.45), (2.51, 0.2, 0.3)]
    x = sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t / d) for r, a, d in partials)
    return x * np.minimum(1, t / 0.004) * 0.6


# Named "grid_*": AudioDirector keeps one sound per name for every game.
SFX = {"grid_" + k: v for k, v in {
    "hum": hum, "rain": rain, "on_0": on_houses, "on_1": on_streets, "on_2": on_funfair, "on_3": on_stadium,
    "crackle": crackle, "out": out, "relit": relit, "thunder": thunder, "strike": strike, "restored": restored,
    "crew_fixed": crew_fixed, "full_town": full_town, "firework": firework, "bell": bell}.items()}
