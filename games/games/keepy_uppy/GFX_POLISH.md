# Keepy Uppy: graphics polish punch list

> **Status:** 2026-11-02, the 2D rework. Items 1-6 done; 7-8 left (why under each). In play: 56-73
> draw calls with the HUD on the desktop (the most with rain, two birds and a bird coming in),
> 15-24k primitives.

From the graphics review of 2026-11-02, after the 2D rebuild, against `ART_BIBLE.md` (this
folder) and the reference games: Safe Cracker (the 2D bar: one illustrated hero, a lit place,
ambient life that never redraws) and Tug of War (a lit world, warm and lively).

**Captures** (desktop, 1920x1008, with the HUD), kept in `~/openride-scratch-backup/wave2/keepy_uppy/`:
`gfx_before/` (the first 2D build, and `compare.png`: Safe Cracker's office and Tug's river
beside Keepy's meadow and park) and `gfx_after/`. Retake with:

```sh
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_keepy.gd -- --out=DIR --places
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_keepy.gd -- --out=DIR --place=meadow
```

`keepy_scene_test` checks the frame (the balloon, the fan and the pole never clipped by the frame,
the grille or a HUD panel), that playing redraws nothing, and that a new place bakes once.

## What works (keep)

- The balloon reads at a glance: one coral egg, lit from the place's sun with a sky rim.
- Four places with their own light and their own ambient life; the place cross-fades every three
  minutes in a long ride.
- Every force is visible before it acts (the rain cloud, the bird, the downdraft's curtain, the
  streamers).
- Nothing redraws in play; the place is one baked sprite.

## P0

1. **The fan didn't read as an object** (`KeepyRig._paint_crate`). Next to Safe Cracker's safe the
   first crate was five flat planks and four brackets: a box, not a built thing. Add a shipping
   crate's cross braces (with a cast shadow and a lit top edge), a plinth board at the foot, and a
   light bevel along the top. **Done:** it reads as a heavy wooden crate at half size.
2. **The places were flatly lit** (`KeepyPlaces.build_scene`, `KeepyBackdrop.vignette`). Safe
   Cracker's rooms each have a key light the safe agrees with; ours had a sun in the sky and a
   faint pool. Warm the ground round the fan toward the sun (a wider, brighter pool, offset to
   the sun's side) and deepen the vignette so the eye goes to the column. **Done.**
3. **The far land sat on top of the near land** (every place). Add a haze band along the horizon
   in the place's haze colour. **Done.**
4. **The grass was a flat field** (meadow, seaside, park). Safe Cracker's floors converge on the
   safe; ours didn't tell the eye where the fan stands. Mown stripes in one-point perspective
   toward the fan. **Done** (the rooftop has its deck boards already).
5. **A black band showed where a ridge dipped** (meadow, park: the bake's clear colour). Paint the
   land under every ridge first. **Done.**
6. **The balloon floated without touching anything.** Add its shadow on the grille: darker and
   tighter the lower it flies (`KeepyRig.set_shadow`), gone above the mid band. **Done.**

## P1

7. **Ridge and tree rim light toward the sun.** The trees have a sun-side highlight; the ridges
   don't. *Left:* the haze band and the stripes gave most of the depth; a rim on every ridge
   adds vertices to every bake for a small gain. Revisit with the reviewer's list.
8. **A second hero motion at rest** (Safe Cracker's dust in the light). The column, clouds and
   the place's ambient life already move; *left* to keep the full-screen blended layers at zero.

## Earlier fixes in this rework (before this review)

- The grille drew at the fan's position twice over (it used screen coordinates inside the fan's
  node): moved into the fan's own space.
- The rain cloud was too big and sat under the HUD's status widget: smaller (340 px), lower
  (y 380), sailing in from the right at the balloon's height.
- The pop's shards were specks: twice the size.
- The bird used to fly in at the ride panel's height: it now comes in low from the left.
