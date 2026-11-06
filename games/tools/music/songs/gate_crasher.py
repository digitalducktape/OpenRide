"""Gate Crasher (#80): "Clear Round", a bright show-ring galop at 138 bpm in G major for a morning
in the arena. A brisk snare drive and a bouncing octave bass under eighth-note piano and acoustic
strums; a flute sings the verse, a brass fanfare carries the chorus with bells on top, and the
bridge settles on a pad before a snare build. The harmony comes in at a canter, the lead with
the round still clear. Written for this repo: no samples, nothing borrowed.

The effects are the arena's: a three-beat canter stride the game plays once per stride, the
countdown tick and take-off chime, the lift and landing, a rail clatter, applause and the clear
round's fanfare."""
import numpy as np

import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, bp, hp

PREFIX = "Gate"

SONG = dict(
    file="clear_round", title="Clear Round", bpm=138, key="G", scale=[0, 2, 4, 5, 7, 9, 11], seed=80,
    drums="drive", bass="octave", verb_sec=1.5,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["G", "G", "C D", "G"],
        verse=["G", "D", "Em", "C", "G", "D", "C D", "G"],
        chorus=["C", "G", "D", "Em", "C", "G", "Am D", "G"],
        bridge=["Em", "C", "G", "D", "Em", "C", "A7", "D7"],
    ),
    melody=dict(
        verse="G5:0.5 B5:0.5 D6:1 B5:0.5 G5:0.5 D5:1 | F#5:0.5 A5:0.5 D6:1 C6:0.5 A5:0.5 F#5:1 |"
              " E5:0.5 G5:0.5 B5:1 G5:0.5 E5:0.5 B4:1 | C5:0.5 E5:0.5 G5:1 E5:1 r:1 |"
              " G5:0.5 B5:0.5 D6:1 E6:0.5 D6:0.5 B5:1 | A5:0.5 F#5:0.5 D5:1 A5:1 r:1 |"
              " G5:0.5 E5:0.5 C5:1 F#5:0.5 A5:0.5 D6:1 | B5:3 r:1",
        chorus="G5:1 C6:1 E6:1.5 D6:0.5 | D6:1 B5:1 G5:2 | A5:1 D6:1 F#6:1.5 E6:0.5 | E6:1 B5:1 G5:2 |"
               " G5:1 C6:1 E6:1.5 G6:0.5 | F#6:0.5 E6:0.5 D6:1 B5:2 | C6:1 E6:1 D6:1 F#6:1 | G6:3 r:1",
        bridge="B5:2 G5:2 | C6:2 E5:2 | D6:1 B5:1 G5:2 | A5:3 r:1 | B5:2 E6:2 | C6:2 G5:2 |"
               " C#6:1 E6:1 A5:2 | D6:1 F#6:1 A6:2",
    ),
    parts=dict(
        intro=[("comp", "stabs", 0.75), ("comp", "strum", 0.6)],
        # Verse: eighth-note piano and strums under the flute.
        verse=[("comp", "piano8", 0.7), ("comp", "strum", 0.6),
               ("lead", "verse", "flute", "lead", 0, 0.9)],
        # Chorus: the fanfare on brass, bells an octave up, stabs answering.
        chorus=[("comp", "piano8", 0.65), ("comp", "stabs", 0.6), ("comp", "strum", 0.5),
                ("lead", "chorus", "brass", "lead", -12, 0.9), ("lead", "chorus", "bells", "lead2", 0, 0.45)],
        # Bridge: half-time drums (the arranger's), a pad, held stabs and the flute low.
        bridge=[("comp", "pad", 0.55), ("comp", "stabs_hold", 0.5), ("comp", "strum", 0.45),
                ("lead", "bridge", "flute", "lead", -12, 0.85), ("lead", "bridge", "vibes", "lead2", 0, 0.4)],
        chorus2=[("comp", "piano8", 0.65), ("comp", "stabs", 0.65), ("comp", "strum", 0.5),
                 ("lead", "chorus", "brass", "lead", -12, 0.9, True), ("lead", "chorus", "flute", "lead2", 0, 0.5),
                 ("counter", "bells", "lead2", 0.35)],
    ),
)

BEAT = 60 / 138


def _hoof(rng, level=1.0, pitch=1.0):
    # One hoof in arena sand: a soft low thump with a little grit thrown up.
    n = secs(0.13)
    t = np.arange(n) / SR
    thump = np.sin(2 * np.pi * (95 * pitch) * t * (1 - 0.8 * t)) * np.exp(-t * 34)
    grit = bp(rng.uniform(-1, 1, n), 700, 3200) * np.exp(-t * 55) * 0.3
    return (thump + grit) * level


def hoof_canter(rng):
    # A canter stride: three beats, then the moment of suspension (the game plays one per stride).
    return fx.mix((0, _hoof(rng, 0.8, 1.1)), (0.09, _hoof(rng, 0.7, 0.95)), (0.2, _hoof(rng, 1.0, 1.0)))


def count_tick(rng):
    # A countdown beat, in the key: a bright wood-and-bell tick on D.
    return fx.mix((0, ins.bells(note("D6"), 0.2, 0.8, rng)), (0, fx.tick(2400, 0.04, rng) * 0.5))


def line_chime(rng):
    # The line itself: the beat resolves up to G, an octave stack.
    return fx.mix((0, ins.bells(note("G6"), 0.4, 1.0, rng)), (0, ins.bells(note("G5"), 0.4, 0.8, rng)))


def take_chime(rng):
    # The camera read the stand in time: a rising G major triad, quick.
    return fx.arp([note("G5"), note("B5"), note("D6")], 0.07, "bells", dur=0.35, vel=0.9, rng=rng)


def lift_off(rng):
    # The horse leaves the ground: a short rush of air and a creak of leather.
    return fx.mix((0, fx.whoosh(0.4, 300, 2400, True, rng) * 0.7), (0.02, fx.creak(0.18, 210, rng) * 0.25))


def landing(rng):
    # All four feet back in the sand.
    return fx.mix((0, _hoof(rng, 1.0, 0.8)), (0.05, _hoof(rng, 0.9, 0.75)), (0.09, fx.thud(0.24, 70, 40, rng, knock=0.4) * 0.7))


def rail_clatter(rng):
    # A pole comes down: a hollow knock, a bounce and a rolling rattle.
    def knock(pitch, level):
        n = secs(0.16)
        t = np.arange(n) / SR
        wood = (np.sin(2 * np.pi * 520 * pitch * t) + 0.6 * np.sin(2 * np.pi * 1180 * pitch * t)) * np.exp(-t * 32)
        return (wood + bp(rng.uniform(-1, 1, n), 900, 3800) * np.exp(-t * 60) * 0.3) * level
    return fx.mix((0, knock(1.0, 1.0)), (0.17, knock(0.82, 0.8)), (0.3, knock(1.1, 0.55)), (0.4, knock(0.9, 0.42)),
                  (0.48, knock(1.0, 0.3)), (0.54, knock(0.86, 0.22)), (0.02, fx.thud(0.3, 110, 50, rng, knock=0.6) * 0.5))


def applause(rng):
    # A grandstand clapping: a few thousand short bursts, swelling and dying away.
    sec = 3.2
    n = secs(sec)
    t = np.arange(n) / SR
    claps = (rng.random(n) > 0.9965).astype(float) * rng.uniform(0.3, 1.0, n)
    kernel = np.exp(-np.arange(secs(0.012)) / (SR * 0.003)) * rng.uniform(-1, 1, secs(0.012))
    x = np.convolve(claps, kernel)[:n]
    x = hp(bp(x, 800, 5200), 500)
    env = np.minimum(t / 0.5, 1.0) * np.minimum((sec - t) / 1.4, 1.0)
    x = x * env
    return x / (np.max(np.abs(x)) + 1e-9) * 0.8


def clear_round(rng):
    # The round was clear: the chorus's fanfare, to a held G with a crash and a snare flourish.
    notes = [(0, 0.5, note("D5")), (0.5, 0.5, note("G5")), (1, 0.5, note("B5")), (1.5, 3.0, note("D6"))]
    top = fx.fanfare(notes, BEAT, "brass", rng)
    under = fx.fanfare([(1.5, 3.0, note("B4")), (1.5, 3.0, note("G4"))], BEAT, "brass", rng, vel=0.6)
    return fx.mix((0, top), (0, under), (0, fx.drumroll(1.5 * BEAT, rng) * 0.5), (1.5 * BEAT, ins.crash(0.8, rng)),
                  (1.5 * BEAT, ins.bells(note("G6"), 1.0, 0.7, rng)))


def rein_warn(rng):
    # A soft two-note nudge: sit, or pedal.
    return fx.mix((0, ins.bells(note("A5"), 0.2, 0.7, rng)), (0.16, ins.bells(note("E5"), 0.3, 0.7, rng)))


SFX = {"hoof_canter": hoof_canter, "count_tick": count_tick, "line_chime": line_chime, "take_chime": take_chime,
       "lift_off": lift_off, "landing": landing, "rail_clatter": rail_clatter, "applause": applause,
       "clear_round": clear_round, "rein_warn": rein_warn}
