# Watt Lane: graphics polish punch list

> **Status:** every item done on `games-78-watt-lane` (2026-11-02) except item 8 (tablet), which
> needs the tablet. The notes under each say how.

From the graphics review of 2026-11-02 against `ART_BIBLE.md` and the wave 1 references (Safe
Cracker, Tug of War, Dodge Ball), after the rework to an abstract 2D lane. Gameplay and tuning
are out of scope; the UI is in `UI_POLISH.md`.

**Captures** (desktop, 1920×1008, with the HUD), in the review's scratchpad
`review/watt_lane/`: `before/a1_muddy_lane.png` and `before/a2_cursor_under_hud.png` (before),
`wl_{1..6}_*.png` (after), and `refs/{safe_cracker,tug_of_war}_*.png` with
`refs/watt_lane_*.png` for the side by side. Retake with:

```sh
$GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_watt_lane.gd -- --out=DIR
$GODOT_BIN --path games -s res://tests/capture_ui_states.gd -- --game=watt_lane --out=DIR
```

`watt_lane_scene_test` keeps the layout and the HUD's agreement honest; keep it and the full
suite green.

## What works (keep)

- One warm lane in a cool field: it reads at a glance from across the room.
- The step is visible about 9 s ahead, with a riser, chevrons and its watts where it lands.
- The chevron is unmistakably a pointer (the silhouette check passes).
- Depth from layered motion (bokeh, dot grid, beat lines) instead of a tunnel's perspective.

## Items

1. **The lane's body read as muddy olive** (`before/a1_muddy_lane.png`). The body was an opaque
   tint (alpha 0.14) over the teal field. **Done:** the body is light, not paint: additive glow,
   brighter toward the edges like a lit tube, alpha 0.03.
2. **The cursor rode up under the ride panel** at high power (`before/a2_cursor_under_hud.png`,
   214 W at a 150 W FTP). **Done:** `TOP_Y` 330 → 372, clear of the top bar; the step label
   above a high lane stays under it too.
3. **Out of the lane, the lane went dead grey** (glow 0.5). **Done:** 0.68: dimmer, still lit.
4. **The field was sparse next to Safe Cracker's rooms and Tug's fairground.** **Done:** a
   farthest layer of two huge soft washes (teal and copper) drifting very slowly.
5. **The washes first came out mottled** (camouflage blotches from the noise's fine mips).
   **Done:** sampled from mip 4 at a quarter of the scale: broad, smooth.
6. **Nothing tied the picture to the music.** **Done:** the lane's edges, the field's beat lines
   and the chevron's glow pulse on the music's beat (112 bpm), one bar line in four brighter.
7. **A satisfying "in lane" state.** **Done:** while in the lane a beam runs from the chevron
   along it, the field warms around the lane, the chevron's rim is green; a catch flashes the
   lane and throws gold sparks.
8. **Tablet cost.** Done: see "Tablet performance" at the end.

## Removed with the rework (for the record)

- The 3D night highway (a road read as "lean to change lanes").
- The power-line staff, its four illustrated places and the note-head marker (the marker failed
  the silhouette check; the rider asked for an abstract look).

## Reviewer's punch list (2026-11-02), done

9. **The last step chevron was cut by the lane's bend** (`wl_3`). **Done:** only whole chevrons,
   each at its own centre's lane height, ending 130 px before the step (the bend starts about
   90 px before it).
10. **The step label was small and sat low.** **Done:** 56 px, white with an ink outline, just
    inside the new lane at its top, right of the riser.
11. **The top 40% of the field was empty next to Safe Cracker.** **Done:** a horizon of light
    behind the top of the scale and two slow ribbons of light (teal and copper) drifting at a
    tenth of the lane's speed, all dimmer than the lane.

## Tablet performance (2026-11-06)

Measured on the bike's tablet (mock build, real play, 5-minute Just Ride): **31 fps, worst 30,
GPU-bound** before; **60-61 fps** after, for 80 s of play. The GX6250 is fill-bound, and the look
paid per pixel per frame:

- **The field** ran noise, `exp`, a ribbon loop and a vignette on every pixel. Now everything still
  is baked once at the window's size (`wl_field_bake.gdshader`), the dots, bokeh and streaks once
  into a 512 px tile (`wl_tile_bake.gdshader`); per frame, two texture reads and a beat line. The
  ribbons and bokeh no longer twinkle, and the warm light around the lane is gone.
- **The lane** indexed uniform arrays and ran `exp` per pixel over two thirds of the screen. Now it
  is a strip mesh over only the lane and its glow, its light per vertex (rows packed at the
  edges), with one texture read a pixel. The beam, riser, chevrons and path are small drawings.
- **The speckled fill:** per-pixel noise thresholds on large coordinates. The streaks are now a
  soft baked texture, with coordinates worked out per vertex in highp and scrolls wrapped on the
  CPU.
