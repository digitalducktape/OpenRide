class_name GameInfo
extends RefCounted
## What a game declares about itself (docs/GAMES.md, "Adding a game"). `Game.info()` returns
## one; `GameRegistry` caches it per game_id, and `Session` reads it before a segment starts.

const SUPPORTS := ["rounds", "minutes", "open"]
const ROLES := ["warmup", "work", "recovery", "cooldown"]
const TRACKER_MODES := ["off", "lean_x", "lean_2d", "lean_stand"]
const DIFFICULTIES := ["easy", "standard", "hard"]
## An option's screens (`where`), control (`kind`) and the hub's card grid (spec §7.1).
const OPTION_WHERE := ["hub", "pause", "both"]
const OPTION_KINDS := ["cycle", "segmented", "cards"]
const SEGMENTED_MAX := 4
const COLUMNS_MAX := 6

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
## `end_mode` of a timed ("minutes") Just Ride: "timer" (Kotlin ends it at its length) unless the
## game ends on its own terms, like a race finishing on a lap line ("game"; Kotlin still
## hard-stops at 1.5 × the length). Kotlin's `GameDeclaration.timedEndMode` must match.
var timed_end_mode := "timer"
## The game counts its own start down (Kart Race's grid 3-2-1-GO), so the intro card shows
## "Get ready" instead of a 3-2-1 and plays no countdown cues: one countdown, not two.
var own_countdown := false
## Score → stars, per difficulty: {"easy": [one, two, three], "standard": […], "hard": […]}.
## Each list holds the minimum score for 1, 2 and 3 stars.
var star_thresholds := {}
## When true, the thresholds are points per minute of gameplay, so the same stars fit a 90 s
## circuit slot and a 30-minute Just Ride.
var stars_per_minute := false
## Star thresholds for a game's variants, by variant: {"catch": {"easy": […], …}}. A variant not
## listed uses `star_thresholds`.
var variant_star_thresholds := {}
## The game's own options, shown on the hub's game screen and in the shared pause screen's
## "Game options" card, and remembered per rider (`GameOptions`). Each is
## {key, label, choices: [values], labels: [shown text], default}. Values are strings.
## Optional keys (docs/GAMES.md "Game options"):
##   where    "hub" | "pause" | "both" (default): the screens that show it
##   kind     "cycle" (default: one button that steps) | "segmented" (2-4 short choices side by
##            side) | "cards" (a picture card per choice, hub only; the pause screen cycles)
##   cards    for "cards": [{value, title, subtitle, image (res:// path), accent (Color)}];
##            a choice without one falls back to its label
##   columns  for "cards": the grid's columns (default 4)
##   group    a heading: "" (default) shows on the game screen, anything else folds under
##            the hub's "More options"
##   rider_badge  for "cards": the chosen card wears the rider's name (Kart Race's kart)
var options: Array[Dictionary] = []
## A one-game summary's extra tiles, from the result's `stats`: `[{key, label, suffix, of, grouped}]`
## (`suffix` after the value, e.g. "%"; `grouped` true for 384,400; `of` a second stat shown as
## "value/of", e.g. 3/4). Watt
## Lane shows in-lane %, the longest streak and the steps caught. Empty: points and time only.
var summary_stats: Array[Dictionary] = []


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
	if timed_end_mode not in ["timer", "game"]:
		problems.append("unknown timed_end_mode '%s'" % timed_end_mode)
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
		else:
			problems.append_array(_validate_presentation(option))
	return problems


## The hub keys of one option (spec §7.1).
static func _validate_presentation(option: Dictionary) -> PackedStringArray:
	var problems := PackedStringArray()
	var key := str(option.key)
	var choices: Array = option.choices
	if str(option.get("where", "both")) not in OPTION_WHERE:
		problems.append("option '%s': unknown where '%s'" % [key, option.where])
	var kind := str(option.get("kind", "cycle"))
	if kind not in OPTION_KINDS:
		problems.append("option '%s': unknown kind '%s'" % [key, kind])
	if kind == "segmented" and choices.size() > SEGMENTED_MAX:
		problems.append("option '%s': segmented takes at most %d choices" % [key, SEGMENTED_MAX])
	if not (option.get("group", "") is String):
		problems.append("option '%s': group must be a string" % key)
	if option.has("rider_badge") and not (option.rider_badge is bool):
		problems.append("option '%s': rider_badge must be true or false" % key)
	if kind != "cards":
		for card_key in ["cards", "columns", "rider_badge"]:
			if option.has(card_key):
				problems.append("option '%s': %s is for kind cards" % [key, card_key])
		return problems
	var columns = option.get("columns", 4)
	if not (columns is int) or columns < 1 or columns > COLUMNS_MAX:
		problems.append("option '%s': columns must be 1-%d" % [key, COLUMNS_MAX])
	if not (option.get("cards", []) is Array):
		problems.append("option '%s': cards must be a list" % key)
		return problems
	var seen := {}
	for card in option.get("cards", []):
		if not (card is Dictionary) or not choices.has(card.get("value")):
			problems.append("option '%s': a card's value isn't one of its choices" % key)
			continue
		if seen.has(card.value):
			problems.append("option '%s': two cards for '%s'" % [key, card.value])
		seen[card.value] = true
		var image := str(card.get("image", ""))
		if not image.is_empty() and not ResourceLoader.exists(image):
			problems.append("option '%s': card '%s' image %s is missing" % [key, card.value, image])
		if card.has("accent") and not (card.accent is Color):
			problems.append("option '%s': card '%s' accent must be a Color" % [key, card.value])
	return problems


## An option's screens: "hub", "pause" or "both".
static func option_where(option: Dictionary) -> String:
	return str(option.get("where", "both"))


## An option's control: "cycle", "segmented" or "cards".
static func option_kind(option: Dictionary) -> String:
	return str(option.get("kind", "cycle"))


## The options the hub's game screen shows (where hub or both), in declaration order.
func hub_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(options.filter(func(o): return option_where(o) != "pause"))
	return out


## The options the pause screen shows (where pause or both), in declaration order.
func pause_options() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	out.assign(options.filter(func(o): return option_where(o) != "hub"))
	return out


## The card for `value` of a `cards` option: {value, title, subtitle, image, accent}, the
## declared card filled in from the option's label (no image, no accent) where it's missing.
static func card_for(option: Dictionary, value: String) -> Dictionary:
	var out := {"value": value, "title": GameOptions.label_for(option, value), "subtitle": "", "image": "", "accent": null}
	for card in option.get("cards", []):
		if card is Dictionary and str(card.get("value")) == value:
			for k in ["title", "subtitle", "image", "accent"]:
				if card.has(k):
					out[k] = card[k]
	return out


## The star thresholds for `variant` (its own, or the game's).
func thresholds_for(variant: String) -> Dictionary:
	return variant_star_thresholds.get(variant, star_thresholds)


## The option declared as `key`, or {}.
func option_spec(key: String) -> Dictionary:
	for option in options:
		if option.get("key") == key:
			return option
	return {}


## A copy of these declarations with another camera mode, for a game that picks its camera
## per segment (`Game.tracker_mode_for_segment`).
func with_tracker_mode(mode: String) -> GameInfo:
	var copy := GameInfo.new()
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(prop.name, get(prop.name))
	copy.tracker_mode = mode
	return copy


## Whether this game uses the camera.
func uses_camera() -> bool:
	return tracker_mode != "off"


## The calibration mode for request_calibration: "lean_2d" for the depth axis, else "lean_x".
func calibration_mode() -> String:
	return "lean_2d" if tracker_mode == "lean_2d" else "lean_x"
