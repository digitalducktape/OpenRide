extends SceneTree
## The Pull's review captures (#79). Not headless; needs a window:
##   $GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_pull.gd -- --out=DIR
## Plays a local timed Just Ride of The Pull with a scripted rider (the simulator's cadence and
## resistance) and saves full-size PNGs:
##   the_pull_1_intro.png     the intro card
##   the_pull_2_set.png       the look back at the sled while the pull is set
##   the_pull_3_pull.png      rolling down the track near FTP, the sled in the mirror
##   the_pull_4_dig_in.png    the sled bogging down: "Dig in!"
##   the_pull_5_full.png      a Full Pull (the pull is moved near the line for the shot)
##   the_pull_6_summary.png   the session summary
## Each line prints the frame rate and draw calls. With --play=SECONDS it instead rides one
## scripted pull for a recording (add --write-movie FILE.avi --fixed-fps 30): steady near FTP,
## a fade to a stall, then the rest card. With --stats it prints the 3D view's draw calls in play.

var _session: Node
var _director: Node
var _bus: Node
var _out := "user://captures"
var _play := 0.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			_play = float(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_out)
	_session = root.get_node("Session")
	_director = _session.director
	_bus = root.get_node("InputBus")
	_bus._sim_cadence = 0.0
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": 600,
		"segments": [{"game_id": "the_pull", "role": "free", "duration_sec": 600, "end_mode": "game"}]})
	var deadline := Time.get_ticks_msec() + 30000
	await create_timer(1.5).timeout
	if _play <= 0.0:
		_shot("1_intro")
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline:
		await process_frame
	if _director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	var game: Node = _director.game
	if _play > 0.0:
		await _ride(game)
		quit()
		return
	_bus._sim_cadence = 85.0
	_bus._sim_resistance = 32.0
	await create_timer(1.7).timeout
	_shot("2_set")
	await create_timer(14.0).timeout
	_shot("3_pull")
	# Bog down: move the pull far along, then ease off until the warning.
	game.logic.distance = 230.0
	_bus._sim_cadence = 60.0
	_bus._sim_resistance = 25.0
	deadline = Time.get_ticks_msec() + 30000
	while not game.logic.warned and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.6).timeout
	_shot("4_dig_in")
	# A Full Pull: just short of the line, and hard.
	_bus._sim_cadence = 110.0
	_bus._sim_resistance = 60.0
	await create_timer(1.0).timeout
	game.logic.distance = game.logic.full_m - 3.0
	game.logic.speed = 2.0
	deadline = Time.get_ticks_msec() + 15000
	while game.logic.last_end != "full" and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(0.7).timeout
	_shot("5_full")
	_session.request_end()
	deadline = Time.get_ticks_msec() + 15000
	while not _director.summary_screen.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.2).timeout
	_shot("6_summary")
	quit()


## One scripted pull for a recording: the look back, a strong start, the boards, the mirror, a
## fade into the warning and the stall, then the rest card.
func _ride(game: Node) -> void:
	_bus._sim_cadence = 88.0
	_bus._sim_resistance = 34.0
	await create_timer(minf(_play * 0.45, 14.0)).timeout
	game.logic.distance = maxf(game.logic.distance, 150.0)
	await create_timer(minf(_play * 0.2, 6.0)).timeout
	_bus._sim_cadence = 55.0
	_bus._sim_resistance = 22.0
	await create_timer(_play * 0.35).timeout


func _shot(state: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/the_pull_%s.png" % [_out, state]
	img.save_png(path)
	print("CAPTURE %s fps=%d draw_calls=%d" % [path, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
