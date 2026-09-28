extends SceneTree
## Headless check of the desktop keyboard simulator (docs/GAMES.md, "Running on a desktop"):
##   $GODOT_BIN --headless --path games -s res://tests/sim_keyboard_check.gd
## Injects key events and checks the synthesised input frame and session keys.

var _failures: Array[String] = []
var _input_bus: Node
var _session: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_input_bus = root.get_node("InputBus")
	_session = root.get_node("Session")
	await _frames(3)
	_check(_input_bus.is_simulated(), "no bridge on a desktop: simulator active")
	_check(_input_bus.sensors_ok, "simulated sensors are ok")
	var cadence: float = _input_bus.cadence
	var resistance: float = _input_bus.resistance

	# Lean eases back towards centre once the key is released, hence "nearly" full lock.
	await _hold(KEY_RIGHT, 0.5)
	_check(_input_bus.lean_x > 0.9, "Right leans to +1 (got %s)" % _input_bus.lean_x)
	await _hold(KEY_LEFT, 0.8)
	_check(_input_bus.lean_x < -0.9, "Left leans to -1 (got %s)" % _input_bus.lean_x)
	await _hold(KEY_W, 0.5)
	_check(_input_bus.lean_depth > 0.9, "W leans in (got %s)" % _input_bus.lean_depth)
	await _hold(KEY_EQUAL, 0.5)
	_check(_input_bus.cadence > cadence + 10, "+ raises cadence (%s -> %s)" % [cadence, _input_bus.cadence])
	await _hold(KEY_MINUS, 1.0)
	_check(_input_bus.cadence < cadence, "- lowers cadence (got %s)" % _input_bus.cadence)
	await _hold(KEY_BRACKETRIGHT, 0.5)
	_check(_input_bus.resistance > resistance + 5, "] raises resistance (%s -> %s)" % [resistance, _input_bus.resistance])
	_check(_input_bus.power > 0, "power follows cadence and resistance (got %s)" % _input_bus.power)

	await _tap(KEY_SPACE)
	_check(_input_bus.standing, "Space stands")
	await _tap(KEY_SPACE)
	_check(not _input_bus.standing, "Space again sits")

	await _tap(KEY_P)
	_check(_session.paused, "P pauses")
	await _tap(KEY_P)
	_check(not _session.paused, "P resumes")
	# Esc asks the game to finish its segment; with no game scene loaded here, the session ends
	# after the 5 s grace, as the app would.
	await _tap(KEY_ESCAPE)
	_check(_session.active, "Esc waits for the game's result")
	await create_timer(5.5).timeout
	_check(not _session.active and not _session.summary.is_empty(), "Esc ends the session")

	if _failures.is_empty():
		print("PASS sim keyboard")
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


func _hold(keycode: Key, seconds: float) -> void:
	_key(keycode, true)
	await create_timer(seconds).timeout
	_key(keycode, false)
	await _frames(2)


func _tap(keycode: Key) -> void:
	_key(keycode, true)
	await _frames(2)
	_key(keycode, false)
	await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
