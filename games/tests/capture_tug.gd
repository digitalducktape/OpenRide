extends SceneTree
## Desktop screenshots of Tug of War (not headless; needs a window):
##   $GODOT_BIN --path games -s res://tests/capture_tug.gd -- --out=DIR
## Plays a local Just Ride, then sets the rope and the bot's state by hand for each shot, in
## each time of day. With --play=SECONDS it instead holds the rope steady and lets surges and
## rounds run (for Movie Maker: add --write-movie FILE.avi --fixed-fps 30).

var _session: Node
var _director: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://captures"
	var hud := true
	var play_sec := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg == "--nohud":
			hud = false
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out)
	_session = root.get_node("Session")
	_director = _session.director
	Engine.time_scale = 4.0
	# --play runs rounds back to back (a timed segment), so a short recording shows several.
	var duration := 600 if play_sec > 0.0 else -1
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": duration,
		"segments": [{"game_id": "tug_of_war", "role": "free", "duration_sec": duration, "end_mode": "timer",
			"params": {"ftp": 200.0, "bot_watts": 220.0, "surge_watts": 260.0}}]})
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
	if play_sec > 0.0:
		game.change_option("scene", "dusk")
		await _ride(game, play_sec)
		quit()
		return
	# [name, scene, rope p, surge state]
	var shots := [
		["day_even", "day", 0.0, ""],
		["day_winning", "day", 0.6, ""],
		["dusk_losing_telegraph", "dusk", -0.6, "telegraph"],
		["night_surge", "night", 0.1, "surge"],
		["dawn_even", "dawn", 0.0, ""],
	]
	for shot in shots:
		game.change_option("scene", shot[1])
		game.logic._next_surge = 1000.0
		game.logic.surge_state = shot[3]
		game.logic.p = shot[2]
		game.world.set_bot(0 if shot[0] != "night_surge" else 3)
		for i in 8:
			game.logic.p = shot[2]
			game.logic.surge_state = shot[3]
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/tug_%s.png" % [out, shot[0]])
		print("CAPTURE %s/tug_%s.png fps=%d" % [out, shot[0], Engine.get_frames_per_second()])
	# A round won: the bot falls into the river, and the splash.
	game.change_option("scene", "day")
	game.logic.surge_state = ""
	game.logic.p = 0.99
	for i in 5:
		game.logic.p = 0.99
		await process_frame
	var none: Array[Dictionary] = []
	game.logic._end_round(true, none)
	game.world.fall(true)
	for frame in [18, 42, 60]:
		while game.world._fall * game.world.FALL_SEC * 60.0 < frame and game.world._fall < 1.0:
			await process_frame
		var img := root.get_viewport().get_texture().get_image()
		img.save_png("%s/tug_fall_%d.png" % [out, frame])
		print("CAPTURE %s/tug_fall_%d.png" % [out, frame])
	# A round lost: the camera is pulled in.
	game.logic.phase = TugLogic.Phase.ROUND
	game.world.reset_round()
	game.logic.p = -0.99
	for i in 5:
		game.logic.p = -0.99
		await process_frame
	game.logic._end_round(false, none)
	game.world.fall(false)
	for frame in [40, 60, 78]:
		while game.world._fall * game.world.FALL_SEC * 60.0 < frame and game.world._fall < 1.0:
			await process_frame
		var lost_img := root.get_viewport().get_texture().get_image()
		lost_img.save_png("%s/tug_lose_%d.png" % [out, frame])
		print("CAPTURE %s/tug_lose_%d.png" % [out, frame])
	quit()


## Rides for `seconds` with a simple controller that holds the simulator at a target wattage:
## well over the bot to win a round, then well under it to lose one, and so on.
func _ride(game: Node, seconds: float) -> void:
	var bus: Node = root.get_node("InputBus")
	var held := 0
	# Frames, not wall time: Movie Maker (--fixed-fps 30) renders slower than real time.
	for frame in roundi(seconds * 30.0):
		var target := 290.0 if int(game.logic.round_index) % 2 == 1 else 160.0
		var key := 0
		if bus.power < target - 6.0:
			key = KEY_EQUAL
		elif bus.power > target + 6.0:
			key = KEY_MINUS
		if key != held:
			if held != 0:
				_key(held, false)
			if key != 0:
				_key(key, true)
			held = key
		await process_frame
	if held != 0:
		_key(held, false)


func _key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
