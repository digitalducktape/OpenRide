class_name Game
extends Node2D
## Base class of every game scene (docs/GAMES.md, "Adding a game").
##
## `Session` drives it through a segment:
##   prepare(segment)   the scene is loaded and the intro card shows (`_on_prepare`)
##   start(segment)     gameplay begins (`_on_start`), then `_on_frame(delta)` every frame
##   set_paused(bool)   pause and resume (`_on_pause`, `_on_resume`); frames stop meanwhile
##   request_finish()   the timer ran out: wrap up within 5 s (`_on_finish_requested`)
##   finish() -> result the contract's segment result, stars included
##
## A game overrides `info()` and the `_on_*` hooks it needs, reads its inputs from `InputBus`,
## and scores only through `award(points)` (= `Effort.award`). It never talks to the bridge,
## never calls `get_tree().quit()`, and never overrides `_process`. Keep the rules in a plain
## class that can be tested headless, and use the scene only to draw it.

## The game has finished its segment: it won the race, or it wrapped up after
## `request_finish`. Session then reports `finish()`.
signal ended

var segment: Dictionary = {}  ## the segment_started payload
var params: Dictionary = {}  ## the segment's game-specific params, already FTP-scaled
var difficulty := "standard"
var rng := RandomNumberGenerator.new()  ## seeded from the segment's `seed`
var hud: Hud  ## set by Session before prepare()
var playing := false  ## between start() and the end of the segment
var paused := false
var finishing := false  ## after request_finish()
var played_sec := 0.0  ## gameplay seconds, pauses excluded
## The result's `won` (true / false) for games with a winner; null otherwise.
var won = null
## Extra `stats` for the result; `effort_avg` and `played_sec` are added for you.
var stats := {}
## The game's variant for the result (e.g. Dodge Ball's "catch" mode), or "". Bests,
## leaderboards and stars are kept per variant.
var variant := ""

## The registry key, from `info()`.
var game_id: String:
	get:
		return declared().id

var _declared: GameInfo
var _prepared := false
var _ended := false


# --- Declarations: override ---

## What this game is and supports. Every game must override it.
func info() -> GameInfo:
	push_error("Game %s does not override info()" % get_script().resource_path)
	return GameInfo.new()


## The intro card's how-to line; `info().how_to` unless the game says more (e.g. a mode).
func how_to_text(_segment: Dictionary) -> String:
	return declared().how_to


## A small picture or animation for the intro card (a Control, freed with the card's next
## segment), or null. Called after `_on_prepare`.
func intro_visual() -> Control:
	return null


## The intro card's target line, e.g. "Hold 250 W" or "Keep cadence above 70 rpm".
func target_text(_segment: Dictionary) -> String:
	return ""


## The camera mode for this segment: `info().tracker_mode` unless the game decides per segment
## (Tug of War runs the camera only when the rider turned brace lean on). Called before
## `_on_prepare`, once the rider's options can be read.
func tracker_mode_for_segment(_segment: Dictionary) -> String:
	return declared().tracker_mode


# --- Hooks: override the ones you need ---

## The scene is loaded and the intro card is showing: build the level, add HUD widgets, ask
## AudioDirector for music. `segment`, `params`, `difficulty` and `rng` are set.
func _on_prepare(_segment: Dictionary) -> void:
	pass


## Gameplay begins.
func _on_start() -> void:
	pass


## Every gameplay frame while not paused. Read InputBus; award points with `award()`.
func _on_frame(_delta: float) -> void:
	pass


func _on_pause() -> void:
	pass


func _on_resume() -> void:
	pass


## The rider changed one of the game's options (`GameInfo.options`) on the pause screen.
## The new value is already stored; `option(key)` returns it.
func _on_option_changed(_key: String, _value: String) -> void:
	pass


## The segment's timer ran out (or the rider ended the session). Wrap up and call
## `end_segment()` within 5 s; by default the game ends at once. After 4.5 s Session ends it
## anyway.
func _on_finish_requested() -> void:
	end_segment()


# --- For the game ---

## Scores `points` × the effort multiplier. Returns what counted: 0 while scoring is frozen
## (intro card, pause, sensor loss, after the end).
func award(points: float) -> float:
	return Effort.award(points) if playing else 0.0


## Takes `points` off the score, without the multiplier (= `Effort.penalize`). Returns what
## was taken.
func penalize(points: float) -> float:
	return Effort.penalize(points) if playing else 0.0


## Ends the segment. In `end_mode: game` the game calls this when it's done (a race's finish
## line); otherwise only after `request_finish`. A game in a timed slot that finishes early
## starts another round instead (epic #31, "Short games fill their slot").
func end_segment() -> void:
	if _ended:
		return
	var timed := str(segment.get("end_mode", "timer")) == "timer" and float(segment.get("duration_sec", -1)) >= 0
	if timed and not finishing:
		push_warning("%s: end_segment() in a timed segment before its timer ran out; keep playing" % game_id)
		return
	_ended = true
	playing = false
	ended.emit()


## The rider's choice for one of this game's options (`GameInfo.options`), or its default.
func option(key: String) -> String:
	return GameOptions.get_value(declared(), key)


## The score so far, multiplier included.
func score() -> float:
	return Effort.score


## `info()`, cached.
func declared() -> GameInfo:
	if _declared == null:
		_declared = info()
	return _declared


# --- Called by Session ---

func was_prepared() -> bool:
	return _prepared


func has_ended() -> bool:
	return _ended


func prepare(new_segment: Dictionary) -> void:
	_prepared = true
	_ended = false
	segment = new_segment
	params = segment.get("params", {})
	difficulty = str(segment.get("difficulty", "standard"))
	rng.seed = int(segment.get("seed", 0))
	playing = false
	finishing = false
	played_sec = 0.0
	won = null
	stats = {}
	variant = ""
	set_paused(false)
	_on_prepare(segment)


func start(_segment: Dictionary = segment) -> void:
	playing = true
	_on_start()


func set_paused(value: bool) -> void:
	if value == paused:
		return
	paused = value
	# Freezes this scene's nodes (tweens, particles, timers) along with _on_frame.
	process_mode = Node.PROCESS_MODE_DISABLED if paused else Node.PROCESS_MODE_INHERIT
	if paused:
		_on_pause()
	else:
		_on_resume()


## Stores an option the rider changed and tells the game (the pause screen calls this).
func change_option(key: String, value: String) -> void:
	if GameOptions.set_value(declared(), key, value):
		_on_option_changed(key, value)


func request_finish() -> void:
	if _ended:
		return
	finishing = true
	_on_finish_requested()


## The contract's segment result: {game_id, score, stars, won, skipped, stats: {effort_avg, …},
## variant}.
func finish() -> Dictionary:
	playing = false
	_ended = true
	var total := score()
	var result_stats := stats.duplicate()
	result_stats["effort_avg"] = snappedf(Effort.average(), 0.01)
	result_stats["played_sec"] = roundi(played_sec)
	return {
		"game_id": game_id,
		"score": roundi(total),
		"stars": Stars.for_score(total, declared(), difficulty, played_sec, variant),
		"won": won,
		"skipped": false,
		"stats": result_stats,
		"variant": variant,
	}


func _process(delta: float) -> void:
	if playing and not paused:
		played_sec += delta
		_on_frame(delta)
