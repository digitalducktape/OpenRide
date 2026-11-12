# Ready for Launch: graphics polish punch list

> **Status:** 2026-11-06. Items 1-11 done, 12-13 left (why under each). In play: 47-72 draw calls
> with the HUD on the desktop, at most about 26k primitives.

From the graphics review against `ART_BIBLE.md` and Safe Cracker (fresh capture with
`tests/capture_ui_states.gd`). Captures in `~/openride-scratch-backup/wave2/ready_for_launch/`:
`gfx_before/`, `gfx_after/`. Retake with:

```sh
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_launch.gd -- --out=DIR --stats
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_launch.gd -- --out=DIR --places
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_launch.gd -- --out=DIR --silhouette
```

## What works (keep)

- One illustrated hero dead centre, with Safe Cracker's craft: rivets, bevels, brass, grime.
- Three lit places with their own ambient life, and a rocket that takes their light.
- The climb tells a story with no text: pad, clouds, black sky, limb, Earth, Moon.

## P0

1. **The Earth didn't look like the Earth** (rider). Faceted blobs on a blue disc. **Done:** a sphere
   shader over a generated map (ART_BIBLE §6).
2. **A steeple's cross on the tip** (silhouette check). **Done:** a plain spike.
3. **The flame in space was a long tail** behind the capsule. **Done:** a curtain of three tongues,
   a short wide fan in vacuum, tested.
4. **The rocket flew into the HUD after a stage dropped** (a sign error in the framing). **Done**,
   and tested at nine heights for every mark.
5. **The tower and clock touched the ride panel.** **Done:** a narrower tower moved right; the clock
   lower; buildings moved clear of the board.

## P1

6. **Geometry:** cloud decks and Earth weather reached 153k primitives. **Done:** low-vertex soft
   lumps, 26k at the worst.
7. **Black band under the polar ice** (the bake's clear colour). **Done.**
8. **Smoke was flat pink blobs.** **Done:** puffs lit from above, a short hot start, then the place's
   cloud colours.
9. **The rocket sat on the table with no contact.** **Done:** a contact shadow and floodlight cones.
10. **Storage tanks read as pills.** **Done:** square ends on saddles.
11. **A pale wedge round the Moon** (its light spilled past the disc). **Done.**

## P2

12. **Tick marks on the fuel sight glass.** *Left:* the status bar and percentage already say it.
13. **Moving lights on the hull during fuelling.** *Left:* out of scope for v1; no gameplay value.

## Code review (LP-CODE-REVIEW)

**CONCERNS, addressed:** phase rules stay in `LaunchLogic`; views read it and own no rules. Some
methods paint at length past the 40-line guide, in keeping with `SafePlaces` and `KeepyPlaces`.
