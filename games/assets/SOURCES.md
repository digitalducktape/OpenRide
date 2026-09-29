# Game asset sources

Every asset file under `games/` (sprites, textures, fonts, music, sound effects) is listed here
with its source, author and licence, in the same PR that adds it. Allowed: original work made
for this repo (including procedurally generated content), CC0 / public domain, and fonts under
the SIL Open Font License. A file with an unclear licence is not added. See the epic's
**Originality and licensing** rule (#31) and `docs/GAMES.md`.

Game music and sound effects are generated in code at runtime, so they need no entry. The
framework (#34) and the demo game draw everything in code (shapes, a generated ball texture)
with Godot's default font.

| File | Source URL | Author | Licence |
| --- | --- | --- | --- |
| `addons/gdUnit4/**/*.png` (9 UI images of the test framework; test-only, not exported) | https://github.com/godot-gdunit-labs/gdUnit4/tree/v6.2.1 | Mike Schulze and GdUnit4 contributors | MIT (`addons/gdUnit4/LICENSE`; code recorded in `THIRD_PARTY_NOTICES.md`) |
