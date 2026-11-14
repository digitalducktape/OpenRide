class_name HubState
extends RefCounted
## Reads a `hub_state` snapshot (Bridge v1.1, spec §3.1) with every documented default, so an
## old or partial payload still draws: Godot treats a missing key as its default. Numbers
## arrive as floats.

const DEFAULTS := {
	"hub_version": 1,
	"visit_id": "",
	"phase": "hub",
	"rider": {"id": null, "name": "", "avatar_png": null, "avatar_color": "#7A7CFF", "ftp_watts": 150,
		"ftp_is_default": false},
	"settings": {"camera_games": true, "game_music": true, "music_volume": 0.8, "sfx_volume": 1.0,
		"lean_sensitivity": "normal"},
	"audio": {"music": true, "music_volume": 0.8, "sfx_volume": 1.0},
	"camera": {"permission": "granted", "available": true, "calibrated": "", "same_day_extremes": false},
	"catalog": [],
	"circuits": [],
	"bests": {"games": [], "plans": []},
	"visit": {"recording": true, "ride_sec": 0, "gameplay_sec": 0, "plans": []},
}
const ENTRY_DEFAULTS := {"id": "", "title": "", "supports": ["minutes"], "min_sec": 60, "max_sec": 3600,
	"min_rounds": 1, "max_rounds": 10, "round_sec": 60, "roles": [], "uses_camera": false,
	"minute_steps": [5, 10, 15, 20, 30, 45, 60], "circuit_role": "free"}


## The snapshot with every missing key (at any level shown above) filled from DEFAULTS; catalog
## entries are filled from ENTRY_DEFAULTS, and entries without an id are dropped.
static func normalized(raw: Dictionary) -> Dictionary:
	var out := _merge(DEFAULTS, raw)
	var catalog: Array = []
	for e in out.catalog:
		if e is Dictionary and not str(e.get("id", "")).is_empty():
			var entry := _merge(ENTRY_DEFAULTS, e)
			if str(entry.title).is_empty():
				entry.title = str(entry.id).capitalize()
			catalog.append(entry)
	out.catalog = catalog
	out.circuits = out.circuits.filter(func(c): return c is Dictionary and c.has("id"))
	return out


## Games to show: the catalog (Kotlin decides what's playable) intersected with GameRegistry.
static func games(state: Dictionary) -> Array:
	return state.catalog.filter(func(e): return GameRegistry.has(str(e.id)) or str(e.id) in test_ids)


## Ids shown as if registered: lets hub tests lay out a bigger catalog (#75's 11 games).
static var test_ids: Array = []


static func entry(state: Dictionary, game_id: String) -> Dictionary:
	for e in state.catalog:
		if str(e.id) == game_id:
			return e
	return {}


static func circuit(state: Dictionary, circuit_id: String) -> Dictionary:
	for c in state.circuits:
		if str(c.id) == circuit_id:
			return c
	return {}


## Whether a game can start now: a camera game needs the camera.
static func playable(state: Dictionary, e: Dictionary) -> bool:
	return not bool(e.get("uses_camera", false)) or bool(state.camera.available)


## The rider's best Just Ride of a game, any length: {score, stars} with the highest score, or {}.
static func game_best(state: Dictionary, game_id: String, difficulty := "") -> Dictionary:
	var best := {}
	for row in state.bests.games:
		if str(row.get("game_id", "")) != game_id or not str(row.get("plan_id", "")).begins_with("just-ride:"):
			continue
		if not difficulty.is_empty() and str(row.get("difficulty", "")) != difficulty:
			continue
		if best.is_empty() or float(row.get("score", 0)) > float(best.score):
			best = {"score": int(row.get("score", 0)), "stars": int(row.get("stars", 0))}
	return best


## The rider's best Just Ride at a plan id and difficulty (`bests.games`, any variant):
## {score, stars}, or {}.
static func just_ride_best(state: Dictionary, game_id: String, plan_id: String, difficulty: String) -> Dictionary:
	var best := {}
	for row in state.bests.games:
		if str(row.get("game_id", "")) == game_id and str(row.get("plan_id", "")) == plan_id \
				and str(row.get("difficulty", "")) == difficulty \
				and (best.is_empty() or float(row.get("score", 0)) > float(best.score)):
			best = {"score": int(row.get("score", 0)), "stars": int(row.get("stars", 0))}
	return best


## The rider's best at a plan id and difficulty: {score, stars}, or {}.
static func plan_best(state: Dictionary, plan_id: String, difficulty: String) -> Dictionary:
	for row in state.bests.plans:
		if str(row.get("plan_id", "")) == plan_id and str(row.get("difficulty", "")) == difficulty:
			return {"score": int(row.get("score", 0)), "stars": int(row.get("stars", 0))}
	return {}


## The circuit's best at any difficulty (for its card).
static func circuit_best(state: Dictionary, circuit_id: String) -> Dictionary:
	var best := {}
	for row in state.bests.plans:
		if str(row.get("plan_id", "")) == circuit_id and (best.is_empty() or float(row.get("score", 0)) > float(best.score)):
			best = {"score": int(row.get("score", 0)), "stars": int(row.get("stars", 0))}
	return best


## "Ride so far 12:30 · 2 games" (menu time excluded), "" before the first plan, or why
## nothing records.
static func ride_line(state: Dictionary) -> String:
	if not bool(state.visit.recording):
		if state.rider.id == null:
			return "Not recording: pick a rider in the app"
		return "Not recording: another ride is running"
	var plans: Array = state.visit.plans
	if plans.is_empty():
		return "Ride starts with a game"
	var games := 0
	for p in plans:
		games += (p.get("game_ids", []) as Array).size()
	return "Ride so far %s · %d %s" % [HudTheme.clock(float(state.visit.ride_sec)), games, "game" if games == 1 else "games"]


static func _merge(defaults: Dictionary, raw: Dictionary) -> Dictionary:
	var out := {}
	for key in defaults:
		var d = defaults[key]
		var v = raw.get(key)
		if v == null and d != null:
			out[key] = d.duplicate(true) if d is Dictionary or d is Array else d
		elif d is Dictionary and v is Dictionary:
			out[key] = _merge(d, v)
		elif d is Array and not (v is Array):
			out[key] = d.duplicate(true)
		elif d is Dictionary and not (v is Dictionary):
			out[key] = d.duplicate(true)
		else:
			out[key] = v
	for key in raw:
		if not out.has(key):
			out[key] = raw[key]
	return out
