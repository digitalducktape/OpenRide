"""Ready for Launch (#82, the music rework): "Moon Shot", space-age surf at 156 bpm in A minor, for
a chunky rocket and a countdown. A galloping floor tom, tambourine and backbeat; a picked gallop
bass; a reverb-drenched twang guitar with a riff the rider hears all through the fuelling; a reedy
combo organ; and a theremin, one gliding voice, singing the hook. Every line shares one motif, a
dotted crotchet, a quaver and a long note reaching up.

Real song form that climbs: an intro, a verse in A minor, a four-bar rising climb on a snare build
and a riser, the chorus breaking into C major, a bridge that drops to tremolo-picked guitar and
builds back, and a final chorus a whole tone higher with horns and thirds. Distinct from the
family: no spy jazz (Safe), no shanty (Tug), no electro-rock (Dodge), no synth-funk (Cadence), no
boogie (The Pull), no carousel (Pump), no indie-pop (Keepy).

The riff lives in the harmony stem, so a rider fuelling hears the tune's skeleton; the theremin and
horns are the lead stem, which opens on the push. Effects are in the key. Written for this repo."""
import numpy as np

import dsp
import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, hp, bp

PREFIX = "Launch"

RIFF = ("A4:0.5 A4:0.25 A4:0.25 C5:0.5 E5:0.5 A5:0.5 G5:0.5 E5:0.5 C5:0.5 |"
        " A4:0.5 A4:0.25 A4:0.25 C5:0.5 E5:0.5 G5:0.5 E5:0.5 C5:0.5 B4:0.5 |"
        " F4:0.5 F4:0.25 F4:0.25 A4:0.5 C5:0.5 F5:0.5 E5:0.5 C5:0.5 A4:0.5 |"
        " G4:0.5 G4:0.25 G4:0.25 B4:0.5 D5:0.5 G5:0.5 F5:0.5 D5:0.5 B4:0.5 |"
        " A4:0.5 A4:0.25 A4:0.25 C5:0.5 E5:0.5 A5:0.5 G5:0.5 E5:0.5 C5:0.5 |"
        " A4:0.5 A4:0.25 A4:0.25 C5:0.5 E5:0.5 G5:0.5 E5:0.5 C5:0.5 B4:0.5 |"
        " F4:0.5 F4:0.25 F4:0.25 A4:0.5 C5:0.5 F5:0.5 E5:0.5 C5:0.5 A4:0.5 |"
        " E4:0.5 E4:0.25 E4:0.25 G#4:0.5 B4:0.5 E5:0.5 D5:0.5 B4:0.5 G#4:0.5")

SONG = dict(
    file="moon_shot", title="Moon Shot", bpm=156, key="A", scale=[0, 2, 3, 5, 7, 8, 11], seed=82,
    drums="surf", bass="gallop", verb_sec=1.5,
    form=([("intro", 4)], [("verse", 8), ("climb", 4), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["Am", "Am", "F", "E7"],
        verse=["Am", "Am", "F", "G", "Am", "Am", "F", "E7"],
        climb=["Dm", "Em", "F", "G7"],
        chorus=["C", "E7", "Am", "F", "D7", "G", "C Am", "Dm G"],
        bridge=["Am", "Em", "F", "C", "Dm", "Am", "E7", "E7"],
        chorus2=["D", "F#7", "Bm", "G", "E7", "A", "D Bm", "Em A"],
    ),
    melody=dict(
        riff=RIFF,
        riff_intro=" | ".join(RIFF.split("|")[i].strip() for i in (0, 1, 2, 7)),
        verse="E5:1.5 A5:0.5 C6:2 | B5:1 A5:1 E5:2 | F5:1.5 A5:0.5 C6:2 | D6:1 B5:1 G5:2 |"
              " E5:1.5 A5:0.5 E6:2 | D6:1 C6:1 A5:2 | C6:1 A5:1 F5:1 A5:1 | G#5:1.5 B5:0.5 E6:2",
        climb="D5:2 F5:2 | E5:2 G5:2 | F5:2 A5:2 | G5:1 B5:1 D6:1 F6:1",
        climb_gtr="D4:4 | E4:4 | F4:4 | G4:2 B4:2",
        chorus="G5:1.5 E5:0.5 C6:2 | B5:1.5 G#5:0.5 E6:2 | A5:1 C6:1 E6:1.5 D6:0.5 | C6:3 r:1 |"
               " F#5:1.5 A5:0.5 D6:2 | B5:1.5 D6:0.5 G6:2 | E6:1 D6:1 C6:1 A5:1 | D6:1.5 C6:0.5 B5:2",
        chorus_gtr="C5:0.5 E5:0.5 G5:0.5 C6:0.5 r:2 | B4:0.5 E5:0.5 G#5:0.5 B5:0.5 r:2 | A4:0.5 C5:0.5 E5:0.5 A5:0.5 r:2 |"
                   " F4:0.5 A4:0.5 C5:0.5 F5:0.5 A5:0.5 F5:0.5 C5:0.5 A4:0.5 | D5:0.5 F#5:0.5 A5:0.5 D6:0.5 r:2 |"
                   " G4:0.5 B4:0.5 D5:0.5 G5:0.5 r:2 | C5:0.5 E5:0.5 G5:0.5 E5:0.5 A4:0.5 C5:0.5 E5:0.5 C5:0.5 |"
                   " D5:0.5 F5:0.5 A5:0.5 F5:0.5 G4:0.5 B4:0.5 D5:0.5 B4:0.5",
        bridge="A4:2 C5:2 | B4:2 G4:2 | A4:2 F4:2 | G4:2 E4:2 | D5:2 F5:2 | C5:2 E5:2 | B4:2 G#4:2 | E5:4",
        bridge_lead="r:4 | E6:1.5 D6:0.5 B5:2 | r:4 | E6:1.5 C6:0.5 G5:2 | r:4 | E6:1.5 C6:0.5 A5:2 | B5:1 D6:1 E6:2 | G#6:4",
    ),
    parts=dict(
        intro=[("lead", "riff_intro", "twang", "gtr", 0, 0.8)],
        # The verse: the riff and off-beat organ under the theremin's call.
        verse=[("lead", "riff", "twang", "gtr", 0, 0.95), ("comp", "surf_chop", 0.6), ("comp", "organ_off", 0.55),
               ("lead", "verse", "theremin", "lead", 0, 0.9)],
        # The climb: guitar tremolo rising, organ held, the theremin stepping up.
        climb=[("lead", "climb_gtr", "surf_trem", "gtr", 0, 0.9), ("comp", "organ_hold", 0.7), ("comp", "stabs_hold", 0.5),
               ("lead", "climb", "theremin", "lead", 0, 0.9)],
        # The chorus: arpeggio breaks answering the hook, big organ, horn stabs; horns double the theremin.
        chorus=[("lead", "chorus_gtr", "twang", "gtr", 0, 0.85), ("comp", "surf_chop", 0.7), ("comp", "organ_hold", 0.7),
                ("comp", "stabs", 0.55), ("lead", "chorus", "theremin", "lead", 0, 1.0), ("lead", "chorus", "brass", "lead2", -12, 0.65)],
        # The bridge: drums halve, tremolo guitar sings, the theremin floats answers, then the build.
        bridge=[("lead", "bridge", "surf_trem", "gtr", 0, 0.9), ("comp", "organ_hold", 0.5),
                ("lead", "bridge_lead", "theremin", "lead", 0, 0.8)],
        # The last chorus: a whole tone up, horns in thirds, a bell counter line.
        chorus2=[("lead", "chorus_gtr", "twang", "gtr", 2, 0.9), ("comp", "surf_chop", 0.75), ("comp", "organ_hold", 0.75),
                 ("comp", "stabs", 0.65), ("lead", "chorus", "theremin", "lead", 2, 1.0),
                 ("lead", "chorus", "brass", "lead2", -10, 0.75, True), ("counter", "bells", "lead2", 0.35)],
    ),
    roles={"chorus2": "chorus", "climb": "pickup"},
    risers=("intro", "climb", "bridge"),
    # The arc: a quiet start, a verse that holds back, the climb, the chorus, a real drop, the top.
    dynamics={"intro": -6.0, "verse": -4.0, "climb": -2.0, "chorus": 0.0, "bridge": -7.0, "chorus2": 1.5},
    lufs_offset=-1.5,
    levels={"perc": -30, "keys": -25, "gtr": -20, "gtr2": -28, "lead": -19.5},
    sends={"gtr": {"verb": 0.42, "delay": 0.1}, "gtr2": {"verb": 0.3}, "lead": {"verb": 0.3, "delay": 0.28},
           "snare": {"room": 0.45, "verb": 0.2}},
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
    tone = np.sin(2 * np.pi * 55.0 * t) * 0.35  # A1, in the key
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
    # One second of the count: a short rounded tone on A5, above the riff.
    return fx.env(_voice(note_hz("A5"), 0.2, rng), 0.008, 0.08) * 1.0


def count_final(rng):
    # The last three: the same voice, longer, with a bell on top.
    v = fx.env(_voice(note_hz("A5"), 0.34, rng), 0.008, 0.14)
    return fx.mix((0, v), (0, ins.bells(note("A6"), 0.3, 0.6, rng) * 0.5))


def note_hz(name):
    return 440.0 * 2.0 ** ((note(name) - 69) / 12.0)


def count_start(rng):
    # The count begins: two rising brass notes and a low drum.
    return fx.mix((0, fx.thud(0.5, 60, 50, rng, 0.8) * 0.8),
                  (0, fx.fanfare([(0, 0.5, note("E4")), (0.5, 1.5, note("A4"))], 0.2, "brass", rng, vel=0.8)))


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
    chord = fx.chord([note("A3"), note("E4"), note("A4"), note("C#5")], 1.2, "brass", 0.8, rng, spread=0.03)
    return fx.mix((0, clanks), (0.18, chord * 0.7))


def stage(rng):
    # Stage separation: a low thud with a pyrotechnic crack and a falling rush.
    n = secs(0.7)
    t = np.arange(n) / SR
    crack = hp(rng.uniform(-1, 1, n), 900) * np.exp(-t / 0.02) * 1.2
    return fx.mix((0, crack), (0, fx.thud(0.6, 70, 80, rng, 1.0) * 1.3), (0.08, fx.whoosh(0.6, 2200, 300, False, rng, 0.2) * 0.5))


def milestone(rng):
    # A milestone: three rising bells on the C major triad, as the chorus opens.
    return fx.arp([note("C6"), note("E6"), note("G6")], 0.09, "bells", 0.5, 0.9, rng)


def moon(rng):
    # The Moon: a full brass fanfare over a bell chord.
    fan = fx.fanfare([(0, 0.5, note("C5")), (0.5, 0.5, note("E5")), (1, 0.5, note("G5")), (1.5, 2.5, note("C6"))], 0.2, "brass", rng, vel=1.0)
    bell = fx.chord([note("C6"), note("G6"), note("C7")], 1.6, "bells", 0.7, rng, spread=0.02)
    return fx.mix((0, fan), (0.3, bell * 0.6))


def touchdown(rng):
    # Touchdown: a soft crunch of dust and a settling thud.
    n = secs(0.5)
    t = np.arange(n) / SR
    dust = lp(rng.uniform(-1, 1, n), 2200) * np.exp(-t / 0.14) * 0.7
    return fx.mix((0, dust), (0.02, fx.thud(0.4, 90, 50, rng, 0.8)), (0.2, ins.bells(note("E6"), 0.4, 0.5, rng) * 0.4))


def tank_full(rng):
    # The tank's full: a valve clunk and two bright notes.
    return fx.mix((0, fx.thud(0.18, 180, 80, rng, 1.0) * 0.7), (0.05, fx.arp([note("E5"), note("A5")], 0.1, "bells", 0.5, 0.9, rng)))


def cutoff(rng):
    # Engines off: the rush falling away with a soft low note.
    return fx.mix((0, fx.whoosh(0.9, 1800, 240, False, rng, 0.1) * 0.7), (0.05, ins.bells(note("A4"), 0.5, 0.5, rng) * 0.5))


def scrub(rng):
    # A scrub: two low falling tones.
    a = fx.env(fx.sweep(0.34, 220, 196, "sine"), 0.01, 0.14)
    b = fx.env(fx.sweep(0.5, 174.6, 146.8, "sine"), 0.01, 0.24)
    return fx.mix((0, a), (0.32, b))


def result(rng):
    # The launch's result: a warm rising chord.
    return fx.chord([note("A4"), note("E5"), note("A5")], 0.9, "bells", 0.7, rng, spread=0.05)


SFX = {"rfl_" + k: v for k, v in {
    "hiss": hiss, "engine": engine, "count": count, "count_final": count_final, "count_start": count_start,
    "ignition": ignition, "liftoff": liftoff, "stage": stage, "milestone": milestone, "moon": moon,
    "touchdown": touchdown, "tank_full": tank_full, "cutoff": cutoff, "scrub": scrub, "result": result}.items()}
