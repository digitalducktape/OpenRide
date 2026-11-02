# Watt Lane: art bible

> **Status**: Approved for the look-and-sound slice (AD-ART-BIBLE: APPROVE, with the notes at
> the end)
> **Owned by**: art-director pass, 2026-11-02
> **Scope**: the 3D world (`WattLaneWorld`, `shaders/`), the HUD widget (`WattLaneStatus`) and
> the hub card. Rules are in `DESIGN.md`.

## 1. Visual identity statement

**"Open road, one light to follow."** A wide, dark highway under a big night sky, and the only
saturated thing on it is the lane: two rails of volt-lime light that bend ahead of you.

- **The lane wins every contrast contest.** When anything competes with the rails (lamps, the
  city glow, the HUD), dim the other thing. Serves the rule "know at a glance if you're in".
- **Open, never enclosed.** When in doubt, remove a wall or ceiling and show more sky. This is
  what separates it from Cadence Karaoke's tunnel.
- **The future is drawn on the road.** Anything the rider must react to (a jump) appears on the
  road ahead first, then in the HUD, then as a sound. Never only in the HUD.

## 2. Mood and atmosphere

| State | Target | Lighting | Descriptors | Energy |
| --- | --- | --- | --- | --- |
| Cruising in the lane | calm focus, "locked in" | cool night, lime rails at full glow, lane floor lit | hushed, wide, humming | medium |
| Off the lane | a gentle nudge, not alarm | rails dim to 60%, the lane floor fades, your beam goes amber at its tip | cooler, emptier | low |
| A jump coming | anticipation | amber chevrons pulse in the lane ahead, rails bend toward the new lane | expectant, clear | rising |
| Caught it | release | rails flash white-lime for 0.4 s, sparks off the rails | crisp, bright | peak |
| Intro card / paused | still postcard | the same scene, held | quiet | low |

## 3. Shape language

- **Long and horizontal.** Rails, road lines, the horizon, the low city: everything is a line
  that runs to the vanishing point or along the horizon. No round hero objects (Cadence has the
  orb).
- **The lane** is two thin bright rails (a white-hot core, lime halo) and a faint fill between
  them. Rails curve smoothly (S-bends for jumps); they never break.
- **Chevrons** (▲-shapes laid flat, pointing toward the new lane) are the only angular shapes,
  and they mean "a change is coming".
- **Your bike** is a slim light nose at the bottom centre and a headlight beam, warm white, so
  "you" is never the same colour as "the lane".
- **Scenery** is silhouettes: flat mesas and a low city skyline on the horizon, slender lamp
  posts along the shoulders. Nothing tall near the road.

## 4. Colour system

| Name | Hex | Meaning |
| --- | --- | --- |
| Volt lime | `#C8FF3E` | the lane (rails, fill, the HUD accent and hero) |
| Rail core | `#F4FFE0` | the rails' white-hot centre, the "caught" flash |
| Signal amber | `#FFB020` | a change is coming: chevrons, the countdown chip, the off-lane beam tip |
| Headlight | `#FFF1D0` | you: the bike's nose and beam |
| Sodium | `#FF8A3C` | street lamps (small, far, dim) |
| Night petrol | `#061418` | ink: the HUD panels, the sky's top |
| Horizon teal | `#145A5C` | the sky's glow at the horizon, the city's haze |
| Asphalt | `#0B1216` | the road |

- Cool world, warm accents: everything big is petrol and teal; lime and amber are the only
  saturated colours, and they never touch (chevrons sit inside the lane's fill, which is faint).
- **Distinct from Cadence Karaoke** (magenta, cyan, violet, a magenta-on-violet ink): no pink,
  no violet, no cyan grid.
- **Colourblind backups:** in/out is never colour alone: the rails' brightness changes, the hum
  changes, and the HUD says IN LANE / PUSH ▲ / EASE ▼. Lime vs amber (hard to tell apart for
  some riders) is backed by shape (chevrons, arrows) and by the chime and countdown.
- The HUD uses the framework's meaning colours (good, warn, bad, target) with lime as the
  game's accent and petrol as its ink (`GameTheme`).

## 5. Character design direction

There are no characters. The rider's bike is the only "actor": a light-cycle nose (a low wedge
with a lit edge) and its beam. The hub card and the intro picture show it from behind, with its
light trail drawn on the road: a warm ribbon from the bike back toward the camera.

## 6. Environment design language

- **A desert highway at night**: six lanes' worth of dark asphalt with faint white dashed lines
  (every 25% of FTP is a painted line, so the road reads as a scale), solid edge lines, and a
  glowing shoulder line. Beyond: flat dark ground with a little noise, mesas, and a city's skyline
  glowing on the horizon straight ahead.
- **Texture philosophy:** none imported. Every surface is unshaded and drawn in its shader (the
  tablet recipe), the grade folded in through `world_look.gdshaderinc` (`wl_look.gdshaderinc`
  sets the game's defines).
- **Props:** lamp posts every 40 m each side (a MultiMesh, scrolled in the shader), reflector
  studs along the edge lines. Density is low on purpose: the lane must dominate.
- **Wet sheen:** the road reflects the rails and lamps as soft vertical streaks (drawn in the
  road shader, no reflection pass).
- **Sky:** a gradient from petrol to teal at the horizon, a scatter of stars, and a thin crescent
  moon high left. No aurora, no sun.

## 7. UI/HUD visual direction

- Screen-space HUD in the top-centre slot (`WattLaneStatus`, at most 850 x 120): the lane's
  bounds are the hero ("150–190", 96 px, lime gradient), "W lane" as its caption, and a second
  row with "In lane 82%", the streak (×2.5) and a direction chip when you're out (PUSH ▲ / EASE ▼).
- The **countdown chip** is amber, with a drawn arrow: "UP to 175–215 W in 4". It pops when it
  appears and on each second.
- Display face: the shared OFL face (`GameTheme`); upright (lean 0.0): a highway sign, not a
  sticker. Minimum 34 px.
- Motion: pop on change, slam on ×3, fade on hide (the framework's tweens). Nothing moves every
  frame.
- Conflict decided: the countdown could be a big centre message (more readable), but the centre
  of the screen is the road where the arrows are drawn; the chip stays in the top slot and the
  road carries the big signal.

## 8. Asset standards

- No imported assets: meshes are built in code (`PlaneMesh`, `ArrayMesh` strips, a MultiMesh
  for posts), all shading in `.gdshader` files under `shaders/` (pre-loaded by
  `Game.keep_shaders`).
- **Tablet budget** (Gen 2, PowerVR GX6250, Compatibility, no camera): 3D view at 0.62 scale in
  a SubViewport, MSAA off; at most 12 draw calls for the world; no engine lights, fog, glow or
  post passes; additive layers kept thin (rails and beam are strips, not full quads); per-frame
  GDScript limited to a handful of uniforms (the lane's 64 offsets, the scroll and states).
- Where art and the budget disagree: the wet-road reflections are fake streaks in the road
  shader rather than a mirrored pass (about a whole extra scene draw).

## 9. Reference direction

- **Night motorway photography with long exposures**: take the light streaks and the empty
  dark around them. Avoid motion-blur trails across the whole frame.
- **1980s retro-futurist album covers (general synthwave styling)**: take the horizon glow and
  the sense of a road to a glowing city. Avoid the cliché pink-and-purple grid sun (that's also
  Cadence's palette).
- **Highway signage**: take the upright, plain numerals and the amber "change ahead" language.
- **Racing-game ghost lines in general**: take "the line to follow is drawn on the road". Avoid
  any specific game's look, colours or UI.

## AD-ART-BIBLE review (art-director gate)

**APPROVE.** The colour system matches the mood targets (one saturated element, cool world),
the shape language follows from "open road, one light to follow", and the asset standards fit
the measured budgets of the existing 3D games (Cadence ~10 world calls). Notes carried into
production: (1) the rails must stay readable when they bend sharply near the camera: keep their
screen width from collapsing (a minimum width in the shader); (2) check the lime against the
amber chevrons on the tablet's panel, which runs warm.
