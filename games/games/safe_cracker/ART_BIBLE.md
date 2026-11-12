# Safe Cracker: art bible

> **Status:** v2, 2026-10-20: the graphics pass (branch `gfx-safe`) built every Target below
> except the cabin's tilt; v1 was the review of `games-polish` at 6ef6fab. **Owner:** whoever changes the look. Change this file in the same commit
> as any change to the places, the safe, the dial's drawing or the effects. **Sources of truth:**
> `SafePlaces.gd` (rooms, palettes, key lights), `SafeBackdrop.gd` (ambient life), `SafeBody.gd`
> (the body and the vault), `SafeDoor.gd` (the static door), `SafeDial.gd` (the dial's layers and
> the swing), `MeshBatch2D.gd` (the batcher), `SafeBackdrop.vignette`, `SafeCracker.look` (UI).
> `GFX_POLISH.md` records the work.

Everything is drawn in code. The six places are plain descriptions; no film, game or brand is
referenced, and nothing on the safe carries a maker's name.

## 1. Identity

**The one rule:** *one heavy steel safe in a pool of light, in a room that tells you where you
broke in.* When something is ambiguous, pick what makes the dial and the safe's weight read.

| Pillar | Design test |
| --- | --- |
| **The dial is the hero** | Highest contrast and sharpest edges on screen. Nothing in the room competes with its brightness or its brass. |
| **Weight and craft** | The safe is thick riveted steel with bevels, hinges, a handle and bolts. Every shape has an edge highlight and a shadow; nothing is a flat panel. |
| **Noir light** | One key light per room (lamp, window, spotlight) and deep shadow elsewhere. Warm brass against cool dark. Calm: a recovery ride, so motion is slow and small. |

The 2D flat-vector style stays: clean shapes, no outlines on the room, soft gradients, a few
crisp highlights. Not painterly, not photographic.

## 2. Mood by state

| State | Look |
| --- | --- |
| Turning | The room still and dim; the lamp's pool on the safe; dust in the light. |
| On target | The reading turns green; the dial's glass catches a glint. |
| Tumbler clicks | The newest brass light pops; bolts on the door's edge slide back (five, spread over the combination). |
| Alarm | The safe glows red round its body (`SafeDial.alarm_glow`) and pulses; a red wash over the room from the left, as if a light came on. |
| Cracked | The door swings open in perspective, its thickness showing, on a lamp-lit vault; warm light spills out and 18 gold sparkles rise. |
| Next safe | The safe slides in on a new room. |

## 3. Palette per place (`SafePlaces.PLACES`)

| Place | Wall / lower wall | Floor | Safe | Accent | Key light |
| --- | --- | --- | --- | --- | --- |
| Night office | `#1A2B38` / `#0F1A24` | `#1A1412` | `#575E66` | `#F2BF59` | Desk lamp right, warm; blind stripes from a moonlit window left |
| Bank vault | `#5C6169` / `#3D424A` | `#29292E` | `#80858C` | `#D9A640` | Cold overhead strip, top |
| Museum hall | `#9E8F75` / `#80705C` | `#544033` | `#404D5C` | `#E6CC80` | Two picture spotlights, warm |
| Ship's cabin | `#614026` / `#472E1C` | `#332117` | `#384D47` | `#E6B34D` | Swinging lantern right; sea light through the porthole |
| Laboratory | `#9EBDB3` / `#809E94` | `#4D5C5C` | `#B3B8BD` | `#4FB4C8` | Cool fluorescent top; flask glow |
| Old library | `#4D3024` / `#331F17` | `#241712` | `#473D4D` | `#E6B84D` | A reading lamp, warm, low |

Rules:
- The safe is always a mid value against its wall: lighter on dark rooms, darker on the light
  ones (museum, lab). Its body never matches the wall's value within 15%.
- The accent (brass) appears on the dial's target plate, the tumbler lights and the room's key
  prop only.
- Shadow colour is the room's lower wall darkened, never neutral black; the vignette uses the
  UI's soot `#14110D`.

**UI harmony.** The HUD is brass `#E8B04A` on soot `#14110D` (`SafeCracker.look`). Each place's
accent is a brass or, in the lab, a teal that must not read as the reading's "on target" green
(`GameTheme.GOOD`): `#4FB4C8` (`#5CC7B0` was too close; `safe_gfx_test` keeps it apart).

## 4. Light, materials and drawing

- **Everything goes through `MeshBatch2D`**: one triangle array per node with per-vertex colours
  (one draw call), every filled edge feathered 1.2 px to transparent (Compatibility has no 2D
  MSAA). Never `draw_circle`, `draw_colored_polygon` or `draw_arc` directly: each is a draw call.
- **One key light per room** (`PLACES[i].light`), drawn, not computed: a smooth many-ring pool
  (`MeshBatch2D.glow`) in the room's batch, a pool on the floor under it, and a soft shadow of the
  safe cast away from it. No `Light2D` (each lit item would draw again) and no light texture
  (an extra full-screen layer).
- **The room is baked.** The room's batch and the vignette render once per place into one
  texture at the screen's own resolution (`SafeBackdrop.bake`), shown as one opaque sprite; the
  ambient life draws over it. So the room may stack as many fills as it likes: they cost the
  tablet once, not every frame. Nothing that moves goes in the bake.
- **Steel:** top-lit, the key light's side brighter and warmer (`SafePlaces.steel_shade`, an
  affine relight so fans interpolate it exactly); a 5-6 px bevel bright on the lit edges, dark
  on the far ones; brushed streaks at 4-6% white, seeded per place; rivets with a highlight dot
  toward the light. Redrawn only on a place change.
- **Glass:** a soft arc band over the ticks at the upper left (13% white at its middle), a faint
  one lower right, never over the numbers' centres; a glint while on target.
- **Gold:** bars with a top face and a front face, coin stacks on a shelf, a lamp-lit vault; a
  warm additive spill fades in as the door opens.

## 5. Shapes and proportions

- **The safe:** body 980 × 740, a door inset 50 px with a 28 px thickness showing on its free
  edge as it opens (it turns 72° toward the viewer about the hinge, seen from 3400 px: short of
  edge-on, so its face never flips), two hinges on the left, a compact four-spoke
  handle wheel under the tumbler lights, a column of bolt ends along the door's right edge (they slide
  back as tumblers click), short feet. Rounded corners 22-34 px. The dial stays centred where it
  is (`SafeDial.R` 262), so the layout tests hold.
- **The rooms:** the floor line at y 905; props stay outside the safe's footprint (x 470-1450)
  except where they pass behind it. Perspective is a gentle one-point floor (boards or tiles
  converging toward the safe), never a tilted wall.

## 6. Environment per place

- **Office:** venetian blind stripes of moonlight across the wall from the window; rain
  streaking down the window (a scrolling shader on that rect); a desk lamp's warm pool.
- **Bank:** a round vault door edge on the wall behind, steel panel seams, bars.
- **Museum:** the two framed pictures under spotlights, a rope barrier on brass posts.
- **Cabin:** timber planks, the porthole with a moving sea line, the lantern swaying slowly
  (a rotation tween). No tilt of the whole room: a moving room reads as motion.
- **Lab:** shelves of flasks with a slow bubble shimmer, tiled floor, a fume-hood outline.
- **Library:** shelves with spines, a rolling ladder, a reading lamp, dust motes in its beam.

## 7. VFX language

| Effect | Look |
| --- | --- |
| Tumbler click | The newest light pops; bolts slide back |
| Alarm | A red edge glow on the safe, breathing; a red side wash |
| Crack | The swing, the warm spill, 18 gold sparkles rising (one `CPUParticles2D` burst) |
| Ambient | 16 dust motes in the key light, rain on the office window, the porthole's sea, the lantern's sway, the flasks' shimmer |

All slow and soft: this is a recovery game. Nothing flashes faster than twice a second.

## 8. Camera

None: a fixed 1920 × 1080 canvas, the safe centred at `BODY_HOME`. The only motion is the safe
sliding in and its door. Never shake the view.

## 9. Tablet budget (Gen 2, PowerVR GX6250, Compatibility, tracker OFF)

| Item | Budget | After the pass (desktop, 2026-10-20) |
| --- | --- | --- |
| fps | 60 (≥ 55 sustained) | measured on the bike before the tablet pass: 50 avg in play (min 36), 31 in the intro (min 20); re-measure after it (GFX_POLISH.md, "Tablet performance") |
| Pixels a frame (`tests/measure_safe.gd`) | ≤ 3 screens in play, ≤ 4 at the worst moment | 2.1-2.2 screens in play, 2.7 with the alarm, 3.6 during a crack or under the intro card (was 6.9-7.7, 8.2 in the intro) |
| Draw calls in play | ≤ 100 with the HUD | 50-52 (54-57 with the alarm, the swing or the cover); 86-258 before |
| Redraws | the room and body only on a place change; the dial only on a shown change (`SafeDial.refresh`) | as is; a needle step redraws nothing, a new whole number only the reading's text |
| Animated parts | shaders (`TIME`) or tweens on a node's transform or modulate, never a `queue_redraw` per frame | as is; the only redraws while animating are the light pop (0.35 s) and a bolt sliding (0.45 s) |
| Full-screen layers | the room, the vignette: at most 3 full-screen blended layers | 1: the baked room with its vignette (was 3: a backing rect, the room's 2-3 screens of fills, the vignette); the alarm wash covers the left half while it holds |
| Particles | ≤ 40 alive (`CPUParticles2D`) | 16 dust, plus 18 sparkles for 2 s on a crack |

The canvas runs at full 1080p and the tablet pays for every blended pixel, seen or not, so the
rules are: anything static and full-screen goes in the room's bake; a shape under an opaque one
gets a hole (`MeshBatch2D.round_frame`, `holed_round_rect`, the `hollow` of `glow` and
`soft_shadow`); what's hidden is not drawn (the vault while the door is shut). Check a change with
`tests/measure_safe.gd`, which prints each layer's pixels per place.
