# Balloon Pump: art bible

> **Status:** v2, 2026-11-02: the 2D rework (rider: "2D, like Safe Cracker", and parity with the
> wave 1 games). v1 was a 3D daylight stall, replaced. **Owner:** whoever changes the look.
> Change this file in the same commit as any change to the places, the pump, the balloons or the
> effects. **Sources of truth:** `PumpPlaces.gd` (layout, places, palettes, key lights),
> `PumpArt.gd` (the pump, gauge, hose, stand, basket; the plunger's and needle's drawings),
> `PumpStage.gd` (the layers, the bake, the bunch, the motion), `shaders/*.gdshader`,
> `BalloonPump.look` (UI). `GFX_POLISH.md` records the work.

Everything is drawn in code: shapes batched by `SafeMesh` (Safe Cracker's batcher, read only) and
four small canvas shaders. No textures but a soft dot. Places are plain descriptions; nothing
refers to a real fair, circus, pier or maker, and nothing carries lettering.

## 1. Identity

**The one rule:** *a polished brass pump and its balloon in a pool of warm light, at the fair
after dark.* When something is ambiguous, pick what makes the balloon's size and the gauge's
needle read faster.

| Pillar | Design test |
| --- | --- |
| **The balloon is the hero** | The nozzle's balloon is the biggest, most saturated, glossiest shape on screen, right of centre; nothing crosses it. |
| **Brass with weight** | The pump is a riveted brass barrel with hoops, a dome, a big gauge and a T handle on a red-painted plinth; every part has a highlight toward the key light and a shadow away from it. |
| **Night-fair warmth** | One warm key light per place (a lantern or a spotlight), deep blue-violet or velvet-red shadow elsewhere, small twinkling lights for life. Calm, not frantic. |

Flat-vector style with soft gradients and crisp highlights (Safe Cracker's craft), but warmer and
more colourful: candy balloons and bulbs against night, where Safe is brass on soot.

## 2. Mood by state

| State | Look |
| --- | --- |
| Filling | The plunger pumps with the cadence and a puff of vapour rises at the collar each stroke; the balloon swells smoothly, its sheen tightening; the gauge's needle sits past the gold push line, its hub green. |
| Under the line | The needle drops below the line; the balloon wobbles and a hiss of air puffs from its neck. |
| Tie-off | The balloon pops off the nozzle with a confetti burst and floats up in an arc to its place in the bunch. |
| Gold | Metallic gold with a glint sweeping across. |
| Race heat won | Confetti over the bunch; the bunch bounces. |
| New place | After a Race heat (or every 6 balloons in Max) the next place bakes in. |

## 3. Places (`PumpPlaces.PLACES`)

| Place | Palette | Key light | Ambient life |
| --- | --- | --- | --- |
| Fair at dusk | indigo sky to a coral afterglow; dusky field; striped tents with lit doorways | a lantern on a pole between the pump and the balloon, warm | the Ferris wheel turning slowly on the horizon, its lamps and the string lights twinkling |
| Big top, backstage | velvet-red curtains in folds, a gold-fringed valance, sawdust floor, a red-and-cream ring curb | a spotlight from the rigging, its beam drawn | dust motes drifting in the beam, bulbs twinkling |
| Pier at night | navy sky with stars and a moon, a far shore with lit windows, planked deck, railing | a lantern on a post, warm | the sea rolling with the moon's glitter path, the railing's lamps twinkling |

Rules: the key light's pool sits under the hero; the pump's highlight, the balloon's highlight and
the soft shadows agree with it. The vignette (soot plum) pulls the corners in.

## 4. Light, materials and drawing

- **Bake.** The room, the pump, its hose, the stand, the basket, the key light's pools, the soft
  shadows and the vignette are one `SafeMesh` batch per place, rendered once into a SubViewport and
  shown as one sprite (Safe Cracker's tablet recipe). Only what moves is drawn live.
- **Brass:** a vertical cylinder ramp with the hot stripe on the light's side and a faint reflected
  light on the far edge; hoops with a lit lip, a dark seam and rivets spaced as on a cylinder; a
  dome with a hot spot; a blank maker's plate.
- **Rubber (balloons):** per pixel in `pump_balloon.gdshader`: a teardrop SDF with a smooth edge at
  any size, wrapped diffuse, a deeper, more saturated rim, light glowing through on the shadow side,
  a hot highlight that tightens as the balloon fills (`taut`), a darker knot. Gold is a metal ramp
  with a sweeping glint.
- **Gauge:** a cream face with 21 ticks and a lit brass bezel (baked); the push line is a band
  from the line to the end of the scale, gold to red, drawn by `pump_wedge.gdshader` from one
  uniform; the needle a static drawing turned by rotation.
- **Bulbs:** baked wires, live bulbs whose phase rides in UV.x; `pump_twinkle.gdshader` breathes
  them slowly (never faster than twice a second).

## 5. Shapes and proportions (canvas px)

The pump's barrel 170 × 360 at x 715-885, the gauge r 100 at (800, 585), the plinth 260 × 92 on
the floor line (y 880), the handle 268 wide, travelling 52 px between y 262 and 314 (centre). The
nozzle at (1225, 772); balloons 140 / 170 / 200 px half-wide full (small / medium / large), 2.3
half-widths tall. The bunch tethered at (1600, 868), its balloons at 0.42 of their nozzle size.
`pump_layout_test` holds every one of these inside the stage, clear of every HUD panel, at its
extremes, and the Ferris wheel on its horizon.

## 6. Silhouette check (rider rule, 2026-11-02)

Every main shape checked in silhouette at small size (the half-size captures) for unintended
readings: the pump (a cylinder with a T handle and a round gauge), the balloons (a round body
narrowing to a small knot; the moving balloon never trails a string: only the bunch's resting
balloons have strings, straight and converging on the weight), the bunch, the Ferris wheel, the
lantern, the basket. Particles are round dots with no tails (hiss, vapour, dust) and rectangles
(confetti). No moving marker has a round head with a wavy or tapering tail. **Passed.**

## 7. Tablet budget (Gen 2, PowerVR GX6250, Compatibility)

| Item | Budget | Desktop, 2026-11-02 |
| --- | --- | --- |
| Draw calls in play | ≤ 100 with the HUD | 50-56 |
| Full-screen layers | 1 (the baked room); the pier's bake is blended over its sea rect | as is |
| Redraws | the room once per place; the strings when a balloon lands; nothing per frame | as is |
| Particles | ≤ 40 alive | 18 dust (big top), 40 confetti for 1.8 s, 10 hiss, 6 vapour |

## 8. AD-ART-BIBLE review (art-director pass, 2026-11-02)

**AD-ART-BIBLE: APPROVE.** The identity follows Safe Cracker's craft (one illustrated hero in a
lit place, several places, restrained palettes) without copying its look: warm night-fair colour
and a balloon instead of brass on soot and a dial. Distinct from Tug of War (3D daytime riverside)
and Keepy Uppy (a balloon over a fan). The silhouette check passed.
