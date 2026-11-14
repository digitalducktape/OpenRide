# Kart Race: art bible

> **Status:** v1, 2026-10-15. Written by the art-direction review of the `kart-race` branch at
> f69f039, from the code and the capture set. **Owner:** whoever changes the look. Change this
> file in the same commit as any change to the palette, the shaders' light model, the racers'
> proportions or the HUD's look.
>
> **Sources of truth.** The numbers come from `world/KartLook.gd` (themes and light),
> `world/shaders/light.gdshaderinc` (light and grade), `world/shaders/kart.gdshader` and
> `outline.gdshader` (karts), `racers/KartRoster.gd` (the cast) and `ui/KartTheme.gd` (the UI).
> If the code and this file disagree, the code describes what ships. Fix whichever one is wrong.
> Lines marked **Correction** describe the target, not what the code does today. The polish punch
> list tracks the work.

Everything is original: no franchise's names, characters, track layouts, UI look, music or
sounds. Mechanics can be inspired by the genre. Names, art and audio cannot.

---

## 1. Visual identity

**The one rule:** *a toy race on a sunny afternoon, readable at a glance from a moving bike.*
When something is ambiguous, pick the option that reads faster at 1 m and half-attention.

| Pillar | Design test |
| --- | --- |
| **Readable first** | If a detail doesn't survive the tablet's 0.66 render scale at 1 m, cut it or make it bigger. Silhouettes, colour blocks and value contrast come before texture. |
| **Toy-like and warm** | Rounded, chunky, slightly oversized forms with fat tyres. A warm, low sun. Nothing gritty, metallic or realistic. When in doubt, make it rounder and more saturated. |
| **Speed you can feel** | Movement cues (kerbs, road dashes, streaks, FOV, sparks) beat static detail. Detail that only reads when standing still is low priority. |
| **One hand-made light** | Every surface is lit by the same hand-written sun, hemisphere and haze (`light.gdshaderinc`). No engine lights. No asset may bring its own lighting model. |

The genre references are console party racers in general. Take the clarity, the chunky
proportions and the saturated toon light from them. Never take a character, a kart shape, an
item, a track layout, a HUD layout or a logo.

## 2. Mood by game state

| State | Target | Light and colour |
| --- | --- | --- |
| Fly-over and grid | Anticipation and showcase | Each track's landmark in frame. Warm sun. The title band low left. |
| Racing | Flow and speed | Full-saturation world. The HUD sits at the edges. The centre third (the kart and the road ahead) stays clear. |
| Final lap | Urgency | A red ribbon banner, a music variation and the same world. Don't recolour the world. |
| Results and podium | Reward | A violet "night" overlay with a sunburst (`ui/shaders/sunburst.gdshader`), gold for the rider and confetti. The world stays visible, dimmed, behind; on the podium it clears over the 3D stage. |

## 3. Palette

### 3.1 Light per theme (`KartLook.THEMES[*].light` and `.sky`)

The sun keeps one bearing (`SUN_DIR`, west-south-west) in every theme. Only its height and
colour change, so blob shadows stay right.

| | Meadow (hero) | Canyon | Harbor (sunset) | Frost |
| --- | --- | --- | --- | --- |
| sun height | 0.438 | 0.62 | 0.16 | 0.34 |
| sun colour | `#FFD9A3` | `#FFE0B2` | `#FFA86B` | `#FFEDD6` |
| sky ambient | `#859ED6` | `#8CA8DB` | `#8075C2` | `#99B8EB` |
| ground ambient | `#706647` | `#9E613D` | `#664C57` | `#9EA8BD` |
| haze | `#EDD6BD` | `#F5CC9E` | `#FAB294` | `#D6E6FA` |
| haze density | 0.0024 | 0.0021 | 0.0026 | 0.0030 |
| sky top / mid / horizon | `#3D73D9` `#8CB8F2` `#FFD6A8` | `#336BD1` `#85B2ED` `#FFD19E` | `#383385` `#B275A8` `#FF9E5C` | `#427ADB` `#9EC7F5` `#F0F0FA` |

### 3.2 Surfaces per theme (`road`, `ground` and the builders' colours)

| | Meadow | Canyon | Harbor | Frost |
| --- | --- | --- | --- | --- |
| asphalt / dark | `#4C4F59` `#33363D` | `#544C4F` `#3D3638` | `#4C4A57` `#363340` | `#4F5461` `#383D4A` |
| kerb a / b | `#DB211F` `#F7F7F2` | `#E0291F` `#FAF5EB` | `#296BD9` `#F7F5F2` | `#D9242E` `#FAFAFF` |
| verge or ground a / b | `#549430` `#80B540` | `#E09457` `#F2B270` | `#668F42` `#85A34C` (cobbled quay verge) | `#E6EDFC` `#FAFCFF` |
| rock | `#8C8575` | `#C75C33` (strata 1.6 m) | `#8F8585` | `#6B7085` |
| wall a / b / rail | `#F5F5F7` `#2985DB` `#E63329` | `#BD8552` (timber) `#F2731F` `#2E2E38` | `#F5F2F0` `#296BD9` `#FAC733` | `#F7F7FC` `#D9242E` `#D9242E` |
| wall cap / foot | `#E6E8ED` / tyres `#212126` | `#DBAD75` / `#6B3D29` | `#DBD6D1` / stone `#5C5761` | snow `#FAFCFF` / blue shade `#8099CC` |

**Theme colour rules**

- Each theme has **one signature accent**, and the walls, stands and gate carry it. Meadow is
  blue and red, Canyon orange and teal, Harbor blue and gold, Frost red.
- **The road is always the darkest large value on screen.** The karts must pop against it.
  Asphalt luminance stays between 0.28 and 0.36 (Harbor's purple dusk may go darker).
- **Frost snow** is lit by its own rule (`ground.gdshader` `snow` = 1): bright white `#FFFDF7`
  in the sun, **blue** `#A9C4EE` in the shade (sky ambient), never grey. Drift noise is 5% and
  the grain 3%; texture comes from sparkle that twinkles as the view moves (one noise read,
  offset by the view). The road's verges use `verge_grain` 0.06 and `verge_gain` 1.2. The Frost
  wall is white and red under a red rail and a fat snow cap.
- **Walls** take the sun like scenery: a self-glow of only 0.08, a darker foot and a chamfered,
  lighter cap (see 6, Barriers).

### 3.3 The cast (`KartRoster.RACERS`): kart colour and accent

| Racer | Species | Kart | Accent | Class |
| --- | --- | --- | --- | --- |
| Juniper | fox | `#FF7A1A` | `#FFEDC7` | medium #7 |
| Tofu | panda | `#33C7B2` | `#F7F7F2` | heavy #22 |
| Pip | frog | `#8CDB2E` | `#FFDB40` | light #5 |
| Clover | rabbit | `#FF73AD` | `#FFFFFF` | light #12 |
| Bramble | bear | `#EB3333` | `#FFD14C` | heavy #33 |
| Ripple | otter | `#2980FF` | `#D9F5FF` | medium #9 |
| Pebble | penguin | `#FFCC1F` | `#334C99` | light #44 |
| Scout | raccoon | `#994CF2` | `#66F2D9` | medium #18 |

These eight hues must stay well spaced. The racer list, the minimap dots and the kart in the
world must all say the same colour. A new racer needs a hue at least 30° from every other one.

### 3.4 Semantic colours (shared by world FX and UI)

| Meaning | Colour | Backup cue (colour-blind safety) |
| --- | --- | --- |
| Drift tier 1 / 2 / 3 | `#4CBFFF` / `#FF8C26` / `#D973FF` | Spark size and count grow by tier, the meter has 3 segments, and a ping rises in pitch |
| The rider (you) | gold chip `#FFCC29`, gradient `#FFF799`→`#FF8C1A` | The name label is shown only for the rider: their profile name (`KartRoster.rider_label`, "You" without one), and their board rows are gold. |
| A gain (points, place up) | green `#D9FF80`→`#33CC59` | A "+" sign, and a scale-up pop |
| A warning or the final lap | red ribbon `#D92640` (90% alpha), gold edge `#FFD94C`, orange gradient text; normal lap ribbons are violet `#4C2ECC` | The words "FINAL LAP!" and the fanfare |
| Boost | flame orange → white core | A FOV kick, a whoosh |

## 4. Lighting, materials and shading

Everything in the world is `unshaded` + `fog_disabled` and calls `grade(haze(col, dist), SCREEN_UV)`.
There are **no engine lights, shadows, fog, glow or post passes.** A full-screen pass cost about
5 fps at the tablet's 1080p.

**The shared light** (`light.gdshaderinc`):

- `hemi(n)` mixes ground → sky ambient by `n.y`.
- `haze()` uses exponential fog towards the theme's haze colour, capped at 0.85.
- `grade()` is the same in every material:

  | Parameter | Value |
  | --- | --- |
  | saturation | ×1.12 |
  | contrast | ×1.06 |
  | gain | (1.04, 1.0, 0.95) |
  | violet lift | (0.02, 0, 0.05) |
  | vignette | 0.38, from `smoothstep(0.7, 1.75)`, with a violet edge tint |

  The sky repeats the grade without the vignette. **Don't fork these constants per material.**
- Noise comes only from the shared 64×64 `noise_tex` (`vnoise`). There is no `sin()` hashing.
  Use at most three noise reads per pixel on large surfaces.

**Per surface class**

| Class | Shader | Light | Rules |
| --- | --- | --- | --- |
| Karts and drivers | `kart.gdshader` + `outline.gdshader` (next pass) | Per pixel: a toon ramp `smoothstep(-0.06-wrap, 0.14-wrap/2, N·L)`. Fur gets wrap 0.3 × (1 − gloss). The shade is sky-tinted (×0.78, a violet core). Paint (`COLOR.a` = gloss) gets a crisp toon highlight (pow 32, stepped 0.3-0.6), a broad sheen and a sky clear-coat. A **rim** (fresnel 0.55-0.95, strength 0.5): warm `#FFE6B8` in the sun, cool `#9EBDFF` in the shade. | Vertex colours carry the paint and the **painted AO**. `UV.y` = self-lit (eyes, lamps). `UV.x` = outline width (0 on eye glints and blush). `flash` is for hits and boosts. |
| Outline | inverted hull, `cull_front` | none | Width 0.02 × `UV.x` × `clamp(dist·0.08, 0.7, 2.5)`. Colour `mix(#1F122A, surface×0.3, 0.35)`: a deep shade of the surface, **never pure black**. Karts and drivers only. Scenery has no outlines. |
| Road | `road.gdshader` | Flat-normal: hemi × 0.55 + sun × `sun.y` × 1.25, plus a warm glare (`sheen` 0.22, pow 8 of the sun's mirror direction, broken by the grain) | Everything is procedural in track space (UV = d, s): grain, repairs, the rubbered line (−20%), tyre marks weighted by corner, a darker grime band 0.6 m inside each edge, edge lines, dashed lane lines, the chequered line, grid boxes, kerbs (1 m blocks) and verges. No extra texture reads. |
| Terrain | `ground.gdshader` | Per pixel, the same light; snow (`snow` = 1) has its own: white in the sun, sky-blue in the shade | World-space textured. Slopes below `rock_slope` turn to strata. Specks are flowers; on snow, view-dependent sparkle. `grain` sets the fine noise's contrast. |
| Scenery | `scenery.gdshader` | **Per vertex**: hemi + sun·N·L. Hazed and graded per pixel. | Painted AO in the vertex colours. `COLOR.a` = sway (foliage, flags) or glow (`alpha_glow`). MultiMesh for repeats (`INSTANCE_CUSTOM` tint). Matte only: no specular on scenery. |
| Sky | `sky.gdshader` | n/a | Texture-free gradient, a sun halo, the grade. The clouds are cards (`_build_clouds`). |
| Water, items | `water`, `item_*` | Same light | Items may be emissive and additive. They must read against both the road and the sky. |

**Shadows.** Karts get blob shadows only, cast along `sun_dir()`, with a tight, darker contact
core (0.8 alpha) under the chassis inside the soft falloff, so karts sit on the road.

**Anti-aliasing.** The 3D view renders at 0.66 of 1080p (0.58 at governor tier 4) and is
scaled up linearly. Measured on the tablet (Meadow, 60 s of racing, tier 1 fixed, 2026-10-15/16):
render scale 0.72 costs about 4 fps with the tracker on or off; 0.66 costs under 2 (−0.6 on,
−1.3 off); MSAA 2× on the SubViewport renders the 3D view black on the PowerVR driver; FXAA
isn't available in Compatibility. Silhouettes carry the rest: chamfered wall caps, outlines and
no thin high-contrast slivers.

## 5. Shapes and proportions

**Shape language.** The world uses big rounded masses (hills, puffball trees, mesas with soft
strata). Hazards and signage use angles: chevrons, kerbs, ramps. Items use spheres and capsules
with glowing rings. The UI uses slanted rounded badges.

**Karts** (`racers/KartModels.gd`, three classes):

- Chunky and toy-like, about 1.9 m long. The wheels are fat (front radius 0.27-0.31,
  rear 0.30-0.38) and oversized against the body.
- **Each kart is one mesh**, rigged in the vertex shader, with at most 3k triangles, kart and
  driver together, and two materials (paint and outline). Each kart also has a number plate, a
  spoiler and one paint colour, with its accent as stripes and trim.
- Light, medium and heavy must differ in silhouette from behind: the width, the wing, the
  sidepods and the rear tyre width.

**Drivers:**

- Proportions are about 2.5 heads tall (head : body ≈ 1 : 1.5), with big eyes, blush and a
  helmet with a visor or goggles.
- Ears go through or over the helmet: they are the species' silhouette.
- They lean into turns, squash on landing and cheer at the finish.

**The view from behind.** The chase camera sees the back of the kart for 95% of a ride:

- The **helmet is in the racer's kart colour** with an accent stripe, the number above a wide
  dark goggle strap that wraps the back as a visor band, and a darker rim. Only Pip (a green
  frog in a green kart) keeps a contrasting yellow override.
- On the kart the head is built at portrait size and scaled by `HEAD_SCALE` 0.88, and the
  helmet sits snug (`HELMET` 1.05 / 1.1 / 1.07 of the head). Its width stays within the rear
  axle's track × 0.45 (Juniper: 0.63 m against 0.67). The ears stay full size.
- The rear of every kart has a body-colour wing with an accent trailing edge, two self-lit
  taillight bars (`UV.y`), glowing exhaust tips and a dark diffuser with fins. The classes
  differ: the medium kart has a full-width wing on tall endplates, the light kart a narrow high
  wing on its shark fin, and the heavy kart a low, wide ducktail across its fenders under twin
  stacks. All stay under 3k triangles (2.5-2.9k).

## 6. Environments

- **Construction.** Track-space meshes (the road, kerbs, verges and walls along `s`), terrain
  sectors and MultiMesh scenery. Dressing sits in cells (visibility 230 m, 150 m at tier ≥ 2).
- **Density.** The trackside 0-15 m band is dense (barriers, tyre stacks, flags, signs,
  props). The mid-ground 15-80 m has clumps of the theme's foliage. The background is the
  terrain and a landmark silhouette. Every corner gets a readable object on its outside:
  chevrons, a tyre wall or a sign.
- **Landmarks.** Each track gets one hero landmark, visible from the grid and mid-lap:
  - Meadow: the windmill and the red barn;
  - Canyon: the rock arch and the mesas;
  - Harbor: the lighthouse and the string lights;
  - Frost: the ice lake and the peaks.

  **Correction:** the grid shot is the same composition on all four tracks (the same
  grandstand and camera, in `*_fwd_grid.png`). Frame each grid on its landmark, and dress the
  grandstand per theme: snow on the roof for Frost, an awning and lamps for Harbor.
- **Barriers** (`KartRoadMeshes.walls`, one mesh and one material per track). The profile from
  the road: a dark foot (0.2 m), panels alternating in the two wall colours with a dark seam at
  every 2 m row, the rail as a stripe under the cap, a chamfered lighter cap and a shaded back.
  Per theme (`wall_style`): Meadow's foot is a tyre row with a tread line, Canyon's panels are
  timber planks with joints, Harbor's quay wall has a stone foot (the bollards are in its
  dress), and Frost's cap is a fat lip of snow over a blue-shaded foot. About twice the old
  wall's triangles, still one draw.
- **Road.** The road is the largest area on screen. It carries dashed lane lines (3 m dash, 6 m
  gap, at d = ±hw/3, none on the grid), a darker 0.6 m band just inside each edge line, a
  stronger rubbered line, and a warm sun glare towards `sun_dir`. All of it is procedural.
- **Sky.** Clouds are cumulus cards: puffs piled in a dome over a flat, cooler base, lit on top.
  There are 40% fewer banks than before, each about twice the size, with one or two smaller
  cards overlapping it (one MultiMesh).

## 7. UI and HUD

**Typography.** **Lilita One** (SIL OFL, `ui/fonts/`) is the only display face, slanted −0.16
for badges (`KartTheme.display()`), with `spacing_glyph` 1.

- Outline `#210F3D`, size `max(6, size/6)`.
- A drop shadow only at 70 px and up (each shadow is another text pass).
- The framework's chrome (the clock, Pause, End, Recalibrate) takes the Kart skin.

| Use | Size (1080p canvas) |
| --- | --- |
| Place number / suffix | 250 / 96 |
| Countdown | 280 |
| Banner (LAP 2/3, FINAL LAP!) | 124, subline 38 |
| Track title / chip | 150 / 38 |
| Lap badge digit | ~110, clock 46 |
| Racer list numbers, rider name | ≥ 40 |
| Board rows | ≥ 44 |
| **Minimum anywhere** | **34** (framework rule). The drift meter has no label (the arc explains itself). |

**Colours** (`KartTheme`): the panel night `#291A57` at 86% alpha with an edge `#8C6BFF` and a
6 px bottom border; the tile fill `#1A0F3D`; the chip gold `#FFCC29`. Gradients run top → bottom:

| Gradient | Top → bottom |
| --- | --- |
| gold | `#FFF799` → `#FF8C1A` |
| violet | `#DBCCFF` → `#8052FF` |
| green | `#D9FF80` → `#33CC59` |
| orange | `#FFDB73` → `#FF6B1F` |

The place badge is gold for 1st-3rd and violet otherwise.

**Shapes.**

- Slanted rounded badges (`StyleBoxFlat` skew 0.18-0.3, radius 14) with a soft violet shadow
  (4, 6).
- Circles for the item button and portraits.
- Pills for buttons and chips.
- No square-cornered panels and no thin 1 px lines.

**Layout (racing).**

| Zone | Contents |
| --- | --- |
| Top left | lap badge, clock, racer list |
| Bottom left | minimap |
| Bottom centre | ride strip (rpm, W, %, effort) |
| Right (y 336-596) | place |
| Bottom right | item button with the drift arc |
| Top right | clock / score, Recalibrate \| Pause \| End |

The kart and the road ahead (the centre third, y 380-880) stay clear.

**The item button** sits **bottom right** (a 260 px disc whose edge touches the margins), at the
far end of the screen from End, with a hit circle 1.25× the drawn radius. Recalibrate moved up
beside Pause | End as a dark outline pill, so End never sits beside a twin.
`kart_presentation_test` keeps the item's hit circle at least 120 px from End and fires real
touches over the whole circle. An item held unused for 2 s pulses: the face breathes 1.0 → 1.06
and a gold rim glow fades in (tweens on a transform and a modulate, never a redraw).

**The drift meter** is a three-segment arc round the item button's upper-left edge in the tier
colours, on a dark `OUTLINE` band (88%) with round ends, so it reads over sky, grass or
barriers. The unfilled segments show their colour at 30%; the knob glyph sits just past the
arc's end. No text. It redraws only on 24 charge steps, a tier, the knob or the fade.

**The camera strip** ("Camera steering is off") sits between the minimap and the item button,
above the ride strip (it wraps to two lines). On a board it takes the bottom band, under the
rows and the pill.

**Motion.**

- Pops use elastic or back easing, 0.25-0.5 s: a place change scales 1.35 (gain) or 0.8
  (loss), then settles.
- Banners slide in from the side and leave within 1.5 s.
- The countdown digits scale 2.0 → 1.0 with a ring burst.
- Bakes (`KartBaked`) re-render only on a change. **Animate the baked widget's transform,
  never its contents.**

**Boards.** A violet overlay, a sunburst, a gradient title over its subtitle, rows as slanted
tiles, the rider's row gold, and an auto-advance pill with a countdown. Confetti falls
**behind** the titles and the rows. A bot still racing when the rider finished shows its
projected gap (timed at its race pace, spread by believable gaps) in a muted lavender.

**The podium** is staged in 3D on the start straight, the gate and the grandstand behind: a
violet plinth and three vertex-coloured blocks (gold, silver, bronze; painted AO, a lighter
bevelled cap, a pale stripe, a dark foot) under the world's one light. They rise third, second,
then the champion, and each racer's own kart drops onto its block and cheers (`KartView`, both
arms up), facing a held camera that frames the stage in the left two thirds. The sunburst
clears to a soft window over the stage. Each place's number sits on its block's face and its
name and points tag over its kart, popping in as the kart lands. The standings stay on the right.

## 8. VFX language

All effects live in three pooled MultiMeshes in `KartFx`: alpha puffs, additive sparks and
stars. Every effect fits that grammar, so no new pools or nodes are needed.

| Effect | Look |
| --- | --- |
| Drift sparks | **Streaks, not discs** (`spark.gdshader`): stretched along their velocity (0.06 s of travel, so 3-5:1), a white-hot core blending to the tier colour. The still wheel glow is a hard-edged four-point flare. A tier reached bursts a flat ring of 12-22 streaks round the tail. KartFx writes each spark's velocity into its transform's free basis slots: the same buffer writes, no texture. |
| Boost | Two flame cones from the exhausts, the tier colour → `FLAME_CORE` white, plus FOV +14° and the boost rumble |
| Dust | Theme-tinted puffs: verge dust, sand, snow powder. Alpha ≤ 0.5. Short lived. |
| Hit | Yellow stars orbiting the driver and a white `flash` on the kart |
| Shield | A cyan bubble (`item_shield`) and a burst ring when it blocks |
| Speed lines | Thin screen-space streaks from the draft point, **only at a real sprint or on a boost**: from 1.15× the rider's steady 0.6-FTP speed, full at 1.27× (`KartRace.SPEED_LINES_*`). The draft streaks show while drafting. Never at cruise. |

Additive effects must stay in the tier, flame and shield colours. Smoke and dust are never
additive.

## 9. Camera

- The chase camera: 5.6 m back and 2.6 m up, looking 10 m ahead at 0.9 m, FOV 64→80 by speed.
  That shows the kart's top and more road over the helmet: the elevated three-quarter read
  that makes karts look like toys. "Close" is the same angle nearer: 4.0 m back, 1.95 m up.
- Keep "close" for riders who want it.

## 10. Tablet budget: hard constraints

Target: Peloton Gen 2, PowerVR GX6250, GL Compatibility, 1920×1080 at about 1 m. **It is
CPU-bound on the main thread**, and the GL driver takes about 17% of it.

1. **Don't add per-frame GDScript for looks.** Put motion in shaders (`TIME`, the vertex rig),
   tweens or baked meshes. Physics, the bots, the views and the FX already take about 6 ms a
   tick on the tablet.
2. **Draw calls: at most 120 a frame** (the race averages about 72-92 and peaks at about 130).
   Each new material or mesh instance costs CPU in the driver. Merge into existing meshes and
   MultiMeshes. Prefer shader detail over geometry instances.
3. About 250k visible triangles. A kart plus its driver is at most 3k triangles with at most
   2 materials (paint and outline).
4. Everything is unshaded with the shared hand light. No engine lights, shadow maps, fog,
   glow, SSAO or full-screen passes. Shadows are blob shadows.
5. Noise comes only from `noise_tex`, with at most 3 reads per pixel on large surfaces.
6. Particles use the three pooled MultiMeshes and their caps. The governor halves the caps at
   tier 1.
7. The 3D view renders in a SubViewport at 0.66. Never set `scaling_3d_scale` below 1. AA and
   scale changes need a tablet measurement (±3 fps is noise).
8. HUD widgets are baked, and labels change only when their values change. A new HUD element
   joins a `KartBaked` bake or the shared draw.
9. Assets are original, procedural, CC0 or OFL, each in `games/assets/SOURCES.md`.

## 11. Do and don't

**Do**

- Read every change at the tablet's scale. Capture with `capture_world.gd` and
  `capture_kart_hud.gd`, and look at the result at 50%.
- Keep the karts the most saturated, highest-contrast objects. The world is a stage.
- Put each theme's accent on its walls, stands and gate, and its landmark in the grid shot.
- Use the racer's colour everywhere it appears: the kart, the helmet, the list ring and the
  minimap dot.
- Put detail into vertex colours (painted AO, stripes) and procedural shader bands.

**Don't**

- Use pure black (outlines are tinted), pure grey snow, or flat unlit slabs.
- Place a touch target next to End, or HUD over the centre third during racing.
- Draw text under 34 px, or text without the dark outline over the 3D view.
- Fork the grade or the light per asset, or import a PBR or metallic asset.
- Use any franchise's names, item shapes, kart silhouettes, HUD layouts or sounds.
