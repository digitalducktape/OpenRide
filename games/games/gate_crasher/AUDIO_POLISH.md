# Gate Crasher: audio notes

"Clear Round", 138 bpm in G major (`songs/gate_crasher.py`): a show-ring galop. Same form as
`tug_of_war.py` and `the_pull.py`: intro, then verse, chorus, bridge and a second chorus with a
counter-melody, about 60 s. Signature instruments: flute verse, brass fanfare chorus with bells, a
pad and vibes in the bridge, piano eighths and strums under it all. Mastered to -15.1 LUFS.

**Gating:** the bed always, the harmony at a canter, the lead while the round is clear, so a rail down
takes the tune away until the next round.

**Effects:** a three-beat stride played once per stride (it follows the pace), count tick, line
chime, take-off chime, lift, landing, rail clatter, applause, the clear-round fanfare, and a soft
two-note nudge.

**Mix** (`render_game_audio`, `analyze_mix.py`, a scripted two rounds):

1. **Changed.** The first pass had the hooves running constantly at -7 dB, leaving the effects 6 dB
   over the music (-12.4 against -18.5 LUFS). The stride is now -12 dB and the tick -5 dB.
2. **Kept.** The cues the rider acts on cut through: count tick +9 dB, line chime +13 dB and take-off
   chime +14 dB over the music in their best band. The clatter is +7 dB and ducks the music.
3. **Not checked by ear.** Nobody has listened to this on the bike's speakers yet.
