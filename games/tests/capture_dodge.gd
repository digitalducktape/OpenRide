extends SceneTree
## Desktop screenshots of Dodge Ball in each lighting (not headless; needs a window):
##   $GODOT_BIN --path games -s res://tests/capture_dodge.gd -- --out=DIR
## Plays a local Just Ride, weaves with the arrow keys, and saves one PNG per time of day.
## With --play=SECONDS it instead rides that long above the cadence floor and the power target
## (for Movie Maker: add --write-movie FILE.avi --fixed-fps 30 to record the game's own mix,
## reverb and all, without playing a sound).

var _session: Node
var _director: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://captures"
	var hud := true
	var play_sec := 0.0
	var intro := false
	var bonus := false
	var scenes := ["dawn", "day", "dusk", "night"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg == "--nohud":
			hud = false
		elif arg.begins_with("--scenes="):
			scenes = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--mode="):
			# Written straight to the options file: a -s script can't name classes that use autoloads.
			var options := ConfigFile.new()
			options.load("user://game_options.cfg")
			options.set_value("guest/dodge_ball", "mode", arg.get_slice("=", 1))
			options.save("user://game_options.cfg")
		elif arg == "--bonus":
			bonus = true
		elif arg == "--intro":
			intro = true
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out)
	_session = root.get_node("Session")
	_director = _session.director
	Engine.time_scale = 4.0
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": -1,
		"segments": [{"game_id": "dodge_ball", "role": "free", "duration_sec": -1}]})
	if intro:
		# The intro card, once the calibration has run.
		Engine.time_scale = 1.0
		while _session.is_calibrating():
			await process_frame
		await create_timer(1.5).timeout
		root.get_viewport().get_texture().get_image().save_png("%s/dodge_intro.png" % out)
		print("CAPTURE %s/dodge_intro.png" % out)
		Engine.time_scale = 4.0
	var deadline := Time.get_ticks_msec() + 20000
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline:
		await process_frame
	Engine.time_scale = 1.0
	if _director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	var game: Node = _director.game
	_director.hud.visible = hud
	if bonus:
		# A power target under the simulator's power, so the bonus shows (a local plan has none).
		game.logic.target_watts = 100.0
		_director.hud.metrics.set_power_band(100.0)
	var key := KEY_LEFT
	if play_sec > 0.0:
		game.change_option("scene", scenes[0])
		# Pedal up past the floor, then add resistance until the power bonus is on.
		_key(KEY_EQUAL, true)
		await create_timer(1.5).timeout
		_key(KEY_EQUAL, false)
		_key(KEY_BRACKETRIGHT, true)
		await create_timer(1.2).timeout
		_key(KEY_BRACKETRIGHT, false)
		var t := 0.0
		while t < play_sec:
			_key(key, true)
			await create_timer(0.45).timeout
			_key(key, false)
			key = KEY_RIGHT if key == KEY_LEFT else KEY_LEFT
			t += 0.45
		quit()
		return
	for scene in scenes:
		game.change_option("scene", scene)
		for i in 6:
			_key(key, true)
			await create_timer(0.4).timeout
			_key(key, false)
			key = KEY_RIGHT if key == KEY_LEFT else KEY_LEFT
		await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/dodge_%s.png" % [out, scene])
		print("CAPTURE %s/dodge_%s.png fps=%d" % [out, scene, Engine.get_frames_per_second()])
	game.change_option("scene", "auto")
	quit()


func _key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
