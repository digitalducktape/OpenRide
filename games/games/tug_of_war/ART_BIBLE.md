# Tug of War: art bible

> **Status:** v2.1, 2026-10-20: the tablet performance pass (`GFX_POLISH.md`, Tablet
> performance: the sky from its cubemap, the vignette in the view grid, haze per vertex) on v2,
> the graphics pass (every item done), on v1 of 2026-10-19. **Owner:** whoever changes the look. Change this file in the same commit as any
> change to the palette, the light, the bot, the crowd or the effects. **Sources of truth:**
> `TugWorld.gd` (layout, per-frame), `TugMeshes.gd` (every mesh), `shaders/*.gdshader` and
> `shaders/tug_look.gdshaderinc` (the grade), Dodge Ball's `tod/*.tres` (shared presets),
> `TugStatus` / `TugOfWar.look` (UI). **Open** marks what the code still doesn't do.

All of it is procedural except the Kenney nature-kit trees, bushes and rocks (CC0, loaded from
`games/assets/models/`, recoloured and baked into the riverside mesh). The bots are plain material-and-animal names, nobody's character.

## 1. Identity

**The one rule:** *a summer fairground contest across a lazy river: you against a wind-up tin
robot, and the rope between you is the story.* When something is ambiguous, pick what makes the
rope, the flag and the bot's pose read faster.

| Pillar | Design test |
| --- | --- |
| **The rope is the stage** | Nothing crosses the line from the rider's fists to the bot. The flag's place on the rope reads from 1 m at a glance. |
| **A hand-made fairground** | Timber, rope, bunting, painted tin. Warm wood and saturated toy colours against cool water. Rounded, chunky, slightly toy-scaled. |
| **Effort shows in the world** | The bot braces, the crowd cheers, the rope tightens and sags with tension. Every state change shows in pose and light before any text. |

Distinct from Kart (no karts, no violet grade) and from Dodge (no road; warm and woody where
Dodge is cool and asphalt). Tug shares Dodge's sky and time-of-day presets, so the two must
diverge in the grade and the materials, not the sky.

## 2. Mood by state

| State | Look |
| --- | --- |
| Even | Calm river, the crowd bobbing, torches flickering. Flag mid-rope. |
| Winning | The bot leans forward and slides; the near crowd hops higher (`excitement`). |
| Telegraph | The bot's eyes flash amber, it braces (-10°), its wind-up key spins fast and its chimney puffs steam. |
| Surge | Red eyes, -16° lean, a small rumble shake, steam jets from the chimney. |
| Win | The bot topples into the river: splash, ripple ring, crowd jumps. |
| Lose | The camera is pulled in and dips toward the water: the water fills the view. |

## 3. Palette

| Role | Colour | Rule |
| --- | --- | --- |
| Deck timber | `#8C6138` planks, gaps `#2E1F14` | Warm, the brightest wood near the camera. A procedural plank shader (`deck.gdshader`), never a magnified blurry texture. |
| Pilings, posts | `#4D331F` | Dark, so the pier ends frame the river. |
| Water deep / shallow | `#12405C` / `#29758C` | Cool: the river is the one big cool area. Sky shows at grazing angles. |
| Banks | `#4D8033`, earth `#6B5233` | A sloped earth bank with reeds and shore rocks, never a box edge. |
| Rope | `#C7A86B` / `#8C6B42` stripes | The lightest warm line on screen. |
| Flag | `#FF401F` | The only red; the bot's eyes may flash red in a surge. |
| Bot bodies | `BOT_COLORS` (rust, copper, tin, brass, iron, steel, zinc, chrome) | Metallic hues, matte painted tin (no real specular). |
| Crowd shirts | `CROWD_COLORS` | Saturated, but darker than the flag. |
| Torch flame | `#FF9933` | Warm emissive, brighter at dusk and night. |

**UI harmony.** The HUD is rope orange `#FF9F1C` on bark `#2A160B` (`TugOfWar.look`), YOU in the
gloves' blue `#5980D9` and BOT in the bot's body colour. Keep the rider's sleeves that blue, the
flag the only red, and the rope orange-tan so the meter and the world agree.

## 4. Lighting, materials and shading

- **One hand light**, `framework/shaders/world_look.gdshaderinc` through
  `shaders/tug_look.gdshaderinc`: every surface `unshaded, fog_disabled`, lit by `sun_light` per
  vertex (the water, deck and crowd per pixel or per quad), hazed per vertex on the big surfaces
  (water, deck, riverside, crowd) and graded per pixel, from one table
  per preset (`TugWorld.look_for`). The sun node only places the sky's disc. The gloves have
  their own fixed key light; the eyes, flames and bulbs are self-lit.
- **Tug's grade** (the `LOOK_*` defines in `tug_look.gdshaderinc`; the sky repeats it in its
  cubemap pass). The vignette is not per pixel: since the tablet performance pass it is painted
  into the vertex colours of the grid that draws the view on screen (`StageView3D.view_image`),
  so it darkens the sky's corners too.

  | Define | Value |
  | --- | --- |
  | `LOOK_SAT` | 1.1 |
  | `LOOK_CONTRAST` | 1.04 |
  | `LOOK_GAIN` | `vec3(1.04, 1.0, 0.94)` (warm, sunlit timber) |
  | `LOOK_LIFT` | `vec3(0.03, 0.01, 0.0)` (bark-brown shadows, the UI's ink) |
  | Vignette (`TugMeshes.VIGNETTE`, `VIGNETTE_TINT`) | 0.3, tint `(1.0, 0.9, 0.8)`, in the view grid |

- **Materials.** Wood: procedural planks (gaps, grain from one noise read, nail dots, darker and
  wetter toward the water). Tin (the bot): flat paint with a soft fake highlight band from the
  view (`pow(1 - N·V, 2)`), rivet dots, painted AO in vertex colours. Water: hand-lit, two
  scrolling noise reads, fresnel to the sky gradient, glitter only along the sun's path, foam
  where it meets pilings and banks. Cloth (flag, bunting): unshaded both sides, a vertex-shader
  flutter.
- **Shadows.** Blob shadows under the bot and the crowd (in their MultiMeshes), a darker water
  band under each pier. No shadow maps.

## 5. Shapes and proportions

- **The bot:** a wind-up tin robot 2.75 m tall to its chimney (built at scale 1): a barrel body
  with darker hoops and rivets, a chest gauge, a dome head with a visor slot for the glowing
  eyes, a mouth grille, springy hose arms to mitten hands on the rope, a brass wind-up key on its
  back and a chimney. Ears or horns alternate by rung. Under 3k triangles.
- **The crowd:** toy-like fans, 1.6-1.9 m, a round head with dark hair, a shirt, trousers and arms
  that go up when they cheer: billboard sprites from a two-frame image drawn in code, each with a
  blob shadow.
- **The rider's hands:** chunky work gloves in the UI blue, knuckles readable, cream knit cuffs,
  the rope running through the fists.
- **The flag:** a short white pole and a red swallowtail pennant flying broadside, the pole
  leaned 22° right so it never stands across the bot.
- Proportions: the near pier 5 m wide, the river 8.4 m between pier ends, the far pier 7 m deep.

## 6. Environment

- **Layout:** the near pier (rider), the river across the whole view, the far pier with the bot
  and two torches, crowds either side of both piers, trees, then hills.
- **Banks and piers:** the piers jut out over the water (the banks' top edges at z −1.4 and
  −12.2), so their end pilings stand in it with foam around them.
- **Dressing:** bunting from masts beside the far torches back to masts on the near bank, wide of
  the camera (never across the rope's line); string lights from those masts out over the far
  bank; a mustard-and-cream striped tent and hay bales on the far bank; reeds and rocks along the
  waterline; lily pads drifting downstream. **Open:** a scoreboard post.
- **Depth:** near (deck, hands) warm and detailed, mid (river, far pier, crowd) the story, far
  (trees, hills) hazed toward the sky. Keep the far pier's backdrop simpler than the bot.

## 7. VFX language

| Effect | Look |
| --- | --- |
| Splash | White droplets as short streaks up and out, a ripple ring spreading over a foam disc that fades |
| Torches | An additive flame card per torch, licking and flickering in the shader, with a glow halo; warm pools on the far deck at dusk and night |
| Surge | Steam puffs from the bot's chimney (alpha, never additive): a few on a telegraph, jets in a surge |
| Life | The crowd bobs and cheers, the bunting, reeds and flag flutter, the lily pads drift, the bot's key turns: all in shaders |
| Crowd cheer | Hops scale with `excitement` |

Additive only for flames, eyes and string lights. Water and steam are alpha blended.

## 8. Camera

First person at 1.6 m, pitched -9°, FOV 66. Pulled toward the far pier as the rider loses, with
a dip toward the water at the end, and a tiny shake in a surge or splash. No roll, no bob beyond
the pull rhythm on the fists.

## 9. Tablet budget (Gen 2, PowerVR GX6250, Compatibility; tracker only with Brace lean on)

| Item | Budget | Now (desktop, 2026-10-20) |
| --- | --- | --- |
| fps | 60 with the tracker on (`lean_2d`), at least 55 sustained | 59-62 before the pass (tracker off, 2026-10-03); 48 intro / 35 play after it (tracker on); the performance pass (`GFX_POLISH.md`, Tablet performance) is to be re-measured |
| Render scale | 0.62 (`TugOfWar.RENDER_SCALE`), 0.55 if a round stays under 54 fps (`RenderScaleStep`) | 0.62 |
| Sky per pixel | one cubemap read (the full sky only when the time of day changes) | 1 |
| Per-pixel extras | no vignette, haze or constant light per pixel on the big surfaces | as budgeted |
| Draw calls in play | ≤ 100 with the HUD (world ≤ 70) | 57 with the HUD (99 before); the world 13 (14 with steam), from 55 |
| Visible triangles | ≤ 100k | about 29k |
| Water per pixel | ≤ 3 noise reads | 2 |
| Per-frame GDScript | the rope's 22 segments and the bot's pose only; crowd, torches, flags and bunting move in shaders | as budgeted, plus a few uniforms (eyes, key, steam, the deck's shadow) |
| Particles | the splash (48) only | as is |

The statics are one vertex-coloured mesh (`TugMeshes.scenery`, about 22k triangles); add new
dressing to it, not as new nodes: each draw costs main-thread driver time on the tablet.
