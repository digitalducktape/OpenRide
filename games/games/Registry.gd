class_name GameRegistry
extends RefCounted
## Every game, by game_id (docs/GAMES.md, "Adding a game"). A new game is one folder here,
## `res://games/<game_id>/`, with a scene whose root extends `Game`, plus one line below.
## The game_id is the contract's `game_id` and must match the game's `info().id`.

const GAMES := {
	"demo": "res://games/demo/Demo.tscn",
	"dodge_ball": "res://games/dodge_ball/DodgeBall.tscn",
	"tug_of_war": "res://games/tug_of_war/TugOfWar.tscn",
	"safe_cracker": "res://games/safe_cracker/SafeCracker.tscn",
	"cadence_karaoke": "res://games/cadence_karaoke/CadenceKaraoke.tscn",
	"kart_race": "res://games/kart_race/KartRace.tscn",
	"watt_lane": "res://games/watt_lane/WattLane.tscn",
	"the_pull": "res://games/the_pull/ThePull.tscn",
	"balloon_pump": "res://games/balloon_pump/BalloonPump.tscn",
	"keepy_uppy": "res://games/keepy_uppy/KeepyUppy.tscn",
	"power_grid": "res://games/power_grid/PowerGrid.tscn",
	"ready_for_launch": "res://games/ready_for_launch/ReadyForLaunch.tscn",
	"gate_crasher": "res://games/gate_crasher/GateCrasher.tscn",
}

static var _infos := {}
## Background loading (the bike's "first launch / starting a game takes too long", 2026-10-20):
## every game's declarations load on a loader thread at boot, one scene at a time (the hub's
## game cards would otherwise block ~3 s loading all six), and a game the rider is about to
## play loads ahead (`prefetch`, on its hub card) and is kept until it starts.
static var _warm_queue: Array[String] = []  # game_ids whose info still loads in the background
static var _requested := {}  # path -> true: a load_threaded_request of ours not yet collected
static var _held := {}  # game_id -> PackedScene kept for a coming start (prefetch)


static func has(game_id: String) -> bool:
	return GAMES.has(game_id)


static func ids() -> Array:
	return GAMES.keys()


## A fresh instance of the game's scene, or null for an unknown game_id. Uses a prefetched or
## background-loaded scene when there is one (waiting for it if it is still loading).
static func instantiate(game_id: String) -> Game:
	if not GAMES.has(game_id):
		return null
	var scene := _scene(game_id)
	if scene == null:
		push_error("GameRegistry: can't load %s" % GAMES[game_id])
		return null
	var node := scene.instantiate()
	if node is Game:
		return node
	push_error("GameRegistry: %s's root doesn't extend Game" % GAMES[game_id])
	node.free()
	return null


## The game's declarations (cached), or null for an unknown game_id. Blocks while the scene
## loads; the hub uses `cached_info` instead.
static func info(game_id: String) -> GameInfo:
	if _infos.has(game_id):
		return _infos[game_id]
	var started := Time.get_ticks_msec()
	var game := instantiate(game_id)
	if game == null:
		return null
	_store_info(game_id, game)
	print("OPENRIDE_GAMES load info game=%s ms=%d (waited)" % [game_id, Time.get_ticks_msec() - started])
	return _infos[game_id]


## The game's declarations if they have loaded, else null (never blocks).
static func cached_info(game_id: String) -> GameInfo:
	return _infos.get(game_id)


## Starts loading every game's declarations in the background (the hub, at boot). `poll()`
## collects them, one scene at a time.
static func warm_infos() -> void:
	for game_id in GAMES:
		if not _infos.has(game_id) and game_id not in _warm_queue:
			_warm_queue.append(game_id)
	poll()


## Whether every game's declarations are in.
static func infos_ready() -> bool:
	return _warm_queue.is_empty() and _infos.size() >= GAMES.size()


## Call once a frame (SessionDirector does): collects a finished background load and starts the
## next. Cheap while a load runs (a status check).
static func poll() -> void:
	while not _warm_queue.is_empty():
		var game_id: String = _warm_queue[0]
		if _infos.has(game_id) or not GAMES.has(game_id):
			_warm_queue.pop_front()
			continue
		var path: String = GAMES[game_id]
		if not _held.get(game_id) is PackedScene:
			if not _requested.has(path):
				_request(path)
				return
			if ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				return
		var started := Time.get_ticks_msec()
		var game := instantiate(game_id)
		_warm_queue.pop_front()
		if game:
			_store_info(game_id, game)
			print("OPENRIDE_GAMES load info game=%s ms=%d (background)" % [game_id, Time.get_ticks_msec() - started])
		return


## The rider picked this game's card: load its scene now, on a loader thread, and keep it until
## the game starts (`instantiate`) or another game is prefetched. Several ids for a circuit.
static func prefetch(game_ids: Array) -> void:
	for game_id in _held.keys():
		if game_id not in game_ids:
			_held.erase(game_id)
	for game_id in game_ids:
		if GAMES.has(game_id) and not _held.has(game_id):
			_held[game_id] = null  # loading
			_request(GAMES[game_id])


## Whether a game's scene is held or loading for a coming start (tests).
static func is_prefetched(game_id: String) -> bool:
	return _held.has(game_id)


## Drops prefetched scenes (back on the hub's home screen, or a game started).
static func release() -> void:
	_held.clear()


static func _request(path: String) -> void:
	if _requested.has(path):
		return
	# One loader thread, no sub-threads: a scene's scripts and resources compile in order.
	if ResourceLoader.load_threaded_request(path, "PackedScene", false) == OK:
		_requested[path] = true


static func _scene(game_id: String) -> PackedScene:
	var held = _held.get(game_id)
	if held is PackedScene:
		return held
	var path: String = GAMES[game_id]
	var scene: PackedScene
	if _requested.has(path):
		_requested.erase(path)
		scene = ResourceLoader.load_threaded_get(path) as PackedScene  # waits if still loading
	else:
		scene = load(path) as PackedScene
	if _held.has(game_id):
		_held[game_id] = scene
	return scene


static func _store_info(game_id: String, game: Game) -> void:
	_infos[game_id] = game.declared()
	game.free()
