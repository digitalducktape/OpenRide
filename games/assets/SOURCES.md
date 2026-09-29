# Game asset sources

Every asset file under `games/` (sprites, textures, fonts, music, sound effects) is listed here
with its source, author and licence, in the same PR that adds it. Allowed: original work made
for this repo (including procedurally generated content), CC0 / public domain, and fonts under
the SIL Open Font License. A file with an unclear licence is not added. See the epic's
**Originality and licensing** rule (#31) and `docs/GAMES.md`.

Game music and sound effects are generated in code at runtime (#36, `games/audio/`), so the
audio itself needs no entry. The parameter files it renders from are listed below. They
contain no recorded sound, and the generated music doesn't quote or imitate existing songs or
game themes. The
framework (#34) and the demo game draw everything in code (shapes, a generated ball texture)
with Godot's default font.

| File | Source URL | Author | Licence |
| --- | --- | --- | --- |
| `audio/sfx/*.tres` (14 `SfxPreset` parameter sets: synth settings, no samples) | Written for this repo (#36) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `audio/styles/*.tres` (6 `MusicStyle` parameter sets: scales, chord progressions, patterns, synth settings; no samples) | Written for this repo (#36) | The OpenRide Authors | Apache-2.0, the repo's licence |
| `addons/gdUnit4/**/*.png` (9 UI images of the test framework; test-only, not exported) | https://github.com/godot-gdunit-labs/gdUnit4/tree/v6.2.1 | Mike Schulze and GdUnit4 contributors | MIT (`addons/gdUnit4/LICENSE`; code recorded in `THIRD_PARTY_NOTICES.md`) |
