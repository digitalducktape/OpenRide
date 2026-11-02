"""Balloon Pump (#76): "Candy Stripe March", a fairground-organ march at 126 bpm in F major, for a
balloon stall at noon. A light pop beat, an oom-pah root-fifth bass, an accordion oom-pah and
vibes as the band organ's chords, a pipe-organ tune with a glockenspiel an octave up in the
chorus, and a flute in the bridge. The harmony comes in while the balloon takes air, the lead
once the rider is well over the push line. Written for this repo; no existing tune is quoted.

Effects, in the theme's key: the pump's chuff (pitched per stroke by the game), the rubber squeak
of a filling balloon, the tie-off's pop and twang, the hiss of a leak, a gold chime, the Race's
start call, its won and lost stings, and the last-seconds tick."""
import numpy as np

import dsp
import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, hp, bp, lp

PREFIX = "Pump"

SONG = dict(
    file="candy_stripe_march", title="Candy Stripe March", bpm=126, key="F", scale=[0, 2, 4, 5, 7, 9, 10], seed=76,
    drums="pop", bass="root5", verb_sec=1.5,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["F", "Bb", "C7", "C7"],
        verse=["F", "C7", "C7", "F", "Bb", "F", "C7", "F"],
        chorus=["F", "C7", "Bb", "F", "F", "C7", "Bb C7", "F"],
        bridge=["Dm", "C", "F", "Bb", "Bb", "F", "Gm", "C7"],
    ),
    melody=dict(
        verse="C5:0.5 F5:0.5 A5:0.5 F5:0.5 C6:1 A5:1 | Bb5:0.5 A5:0.5 G5:0.5 F5:0.5 G5:2 |"
              " C5:0.5 E5:0.5 G5:0.5 E5:0.5 C6:1 Bb5:1 | A5:1.5 G5:0.5 F5:2 |"
              " D5:0.5 F5:0.5 Bb5:0.5 D6:0.5 C6:1 Bb5:1 | A5:0.5 C6:0.5 F5:0.5 A5:0.5 G5:2 |"
              " E5:0.5 G5:0.5 C6:0.5 Bb5:0.5 A5:1 G5:1 | F5:3 r:1",
        chorus="A5:1 A5:0.5 Bb5:0.5 C6:1 A5:1 | G5:1 G5:0.5 A5:0.5 Bb5:2 |"
               " Bb5:1 Bb5:0.5 C6:0.5 D6:1 Bb5:1 | A5:1 G5:1 F5:2 |"
               " A5:1 A5:0.5 Bb5:0.5 C6:1 F6:1 | E6:1 D6:0.5 C6:0.5 D6:2 |"
               " C6:0.5 Bb5:0.5 A5:0.5 G5:0.5 A5:1 E5:1 | F5:2 r:2",
        bridge="D5:2 F5:2 | E5:2 G5:2 | F5:1 A5:1 C6:2 | Bb5:3 r:1 |"
               " D6:2 C6:1 Bb5:1 | A5:2 F5:2 | G5:1 A5:1 Bb5:1 G5:1 | C6:2 E5:2",
    ),
    parts=dict(
        intro=[("comp", "oompah", 0.7), ("comp", "vibes", 0.5)],
        verse=[("comp", "oompah", 0.8), ("comp", "vibes", 0.5), ("lead", "verse", "organ", "lead", 0, 0.9)],
        chorus=[("comp", "oompah", 0.85), ("comp", "stabs", 0.45), ("lead", "chorus", "organ", "lead", 0, 0.9),
                ("lead", "chorus", "bells", "lead2", 12, 0.5)],
        bridge=[("comp", "acc_hold", 0.6), ("comp", "vibes", 0.6), ("lead", "bridge", "flute", "lead", 0, 0.8)],
        chorus2=[("comp", "oompah", 0.85), ("comp", "stabs", 0.5), ("lead", "chorus", "organ", "lead", 0, 0.9, True),
                 ("lead", "chorus", "whistle", "lead2", 12, 0.4)],
    ),
)

BEAT = 60 / 126


def _t(sec):
    return np.arange(secs(sec)) / SR


def pump_chuff(rng):
    # One stroke of the brass pump: a puff of air through the valve and a soft knock of the piston.
    air = fx.whoosh(0.22, 350, 2400, True, rng, 0.35)
    knock = fx.thud(0.14, 95, 45, rng, 0.35) * 0.45
    valve = bp(rng.uniform(-1, 1, secs(0.05)), 1200, 3000) * np.exp(-_t(0.05) / 0.01) * 0.4
    return fx.mix((0, air), (0, knock), (0.16, valve))


def squeak(rng):
    # Rubber stretching: a reedy tone sliding up with a quick wobble, through a rubbery band.
    t = _t(0.3)
    f = 620 * (1.7 ** (t / 0.3)) * (1 + 0.05 * np.sin(2 * np.pi * 23 * t))
    ph = np.cumsum(f) / SR
    tone = np.sin(2 * np.pi * ph) + 0.45 * np.sin(4 * np.pi * ph) + 0.2 * np.sin(6 * np.pi * ph)
    tone = bp(tone, 500, 3500) + hp(rng.uniform(-1, 1, len(t)), 3000) * 0.08
    return tone * np.sin(np.pi * t / 0.3) ** 0.8


def tie_pop(rng):
    # The tie-off: a rubbery pop off the nozzle, the knot's snap and a bright twang up a fifth.
    t = _t(0.12)
    pop = hp(rng.uniform(-1, 1, len(t)), 700) * np.exp(-t / 0.008)
    body = np.sin(2 * np.pi * np.cumsum(220 + 400 * np.exp(-t / 0.01)) / SR) * np.exp(-t / 0.03)
    twang = ins.twang(note("C5"), 0.35, 0.7, rng)
    up = ins.pluck(note("F5"), 0.25, 0.6, rng)
    return fx.mix((0, pop * 0.9 + body * 0.7), (0.05, twang), (0.13, up))


def leak_hiss(rng):
    # Air escaping the neck: a thin hiss that swells and fades.
    t = _t(0.55)
    x = bp(rng.uniform(-1, 1, len(t)), 2500, 7500) + bp(rng.uniform(-1, 1, len(t)), 900, 1600) * 0.25
    return x * np.sin(np.pi * t / 0.55) ** 1.5


def gold_chime(rng):
    # A gold balloon tied: glockenspiel up the F major arpeggio.
    return fx.arp([note("F6"), note("A6"), note("C7"), note("F7")], 0.07, "bells", 0.5, 0.9, rng)


def heat_start(rng):
    # A Race heat starts: the band organ's call, two short and a long.
    return fx.fanfare([(0, 0.5, note("C5")), (0.5, 0.5, note("C5")), (1, 1.5, note("F5"))], BEAT, "organ", rng)


def race_won(rng):
    # A heat won: the organ runs up to the top F, the glockenspiel doubling, with a cymbal.
    notes = [(0, 0.5, note("F5")), (0.5, 0.5, note("A5")), (1, 0.5, note("C6")), (1.5, 2.5, note("F6"))]
    top = fx.fanfare(notes, BEAT, "organ", rng)
    bells = fx.fanfare(notes, BEAT, "bells", rng, vel=0.5)
    under = fx.fanfare([(1.5, 2.5, note("A5")), (1.5, 2.5, note("C5"))], BEAT, "organ", rng, vel=0.6)
    return fx.mix((0, top), (0, bells), (0, under), (1.5 * BEAT, ins.crash(0.6, rng)))


def race_lost(rng):
    # Time's up: a deflating slide down on the organ, wah-wah.
    notes = [(0, 0.75, note("C5")), (0.75, 0.75, note("B4")), (1.5, 0.75, note("Bb4")), (2.25, 2.0, note("A4"))]
    return fx.fanfare(notes, BEAT, "organ", rng)


def last_tick(rng):
    return fx.tick(2600, 0.07, rng)


# Every name starts "pump_": AudioDirector's sound names are global, and other games register theirs.
SFX = {"pump_chuff": pump_chuff, "pump_squeak": squeak, "pump_tie": tie_pop, "pump_hiss": leak_hiss,
       "pump_gold": gold_chime, "pump_heat_start": heat_start, "pump_won": race_won, "pump_lost": race_lost,
       "pump_tick": last_tick}
