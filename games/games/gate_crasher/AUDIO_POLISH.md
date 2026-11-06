# Gate Crasher: audio notes

The rider called the new games' music "very basic", so the first pass of this theme was thrown out.
It had a verse and a chorus with nothing in common, no recurring figure, and only stock parts.

## "Clear Round" (`songs/gate_crasher.py`)

A show-ring galop, 138 bpm, G major, 76 s. Modelled on `tug_of_war.py` (a genre you can name, a
signature instrument per section) and `safe_cracker.py` (a tune with an identity, a counter-line).

- **The hook is the gallop:** a long-short-short figure leaping to a fanfare. Brass in thirds calls,
  and a tin whistle answers in the gaps it leaves. The figure runs through everything: the horn
  call's second half, the end of each verse (a tease), the bridge's climb, and the clear-round
  sting, so the win sounds like the song.
- **Form:** horn call intro (once), verse, chorus, verse 2, bridge, last chorus.
- **Signature parts:** the conga clip-clop that gives the song its gait, brass and whistle, the flute
  verses, kettle hits on the chorus downbeats.
- **Growth:** verse 2 adds piano eighths and a strings counter-line. The bridge falls to E minor on
  strings at half time, then climbs on the hook's figure over a snare roll and a riser.
- **The lift:** the bridge lands on E7 and the last chorus goes up a whole tone to A, with bells on
  the hook. Its last bar turns through D7 back to G, so the loop is a real cadence.
- **Fills and pickups:** tom fills at the ends of sections (the arranger's), and a brass pickup in
  the hook's rhythm into each chorus. This needed one new optional key in `render_music.py`, `extra`,
  for a song's own parts; no other song uses it.

| Section | Mix dB | Lead dB |
| --- | --- | --- |
| Verse | -18.5 | -25.8 |
| Chorus | -17.7 | -23.3 |
| Verse 2 | -18.3 | -25.0 |
| Bridge, first half | -20.5 | -27.9 |
| Bridge, build | -18.0 | -27.0 |
| Last chorus | -17.6 | -22.6 |

The first render failed this check: the chorus was no bigger than the verse and the hook sat 2 dB
under the flute. The verse was pulled back and the hook brought up.

## Gating

The bed and harmony always play, so the horn call sounds over the intro card. The lead, which has
the hook, plays at a canter. A rail takes it away for 6 s, not the rest of the round as first
built: that left the tune silent for up to a lap. In a scripted ride the lead is now up 75% of the
time, from 54%.

## Effects

A three-beat stride played once per stride (it follows the pace), count tick, line chime, take-off
chime, lift, landing, rail clatter, applause, the clear-round fanfare and a soft two-note nudge.

## Mix (`render_game_audio`, `analyze_mix.py`, a scripted ride)

1. **Changed.** The hooves ran constantly at -7 dB, leaving the effects 6 dB over the music. The
   stride is now -12 dB and the tick -5 dB.
2. **Kept.** The cues the rider acts on cut through in their best band: count tick +6 dB, line chime
   +13 dB, take-off chime +12 dB. The clatter is +7 dB and ducks the music.
3. **Open.** The effects still measure 4 dB over the music overall (-13.3 against -17.7 LUFS).
4. **Not checked by ear.** All of this is measured, not heard. Nobody has listened to the theme yet,
   and whether the hook is memorable is the rider's call.
