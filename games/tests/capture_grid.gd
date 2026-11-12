extends SceneTree
## Desktop screenshots of Power Grid (not headless; needs a window):
##   $GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_grid.gd -- --out=DIR
## Plays a local Just Ride: the intro card, then stages each state by hand (dusk with the houses,
## the street lamps on, the funfair, the whole town at night, a brown-out, a storm's warning, a line
## down, the repair), then ends the ride for the summary. --role=warmup|recovery|cooldown plays that
## role instead. With --stats each shot also prints its draw calls and primitives. With
## --play=SECONDS it instead rides with a scripted rider (for Movie Maker: add --write-movie
## FILE.avi --fixed-fps 30).

const FTP := 200.0

var _session: Node
var _director: Node
var _bus: Node
var _out := "user://captures"
var _stats := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var play_sec := 0.0
	var role := "free"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
		elif arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg == "--stats":
			_stats = true
	DirAccess.make_dir_recursive_absolute(_out)
	_session = root.get_node("Session")
	_director = _session.director
	_bus = root.get_node("InputBus")
	_bus._sim_resistance = 30.0
	_bus._sim_cadence = 62.0
	var duration := 240 if play_sec <= 0.0 else maxi(roundi(play_sec * 1.6), 60)
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": duration,
		"segments": [{"game_id": "power_grid", "role": role, "duration_sec": duration, "end_mode": "timer", "seed": 5,
			"params": {"ftp_watts": FTP}}]})
	var deadline := Time.get_ticks_msec() + 20000
	while _director.phase_name() != "INTRO" and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 40:
		await process_frame
	if play_sec <= 0.0:
		_save("intro")
	Engine.time_scale = 4.0
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline + 20000:
		await process_frame
	Engine.time_scale = 1.0
	if _director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	var game: Node = _director.game
	if play_sec > 0.0:
		await _ride(game, play_sec)
		quit()
		return
	var logic: GridLogic = game.logic
	logic.storms_on = false
	await _at(game, 0.04, 90, 1.1)
	await _shot("1_dusk_houses")
	await _at(game, 0.34, 150, 1.1)
	await _shot("2_street_lamps")
	await _at(game, 0.46, 150, 1.1)
	await _shot("3_funfair")
	await _at(game, 0.8, 420, 1.1)
	await _shot("4_whole_town")
	# A brown-out: the rider eases off and the stadium dims.
	await _short(game, 240)
	await _shot("5_brown_out")
	await _at(game, 0.8, 260, 1.15)
	# A storm: the warning, then the line down, repairing.
	logic.storms_on = true
	logic.storm = GridLogic.Storm.CALM
	logic._next_storm = 0.0
	await _at(game, 0.8, 70, 1.15)
	await _shot("6_storm_warning")
	await _at(game, 0.8, 300, 1.4)
	await _shot("7_line_down")
	_session.request_end()
	deadline = Time.get_ticks_msec() + 15000
	while _director.phase_name() not in ["SUMMARY", "IDLE"] and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 150:
		await process_frame
	_save("8_summary")
	quit()


## Holds the evening at `p` (0-1) for `frames` frames, the rider at `over` × what's asked.
func _at(game: Node, p: float, frames: int, over: float) -> void:
	var logic: GridLogic = game.logic
	for i in frames:
		logic.t = p * logic.evening_sec
		logic.online = GridLogic.online_at(logic.u_at(logic.t))
		logic.powered = logic.online
		_ride_to(logic.target() * over)
		await process_frame


## A rider short of demand for `frames` frames.
func _short(game: Node, frames: int) -> void:
	var logic: GridLogic = game.logic
	for i in frames:
		logic.t = 0.8 * logic.evening_sec
		_ride_to(logic.need() * 0.7)
		await process_frame


## The simulator's cadence that makes `watts` at its resistance.
func _ride_to(watts: float) -> void:
	_bus._sim_cadence = watts / (0.3 + _bus._sim_resistance * 0.045)


func _shot(name: String) -> void:
	await process_frame
	_save(name)


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/grid_%s.png" % [_out, name]
	img.save_png(path)
	var line := "CAPTURE %s %dx%d" % [path, img.get_width(), img.get_height()]
	if _stats:
		line += " draw_calls=%d primitives=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	print(line)


## A scripted rider for `seconds`: meets demand, repairs the storms, eases off once for a brown-out.
func _ride(game: Node, seconds: float) -> void:
	var logic: GridLogic = game.logic
	logic._next_storm = minf(seconds * 0.45, 12.0)
	for frame in roundi(seconds * 30.0):
		var t := frame / 30.0
		var watts := maxf(logic.need_ahead(4.0), logic.target()) * 1.12
		if logic.storm == GridLogic.Storm.WARNING:
			watts = logic.repair_need * 1.2
		if t > seconds * 0.72 and t < seconds * 0.86:
			watts = logic.need() * 0.65
		var cadence: float = watts / (0.3 + _bus._sim_resistance * 0.045)
		_bus._sim_cadence = move_toward(_bus._sim_cadence, cadence, 1.2)
		await process_frame
