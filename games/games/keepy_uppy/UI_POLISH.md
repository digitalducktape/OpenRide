# Keepy Uppy: UI polish punch list

From the UI review of 2026-11-02 (ux-designer and ui-programmer passes), against
`framework/ui/UI_STYLE.md` and Safe Cracker's `UI_POLISH.md`. Captures as in `GFX_POLISH.md`
(`tests/capture_keepy.gd`), judged at half size as the style guide asks.

**Identity: open air, lift.** Sunset coral `#FF7A59` on deep sky navy `#12233A`, badges leaning
0.08, the face upright (`KeepyUppy.look`). The coral accent agrees with the balloon (as Tug's rope
orange agrees with its rope) and stays clear of the meaning colours: it is warmer and softer than
`BAD`, and End keeps the kit's red. Clear of Balloon Pump's mint and candy pink.

**Hero: the balloon itself**, with the band it's earning in the status widget.

## What works

- The status widget: the three bands as chips, the earning one lit in its pole colour; position
  carries the meaning (left low, right high) as well as colour.
- The warning badge under the chips says what is coming, in one word or two.
- The intro card's picture (the bands, the balloon over the fan) and its copy, every number in it
  computed from the segment (`target_text`, the penalty from `KeepyLogic.POP_PENALTY`, the
  multipliers from `KeepyLogic.multiplier`).

## P0: blocking

1. [x] **The HUD's centre message covered the balloon.** `hud.show_message` centres on the
   screen, which is the column: "Rain cloud coming" and "Bird incoming" sat across the balloon
   exactly when the rider must watch it. **Done:** `KeepyBanner`, the game's own callout lane
   left of the column (layer 6, under the HUD), slammed in and faded out in the meaning colour.
   `keepy_scene_test` checks the lane clears every HUD panel and the balloon's widest drift, and
   that nothing goes to the centre message.
2. [x] **The mid band was mint, Balloon Pump's accent.** **Done:** sky blue `#8FD0F0` on the
   pole, the chip and the intro picture.
3. [x] **The accent was mint on pine (v1).** **Done:** coral on sky navy, above.

## P1

4. [x] **Hard-coded numbers in the intro copy.** The rider's rule: every number from the
   segment's params. **Done:** the multipliers and the penalty are computed; the target line was
   already (tested at three FTPs and difficulties).
5. [x] **Copy** (rider, 2026-11-02): how-to "Pedal to keep the balloon in the air. The higher it
   flies, the more you score" (Steer on: "Pedal to keep the balloon up. Lean to slide the fan under
   it"); target "About N W holds it in the middle". **Done**, tested word for word.
6. [ ] **The status widget's second row is empty when calm.** A live "air time" counter there
   would change text every second and re-lay out the HUD (UI_STYLE §8: labels change only on a
   change, and a re-layout cost 25 ms on the tablet). *Left* by choice; the row holds its height
   so nothing jumps when a warning appears.

## Checks kept

- Every label 34 px or more (`keepy_scene_test`), the widget within 800 x 125 with the longest
  texts.
- Buttons are the HUD's (Pause, End); the game adds no touch targets in play.
