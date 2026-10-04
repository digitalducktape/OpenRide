extends SceneTree
## Headless desktop playthrough of the framework with the demo game and the keyboard simulator:
##   $GODOT_BIN --headless --path games -s res://tests/sim_demo_check.gd
## A three-segment local circuit, sped up 4×: the intro card and calibration, a played warm-up
## (weaving with the arrow keys), a skipped work segment (a stray tap on the card does nothing, then "Skip this game"), pause and resume
## with P, Esc to end, then the summary and Done.

const SPEED := 4.0

var _failures: Array[String] = []
var _session: Node
var _director: Node  # untyped: a -s script compiles before the autoloads exist


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_session = root.get_node("Session")
	_director = _session.director
	Engine.time_scale = SPEED
	_session._local.start({"kind": "circuit", "plan_id": "check", "difficulty": "standard", "total_sec": 60,
		"segments": [
			{"game_id": "demo", "role": "warmup", "duration_sec": 20},
			{"game_id": "demo", "role": "work", "duration_sec": 20},
			{"game_id": "demo", "role": "cooldown", "duration_sec": 20},
		]})
	await _frames(3)
	_check(_director.intro_card.visible, "the intro card shows")
	_check(_director.calibration.visible and _director.calibration.mode == "calibrating", "calibration runs for the camera game")
	_check(_director.calibration._prompt.text.contains("centred"), "calibration starts centred (got '%s')" % _director.calibration._prompt.text)
	var progress: Dictionary = _session.calibration
	_check(progress.step == "centre" and progress.step_index == 0 and progress.step_count == 3 and progress.attempt == 1
		and progress.retry_reason == "", "calibration_progress carries all six fields (%s)" % [progress])

	# Warm-up: wait out the card, then weave while pedalling.
	await _until(func(): return _director.phase_name() == "PLAYING", 15.0)
	_check(_director.hud.visible, "the HUD shows in gameplay")
	# The overlay lingers a real second after the last step; the check runs at 4× speed.
	await create_timer(1.2, true, false, true).timeout
	_check(not _director.calibration.visible, "calibration is over by gameplay")
	var time_left: float = root.get_node("InputBus").segment_time_left
	_check(time_left > 0.0, "the timer counts down (%s)" % time_left)
	var results: Array = _session._local._results
	var key := KEY_LEFT
	var deadline := Time.get_ticks_msec() + 30000
	while results.is_empty() and _session.active and Time.get_ticks_msec() < deadline:
		_key(key, true)
		await create_timer(0.35 * SPEED).timeout
		_key(key, false)
		key = KEY_RIGHT if key == KEY_LEFT else KEY_LEFT
	_check(results.size() == 1 and int(results[0].score) > 0, "the warm-up scored (%s)" % [results])
	_check(_session.calibration.step == "right" and _session.calibration.fraction == 1.0, "calibration ran to the last step")
	_check(results[0].stats.get("dodged", 0) > 0, "balls were dodged")
	_check(results[0].stats.effort_avg == 1.0, "no effort multiplier in a warm-up")

	# Work: a stray tap on the card does nothing; its Skip button skips it.
	await _frames(2)
	_check(int(_session.segment.index) == 1 and _director.phase_name() == "INTRO", "on to the work segment's card")
	await _click(Vector2(960, 300))
	await _frames(3)
	_check(results.size() == 1 and _director.phase_name() == "INTRO", "a stray tap on the card did nothing")
	await _click(_director.intro_card.skip_button.get_global_rect().get_center())
	await _frames(3)
	_check(results.size() == 2 and results[1].skipped, "Skip this game skipped the work segment (%s)" % [results])
	_check(_session._local.calibrations_started == 1, "one calibration for the whole circuit (%d)" % _session._local.calibrations_started)

	# Cool-down: pause and resume, then end with Esc.
	await _until(func(): return _director.phase_name() == "PLAYING", 15.0)
	await _tap(KEY_P)
	_check(_session.paused and _director.pause_overlay.visible and _director.game.paused, "P pauses")
	await _tap(KEY_P)
	_check(not _session.paused and not _director.pause_overlay.visible, "P resumes")
	await _tap(KEY_ESCAPE)
	_check(not _session.active, "Esc ends the session")
	_check(_director.summary_screen.visible, "the summary shows")
	_check(_session.summary.results.size() == 3, "the summary has the three segments (%s)" % [_session.summary.results])
	_check(_director.summary_screen._rows.get_child_count() >= 3, "the summary lists them")

	# Done: on a desktop, request_exit plays the default plan again.
	_click(_director.summary_screen.done_button.get_global_rect().get_center())
	await _frames(3)
	_check(_session.active and not _director.summary_screen.visible, "Done exits (a desktop starts again)")

	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("PASS sim demo")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL ", f)
		quit(1)


func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(2)
	_key(keycode, false)
	await _frames(2)


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)  # canvas (1920x1080) coordinates
		await process_frame


func _until(condition: Callable, timeout_sec: float) -> void:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < timeout_sec * 1000.0:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
