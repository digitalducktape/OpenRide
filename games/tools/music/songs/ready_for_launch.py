"""Ready for Launch (#82): "First Light", orchestral-synth at 104 bpm in D minor turning to D major in
the chorus, for a rocket on the pad at dawn. Pulsing low strings and a sub bass under a timpani
figure, a pad choir, a slow horn line that opens into a soaring brass and supersaw theme, bells
counting over the top. Real song form: an intro, a tense verse, a lift, a second verse with a
counter line, a bridge that drops to the pad and builds back on a riser, then the big final chorus.
Distinct from the family: no spy jazz (Safe), no shanty (Tug), no electro-rock (Dodge), no synth-funk
(Cadence), no carousel (Pump), no indie-pop (Keepy).

The harmony comes in with fuel flowing, the lead on the push.

Effects, in the key: the fuel line's hiss and the engine (seamless loops the game pitches), the
countdown's tone "voice" (a formant-shaped tone, no speech: the game pitches it up a semitone a
second), the ignition, the liftoff's clamps letting go, a stage's thud, a milestone's bell, the
Moon's fanfare, touchdown, tank full, the engine cut-off, a scrub and the launch's result.
Written for this repo."""
import numpy as np

import dsp
import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, hp, bp

PREFIX = "Launch"

SONG = dict(
    file="first_light", title="First Light", bpm=104, key="D", scale=[0, 2, 3, 5, 7, 8, 10], seed=82,
    drums="cinematic", bass="sub", verb_sec=2.6,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("verse2", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Dm", "Bb", "Gm", "A"],
        verse=["Dm", "Bb", "F", "C", "Dm", "Bb", "Gm", "A"],
        chorus=["D", "A", "Bm", "G", "D", "A", "G", "A"],
        bridge=["Bm", "G", "D", "A", "Bm", "G", "Em7", "A7sus4"],
    ),
    melody=dict(
        verse="D5:3 F5:1 | A5:2 G5:2 | F5:3 E5:1 | C5:4 | D5:2 F5:2 | Bb5:3 A5:1 | G5:2 E5:2 | A4:3 r:1",
        chorus="A5:2 D6:2 | E6:3 C#6:1 | D6:2 B5:2 | G5:3 r:1 | A5:2 D6:2 | F#6:3 E6:1 | D6:2 B5:1 G5:1 | A5:3 r:1",
        bridge="F#5:2 D5:2 | G5:2 B5:2 | A5:2 F#5:2 | E5:3 r:1 | F#5:1 A5:1 D6:2 | B5:2 G5:2 | E5:1 G5:1 B5:2 | A5:4",
    ),
    parts=dict(
        intro=[("comp", "pad", 0.6), ("comp", "arp", 0.35)],
        verse=[("comp", "ostinato", 0.8), ("comp", "pad", 0.5), ("comp", "arp", 0.35), ("lead", "verse", "brass", "lead", -12, 0.8)],
        chorus=[("comp", "ostinato", 0.85), ("comp", "pad", 0.6), ("comp", "arp", 0.5), ("comp", "stabs", 0.5),
                ("lead", "chorus", "brass", "lead", 0, 0.9), ("lead", "chorus", "bells", "lead2", 12, 0.4)],
        verse2=[("comp", "ostinato", 0.8), ("comp", "pad", 0.55), ("comp", "arp", 0.5), ("lead", "verse", "strings", "lead", 0, 0.85),
                ("counter", "bells", "lead2", 0.4)],
        bridge=[("comp", "pad", 0.7), ("lead", "bridge", "strings", "lead", 0, 0.8)],
        chorus2=[("comp", "ostinato", 0.9), ("comp", "pad", 0.65), ("comp", "arp", 0.6), ("comp", "stabs", 0.55),
                 ("lead", "chorus", "supersaw", "lead", 0, 0.85, True), ("lead", "chorus", "brass", "lead2", -12, 0.6),
                 ("counter", "bells", "lead2", 0.35)],
    ),
    roles={"verse2": "verse", "chorus2": "chorus"},
    risers=("intro", "bridge"),
    levels={"perc": -29, "keys": -23},
)


def _loop(x, fade_sec=0.25):
    """A seamless loop of `x`: its tail crossfaded into its head (equal power), the tail cut."""
    f = secs(fade_sec)
    body = x[:-f].copy()
    ramp = np.linspace(0.0, 1.0, f)
    body[:f] = x[:f] * np.sqrt(ramp) + x[-f:] * np.sqrt(1.0 - ramp)
    return body


def hiss(rng):
    # The fuel line: cold gas through a pipe, a breathy hiss with a slow flutter. A 3 s loop.
    n = secs(3.25)
    t = np.arange(n) / SR
    air = bp(rng.uniform(-1, 1, n), 1800, 7500) * (0.75 + 0.15 * np.sin(2 * np.pi * 3.0 * t))
    gurgle = bp(rng.uniform(-1, 1, n), 220, 620) * 0.35
    return _loop(air * 0.7 + gurgle)


def engine(rng):
    # The engine: a wide low roar with a crackle on top. A 3 s loop the game pitches with thrust.
    n = secs(3.25)
    t = np.arange(n) / SR
    low = lp(rng.uniform(-1, 1, n), 170) * 2.4
    mid = bp(rng.uniform(-1, 1, n), 200, 900) * (0.7 + 0.3 * np.sin(2 * np.pi * 9.0 * t))
    crackle = hp(rng.uniform(-1, 1, n), 1800) * (rng.uniform(0, 1, n) > 0.985) * 1.2
    tone = np.sin(2 * np.pi * 73.42 * t) * 0.35  # D2, in the key
    return _loop(low + mid * 0.8 + crackle * 0.35 + tone)


def _voice(f0, sec, rng):
    # A tone with vowel-like formants: a sawtooth through two resonances. A machine's count, not
    # a word: there is no speech in it.
    n = secs(sec)
    t = np.arange(n) / SR
    saw = 2.0 * ((t * f0) % 1.0) - 1.0
    shaped = bp(saw, 500, 900) * 1.5 + bp(saw, 1300, 1900) * 0.9 + saw * 0.12
    return shaped


def count(rng):
    # One second of the count: a short rounded tone on D5.
    return fx.env(_voice(note_hz("D5"), 0.2, rng), 0.008, 0.08) * 1.0


def count_final(rng):
    # The last three: the same voice, longer, with a bell on top.
    v = fx.env(_voice(note_hz("D5"), 0.34, rng), 0.008, 0.14)
    return fx.mix((0, v), (0, ins.bells(note("D6"), 0.3, 0.6, rng) * 0.5))


def note_hz(name):
    return 440.0 * 2.0 ** ((note(name) - 69) / 12.0)


def count_start(rng):
    # The count begins: two rising brass notes and a low drum.
    return fx.mix((0, fx.thud(0.5, 60, 50, rng, 0.8) * 0.8),
                  (0, fx.fanfare([(0, 0.5, note("A4")), (0.5, 1.5, note("D5"))], 0.2, "brass", rng, vel=0.8)))


def ignition(rng):
    # Zero: a deep boom and a tearing rush of flame.
    n = secs(1.6)
    t = np.arange(n) / SR
    boom = fx.thud(1.2, 55, 70, rng, 1.0) * 1.4
    tear = bp(rng.uniform(-1, 1, n), 300, 4200) * np.minimum(t / 0.08, 1.0) * np.exp(-t / 0.55) * 0.9
    return fx.mix((0, tear), (0, boom))


def liftoff(rng):
    # The clamps let go: heavy steel clanks, then a brass chord lifting.
    clanks = fx.mix((0, fx.thud(0.3, 110, 60, rng, 1.0)), (0.11, fx.tick(1400, 0.06, rng) * 0.7),
                    (0.16, fx.thud(0.28, 130, 60, rng, 1.0) * 0.8))
    chord = fx.chord([note("D4"), note("A4"), note("D5"), note("F#5")], 1.2, "brass", 0.8, rng, spread=0.03)
    return fx.mix((0, clanks), (0.18, chord * 0.7))


def stage(rng):
    # Stage separation: a low thud with a pyrotechnic crack and a falling rush.
    n = secs(0.7)
    t = np.arange(n) / SR
    crack = hp(rng.uniform(-1, 1, n), 900) * np.exp(-t / 0.02) * 1.2
    return fx.mix((0, crack), (0, fx.thud(0.6, 70, 80, rng, 1.0) * 1.3), (0.08, fx.whoosh(0.6, 2200, 300, False, rng, 0.2) * 0.5))


def milestone(rng):
    # A milestone: three rising bells on the D major triad.
    return fx.arp([note("D6"), note("F#6"), note("A6")], 0.09, "bells", 0.5, 0.9, rng)


def moon(rng):
    # The Moon: a full brass fanfare over a bell chord.
    fan = fx.fanfare([(0, 0.5, note("D5")), (0.5, 0.5, note("F#5")), (1, 0.5, note("A5")), (1.5, 2.5, note("D6"))], 0.2, "brass", rng, vel=1.0)
    bell = fx.chord([note("D6"), note("A6"), note("D7")], 1.6, "bells", 0.7, rng, spread=0.02)
    return fx.mix((0, fan), (0.3, bell * 0.6))


def touchdown(rng):
    # Touchdown: a soft crunch of dust and a settling thud.
    n = secs(0.5)
    t = np.arange(n) / SR
    dust = lp(rng.uniform(-1, 1, n), 2200) * np.exp(-t / 0.14) * 0.7
    return fx.mix((0, dust), (0.02, fx.thud(0.4, 90, 50, rng, 0.8)), (0.2, ins.bells(note("A6"), 0.4, 0.5, rng) * 0.4))


def tank_full(rng):
    # The tank's full: a valve clunk and two bright notes.
    return fx.mix((0, fx.thud(0.18, 180, 80, rng, 1.0) * 0.7), (0.05, fx.arp([note("A5"), note("D6")], 0.1, "bells", 0.5, 0.9, rng)))


def cutoff(rng):
    # Engines off: the rush falling away with a soft low note.
    return fx.mix((0, fx.whoosh(0.9, 1800, 240, False, rng, 0.1) * 0.7), (0.05, ins.bells(note("D5"), 0.5, 0.5, rng) * 0.5))


def scrub(rng):
    # A scrub: two low falling tones.
    a = fx.env(fx.sweep(0.34, 220, 196, "sine"), 0.01, 0.14)
    b = fx.env(fx.sweep(0.5, 174.6, 146.8, "sine"), 0.01, 0.24)
    return fx.mix((0, a), (0.32, b))


def result(rng):
    # The launch's result: a warm rising chord.
    return fx.chord([note("D5"), note("A5"), note("D6")], 0.9, "bells", 0.7, rng, spread=0.05)


SFX = {"rfl_" + k: v for k, v in {
    "hiss": hiss, "engine": engine, "count": count, "count_final": count_final, "count_start": count_start,
    "ignition": ignition, "liftoff": liftoff, "stage": stage, "milestone": milestone, "moon": moon,
    "touchdown": touchdown, "tank_full": tank_full, "cutoff": cutoff, "scrub": scrub, "result": result}.items()}
