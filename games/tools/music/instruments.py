"""The game music renderer (#43, #55): the instruments. Each takes (midi or a chord, seconds, velocity,
rng, **options) and returns a mono buffer, except where noted. All synthesised; original code."""
import numpy as np
from dsp import SR, hz, secs, osc, vibrato, adsr, expdec, fade_out, lp, hp, bp, sweep_lp, drive, ks, peak_eq
from dsp import lp as dsp_lp


# --- Drums ---

def kick(vel, rng, tone=1.0):
    n = secs(0.45)
    t = np.arange(n) / SR
    f = 46 + 110 * tone * np.exp(-t / 0.035) + 60 * np.exp(-t / 0.006)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.32)
    click = hp(rng.uniform(-1, 1, n), 2500) * np.exp(-t / 0.0025) * 0.5
    x = drive(body * 1.4 + click, 1.6)
    return x * vel


def snare(vel, rng, tight=False):
    n = secs(0.4)
    t = np.arange(n) / SR
    body = (np.sin(2 * np.pi * 182 * t) * 0.8 + np.sin(2 * np.pi * 329 * t) * 0.45) * np.exp(-t / 0.07)
    nz = bp(rng.uniform(-1, 1, n), 1400, 9000) * np.exp(-t / (0.11 if tight else 0.17))
    snap = hp(rng.uniform(-1, 1, n), 4000) * np.exp(-t / 0.01)
    x = body * 0.7 + nz * 1.2 + snap * 0.4
    return drive(x, 1.3) * vel


def ghost(vel, rng):
    return snare(vel * 0.3, rng, tight=True)[: secs(0.12)]


def clap(vel, rng):
    n = secs(0.35)
    t = np.arange(n) / SR
    env = np.zeros(n)
    for k, at in enumerate([0.0, 0.011, 0.022, 0.031]):
        s = secs(at)
        env[s:] += np.exp(-(t[: n - s]) / (0.006 if k < 3 else 0.12)) * (0.8 if k < 3 else 1.0)
    return bp(rng.uniform(-1, 1, n), 900, 5000) * env * vel


_METAL = [205.3, 304.4, 369.6, 522.7, 540.0, 800.0]


def _metal(n, rng, scale=1.0):
    t = np.arange(n) / SR
    m = sum(np.sign(np.sin(2 * np.pi * f * scale * t + rng.uniform(0, 6.28))) for f in _METAL)
    return m / 6


def hat(vel, rng, open_=False):
    n = secs(0.5 if open_ else 0.09)
    t = np.arange(n) / SR
    x = _metal(n, rng, 1.6) * 0.6 + rng.uniform(-1, 1, n) * 0.6
    x = hp(bp(x, 6500, 12000), 7000)
    return x * np.exp(-t / (0.16 if open_ else 0.022)) * vel


def shaker(vel, rng):
    n = secs(0.12)
    t = np.arange(n) / SR
    env = np.minimum(1, t / 0.012) * np.exp(-t / 0.035)
    return bp(rng.uniform(-1, 1, n), 4500, 11000) * env * vel * 0.8


def tamb(vel, rng):
    n = secs(0.25)
    t = np.arange(n) / SR
    j = sum(np.sin(2 * np.pi * rng.uniform(5500, 9500) * t) for _ in range(8)) / 8
    x = (j + rng.uniform(-1, 1, n) * 0.5) * np.exp(-t / 0.06)
    return hp(x, 4000) * vel


def sleigh(vel, rng):
    """A shake of sleigh bells: a cloud of small jingles."""
    n = secs(0.3)
    out = np.zeros(n)
    t = np.arange(secs(0.12)) / SR
    for _ in range(14):
        at = secs(rng.uniform(0, 0.06))
        f = rng.uniform(5200, 10500)
        j = (np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * f * 1.51 * t)) * np.exp(-t / rng.uniform(0.02, 0.05))
        k = min(len(j), n - at)
        out[at:at + k] += j[:k] * rng.uniform(0.4, 1)
    return hp(out, 4500) * vel / 5


def crash(vel, rng):
    n = secs(2.2)
    t = np.arange(n) / SR
    x = _metal(n, rng, 2.3) * 0.5 + rng.uniform(-1, 1, n)
    x = hp(x, 3500)
    return x * np.exp(-t / 0.7) * np.minimum(1, t / 0.002) * vel * 0.6


def ride(vel, rng):
    n = secs(0.9)
    t = np.arange(n) / SR
    ping = sum(np.sin(2 * np.pi * f * t) for f in [3100, 4520, 5810]) / 3
    x = hp(_metal(n, rng, 3.1) * 0.4 + rng.uniform(-1, 1, n) * 0.3, 5000) + ping * 0.5
    return x * np.exp(-t / 0.35) * vel * 0.5


def tom(vel, rng, pitch=1.0):
    n = secs(0.5)
    t = np.arange(n) / SR
    f = (100 + 80 * np.exp(-t / 0.05)) * pitch
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.22)
    x += bp(rng.uniform(-1, 1, n), 300, 3000) * np.exp(-t / 0.03) * 0.3
    return drive(x, 1.2) * vel


def riser(seconds, rng):
    n = secs(seconds)
    t = np.arange(n) / SR
    k = t / seconds
    nz = rng.uniform(-1, 1, n)
    x = bp(nz, 800, 10000) * k ** 2 * 0.5
    x += osc("saw", 200 * 2 ** (2.5 * k), n) * 0.12 * k ** 3
    return hp(x, 300)


# --- Bass ---

def slap_bass(m, dur, vel, rng, art="thumb"):
    f = hz(m)
    pop = art == "pop"
    x = ks(f, dur + 0.05, rng, bright=0.95 if pop else 0.75, damp=0.993, pick=0.6 if pop else 0.3)
    t = np.arange(len(x)) / SR
    sub = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.6) * 0.6
    thump = lp(rng.uniform(-1, 1, len(x)), 900) * np.exp(-t / 0.006) * (0.4 if not pop else 0.2)
    y = x + sub + thump
    if art == "ghost":
        y = lp(y, 1200) * np.exp(-t / 0.03) * 0.5
    y = drive(lp(y, 4500 if pop else 3000), 1.5)
    y *= adsr(len(y), a=0.001, d=0.05, s=0.9, r=0.03, gate=secs(dur))
    return fade_out(y) * vel


def pick_bass(m, dur, vel, rng):
    f = hz(m)
    x = ks(f, dur + 0.05, rng, bright=0.45, damp=0.995, pick=0.4)
    t = np.arange(len(x)) / SR
    y = x * 0.9 + np.sin(2 * np.pi * f * t) * 0.7 * np.exp(-t / 0.9)
    y = drive(lp(y, 2400), 1.8)
    y *= adsr(len(y), a=0.002, d=0.08, s=0.85, r=0.03, gate=secs(dur))
    return fade_out(y) * vel


def synth_bass(m, dur, vel, rng):
    f = hz(m)
    n = secs(dur + 0.04)
    x = osc("saw", f, n) * 0.6 + osc("square", f * 0.5, n) * 0.4
    env = expdec(n, 0.08)
    y = sweep_lp(x, 300, 2400, env)
    y = drive(y, 1.5) * adsr(n, a=0.003, d=0.1, s=0.8, r=0.03, gate=secs(dur))
    return fade_out(y) * vel


# --- Guitars ---

def guitar_chop(chord, dur, vel, rng, mute=True, down=True):
    """A strummed chord on a clean electric guitar: 6 ms between strings."""
    notes = sorted(chord) if down else sorted(chord, reverse=True)
    n = secs(dur + 0.15)
    out = np.zeros(n)
    for i, m in enumerate(notes):
        at = secs(0.006 * i)
        s = ks(hz(m), dur + 0.15, rng, bright=0.8, damp=0.985 if mute else 0.997, pick=0.3)
        out[at:] += s[: n - at] * (0.9 ** i)
    out = hp(out, 180)
    out = peak_eq(out, 2500, 4, 1.0)
    out *= adsr(n, a=0.001, d=0.03, s=0.9, r=0.04, gate=secs(dur))
    return fade_out(out) * vel / len(notes) * 1.8


def scratch(vel, rng):
    """A muted strum: the funk scratch."""
    n = secs(0.05)
    t = np.arange(n) / SR
    return bp(rng.uniform(-1, 1, n), 800, 4000) * np.exp(-t / 0.012) * vel * 0.6


def power_chord(m, dur, vel, rng, mute=True):
    n = secs(dur + 0.1)
    out = np.zeros(n)
    for k, iv in enumerate([0, 7, 12]):
        s = ks(hz(m + iv), dur + 0.1, rng, bright=0.7, damp=0.98 if mute else 0.996, pick=0.4)
        out += s[:n]
    out = drive(hp(out, 90) * 3.0, 4.0)
    out = lp(out, 3600)
    out = peak_eq(out, 1800, 3, 0.8)
    out *= adsr(n, a=0.002, d=0.05, s=0.9, r=0.04, gate=secs(dur))
    return fade_out(out) * vel * 0.5


def twang(m, dur, vel, rng):
    """A bright single-coil lead with vibrato toward the end of long notes."""
    f = hz(m)
    n = secs(dur + 0.2)
    x = ks(f, dur + 0.4, rng, bright=0.95, damp=0.998, pick=0.5)
    # vibrato by re-reading the string at a wobbling rate
    v = vibrato(n, rate=5.2, cents=18 if dur > 0.4 else 0, delay=0.18, rng=rng)
    pos = np.cumsum(v)
    pos = pos[pos < len(x) - 1]
    y = np.interp(pos, np.arange(len(x)), x)
    y = np.pad(y, (0, n - len(y)))
    y = peak_eq(hp(y, 200), 3000, 5, 1.2)
    y = drive(y * 1.5, 1.6)
    y *= adsr(n, a=0.001, d=0.05, s=0.95, r=0.08, gate=secs(dur))
    return fade_out(y) * vel


def pluck(m, dur, vel, rng):
    x = ks(hz(m), dur + 0.3, rng, bright=0.85, damp=0.995, pick=0.2)
    x = hp(x, 250) * adsr(len(x), a=0.001, d=0.05, s=1.0, r=0.15, gate=secs(dur))
    return fade_out(x) * vel


# --- Keys ---

def epiano(chord, dur, vel, rng):
    """FM electric piano (a tine and its bark)."""
    notes = chord if isinstance(chord, (list, tuple)) else [chord]
    n = secs(dur + 0.6)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in notes:
        f = hz(m)
        idx = (1.2 + 1.5 * vel) * np.exp(-t / 0.35)
        mod = np.sin(2 * np.pi * f * t)
        body = np.sin(2 * np.pi * f * t + idx * mod)
        tine = np.sin(2 * np.pi * f * 14.0 * t) * np.exp(-t / 0.02) * 0.25 * vel
        out += (body + tine) * np.exp(-t / 1.6)
    out *= adsr(n, a=0.002, d=0.0, s=1.0, r=0.25, gate=secs(dur))
    return fade_out(lp(out, 6000)) * vel / max(1, len(notes)) ** 0.6


def piano(chord, dur, vel, rng):
    notes = chord if isinstance(chord, (list, tuple)) else [chord]
    n = secs(dur + 0.8)
    t = np.arange(n) / SR
    out = np.zeros(n)
    B = 0.0004
    for m in notes:
        f0 = hz(m)
        for det in (-0.6, 0.6):
            f = f0 * 2 ** (det / 1200)
            for k in range(1, 12):
                fk = f * k * np.sqrt(1 + B * k * k)
                if fk > SR * 0.45:
                    break
                amp = (1 / k ** 1.1) * (0.4 + 0.6 * vel) ** (k * 0.25)
                out += amp * np.sin(2 * np.pi * fk * t + rng.uniform(0, 6.28)) * np.exp(-t * (0.6 + 0.35 * k) * (f0 / 400) ** 0.3)
        out += hp(rng.uniform(-1, 1, n), 1500) * np.exp(-t / 0.004) * 0.15 * vel
    out *= adsr(n, a=0.001, d=0.0, s=1.0, r=0.2, gate=secs(dur))
    return fade_out(out) * vel * 0.35 / max(1, len(notes)) ** 0.6


def bells(m, dur, vel, rng):
    """Glockenspiel: bright inharmonic partials, quick decay."""
    f = hz(m)
    n = secs(max(dur, 0.2) + 0.9)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, tau in [(1.0, 1.0, 0.9), (2.76, 0.45, 0.35), (5.40, 0.25, 0.15), (8.93, 0.12, 0.07)]:
        if f * r < SR * 0.45:
            out += a * np.sin(2 * np.pi * f * r * t) * np.exp(-t / tau)
    out += hp(rng.uniform(-1, 1, n), 5000) * np.exp(-t / 0.003) * 0.2
    return fade_out(out) * vel * 0.6


def organ(chord, dur, vel, rng):
    notes = chord if isinstance(chord, (list, tuple)) else [chord]
    n = secs(dur + 0.05)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in notes:
        f = hz(m)
        for r, a in [(0.5, 0.5), (1, 1), (2, 0.6), (3, 0.35), (4, 0.2)]:
            out += a * np.sin(2 * np.pi * f * r * t)
    out *= adsr(n, a=0.005, d=0.0, s=1.0, r=0.04, gate=secs(dur))
    return fade_out(out) * vel * 0.25 / max(1, len(notes)) ** 0.7


# --- Synths and horns ---

def supersaw(m, dur, vel, rng, voices=7, spread=18.0, cutoff=5500, attack=0.006, release=0.12, vib=True):
    """Detuned saw stack, returned stereo (2, n)."""
    f = hz(m)
    n = secs(dur + release + 0.05)
    out = np.zeros((2, n))
    v = vibrato(n, 5.6, 10, 0.25, rng) if vib and dur > 0.35 else 1.0
    for i in range(voices):
        d = spread * (i / (voices - 1) * 2 - 1) if voices > 1 else 0
        s = osc("saw", f * 2 ** (d / 1200) * v, n, rng.uniform(0, 1))
        p = (i / (voices - 1) * 2 - 1) if voices > 1 else 0
        out[0] += s * np.cos((p + 1) * np.pi / 4)
        out[1] += s * np.sin((p + 1) * np.pi / 4)
    out /= voices ** 0.6
    out = lp(out, cutoff)
    env = adsr(n, a=attack, d=0.15, s=0.8, r=release, gate=secs(dur))
    return out * env * vel


def brass(m, dur, vel, rng, stab=False):
    """Synth brass section: detuned saws, a blatty filter swell, a fall on stabs."""
    f = hz(m)
    n = secs(dur + 0.15)
    t = np.arange(n) / SR
    v = vibrato(n, 5.0, 8, 0.3, rng) if dur > 0.5 else 1.0
    fall = 1.0 if not stab else 2 ** (-np.clip((t - dur * 0.6) / 0.15, 0, 1) * 1.5 / 12)
    x = sum(osc("saw", f * 2 ** (c / 1200) * v * fall, n, rng.uniform(0, 1)) for c in (-9, 0, 8)) / 3
    swell = np.clip(t / 0.05, 0, 1) * np.exp(-t / (0.12 if stab else 0.5)) * 0.7 + 0.3
    y = sweep_lp(x, 900, 4200 * (0.7 + 0.3 * vel), swell)
    y = peak_eq(y, 1200, 3, 0.8)
    env = adsr(n, a=0.025 if not stab else 0.008, d=0.1, s=0.85, r=0.08, gate=secs(dur))
    return fade_out(y * env) * vel


def flute_lead(m, dur, vel, rng):
    """A breathy, whistly FM lead for verses."""
    f = hz(m)
    n = secs(dur + 0.12)
    t = np.arange(n) / SR
    v = vibrato(n, 5.4, 14, 0.22, rng)
    ph = np.cumsum(f * v) / SR
    x = np.sin(2 * np.pi * ph + 0.6 * np.exp(-t / 0.08) * np.sin(4 * np.pi * ph))
    x += 0.15 * np.sin(4 * np.pi * ph)
    breath = bp(rng.uniform(-1, 1, n), f, min(f * 4, 12000)) * 0.12
    y = (x + breath) * adsr(n, a=0.03, d=0.1, s=0.85, r=0.09, gate=secs(dur))
    return fade_out(y) * vel


def sax(m, dur, vel, rng):
    """A reedy lead: a saw-square blend through two formants, breath and vibrato."""
    f = hz(m)
    n = secs(dur + 0.12)
    v = vibrato(n, 5.0, 16, 0.25, rng)
    x = osc("saw", f * v, n) * 0.6 + osc("square", f * v, n) * 0.4
    y = bp(x, 450, 1100) * 1.4 + bp(x, 1400, 2800) * 0.9 + lp(x, 400) * 0.4
    y += bp(rng.uniform(-1, 1, n), 1500, 6000) * 0.05
    y = drive(y * 1.5, 1.4)
    y *= adsr(n, a=0.02, d=0.1, s=0.8, r=0.08, gate=secs(dur))
    return fade_out(y) * vel


def pad(chord, dur, vel, rng, cutoff=2400):
    """Warm string-synth pad (stereo)."""
    n = secs(dur + 0.55)
    out = np.zeros((2, n))
    for m in chord:
        s = supersaw(m, dur, 1.0, rng, voices=5, spread=12, cutoff=cutoff, attack=0.25, release=0.5, vib=False)
        k = min(n, s.shape[1])
        out[:, :k] += s[:, :k]
    return out * vel / max(1, len(chord)) ** 0.7


# --- Added for the other games (#55) ---

def vibes(m, dur, vel, rng, tremolo=5.5):
    """Vibraphone: a struck bar (sine partials 1, 4, 10) with the motor's tremolo."""
    f = hz(m)
    n = secs(max(dur, 0.25) + 1.2)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for r, a, tau in [(1.0, 1.0, 1.4), (3.93, 0.25, 0.4), (9.8, 0.08, 0.08)]:
        if f * r < SR * 0.45:
            out += a * np.sin(2 * np.pi * f * r * t) * np.exp(-t / tau)
    out *= 1.0 - 0.35 * (0.5 + 0.5 * np.sin(2 * np.pi * tremolo * t))
    out += hp(rng.uniform(-1, 1, n), 3000) * np.exp(-t / 0.002) * 0.15
    out *= adsr(n, a=0.001, d=0.0, s=1.0, r=0.3, gate=secs(dur + 0.3))
    return fade_out(out) * vel * 0.6


def accordion(chord, dur, vel, rng):
    """A musette accordion: two reeds a few cents apart per note, through a reedy formant, with a
    bellows swell."""
    notes = chord if isinstance(chord, (list, tuple)) else [chord]
    n = secs(dur + 0.08)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for m in notes:
        f = hz(m)
        for c in (-7, 7):
            out += osc("square", f * 2 ** (c / 1200), n, rng.uniform(0, 1)) * 0.5 + osc("saw", f * 2 ** (c / 1200), n, rng.uniform(0, 1)) * 0.3
    out = bp(out, 300, 3200) + lp(out, 400) * 0.3
    swell = 0.85 + 0.15 * np.sin(2 * np.pi * 0.9 * t)
    out *= swell * adsr(n, a=0.03, d=0.08, s=0.85, r=0.05, gate=secs(dur))
    return fade_out(out) * vel * 0.35 / max(1, len(notes)) ** 0.7


def brush(vel, rng, sweep=False):
    """A brush on the snare: a soft slap, or a sweep (a swish that swells and dies)."""
    n = secs(0.35 if sweep else 0.22)
    t = np.arange(n) / SR
    nz = bp(rng.uniform(-1, 1, n), 1800, 9000)
    env = np.minimum(1, t / (0.06 if sweep else 0.002)) * np.exp(-t / (0.12 if sweep else 0.06))
    body = np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04) * (0 if sweep else 0.35)
    return (nz * env + body) * vel * 0.8


def stomp(vel, rng):
    """A foot stomp on a wooden pier: a low thud with a boxy knock and a little room."""
    n = secs(0.5)
    t = np.arange(n) / SR
    f = 55 + 70 * np.exp(-t / 0.03)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.18)
    knock = bp(rng.uniform(-1, 1, n), 180, 1200) * np.exp(-t / 0.03) * 0.8
    x = drive(body * 1.2 + knock, 1.4)
    return x * vel


def snap(vel, rng):
    """A finger snap."""
    n = secs(0.12)
    t = np.arange(n) / SR
    x = bp(rng.uniform(-1, 1, n), 1800, 7000) * np.exp(-t / 0.012)
    x += np.sin(2 * np.pi * 2100 * t) * np.exp(-t / 0.006) * 0.4
    return x * vel


def rim(vel, rng):
    """A rimshot click (cross-stick)."""
    n = secs(0.1)
    t = np.arange(n) / SR
    x = (np.sin(2 * np.pi * 1650 * t) + 0.6 * np.sin(2 * np.pi * 520 * t)) * np.exp(-t / 0.012)
    x += bp(rng.uniform(-1, 1, n), 2000, 8000) * np.exp(-t / 0.004) * 0.5
    return x * vel * 0.8


def conga(vel, rng, pitch=1.0):
    n = secs(0.35)
    t = np.arange(n) / SR
    f = (220 + 60 * np.exp(-t / 0.01)) * pitch
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.12)
    x += bp(rng.uniform(-1, 1, n), 800, 4000) * np.exp(-t / 0.005) * 0.4
    return x * vel * 0.8


def muted_trumpet(m, dur, vel, rng):
    """A trumpet with a harmon mute: brassy saws through a nasal, narrow formant."""
    f = hz(m)
    n = secs(dur + 0.1)
    t = np.arange(n) / SR
    v = vibrato(n, 5.5, 12, 0.25, rng) if dur > 0.4 else 1.0
    x = osc("saw", f * v, n, rng.uniform(0, 1))
    y = bp(x, 1300, 2600) * 1.6 + bp(x, 600, 900) * 0.4
    y = drive(y * 1.4, 1.5)
    y *= np.clip(t / 0.02, 0, 1) * (0.75 + 0.25 * np.exp(-t / 0.15))
    y *= adsr(n, a=0.015, d=0.08, s=0.85, r=0.06, gate=secs(dur))
    return fade_out(y) * vel


def strum(chord, dur, vel, rng, down=True):
    """An open strum on a steel-string acoustic: 9 ms between strings, ringing."""
    notes = sorted(chord) if down else sorted(chord, reverse=True)
    n = secs(dur + 0.3)
    out = np.zeros(n)
    for i, m in enumerate(notes):
        at = secs(0.009 * i)
        s = ks(hz(m), dur + 0.3, rng, bright=0.9, damp=0.998, pick=0.25)
        out[at:] += s[: n - at] * (0.92 ** i)
    out = hp(out, 120)
    out = peak_eq(out, 4500, 4, 0.8)
    out *= adsr(n, a=0.001, d=0.05, s=0.9, r=0.12, gate=secs(dur))
    return fade_out(out) * vel / len(notes) * 1.7


def whistle(m, dur, vel, rng):
    """A tin whistle: a near-pure tone, chiffy attack, gentle vibrato."""
    f = hz(m)
    n = secs(dur + 0.08)
    t = np.arange(n) / SR
    v = vibrato(n, 5.8, 10, 0.25, rng)
    ph = np.cumsum(f * v) / SR
    x = np.sin(2 * np.pi * ph) + 0.08 * np.sin(4 * np.pi * ph) + 0.04 * np.sin(6 * np.pi * ph)
    chiff = bp(rng.uniform(-1, 1, n), f * 2, min(f * 6, 12000)) * np.exp(-t / 0.025) * 0.4
    breath = bp(rng.uniform(-1, 1, n), f, min(f * 3, 12000)) * 0.05
    y = (x + chiff + breath) * adsr(n, a=0.015, d=0.06, s=0.9, r=0.05, gate=secs(dur))
    return fade_out(y) * vel


def sub_bass(m, dur, vel, rng):
    """A round synth bass: a sine with a little saw on top, for house grooves."""
    f = hz(m)
    n = secs(dur + 0.04)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) + lp(osc("saw", f, n), 900) * 0.35
    x = drive(x * 1.2, 1.3) * adsr(n, a=0.004, d=0.12, s=0.8, r=0.03, gate=secs(dur))
    return fade_out(x) * vel


# --- Added for Power Grid's bossa (#81) ---

def nylon(chord, dur, vel, rng):
    """A nylon-string guitar, fingered: all the strings of a chord almost at once, soft and woody,
    a body resonance low down and no steel brightness."""
    notes = sorted(chord)
    n = secs(dur + 0.5)
    out = np.zeros(n)
    for i, m in enumerate(notes):
        at = secs(0.006 * i + rng.uniform(0, 0.003))
        s = ks(hz(m), dur + 0.5, rng, bright=0.55, damp=0.9975, pick=0.32)
        out[at:] += s[: n - at] * (0.95 ** i)
    out = hp(out, 85)
    out = peak_eq(out, 210, 4, 1.2)
    out = peak_eq(out, 2400, -2, 0.8)
    out = lp(out, 7000)
    out *= adsr(n, a=0.001, d=0.05, s=0.92, r=0.16, gate=secs(dur))
    return fade_out(out) * vel / max(1, len(notes)) ** 0.75 * 1.5


def upright(m, dur, vel, rng):
    """An upright bass: a round sine body under a plucked string, a thump at the finger."""
    f = hz(m)
    n = secs(dur + 0.18)
    t = np.arange(n) / SR
    string = ks(f, dur + 0.18, rng, bright=0.42, damp=0.9955, pick=0.3)[:n]
    body = (np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t)) * np.exp(-t / 0.7)
    thump = lp(rng.uniform(-1, 1, n), 420) * np.exp(-t / 0.018) * 0.6
    x = lp(string * 0.8 + body * 0.75 + thump, 1500)
    x = drive(x * 1.1, 1.2) * adsr(n, a=0.003, d=0.1, s=0.82, r=0.09, gate=secs(dur))
    return fade_out(x) * vel


def flugel(m, dur, vel, rng):
    """A flugelhorn: additive harmonics whose brightness swells with the breath, a small scoop
    into the note, a late vibrato. Darker and rounder than the muted trumpet's filtered saw."""
    f = hz(m)
    n = secs(dur + 0.12)
    t = np.arange(n) / SR
    v = vibrato(n, 5.0, 9, 0.32, rng) * 2.0 ** (-0.35 * np.exp(-t / 0.03) / 12.0)
    ph = np.cumsum(f * v) / SR
    swell = np.clip(t / 0.09, 0, 1) * (0.72 + 0.28 * np.minimum(t / max(dur, 0.1), 1.0)) * (0.55 + 0.45 * vel)
    x = np.zeros(n)
    for k in range(1, 13):
        if f * k > SR * 0.42:
            break
        x += np.exp(-(k - 1) * (1.5 - 0.95 * swell)) * np.sin(2 * np.pi * k * ph) / k ** 0.3
    breath = bp(rng.uniform(-1, 1, n), f * 2, min(f * 7, 10000)) * (0.05 + 0.1 * np.exp(-t / 0.05))
    y = (x + breath) * adsr(n, a=0.028, d=0.12, s=0.84, r=0.09, gate=secs(dur))
    return fade_out(y * 0.55) * vel


def silver_flute(m, dur, vel, rng):
    """A concert flute: few harmonics, a tongued chiff, breath that follows the partials, a slow
    tremolo with the vibrato."""
    f = hz(m)
    n = secs(dur + 0.1)
    t = np.arange(n) / SR
    v = vibrato(n, 5.2, 11, 0.24, rng)
    ph = np.cumsum(f * v) / SR
    x = np.sin(2 * np.pi * ph) + 0.28 * np.sin(4 * np.pi * ph) + 0.1 * np.sin(6 * np.pi * ph) + 0.03 * np.sin(8 * np.pi * ph)
    x *= 1.0 + 0.09 * np.clip((t - 0.24) / 0.25, 0, 1) * np.sin(2 * np.pi * 5.2 * t)
    chiff = bp(rng.uniform(-1, 1, n), f * 1.5, min(f * 5, 11000)) * np.exp(-t / 0.02) * 0.32
    breath = bp(rng.uniform(-1, 1, n), f * 0.9, min(f * 2.4, 11000)) * 0.09 + bp(rng.uniform(-1, 1, n), 4000, 9000) * 0.012
    y = (x + chiff + breath) * adsr(n, a=0.024, d=0.08, s=0.88, r=0.08, gate=secs(dur))
    return fade_out(y * 0.7) * vel


def string_section(m, dur, vel, rng):
    """A small string section (stereo): six players, each a little out of tune with their own
    vibrato, through a body resonance; a slow bow. Returns (2, n)."""
    f = hz(m)
    n = secs(dur + 0.45)
    out = np.zeros((2, n))
    for i in range(6):
        cents = rng.uniform(-9, 9)
        v = vibrato(n, rng.uniform(4.6, 5.8), rng.uniform(8, 14), rng.uniform(0.1, 0.35), rng)
        x = osc("saw", f * 2 ** (cents / 1200) * v, n, rng.uniform(0, 1))
        p = (i / 5.0) * 2 - 1
        out[0] += x * np.sqrt((1 - p * 0.8) / 2)
        out[1] += x * np.sqrt((1 + p * 0.8) / 2)
    for c in (0, 1):
        y = hp(lp(out[c], 3600), 170)
        out[c] = peak_eq(peak_eq(y, 480, 3, 1.1), 1900, 3, 1.3)
    out *= adsr(n, a=0.16, d=0.1, s=0.9, r=0.38, gate=secs(dur))
    return out * vel * 0.2


def oohs(chord, dur, vel, rng):
    """Wordless backing voices on an "ooh" (stereo): three singers a note, a glottal saw through
    the vowel's formants, each with their own drift. Returns (2, n)."""
    n = secs(dur + 0.4)
    out = np.zeros((2, n))
    for m in chord:
        f = hz(m)
        for i in range(3):
            v = vibrato(n, rng.uniform(4.8, 5.6), rng.uniform(10, 17), rng.uniform(0.15, 0.4), rng)
            x = osc("saw", f * 2 ** (rng.uniform(-7, 7) / 1200) * v, n, rng.uniform(0, 1))
            y = lp(x, 340) * 1.1 + bp(x, 300, 480) * 1.0 + bp(x, 720, 980) * 0.3 + bp(x, 2300, 2900) * 0.05
            p = rng.uniform(-0.75, 0.75)
            out[0] += y * np.sqrt((1 - p) / 2)
            out[1] += y * np.sqrt((1 + p) / 2)
    out *= adsr(n, a=0.14, d=0.1, s=0.9, r=0.32, gate=secs(dur))
    return out * vel * 0.3 / max(1, len(chord)) ** 0.7
