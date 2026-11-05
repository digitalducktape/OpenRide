# Game asset sources

Every asset file under `games/` (sprites, textures, fonts, music, sound effects) is listed here
with its source, author and licence, in the same PR that adds it. Allowed: original work made
for this repo (including procedurally generated content), CC0 / public domain, and fonts under
the SIL Open Font License. A file with an unclear licence is not added. See the epic's
**Originality and licensing** rule (#31) and `docs/GAMES.md`.

Game music and sound effects are generated in code at runtime (#36, `games/audio/`). Since #39
the generator also plays a few recorded CC0 one-shots (drums and instrument tones under
`audio/samples/`), and Dodge Ball plays three CC0 impact recordings; each is listed below. The parameter files it renders from are listed below. They
contain no recorded sound, and the generated music doesn't quote or imitate existing songs or
game themes. The
framework (#34) and the demo game draw everything in code (shapes, a generated ball texture)
with Godot's default font.

| File | Source URL | Author | Licence |
| --- | --- | --- | --- |
| `audio/sfx/*.tres` (14 `SfxPreset` parameter sets: synth settings, no samples) | Written for this repo (#36) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `audio/styles/*.tres` (7 `MusicStyle` parameter sets; `kart_circuit` is Kart Race's, #43: scales, chord progressions, patterns, synth settings; `drive` names the samples listed below) | Written for this repo (#36) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `addons/gdUnit4/**/*.png` (9 UI images of the test framework; test-only, not exported) | https://github.com/godot-gdunit-labs/gdUnit4/tree/v6.2.1 | Mike Schulze and GdUnit4 contributors | MIT (`addons/gdUnit4/LICENSE`; code recorded in `THIRD_PARTY_NOTICES.md`) |
| `audio/samples/kick_punchy.wav` (from `Bass Drum/Wav/Bass Drum__009.wav`, resampled to 22.05 kHz mono) | https://opengameart.org/content/sfx-the-ultimate-2017-16-bit-mini-pack | phoenix1291 | CC0 1.0 |
| `audio/samples/snare_crack.wav` (from `Snare/Wav/Snare__003.wav`, resampled) | https://opengameart.org/content/sfx-the-ultimate-2017-16-bit-mini-pack | phoenix1291 | CC0 1.0 |
| `audio/samples/hat_closed.wav` (from `Hi-hat/Wav/Hi-hat__010.wav`, resampled) | https://opengameart.org/content/sfx-the-ultimate-2017-16-bit-mini-pack | phoenix1291 | CC0 1.0 |
| `audio/samples/hat_open.wav` (from `Hi-hat/Wav/Hi-hat__005.wav`, resampled) | https://opengameart.org/content/sfx-the-ultimate-2017-16-bit-mini-pack | phoenix1291 | CC0 1.0 |
| `audio/samples/tone_lead_a4.wav` (from `Instrument/Wav/Instrument__002.wav`, resampled) | https://opengameart.org/content/sfx-the-ultimate-2017-16-bit-mini-pack | phoenix1291 | CC0 1.0 |
| `audio/samples/tone_bass_d2.wav` (from `Instrument/Wav/Instrument__005.wav`, resampled) | https://opengameart.org/content/sfx-the-ultimate-2017-16-bit-mini-pack | phoenix1291 | CC0 1.0 |
| `games/dodge_ball/sounds/impactPunch_heavy_001.ogg`, `impactGlass_heavy_002.ogg`, `impactSoft_heavy_000.ogg` (unchanged) | https://kenney.nl/assets/impact-sounds | Kenney (www.kenney.nl) | CC0 1.0 (pack `License.txt`) |
| `games/dodge_ball/models/light-curved.glb`, `construction-cone.glb`, `Textures/colormap.png` (unchanged) | https://kenney.nl/assets/city-kit-roads (v2.1) | Kenney (www.kenney.nl) | CC0 1.0 (pack `License.txt`) |
| `games/dodge_ball/models/tree_default.glb`, `tree_oak.glb`, `tree_pineTallA.glb`, `tree_cone.glb`, `plant_bushLarge.glb`, `rock_largeA.glb` (unchanged; recoloured at runtime) | https://kenney.nl/assets/nature-kit | Kenney (www.kenney.nl) | CC0 1.0 (pack `License.txt`) |
| `games/dodge_ball/sfx/*.tres` (7 `SfxPreset` parameter sets) and `tod/*.tres` (4 lighting presets), with the scripts that write them | Written for this repo (#39) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/dodge_ball/shaders/*.gdshader` and `look.gdshaderinc` (road, verge, sky, scenery, handlebars, bursts, ball, warning, shadow, shield, screen effects), and the procedural horizon, fence and handlebar meshes in `DodgeWorld.gd` | Written for this repo (#39, graphics pass 2026-10-20) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/tug_of_war/sfx/*.tres` (6 `SfxPreset` parameter sets: rope_creak, crowd_swell, surge_drumroll, win_sting, lose_sting, splash; synth settings, no samples) | Written for this repo (#40) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/tug_of_war/shaders/*.gdshader`, `tug_look.gdshaderinc` and every mesh in `TugMeshes.gd` / `TugWorld.gd` (banks, piers, deck planks, water, the wind-up tin robot, the crowd's two-frame sprite drawn in code, gloves, rope, flag, bunting, string lights, reeds, tent, hay bales, lily pads, flames, steam, splash; graphics pass 2026-10-19, built from primitives and `KartMeshKit` shapes in code; `sky.gdshader` is a copy of Dodge Ball's with Tug's grade) | Written for this repo (#40) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/the_pull/shaders/*.gdshader`, `pull_look.gdshaderinc` and every mesh in `PullMeshes.gd` / `PullWorld.gd` (the clay track, infield, dusk sky and clouds, stands with painted panels, bunting and bulbs, billboard crowd, barriers, floodlight towers and halos, distance boards, the Full Pull line and arch, the far fair's tents, wheel and string lights, the sled, its weight box and chain, the handlebars and mirror, the best flag; built from primitives and `KartMeshKit` shapes in code; `PullIntroArt.gd`, the intro card's sled, drawn in code). The track's words are generic ("FULL PULL", distances, "YOUR BEST"), no league's name or livery | Written for this repo (#79) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/balloon_pump/shaders/*.gdshader` and every shape in `PumpPlaces.gd`, `PumpArt.gd` and `PumpStage.gd` (the brass pump, plunger, gauge, hose, stand and basket; the balloons and the bunch; the fair at dusk, the big top and the pier: tents, Ferris wheel, curtains, ring curb, trunk, sea, moon, railing, lanterns, bulbs; the 2D rework of 2026-11-02, drawn in code with Safe Cracker's `SafeMesh` batcher; no textures but a soft dot) | Written for this repo (#76) | The OpenRide Authors | Apache-2.0, the repo's licence |

The Pull (#79) adds no recorded asset: everything in its world is built in code, its board
numbers use the shared OFL display face, and its music and effects are rendered by
`games/tools/music` (below).

Tug of War (#40) adds no recorded asset: its trees, bushes and rocks are the Kenney nature-kit
models listed above (loaded from `games/dodge_ball/models/`, recoloured and baked into its
riverside mesh at runtime), its bots are named from plain
material and animal words, and its music was the repo's own `heave` style (since #55 a rendered theme, below).
| `games/safe_cracker/sfx/*.tres` (5 `SfxPreset` parameter sets: tumbler_click, proximity_tick, soft_alarm, vault_open, door_creak; synth settings, no samples) | Written for this repo (#41) | The OpenRide Authors | Apache-2.0, the repo's licence |
| Every shape in `SafePlaces.gd`, `SafeBackdrop.gd`, `SafeBody.gd`, `SafeDoor.gd` and `SafeDial.gd` (six rooms with their props and key lights, the safe, its door, hardware, dial, vault and gold, drawn in code through `SafeMesh.gd`) | Written for this repo (#41) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/safe_cracker/safe_door.gdshader`, `safe_rain.gdshader`, `safe_sea.gdshader`, `safe_shimmer.gdshader` (the door's perspective swing, the office rain, the porthole sea, the flasks' shimmer) | Written for this repo (#41) | The OpenRide Authors | Apache-2.0, the repo's licence |

Safe Cracker (#41) adds no recorded or imported asset: it draws everything in code (the dust
and sparkle dot is a `GradientTexture2D` made at run time), uses the framework's display font and
until #55 (below), the repo's own `noir` music style.
| `games/cadence_karaoke/sfx/*.tres` (4 `SfxPreset` parameter sets: beat_tick, streak_up, band_exit, ease_off_chime; synth settings, no samples) | Written for this repo (#42) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/cadence_karaoke/shaders/*` (the tunnel grid include and its floor, wall and ceiling wrappers, `cadence_look.gdshaderinc`, ring, orb, orb halo, orb pool, portal and spark shaders) and every mesh in `CadenceWorld.gd` (tunnel, the beat rings' frame mesh, the box, orb, halo, pool, portal card and sparks; shaders, primitive meshes and a mesh built in code, no textures beyond the shared runtime noise) | Written for this repo (#42) | The OpenRide Authors | Apache-2.0, the repo's licence |

Cadence Karaoke (#42) adds no recorded or imported asset: it is drawn in code, uses Godot's
default font and, until #55 (below), the repo's own `bright` music style.

| `games/kart_race/world/shaders/*.gdshader`, `*.gdshaderinc` (road, ground, sky, scenery, water, boost pads, kart toon and rig, outline, crowd, flags, lamps, the item glass, glow, goo, shield, beam and trails) and `games/kart_race/ui/shaders/*.gdshader` (text gradient, portrait, portrait atlas, sunburst) | Written for this repo (#43) | The OpenRide Authors | Apache-2.0, the repo's licence |
| Every mesh and texture in `KartMeshKit.gd`, `KartWorld.gd`, `KartTerrain.gd`, `KartDress*.gd` (the four tracks' dressing), `KartLook.gd`, `KartModels.gd`, `KartView.gd`, `KartItemViews.gd`, `KartFx.gd`, `KartHud.gd` and `KartRaceBoard.gd` (karts, the eight animal drivers, terrain, trees, rocks, mesas, rock arches and spire, houses, a clock tower, quays, boats, lighthouse, a hot-air balloon, ice-fishing huts and a jetty, snow, frozen lakes, themed grandstands and banners, the two-frame crowd sprite, start gate, flags, fences, windmill, bevelled tyre stacks and barrels, hills, clouds, the items, portraits, the item icons, confetti; built from primitive shapes and generated images in code) | Written for this repo (#43) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/kart_race/audio/KartSfx.gd` (the kart effects in code: SfxSynth presets, layered one-shots, and synthesised engine and spark loops; synth settings, no samples) | Written for this repo (#43) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/kart_race/music/*.ogg` (each track's theme and final-lap version, the results loop, the podium sting) and `games/kart_race/audio/KartMusicIndex.gd`, rendered by `tools/kart_music/` (compositions, synthesis and drum synthesis written for this repo; no samples, no third-party material) | Written for this repo (#43) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/kart_race/ui/tracks/*.png` (the kart and track picker's four track thumbnails, 384×216: each track's title shot rendered by the game itself and scaled down by `tests/capture_track_thumbs.gd`) | Original, rendered from this repo's own tracks (#43) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/kart_race/ui/fonts/LilitaOne-Regular.ttf` (unchanged; Kart Race's display face) | https://github.com/google/fonts/tree/main/ofl/lilitaone | Juan Montoreano | SIL OFL 1.1 (`games/kart_race/ui/fonts/LilitaOne-OFL.txt`) |

Kart Race (#43) adds one imported asset, the OFL display font above; everything else is
procedural, or rendered offline from the game's own scenes (the picker's track thumbnails).

| File | Source URL | Author | Licence |
| --- | --- | --- | --- |
| `assets/fonts/LilitaOne-Regular.ttf` (unchanged; the shared display face of `GameTheme`, a copy of Kart Race's) | https://github.com/google/fonts/tree/main/ofl/lilitaone | Juan Montoreano | SIL OFL 1.1 (`assets/fonts/LilitaOne-OFL.txt`) |
| `framework/shaders/world_look.gdshaderinc` (the 3D games' shared hand light, haze and grade) and `framework/WorldLook.gd` (its uniforms and generated noise texture) | Written for this repo (graphics pass) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `framework/ui/shaders/text_gradient.gdshader` (the kit's gradient text fill, a copy of Kart Race's) | Written for this repo | The OpenRide Authors | Apache-2.0, the repo's licence |

The shared game-UI kit (`framework/ui/GameTheme.gd`, `UI_STYLE.md`) uses that one OFL face for
every game. Kart Race still loads its own copy, so both files ship until Kart moves to the shared
path.

## Rendered music and effects (#55)

Every file below is synthesised by code written for this repo (`games/tools/music/`: numpy and
scipy; drum synthesis, Karplus-Strong strings, FM and additive keys, saw stacks; compositions
written for this repo). No samples, soundfonts or third-party material.

| Asset | Source | Author | Licence |
| --- | --- | --- | --- |
| `games/the_pull/music/*.ogg`, `music/sfx/*.ogg` and `PullMusic.gd` ("Heavy Haul", a county-fair boogie at 116 bpm in E, and the game's effects: three loops and seven one-shots) | Written for this repo (#79), `songs/the_pull.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/dodge_ball/music/*.ogg`, `music/sfx/*.ogg` and `DodgeMusic.gd` ("Incoming!" and the game's effects) | Written for this repo (#55), `games/tools/music/songs/dodge_ball.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/tug_of_war/music/*.ogg`, `music/sfx/*.ogg` and `TugMusic.gd` ("Heave Together" and the game's effects) | Written for this repo (#55), `songs/tug_of_war.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/balloon_pump/music/*.ogg`, `music/sfx/*.ogg` and `PumpMusic.gd` ("Midnight Carousel", a swung band-organ carousel at 126 bpm in D minor, and the game's effects: pump chuff, rubber squeak, tie-off pop and twang, hiss, chimes, stings, tick) | Written for this repo (#76), `songs/balloon_pump.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/safe_cracker/music/*.ogg`, `music/sfx/*.ogg` and `SafeMusic.gd` ("Night Shift" and the game's effects) | Written for this repo (#55), `songs/safe_cracker.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/cadence_karaoke/music/neon_lines_bank.ogg`, `music/sfx/*.ogg` and `CadenceMusic.gd` ("Neon Lines": a sample bank and a score, and the game's effects) | Written for this repo (#55), `songs/cadence_karaoke.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/demo/music/*.ogg`, `music/sfx/*.ogg` and `DemoMusic.gd` ("Warm Up", `dodge`, `hit`) | Written for this repo (#55), `songs/demo.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `audio/cues/*.ogg` and `audio/CueSounds.gd` (the framework's cues) | Written for this repo (#55), `songs/cues.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `hub/music/*.ogg` and `hub/HubMusicIndex.gd` ("Lobby Loop", the Games hub's theme: 108 bpm in G major, three stems, 985 KB; original melody and arrangement, synthesised, no samples) | Written for this repo (the Games hub, spec §8.5), `songs/hub.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/*/hub_card.png` (each game's 512×288 card picture in the Games hub: its own world, rendered by the game and scaled down by `tests/capture_hub_cards.gd`) | Original, rendered from this repo's own games (the Games hub) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/watt_lane/shaders/*` (`wl_field.gdshader`, `wl_lane.gdshader`) and the shapes in `WattLaneTrack.gd` (the chevron, built in code; no textures beyond the shared runtime noise and Safe Cracker's soft dot) | Written for this repo (#78) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/watt_lane/music/*.ogg`, `music/sfx/*.ogg` and `WattLaneMusic.gd` ("Live Wire": dream-pop electronica, 112 bpm in Eb major, three stems; and the game's effects; original melody and arrangement, synthesised, no samples) and the hum loop rendered at runtime by `WattLaneAudio.hum` | Written for this repo (#78), `songs/watt_lane.py` | The OpenRide Authors | Apache-2.0, the repo's licence |
