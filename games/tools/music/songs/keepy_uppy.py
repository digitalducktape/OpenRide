"""Keepy Uppy (#77, the audio rework): "Updraft", bright summer indie-pop at 118 bpm in B-flat
major, for a balloon riding a column of air. A pop kit with handclap backbeats and a sleigh-bell
shimmer, a bouncy octave bass, eighth-note piano and a plucked arpeggio; the glockenspiel sings
the verse hook, and the chorus lifts with a soft string section an octave under the bells, then a
counter line in the second chorus. Real song form: an intro, verse, chorus, a second verse with
the counter line, a bridge that drops to piano and builds back on a riser, and a final chorus.
Distinct from the family: no shanty whistle (Tug), no spy jazz (Safe), no electro-rock (Dodge),
no synth-funk (Cadence), no house (the demo).

The harmony comes in with the balloon off the ground (the mid band), the lead in the high band.

Effects, in the key: the fan's hum (a seamless loop the game pitches to the lift), the rain (a
seamless loop), the balloon's squeak on the grille, the pop (a rubber crack, a thump and a falling
"aww" on the glockenspiel), a bird's flutter and chirp, the birds shaken off, a gust and the
downdraft's warning, the rain cloud's rumble, a new balloon's rising pluck and a chime for reaching
the high band. Written for this repo."""
import numpy as np

import dsp
import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, hp, bp

PREFIX = "Keepy"

SONG = dict(
    file="updraft", title="Updraft", bpm=118, key="Bb", scale=[0, 2, 4, 5, 7, 9, 11], seed=177,
    drums="pop", bass="octave", verb_sec=1.5,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("verse2", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Bb", "Gm7", "Ebmaj7", "F"],
        verse=["Bb", "F", "Gm7", "Eb", "Bb", "F", "Eb", "F"],
        chorus=["Eb", "F", "Dm7", "Gm7", "Eb", "F", "Bb", "Bb"],
        bridge=["Gm7", "Eb", "Bb", "F", "Gm7", "Cm7", "Ebmaj7", "F7sus4"],
    ),
    melody=dict(
        verse="D5:1 F5:0.5 Bb5:0.5 A5:1 F5:1 | C5:1.5 F5:0.5 A5:1 r:1 | Bb5:0.5 A5:0.5 G5:0.5 F5:0.5 D5:1 G5:1 |"
              " G5:1 F5:0.5 Eb5:0.5 D5:1 r:1 | D5:1 F5:0.5 Bb5:0.5 C6:1 Bb5:1 | A5:1.5 G5:0.5 F5:1 C5:1 |"
              " G5:0.5 Bb5:0.5 G5:0.5 Eb5:0.5 D5:1 C5:1 | C5:2 r:2",
        chorus="Bb5:1 G5:0.5 Bb5:0.5 Eb6:1 D6:1 | C6:1.5 A5:0.5 F5:1 r:1 | A5:0.5 C6:0.5 D6:1 F6:1 D6:1 |"
               " D6:1.5 Bb5:0.5 G5:1 r:1 | Bb5:1 G5:0.5 Bb5:0.5 G6:1 F6:1 | Eb6:1 D6:0.5 C6:0.5 A5:1 F6:1 |"
               " D6:1 F6:1 Bb6:1.5 A6:0.5 | Bb6:2 r:2",
        bridge="G5:2 Bb5:2 | Eb5:2 G5:2 | F5:1 Bb5:1 D6:2 | C6:3 r:1 | D6:2 Bb5:2 | Eb6:2 C6:2 |"
               " Bb5:1 G5:1 Eb5:2 | F5:2 A5:2",
    ),
    parts=dict(
        intro=[("comp", "piano8", 0.6), ("comp", "pad", 0.45)],
        verse=[("comp", "piano8", 0.75), ("comp", "pad", 0.35), ("lead", "verse", "bells", "lead", 0, 0.9)],
        chorus=[("comp", "piano8", 0.75), ("comp", "arp", 0.55), ("comp", "pad", 0.5),
                ("lead", "chorus", "strings", "lead", -12, 0.9), ("lead", "chorus", "bells", "lead2", 0, 0.5)],
        verse2=[("comp", "piano8", 0.75), ("comp", "arp", 0.45), ("lead", "verse", "bells", "lead", 0, 0.9),
                ("counter", "strings", "lead2", 0.45)],
        bridge=[("comp", "piano", 0.7), ("comp", "pad", 0.55), ("lead", "bridge", "piano", "lead", 0, 0.8)],
        chorus2=[("comp", "piano8", 0.8), ("comp", "arp", 0.6), ("comp", "pad", 0.55),
                 ("lead", "chorus", "strings", "lead", -12, 0.9, True), ("lead", "chorus", "bells", "lead2", 0, 0.55),
                 ("counter", "pluck", "lead2", 0.35)],
    ),
    roles={"verse2": "verse", "chorus2": "chorus"},
    risers=("intro", "bridge"),
    levels={"perc": -29, "keys": -23},
)

BEAT = 60 / 118


def _loop(x, fade_sec=0.25):
    """A seamless loop of `x`: its tail crossfaded into its head (equal power), the tail cut."""
    f = secs(fade_sec)
    body = x[:-f].copy()
    ramp = np.linspace(0.0, 1.0, f)
    body[:f] = x[:f] * np.sqrt(ramp) + x[-f:] * np.sqrt(1.0 - ramp)
    return body


def fan_hum(rng):
    # The fan: a soft blade-pass hum (Bb1's harmonics, beating gently) over a breath of air. A
    # 2 s loop the game pitches with the lift.
    sec = 2.25
    n = secs(sec)
    t = np.arange(n) / SR
    blade = 116.54  # Bb2, in the key
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
    # The pop: a sharp crack, the rubber's slap and a low thump, then a falling "aww" on the
    # glockenspiel (F, D, Bb: down the key's triad) so the moment reads over the music.
    n = secs(0.7)
    t = np.arange(n) / SR
    crack = hp(rng.uniform(-1, 1, n), 1200) * np.exp(-t / 0.018) * 1.4
    slap = bp(rng.uniform(-1, 1, n), 300, 2500) * np.exp(-t / 0.07) * 0.6
    body = fx.thud(0.5, 85, 140, rng, 1.0)
    aww = fx.arp([note("F5"), note("D5"), note("Bb4")], 0.11, "bells", 0.3, 0.7, rng)
    return fx.mix((0, crack + slap), (0.004, body), (0.12, aww * 0.55))


def bird_flutter(rng):
    # A bird coming in: wing beats (noise bursts at 14 a second) and a two-note chirp.
    sec = 1.1
    n = secs(sec)
    t = np.arange(n) / SR
    beats = (0.5 + 0.5 * np.sin(2 * np.pi * 14.0 * t)) ** 4
    wings = bp(rng.uniform(-1, 1, n), 700, 3500) * beats * np.minimum(1, t / 0.3) * 0.8
    chirp1 = fx.env(fx.sweep(0.07, 2900, 3900, "sine"), 0.005, 0.03)
    chirp2 = fx.env(fx.sweep(0.09, 3500, 2600, "sine"), 0.005, 0.04)
    return fx.mix((0, wings), (0.62, chirp1 * 0.8), (0.74, chirp2 * 0.8), (0.95, chirp1 * 0.6))


def birds_shaken(rng):
    # Shaken off: a flurry of wings flying away and a happy rising bell arpeggio (B-flat major).
    n = secs(0.9)
    t = np.arange(n) / SR
    beats = (0.5 + 0.5 * np.sin(2 * np.pi * 18.0 * t)) ** 4
    wings = bp(rng.uniform(-1, 1, n), 900, 4500) * beats * np.exp(-t / 0.35) * 0.7
    arp = fx.arp([note("Bb5"), note("D6"), note("F6"), note("Bb6")], 0.07, "bells", 0.35, 0.8, rng)
    return fx.mix((0, wings), (0.05, arp))


def gust(rng):
    # A gust building through the pole's streamers: a whoosh that swells over 2 s, with a flap of
    # cloth at its peak.
    n = secs(0.4)
    t = np.arange(n) / SR
    flap = bp(rng.uniform(-1, 1, n), 400, 2000) * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * t)) ** 3 * np.exp(-t / 0.15)
    return fx.mix((0, fx.whoosh(2.2, 400, 3600, True, rng, 0.85)), (1.75, flap * 0.7))


def downdraft_warn(rng):
    # The downdraft coming: a darker whoosh falling in pitch, a low swell under it, and two
    # falling low tones (F2, Bb1) so it reads as "down" through the music.
    n = secs(2.4)
    t = np.arange(n) / SR
    rumble = lp(rng.uniform(-1, 1, n), 180) * (t / 2.4) ** 1.5 * 1.4
    tones = fx.mix((0.9, fx.env(fx.sweep(0.6, 174.6, 130.8, "sine"), 0.02, 0.2) * 0.5),
                   (1.6, fx.env(fx.sweep(0.7, 116.5, 87.3, "sine"), 0.02, 0.3) * 0.6))
    return fx.mix((0, fx.whoosh(2.4, 1800, 250, True, rng, 0.9) * 0.8 + rumble), (0, tones))


def rain_warn(rng):
    # The rain cloud: a far roll of thunder and the first drops tapping on the crate.
    n = secs(2.6)
    t = np.arange(n) / SR
    roll = lp(rng.uniform(-1, 1, n), 160) * (np.exp(-((t - 0.8) / 0.55) ** 2) + 0.6 * np.exp(-((t - 1.6) / 0.5) ** 2))
    drops = np.zeros(n)
    for k in range(9):
        at = secs(1.4 + k * 0.12 + rng.uniform(0, 0.06))
        d = secs(0.03)
        tt = np.arange(d) / SR
        drops[at:at + d] += np.sin(2 * np.pi * rng.uniform(1500, 2600) * tt) * np.exp(-tt / 0.006) * 1.2
    return roll * 1.4 + drops


def new_balloon(rng):
    # A new balloon floats in: a rising plucked arpeggio and a soft breath.
    arp = fx.arp([note("F5"), note("Bb5"), note("D6"), note("F6")], 0.09, "pluck", 0.3, 0.8, rng)
    air = fx.whoosh(0.6, 1200, 4000, True, rng, 0.5) * 0.25
    return fx.mix((0, air), (0.1, arp))


def high_chime(rng):
    # Into the high band: a bright two-bell chime on the fifth and the octave.
    return fx.mix((0, ins.bells(note("F6"), 0.25, 0.8, rng)), (0.09, ins.bells(note("Bb6"), 0.4, 0.9, rng)))


# Named "keepy_*": AudioDirector keeps one sound per name for every game, and Balloon Pump (#76)
# is likely to have a "pop" of its own.
SFX = {"keepy_" + k: v for k, v in {
    "fan_hum": fan_hum, "rain": rain, "squeak": squeak, "pop": pop, "bird_flutter": bird_flutter,
    "birds_shaken": birds_shaken, "gust": gust, "downdraft_warn": downdraft_warn, "rain_warn": rain_warn,
    "new_balloon": new_balloon, "high_chime": high_chime}.items()}
