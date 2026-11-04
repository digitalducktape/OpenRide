# The Pull: audio polish

From the audio review of 2026-11-02 (the audio-director and sound-designer roles), against
`songs/tug_of_war.py` and `songs/safe_cracker.py`. Both games were also rendered offline with
`tests/render_game_audio.gd` (90 s, a scripted ride) and analysed with
`tools/music/analyze_mix.py --limit`.

## The theme: "Heavy Haul" (`songs/the_pull.py`)

A county-fair boogie at 116 bpm in E mixolydian. Its form matches Tug's: a 4-bar intro played
once, then verse, chorus, bridge and chorus2 (8 bars each) looping. The arranger adds the fills
on each section's last bar, the build into the chorus and the bridge's half-time drums.

| | Before | After |
| --- | --- | --- |
| Signature instruments | twang guitar lead, brass hook, piano, chugs | the same, plus an acoustic strum doubling the rhythm, held horn stabs in the bridge, and a honking sax answering the twang (bridge) and countering the brass (chorus2) |
| Parts (verse / chorus / bridge / chorus2) | 3 / 5 / 3 / 5 | 4 / 6 / 5 / 7 (Tug 3 / 5 / 3 / 5) |
| Lead stem on | only within 15 m of the best flag or 20 m of the line | also while the sled rolls at 1 m/s or more. A half-FTP rider starts at 1.34 m/s, so every rider hears the hook early in a pull. A first try at 1.6 m/s would have left that rider without it |

## The mix (offline render, Master limiter applied by the analysis)

| | The Pull before | The Pull after | Tug of War (reference) |
| --- | --- | --- | --- |
| Mix, integrated | -18.3 LUFS | -17.6 LUFS | -17.4 LUFS |
| Music | -21.2 LUFS | -19.8 LUFS | -20.3 LUFS |
| Music mid band (3rd of 6) | -48.1 dB | -44.2 dB | -44.4 dB |
| Peak before the limiter | -1.7 dBFS | -2.2 dBFS | -0.1 dBFS |
| Lead stem up | 0% of the time | 38% | 25% |
| Duck | 78 samples, -10 dB deepest | the same | 159, -10 dB |

The mix now sits within 0.2 dB of Tug's (the music 0.5 dB above it), the mid band (where the strums, piano and horns live)
is as full, and nothing clips. The duck runs less than Tug's because The Pull has fewer stings
(Tug has a sting every round).

## Effects

The cues measured in the render cut through as well as Tug's. The scripted ride reaches no best
flag and no Full Pull, so `best_pass`, `full_pull` and `crowd_swell` weren't measured here:
- The horn: 14 dB broadband over the music.
- The stall horn: 10 dB broadband.
- "Dig in!": 3 dB broadband and 11 dB in its best band.
- The board clack: about -3 dB broadband. It is a subtle cue by design, like Tug's rope creak
  (-6 dB).

The three loops (motor, chain, box) follow the pull: the motor's pitch follows the watts. They
need no change. No effect was re-rendered.
