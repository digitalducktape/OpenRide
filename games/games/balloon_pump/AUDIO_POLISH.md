# Balloon Pump: audio polish

> **Status:** 2026-11-02, the rework (rider: the music "not the level of quality … compared to the
> other games"). Passes: `audio-director` and `sound-designer` (`.claude/ccgs/`).

## The theme: "Candy Stripe March" → "Midnight Carousel"

Compared with `songs/safe_cracker.py` ("Night Shift") and `songs/tug_of_war.py` ("Heave
Together"): the first theme had their form (an intro, then verse, chorus, bridge, chorus) but a
plain major march that suited the old daylight stall and nothing in particular. The rework
(`games/tools/music/songs/balloon_pump.py`):

| | Before | After |
| --- | --- | --- |
| Genre | a bright F major march | a swung band-organ carousel in D minor, turning to F major in the chorus: the fair after dark |
| Feel | straight | swing 0.1, so it lilts like a carousel |
| Signature instruments | organ, glockenspiel, accordion | calliope organ lead, glockenspiel counter-line, accordion oom-pah, plucked arpeggios, vibes; brass stabs and a pad in the chorus; flute and pluck counter in the bridge |
| Parts per section | 2-4 | 4-5, with counter-lines in the verse and bridge and the organ in harmony in the choruses |
| Builds | the renderer's risers | the same, plus the chorus2 lift (whistle an octave up, arpeggios) |
| Length, size | 68.6 s (7.6 s intro), 1.36 MB | 68.6 s (7.6 s intro), 1.45 MB with the effects |

The stems are as before: the bed (pop kit, oom-pah bass) always; the harmony while the balloon
takes air; the lead (the tune) **while the valve is wide open**, i.e. the rider is over the push
line. Before, the lead needed the balloon over half full too, so it played 25% of the time; now
64% in the scripted ride (Safe Cracker's plays while the rider is steady, 95%).

## Effects

Retuned to D minor: the tie-off's twang and pluck (D5, A5), the gold chime (a D major run: the
minor lifts), the Race's start call (A4 A4 D5), the won sting (up to D major) and the lost sting
(sliding down to F). Levels: the tie-off at -1 dB with a 0.6 s music dip; squeak -14 to -8 dB by
fill; chuff -11 to -7 dB by the valve; stings -4 dB.

## The mix (`tests/render_game_audio.gd` 90 s, `analyze_mix.py --limit`)

| | Balloon Pump | Safe Cracker | Tug of War |
| --- | --- | --- | --- |
| Integrated | -15.4 LUFS | -15.8 | -17.7 |
| Music | -18.7 LUFS | -17.8 | -20.5 |
| Payoff effect's cut-through (best band) | tie-off 10.5 dB, gold 20, won 19 | vault open 15.6, tumbler 11.1 | splash 29.7, sting 24.7 |
| True peak after the limiter | -0.7 dBTP | -1.5 | -0.9 |
| Stems up | harmony 81%, lead 64% | 95%, 95% | 43%, 20% |

Within the references' range. One sample over 0 dBFS before the master limiter where two effects
overlap (the limiter catches it, as in Tug's mix at -0.2).
