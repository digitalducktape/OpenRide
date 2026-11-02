# Keepy Uppy: art bible

> **Status:** v1, 2026-11-01, the look-and-sound slice (#77). **Owner:** whoever changes the
> look. Change this file in the same commit as any change to the palette, the light, the balloon
> or the weather. **Sources of truth:** `KeepyWorld.gd` (layout, per frame), `KeepyMeshes.gd`
> (every mesh), `shaders/*.gdshader` and `shaders/keepy_look.gdshaderinc` (the grade),
> `KeepyStatus` / `KeepyUppy.look` (UI). **Open** marks what the code doesn't do yet.
> **AD-ART-BIBLE:** reviewed in the art-director pass below (section 10).

Everything is procedural (primitive shapes merged into vertex-coloured meshes, shaders, a sky
drawn in code) except the Kenney nature-kit trees and bushes (CC0, loaded from
`games/dodge_ball/models/`, recoloured and baked into the meadow mesh), as Tug of War does.

## 1. Identity

**The one rule:** *a breezy summer afternoon in an open meadow: one bright balloon riding a
column of air you are making.* When something is ambiguous, pick what makes the balloon's height
and what the sky is about to do read faster.

| Pillar | Design test |
| --- | --- |
| **The balloon is the hero** | It is the brightest, most saturated thing on screen and always near the centre. Nothing else is coral. |
| **The wind is visible** | Every force shows in the world before it acts: a cloud's shadow creeps over the grass, a bird comes in from the side, the grass flattens in a band, the streamers whip. Text only confirms. |
| **Open air, soft and airy** | Wide sky (more than half the frame), long views, rounded hills, pale haze. Calm, never cluttered: this is the calm effort game. |

**Distinct from Balloon Pump (#76)**, built at the same time: that is a fairground pump stall
(striped canvas, a stall counter, lights, a crowd, a held pump, warm saturated fair colours, an
enclosed booth). Keepy Uppy has **no stalls, no stripes, no crowd and no fairground props**:
a wild meadow with nobody in it, cool-fresh greens and sky blues, one coral balloon. Its UI
accent is a **meadow mint**, not a fair red or gold.

Distinct from the family too: not Tug's warm timber and river, not Dodge's road, not Kart's
violet, not Cadence's neon. The closest neighbour is Kart Race's Meadow Ring (green hills): Keepy
has no track, no grandstand and no windmill, and its grass is long, flowered and swaying.

## 2. Mood by state

| State | Look |
| --- | --- |
| Calm | Warm sun from the upper left, high thin clouds drifting, grass swaying, the air column's streaks rising softly. |
| Climbing / high | The column's streaks run faster and brighter; the camera pitches up with the balloon so the horizon drops and more sky fills the frame: the feeling of height. |
| Rain cloud (warning) | A grey-blue cloud slides in from the horizon; its shadow, a dark soft ellipse, crosses the meadow toward the fan. |
| Rain | The cloud overhead, grey streaks falling through the column, the light cooled and dimmed by about a fifth. |
| Bird (warning, landing) | A small round bird flaps in from the side and perches on the balloon's top, bobbing it. |
| Downdraft (warning) | A darker band of flattened grass rolls toward the fan from the horizon; the column's streaks stall. During it: the streaks turn downward and the balloon squashes a little. |
| Gust (high band) | The streamers on the height pole whip; the balloon wobbles sideways. |
| Pop | A bright burst of coral shards and a white ring, a quick camera shake, then empty air over the fan for a moment. |
| New balloon | It floats in from the left on a long string from off-screen, the string lets go and the balloon settles into the column. |

## 3. Shape language

- **Round and soft everywhere.** The balloon is a sphere stretched slightly tall (a classic party
  balloon, a knot and a short curly ribbon below). Hills are rounded, trees are lollipop crowns,
  clouds are clusters of spheres, the bird is two spheres and a wedge.
- **The rig is the one built thing:** a chunky wooden pedal-fan box on the grass (a square crate
  with a round grille facing up and four blades) on short rails, linked to the bike's front by a
  belt (drawn as a dark band running off the bottom of the screen toward the rider).
- **The height pole** beside the fan is the hero prop for reading height: a tall wooden pole
  painted in three bands (low, mid, high) with a pennant streamer at each band line and a
  windsock at the top.

## 4. Colour system

| Role | Colour | Rule |
| --- | --- | --- |
| Balloon | coral `#FF5E5B`, highlight `#FFD6C9` | The only coral, the most saturated colour; a soft rim light so it reads against cloud and sky alike |
| Grass near / far | `#6FBF4A` / `#9CCB6B` | Fresh yellow-green near, paler toward the horizon |
| Hills | `#7FB86A` to `#B5D3A0` | Rolling, hazed toward the sky |
| Wildflowers | white `#F7F4E8`, butter `#F5D547`, lilac `#B8A1E3` | Small dots, never coral or red |
| Sky top / horizon | `#4FA3E8` / `#CFE9F7` | Clear, airy |
| Clouds | `#FFFFFF` lit, `#C9D6E3` shade; rain cloud `#7D8A9C` / `#5A6677` | |
| Fan rig, pole | pale pine `#C9A577`, dark `#6B4E2E` | Warm wood, the only built material |
| Height bands (pole) | low `#F2EFE6` cream, mid `#7FD3C4` mint, high `#F5C04A` sun | The same three colours as the HUD's band strip |
| Air column | white `#FFFFFF` streaks, additive and faint | Never opaque; it must not hide the balloon |
| Bird | slate `#465466`, cream belly `#EDE6D6`, beak `#F5A623` | Small and dark so it reads on the coral |

- **The grade** (`shaders/keepy_look.gdshaderinc`): fresh and airy, `LOOK_SAT 1.08`,
  `LOOK_CONTRAST 1.03`, `LOOK_GAIN vec3(1.0, 1.02, 1.02)` (a hair cool-fresh), `LOOK_LIFT
  vec3(0.0, 0.015, 0.03)` (soft blue-green shadows, never brown: that's Tug's), the vignette
  light (0.18) and painted into the view grid as Tug does.
- **UI palette.** Meadow mint accent `#2FD3B0` on deep pine ink `#0B2620`, badges leaning 0.08
  (a little lift). The band strip uses the pole's three colours. Meaning colours are the kit's
  (good, warn, bad, target gold). Coral stays in the world.
- **Colourblind safety:** bands are told by position (bottom, middle, top) and the multiplier
  number (1×, 2×, 3×), not colour alone; each force has its own icon word and sound.

## 5. Characters

No people. The **balloon** is the rider's avatar: it squashes a little when it sinks fast, bobs
on the column, and its ribbon trails. The **birds** are round slate birds, cartoon-simple, no
recognisable species or anyone's character; they flap in the vertex shader and perch facing the
camera. The rider never sees themselves: only the belt and the fan they drive.

## 6. Environment

- **Layout:** the fan 7 m ahead of the camera on the grass, the height pole 2 m to its right,
  meadow in every direction, a few trees wide of the column (never behind the balloon's path),
  hedgerow lines, hills, then haze. The column rises from the fan's grille up out of the top of
  the view.
- **Heights:** the balloon's centre is 1.1 m (on the grille: the ground) to 6.6 m (the top of the
  column) above the grass; the pole's bands match the logic's 0.35 and 0.65.
- **Density:** sparse and open. Flowers and grass tufts are one MultiMesh each; trees and
  hedges are baked into the meadow mesh.

## 7. VFX language

| Effect | Look |
| --- | --- |
| Air column | A tall open cone of soft white streaks rising (shader on one mesh), speed and brightness with the lift |
| Pop | 28 coral shards (`CPUParticles3D`, one-shot) and a white ring card expanding |
| Rain | One cylinder card of grey streaks falling under the cloud, alpha blended |
| Cloud shadow | A soft dark ellipse on the grass (a decal-like quad in the ground shader's uniform) |
| Downdraft | A wide curtain of dark, slanting air (the rain shader on one card) rolling in from the horizon to the fan over the warning, a dark band of flattened grass under it, and the column's streaks turning downward. The ground band alone was invisible at a grazing angle (AD-VISUAL), hence the curtain |
| Grass, flowers, streamers, windsock | Sway in their shaders with the wind |

Additive only for the column's streaks and the pop ring. Everything else alpha blended or opaque.

## 8. Camera

First person from the bike at 1.5 m, FOV 66. It **pitches with the balloon** (from +4° with
the balloon low to +22° at the top, eased) and, with Steer on, **pans gently toward the
balloon's side** (about a third of its offset, a 1.2 s lag), so the balloon stays near the centre
of the screen. A small shake at a pop. No roll.

## 9. Tablet budget (Gen 2, PowerVR GX6250, Compatibility; the tracker only with Steer on)

| Item | Budget |
| --- | --- |
| fps | 60, at least 55 sustained, with Steer's tracker on |
| Render scale | 0.62 in a SubViewport, no MSAA; 0.55 if play stays under 54 fps (`RenderScaleStep`) |
| Sky per pixel | one cubemap read (the full sky only in the cubemap pass) |
| Draw calls in play | ≤ 80 with the HUD (world ≤ 30) |
| Triangles | ≤ 60k |
| Ground per pixel | ≤ 2 noise reads |
| Per-frame GDScript | the balloon, the rig's blades, a handful of uniforms; grass, flowers, clouds and birds' wings move in shaders |
| Particles | the pop (28) only |

## 10. Art-director review (AD-ART-BIBLE)

**AD-ART-BIBLE: APPROVE**, with two notes carried into the build:

- The colour system matches the mood targets: one coral hero against a cool-fresh field, and
  each state changes the light or the ground before any text (the shadow, the dark band).
- Shape language follows from the identity (round and soft; the rig as the one built thing).
- The asset standards fit the family's proven tablet recipe (Tug of War: 13 world draw calls).
- Note 1: the air column must stay faint enough that the balloon and its birds read through it;
  keep it additive and under about 0.25 opacity at full lift.
- Note 2: the camera's pitch with height is the main "height" cue besides the pole; keep it
  eased (about 1 s) so a power change never swings the horizon.
