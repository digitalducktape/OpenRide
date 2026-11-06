"""The game music renderer (#43, #55): the parts. Drums, bass, comping, stabs, pads and lines for one
section at a time, in a style. Original code for this repo (Apache-2.0)."""
import numpy as np
import instruments as ins
from compose import voicing, bass_root, bar_chords, parse_chord, third_below


# --- Drums ---

def drums(song, bar0, nbars, style, role, double=False):
    for i in range(nbars):
        b = (bar0 + i) * 4
        last = i == nbars - 1
        odd = i % 2 == 1
        if i == 0 and role in ("verse", "chorus", "final", "bridge"):
            song.hit("crash", b, 0.9 if role != "verse" else 0.7, "cym", pan=0.3)
        if role == "intro":
            _intro_bar(song, b, i, nbars, style)
            continue
        if role == "bridge" and i < nbars // 2:
            _halftime(song, b, style)
            continue
        if role == "bridge" or role == "pickup":
            _build(song, b, i, nbars if role == "bridge" else nbars, style, last)
            continue
        fill = last and role in ("verse", "chorus", "final")
        _groove(song, b, style, role, odd, double, fill)
        if fill:
            _fill(song, b, style, i)


def _groove(song, b, style, role, odd, double, fill):
    big = role in ("chorus", "final")
    end = 2.0 if fill else 4.0
    h = song.hit
    if style == "funk":
        kicks = [0, 0.75, 2.5] if not odd else [0, 1.75, 2.5, 3.25]
        ghosts = [1.75, 2.25, 3.75] if not big else [2.25]
    elif style == "drive":
        kicks = [0, 1.5, 2, 3.5] if not odd else [0, 1.5, 2.5]
        ghosts = [0.5, 1.5, 2.5, 3.5] if role == "verse" else []
    elif style == "disco":
        kicks = [0, 1, 2, 3]
        ghosts = [3.75] if odd else []
    elif style == "stomp":
        _stomp(song, b, role, odd, big, end)
        return
    elif style == "spy":
        _spy(song, b, role, odd, big, end)
        return
    elif style == "house":
        _house(song, b, role, odd, big, end, double)
        return
    elif style == "synthwave":
        _synthwave(song, b, role, odd, big, end)
        return
    elif style == "porch":
        _porch(song, b, role, odd, big, end)
        return
    else:  # pop
        kicks = [0, 1.5, 2.5] if not odd else [0, 1.5, 2.5, 3.75]
        ghosts = [1.75] if odd else []
    for k in kicks:
        if k < end:
            h("kick", b + k, 1.0 if k == 0 else 0.85, "kick")
    for s in (1, 3):
        if s < end:
            h("snare", b + s, 0.95, "snare")
            if big or style == "disco":
                h("clap", b + s, 0.55, "perc", pan=-0.1)
    for g in ghosts:
        if g < end:
            h("ghost", b + g, 0.9, "snare", pan=0.1)
    # hats: eighths, or sixteenths (double time); open on the last off-beat in big sections
    step = 0.25 if double else 0.5
    t = 0.0
    while t < end - 1e-6:
        off = (t * 2) % 1 > 0.4 if not double else (t * 4) % 2 == 1
        if style == "disco" and abs(t % 1 - 0.5) < 1e-6:
            h("hat", b + t, 0.55, "hats", pan=0.25, open_=True)
        elif big and abs(t - 3.5) < 1e-6 and not double:
            h("hat", b + t, 0.6, "hats", pan=0.25, open_=True)
        elif style == "drive" and big:
            h("ride", b + t, 0.55 if off else 0.75, "cym", pan=0.35)
        else:
            h("hat", b + t, (0.5 if off else 0.75) * (0.9 if double else 1.0), "hats", pan=0.25)
        t += step
    if double:
        for t in np.arange(0.5, end, 1.0):
            h("hat", b + t, 0.45, "hats", pan=0.3, open_=True)
    # percussion layer
    if style == "pop":
        step = 0.25 if big or double else 0.5
        for t in np.arange(0, end, step):
            h("sleigh", b + t, 0.75 if (t * 2) % 1 > 0.4 else 0.5, "perc", pan=-0.35)
    elif style == "drive":
        if big:
            for t in np.arange(0.5, end, 1.0):
                h("tamb", b + t, 0.6, "perc", pan=-0.55)
    elif big or style in ("funk", "disco") or double:
        for t in np.arange(0, end, 0.25):
            h("shaker", b + t, 0.55 if (t * 4) % 2 == 1 else 0.3, "perc", pan=-0.4)


def _stomp(song, b, role, odd, big, end):
    """Stomp-clap: stomps (and a kick under them) on 1 and 3, every beat in big sections; claps
    on 2 and 4 with the snare in big sections; a tambourine on the eighths."""
    h = song.hit
    stomps = [0, 1, 2, 3] if big else [0, 2, 2.5] if odd else [0, 2]
    for k in stomps:
        if k < end:
            h("stomp", b + k, 1.0 if k in (0, 2) else 0.8, "kick")
            h("kick", b + k, 0.55, "kick")
    for c in (1, 3):
        if c < end:
            h("clap", b + c, 0.9, "snare", pan=-0.15)
            h("clap", b + c + 0.02, 0.6, "snare", pan=0.25)
            if big:
                h("snare", b + c, 0.7, "snare")
    for t in np.arange(0, end, 0.5):
        h("tamb", b + t, 0.75 if (t * 2) % 2 == 1 else 0.45, "perc", pan=0.45)
    if big:
        for t in np.arange(0, end, 0.5):
            h("hat", b + t, 0.4, "hats", pan=-0.3)


def _spy(song, b, role, odd, big, end):
    """A swung spy-jazz groove: the ride's ding, ding-a ding; brushes or cross-stick on 2 and 4
    (the snare in big sections); a light kick; snaps in verses, congas in big sections."""
    h = song.hit
    for t in (0, 1, 1.5, 2, 3, 3.5):
        if t < end:
            h("ride", b + t, 0.75 if t % 1 == 0 else 0.5, "cym", pan=0.35)
    for t in (1, 3):
        if t < end:
            if big:
                h("snare", b + t, 0.8, "snare")
            else:
                h("rim", b + t, 0.9, "snare", pan=0.1)
                h("snap", b + t, 0.6, "perc", pan=-0.5)
    for t in ([0, 2.5] if not odd else [0, 1.5, 2.5]):
        if t < end:
            h("kick", b + t, 0.8, "kick")
    for t in np.arange(0.5, end, 1.0):
        h("hat", b + t + 0.0, 0.35, "hats", pan=-0.25)
    if big:
        for t, p in ((0.5, 1.0), (1.5, 1.4), (2.5, 1.0), (3.0, 1.4), (3.5, 1.0)):
            if t < end:
                h("conga", b + t, 0.6, "perc", pan=-0.55, pitch=p)
    else:
        for t in np.arange(0, end, 1.0):
            h("brush", b + t, 0.5, "perc", pan=0.2, sweep=True)


def _porch(song, b, role, odd, big, end):
    """A front-porch brush groove: brushes sweeping every beat, a cross-stick on 2 and 4 (a soft
    snare and a tambourine in big sections), a round kick and a shaker in eighths. Unhurried."""
    h = song.hit
    for t in np.arange(0, end, 1.0):
        h("brush", b + t, 0.65, "perc", pan=0.2, sweep=True)
    for t in (1, 3):
        if t < end:
            if big:
                h("snare", b + t, 0.6, "snare")
                h("tamb", b + t, 0.55, "hats", pan=0.4)
            else:
                h("rim", b + t, 0.85, "snare", pan=0.1)
    for t in ([0, 2.5] if not odd else [0, 1.5, 2.5]):
        if t < end:
            h("kick", b + t, 0.75, "kick", tone=0.85)
    for t in np.arange(0, end, 0.5):
        h("shaker", b + t, 0.5 if t % 1 == 0 else 0.34, "hats", pan=-0.3)


def _house(song, b, role, odd, big, end, double):
    """Four on the floor: claps on 2 and 4, open hats on the off-beats, sixteenth closed hats and
    a shaker in big sections."""
    h = song.hit
    for k in (0, 1, 2, 3):
        if k < end:
            h("kick", b + k, 1.0 if k == 0 else 0.92, "kick")
    for c in (1, 3):
        if c < end:
            h("clap", b + c, 0.85, "snare")
            if big:
                h("snare", b + c, 0.45, "snare")
    for t in np.arange(0.5, end, 1.0):
        h("hat", b + t, 0.6, "hats", pan=0.25, open_=True)
    if big or double:
        for t in np.arange(0, end, 0.25):
            if (t * 4) % 2 == 1:
                h("hat", b + t, 0.35, "hats", pan=-0.2)
        for t in np.arange(0, end, 0.25):
            h("shaker", b + t, 0.5 if (t * 4) % 2 == 1 else 0.3, "perc", pan=-0.4)
    elif odd:
        h("hat", b + 3.75, 0.4, "hats", pan=-0.2)


def _synthwave(song, b, role, odd, big, end):
    """Synthwave (Watt Lane, #78): kick on 1 and 3 (and the "and" of 2 in big sections), a big
    snare with a clap on 2 and 4, straight eighth hats (sixteenths in big sections), a tambourine
    on the off-beats."""
    h = song.hit
    for k in ([0, 1.5, 2] if big else [0, 2]) + ([3.5] if odd else []):
        if k < end:
            h("kick", b + k, 1.0 if k in (0, 2) else 0.8, "kick")
    for s in (1, 3):
        if s < end:
            h("snare", b + s, 1.0, "snare")
            h("clap", b + s, 0.6, "perc", pan=0.15)
    step = 0.25 if big else 0.5
    for t in np.arange(0, end, step):
        on = abs(t % 1) < 1e-6
        h("hat", b + t, 0.6 if on else 0.42, "hats", pan=0.3)
    if big:
        for t in np.arange(0.5, end, 1.0):
            h("tamb", b + t, 0.5, "perc", pan=-0.5)


def _fill(song, b, style, i):
    h = song.hit
    if style == "porch":  # a soft turnaround, no tom roll
        for t, v in ((2.5, 0.4), (3.0, 0.5), (3.5, 0.6), (3.75, 0.5)):
            h("snare", b + t, v, "snare")
        h("kick", b + 2, 0.7, "kick", tone=0.85)
        return
    h("kick", b + 2, 0.9, "kick")
    if style in ("drive", "pop") or i % 2:
        for k, t in enumerate(np.arange(2, 4, 0.25)):
            h("tom", b + t, 0.6 + 0.05 * k, "snare", pan=0.4 - 0.1 * k, pitch=1.6 - 0.12 * k)
    else:
        for k, t in enumerate(np.arange(2, 4, 0.25)):
            h("snare", b + t, 0.35 + 0.08 * k, "snare")
    h("kick", b + 3.75, 0.8, "kick")


def _halftime(song, b, style):
    h = song.hit
    if style == "porch":  # brushes alone, a kick on the one, the cross-stick on three
        h("kick", b, 0.65, "kick", tone=0.85)
        h("rim", b + 2, 0.7, "snare", pan=0.1)
        for t in range(4):
            h("brush", b + t, 0.6, "perc", pan=0.2, sweep=True)
        return
    h("kick", b, 0.9, "kick")
    h("kick", b + 2.5, 0.6, "kick")
    h("snare", b + 2, 0.8, "snare")
    for t in np.arange(0, 4, 0.5):
        h("ride" if style != "pop" else "sleigh", b + t, 0.45, "cym", pan=0.3)


def _build(song, b, i, nbars, style, last):
    h = song.hit
    if style == "porch":  # no snare roll: the groove simply comes back, shaker first
        _porch(song, b, "verse", i % 2 == 1, False, 4.0)
        if last:
            for t, v in ((3.0, 0.45), (3.5, 0.55), (3.75, 0.6)):
                h("snare", b + t, v, "snare")
        return
    for t in range(4):
        h("kick", b + t, 0.85, "kick")
    step = 0.25 if last else 0.5
    k0 = (i / max(1, nbars - 1))
    for t in np.arange(0, 4, step):
        h("snare", b + t, 0.3 + 0.55 * (k0 * 0.6 + 0.4 * t / 4), "snare")
    for t in np.arange(0, 4, 0.5):
        h("hat", b + t, 0.5, "hats", pan=0.25)


def _intro_bar(song, b, i, nbars, style):
    h = song.hit
    if i == nbars - 1:
        for t in (0, 1):
            h("kick", b + t, 0.9, "kick")
        for k, t in enumerate(np.arange(1, 4, 0.25)):
            h("snare", b + t, 0.25 + 0.06 * k, "snare")
        return
    for t in np.arange(0, 4, 0.5):
        h("hat", b + t, 0.35 + 0.15 * i, "hats", pan=0.25)
    if i >= 1:
        for t in range(4):
            h("kick", b + t, 0.6 + 0.1 * i, "kick")
    if style == "pop":
        for t in np.arange(0, 4, 0.5):
            h("sleigh", b + t, 0.5, "perc", pan=-0.35)


# --- Bass ---

def bass(song, bar0, bars, style, role, rng):
    for i, text in enumerate(bars):
        b = (bar0 + i) * 4
        nxt = bars[i + 1] if i + 1 < len(bars) else bars[0]
        nroot = bass_root(bar_chords(nxt)[0][1])
        for beat0, sym, dur in bar_chords(text):
            r = bass_root(sym)
            root, ivs, _ = parse_chord(sym)
            fifth = r + 7
            sev = r + (10 if 10 in ivs else 11 if 11 in ivs else 12)
            if role == "intro" or (role == "bridge" and i < len(bars) // 2):
                _bnote(song, style, b + beat0, dur * 0.95, r, 0.8, "thumb", rng)
                continue
            for t, which, d, art, vel in _bass_pattern(style, dur):
                third = r + (3 if 3 in ivs else 4)
                m = {"r": r, "o": r + 12, "5": fifth, "7": sev, "3": third,
                     "n": nroot - 1 if nroot > r else nroot + 2}[which]
                if beat0 + t >= 4:
                    continue
                if which == "n" and beat0 + dur < 4:
                    m = r + 12
                _bnote(song, style, b + beat0 + t, d, m, vel, art, rng)


def _bass_pattern(style, dur):
    full = dur >= 4
    if style == "slap":
        p = [(0, "r", 0.45, "thumb", 1), (0.75, "o", 0.2, "pop", 0.8), (1.0, "r", 0.2, "ghost", 0.6),
             (1.5, "r", 0.4, "thumb", 0.9), (2.0, "5", 0.4, "thumb", 0.85), (2.5, "o", 0.2, "pop", 0.8),
             (2.75, "7", 0.2, "pop", 0.7), (3.0, "r", 0.4, "thumb", 0.9), (3.5, "5", 0.2, "thumb", 0.8),
             (3.75, "n", 0.2, "pop", 0.7)]
    elif style == "pick8":
        p = [(t, "r", 0.45, "pick", 0.95 if t % 1 == 0 else 0.8) for t in np.arange(0, 3.5, 0.5)] + [(3.5, "5" if full else "r", 0.45, "pick", 0.85)]
    elif style == "octave":
        p = [(t, "r" if (t * 2) % 2 == 0 else "o", 0.4, "pick", 0.9) for t in np.arange(0, 3.5, 0.5)] + [(3.5, "n", 0.25, "pick", 0.8), (3.75, "r", 0.2, "pick", 0.7)]
    elif style == "walk":
        p = [(0, "r", 0.9, "pick", 0.95), (1, "3", 0.9, "pick", 0.8), (2, "5", 0.9, "pick", 0.85), (3, "n", 0.9, "pick", 0.8)]
        if not full:
            return [(0, "r", 0.9, "pick", 0.95), (1, "5" if dur >= 2 else "n", 0.9, "pick", 0.8)][: int(dur)]
    elif style == "root5":
        p = [(0, "r", 0.9, "pick", 1.0), (1.5, "r", 0.4, "pick", 0.7), (2, "5", 0.9, "pick", 0.9), (3.5, "5", 0.4, "pick", 0.7)]
    elif style == "sub":
        p = [(t, "r" if t < 3 else "o", 0.4, "sub", 0.95) for t in (0.5, 1.5, 2.5, 3.5)] + [(0, "r", 0.3, "sub", 0.7)]
    elif style == "pulse":  # synthwave: driving eighths on the root, an octave lift at the bar's end
        p = [(t, "o" if t == 3.5 else "r", 0.42, "synth", 1.0 if t % 1 == 0 else 0.8) for t in np.arange(0, 4, 0.5)]
    else:  # pop synth bass
        p = [(0, "r", 1.3, "synth", 1), (1.5, "r", 0.45, "synth", 0.85), (2.5, "r", 0.45, "synth", 0.9),
             (3.0, "5", 0.45, "synth", 0.8), (3.5, "o", 0.45, "synth", 0.8)]
    if not full:
        p = [(t * dur / 4, w, d * dur / 4 if d > 0.3 else d, a, v) for t, w, d, a, v in p if t * dur / 4 < dur][: max(2, int(len(p) * dur / 4))]
    return p


def _bnote(song, style, beat, dur, m, vel, art, rng):
    sec = dur * song.spb
    if style == "slap":
        x = ins.slap_bass(m, sec, vel, rng, art if art in ("thumb", "pop", "ghost") else "thumb")
    elif style in ("pop", "pulse"):
        x = ins.synth_bass(m, sec, vel, rng)
    elif style == "sub":
        x = ins.sub_bass(m, sec, vel, rng)
    elif style == "walk":
        x = ins.dsp_lp(ins.pick_bass(m, sec, vel, rng), 1400)
    else:
        x = ins.pick_bass(m, sec, vel, rng)
    song.put("bass", beat, x, pan=0.0, human=0.002)


# --- Comping ---

def comp(song, bar0, bars, kind, role, rng, vel=1.0):
    for i, text in enumerate(bars):
        b = (bar0 + i) * 4
        for beat0, sym, dur in bar_chords(text):
            hits = _comp_hits(kind, dur, i)
            for t, d, v, mode in hits:
                if t >= dur:
                    continue
                _comp_note(song, kind, b + beat0 + t, d, sym, v * vel, mode, rng)


def _comp_hits(kind, dur, i):
    if kind == "funk_gtr":
        return [(0.5, 0.12, 0.9, "chord"), (1.25, 0.05, 0.6, "scratch"), (1.5, 0.12, 0.8, "chord"),
                (2.0, 0.05, 0.5, "scratch"), (2.75, 0.12, 0.9, "chord"), (3.25, 0.05, 0.5, "scratch"), (3.5, 0.12, 0.8, "chord")]
    if kind == "disco_gtr":
        return [(t, 0.12, 0.85, "chord") for t in (0.5, 1.5, 2.5, 3.5)] + [(t, 0.05, 0.4, "scratch") for t in (0.75, 1.75, 2.75, 3.75)]
    if kind == "ep":
        return [(0, 1.4, 0.75, "chord"), (1.75, 0.25, 0.6, "chord"), (2.5, 1.2, 0.7, "chord")]
    if kind == "ep_hold":
        return [(0, dur * 0.95, 0.65, "chord")]
    if kind == "piano":
        return [(t, 0.45, 0.85 if t % 2 == 0 else 0.65, "chord") for t in (0, 1, 2, 3)]
    if kind == "piano8":
        return [(t, 0.4, 0.8 if t % 1 == 0 else 0.55, "chord") for t in np.arange(0, 4, 0.5)]
    if kind == "chug":
        return [(t, 0.4, 0.85 if t % 1 == 0 else 0.65, "chug") for t in np.arange(0, 4, 0.5)]
    if kind == "power":
        return [(0, 1.9, 0.9, "open"), (2, 0.4, 0.75, "chug"), (2.5, 0.4, 0.7, "chug"), (3, 0.9, 0.85, "open")]
    if kind == "arp":
        return [(t, 0.45, 0.7, k) for k, t in enumerate(np.arange(0, 4, 0.5))]
    if kind == "stabs":
        return [(0, 0.3, 0.9, "stab"), (1.5, 0.25, 0.75, "stab")] if i % 2 == 0 else [(0.5, 0.25, 0.7, "stab"), (3.5, 0.3, 0.85, "stab")]
    if kind == "stabs_hold":
        return [(0, 1.0, 0.85, "hold"), (2.5, 0.3, 0.75, "stab")]
    if kind == "pad":
        return [(0, dur * 0.98, 0.7, "pad")]
    if kind == "strum":
        return [(0, 0.9, 0.9, "down"), (1, 0.45, 0.7, "down"), (1.5, 0.9, 0.65, "up"), (2.5, 0.45, 0.65, "up"),
                (3, 0.45, 0.85, "down"), (3.5, 0.45, 0.6, "up")]
    if kind == "oompah":
        return [(t, 0.35, 0.8, "acc") for t in (0.5, 1.5, 2.5, 3.5)]
    if kind == "acc_hold":
        return [(0, dur * 0.95, 0.75, "acc")]
    if kind == "vibes":
        return [(0, 1.4, 0.8, "vib"), (2.5, 1.2, 0.7, "vib")] if i % 2 == 0 else [(0.5, 1.0, 0.7, "vib"), (2, 1.8, 0.75, "vib")]
    if kind == "muted_stabs":
        return [(0.5, 0.25, 0.8, "stab"), (1.5, 0.4, 0.7, "stab")] if i % 2 == 0 else [(0, 0.6, 0.85, "stab"), (3.5, 0.3, 0.7, "stab")]
    if kind == "piano_off":
        return [(t, 0.3, 0.75, "chord") for t in (0.5, 1.5, 2.5, 3.5)]
    return []


def _comp_note(song, kind, beat, d, sym, v, mode, rng):
    sec = d * song.spb
    if kind in ("funk_gtr", "disco_gtr"):
        if mode == "scratch":
            song.put("gtr", beat, ins.scratch(v, rng), pan=0.65 if rng.random() > 0.5 else -0.65)
        else:  # double-tracked: a second take, a hair late, on the other side
            down = int(beat * 2) % 2 == 0
            song.put("gtr", beat, ins.guitar_chop(voicing(sym, 66, top=3), sec, v, rng, down=down), pan=0.65)
            song.put("gtr", beat + 0.012 / song.spb, ins.guitar_chop(voicing(sym, 66, top=3), sec, v * 0.9, rng, down=down), pan=-0.65)
    elif kind in ("ep", "ep_hold"):
        song.put("keys", beat, ins.epiano(voicing(sym, 62), sec, v, rng), pan=-0.4)
    elif kind in ("piano", "piano8"):
        song.put("keys", beat, ins.piano(voicing(sym, 64, drop_root=False), sec, v, rng), pan=-0.25)
    elif kind in ("chug", "power"):
        r = bass_root(sym) + 12
        bus = "gtr2" if kind == "chug" else "gtr"
        song.put(bus, beat, ins.power_chord(r, sec, v, rng, mute=mode == "chug"), pan=-0.7)
        song.put(bus, beat + 0.01 / song.spb, ins.power_chord(r, sec, v * 0.9, rng, mute=mode == "chug"), pan=0.7)
    elif kind == "arp":
        tones = voicing(sym, 70, drop_root=False)
        m = tones[mode % len(tones)] if (mode // len(tones)) % 2 == 0 else tones[::-1][mode % len(tones)]
        song.put("gtr", beat, ins.pluck(m, sec, v, rng), pan=0.55 if mode % 2 else -0.55)
    elif kind in ("stabs", "stabs_hold"):
        for m in voicing(sym, 70, top=3):
            song.put("brass", beat, ins.brass(m, sec, v * 0.6, rng, stab=mode == "stab"), pan=rng.uniform(-0.5, 0.5))
    elif kind == "pad":
        song.put("pad", beat, ins.pad(voicing(sym, 60, drop_root=False), sec, v, rng), human=0)
    elif kind == "strum":
        down = mode == "down"
        song.put("gtr", beat, ins.strum(voicing(sym, 60, drop_root=False) + [voicing(sym, 67, drop_root=False)[-1]], sec, v, rng, down=down), pan=-0.6)
        song.put("gtr", beat + 0.015 / song.spb, ins.strum(voicing(sym, 62, drop_root=False), sec, v * 0.85, rng, down=down), pan=0.6)
    elif kind in ("oompah", "acc_hold"):
        song.put("keys", beat, ins.accordion(voicing(sym, 64, drop_root=False), sec, v, rng), pan=0.2)
    elif kind == "vibes":
        for k, m in enumerate(voicing(sym, 67)):
            song.put("keys", beat + 0.02 * k, ins.vibes(m, sec, v * 0.55, rng), pan=-0.35 + 0.2 * k, human=0.002)
    elif kind == "muted_stabs":
        for m in voicing(sym, 67, top=3):
            song.put("brass", beat, ins.muted_trumpet(m, sec, v * 0.5, rng), pan=rng.uniform(-0.4, 0.4))
    elif kind == "piano_off":
        song.put("keys", beat, ins.piano(voicing(sym, 66, drop_root=False), sec, v, rng), pan=0.3)


# --- Lines ---

LEADS = {
    "supersaw": lambda m, s, v, r: ins.supersaw(m, s, v * 0.8, r),
    "brass": lambda m, s, v, r: ins.brass(m, s, v, r),
    "flute": lambda m, s, v, r: ins.flute_lead(m, s, v * 0.9, r),
    "sax": lambda m, s, v, r: ins.sax(m, s, v * 0.8, r),
    "twang": lambda m, s, v, r: ins.twang(m, s, v * 0.9, r),
    "bells": lambda m, s, v, r: ins.bells(m, s, v, r),
    "ep": lambda m, s, v, r: ins.epiano([m], s, v, r),
    "piano": lambda m, s, v, r: ins.piano([m], s, v * 1.2, r),
    "pluck": lambda m, s, v, r: ins.pluck(m, s, v, r),
    "analog": lambda m, s, v, r: ins.supersaw(m, s, v * 0.85, r, voices=3, spread=7.0, cutoff=3600, attack=0.01, release=0.2),
    "strings": lambda m, s, v, r: ins.supersaw(m, s, v * 0.5, r, voices=5, spread=10, cutoff=3200, attack=0.12, release=0.3),
    "whistle": lambda m, s, v, r: ins.whistle(m, s, v * 0.8, r),
    "muted": lambda m, s, v, r: ins.muted_trumpet(m, s, v * 0.9, r),
    "vibes": lambda m, s, v, r: ins.vibes(m, s, v * 1.2, r),
    "accordion": lambda m, s, v, r: ins.accordion([m], s, v * 1.6, r),
    "organ": lambda m, s, v, r: ins.organ([m], s, v * 2.0, r),
}


def line(song, bar0, bars, instr, bus, rng, shift=0, vel=1.0, pan=0.0, harmony=None):
    """Plays parsed melody bars; `harmony` = (key pc, scale) adds the third below."""
    fn = LEADS[instr]
    for i, notes in enumerate(bars):
        b = (bar0 + i) * 4
        for t, d, m in notes:
            m2 = m + shift
            v = vel * (0.95 if t % 1 == 0 else 0.85)
            song.put(bus, b + t, fn(m2, d * song.spb * 0.95, v, rng), pan=pan, human=0.003)
            if harmony:
                song.put(bus, b + t, fn(third_below(m2, *harmony), d * song.spb * 0.95, v * 0.6, rng), pan=-pan, human=0.003)


def counter(bars, lo=62, hi=74):
    """A countermelody: two chord tones per bar, each the nearest to the last (smooth voice
    leading), as melody bars."""
    out, last = [], (lo + hi) // 2
    for text in bars:
        notes = []
        for beat0, sym, dur in bar_chords(text):
            root, ivs, _ = parse_chord(sym)
            tones = [(root + i) % 12 for i in ivs[1:]]
            for k in range(2 if dur >= 4 else 1):
                cands = [t + 12 * o for t in tones for o in range(3, 8) if lo <= t + 12 * o <= hi and t + 12 * o != last]
                m = min(cands, key=lambda c: abs(c - last) + (0.5 if k else 0))
                notes.append((beat0 + k * dur / 2, dur / (2 if dur >= 4 else 1), m))
                last = m
        out.append(notes)
    return out
