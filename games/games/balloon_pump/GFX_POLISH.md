# Balloon Pump: graphics polish punch list

> **Status:** 2026-11-02, the 2D rework (rider: "2D, like Safe Cracker"; "visuals not at the level
> of the other games"). Every item below is done unless it says otherwise. In play: 50-56 draw
> calls on the desktop with the HUD.

From the review of the first 2D pass against `ART_BIBLE.md`, Safe Cracker (the 2D bar:
`safe_cracker/ART_BIBLE.md`, `GFX_POLISH.md`) and Tug of War, side by side in the same captures:

```sh
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_ui_states.gd -- --game=safe_cracker --out=DIR
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_ui_states.gd -- --game=balloon_pump --tension=30:6 --out=DIR
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_pump.gd -- --places --out=DIR   # every place, posed
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_pump.gd -- --out=DIR            # the review stills
```

**Before captures** (the scratchpad's `bp2/first/`): the first 2D pass, before this list; the 3D
slice it replaced is described in git history (`ART_BIBLE.md` v1).

## What works (keep)

- One illustrated hero (the brass pump and its balloon) in a lit place, Safe Cracker's craft:
  bevels, rivets, highlights toward a single key light, soft shadows, a vignette.
- The balloon shaded per pixel reads as glossy rubber at any size, with a smooth edge.
- Three distinct places from palettes and a few shapes; slow ambient life in shaders and tweens.

## P0: the hero, whole and unclipped

1. **The room bake was drawn at a fraction of the screen** (the first capture: a postage-stamp room
   top left). The bake's SubViewport kept its default size. **Done:** sized to the painted room
   (`PumpPlaces.WIDE`), rendered once per place.
2. **The plunger's handle was cut off** (rider, 2026-11-02). It sank into the collar's clip at the
   bottom of its stroke and sat under the ride panel's edge. **Done:** the stroke is 52 px between
   y 262 and 314, the handle never reaches the collar; the pump moved right (x 800) so the handle
   clears the ride panel with its effort badge. `pump_layout_test` checks the handle at the top,
   middle and bottom of its stroke.
3. **The Ferris wheel sat in the ground** (rider). Its lowest car hung 90 px below the horizon and
   its top ran under the ride panel. **Done:** a smaller wheel (r 148) standing on the fair's
   horizon with its feet on it; `pump_layout_test` checks the wheel's reach as it turns.
4. **The bunch ran off the right edge and under Pause | End.** **Done:** the tether moved to
   x 1600 and the slots were pulled in; `pump_layout_test` checks every slot at both ends of the
   sway.
5. **Bulbs drew over the pump** (the bulbs layer sits above the bake). **Done:**
   `PumpPlaces.behind_hero` leaves out the bulbs in front of the pump, its gauge and the lantern;
   the wire still runs behind (`pump_stage_test`).

## P1: weight and life

6. **The balloon floated with no contact with the world.** **Done:** a soft shadow on the floor
   under the nozzle, growing and darkening with the balloon (a sprite, no redraw).
7. **Pumping had no visible air.** **Done:** a puff of vapour at the collar on each stroke that
   pushes air (a 6-particle one-shot), and a hiss from the balloon's neck while it leaks.
8. **The fair's field was bare.** **Done:** a trodden path running back between the tents in
   perspective, straw scattered on it, grass tufts.
9. **The pier's glitter was blocky** (square cells). **Done:** short soft dashes, re-dealt a few
   times a second, widening toward the viewer.

## P2: if there is time

10. **A swaying rope or bunting across the big top's front.** Skipped: the curtains, fringe, beam
    and dust already fill the place; more motion competes with the balloon.
11. **A per-place tint on the pump's brass** (cooler under the pier's moon). Skipped: one key
    light per place already drives the brass highlight; a second colour would muddy it.

## Budget (desktop, 2026-11-02)

| Layer | Draws |
| --- | --- |
| Baked room (room, pump, hose, stand, basket, light, shadows, vignette) | 1 |
| Sea (pier) / wheel (fair) / dust (big top) | 1 each, only in their place |
| Bulbs, plunger, collar lip, wedge, needle, strings | 1 each |
| Bunch (MultiMesh), nozzle balloon, flyer, floor shadow | 1 each |
| Confetti, hiss, vapour | 1 each while alive |

About 14 for the world; 50-56 in play with the HUD; 10 in the posed stills with the HUD hidden.
