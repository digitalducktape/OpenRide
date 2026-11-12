# Power Grid: graphics polish punch list

> **Status:** 2026-11-06. Items 1-8 done; 9-10 left (why under each). In play: 62-72 draw calls with
> the HUD on the desktop (budget 120), 36-65k primitives. Tablet fps not measured: unreachable.

From the graphics review after the first build, against `ART_BIBLE.md` and Safe Cracker (one
illustrated hero, a lit place, ambient life that never redraws, a restrained palette).

**Captures** (desktop, 1920x1008, with the HUD) in `~/openride-scratch-backup/wave2/power_grid/`:
`gfx_before/` (the first build beside Safe Cracker's office) and `gfx_after/`. Retake with:

```sh
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_grid.gd -- --out=DIR --stats
```

`grid_layout_test` checks the frame, `grid_scene_test` that playing redraws nothing.

## What works (keep)

- Dusk: the layered range, the rose-to-amber sky, the sun behind the peaks.
- The shed: material detail to Safe Cracker's level, and the crank turning at the rider's cadence.
- Power running down the wires ties the machine to the town.
- Each district lights in its own way, so a glance says how far you've got.

## P0

1. [x] **At night the shed out-shone the town** (pillar 1). The boards, the lamp's pool and the live
   glow are pulled down at night.
2. [x] **The funfair and stadium didn't pay off.** Soft glows left bulbs a pixel wide. `GridLights.bulb`
   now has a solid core; the wheel's bulbs and spokes, the floods, the beams and the lit pitch are
   all stronger.
3. [x] **Giant dark discs across the sky**: a tree radius divided by a near-zero span. Clamped.
4. [x] **The town was too small** beside the shed, with a dead lower right. The road, rows, wheel,
   stadium and river were re-laid to fill y 636-890, and a farm added on the near bank.

## P1

5. [x] **The bridge's arches read as three balloons.** Now half-ellipses down to the water, with a parapet.
6. [x] **The near land ended in a hard vertical edge.** The lower river now paints over it.
7. [x] **Windows were flat squares.** Two panes with a bar; stronger halos. The lamp hung behind the
   flywheel and the meter under the lintel: both moved.
8. [x] **Night was too dark and rain too heavy, with a hard top edge.** Moonlight lift on the night
   palette, thinner rain faded in, a lighter storm gloom. Hay bales removed: they read as targets.

## Left

9. **Seasons or other places** (Safe Cracker has six). The rider asked for one scene; the palette table
   would take variants cheaply, if riders tire of it.
10. **Foreground sway.** The grass is baked. Not worth a draw call while the town carries the motion.

## Code review (LP-CODE-REVIEW)

`repair_need` is frozen at the warning so a callout can't go stale, and the note no longer says
WHOLE TOWN LIT while a district dims. See `DESIGN.md` §10.
