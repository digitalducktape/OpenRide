"""Watt Lane (#78): "Live Wire", bright dream-pop electronica at 112 bpm in Eb major, for a lit
lane through a dark field. Signature sounds: a glockenspiel hook over a flute in the verse, eighth
-note piano and a plucked arpeggio rippling under it, sleigh-bell sparkle in the drums, an octave
picked bass; a supersaw hook with brass stabs in the chorus; strings in the bridge. Extended
harmony (major sevenths, minor sevenths, sus chords) keeps it warm rather than generic. Real
song form: intro, verse, chorus, bridge (half-time, then a build), chorus with the harmony line.
The harmony stem plays while the rider is near the lane, the lead only in it. Written for this
repo; everything is synthesised by games/tools/music."""
import instruments as ins
import sfx as fx
from compose import note

PREFIX = "WattLane"

SONG = dict(
    file="live_wire", title="Live Wire", bpm=112, key="Eb", scale=[0, 2, 4, 5, 7, 9, 11], seed=78,
    drums="pop", bass="octave", verb_sec=2.0,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Ebmaj7", "Ebmaj7", "Abmaj7", "Bb7sus4"],
        verse=["Ebmaj7", "Cm7", "Abmaj7", "Bb7", "Ebmaj7", "Gm7", "Abmaj7", "Bb7sus4"],
        chorus=["Abmaj7", "Bb", "Gm7", "Cm7", "Abmaj7", "Bb", "Eb", "Eb"],
        bridge=["Cm7", "Gm7", "Abmaj7", "Ebmaj7", "Fm7", "Gm7", "Abmaj7", "Bb7"],
    ),
    melody=dict(
        verse="G5:1 Bb5:0.5 G5:0.5 F5:1 Eb5:1 | G5:1.5 C6:0.5 Bb5:1 r:1 | C6:1 Bb5:0.5 Ab5:0.5 G5:1 Eb5:1 |"
              " F5:2 D5:1 r:1 | G5:1 Bb5:0.5 G5:0.5 F5:1 Eb5:1 | D6:1.5 C6:0.5 Bb5:1 r:1 |"
              " C6:0.5 Bb5:0.5 Ab5:1 G5:1 F5:1 | Eb5:2 F5:1 r:1",
        chorus="Eb6:1 C6:1 Ab5:1.5 Bb5:0.5 | D6:1 Bb5:1 F5:2 | G5:1 Bb5:0.5 D6:0.5 F6:1 D6:1 | Eb6:3 r:1 |"
               " Eb6:1 C6:1 Ab5:1.5 Bb5:0.5 | D6:1 F6:1 Bb5:2 | G6:1 F6:0.5 Eb6:0.5 D6:1 Bb5:1 | Eb6:3 r:1",
        bridge="G5:2 Eb5:2 | D5:2 Bb4:2 | C5:1 Eb5:1 G5:2 | G5:3 r:1 | Ab5:2 F5:2 | Bb5:2 G5:2 |"
               " C6:1 Bb5:1 Ab5:2 | D6:2 F5:2",
    ),
    parts=dict(
        intro=[("comp", "pad", 0.6), ("comp", "arp", 0.45)],
        verse=[("comp", "piano8", 0.55), ("comp", "pad", 0.45), ("comp", "arp", 0.4),
               ("lead", "verse", "bells", "lead", 0, 0.9), ("lead", "verse", "flute", "lead2", -12, 0.5)],
        chorus=[("comp", "piano", 0.7), ("comp", "pad", 0.6), ("comp", "arp", 0.55), ("comp", "stabs", 0.5),
                ("lead", "chorus", "supersaw", "lead", 0, 0.9), ("lead", "chorus", "bells", "lead2", 12, 0.4)],
        bridge=[("comp", "pad", 0.85), ("comp", "ep_hold", 0.5), ("lead", "bridge", "strings", "lead", 0, 0.85)],
        chorus2=[("comp", "piano", 0.7), ("comp", "pad", 0.6), ("comp", "arp", 0.55), ("comp", "stabs", 0.5),
                 ("lead", "chorus", "supersaw", "lead", 0, 0.9, True), ("counter", "bells", "lead2", 0.45)],
    ),
)

BEAT = 60 / 112


def jump_chime(rng):
    # A step is announced: two glockenspiel notes up a fourth over a soft swell (in the key).
    swell = fx.env(fx.sweep(0.7, 311, 311, "saw") * 0.1 + fx.sweep(0.7, 466, 466) * 0.2, 0.25, 0.3)
    return fx.mix((0, fx.bp(swell, 300, 2500)), (0.0, ins.bells(note("Bb5"), 0.25, 1.0, rng)),
                  (0.13, ins.bells(note("Eb6"), 0.45, 1.0, rng)))


def count_tick(rng):
    # 3, 2, 1: a short bell ping on the key note over a tick, bright enough to cut through.
    return fx.mix((0, fx.tick(4200, 0.04, rng) * 0.4), (0, ins.bells(note("Eb6"), 0.18, 1.0, rng)),
                  (0, ins.pluck(note("Bb5"), 0.12, 0.8, rng)))


def lane_shift(rng):
    # The lane steps: a quick rising shimmer of light and a soft low thump.
    up = fx.env(fx.sweep(0.4, 600, 2400, "saw") * 0.12 + fx.sweep(0.4, 1200, 4800) * 0.25, 0.02, 0.2)
    return fx.mix((0, fx.whoosh(0.45, 700, 5000, True, rng, 0.5) * 0.7), (0, up), (0, fx.thud(0.25, 70, 40, rng, 0.2) * 0.4))


def caught(rng):
    # Caught it: an Eb major arpeggio sparkling up, bells over supersaw.
    notes = [note(n) for n in ("Eb5", "G5", "Bb5", "Eb6")]
    return fx.mix((0, fx.arp(notes, 0.05, "bells", 0.3, 1.0, rng)), (0, fx.arp(notes, 0.05, "supersaw", 0.25, 0.35, rng)))


def missed(rng):
    # Missed the step: a soft synth sighing down a minor third, no alarm.
    return fx.env(fx.sweep(0.4, _hz("G4"), _hz("Eb4"), "saw") * 0.25 + fx.sweep(0.4, _hz("G3"), _hz("Eb3")) * 0.4, 0.01, 0.2)


def off_buzz(rng):
    # Off the lane: a short, soft, low buzz (filtered saw), never harsh.
    x = fx.sweep(0.32, 104.0, 98.0, "saw") * 0.5 + fx.sweep(0.32, 208.0, 196.0, "square") * 0.15
    return fx.env(fx.bp(x, 120, 900), 0.02, 0.15)


def streak_up(rng):
    # The streak steps up: two quick plucks up a fifth.
    return fx.mix((0, ins.pluck(note("Bb5"), 0.1, 0.8, rng)), (0.07, ins.pluck(note("F6"), 0.18, 0.9, rng)))


def _hz(name):
    return 440.0 * 2 ** ((note(name) - 69) / 12)


SFX = {"jump_chime": jump_chime, "count_tick": count_tick, "lane_shift": lane_shift, "caught": caught,
       "missed": missed, "off_buzz": off_buzz, "streak_up": streak_up}
