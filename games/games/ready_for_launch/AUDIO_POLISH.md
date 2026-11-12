# Ready for Launch: audio polish

From the audio review of 2026-11-06 (audio-director and sound-designer passes). References:
`songs/safe_cracker.py`, `songs/tug_of_war.py`, and an offline render of Tug of War.

No speakers were involved: the checks are `tests/render_game_audio.gd` and
`tools/music/analyze_mix.py`, so **the rider's ear is still the real test of the theme.**

```sh
$GODOT_BIN --headless --fixed-fps 60 --path games -s res://tests/render_game_audio.gd -- --game=ready_for_launch --out=DIR --seconds=92
python games/tools/music/analyze_mix.py DIR --limit
```

## The theme: "First Light" replaced by "Moon Shot"

The rider listened to "First Light" and said it "sounds very basic". They were right: the melody
was two or three long notes a bar with no rhythm to hum, every part was a detuned saw, and the song
stayed at one level. Its only commitment was a label ("orchestral-synth").

**What makes Night Shift and Heave Together rich,** and what this theme takes from that:

| Quality | The references | Moon Shot |
| --- | --- | --- |
| Genre commitment | Spy jazz; a stomp-clap shanty: every part belongs | Space-age surf, friendly and retro like the rocket |
| Signature instruments | Vibes, muted trumpet, spy guitar; whistle, accordion | Reverb twang guitar, tremolo picking, combo organ, a gliding theremin |
| A singable hook | Short rhythmic phrases that repeat | One motif in every line: a dotted crotchet, a quaver, a long note reaching up |
| Song form | Verse, chorus, bridge | Verse, a four-bar climb, chorus, bridge, final chorus |
| Counter-melody | Instruments answering | The riff answers the theremin; guitar breaks fill the chorus's gaps; a bell counter line at the end |
| Fills, risers | Fills into sections | Tom cascades, snare build and riser on the climb, riser out of the bridge |
| Dynamic contrast | Sections with different weights | A section arc of about 8 dB (below), half-time bridge |
| Sends | Room on the snare, delay on leads | Spring-like reverb on the guitar, slap delay on the theremin |

| | "First Light" | "Moon Shot" |
| --- | --- | --- |
| Tempo, key | 104 bpm, D minor to major | 156 bpm, A minor, chorus in C, final chorus up a tone (D) |
| Loop | 40 bars, about 92 s | 36 bars, 55.4 s |
| Lead | Saw brass in long notes | Theremin: a whole section as one gliding voice |
| Section levels | 1 dB apart | Intro -24, verse -20, climb -18, chorus -18, bridge -23, final chorus -17 dB RMS before the trim |

**It builds toward liftoff.** The stems keep their links, and the riff sits in the harmony stem, so
the rider hears the tune's skeleton all through the fuelling; the theremin and horns are the lead
stem and open on the push, so the hook arrives with the sprint. The song isn't locked to the phases.

**New in the tools:** `ins.theremin` (phrase-long pitch glide, vibrato that blooms on held notes),
`ins.combo_organ`, the `surf` groove, the `gallop` bass, `surf_chop` and `organ_*` comps, `surf_trem`
tremolo lines, per-section `dynamics` and per-song `sends`. The first cut's `cinematic` and
`ostinato` are gone.

## The mix, against Tug of War

| Measure | "First Light" | "Moon Shot" | Tug of War |
| --- | --- | --- | --- |
| Mix, integrated | -17.2 LUFS | -17.1 LUFS | -17.4 LUFS |
| Music | -20.6 LUFS | -20.4 LUFS | -20.3 LUFS |
| Effects | -17.1 LUFS | -17.2 LUFS | -17.9 LUFS |
| Peak before the limiter | -1.3 dBFS | -0.8 dBFS | -0.2 dBFS |
| Clipped samples | 0 | 0 | 0 |
| Ignition's cut-through (best / broadband) | 23.5 / 19.0 dB | 21.4 / 19.3 dB | |
| Deepest duck | -10 dB | -10 dB | |

## What changed in the effects

1. **Ignition and liftoff clipped together.** They land within a moment of each other, so both came
   down; the engine came down 2 dB as well.
2. **The countdown is tones only**, a formant-shaped tone that rises a semitone a second, brighter
   with a bell on the last three. No speech. Against the new riff it was masked (3.5 dB best band),
   so it moved up an octave to A5 and every second ducks the music: now about 12 dB.
3. **Every warning ducks the music** (`duck_for_moment`), and ignition takes the sting's duck.
4. **Names are `rfl_*`**, so another game's sounds can't replace ours.
5. **Effects re-keyed** to A minor and C major for the new theme; otherwise unchanged, because their
   cut-through already measured well.
6. `render_game_audio.gd` knows this game: its sounds and a scripted rider through a launch.

## Left

- **Nobody has listened to "Moon Shot".** Every check here is a measurement; it can't say whether the
  hook is catchy or the theremin sounds right.
- The Moon's fanfare and touchdown aren't in the scripted render (its rider stops at orbit), so
  they're checked for level only by their peak, not against the music.
- The hiss and engine loops are checked for level, not for how the loop point sounds.
