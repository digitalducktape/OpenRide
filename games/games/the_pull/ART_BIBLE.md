# The Pull: art bible

> **Status:** v1, 2026-11-02: the look-and-sound slice (#79). **Owner:** whoever changes the
> look. Change this file in the same commit as any change to the palette, the light, the sled or
> the effects. **Sources of truth:** `PullWorld.gd` (layout, per frame), `PullMeshes.gd` (every
> mesh), `shaders/*.gdshader` and `shaders/pull_look.gdshaderinc` (the grade), `ThePull.look`
> and `PullStatus` (UI). **Open** marks what the code doesn't do yet.

Everything is procedural: shapes built in code, lit by hand in shaders. There are no textures
beyond the shared 64×64 noise, no imported models and no fonts but the kit's OFL display face.
Nothing is any real pulling league's name, logo or livery. The words on the track are generic:
"FULL PULL", distance numbers, "THE PULL".

## 1. Identity

**The one rule:** *a county-fair pull track at dusk under floodlights: your bike, a chain, and a
steel sled that gets heavier with every metre.* When something is ambiguous, pick what makes the
distance and the load read faster.

| Pillar | Design test |
| --- | --- |
| **Distance is the story** | The boards, the best flag and the Full Pull line are the brightest, cleanest shapes on the track. From 1 m away the rider can tell how far they are and how far the flag is. |
| **The load is felt** | The chain sags and snaps taut, the weight box creeps forward on the sled (in the mirror and the look-back), the view strains and shakes as the sled bogs down. |
| **Floodlit dirt at dusk** | Warm sodium pools on red-brown clay under a deep blue sky with a last orange band. Fair lights twinkle beyond the stands. |

It is distinct from its neighbours. Kart is a violet night with no dirt. Dodge is cool asphalt
in daylight. Tug is a sunny timber pier on water. Cadence is a neon tunnel. The Pull is the only
warm-on-cool dusk with floodlight pools.

## 2. Mood by state

| State | Look |
| --- | --- |
| Set | The view turns back over the right shoulder: the sled, its yellow frame, the box at the rear, the chain slack on the dirt. The crowd hums. |
| Rolling | The view faces down the track. Boards slide by, the floodlight pools pass overhead and the camera bobs with the pedal stroke. The chain is taut. |
| Bogging down | Speed drops, the bob slows and a strain shake rises. The mirror shows the box near the front. |
| Dig in! | The view's edges flush red-amber with the warning, pulsing. |
| Stall | The shake stops dead, the view dips 2°, and the chain goes slack in the mirror. |
| Near best | The crowd jumps (`excitement`), and the best flag's gold brightens. |
| Full Pull | A gold confetti burst over the line, every floodlight flares, the crowd jumps. |
| Rest | The view drifts back to the start. The sled is dragged back to the line off screen. |

## 3. Palette

| Role | Colour | Notes |
| --- | --- | --- |
| Accent (UI, best flag) | `#5FD068` tractor green | No other game uses green (Kart violet, Dodge blue, Tug orange, Safe brass, Cadence pink) |
| Ink | `#10200F` | UI outlines, board numbers |
| Clay track, lit | `#C27A4A` | inside a floodlight pool |
| Clay track, shade | `#5C3220` | between pools; ruts darker |
| Chalk lines | `#EDE6D6` | the side lines, the start line |
| Full Pull line | `#F2C230` / `#1A1A1A` checks | the brightest band on the track |
| Sled frame | `#F2B71C` hazard yellow | with black steel `#262626` |
| Weights | `#6A7480` | slate blocks, lighter tops |
| Boards | `#F2E6C8` face, `#10200F` numbers | posts `#5A4630` |
| Barrier | `#E8E4DC` and `#C8382E` stripes | a low rail along each side |
| Sky | zenith `#141C46` → mid `#3A4A8A` → horizon `#E8743B` | dusk |
| Floodlight | `#FFD9A0` | lamps, pools and cones |
| Fair lights | `#FFB347`, `#FF5D73`, `#6FD3FF` | the far wheel and string lights |

## 4. Lighting, materials and shading

- **Hand-lit, as every 3D game here:** every surface is `unshaded, fog_disabled`, with no engine
  lights, shadows or fog. `shaders/pull_look.gdshaderinc` defines The Pull's grade (a little
  extra saturation and contrast, a warm gain, blue-lifted shadows) on the shared
  `world_look.gdshaderinc`, and `WorldLook.apply` sets one dusk look on every material.
- **The floodlights are the key light.** Towers stand every 40 m on both sides. The track shader
  works out the nearest pair from `z` (a `mod`, no loop) and adds a warm pool of falloff; the
  ruts and grain come from two noise reads. Off-track props (stands, boards, barrier) take the
  pool too, per vertex (`pool_at` in the include).
- **The sky** is one gradient dome mesh (unshaded, no cubemap), with the horizon band and faint
  stars from one noise read.
- **Scenery** is vertex-coloured with painted AO, lit per vertex (hemisphere plus a weak moon),
  graded per pixel.
- **The sled** is vertex-coloured steel with painted AO. The box is a separate mesh that slides.
- **Self-lit:** the lamps, the far fair lights, the board faces (they catch the floods), the Full
  Pull line and the best flag.

## 5. Shapes and proportions

- **Chunky and readable.** Boards are 1.6 m wide on 2.2 m posts, numbers 0.9 m tall. The flag
  is 1.2 m on a 3.2 m pole. The Full Pull line is a 1 m checked band with a banner arch over it.
- **The sled:** a 4.2 m long, 1.8 m wide pan with upturned runners, a yellow box-frame and a
  hitch tower at the front. The weight box is a 1.2 m cage of slate blocks on two rails. Its
  front faces the bike.
- **The bike:** first person. The handlebars and gloves sit low at the bottom of the view. A round
  mirror on a stalk at the right end shows the sled.

## 6. Environment

- The track: 12 m of clay between low striped barriers, 420 m long. The Full Pull line sits at
  `full_m`, and a run-off continues past it.
- Boards every 25 m on the left. The best flag stands on the right at the rider's best distance.
- Bleachers on both sides at 16-22 m, with a crowd of billboards. Floodlight towers stand
  outside them.
- Beyond: tents, a tree line, a lit wheel on the right horizon, string lights. All one baked
  mesh.

## 7. VFX language

- **Dust:** a puff trail behind the sled's runners while it moves (`CPUParticles3D`, at most 24),
  seen in the mirror and the look-back.
- **Confetti:** a gold and green burst at a Full Pull (48 particles, one shot).
- **Strain:** a camera shake that grows as the speed falls below 0.6 m/s with power on, plus a
  red-amber flush tint on the view's image during Dig in! (its modulate, no overlay).
- **Flare:** the lamps' glow uniform jumps at a Full Pull and eases back.

## 8. Camera

- First person at an eye height of 1.55 m, pitch −6°, FOV 68°. A pedal-stroke bob of ±1.5 cm.
- Set: a yaw of up to 150° right over the shoulder, eased, then back for the horn.
- The mirror: a 256×144 SubViewport with a camera at head height looking back. It shows on the
  mirror glass, updated every frame at that size.

## 9. Tablet budget (Gen 2, PowerVR GX6250, Compatibility; no tracker)

- The 3D view renders into a SubViewport at a render scale of 0.62, MSAA off, drawn scaled under
  the HUD through a grid mesh carrying the vignette (Tug's pattern).
- Target: ≤ 30 world draw calls in the main view, ≤ 20 in the mirror. One baked scenery mesh, one
  crowd MultiMesh, one board MultiMesh and Label3D numbers (**open**: an atlas if they cost).
- No per-pixel `sin` hashes: noise from the shared texture, at most three reads a pixel on the
  track.
- `prewarm` draws the confetti and dust behind the intro card so their shaders compile then.
