"""Keepy Uppy (#77): "Meadow Breeze", a light, breezy acoustic pop at 112 bpm in G major for a
balloon over a meadow on a summer afternoon. A soft kick and snare with sleigh-bell shimmer, a
picked root-fifth bass, airy strummed acoustic chords and a pad; a whistle sings the verse, a
flute with bells an octave up carries the chorus. The harmony comes in with the balloon off the
ground (the mid band), the lead in the high band. Written for this repo.

Effects, in the theme's key: the fan's hum (a seamless loop the game pitches to the lift), the
rain (a seamless loop), the balloon's squeak near the ground, the pop, a bird's flutter and
chirp, the birds shaken off, a gust and the downdraft's warning whooshes, the rain cloud's
rumble, a new balloon's rising pluck and a bright chime for reaching the high band."""
import numpy as np

import dsp
import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, hp, bp

PREFIX = "Keepy"

SONG = dict(
    file="meadow_breeze", title="Meadow Breeze", bpm=112, key="G", scale=[0, 2, 4, 5, 7, 9, 11], seed=77,
    drums="pop", bass="root5", verb_sec=1.6,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Gadd9", "Cmaj7", "Gadd9", "D"],
        verse=["G", "D", "Em7", "Cmaj7", "G", "D", "Cmaj7", "D"],
        chorus=["Cmaj7", "D", "Bm7", "Em7", "Cmaj7", "D", "G", "G"],
        bridge=["Em7", "Cmaj7", "G", "D", "Em7", "Am7", "Cmaj7", "D7sus4"],
    ),
    melody=dict(
        verse="B4:1 D5:0.5 G5:0.5 F#5:1 D5:1 | A4:1.5 D5:0.5 F#5:1 r:1 | G5:0.5 F#5:0.5 E5:0.5 D5:0.5 B4:1 E5:1 |"
              " E5:1 D5:0.5 C5:0.5 B4:1 r:1 | B4:1 D5:0.5 G5:0.5 A5:1 G5:1 | F#5:1.5 E5:0.5 D5:1 A4:1 |"
              " E5:0.5 G5:0.5 E5:0.5 C5:0.5 B4:1 A4:1 | A4:2 r:2",
        chorus="G5:1 E5:0.5 G5:0.5 C6:1 B5:1 | A5:1.5 F#5:0.5 D5:1 r:1 | F#5:0.5 A5:0.5 B5:1 D6:1 B5:1 |"
               " B5:1.5 G5:0.5 E5:1 r:1 | G5:1 E5:0.5 G5:0.5 E6:1 D6:1 | C6:1 B5:0.5 A5:0.5 F#5:1 D6:1 |"
               " B5:1 D6:1 G6:1.5 F#6:0.5 | G6:2 r:2",
        bridge="E5:2 G5:2 | E5:2 C5:2 | D5:1 G5:1 B5:2 | A5:3 r:1 | B5:2 G5:2 | C6:2 A5:2 | G5:1 E5:1 C5:2 | D5:2 A5:2",
    ),
    parts=dict(
        intro=[("comp", "pad", 0.6), ("comp", "strum", 0.6)],
        verse=[("comp", "strum", 0.85), ("comp", "pad", 0.45), ("lead", "verse", "whistle", "lead", 0, 0.85)],
        chorus=[("comp", "strum", 0.9), ("comp", "arp", 0.5), ("comp", "pad", 0.5),
                ("lead", "chorus", "flute", "lead", 0, 0.9), ("lead", "chorus", "bells", "lead2", 12, 0.35)],
        bridge=[("comp", "pad", 0.6), ("comp", "arp", 0.45), ("lead", "bridge", "flute", "lead", 0, 0.75)],
        chorus2=[("comp", "strum", 0.9), ("comp", "arp", 0.5), ("comp", "pad", 0.5),
                 ("lead", "chorus", "flute", "lead", 0, 0.9, True), ("lead", "chorus", "whistle", "lead2", 12, 0.35)],
    ),
)

BEAT = 60 / 112


def _loop(x, fade_sec=0.25):
    """A seamless loop of `x`: its tail crossfaded into its head (equal power), the tail cut."""
    f = secs(fade_sec)
    body = x[:-f].copy()
    ramp = np.linspace(0.0, 1.0, f)
    body[:f] = x[:f] * np.sqrt(ramp) + x[-f:] * np.sqrt(1.0 - ramp)
    return body


def fan_hum(rng):
    # The fan: a soft blade-pass hum (a low tone with its harmonics, beating gently) over a
    # breath of air. A 2 s loop the game pitches with the lift.
    sec = 2.25
    n = secs(sec)
    t = np.arange(n) / SR
    blade = 98.0  # G2, in the key
    tone = (np.sin(2 * np.pi * blade * t) * 0.6 + np.sin(2 * np.pi * blade * 2 * t) * 0.25
            + np.sin(2 * np.pi * blade * 3 * t) * 0.08)
    tone *= 0.8 + 0.2 * np.sin(2 * np.pi * 8.0 * t)
    air = bp(rng.uniform(-1, 1, n), 300, 2400) * (0.55 + 0.15 * np.sin(2 * np.pi * 4.0 * t))
    return _loop(tone * 0.7 + air * 0.5)


def rain(rng):
    # Steady rain: soft broadband hiss with scattered patters. A 3 s loop.
    sec = 3.25
    n = secs(sec)
    hiss = lp(hp(rng.uniform(-1, 1, n), 900), 7000) * 0.35
    patter = np.zeros(n)
    for _ in range(260):
        at = rng.integers(0, n - secs(0.02))
        d = secs(0.012)
        tt = np.arange(d) / SR
        f = rng.uniform(1800, 5200)
        patter[at:at + d] += np.sin(2 * np.pi * f * tt) * np.exp(-tt / 0.003) * rng.uniform(0.1, 0.4)
    return _loop(hiss + patter)


def squeak(rng):
    # The balloon rubbing on the grille: a short rubbery squeak, wobbling in pitch.
    x = fx.sweep(0.32, 900, 620, "sine", vib=0.08)
    x += fx.sweep(0.32, 1800, 1240, "sine", vib=0.08) * 0.3
    return fx.env(x, 0.02, 0.08) * 0.8


def pop(rng):
    # The pop: a sharp crack of noise, a low thump and the rubber's slap.
    n = secs(0.6)
    t = np.arange(n) / SR
    crack = hp(rng.uniform(-1, 1, n), 1500) * np.exp(-t / 0.012) * 1.2
    body = fx.thud(0.4, 90, 120, rng, 0.8) * 0.7
    slap = bp(rng.uniform(-1, 1, n), 400, 2500) * np.exp(-t / 0.05) * 0.4
    return fx.mix((0, crack + slap), (0.005, body))


def bird_flutter(rng):
    # A bird coming in: wing beats (noise bursts at 14 a second) and a two-note chirp in G.
    sec = 1.1
    n = secs(sec)
    t = np.arange(n) / SR
    beats = (0.5 + 0.5 * np.sin(2 * np.pi * 14.0 * t)) ** 4
    wings = bp(rng.uniform(-1, 1, n), 700, 3500) * beats * np.minimum(1, t / 0.3) * 0.6
    chirp1 = fx.env(fx.sweep(0.07, 2900, 3900, "sine"), 0.005, 0.03)
    chirp2 = fx.env(fx.sweep(0.09, 3500, 2600, "sine"), 0.005, 0.04)
    return fx.mix((0, wings), (0.75, chirp1 * 0.5), (0.86, chirp2 * 0.5))


def birds_shaken(rng):
    # Shaken off: a flurry of wings flying away and a happy rising bell arpeggio (G major).
    n = secs(0.9)
    t = np.arange(n) / SR
    beats = (0.5 + 0.5 * np.sin(2 * np.pi * 18.0 * t)) ** 4
    wings = bp(rng.uniform(-1, 1, n), 900, 4500) * beats * np.exp(-t / 0.35) * 0.7
    arp = fx.arp([note("G5"), note("B5"), note("D6"), note("G6")], 0.07, "bells", 0.35, 0.8, rng)
    return fx.mix((0, wings), (0.05, arp))


def gust(rng):
    # A gust building through the pole's streamers: a whoosh that swells over 2 s.
    return fx.whoosh(2.2, 400, 3200, True, rng, 0.85) * 0.8


def downdraft_warn(rng):
    # The downdraft coming: a deeper, darker whoosh falling in pitch, with a low swell under it.
    n = secs(2.4)
    t = np.arange(n) / SR
    rumble = lp(rng.uniform(-1, 1, n), 180) * (t / 2.4) ** 1.5 * 1.4
    return fx.whoosh(2.4, 1800, 250, True, rng, 0.9) * 0.8 + rumble


def rain_warn(rng):
    # The rain cloud: a far, soft roll of thunder.
    n = secs(2.6)
    t = np.arange(n) / SR
    roll = lp(rng.uniform(-1, 1, n), 140) * (np.exp(-((t - 0.9) / 0.6) ** 2) + 0.6 * np.exp(-((t - 1.7) / 0.5) ** 2))
    return roll * 1.5


def new_balloon(rng):
    # A new balloon floats in: a rising plucked arpeggio and a soft breath.
    arp = fx.arp([note("D5"), note("G5"), note("B5"), note("D6")], 0.09, "pluck", 0.3, 0.8, rng)
    air = fx.whoosh(0.6, 1200, 4000, True, rng, 0.5) * 0.25
    return fx.mix((0, air), (0.1, arp))


def high_chime(rng):
    # Into the high band: a bright two-bell chime on the fifth and the octave.
    return fx.mix((0, ins.bells(note("D6"), 0.25, 0.8, rng)), (0.09, ins.bells(note("G6"), 0.4, 0.9, rng)))


# Named "keepy_*": AudioDirector keeps one sound per name for every game, and Balloon Pump (#76)
# is likely to have a "pop" of its own.
SFX = {"keepy_" + k: v for k, v in {
    "fan_hum": fan_hum, "rain": rain, "squeak": squeak, "pop": pop, "bird_flutter": bird_flutter,
    "birds_shaken": birds_shaken, "gust": gust, "downdraft_warn": downdraft_warn, "rain_warn": rain_warn,
    "new_balloon": new_balloon, "high_chime": high_chime}.items()}
