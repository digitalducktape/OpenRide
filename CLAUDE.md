# OpenRide agent notes

## GodotPrompter

The mini-games in `games/` are a Godot 4.7 project (GL Compatibility renderer).

- Before you implement or change any Godot system (scenes, input, UI, audio, shaders, 3D, tests), invoke the matching `godot-prompter:*` skill. The skill index is `godot-prompter:using-godot-prompter`.
- Before you build, report the pattern you picked, the alternative you rejected, and why.
- `docs/GAMES.md` is the source of truth for the Kotlin–Godot bridge contract and the shared framework.
