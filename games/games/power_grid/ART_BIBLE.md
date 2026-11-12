# Power Grid: art bible

> **Status:** v1, 2026-11-04. **Owner:** whoever changes the look. Change this file in the same commit
> as any change to the valley, the shed or the lights. **Sources of truth:** `GridValley.gd` (layout,
> palettes, every light), `GridShed.gd` (the shed and machine), `GridStage.gd` (live layers and
> effects), `GridLights.gd` and `shaders/`, `PowerGrid.look` (UI). `GFX_POLISH.md` records the work.

Everything is drawn in code, in Safe Cracker's craft (rider's decision for v1, 2026-11-04). The town
is nowhere real; nothing carries a maker's name, a team's badge or a fair's brand.

## 1. Identity

**The one rule:** *a dark valley that your legs light up.* When something is ambiguous, pick what makes
the town's lights the reward.

| Pillar | Design test |
| --- | --- |
| **The town is the score** | At night the lit town is the brightest thing on screen. Each district looks different lit, so a glance says how far you've got. |
| **Cause and effect** | The empty pedals turn at the rider's cadence, power runs visibly down the wires, and windows answer. Nothing lights by itself. |
| **A calm evening** | Slow motion, soft light, no flashing. It must suit a recovery ride. The storm is the one rough moment, and only in work. |

Flat-vector style: clean shapes, soft gradients, a few crisp highlights, no outlines. Not painterly.

## 2. Mood by state

| State | Look |
| --- | --- |
| Dusk | Rose and amber sky, the sun behind the far range, the town unlit but for the first windows |
| Night | Indigo, stars, a moon that climbs; the land still reads in moonlight |
| A district comes on | Window by window (houses), a wave along the road (lamps), bulbs and the wheel starting to turn (funfair), mast by mast (stadium) |
| Dimming | Its lights drop out one by one, unsteady, at about one flicker a second |
| Dark | Its feeder's dashes stop; its pip is struck through |
| Storm | A cloud bank rolls in, rain, two dim flickers, then one bolt on the line's pylon, and sparks |
| Whole town | Fireworks over the fair, the wheel turning, floods on the pitch |

## 3. The hero and the place

Two halves in one picture. **Left, the rider's half:** an open timber bay on the hill, lit by one
lamp: pedal crank, chain, flywheel, belt, copper dynamo, and a brass meter. **Right, the town's
half:** the valley floor from the church to the stadium. **Pylons** join them, smaller as they march
down the valley, and the wires carry the eye from the machine to the town.

## 4. Palette

Two painted palettes, `GridValley.PALETTE`, each colour `[dusk, night]`. Night is lifted 13% toward
`#3A4C86` (moonlight), so the land reads.

| Part | Dusk | Night |
| --- | --- | --- |
| Sky top / mid / low / horizon | `#23306A` `#6A4F8F` `#E07F72` `#FFC677` | `#050A1E` `#0C1536` `#1A2452` `#2F3A72` |
| Far range | `#8D6C9E` | `#1A2148` |
| Valley floor | `#5E6C5C` | `#141E34` |
| Near land | `#35463F` | `#0C1424` |

Light colours (`GridStatus.DISTRICT_COLORS` for the HUD): houses warm amber `#FFD27A`, lamps pale
sodium `#FFE9A8`, funfair rose `#FF8FA0` with amber and blue bulbs, stadium cold white `#BFE3FF`.

**UI harmony.** Arc blue `#8FD8FF` on dusk indigo `#151336`, skew 0.06: the cold of a spark against the
warm town. It's lighter and paler than Dodge's cyan, and isn't a meaning colour.

## 5. Silhouette check (rider, 2026-11-02; required)

Every main shape, checked in silhouette at about 25% size, for unintended readings:

| Shape | Reads as | Verdict |
| --- | --- | --- |
| Wire dashes (the only thing that travels a line) | short even dashes | Pass: **symmetric, no head, no tail**, by design (`grid_wires.gdshader`) |
| Pylon | lattice tower with arms | Pass |
| Church spire | pointed cone on a square tower, with a cross | Pass: pointed, never rounded |
| Chimneys | square stacks with a cap | Pass |
| Flywheel, chainring, pulley | wheels | Pass |
| Crank and pedals | a crank | Pass |
| Dynamo | a drum on a bed, seen end-on with its pulley | Pass: kept square-shouldered, one drum, not two lobes |
| Lamp shade, street lamps | a shade; a post and arm | Pass |
| Stadium, masts | an oval, posts with rectangular banks | Pass |
| Big wheel | a wheel on an A-frame | Pass |
| Tents, carousel | striped cones with a pennant | Pass |
| Lightning bolt | jagged polyline | Pass: no taper to a head |
| Birds | bare wing chevrons | Pass: no head, no tail |
| Sparks, fireworks, fireflies | round dots | Pass: dots only, no trails |
| Moon | a cratered disc | Pass |
| Hay bales | concentric rings | **Removed:** they read as targets at night |
| HUD pips | house, lamp, wheel, stadium | Pass |

Run this again for any new moving shape.

## 6. Environment and layout (1920 x 1080 stage, painted 160 px past each side)

- **Nothing tall under the HUD:** the far range tops out at y 352, every prop stays below the side
  panels (to y 338 in a circuit); drifting clouds, birds and the storm's bank stay below y 340.
- **The shed** stands on the hill at x 10-700, roof to y 486, floor y 892.
- **The town** runs from y 636 to the road at y 860-890; the road is its southern edge, so the cars
  and lamps are never hidden.
- **The river** comes down from the hills, under the bridge at (1333, 860), past the farm.
- **The callout lane** is y 150-220, between the panels; the moon stays under it.

## 7. VFX language

| Effect | How |
| --- | --- |
| Dusk to night | `grid_sky.gdshader`: two bakes mixed on one opaque sprite, lightning's lift and the storm's gloom in the same pass |
| Lights | `grid_lights.gdshader`: one mesh (and the wheel's), four levels; per vertex, the fragment only multiplies |
| Power | `grid_wires.gdshader`: dashes on a strip mesh, one phase uniform |
| River | `grid_river.gdshader`: drifting glints on a strip mesh |
| Rain | `grid_rain.gdshader` on one rect, only in storms |
| Sparks, fireworks, smoke, fireflies | `CPUParticles2D`, 6-34 each |

Nothing flashes faster than about twice a second. Lightning peaks at 0.42 of a lift, once a strike.

## 8. The frame check (rider, 2026-11-02)

`grid_layout_test` checks every prop against the stage and each HUD panel at its widest, with a
circuit's strip; the moon against the lane; the sky's scenery against the panels; the machine inside
its bay; the wheel above the road.

## 9. Tablet budget (Gen 2, PowerVR GX6250, Compatibility)

| Item | Budget | Now (desktop) |
| --- | --- | --- |
| fps | 60, at least 55 | **not measured: the tablet wasn't reachable** |
| Draw calls in play | ≤ 120 (UI_STYLE §8) | 62-72 with the HUD |
| Full-screen layers | one opaque; a rain rect in storms only | as budgeted |
| Per frame | transforms and about 12 uniforms; no `_draw` redraws | `grid_scene_test` checks no batch redraws |

## 10. Reference direction

- **Safe Cracker (this repo):** the craft bar: material detail, a lit place, ambient life that never
  redraws, a restrained palette.
- **Travel posters and picture-book landscapes:** layered ridges and one warm light. Take the layering;
  no type, no logos, no one illustrator's recognisable style.

## 11. Art-director review

**AD-ART-BIBLE: APPROVE.** The colour system serves the mood; the shape language follows from the
identity; the budget fits Safe Cracker's proven recipe. **AD-VISUAL: CONCERNS, then addressed:** at
night the shed out-shone the town, against pillar 1, so the boards and lamp were pulled down and the
funfair and stadium raised (`GFX_POLISH.md`, items 1-2).
