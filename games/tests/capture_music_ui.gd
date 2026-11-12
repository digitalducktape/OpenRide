extends SceneTree
## A desktop still of a game with the rider's track set, the Music button showing (not headless;
## needs a window):
##   $GODOT_BIN --path games --resolution 1920x1080 -s res://tests/capture_music_ui.gd -- \
##     --game=ID --out=DIR [--kind=circuit] [--steer] [--callout=TEXT]
## Plays the game through a Just Ride (or a two-slot circuit) and saves DIR/ID.png in play, with a
## callout showing if one is given.

var _out := "user://captures"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var game_id := "balloon_pump"
	var kind := "just_ride"
	var steer := false
	var callout := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--game="):
			game_id = arg.get_slice("=", 1)
		elif arg.begins_with("--kind="):
			kind = arg.get_slice("=", 1)
		elif arg.begins_with("--callout="):
			callout = arg.get_slice("=", 1)
		elif arg == "--steer":
			steer = true
	DirAccess.make_dir_recursive_absolute(_out)
	var session: Node = root.get_node("Session")
	var director: Node = session.director
	var bus: Node = root.get_node("InputBus")
	bus._sim_resistance = 30.0
	bus._sim_cadence = 80.0
	bus._sim_rider_music = true
	if game_id == "keepy_uppy":
		# Loaded at run time: a SceneTree script compiles before the autoloads exist.
		var options: Variant = load("res://framework/GameOptions.gd")
		var registry: Variant = load("res://games/Registry.gd")
		options.set_value(registry.info(game_id), "steer", "on" if steer else "off")
	session._on_now_playing({"title": "Nothin' on You (feat. Bruno Mars)", "artist": "B.o.B, Bruno Mars",
		"art": "", "playing": true, "can_previous": true, "can_next": true})
	var params := {"ftp_watts": 200.0, "weight_watts": 80.0, "fuel_line_watts": 100.0, "fuel_full_watts": 120.0, "target_watts": 210.0}
	var segment := {"game_id": game_id, "role": "free" if game_id in ["keepy_uppy", "the_pull"] else "work", "duration_sec": 600,
		"end_mode": "timer", "seed": 5, "effort": true, "params": params}
	var segments := [segment, segment] if kind == "circuit" else [segment]
	session._local.start({"kind": kind, "plan_id": "capture", "difficulty": "standard", "total_sec": 0, "segments": segments})
	Engine.time_scale = 4.0
	var deadline := Time.get_ticks_msec() + 40000
	while director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline:
		await process_frame
	Engine.time_scale = 1.0
	if director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	for i in 150:
		await process_frame
	if not callout.is_empty():
		if "banner" in director.game:
			director.game.banner.show_callout(callout, Color(1.0, 0.75, 0.3), 5.0)
		else:
			director.hud.show_message(callout, Color(1.0, 0.75, 0.3))
		for i in 30:
			await process_frame
	await process_frame
	root.get_texture().get_image().save_png("%s/%s.png" % [_out, game_id])
	print("CAPTURED %s" % game_id)
	quit()
