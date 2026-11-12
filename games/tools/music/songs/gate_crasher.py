"""Gate Crasher (#80): "Clear Round", a show-ring galop at 138 bpm in G major for a morning in the
arena. The hook is the gallop itself: a long-short-short figure leaping to a fanfare, called by
the brass and answered by a tin whistle in the gaps. A horn call opens it; a clip-clop of congas
runs under the verses and choruses; the flute sings the verses (each ends teasing the hook); the
bridge drops to E minor on strings, half time, then climbs on the same figure over a snare roll,
and the last chorus lifts a whole tone to A before a turnaround back to G. The harmony comes in at
a canter, the lead with the ride going well. Written for this repo: no samples, nothing borrowed.

The effects are the arena's: a three-beat canter stride the game plays once per stride, the
countdown tick and take-off chime, the lift and landing, a rail clatter, applause and the clear
round's fanfare, which quotes the hook."""
import numpy as np

import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, lp, bp, hp

PREFIX = "Gate"

HOOK = ("G5:0.5 G5:0.25 G5:0.25 C6:1 E6:1.5 D6:0.5 | D6:0.5 D6:0.25 D6:0.25 B5:1 G5:2 |"
        " A5:0.5 A5:0.25 A5:0.25 D6:1 F#6:1.5 E6:0.5 | E6:0.5 E6:0.25 E6:0.25 B5:1 G5:1 r:1 |"
        " G5:0.5 G5:0.25 G5:0.25 C6:1 E6:1 G6:1 | F#6:0.5 E6:0.25 D6:0.25 B5:1 G5:2 |"
        " C6:0.5 C6:0.25 C6:0.25 E6:1 D6:0.5 D6:0.25 D6:0.25 F#6:1 | G6:1 D6:0.5 B5:0.5 G5:1 r:1")

SONG = dict(
    file="clear_round", title="Clear Round", bpm=138, key="G", scale=[0, 2, 4, 5, 7, 9, 11], seed=80,
    drums="drive", bass="octave", verb_sec=1.5,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("verse2", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["G", "G", "C D", "G"],
        verse=["G", "D", "Em", "C", "G", "D", "C D", "G"],
        chorus=["C", "G", "D", "Em", "C", "G", "Am D", "G"],
        bridge=["Em", "C", "Am", "B7", "Em", "C", "D", "E7"],
        # The last chorus, a whole tone up; its last bar turns back to G for the loop.
        chorus2=["D", "A", "E", "F#m", "D", "A", "Bm E", "A D7"],
    ),
    melody=dict(
        # The horn call, then the hook's first figure twice.
        intro="D5:0.5 G5:0.5 B5:1 D6:2 | B5:0.5 D6:0.5 G6:1 D6:2 |"
              " G5:0.5 G5:0.25 G5:0.25 C6:1 A5:0.5 A5:0.25 A5:0.25 D6:1 | G5:0.5 G5:0.25 G5:0.25 B5:0.5 D6:0.5 G6:1 r:1",
        verse="B5:1 D6:0.5 B5:0.5 G5:1 A5:0.5 B5:0.5 | A5:1.5 F#5:0.5 D5:2 |"
              " G5:1 B5:0.5 G5:0.5 E5:1 F#5:0.5 G5:0.5 | E5:1.5 C5:0.5 G4:1 r:1 |"
              " B5:1 D6:0.5 B5:0.5 G6:1 F#6:0.5 E6:0.5 | D6:1.5 A5:0.5 F#5:2 |"
              " E6:1 C6:1 D6:0.5 C6:0.5 A5:1 | G5:0.5 G5:0.25 G5:0.25 B5:0.5 D6:0.5 G6:1 r:1",
        chorus=HOOK,
        # The whistle's answers, in the gaps the hook leaves.
        answer="r:4 | r:2 B5:0.5 C6:0.5 D6:1 | r:4 | r:2 E6:0.5 F#6:0.5 G6:1 | r:4 | r:2 D6:0.5 E6:0.5 G6:1 |"
               " r:4 | r:3 D6:0.25 E6:0.25 F#6:0.5",
        bridge="G5:2 B5:2 | C6:2 E5:2 | A5:1 C6:1 E6:2 | D#6:3 r:1 | G5:2 B5:2 | E6:2 C6:2 |"
               " F#6:2 A6:2 | G#6:2 B6:2",
        # The climb: the hook's figure, on brass over the last two bars of the bridge.
        climb="r:4 | r:4 | r:4 | r:4 | r:4 | r:4 | D6:0.5 D6:0.25 D6:0.25 F#6:1 D6:0.5 D6:0.25 D6:0.25 A6:1 |"
              " E6:0.5 E6:0.25 E6:0.25 G#6:1 E6:0.5 E6:0.25 E6:0.25 B6:1",
    ),
    parts=dict(
        # On the brass bus, so the call sounds over the intro card (the harmony stem, not the lead).
        intro=[("comp", "strum", 0.5), ("lead", "intro", "brass", "brass", -12, 0.95)],
        # Verse: light, off-beat piano and strums under the flute.
        verse=[("comp", "piano_off", 0.45), ("comp", "strum", 0.4), ("lead", "verse", "flute", "lead", 0, 0.55)],
        # Chorus: the band at full tilt; brass in thirds calls, the whistle answers.
        chorus=[("comp", "piano8", 0.8), ("comp", "stabs", 0.8), ("comp", "strum", 0.65),
                ("lead", "chorus", "brass", "lead", -12, 1.25, True), ("lead", "answer", "whistle", "lead2", 0, 0.9)],
        # Verse 2: the same tune with piano eighths and a strings counter-line: it has grown.
        verse2=[("comp", "piano8", 0.5), ("comp", "strum", 0.45), ("lead", "verse", "flute", "lead", 0, 0.6),
                ("counter", "strings", "lead2", 0.5)],
        # Bridge: half-time drums then the arranger's build; strings over a pad, vibes behind.
        bridge=[("comp", "pad", 0.6), ("comp", "stabs_hold", 0.45), ("lead", "bridge", "strings", "lead", -12, 1.5),
                ("lead", "climb", "brass", "lead2", -12, 0.85)],
        # The lift: everything, a whole tone up, with bells doubling the hook on top.
        chorus2=[("comp", "piano8", 0.85), ("comp", "stabs", 0.9), ("comp", "strum", 0.7),
                 ("lead", "chorus", "brass", "lead", -10, 1.3, True), ("lead", "answer", "whistle", "lead2", 2, 0.9),
                 ("lead", "chorus", "bells", "lead2", 2, 0.4)],
    ),
    roles={"verse2": "verse", "chorus2": "chorus"},
    risers=("bridge",),
    levels={"perc": -26, "lead2": -23, "brass": -24},
    extra=lambda song, bar0, n, name, role, rng: _extra(song, bar0, n, name, rng),
)

## The chord each section's last beat kicks into, as a three-note brass stab.
_PICKUPS = {"verse": ("C4", "E4", "G4"), "verse2": ("C4", "E4", "G4"), "bridge": ("E4", "G#4", "B4")}


def _extra(song, bar0, n, name, rng):
    """The song's own percussion: the clip-clop that gives it its gait, kettle hits on the chorus's
    downbeats, a snare roll up the bridge's climb, and a brass pickup into each chorus."""
    for i in range(n):
        b = (bar0 + i) * 4
        level = {"verse": 0.45, "verse2": 0.6, "chorus": 1.0, "chorus2": 1.1}.get(name, 0.0)
        if name == "intro" and i >= 2:
            level = 0.7
        if name == "bridge" and i >= 4:
            level = 0.4 + 0.15 * (i - 4)
        if level:
            for beat in range(4):
                song.hit("conga", b + beat, 0.8 * level, "perc", pan=-0.3, pitch=1.0)
                song.hit("conga", b + beat + 0.5, 0.45 * level, "perc", pan=0.3, pitch=1.3)
                song.hit("conga", b + beat + 0.75, 0.55 * level, "perc", pan=0.3, pitch=1.3)
        if name in ("chorus", "chorus2") and i % 2 == 0:
            song.hit("tom", b, 0.9, "perc", pitch=0.55)
        if name == "bridge" and i >= n - 2:
            for k in range(16):
                song.hit("snare", b + k * 0.25, 0.2 + 0.03 * k + 0.25 * (i - (n - 2)), "snare", tight=True)
    if name in _PICKUPS:
        last = (bar0 + n - 1) * 4
        for beat, dur in ((3.0, 0.4), (3.5, 0.2), (3.75, 0.2)):
            for m in _PICKUPS[name]:
                song.put("brass", last + beat, ins.brass(note(m), dur * song.spb, 0.8, rng, stab=True), pan=rng.uniform(-0.4, 0.4))


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
    # The round was clear: the hook's gallop figure, up to a held G with a crash and a snare flourish.
    notes = [(0, 0.5, note("G4")), (0.5, 0.25, note("G4")), (0.75, 0.25, note("G4")), (1, 0.5, note("B4")),
             (1.5, 0.5, note("D5")), (2, 3.0, note("G5"))]
    top = fx.fanfare(notes, BEAT, "brass", rng)
    under = fx.fanfare([(2, 3.0, note("D5")), (2, 3.0, note("B4"))], BEAT, "brass", rng, vel=0.6)
    return fx.mix((0, top), (0, under), (0, fx.drumroll(2 * BEAT, rng) * 0.5), (2 * BEAT, ins.crash(0.8, rng)),
                  (2 * BEAT, ins.bells(note("G6"), 1.0, 0.7, rng)))


def rein_warn(rng):
    # A soft two-note nudge: sit, or pedal.
    return fx.mix((0, ins.bells(note("A5"), 0.2, 0.7, rng)), (0.16, ins.bells(note("E5"), 0.3, 0.7, rng)))


SFX = {"hoof_canter": hoof_canter, "count_tick": count_tick, "line_chime": line_chime, "take_chime": take_chime,
       "lift_off": lift_off, "landing": landing, "rail_clatter": rail_clatter, "applause": applause,
       "clear_round": clear_round, "rein_warn": rein_warn}
