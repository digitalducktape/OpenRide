# Balloon Pump: art bible

> **Status:** v1, 2026-11-01, the look-and-sound slice (#76). **Owner:** whoever changes the
> look. Change this file in the same commit as any change to the palette, the light, the pump,
> the balloons or the effects. **Sources of truth:** `PumpWorld.gd` (layout, per frame),
> `PumpMeshes.gd` (every mesh), `shaders/*.gdshader` and `shaders/pump_look.gdshaderinc` (the
> grade), `PumpStatus` / `BalloonPump.look` (UI). **AD-ART-BIBLE sign-off:** see §10.

Everything is procedural: primitive shapes merged into vertex-coloured meshes with `KartMeshKit`
(read only; Kart owns it). No textures besides the shared 64×64 noise. No third-party art.

## 1. Visual identity

**The one rule:** *a sunny fairground stall where your legs blow up the balloons: the balloon on
the nozzle is the stage, and the bunch overhead is your score.* When something is ambiguous,
pick what makes the balloon's size and the gauge's needle read faster.

| Pillar | Design test |
| --- | --- |
| **The balloon is the hero** | The nozzle's balloon sits at the screen's centre, glossy and the most saturated thing in view; nothing crosses it. |
| **Brass you can feel** | The pump is chunky polished brass on a red-painted plinth; its plunger rises and falls with every pedal stroke, so the rider sees their cadence. |
| **The bunch is the score** | Every tied balloon floats up and stays, swaying, in its own colour. A big ride ends with a big bunch. |

**Distinct from its neighbours.** Tug of War is a warm, woody riverside fairground at any time
of day, rope orange on bark. Balloon Pump is always **high noon**, pastel and candy-bright:
mint, cream and candy-pink stripes on a lawn, no water, no wood planks, no torches. Keepy Uppy
(#77, built in parallel) keeps a balloon aloft over a fan; Balloon Pump's balloons are tethered
or tied, and its stage is a pump and a stall, never open sky play. Dodge's cool asphalt, Kart's
violet night and Cadence's neon tunnel are all far away.

## 2. Mood by state

| State | Look |
| --- | --- |
| Filling | The plunger pumps with the cadence; the balloon swells smoothly and squeaks; the gauge's needle sits in the green over the push line. |
| Pushing back (near full) | The balloon is big and taut, a bright sheen stretches across it; the needle nears the gold-red push wedge. |
| Leaking | The needle drops under the line; the balloon sags a little and wobbles; a small hiss puff at the nozzle. |
| Tie-off | The balloon pinches, pops off the nozzle with a confetti puff and floats up in an arc into the bunch. |
| Gold balloon | Metallic gold with a moving glint; gold confetti when it ties. |
| Race heat won | Confetti burst over the stall; the bunch bobs. |
| Break between heats | The plunger rests; the stall is calm. |

## 3. Shape language

- **Round and soft.** Balloons are teardrops (a lathe with a knot); the pump is cylinders and
  domes; the stall's awning is scalloped. The only straight lines are the plinth, the counter and
  the posts.
- **Toy scale.** The pump is a little oversized (1.4 m tall with its plunger), a fairground
  attraction, not a tyre pump.
- **Hero vs. support.** Hero: the nozzle's balloon and the gauge. Support: the pump body, the
  rack's next balloon. Background: stall, tents, Ferris wheel silhouette, trees, hills.

## 4. Colour system

| Role | Colour | Rule |
| --- | --- | --- |
| Lawn | `#7CC85A`, darker `#5DA845` | Bright spring grass, with one noise read for grain. |
| Sky | top `#5FB8F0`, horizon `#CDEBFA` | Clear noon; a few soft white clouds. |
| Stall stripes | candy pink `#FF5FA2` / cream `#FFF4DE` / mint `#7FE0C4` | The world's signature; stripes, never solid blocks. |
| Brass | `#E2B04A`, shadow `#8C6420` | The pump, the nozzle, the gauge bezel. Polished, with a painted highlight band. |
| Plinth | fire-engine red `#D83A34` | Under the pump; the only big red, and never a meaning. |
| Balloons | small mint `#3FD0A8`, medium candy `#FF4F96`, large periwinkle `#8A7DFF`, gold `#FFC530` | Each kind its own hue **and** size, so colour is never the only cue. |
| Gauge | cream face `#FFF4DE`, push wedge gold→red, needle ink `#2B0F2A` | The face is the lightest round thing near the bottom of the view. |

- **Grade** (`pump_look.gdshaderinc`): saturation 1.08, contrast 1.02, a pastel lift
  `vec3(0.03, 0.02, 0.04)` and a faintly warm gain `vec3(1.02, 1.0, 0.98)`. The vignette is
  painted into the view grid's vertex colours (0.22, toward a soft plum), Tug's recipe.
- **UI palette.** `GameTheme` candy pink `#FF5FA2` on deep plum `#2B0F2A` (an ink no other game
  uses), badges leaning 0.1. Meaning colours stay the kit's: green "filling", amber "push
  harder", gold the target. The push line is drawn gold, the needle in the ink.
- **Colour-blind backup:** the gauge's state also reads by position (needle left or right of the
  wedge) and words ("PUSH!", "FILLING"), and balloon kinds differ in size.

## 5. Characters

None: the stall is unattended, the crowd is implied by the tents and the wheel. The rider is
present only through the plunger moving with their legs.

## 6. Environment

- **Layout** (metres; the camera at the bike, eye 1.5 m, looking down -z, pitched -3°, fov 60;
  `PumpMeshes` constants): the pump at (-0.95, 0, -2.5) on a round pink-and-cream mat; the nozzle
  stand at (0.35, 0, -3.1), the balloon's knot at 1.05 m; a red hose from the pump's foot to the
  stand; the rack with the next balloon on the counter's right at (1.55, 1.12, -4.75); the stall
  behind (counter at z -5, back wall at -5.8) with its striped, scalloped awning and bulbs; the
  bunch's tether, a brass weight and post, at (0.95, 1.0, -4.45), so a tied balloon rises
  up and right from the nozzle into the bunch over the counter (centres 2.1-2.9 m, under the HUD's
  status widget); tents, a Ferris wheel
  (turning slowly) and lollipop trees beyond, hills at 70-150 m.
- **The sun** sits behind the rider's left shoulder (elevation 58°, azimuth -150°), so the stall,
  the pump's gauge and the balloons face it. (First capture: with the sun behind the stall the
  stripes went maroon and the plinth brown.)
- **No sign with lettering or pictures** on the stall: a first pass had three painted balloons on
  a roof board, which read as part of the bunch.
- **Texture philosophy:** none. Vertex colours carry the stripes and painted AO; one noise read
  breaks up the lawn.
- **Density:** the near field is spare (pump, stand, rack) so the balloon reads; dressing lives
  behind the stall line.

## 7. UI and HUD

- Screen-space HUD on the framework kit. The status widget (`PumpStatus`) is the hero gauge
  repeated as a bar: the needle against the push line, the balloon count and, in Race, "3 / 5"
  and the heat's clock. At most 850 × 120 px, two rows.
- The in-world gauge is diegetic and decorative; the HUD bar is what a glance reads.
- Brief messages (Gold!, Race won!, 10 s left!) in the HUD's centre message, popping in with the
  display face; they sit above the balloon, never on it.

## 8. Asset standards (tablet: PowerVR GX6250, GL Compatibility)

- Every world surface is `unshaded, fog_disabled` and lit by hand (`world_look.gdshaderinc`):
  scenery per vertex, the balloons per pixel (small on screen, and they need the gloss).
- The 3D view renders into a SubViewport at 0.62 of the window, no MSAA, drawn scaled up.
- Static scenery is one baked mesh; the pump one; the bunch one MultiMesh and its strings
  another. Budget: under 20 draw calls for the world, under 120 in play with the HUD.
- Every shader is loaded at prepare (`Game.keep_shaders`) and every effect drawn once behind the
  intro card (`PumpWorld.prewarm`).
- Triangles: whole world under 40k.

## 9. References

- Victorian fairground brass and painted signwriting: take the brass and the stripes; avoid any
  real fair's names or lettering.
- Toy-like stylised 3D (rounded primitives, flat bright colours): take the readability; avoid
  any particular game's characters or UI.
- Real party-balloon pumps: take the plunger and gauge; avoid brand marks.

## 10. AD-ART-BIBLE review (art-director pass, 2026-11-01)

**AD-ART-BIBLE: APPROVE.** The identity statement resolves the main ambiguity (balloon first,
then gauge). The palette is distinct from all five shipped games and Keepy Uppy's stated setting
(a fan, open sky). Shape language follows from the toy-fairground identity. Asset standards keep
to the tablet recipe already proven by Tug and Dodge. Colour is never the only cue (size, words,
position). Watch item: the candy-pink medium balloon matches the UI accent; acceptable because
accents are never meaning colours here, but don't make the push wedge pink.
