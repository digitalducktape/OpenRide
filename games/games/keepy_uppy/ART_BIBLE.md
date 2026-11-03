# Keepy Uppy: art bible

> **Status:** v2, 2026-11-02, the 2D rework (rider: "2D, like Safe Cracker"; v1 was a 3D meadow).
> **Owner:** whoever changes the look. Change this file in the same commit as any change to the
> palette, the places, the fan, the balloon or the weather. **Sources of truth:** `KeepyPlaces.gd`
> (layout and the four places), `KeepyBackdrop.gd` (the bake and the ambient life), `KeepyRig.gd`
> (the fan, the pole, the column), `KeepyBalloon.gd` (the balloon, the birds, the pop),
> `KeepyWeather.gd`, `shaders/*.gdshader`, and `KeepyStatus` / `KeepyUppy.look` (UI).
> **AD-ART-BIBLE:** §11. The graphics punch list is `GFX_POLISH.md`.

Everything is drawn in code: shapes batched by Safe Cracker's `SafeMesh` (one draw call a layer,
1.2 px feathered edges, per-vertex gradients), a few small canvas shaders, and three tiny sprites
drawn into images at start (a butterfly, a leaf, a latex shard). No textures from files, no
third-party art.

## 1. Identity

**The one rule:** *a bright balloon riding a column of air you are making, in a lit, lively
outdoor place.* When something is ambiguous, pick what makes the balloon's height and what the
sky is about to do read faster.

| Pillar | Design test |
| --- | --- |
| **The balloon is the hero** | The most saturated thing on screen and always near the centre (it travels between y 340 and 756 on the 1080 canvas, x within ±224 px). Nothing else is coral. |
| **The fan is the built thing** | One illustrated object with real material detail, like Safe Cracker's safe: pine planks with grain and gaps, brass corner brackets with rivets, a brass grille over turning blades, a drive pulley and the belt down to the rider's bike. |
| **The weather shows before it acts** | Each force is visible from its warning: the rain cloud sailing in and its shadow, the bird flapping in, the downdraft's dark curtain sweeping across, the streamers whipping. Text only confirms. |

**Distinct from Balloon Pump (#76):** that's a high-noon fairground stall, pastel mint, cream and
candy pink, a brass pump on a plinth, balloons tied off into a bunch. Keepy Uppy has **no stall,
no stripes, no crowd, no pump**: open-air places at different times of day, one coral balloon in
free flight, and a **sunset coral on deep sky navy** UI. Its mid band is sky blue, not mint.

Distinct from Safe Cracker (2D too): outdoors and airy where Safe is a dark room; the hero is
low centre with the balloon above it, not one object filling the middle.

## 2. Mood by state

| State | Look |
| --- | --- |
| Calm | Clouds drifting, grass and streamers swaying, the column's streaks rising softly over the turning blades. |
| Climbing / high | The column's streaks run faster and brighter; the balloon stretches a little as it climbs and squashes as it sinks. |
| Rain cloud (warning) | A slate cloud sails in from the right and its shadow creeps across the ground. |
| Rain | Rain falls under the cloud; the rain hiss comes in. |
| Bird (warning, landing) | A bird flaps in from the left, low, and lands on the balloon's top; perched birds stay until shaken off. |
| Downdraft (warning) | A curtain of dark slanting streaks sweeps in from the right, over the column by the time it hits; the column's streaks turn downward. |
| Gust (high band) | The streamers whip and pale wind lines sweep past the balloon, which wobbles. |
| Pop | Coral shards and a white ring burst where the balloon was. |
| New balloon | It floats in from the left in an arc and settles into the column. |

## 3. Shape language and the silhouette check

- **Round and soft for nature** (crowns of three circles, cumulus of five, round bushes), **square
  and built for the fan** (planks, brackets, the crate). The balloon is an egg, a little fuller
  at the top, with a pinched knot.
- **The balloon has no string.** A balloon held up by air needs none, and the rider's rule
  (2026-11-02) forbids any moving marker with a round head and a wavy or tapering tail.

**Silhouette check** (every main shape at thumbnail size, against unintended readings):

| Shape | At small size it reads as | Verdict |
| --- | --- | --- |
| Balloon | a round egg with a tiny knot, no tail | Safe. The v1 curly string (round head plus wavy tail) is gone. |
| Perched bird | a round body, a round head, a beak, a short wedge tail wider than long | Safe: no tapering tail. |
| Flying bird | two raised triangle wings over a round body | Safe. |
| Gull (seaside) | a shallow "m" of two arcs | Safe: no body, no tail. |
| Butterfly | four round wings and a short bar | Safe. |
| Falling leaf | a pointed oval | Safe. |
| Pop shard | a small irregular triangle | Safe. |
| Wind lines | three short pale arcs, no heads | Safe. |
| Rain and downdraft streaks | straight short dashes | Safe. |
| Column streaks | soft vertical dashes | Safe. |
| Fan, pole, streamers | built shapes; streamers are flat ribbons attached to a pole | Safe. |

## 4. Colour system

| Role | Colour | Rule |
| --- | --- | --- |
| Balloon | coral `#FF5E5B`, sheen `#FFD6C9` | The only coral; lit from the place's sun, a sky-coloured rim on its far side |
| Fan crate | pine `#C9A577`, dark `#8A6A44` | The built thing; shaded toward the sun |
| Brass | `#D9A441` | Brackets, rivets, the grille, the pulley's hub, the pole's cap |
| Height bands (pole, HUD) | low cream `#F2EFE6`, mid sky `#8FD0F0`, high sun `#F5C04A` | The same three colours on the pole and the HUD's chips |
| Air column | white, additive | Faint (under about 0.25) so the balloon reads through it |
| Bird | slate `#465466`, cream belly `#EDE6D6`, beak `#F5A623` | Small and dark against the coral |
| Rain cloud | slate `#8592A4` over `#56606F` | The only grey mass on screen |

**The places** (`KeepyPlaces.PLACES`), each with its own sky, sun and land:

| Place | Light | Signature |
| --- | --- | --- |
| Summer meadow | high afternoon sun, upper left | rolling hills, hedgerows, round trees, a mown path, wildflowers; butterflies |
| Seaside cliffs | golden late afternoon, low right | the sea with the sun's glitter, a lighthouse on the cliff, a fenced headland; gulls |
| City rooftop at dusk | low orange sun behind the towers | two rows of towers with lit windows, water tanks, a parapet, a deck, pots, a string of warm bulbs; windows lighting up |
| Autumn park | warm afternoon, upper right | orange and red trees in two rows, a gravel path, a lamp post, a bench, fallen leaves; leaves falling |

**UI palette:** sunset coral `#FF7A59` on deep sky navy `#12233A` (`KeepyUppy.look`), badges
leaning 0.08. Meaning colours are the kit's. Bands are told by position (left low, right high) and
the multiplier, never colour alone.

## 5. Characters

No people. The balloon is the rider's avatar: it bobs, squashes when it sinks fast, stretches as
it climbs, tilts when the wind pushes it off the fan. The birds are generic round birds, nobody's
character, facing the camera's side.

## 6. Environment and layout (1920 x 1080 stage, painted 160 px past each side)

- **Horizon** at y 640; the land under it everywhere, ridges and props over it.
- **The fan** stands at x 960 (± 224 px on its rails with Steer), its grille's centre at y 858,
  the crate's front 340 x 150 below it, its feet on two steel rails at y about 1054; the belt
  runs down off the bottom edge to the bike.
- **The balloon** rests on the grille at y 756 (h = 0) and rises to y 340 (h = 1).
- **The pole** stands at x 1300 from the ground to y 236, painted cream to the mid line, sky blue
  to the high line, sun above; a streamer at each band line and an orange pennant at the top.
- **Props stay wide of the column** (x 660-1260 above the horizon is kept for the balloon).

## 7. VFX language

| Effect | How |
| --- | --- |
| Air column | `keepy_column.gdshader` on one rect: streaks rising, faster with lift, falling in a downdraft |
| Rain, downdraft | `keepy_streaks.gdshader` on one rect each: falling dashes; the curtain's leading edge is a uniform |
| Sea glitter, windows | `keepy_sea.gdshader`, `keepy_windows.gdshader`, additive, on one rect each |
| Grass, streamers | `keepy_sway.gdshader`: vertex sway weighted by each vertex's UV.x |
| Pop | `CPUParticles2D` (26 shards) and a ring scaled and faded by a tween |
| Butterflies, leaves | `CPUParticles2D`, 10 and 22 |
| Clouds, gulls | layers drawn once and moved |

## 8. The frame check (rider, 2026-11-02)

Nothing may be clipped by the frame, the ground line or a HUD panel. `keepy_scene_test` checks
the balloon (with three birds, squashed and stretched) at every band and the rail's extremes
against the stage, the grille and the HUD's ride panel, clock panel, Pause, End and the status
widget laid out at their tallest; and the fan and the pole the same way. The rain cloud and the
ambient clouds may pass behind the HUD's panels on their way in and out; they are scenery.

## 9. Tablet budget (Gen 2, PowerVR GX6250, Compatibility)

| Item | Budget |
| --- | --- |
| fps | 60, at least 55 sustained, with Steer's tracker on |
| The place | one opaque sprite of the bake (two only during a 1.6 s cross-fade) |
| Draw calls in play | ≤ 80 with the HUD |
| Full-screen blended layers | none outside a cross-fade and the downdraft's curtain (a few seconds) |
| Per frame | positions, rotations and about ten uniforms; no `_draw` redraws |

## 10. Reference direction

- **Safe Cracker (this repo):** the craft bar: one illustrated hero with material detail, a lit
  place, ambient life that never redraws, a restrained palette.
- **Picture-book landscapes:** layered flat ridges with soft haze, round trees. Take the layering;
  avoid any one illustrator's recognisable style.
- **Travel posters:** strong sky gradients and a single warm light. Take the light; no type, no
  logos.

## 11. Art-director review (AD-ART-BIBLE)

**AD-ART-BIBLE: APPROVE.** The colour system serves the mood (one coral hero, a warm or cool place
around it, slate weather); the shape language follows from the identity (soft nature, a built
fan); the budget fits the 2D recipe Safe Cracker proved on the tablet. Notes carried into the
build: keep the column faint; keep props wide of the balloon's lane; run the silhouette check
again for any new moving shape.
