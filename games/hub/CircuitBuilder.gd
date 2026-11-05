class_name CircuitBuilder
extends RefCounted
## The custom circuit being built (spec §8.3 "Builder", §3.4 `custom`): a lineup of up to
## MAX_SLOTS games, each with its own length, at most MAX_SEC of gameplay in all. Pure data (the
## BuilderScreen draws it, HubPrefs stores it), so the rules are tested without a screen.
##
## It mirrors Kotlin's SessionPlans.custom, which stays the source of truth:
## - a slot's seconds are rounded to 30 s, then clamped to the game's min_sec..max_sec;
## - a slot's role is the game's `circuit_role`, except that the first slot plays warm-up and the
##   last cool-down when the game has those roles (display only: Kotlin decides);
## - the plan id is `custom:` plus `<game_id>.<sec>` joined by `,` (the same lineup keys the same
##   bests);
## - with the camera off, a camera game's slot plays the first camera-free game of its role,
##   and a slot with no such game, or a `free` one (Kart Race), can't play.

const MAX_SLOTS := 12
const MAX_SEC := 90 * 60
const STEP_SEC := 30
## Steps are 30 s up to this, then 1 min.
const FINE_UNTIL_SEC := 5 * 60
## A new slot's length: the game's minimum, or this if longer.
const ADD_SEC := 90
const INTRO_SEC := 10

## The catalog entries (hub_state.catalog, normalized), by id.
var catalog: Dictionary = {}
## [{game_id, duration_sec}], in play order.
var slots: Array = []
var difficulty := "standard"
## Saved slots left out because their game isn't in the catalog any more (or past MAX_SLOTS).
var dropped := 0


func _init(catalog_entries: Array = [], lineup: Array = [], level := "standard") -> void:
	for e in catalog_entries:
		catalog[str(e.id)] = e
	difficulty = level if level in HubPrefs.DIFFICULTIES else "standard"
	for s in lineup:
		var id := str(s.get("game_id", ""))
		if catalog.has(id) and slots.size() < MAX_SLOTS:
			slots.append({"game_id": id, "duration_sec": seconds_for(catalog[id], int(s.get("duration_sec", 0)))})
		else:
			dropped += 1


## Kotlin's customSeconds: rounded to 30 s, then clamped to the game's limits.
static func seconds_for(entry: Dictionary, sec: int) -> int:
	var rounded := int(roundf(sec / float(STEP_SEC))) * STEP_SEC
	return clampi(rounded, int(entry.get("min_sec", 60)), int(entry.get("max_sec", 3600)))


## Every length a slot of `entry` can have: 30 s steps up to 5 min, then whole minutes.
static func steps_for(entry: Dictionary) -> Array:
	var lo := int(entry.get("min_sec", 60))
	var hi := int(entry.get("max_sec", 3600))
	var out: Array = []
	var s := lo
	while s <= hi:
		var v := seconds_for(entry, s)
		if out.is_empty() or v > int(out.back()):
			out.append(v)
		s = (s / STEP_SEC + 1) * STEP_SEC if s < FINE_UNTIL_SEC else (s / 60 + 1) * 60
	return out


## A new slot's length for `entry`.
static func add_seconds(entry: Dictionary) -> int:
	return seconds_for(entry, maxi(int(entry.get("min_sec", 60)), ADD_SEC))


func size() -> int:
	return slots.size()


func is_empty() -> bool:
	return slots.is_empty()


## Seconds of gameplay in all.
func gameplay_sec() -> int:
	var total := 0
	for s in slots:
		total += int(s.duration_sec)
	return total


## The circuit's time with each game's intro card (as a preset's `total_sec`).
func total_sec() -> int:
	return gameplay_sec() + INTRO_SEC * slots.size()


## "" when `game_id` can be added, else why not ("full", "too_long", "unknown").
func add_problem(game_id: String) -> String:
	if not catalog.has(game_id):
		return "unknown"
	if slots.size() >= MAX_SLOTS:
		return "full"
	if gameplay_sec() + add_seconds(catalog[game_id]) > MAX_SEC:
		return "too_long"
	return ""


## Adds `game_id` at the end; false (nothing changes) when add_problem says why not.
func add(game_id: String) -> bool:
	if not add_problem(game_id).is_empty():
		return false
	slots.append({"game_id": game_id, "duration_sec": add_seconds(catalog[game_id])})
	return true


func remove(index: int) -> void:
	if index >= 0 and index < slots.size():
		slots.remove_at(index)


## Moves slot `index` by `delta` (-1 up, +1 down); false at an end.
func move(index: int, delta: int) -> bool:
	var to := index + delta
	if index < 0 or index >= slots.size() or to < 0 or to >= slots.size():
		return false
	var s = slots[index]
	slots.remove_at(index)
	slots.insert(to, s)
	return true


## The lengths slot `index` may take now: its game's steps, up to what keeps the total within
## MAX_SEC (its current length always stays in).
func lengths(index: int) -> Array:
	var s: Dictionary = slots[index]
	var room := MAX_SEC - (gameplay_sec() - int(s.duration_sec))
	return steps_for(catalog[s.game_id]).filter(func(v): return int(v) <= room or int(v) == int(s.duration_sec))


func set_length(index: int, sec: int) -> void:
	if index < 0 or index >= slots.size():
		return
	var s: Dictionary = slots[index]
	var v := seconds_for(catalog[s.game_id], sec)
	if gameplay_sec() - int(s.duration_sec) + v <= MAX_SEC:
		s.duration_sec = v


## The role slot `index` plays (Kotlin's SessionPlans.customRole).
func role(index: int) -> String:
	var e: Dictionary = catalog[slots[index].game_id]
	var roles: Array = e.get("roles", [])
	if index == 0 and "warmup" in roles:
		return "warmup"
	if index == slots.size() - 1 and slots.size() > 1 and "cooldown" in roles:
		return "cooldown"
	return str(e.get("circuit_role", "free"))


## The lineup as a preset's `slots` (game, role, seconds), for LineupStrip.
func lineup() -> Array:
	var out: Array = []
	for i in slots.size():
		out.append({"game_id": slots[i].game_id, "role": role(i), "duration_sec": slots[i].duration_sec})
	return out


func plan_id() -> String:
	var parts: PackedStringArray = []
	for s in slots:
		parts.append("%s.%d" % [s.game_id, int(s.duration_sec)])
	return "custom:" + ",".join(parts)


## The `start_plan` request (spec §3.4).
func request() -> Dictionary:
	var out: Array = []
	for s in slots:
		out.append({"game_id": str(s.game_id), "duration_sec": int(s.duration_sec)})
	return {"kind": "custom", "difficulty": difficulty, "slots": out}


## The circuit as HubPrefs stores it.
func to_saved() -> Dictionary:
	return {"v": 1, "slots": request().slots, "difficulty": difficulty}


## What a slot plays with the camera off: its game, the first camera-free game of the same
## `circuit_role` (Kotlin's customGame), or "" when there is none. A `free` slot (a game with no
## circuit role, like Kart Race) has no stand-in: The Pull is free too, but no substitute for a
## race (#79).
func stand_in(game_id: String) -> String:
	var e: Dictionary = catalog.get(game_id, {})
	if not bool(e.get("uses_camera", false)):
		return game_id
	if str(e.get("circuit_role", "free")) == "free":
		return ""
	for other in catalog.values():
		if not bool(other.get("uses_camera", false)) and str(other.circuit_role) == str(e.get("circuit_role", "")):
			return str(other.id)
	return ""


## Why this lineup can't start now, or "": "empty", or the first game with no stand-in when
## the camera is off ("camera:<game_id>").
func start_problem(camera_available: bool) -> String:
	if slots.is_empty():
		return "empty"
	if not camera_available:
		for s in slots:
			if stand_in(str(s.game_id)).is_empty():
				return "camera:" + str(s.game_id)
	return ""
