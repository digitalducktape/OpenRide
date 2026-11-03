# Watt Lane: art bible

> **Status**: Approved for the rework slice (AD-ART-BIBLE: APPROVE, notes at the end)
> **Owned by**: art-director pass, 2026-11-02 (third look: abstract)
> **Scope**: the 2D field (`WattLaneBackdrop`, `shaders/wl_field.gdshader`), the lane and cursor
> (`WattLaneTrack`, `shaders/wl_lane.gdshader`), the HUD widget (`WattLaneStatus`) and the hub
> card. Rules are in `DESIGN.md`.

**History.** The first slice was a 3D night highway; the rider found a lane that moves sideways
reads as "lean". The second was a 2D music staff of power lines with a note-head marker; its
marker failed the silhouette check (below). This third look is the rider's direction: "just make
it abstract, a chevron cursor following an illuminated horizontal lane."

## 1. Visual identity statement

**"One lit lane through the dark, one arrow riding it."** A flat, deep night field; across it a
lane of warm light that comes in from the right and steps up or down; a chevron (▶) holding it.

- **The lane is the only warm, bright thing.** When something competes (the HUD, the field's
  layers), dim it. Serves "know at a glance if you're in".
- **Flat and horizontal, never a tunnel.** Depth comes from layers moving at different speeds,
  not perspective. This is what keeps it apart from Cadence Karaoke's neon tunnel.
- **The future is drawn ahead.** A step appears on the right first (its riser, chevrons, its new
  watts), then in the HUD's chip, then as a chime.
- **Up is more.** More watts, higher. Nothing in the picture moves sideways for the rider.

## 2. Mood and atmosphere

| State | Target | Light | Descriptors | Energy |
| --- | --- | --- | --- | --- |
| In the lane | locked in, calm | the lane at full glow, a beam from the chevron along it, the field warming around it, the edges pulsing with the beat | warm, steady, humming | medium |
| Out of the lane | a nudge, not alarm | the lane dims to two-thirds, the chevron's rim and glow turn amber, PUSH or EASE in the HUD | cooler, quieter | low |
| A step coming | anticipation | an amber riser where the lane jumps, chevrons leading to it, its new watts beside it | expectant, clear | rising |
| Caught it | release | the lane and the chevron flash, gold sparks | bright, crisp | peak |
| Intro / pause | still | the same field and lane, held | quiet | low |

## 3. Shape language

- **Horizontal bands and lines.** The lane, the watt scale's guides and the path are horizontal;
  the beat lines are thin verticals. No curves except the lane's smooth step.
- **The chevron (▶)** is the only solid shape: four points, a notched arrowhead, an ink outline,
  a rim, a white-hot face with a lit upper facet. Angular on purpose.
- **Amber chevrons** inside the lane mean "a change is coming"; they point up or down.
- **Round only for light**: the bokeh and the chevron's glow are soft discs with no edge and no
  tail, and they never move with a trail.

## 4. Colour system

| Name | Hex | Meaning |
| --- | --- | --- |
| Lane gold | `#FFC752` | the lane (the target: the framework's gold, TARGET) |
| Edge light | `#FFEDBF` | the lane's edges, the beam, a catch |
| Signal amber | `#FFB020` | a change is coming; out of the lane (WARN) |
| Good green | GameTheme `GOOD` | the chevron's rim in the lane (backed by "In lane" and the hum) |
| Path blue | `#BFE6FF` | the dashed path behind the chevron |
| Field teal | `#05121C` → `#08202B` | the field, its grid and bokeh |
| Copper | `#F0875A` | the game's accent: HUD panel edges, buttons, the hero's gradient |
| Dusk navy | `#0F1A2E` | the game's ink |

- Cool field, warm lane: everything big is teal and dark; the lane's gold is the only warm
  light. **Distinct from Cadence Karaoke** (magenta, cyan, violet neon in a tunnel).
- **The accent is copper, not lime** (the first slice): an accent must never read as a meaning
  colour (UI_STYLE.md §4), and lime reads as GOOD green.
- **Colourblind backups:** in or out is never colour alone: the HUD says In lane / PUSH / EASE,
  the hum changes, the lane dims. Steps carry shape (chevrons, the riser) and sound.

## 5. Character design direction

No characters. The rider is the chevron: a pointer, not a creature.

## 6. Environment design language

- **The field** (one shader rect, far to near):
  - two huge soft washes of teal and copper, drifting very slowly (sampled from a low mip, so
    never mottled);
  - bokeh discs at a third of the lane's speed;
  - a dot grid at half speed;
  - the watt scale's five faint guides, one every 12.5% of FTP;
  - beat lines at the lane's own speed, one a beat, brighter at each bar and flaring on the beat;
  - a vignette and a pixel of dither.
- **No imported textures.** Everything is drawn in two canvas shaders and one `SafeMesh` batch
  (the chevron), on the full 1080p canvas with no SubViewport.
- **Density:** the field stays dim (each layer under 10% brightness) so the lane dominates.

## 7. UI/HUD visual direction

- The HUD's top-centre widget (`WattLaneStatus`): the lane's exact bounds as the hero
  ("115–165", 96 px, copper gradient), "W LANE", the streak, "In lane 82%", and PUSH / EASE /
  PEDAL; before a step, the amber chip "▲ UP 135–185 in 3" takes the second row.
- On the field: the step's new bounds ("135–185 W", 40 px, amber, outlined in ink) beside the
  riser, the same numbers as the chip.
- Lilita One, upright (lean 0). Nothing below 34 px.
- Motion: framework tweens (pop, slam, fade); nothing laid out per frame.

## 8. Asset standards

- No imported assets. The field and the lane are canvas shaders on two rects; the chevron is one
  `SafeMesh` batch, redrawn only when its state changes; catch sparks are one CPUParticles2D.
- **Tablet budget** (Gen 2, PowerVR GX6250, Compatibility): no SubViewport; about 1.7 screens of
  fill a frame (the field 1.0, the lane rect 0.67, the chevron's glow small); per frame, three
  64-float arrays and a dozen uniforms. The field's noise reads: 6 a pixel (fallback: drop the
  far washes, 2 reads).

## 9. Reference direction

- **Long-exposure light trails at night:** the warm glow against deep dark. Avoid motion blur
  across the frame.
- **Data-visualisation and audio-meter interfaces:** a clean band and a pointer, legible at a
  glance. Avoid any specific app's look.
- **Ambient generative art (soft bokeh, grids):** depth from layers. Avoid a neon synthwave
  grid floor, which is Cadence Karaoke's world.

## Silhouette check (required; rider, 2026-11-02)

Every main shape, viewed as a black silhouette at hub-card size (about 1/4 scale) and at full
size, for unintended readings:

| Shape | Silhouette | Verdict |
| --- | --- | --- |
| The chevron (▶) | a notched arrowhead, four straight edges | reads as a pointer only. **Pass** |
| The chevron's glow | a soft round disc behind it, no edge, no tail | reads as light. **Pass** |
| The path behind the chevron | a dashed straight-segmented line, separated from the chevron by a 34 px gap, the same width all along | reads as a dotted path, not a tail. **Pass** |
| The lane and its step | a horizontal band with a smooth S-step | reads as a band. **Pass** |
| The amber chevrons in the lane | V or Λ strokes | reads as arrows. **Pass** |
| Bokeh | soft discs, static or drifting slowly, no trails | reads as out-of-focus light. **Pass** |
| Catch sparks | small squares in a burst, short-lived | reads as sparks. **Pass** |

**Rule kept from the failure:** a moving marker, cursor or particle never has a round head with
a wavy or tapering tail. The music-note marker (an oval head with a stem and a glowing trail)
failed this and is gone; nothing round moves with a trail.

## AD-ART-BIBLE review (art-director gate)

**APPROVE.** The colour system follows the mood (one warm element in a cool field), the shape
language follows "one lit lane, one arrow", the silhouette check passes, and the budget is under
Safe Cracker's measured 2.1 screens of fill. Notes: (1) check the gold lane against the amber
step marks on the tablet's warm panel; (2) if the beat flare reads as flicker on the bike, halve
it (`beat` in `wl_lane.gdshader` and `wl_field.gdshader`).
