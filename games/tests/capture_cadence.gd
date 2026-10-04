extends SceneTree
## Desktop capture of Cadence Karaoke (not headless; needs a window):
##   $GODOT_BIN --path games --write-movie FILE.avi --fixed-fps 30 -s res://tests/capture_cadence.gd -- --play=45 --out=DIR
## A scripted rider follows the target with a little wobble, drifts off it for a while, then asks
## for a faster pace, so the clip shows the band, the streak, the ease-off and a pace change.

var _session: Node
var _director: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://captures"
	var play_sec := 45.0
	var role := "free"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
		elif arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	_session = root.get_node("Session")
	_director = _session.director
	Engine.time_scale = 4.0
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": -1,
		"segments": [{"game_id": "cadence_karaoke", "role": role, "duration_sec": -1,
			"params": {"power_cap_watts": 90.0}}]})
	var deadline := Time.get_ticks_msec() + 20000
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline:
		await process_frame
	Engine.time_scale = 1.0
	if _director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	var game: Node = _director.game
	game.change_option("look", "auto")
	var bus: Node = root.get_node("InputBus")
	var held := 0
	var shots := {90: "a", 270: "b", 600: "c", 900: "d", 1200: "e"}
	for frame in roundi(play_sec * 30.0):
		var t := frame / 30.0
		var want: float = game.logic.target() + 2.5 * sin(t * 1.7)
		if t > 18.0 and t < 24.0:
			want = game.logic.target() + 16.0  # drifts well off the target
		if frame == 30 * 28:
			game.adjust_pace(1)  # asks for a faster pace
		var key := 0
		if bus.cadence < want - 1.2:
			key = KEY_EQUAL
		elif bus.cadence > want + 1.2:
			key = KEY_MINUS
		if key != held:
			if held != 0:
				_key(held, false)
			if key != 0:
				_key(key, true)
			held = key
		await process_frame
		if shots.has(frame):
			root.get_viewport().get_texture().get_image().save_png("%s/cad_%s.png" % [out, shots[frame]])
			print("CAPTURE %s/cad_%s.png" % [out, shots[frame]])
	if held != 0:
		_key(held, false)
	quit()


func _key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
