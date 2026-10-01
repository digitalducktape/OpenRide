class_name GameOptions
extends RefCounted
## Each game's own options (`GameInfo.options`), remembered per rider (docs/GAMES.md,
## "Game options"). The shared pause screen shows and changes them; a game reads them with
## `Game.option(key)` and hears changes through `Game._on_option_changed(key, value)`.
##
## Stored in `user://game_options.cfg`, one section per rider and game: `<rider>/<game_id>`.
## The rider is `session_started`'s `rider_id`, or "guest" when no rider is active.

const DEFAULT_PATH := "user://game_options.cfg"

## Tests point this elsewhere.
static var path := DEFAULT_PATH

static var _file: ConfigFile
static var _loaded_path := ""


## The rider the current session belongs to.
static func rider() -> String:
	var id = Session.plan.get("rider_id")
	return "guest" if id == null else str(id).trim_suffix(".0")


## `key`'s value for this rider and game: the stored choice, else the declared default.
static func get_value(info: GameInfo, key: String, rider_id := rider()) -> String:
	var spec := info.option_spec(key)
	if spec.is_empty():
		push_warning("GameOptions: %s declares no option '%s'" % [info.id, key])
		return ""
	var stored := str(_config().get_value(_section(info.id, rider_id), key, spec.default))
	return stored if (spec.choices as Array).has(stored) else str(spec.default)


## Stores `value` for this rider and game. Unknown keys and values are ignored.
static func set_value(info: GameInfo, key: String, value: String, rider_id := rider()) -> bool:
	var spec := info.option_spec(key)
	if spec.is_empty() or not (spec.choices as Array).has(value):
		return false
	var config := _config()
	config.set_value(_section(info.id, rider_id), key, value)
	var err := config.save(path)
	if err != OK:
		push_warning("GameOptions: can't save %s (%d)" % [path, err])
	return true


## The choice after `value` in the option's list, wrapping round (the pause screen's buttons).
static func next_choice(spec: Dictionary, value: String) -> String:
	var choices: Array = spec.get("choices", [])
	if choices.is_empty():
		return value
	return str(choices[(choices.find(value) + 1) % choices.size()])


## The shown text for `value`.
static func label_for(spec: Dictionary, value: String) -> String:
	var choices: Array = spec.get("choices", [])
	var labels: Array = spec.get("labels", choices)
	var i := choices.find(value)
	return str(labels[i]) if i >= 0 and i < labels.size() else value


## Forgets the cached file (tests, or after `path` changes).
static func reload() -> void:
	_file = null


static func _section(game_id: String, rider_id: String) -> String:
	return "%s/%s" % [rider_id, game_id]


static func _config() -> ConfigFile:
	if _file == null or _loaded_path != path:
		_file = ConfigFile.new()
		_loaded_path = path
		if FileAccess.file_exists(path):
			_file.load(path)
	return _file
