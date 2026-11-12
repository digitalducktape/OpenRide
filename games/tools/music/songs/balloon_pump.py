"""Balloon Pump (#76; the audio rework of 2026-11-02, AUDIO_POLISH.md): "Midnight Carousel", a
swung band-organ waltz-march at 126 bpm in D minor, for a balloon pump at the fair after dark. A
light pop kit with swing, an oom-pah root-fifth bass, an accordion oom-pah, plucked arpeggios and
vibes as the carousel's works; a calliope (pipe organ) tune with a glockenspiel counter-line in the
verse; the chorus turns to F major with the organ in harmony over brass stabs and a pad, the
glockenspiel an octave up; the bridge drops to a flute over held accordion, then builds back.
Distinct from Tug of War's stomp-clap shanty and Safe Cracker's spy jazz. Written for this repo;
no existing tune is quoted.

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
    file="midnight_carousel", title="Midnight Carousel", bpm=126, key="D", scale=[0, 2, 3, 5, 7, 8, 10], seed=76,
    drums="pop", bass="root5", swing=0.1, verb_sec=1.8,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Dm", "Dm", "A7", "A7"],
        verse=["Dm", "A7", "A7", "Dm", "Gm", "Dm", "A7", "Dm"],
        chorus=["F", "C", "Dm", "A7", "Bb", "F", "Gm A7", "Dm"],
        bridge=["Gm", "Dm", "Bb", "A7", "Gm", "Dm", "E7", "A7"],
    ),
    melody=dict(
        verse="A4:0.5 D5:0.5 F5:0.5 A5:0.5 A5:1 G5:0.5 F5:0.5 | E5:0.5 C#5:0.5 E5:0.5 G5:0.5 A5:2 |"
              " G5:0.5 E5:0.5 C#5:0.5 E5:0.5 G5:1 F5:0.5 E5:0.5 | F5:1 D5:1 A4:2 |"
              " Bb4:0.5 D5:0.5 G5:0.5 Bb5:0.5 A5:1 G5:1 | F5:0.5 A5:0.5 D6:0.5 A5:0.5 F5:2 |"
              " E5:0.5 G5:0.5 Bb5:0.5 A5:0.5 G5:1 E5:1 | D5:3 r:1",
        chorus="C6:1 A5:0.5 C6:0.5 F6:1 C6:1 | E5:1 G5:0.5 C6:0.5 E6:2 | D6:1 A5:0.5 D6:0.5 F6:1 D6:1 |"
               " C#6:1 A5:1 E5:2 | D6:1 Bb5:0.5 D6:0.5 F6:1 D6:1 | C6:1 A5:1 F5:2 |"
               " G5:0.5 Bb5:0.5 D6:0.5 G5:0.5 A5:0.5 C#6:0.5 E6:0.5 A5:0.5 | D6:2 r:2",
        bridge="G5:2 Bb5:2 | A5:2 F5:2 | D5:1 F5:1 Bb5:2 | A5:3 r:1 | G5:1 A5:1 Bb5:1 D6:1 | A5:2 F5:2 |"
               " G#5:1 B5:1 D6:1 E6:1 | C#6:2 A5:2",
    ),
    parts=dict(
        intro=[("comp", "arp", 0.6), ("comp", "vibes", 0.5)],
        verse=[("comp", "oompah", 0.8), ("comp", "arp", 0.45), ("lead", "verse", "organ", "lead", 0, 0.9),
               ("counter", "bells", "lead2", 0.35)],
        chorus=[("comp", "oompah", 0.85), ("comp", "stabs", 0.45), ("comp", "pad", 0.35),
                ("lead", "chorus", "organ", "lead", 0, 0.95, True), ("lead", "chorus", "bells", "lead2", 12, 0.45)],
        bridge=[("comp", "acc_hold", 0.6), ("comp", "vibes", 0.6), ("comp", "pad", 0.45),
                ("lead", "bridge", "flute", "lead", 0, 0.85), ("counter", "pluck", "lead2", 0.4)],
        chorus2=[("comp", "oompah", 0.9), ("comp", "stabs", 0.5), ("comp", "arp", 0.4),
                 ("lead", "chorus", "organ", "lead", 0, 0.95, True), ("lead", "chorus", "whistle", "lead2", 12, 0.4)],
    ),
    levels={"cym": -30, "perc": -30, "lead2": -24},
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
    twang = ins.twang(note("D5"), 0.35, 0.7, rng)
    up = ins.pluck(note("A5"), 0.25, 0.6, rng)
    return fx.mix((0, pop * 0.9 + body * 0.7), (0.05, twang), (0.13, up))


def leak_hiss(rng):
    # Air escaping the neck: a thin hiss that swells and fades.
    t = _t(0.55)
    x = bp(rng.uniform(-1, 1, len(t)), 2500, 7500) + bp(rng.uniform(-1, 1, len(t)), 900, 1600) * 0.25
    return x * np.sin(np.pi * t / 0.55) ** 1.5


def gold_chime(rng):
    # A gold balloon tied: glockenspiel up the D major arpeggio (the minor key lifts).
    return fx.arp([note("D6"), note("F#6"), note("A6"), note("D7")], 0.07, "bells", 0.5, 0.9, rng)


def heat_start(rng):
    # A Race heat starts: the band organ's call, two short and a long.
    return fx.fanfare([(0, 0.5, note("A4")), (0.5, 0.5, note("A4")), (1, 1.5, note("D5"))], BEAT, "organ", rng)


def race_won(rng):
    # A heat won: the organ runs up to D major (a lift out of the minor), the glockenspiel doubling.
    notes = [(0, 0.5, note("D5")), (0.5, 0.5, note("F#5")), (1, 0.5, note("A5")), (1.5, 2.5, note("D6"))]
    top = fx.fanfare(notes, BEAT, "organ", rng)
    bells = fx.fanfare(notes, BEAT, "bells", rng, vel=0.5)
    under = fx.fanfare([(1.5, 2.5, note("F#5")), (1.5, 2.5, note("A4"))], BEAT, "organ", rng, vel=0.6)
    return fx.mix((0, top), (0, bells), (0, under), (1.5 * BEAT, ins.crash(0.6, rng)))


def race_lost(rng):
    # Time's up: a deflating slide down on the organ, wah-wah.
    notes = [(0, 0.75, note("A4")), (0.75, 0.75, note("G#4")), (1.5, 0.75, note("G4")), (2.25, 2.0, note("F4"))]
    return fx.fanfare(notes, BEAT, "organ", rng)


def last_tick(rng):
    return fx.tick(2600, 0.07, rng)


# Every name starts "pump_": AudioDirector's sound names are global, and other games register theirs.
SFX = {"pump_chuff": pump_chuff, "pump_squeak": squeak, "pump_tie": tie_pop, "pump_hiss": leak_hiss,
       "pump_gold": gold_chime, "pump_heat_start": heat_start, "pump_won": race_won, "pump_lost": race_lost,
       "pump_tick": last_tick}
