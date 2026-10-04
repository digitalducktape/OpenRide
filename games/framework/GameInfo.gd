class_name GameInfo
extends RefCounted
## What a game declares about itself (docs/GAMES.md, "Adding a game"). `Game.info()` returns
## one; `GameRegistry` caches it per game_id, and `Session` reads it before a segment starts.

const SUPPORTS := ["rounds", "minutes", "open"]
const ROLES := ["warmup", "work", "recovery", "cooldown"]
const TRACKER_MODES := ["off", "lean_x", "lean_2d", "lean_stand"]
const DIFFICULTIES := ["easy", "standard", "hard"]

var id := ""  ## the game_id: its folder under res://games/ and its registry key
var title := ""  ## shown on the intro card and the summary, e.g. "Tug of War"
var how_to := ""  ## one line for the intro card, e.g. "Pull harder than the bot"
## Just Ride modes: any of "rounds", "minutes" and "open".
var supports: Array[String] = ["minutes", "open"]
var min_sec := 60  ## shortest timed segment ("minutes"), in seconds
var max_sec := 3600  ## longest timed segment
var min_rounds := 1  ## for "rounds"
var max_rounds := 10
## Circuit roles the game can fill: "warmup", "work", "recovery", "cooldown".
var roles: Array[String] = []
## The camera mode Session sets while this game is on screen: "off", "lean_x", "lean_2d" or
## "lean_stand".
var tracker_mode := "off"
## Whether the effort multiplier applies in a Just Ride (it always does in work segments).
var effort_in_just_ride := false
## Score → stars, per difficulty: {"easy": [one, two, three], "standard": […], "hard": […]}.
## Each list holds the minimum score for 1, 2 and 3 stars.
var star_thresholds := {}
## When true, the thresholds are points per minute of gameplay, so the same stars fit a 90 s
## circuit slot and a 30-minute Just Ride.
var stars_per_minute := false
## Star thresholds for a game's variants, by variant: {"catch": {"easy": […], …}}. A variant not
## listed uses `star_thresholds`.
var variant_star_thresholds := {}
## The game's own options, shown in the shared pause screen's "Game options" card and
## remembered per rider (`GameOptions`). Each is
## {key, label, choices: [values], labels: [shown text], default}. Values are strings.
var options: Array[Dictionary] = []


## Problems with the declaration, empty when it's valid. The registry test runs this for
## every registered game.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("id is empty")
	if title.is_empty():
		problems.append("title is empty")
	if how_to.is_empty():
		problems.append("how_to is empty")
	if supports.is_empty():
		problems.append("supports is empty")
	for mode in supports:
		if mode not in SUPPORTS:
			problems.append("unknown supports mode '%s'" % mode)
	if "minutes" in supports and not (0 < min_sec and min_sec <= max_sec):
		problems.append("min_sec/max_sec out of order")
	if "rounds" in supports and not (0 < min_rounds and min_rounds <= max_rounds):
		problems.append("min_rounds/max_rounds out of order")
	for role in roles:
		if role not in ROLES:
			problems.append("unknown role '%s'" % role)
	if tracker_mode not in TRACKER_MODES:
		problems.append("unknown tracker_mode '%s'" % tracker_mode)
	var tables := {"star_thresholds": star_thresholds}
	for v in variant_star_thresholds:
		tables["variant_star_thresholds.%s" % v] = variant_star_thresholds[v]
	for table_name in tables:
		var table: Dictionary = tables[table_name]
		for difficulty in DIFFICULTIES:
			var t = table.get(difficulty)
			if not (t is Array) or t.size() != 3:
				problems.append("%s.%s needs three scores" % [table_name, difficulty])
			elif not (float(t[0]) > 0.0 and float(t[0]) <= float(t[1]) and float(t[1]) <= float(t[2])):
				problems.append("%s.%s must be positive and rising" % [table_name, difficulty])
	for option in options:
		var choices: Array = option.get("choices", [])
		var labels: Array = option.get("labels", choices)
		if str(option.get("key", "")).is_empty() or str(option.get("label", "")).is_empty():
			problems.append("an option needs a key and a label")
		elif choices.size() < 2 or labels.size() != choices.size():
			problems.append("option '%s' needs two or more choices, each with a label" % option.key)
		elif not choices.has(option.get("default")):
			problems.append("option '%s' default isn't one of its choices" % option.key)
	return problems


## The star thresholds for `variant` (its own, or the game's).
func thresholds_for(variant: String) -> Dictionary:
	return variant_star_thresholds.get(variant, star_thresholds)


## The option declared as `key`, or {}.
func option_spec(key: String) -> Dictionary:
	for option in options:
		if option.get("key") == key:
			return option
	return {}


## Whether this game uses the camera.
func uses_camera() -> bool:
	return tracker_mode != "off"


## The calibration mode for request_calibration: "lean_2d" for the depth axis, else "lean_x".
func calibration_mode() -> String:
	return "lean_2d" if tracker_mode == "lean_2d" else "lean_x"
