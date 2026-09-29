extends Node
## The game session as Godot sees it (Bridge contract v1, docs/GAMES.md).
##
## Kotlin owns the session clock and the ride. This autoload re-emits the bridge's signals with
## their JSON already parsed, and forwards the game's calls. Games use only this and InputBus.
##
## When the `OpenRideBridge` singleton is absent (the editor on a desktop), a LocalSession plays
## a local plan instead: a Just Ride of the open game by default. P pauses/resumes, Esc ends the
## session; `request_exit()` starts it again.
##
## Its `SessionDirector` child runs the session on screen: it loads each segment's game from
## `GameRegistry`, shows the intro card, HUD, pause, calibration and summary, and reports the
## game's result (docs/GAMES.md, "The framework").

signal session_started(plan: Dictionary)
signal segment_started(segment: Dictionary)
signal segment_ending
signal session_paused
signal session_resumed
signal calibration_progress(step: String, fraction: float)
signal session_finished(summary: Dictionary)

const BRIDGE := "OpenRideBridge"
const LocalSession := preload("res://autoload/LocalSession.gd")

var plan: Dictionary = {}  ## the last session_started payload
var segment: Dictionary = {}  ## the current segment_started payload
var summary: Dictionary = {}  ## the session_finished payload, once the session is over
var active := false  ## between session_started and session_finished
var paused := false
var tracker_mode := "off"  ## the last set_tracker_mode
## The last calibration_progress: {step, fraction}, plus step_index, step_count, attempt and
## retry_reason when the tracker sends them (proposed in #33; any may be absent).
var calibration: Dictionary = {}
var director: SessionDirector

var _bridge: Object = null
var _local: Node = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	director = SessionDirector.new()
	add_child(director)
	if Engine.has_singleton(BRIDGE):
		_bridge = Engine.get_singleton(BRIDGE)
		_bridge.connect("session_started", func(json: String): _on_session_started(_parse(json)))
		_bridge.connect("segment_started", func(json: String): _on_segment_started(_parse(json)))
		_bridge.connect("segment_ending", _on_segment_ending)
		_bridge.connect("session_paused", _on_session_paused)
		_bridge.connect("session_resumed", _on_session_resumed)
		_bridge.connect("calibration_progress", _on_calibration_progress)
		_bridge.connect("session_finished", func(json: String): _on_session_finished(_parse(json)))
	else:
		_local = LocalSession.new(self)
		add_child(_local)
		# Deferred, so every scene's _ready has connected its handlers first.
		_local.autostart.call_deferred()


func is_simulated() -> bool:
	return _bridge == null


# --- Godot → Kotlin ---

## Reports the segment's result: {game_id, score, stars (0-3), won (bool|null), skipped (bool),
## stats: {effort_avg, …}}. Call it once per segment, when the game ends it or after
## segment_ending (within 5 s).
func segment_finished(result: Dictionary) -> void:
	print("OPENRIDE_GAMES -> segment_finished %s" % JSON.stringify(result))
	if _bridge:
		_bridge.segment_finished(JSON.stringify(result))
	else:
		_local.segment_finished(result)


## mode: "lean_x" or "lean_2d".
func request_calibration(mode: String) -> void:
	print("OPENRIDE_GAMES -> request_calibration %s" % mode)
	if _bridge:
		_bridge.request_calibration(mode)
	else:
		_local.request_calibration(mode)


## mode: "off", "lean_x", "lean_2d" or "lean_stand". The camera only runs when not "off".
func set_tracker_mode(mode: String) -> void:
	print("OPENRIDE_GAMES -> set_tracker_mode %s" % mode)
	tracker_mode = mode
	if _bridge:
		_bridge.set_tracker_mode(mode)
	else:
		_local.set_tracker_mode(mode)


func request_pause() -> void:
	print("OPENRIDE_GAMES -> request_pause")
	if _bridge:
		_bridge.request_pause()
	else:
		_local.request_pause()


func request_resume() -> void:
	print("OPENRIDE_GAMES -> request_resume")
	if _bridge:
		_bridge.request_resume()
	else:
		_local.request_resume()


## The rider ends the session. Kotlin saves the ride, then sends session_finished.
func request_end() -> void:
	print("OPENRIDE_GAMES -> request_end")
	if _bridge:
		_bridge.request_end()
	else:
		_local.request_end()


## After the summary: the host finishes back to the app. Never call get_tree().quit().
func request_exit() -> void:
	print("OPENRIDE_GAMES -> request_exit")
	if _bridge:
		_bridge.request_exit()
	else:
		_local.start()


## The simulator's segment_time_left, for InputBus.
func local_time_left() -> float:
	return _local.time_left() if _local else -1.0


## The simulator's tracker_state, for InputBus.
func local_tracker_state() -> int:
	return _local.tracker_state() if _local else InputBus.TRACKER_OFF


## The current segment's gameplay seconds, pauses excluded (the HUD's count-up clock).
func played_sec() -> float:
	return director.played_sec() if director else 0.0


# --- Kotlin → Godot (from the bridge, or LocalSession on a desktop) ---

func _on_session_started(new_plan: Dictionary) -> void:
	print("OPENRIDE_GAMES <- session_started %s" % JSON.stringify(new_plan))
	# A fresh session: the engine outlives the host activity, so state from the last one lingers.
	plan = new_plan
	segment = {}
	summary = {}
	calibration = {}
	active = true
	paused = false
	session_started.emit(plan)


func _on_segment_started(new_segment: Dictionary) -> void:
	print("OPENRIDE_GAMES <- segment_started %s" % JSON.stringify(new_segment))
	segment = new_segment
	segment_started.emit(segment)


func _on_segment_ending() -> void:
	print("OPENRIDE_GAMES <- segment_ending")
	segment_ending.emit()


func _on_session_paused() -> void:
	print("OPENRIDE_GAMES <- session_paused")
	paused = true
	session_paused.emit()


func _on_session_resumed() -> void:
	print("OPENRIDE_GAMES <- session_resumed")
	paused = false
	session_resumed.emit()


func _on_calibration_progress(step: String, fraction: float, extra: Dictionary = {}) -> void:
	calibration = extra.duplicate()
	calibration["step"] = step
	calibration["fraction"] = fraction
	calibration["at_msec"] = Time.get_ticks_msec()
	calibration_progress.emit(step, fraction)


func _on_session_finished(new_summary: Dictionary) -> void:
	print("OPENRIDE_GAMES <- session_finished %s" % JSON.stringify(new_summary))
	summary = new_summary
	active = false
	paused = false
	session_finished.emit(summary)


# --- Input ---

func _notification(what: int) -> void:
	# Android back: pause a running session (the pause screen offers "end"); leave after the
	# summary. Never quit (see project.godot's quit_on_go_back).
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if active and not paused:
			request_pause()
		elif not active and not summary.is_empty():
			request_exit()


func _input(event: InputEvent) -> void:
	if _bridge or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_P:
			if paused:
				request_resume()
			else:
				request_pause()
			get_viewport().set_input_as_handled()
		KEY_ESCAPE:
			request_end()
			get_viewport().set_input_as_handled()


func _parse(json: String) -> Dictionary:
	var value = JSON.parse_string(json)
	if value is Dictionary:
		return value
	push_error("Session: unreadable bridge payload: %s" % json)
	return {}
