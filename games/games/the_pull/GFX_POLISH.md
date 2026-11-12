# The Pull: graphics polish punch list

From the graphics review of 2026-11-02 (the rider's ask: parity with the wave 1 games), against
`ART_BIBLE.md` (this folder) and captures of Tug of War and Dodge Ball taken the same day with
`tests/capture_ui_states.gd`. UI is in `UI_POLISH.md` and audio in `AUDIO_POLISH.md`.

**Before captures** (desktop, 1920×1008, with the HUD): in the session scratchpad,
`pull/before/the_pull_{1_intro,2_set,3_pull,4_dig_in,5_full,6_summary}.png`. **After:**
`review/the_pull/` (a copy is in `~/openride-scratch-backup/wave2/the_pull/`). Retake with:

```sh
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_pull.gd -- --out=DIR
```

**Status (2026-11-02):** items 1-9 are done. Item 10 is skipped, with the reason given there.
The draw calls in play are 71-74 with the HUD (68-85 before). The mirror renders every other
frame. The tablet still needs a run.

## What works (keep)

- The composition: the track's vanishing point dead centre, the distance boards on the left and
  the best flag on the right, both readable at a glance.
- The look back at the sled during SET tells the story of the game without words.
- The dusk palette: warm clay under floodlights against a deep blue sky.

## P0: the near field (what fills the screen)

1. [x] **The clay is one orange slab.** Before, the bottom half of `3_pull` was a single
   saturated orange and the pools didn't read. Now the clay is less saturated (`clay`
   0.47/0.30/0.22) and darker between the pools (ambient 0.42, pools ×1.65). It has chevron tyre
   treads in the runner grooves, clods from the brightest grain (no extra noise read), a redder
   berm banked against each barrier, and a damp sheen inside the pools. The review of 2026-11-04
   found the lower frame still swung from a bright slab under a tower to dark brown between
   them, and had nothing in it. Within about 5-26 m of the rider the light now holds at a steady
   level (`near_pool`), with raked lines, cross ripples and fine grit in the lower frame (a third
   noise read), and the middle of the track sits a little darker than its edges.
2. [x] **The bike up front: just the handlebars.** The first version was three blobs and a
   pole. Two rounds of gloves followed, and the reviewer and the rider rejected them: they read
   as small dark blobs, then the rider asked for no arms at all ("be consistent and just show the
   bike handles"). The view now matches Dodge Ball's bars: a thin steel bar low in the frame,
   rubber grips, short drops and a short squared stem in the accent. No hands, no round cap, no
   tyre.

3. [x] **The mirror didn't show the sled.** The sled couldn't be read at 1 m (the review of
   2026-11-04). The glass is now 0.34 × 0.21 m in a slim chrome rim on a jointed stalk, the oval
   fills its quad, and its camera is tight on the sled (27°). The sled and chain keep most of
   their light anywhere on the track (`self_lit` 0.6), and the glass lifts the image 1.3×. It
   stays clear of the frame, the HUD and the longest centre message (the scene test's bounds
   check).

## P1: the place

4. [x] **The stands were dark boxes.** The front walls are painted panels in five colours
   (blocks and stripes; no words or logos), with corrugated roofs on posts. Pennant bunting
   along each eave sways (`COLOR.a`), with a string of warm bulbs under it. All of it is baked
   into the one scenery mesh: still one draw call.
5. [x] **The crowd was still.** The figures are slimmer and raise their arms when the crowd
   cheers, each on its own beat (near the best, on a board, at a Full Pull). Some wear caps. It
   all happens in the crowd shader, so the GDScript cost per frame is unchanged.
6. [x] **No light in the air.** Each floodlight head now has an additive halo (one MultiMesh, 26
   quads, `glow.gdshader`), and 36 dust motes drift in the light around the rider (CPU particles
   that follow the rig). The halos flare with the Full Pull.
7. [x] **A flat sky.** Long cloud banks near the horizon, their undersides lit by the sunset
   (one noise read in the sky shader).
8. [x] **The far fair didn't move.** The lit wheel turns slowly (its own mesh, one draw), and
   its gondolas hang under every other light.

## P2

9. [x] **The best flag and the Full Pull arch** keep their v1 look; the review found nothing to
   fix. The flag's "YOUR BEST" label sits in front of the cloth.
10. [ ] **Fireworks over a Full Pull.** Skipped. The confetti, the flare, the crowd jump and the
    fanfare already mark it. Fireworks would add a second particle system with its own shader
    compile behind the intro card, for a moment that most rides never reach.

## Silhouette check (rider, 2026-11-02)

See `ART_BIBLE.md` §10. Every main shape was checked at small size: the dust motes and the
halos are round with no tail, the confetti is squares, the chain is rings, the pennants are
triangles, and the crowd has arms up, not tails. Nothing reads as anything unintended.
