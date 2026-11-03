# Balloon Pump: UI polish punch list

> **Status:** 2026-11-02, with the 2D rework. Review against `framework/ui/UI_STYLE.md` and Safe
> Cracker's `UI_POLISH.md`, from the half-size captures (`tests/capture_ui_states.gd`), which is
> about how the tablet reads from the saddle.

## What works (keep)

- **One hero, named:** "am I over the push line?" The status widget's pressure bar (the needle as a
  fill against a gold tick) repeats the in-world gauge, and its badge says it in a word: FILLING,
  PUSH!, TIED!, PEDAL!, REST. Colour is never alone (§4).
- The widget is two rows within 800 × 120 (`pump_status_test`), the display face at 34 px or more,
  labels change only on a change, PUSH! breathes on a scale tween (§7).
- The look: candy pink `#FF5FA2` on deep plum `#2B0F2A`, no other game's pair (§4).

## Items

1. **The intro card's balloons were small** (80 px boxes). **Done:** 100 px, so the four kinds and
   their points read at half size.
2. **The ride panel and the pump's handle collided** (GFX_POLISH item 2). **Done:** the pump moved;
   `pump_layout_test` lays the HUD out with its widest contents (the effort badge, a five-digit
   score, a 1885 W reading) and checks the pump, the handle, the balloon, the bunch and the wheel
   against every panel.
3. **The brief messages sit in the centre**, between the pump and the balloon ("Race won! +70",
   "10 s left!", "Gold! +450"). Kept: UI_STYLE §5 allows the centre message, and here it covers
   neither hero (the gauge is left, the balloon right of it). Safe Cracker needed its own banner
   only because its dial is in the centre.
4. **The bar's fill matched the badge** (amber whenever it reads PUSH!, green while FILLING), done
   in the first pass and kept.
5. **The NEXT icon** shows the next kind at its relative size, gold with a star. Kept.

No game buttons: Balloon Pump is played with the legs and the knob, so the touch rules (§6) only
concern the framework's own Pause and End.
