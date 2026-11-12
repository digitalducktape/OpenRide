"""The Pull (#79): "Heavy Haul", a stomping county-fair boogie at 116 bpm in E for a sled pull
under the floodlights. Driving rock drums, an octave-picked bass, palm-muted chugs and open power
chords; a twangy guitar sings the verse and brass with a barrelhouse piano carry the chorus. The
harmony comes in once the sled is rolling, the lead near the rider's best line. Written for this
repo: no samples, nothing borrowed.

The effects include three loops the game plays itself (pitch and level follow the pull):
engine_drone (a pedal-powered motor's rumble), chain_strain (the chain under load) and
box_scrape (the weight box grinding along the sled pan)."""
import numpy as np

import instruments as ins
import sfx as fx
from compose import note
from dsp import SR, secs, osc, lp, bp, hp, drive

PREFIX = "Pull"

SONG = dict(
    file="heavy_haul", title="Heavy Haul", bpm=116, key="E", scale=[0, 2, 4, 5, 7, 9, 10], seed=79,
    drums="drive", bass="octave", verb_sec=1.6,
    form=([("intro", 4)], [("verse", 8), ("chorus", 8), ("bridge", 8), ("chorus2", 8)]),
    chords=dict(
        intro=["E5", "E5", "A5", "B5"],
        verse=["E", "E", "A", "E", "G", "A", "B7", "E"],
        chorus=["A", "E", "B7", "E", "A", "E", "C B7", "E"],
        bridge=["C", "D", "E", "E", "C", "D", "B7", "B7"],
    ),
    melody=dict(
        verse="E4:0.5 G4:0.5 A4:0.5 B4:0.5 D5:1 B4:1 | E5:1.5 D5:0.5 B4:1 r:1 |"
              " A4:0.5 C#5:0.5 E5:0.5 C#5:0.5 A4:1 G4:1 | B4:2 G4:1 r:1 |"
              " G4:0.5 B4:0.5 D5:0.5 G5:0.5 F#5:1 D5:1 | E5:1 C#5:0.5 A4:0.5 E5:1 r:1 |"
              " F#5:1 D#5:0.5 B4:0.5 A4:1 F#4:1 | E4:3 r:1",
        chorus="C#5:1 E5:1 A5:1.5 G5:0.5 | E5:1 B4:1 G#4:2 | F#5:1 D#5:1 B4:1.5 A4:0.5 | G#4:1 B4:1 E5:2 |"
               " C#5:1 E5:1 A5:1.5 B5:0.5 | G#5:1 E5:0.5 B4:0.5 E5:2 | G5:1 E5:1 F#5:1 D#5:1 | E5:3 r:1",
        bridge="G5:2 E5:2 | F#5:2 D5:2 | G#5:1 B5:1 E6:2 | D6:3 r:1 | G5:2 C6:2 | A5:2 F#5:2 | D#5:1 F#5:1 B5:2 | A5:2 F#5:2",
    ),
    parts=dict(
        intro=[("comp", "chug", 0.7), ("comp", "strum", 0.5)],
        # Verse: palm-muted chugs and a barrelhouse off-beat piano under the twang lead, with an
        # acoustic strum doubling the rhythm for the fairground feel.
        verse=[("comp", "chug", 0.85), ("comp", "piano_off", 0.55), ("comp", "strum", 0.55),
               ("lead", "verse", "twang", "lead", 0, 0.9)],
        # Chorus: open power chords, boogie piano eighths and horn stabs; brass carries the hook
        # with the twang an octave down.
        chorus=[("comp", "power", 0.9), ("comp", "piano8", 0.6), ("comp", "stabs", 0.65), ("comp", "strum", 0.45),
                ("lead", "chorus", "brass", "lead", 0, 0.9), ("lead", "chorus", "twang", "lead2", -12, 0.5)],
        # Bridge: half-time drums (the arranger's), held horn stabs and a pad; a honking sax
        # answers the twang.
        bridge=[("comp", "power", 0.7), ("comp", "stabs_hold", 0.55), ("comp", "pad", 0.45),
                ("lead", "bridge", "twang", "lead", 0, 0.8), ("lead", "bridge", "sax", "lead2", -12, 0.5)],
        chorus2=[("comp", "power", 0.9), ("comp", "piano8", 0.6), ("comp", "stabs", 0.65), ("comp", "strum", 0.45),
                 ("lead", "chorus", "brass", "lead", 0, 0.9, True), ("lead", "chorus", "twang", "lead2", 12, 0.4),
                 ("counter", "sax", "lead2", 0.45)],
    ),
)

BEAT = 60 / 116


def _loop(x, fade_sec=0.25):
    """Makes `x` loop seamlessly: its tail is crossfaded into its head, and the tail dropped."""
    f = secs(fade_sec)
    out = x[:-f].copy()
    ramp = np.linspace(0.0, 1.0, f)
    out[:f] = out[:f] * ramp + x[-f:] * (1.0 - ramp)
    return out


def engine_drone(rng):
    # A pedal-powered motor at idle: a low saw at 55 Hz with firing pulses (8 a second), a body
    # resonance and a little grit. The game pitches it with the rider's power (0.7-1.6x).
    sec = 2.0 + 0.25
    n = secs(sec)
    t = np.arange(n) / SR
    base = osc("saw", 55.0, n) * 0.6 + osc("square", 27.5, n) * 0.35
    fire = 0.55 + 0.45 * np.maximum(np.sin(2 * np.pi * 8.0 * t), 0.0) ** 3
    body = lp(base * fire, 420) + bp(base * fire, 160, 260) * 0.8
    grit = bp(rng.uniform(-1, 1, n) * fire, 900, 2400) * 0.08
    return _loop(drive(body + grit, 1.6) * 0.8)


def chain_strain(rng):
    # The chain under load: a slow stick-slip creak with a metallic ring, looping.
    sec = 1.6 + 0.2
    c = fx.creak(sec, 95, rng) * 0.9
    n = len(c)
    t = np.arange(n) / SR
    ring = (osc("sine", 1310.0, n) + osc("sine", 1870.0, n) * 0.6) * 0.04
    ring *= 0.5 + 0.5 * np.sin(2 * np.pi * 1.25 * t) ** 2
    return _loop(c + ring, 0.2)


def box_scrape(rng):
    # The weight box grinding along the steel pan through dirt: band-passed gravel noise with
    # grain clicks, looping. Its level follows the sled's speed.
    sec = 1.5 + 0.2
    n = secs(sec)
    nz = rng.uniform(-1, 1, n)
    grains = (rng.random(n) > 0.9985).astype(float) * rng.uniform(0.3, 1.0, n)
    x = bp(nz, 250, 1600) * 0.6 + bp(grains, 600, 3500) * 3.0 + lp(nz, 120) * 0.5
    return _loop(x * 0.8, 0.2)


def crowd_swell(rng):
    return fx.crowd(2.6, rng)


def pull_horn(rng):
    # The start: two blasts of an air horn (a stacked minor third, detuned), the second longer.
    def blast(sec):
        n = secs(sec)
        t = np.arange(n) / SR
        f = 233.0 * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))
        x = osc("saw", f, n) + osc("saw", f * 1.19, n) * 0.8 + osc("saw", f * 0.5, n) * 0.4
        x = lp(x, 2600)
        env = np.minimum(t / 0.02, 1.0) * np.minimum((sec - t) / 0.08, 1.0)
        return drive(x * env, 1.4) * 0.6
    return fx.mix((0, blast(0.32)), (0.45, blast(0.85)))


def stall_horn(rng):
    # The pull is over: one long, falling horn and the chain going slack.
    n = secs(1.6)
    t = np.arange(n) / SR
    f = 196.0 * (1 - 0.18 * (t / 1.6) ** 2)
    x = lp(osc("saw", f, n) + osc("saw", f * 1.5, n) * 0.5 + osc("square", f * 0.5, n) * 0.4, 1800)
    env = np.minimum(t / 0.03, 1.0) * np.minimum((1.6 - t) / 0.3, 1.0)
    clank = ins.tom(0.9, rng, pitch=0.5)
    return fx.mix((0, drive(x * env, 1.3) * 0.6), (0.05, clank * 0.6), (0.1, fx.thud(0.4, 55, 30, rng) * 0.7))


def dig_in(rng):
    # The stall warning (the sled is crawling): two short bell knocks, a fifth apart.
    a = ins.bells(note("B5"), 0.25, 0.9, rng)
    b = ins.bells(note("E6"), 0.35, 0.9, rng)
    return fx.mix((0, a), (0.18, b))


def board_pass(rng):
    # A distance board goes by: a dry wooden clack.
    return fx.mix((0, fx.tick(1500, 0.05, rng) * 0.6), (0, fx.thud(0.12, 220, 80, rng, knock=0.9) * 0.5))


def best_pass(rng):
    # Past the rider's best: a rising brass call over a cymbal.
    notes = [(0, 0.5, note("B4")), (0.5, 0.5, note("E5")), (1, 1.5, note("G#5"))]
    return fx.mix((0, fx.fanfare(notes, BEAT, "brass", rng)), (BEAT, ins.crash(0.6, rng)))


def full_pull(rng):
    # The Full Pull line: a brass fanfare up to E major, a stomp and a crash.
    notes = [(0, 0.5, note("E5")), (0.5, 0.5, note("G#5")), (1, 0.5, note("B5")), (1.5, 3.0, note("E6"))]
    top = fx.fanfare(notes, BEAT, "brass", rng)
    under = fx.fanfare([(1.5, 3.0, note("B4")), (1.5, 3.0, note("G#4"))], BEAT, "brass", rng, vel=0.6)
    return fx.mix((0, top), (0, under), (0, ins.stomp(1.0, rng) * 0.8), (1.5 * BEAT, ins.stomp(1.0, rng)),
                  (1.5 * BEAT, ins.crash(0.8, rng)))


SFX = {"engine_drone": engine_drone, "chain_strain": chain_strain, "box_scrape": box_scrape,
       "crowd_swell": crowd_swell, "pull_horn": pull_horn, "stall_horn": stall_horn, "dig_in": dig_in,
       "board_pass": board_pass, "best_pass": best_pass, "full_pull": full_pull}
