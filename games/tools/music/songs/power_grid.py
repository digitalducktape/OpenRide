"""Power Grid (#81): "Lamplighter", warm porch folk-soul at 92 bpm in A-flat major, for a valley town
at dusk. Brushes and a cross-stick over a soft kick, a shaker, a round picked bass; Rhodes and a
plucked arpeggio under a muted horn in the verse; the chorus opens with an acoustic strum and a
flute doubled on vibes. Real song form: an intro, verse, chorus, a bridge that drops to vibes and
piano, and a last chorus with the flute in thirds and the horn answering. Calm enough for a
recovery ride, with a tune worth earning. Distinct from the family: no spy jazz (Safe), no shanty
(Tug), no boogie (The Pull), no band organ (Balloon Pump), no glockenspiel hook (Keepy Uppy, Watt
Lane), and the slowest theme of them all.

The harmony comes in while the rider meets demand, the lead with the whole town lit.

Effects, in the key: the dynamo's hum (a seamless loop the game pitches to the supply), four
district switch-on chords climbing through the key, the flicker's crackle, the power-down of a
district going dark, its relight, far thunder and the storm's rain (a seamless loop), the strike, the
repair's rising chord, the crew's quiet fix, the full town's cheer and fireworks, and the church
bell that opens a new evening. Written for this repo."""
import numpy as np

import dsp
import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, hp, bp

PREFIX = "Grid"

SONG = dict(
    file="lamplighter", title="Lamplighter", bpm=92, key="Ab", scale=[0, 2, 4, 5, 7, 9, 11], seed=81,
    drums="porch", bass="root5", swing=0.05, verb_sec=2.2,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Abmaj7", "Fm7", "Dbmaj7", "Eb7sus4"],
        verse=["Abmaj7", "Cm7", "Dbmaj7", "Eb7sus4 Eb7", "Abmaj7", "Fm7", "Bbm7", "Eb7"],
        chorus=["Dbmaj7", "Eb", "Cm7", "Fm7", "Dbmaj7", "Eb", "Abmaj7", "Ab7"],
        bridge=["Fm7", "Db", "Ab", "Eb", "Fm7", "Bbm7", "Dbmaj7", "Eb7sus4"],
    ),
    melody=dict(
        verse="C5:1.5 Eb5:0.5 G5:2 | G5:1 F5:0.5 Eb5:0.5 C5:2 | Db5:1 F5:1 Ab5:1.5 G5:0.5 | F5:2 Eb5:1 r:1 |"
              " C5:1.5 Eb5:0.5 Ab5:1 G5:1 | F5:1.5 Eb5:0.5 C5:2 | Db5:1 F5:1 Bb5:1 Ab5:1 | G5:2 Bb4:1 r:1",
        chorus="Ab5:1.5 Bb5:0.5 C6:2 | Bb5:1 G5:1 Eb5:2 | Eb5:0.5 G5:0.5 C6:1 Bb5:1 G5:1 | Ab5:1.5 G5:0.5 F5:2 |"
               " Ab5:1.5 Bb5:0.5 Db6:2 | C6:1 Bb5:1 G5:2 | Ab5:1 C6:1 Eb6:2 | C6:3 r:1",
        bridge="F5:2 Ab5:2 | Ab5:1 F5:1 Db5:2 | C5:1 Eb5:1 Ab5:2 | G5:3 r:1 | C6:2 Ab5:2 | Bb5:1 Db6:1 F5:2 |"
               " F5:1 Ab5:1 C6:2 | Bb5:2 G5:2",
    ),
    parts=dict(
        intro=[("comp", "ep_hold", 0.7), ("comp", "arp", 0.4)],
        verse=[("comp", "ep", 0.75), ("comp", "arp", 0.5), ("lead", "verse", "muted", "lead", 0, 0.9)],
        chorus=[("comp", "strum", 0.75), ("comp", "ep_hold", 0.5), ("comp", "pad", 0.5),
                ("lead", "chorus", "flute", "lead", 0, 0.85), ("lead", "chorus", "vibes", "lead2", 0, 0.6)],
        bridge=[("comp", "vibes", 0.75), ("comp", "pad", 0.6), ("lead", "bridge", "piano", "lead", 0, 0.8)],
        chorus2=[("comp", "strum", 0.8), ("comp", "ep_hold", 0.55), ("comp", "arp", 0.4), ("comp", "pad", 0.55),
                 ("lead", "chorus", "flute", "lead", 0, 0.85, True), ("lead", "chorus", "vibes", "lead2", 0, 0.55),
                 ("counter", "muted", "lead2", 0.4)],
    ),
    roles={"chorus2": "chorus"},
    risers=("bridge",),
    levels={"cym": -33, "perc": -30, "snare": -25, "kick": -21, "hats": -32, "lead": -20.5, "fx": -36},
    lufs_offset=-2.0,
)

BEAT = 60 / 92
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
