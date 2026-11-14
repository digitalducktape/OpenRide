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
## While the head tracker calibrates (InputBus.tracker_state is TRACKER_CALIBRATING).
## step: "centre", "left", "right", "in" or "back"; fraction: 0..1 through it (restarts on a retry);
## step_index / step_count: 0-based position in this calibration (1 step when only the centre is
## re-taken, 3 for lean_x, 5 for lean_2d); attempt: 1, then 2+ on retries; retry_reason: "" on a
## first attempt, else "unstable", "no_face", "too_small" or "wrong_direction"; "used_default" when
## the step failed 3 times and calibration moves on with the previous or default value.
signal calibration_progress(step: String, fraction: float, step_index: int, step_count: int, attempt: int, retry_reason: String)
signal session_finished(summary: Dictionary)
## Bridge v1.1, the Games hub (docs/GAMES.md "Games hub (v1.1)"). A full snapshot every time,
## never a delta; also kept in `hub`.
signal hub_state_changed(state: Dictionary)
## {request, reason}: sent instead of session_started when a start_plan can't be played.
signal plan_rejected(reason: Dictionary)
## {visit_id, ride_id, saved, discarded_reason, next, reason}: the visit's ride is saved or
## discarded. Call nothing after it, except hub_activity() when `next` is "hub" (the idle guard
## saved the ride and the rider taps to keep playing: Kotlin starts a new visit).
signal visit_ended(result: Dictionary)
## The visit id changed (a new visit): visit-scoped state (calibration, results) resets.
signal visit_changed(visit_id: String)
## v1.3: the rider's music app's track, for the hub's music card: {title, artist, art (a PNG
## path or ""), playing, can_previous, can_next}, or {} with nothing. Also kept in `now_playing`.
signal now_playing_changed(track: Dictionary)

const BRIDGE := "OpenRideBridge"
const LocalSession := preload("res://autoload/LocalSession.gd")

var plan: Dictionary = {}  ## the last session_started payload
var segment: Dictionary = {}  ## the current segment_started payload
var summary: Dictionary = {}  ## the session_finished payload, once the session is over
var active := false  ## between session_started and session_finished
var paused := false
var tracker_mode := "off"  ## the last set_tracker_mode
## The last calibration_progress this session, as {step, fraction, step_index, step_count,
## attempt, retry_reason, at_msec}; empty before the first.
var calibration: Dictionary = {}
var director: SessionDirector
## The last hub_state snapshot; empty outside a hub visit (and before the first).
var hub: Dictionary = {}
## The current hub visit's id, from hub_state or a visit's session_started; "" outside a visit.
var visit_id := ""
## The last now_playing ({} with nothing playing).
var now_playing: Dictionary = {}

var _bridge: Object = null
var _local: Node = null


func _ready() -> void:
	LoadClock.mark("boot", "session_ready_begin")
	process_mode = Node.PROCESS_MODE_ALWAYS
	director = SessionDirector.new()
	add_child(director)
	LoadClock.mark("boot", "session_director")
	if Engine.has_singleton(BRIDGE):
		_bridge = Engine.get_singleton(BRIDGE)
		_bridge.connect("session_started", func(json: String): _on_session_started(_parse(json)))
		_bridge.connect("segment_started", func(json: String): _on_segment_started(_parse(json)))
		_bridge.connect("segment_ending", _on_segment_ending)
		_bridge.connect("session_paused", _on_session_paused)
		_bridge.connect("session_resumed", _on_session_resumed)
		_bridge.connect("calibration_progress", _on_calibration_progress)
		_bridge.connect("session_finished", func(json: String): _on_session_finished(_parse(json)))
		# v1.1: guarded, so a pack run against an older app build still starts.
		if _bridge.has_signal("hub_state"):
			_bridge.connect("hub_state", func(json: String): _on_hub_state(_parse(json)))
			_bridge.connect("plan_rejected", func(json: String): _on_plan_rejected(_parse(json)))
			_bridge.connect("visit_ended", func(json: String): _on_visit_ended(_parse(json)))
		if _bridge.has_signal("now_playing"):
			_bridge.connect("now_playing", func(json: String): _on_now_playing(_parse(json)))
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
var loading := false  ## the native loading screen is up (show_loading)


func set_tracker_mode(mode: String) -> void:
	print("OPENRIDE_GAMES -> set_tracker_mode %s" % mode)
	tracker_mode = mode
	if _bridge:
		_bridge.set_tracker_mode(mode)
	else:
		_local.set_tracker_mode(mode)


## Covers the screen with the host's native loading screen while a game starts (bridge v1.2):
## it keeps animating while the first 3D frame compiles shaders. Desktop: nothing to cover.
func show_loading(show: bool) -> void:
	loading = show
	if _bridge and _bridge.has_method("show_loading"):
		_bridge.show_loading(show)


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
		_local.request_exit()


# --- Godot → Kotlin, the Games hub (v1.1) ---

## Starts a plan from the hub (valid only there): {kind: "just_ride", game_id, mode: "minutes" |
## "rounds" | "open", length, difficulty}, {kind: "circuit", preset_id, difficulty} or
## {kind: "custom", difficulty, slots: [{game_id, duration_sec}]}. Kotlin answers with
## session_started, or plan_rejected.
func start_plan(request: Dictionary) -> void:
	print("OPENRIDE_GAMES -> start_plan %s" % JSON.stringify(request))
	if _bridge:
		_bridge.start_plan(JSON.stringify(request))
	else:
		_local.start_plan(request)


## key: "camera_games" (bool), "game_music" (bool), "music_volume" or "sfx_volume" (0..1),
## "lean_sensitivity" ("low" | "normal" | "high"). Kotlin stores it and sends hub_state.
func update_setting(key: String, value: Variant) -> void:
	print("OPENRIDE_GAMES -> update_setting %s %s" % [key, JSON.stringify(value)])
	if _bridge:
		_bridge.update_setting(key, JSON.stringify(value))
	else:
		_local.update_setting(key, value)


## Calibrates from the hub. full: false takes the centre only when the rider's extremes are
## from today; true runs every step (Recalibrate). Progress comes as calibration_progress.
func hub_calibrate(mode: String, full: bool) -> void:
	print("OPENRIDE_GAMES -> hub_calibrate %s full=%s" % [mode, full])
	if _bridge:
		_bridge.hub_calibrate(mode, full)
	else:
		_local.hub_calibrate(mode, full)


func cancel_calibration() -> void:
	print("OPENRIDE_GAMES -> cancel_calibration")
	if _bridge:
		_bridge.cancel_calibration()
	else:
		_local.cancel_calibration()


func request_camera_permission() -> void:
	print("OPENRIDE_GAMES -> request_camera_permission")
	if _bridge:
		_bridge.request_camera_permission()
	else:
		_local.request_camera_permission()


## Ends the visit: next is "app" or "edit_profile". Kotlin saves the ride, then sends visit_ended.
func exit_hub(next: String) -> void:
	print("OPENRIDE_GAMES -> exit_hub %s" % next)
	if _bridge:
		_bridge.exit_hub(next)
	else:
		_local.exit_hub(next)


## The hub's music card: "play_pause", "next" or "previous", for the rider's music app.
func music_control(action: String) -> void:
	print("OPENRIDE_GAMES -> music_control %s" % action)
	if _bridge:
		# Called straight, with no has_method() guard: the app and this pack ship together, and
		# the guarded call never reached the music app on the bike (2026-10-27).
		_bridge.music_control(action)
	else:
		_local.music_control(action)


## The rider touched the hub. Send it at most once every 60 s: it resets Kotlin's idle guard.
func hub_activity() -> void:
	if _bridge:
		_bridge.hub_activity()
	else:
		_local.hub_activity()


## The simulator's segment_time_left, for InputBus.
func local_time_left() -> float:
	return _local.time_left() if _local else -1.0


## The simulator's tracker_state, for InputBus.
func local_tracker_state() -> int:
	return _local.tracker_state() if _local else InputBus.TRACKER_OFF


## Whether the head tracker is calibrating right now: Kotlin pauses the session meanwhile.
func is_calibrating() -> bool:
	if _local:
		return _local.is_calibrating()
	return InputBus.tracker_state == InputBus.TRACKER_CALIBRATING


## The active rider's profile name from `session_started`'s optional `rider_name`, trimmed;
## "" when there's no active rider, or the payload predates the key.
func rider_name() -> String:
	var n = plan.get("rider_name")
	return "" if n == null else str(n).strip_edges()


## The current segment's gameplay seconds, pauses excluded (the HUD's count-up clock).
func played_sec() -> float:
	return director.played_sec() if director else 0.0


# --- Kotlin → Godot (from the bridge, or LocalSession on a desktop) ---

func _on_session_started(new_plan: Dictionary) -> void:
	print("OPENRIDE_GAMES <- session_started %s" % JSON.stringify(new_plan))
	# A fresh session: the engine outlives the host activity, so state from the last one lingers.
	plan = new_plan
	if new_plan.get("visit_id") is String:
		_set_visit_id(new_plan.visit_id)
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


func _on_calibration_progress(step: String, fraction: float, step_index: int, step_count: int, attempt: int, retry_reason: String) -> void:
	# Progress arrives many times a second: log a step's start, its retries and its end.
	var starting: bool = calibration.is_empty() or calibration.step != step or calibration.attempt != attempt
	if starting or (fraction >= 1.0 and calibration.fraction < 1.0):
		print("OPENRIDE_GAMES <- calibration_progress %s %d/%d attempt %d %s fraction %.2f" % [
			step, step_index + 1, step_count, attempt, retry_reason, fraction])
	calibration = {
		"step": step,
		"fraction": fraction,
		"step_index": step_index,
		"step_count": step_count,
		"attempt": attempt,
		"retry_reason": retry_reason,
		"at_msec": Time.get_ticks_msec(),
	}
	calibration_progress.emit(step, fraction, step_index, step_count, attempt, retry_reason)


func _on_session_finished(new_summary: Dictionary) -> void:
	print("OPENRIDE_GAMES <- session_finished %s" % JSON.stringify(new_summary))
	summary = new_summary
	active = false
	paused = false
	session_finished.emit(summary)


func _on_now_playing(track: Dictionary) -> void:
	now_playing = track
	now_playing_changed.emit(track)


func _on_hub_state(state: Dictionary) -> void:
	print("OPENRIDE_GAMES <- hub_state %s %s" % [state.get("visit_id", ""), state.get("phase", "")])
	hub = state
	if state.get("visit_id") is String:
		_set_visit_id(state.visit_id)
	hub_state_changed.emit(hub)


func _on_plan_rejected(reason: Dictionary) -> void:
	print("OPENRIDE_GAMES <- plan_rejected %s" % JSON.stringify(reason))
	plan_rejected.emit(reason)


func _on_visit_ended(result: Dictionary) -> void:
	print("OPENRIDE_GAMES <- visit_ended %s" % JSON.stringify(result))
	visit_ended.emit(result)


func _set_visit_id(id: String) -> void:
	if id == visit_id:
		return
	visit_id = id
	visit_changed.emit(id)


# --- Input ---

func _notification(what: int) -> void:
	# Android back: pause a running session (the pause screen offers "end"); in the hub, the
	# hub steps back a screen (on its home it asks to exit); on a visit's result card, back to
	# the hub; after a v1 summary, leave. Never quit (see project.godot's quit_on_go_back).
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		back()


## What Android back does now (also for tests and the desktop's Esc in the hub).
func back() -> void:
	if active:
		if not paused:
			request_pause()
	elif director.phase == SessionDirector.Phase.HUB:
		var scene := get_tree().current_scene
		if scene and scene.has_method("back"):
			scene.back()
	elif director.summary_screen.visible:
		director._on_summary_done()
	elif not summary.is_empty():
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
			if active:
				request_end()
			else:
				back()  # the hub and the result card: as Android back
			get_viewport().set_input_as_handled()


func _parse(json: String) -> Dictionary:
	var value = JSON.parse_string(json)
	if value is Dictionary:
		return value
	push_error("Session: unreadable bridge payload: %s" % json)
	return {}
