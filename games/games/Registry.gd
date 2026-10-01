class_name GameRegistry
extends RefCounted
## Every game, by game_id (docs/GAMES.md, "Adding a game"). A new game is one folder here,
## `res://games/<game_id>/`, with a scene whose root extends `Game`, plus one line below.
## The game_id is the contract's `game_id` and must match the game's `info().id`.

const GAMES := {
	"demo": "res://games/demo/Demo.tscn",
	"dodge_ball": "res://games/dodge_ball/DodgeBall.tscn",
}

static var _infos := {}


static func has(game_id: String) -> bool:
	return GAMES.has(game_id)


static func ids() -> Array:
	return GAMES.keys()


## A fresh instance of the game's scene, or null for an unknown game_id.
static func instantiate(game_id: String) -> Game:
	if not GAMES.has(game_id):
		return null
	var scene := load(GAMES[game_id]) as PackedScene
	if scene == null:
		push_error("GameRegistry: can't load %s" % GAMES[game_id])
		return null
	var node := scene.instantiate()
	if node is Game:
		return node
	push_error("GameRegistry: %s's root doesn't extend Game" % GAMES[game_id])
	node.free()
	return null


## The game's declarations (cached), or null for an unknown game_id.
static func info(game_id: String) -> GameInfo:
	if _infos.has(game_id):
		return _infos[game_id]
	var game := instantiate(game_id)
	if game == null:
		return null
	var declared := game.declared()
	game.free()
	_infos[game_id] = declared
	return declared
