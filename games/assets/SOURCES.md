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
| `audio/styles/*.tres` (6 `MusicStyle` parameter sets: scales, chord progressions, patterns, synth settings; `drive` names the samples listed below) | Written for this repo (#36) | The OpenRide Authors | Apache-2.0, the repo's licence |
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
| `games/dodge_ball/shaders/*.gdshader` (road, verge, sky, ball, warning, shadow, shield, screen effects) | Written for this repo (#39) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/tug_of_war/sfx/*.tres` (6 `SfxPreset` parameter sets: rope_creak, crowd_swell, surge_drumroll, win_sting, lose_sting, splash; synth settings, no samples) | Written for this repo (#40) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `games/tug_of_war/shaders/water.gdshader` and every mesh in `TugWorld.gd` (piers, bot, crowd, rope, flag, hands, splash; built from boxes, cylinders, spheres and capsules in code, with a plank texture generated at runtime) | Written for this repo (#40) | The OpenRide Authors | Apache-2.0, the repo's licence |

Tug of War (#40) adds no recorded asset: its trees, bushes and rocks are the Kenney nature-kit
models listed above (loaded from `games/dodge_ball/models/`), its bots are named from plain
material and animal words, and its music is the repo's own `heave` style.
| `games/safe_cracker/sfx/*.tres` (5 `SfxPreset` parameter sets: tumbler_click, proximity_tick, soft_alarm, vault_open, door_creak; synth settings, no samples) | Written for this repo (#41) | The OpenRide Authors | Apache-2.0, the repo's licence |
| Every shape in `SafePlaces.gd`, `SafeBody.gd` and `SafeDial.gd` (six rooms, the safe, its dial and the gold, drawn in code) | Written for this repo (#41) | The OpenRide Authors | Apache-2.0, the repo's licence |

Safe Cracker (#41) adds no recorded or imported asset: it draws everything in code, uses Godot's
default font and the repo's own `noir` music style.

