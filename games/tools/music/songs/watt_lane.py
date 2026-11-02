"""Watt Lane (#78): "Night Current", synthwave at 104 bpm in F minor, for a glowing highway at
night. Kick on 1 and 3 and a big snare-and-clap backbeat, a pulsing eighth-note synth bass, a
wide pad and a plucked arpeggio; an analog-style lead in the verse and a supersaw hook in the
chorus. The harmony plays while the rider is near the lane, the lead only in it (the "hum that
brightens"). The effects are in the song's key: the jump chime (announce), the 3-2-1 ticks, the
lane's shift, a catch, a miss, the off-lane buzz and a streak step. Written for this repo."""
import numpy as np

import instruments as ins
import sfx as fx
from compose import note

PREFIX = "WattLane"

SONG = dict(
    file="night_current", title="Night Current", bpm=104, key="F", scale=[0, 2, 3, 5, 7, 8, 10], seed=78,
    drums="synthwave", bass="pulse", verb_sec=2.2,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Fm", "Fm", "Db", "Eb"],
        verse=["Fm", "Db", "Ab", "Eb", "Fm", "Db", "Ab", "C"],
        chorus=["Db", "Ab", "Eb", "Fm", "Db", "Ab", "Eb", "C"],
        bridge=["Bbm", "Fm", "Db", "Eb", "Bbm", "Fm", "Db", "C"],
    ),
    melody=dict(
        verse="C5:1 Ab4:0.5 F4:0.5 C5:1 Eb5:1 | Db5:1.5 C5:0.5 Ab4:1 r:1 |"
              " Eb5:1 C5:0.5 Ab4:0.5 Eb5:1 F5:1 | G5:1.5 F5:0.5 Eb5:1 r:1 |"
              " C5:1 Ab4:0.5 F4:0.5 C5:1 F5:1 | Ab5:1.5 F5:0.5 Db5:1 r:1 |"
              " C5:0.5 Eb5:0.5 Ab5:1 G5:1 Eb5:1 | E5:2 G5:1 r:1",
        chorus="F5:1 Ab5:1 Db6:1.5 C6:0.5 | C6:1 Ab5:1 Eb5:2 | Bb5:1 G5:0.5 Eb5:0.5 G5:1 Bb5:1 | C6:3 r:1 |"
               " F5:1 Ab5:1 Db6:1.5 Eb6:0.5 | F6:1 Eb6:1 C6:2 | Bb5:0.5 C6:0.5 Bb5:0.5 G5:0.5 Eb5:1 G5:1 |"
               " E5:2 G5:1 C6:1",
        bridge="F5:2 Db5:2 | C5:2 Ab4:2 | Db5:1 F5:1 Ab5:2 | G5:3 r:1 | Bb5:2 F5:2 | Ab5:2 C5:2 |"
               " Db5:1 Eb5:1 F5:2 | E5:2 G5:2",
    ),
    parts=dict(
        intro=[("comp", "pad", 0.7), ("comp", "arp", 0.45)],
        verse=[("comp", "pad", 0.75), ("comp", "arp", 0.6), ("lead", "verse", "analog", "lead", 0, 0.85)],
        chorus=[("comp", "pad", 0.8), ("comp", "arp", 0.65),
                ("lead", "chorus", "supersaw", "lead", 0, 0.9), ("lead", "chorus", "analog", "lead2", -12, 0.5)],
        bridge=[("comp", "pad", 0.9), ("lead", "bridge", "strings", "lead", 0, 0.8)],
        chorus2=[("comp", "pad", 0.8), ("comp", "arp", 0.65),
                 ("lead", "chorus", "supersaw", "lead", 0, 0.9, True), ("counter", "strings", "lead2", 0.5)],
    ),
)


def jump_chime(rng):
    # A jump is announced: two bells up a fourth over a soft pad swell, clear above the music.
    swell = fx.env(fx.sweep(0.7, 349, 349, "saw") * 0.12 + fx.sweep(0.7, 523, 523) * 0.2, 0.25, 0.3)
    return fx.mix((0, fx.bp(swell, 300, 2500)), (0.0, ins.bells(note("C6"), 0.25, 1.0, rng)),
                  (0.13, ins.bells(note("F6"), 0.45, 1.0, rng)))


def count_tick(rng):
    # 3, 2, 1: a short bell ping on the key note over a tick, bright enough to cut through.
    return fx.mix((0, fx.tick(4200, 0.04, rng) * 0.4), (0, ins.bells(note("F6"), 0.18, 1.0, rng)),
                  (0, ins.pluck(note("C6"), 0.12, 0.8, rng)))


def lane_shift(rng):
    # The lane jumps: a rush of air sweeping up, and a low synth thump.
    return fx.mix((0, fx.whoosh(0.55, 500, 5000, True, rng, 0.55)), (0.0, fx.thud(0.3, 70, 40, rng, 0.2) * 0.5))


def caught(rng):
    # Caught it: a bright F major arpeggio (the lift from the minor key) on bells and supersaw.
    notes = [note(n) for n in ("F5", "A5", "C6", "F6")]
    return fx.mix((0, fx.arp(notes, 0.05, "bells", 0.3, 1.0, rng)), (0, fx.arp(notes, 0.05, "supersaw", 0.25, 0.35, rng)))


def missed(rng):
    # Missed the jump: a soft synth falling a minor third, no alarm.
    return fx.env(fx.sweep(0.4, note_hz("Ab4"), note_hz("F4"), "saw") * 0.25 + fx.sweep(0.4, note_hz("Ab3"), note_hz("F3")) * 0.4, 0.01, 0.2)


def off_buzz(rng):
    # Off the lane: a short, soft, low buzz (filtered saw), never harsh.
    x = fx.sweep(0.32, 110.0, 104.0, "saw") * 0.5 + fx.sweep(0.32, 220.0, 208.0, "square") * 0.15
    return fx.env(fx.bp(x, 120, 900), 0.02, 0.15)


def streak_up(rng):
    # The streak steps up: two quick plucks up a fifth.
    return fx.mix((0, ins.pluck(note("C6"), 0.1, 0.8, rng)), (0.07, ins.pluck(note("G6"), 0.18, 0.9, rng)))


def note_hz(name):
    return 440.0 * 2 ** ((note(name) - 69) / 12)


SFX = {"jump_chime": jump_chime, "count_tick": count_tick, "lane_shift": lane_shift, "caught": caught,
       "missed": missed, "off_buzz": off_buzz, "streak_up": streak_up}
