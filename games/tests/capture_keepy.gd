extends SceneTree
## Desktop screenshots of Keepy Uppy (not headless; needs a window):
##   $GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_keepy.gd -- --out=DIR
## Plays a local Just Ride: the intro card, then stages each state by hand (mid band, high band
## with a gust, the rain cloud coming and the rain with birds perched, a bird incoming, the
## downdraft, a pop, Steer with the wind), then ends the ride for the summary. With --stats each
## shot also prints its draw calls and primitives. With --play=SECONDS it instead rides with a
## scripted rider through the weather (for Movie Maker: add --write-movie FILE.avi --fixed-fps 30).
## --steer turns Steer on (the scripted rider leans into the wind).

var _session: Node
var _director: Node
var _out := "user://captures"
var _stats := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var play_sec := 0.0
	var steer := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
		elif arg == "--stats":
			_stats = true
		elif arg == "--steer":
			steer = true
	DirAccess.make_dir_recursive_absolute(_out)
	_session = root.get_node("Session")
	_director = _session.director
	# Loaded at run time: a SceneTree script compiles before the autoloads exist.
	var options: Variant = load("res://framework/GameOptions.gd")
	var registry: Variant = load("res://games/Registry.gd")
	options.set_value(registry.info("keepy_uppy"), "steer", "on" if steer else "off")
	var bus: Node = root.get_node("InputBus")
	bus._sim_resistance = 30.0
	bus._sim_cadence = 62.0
	var duration := 600 if play_sec > 0.0 else -1
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": duration,
		"segments": [{"game_id": "keepy_uppy", "role": "free", "duration_sec": duration, "end_mode": "timer",
			"seed": 5, "params": {"ftp_watts": 200.0, "weight_watts": 80.0}}]})
	# The intro card.
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
		await _ride(game, play_sec, bus)
		quit()
		return
	var logic: KeepyLogic = game.logic
	logic._next_force = 1.0e9
	logic._next_gust = 1.0e9
	# Mid band, calm.
	await _hold(game, 0.5, 90)
	await _shot("play_mid")
	# High band, a gust warned.
	await _hold(game, 0.82, 120)
	logic._next_gust = 0.0
	await _hold(game, 0.82, 20)
	await _shot("high_gust")
	logic.gust = ""
	logic._next_gust = 1.0e9
	# The rain cloud coming in.
	_stage_force(logic, "rain", 1.4)
	await _hold(game, 0.55, 20)
	await _shot("rain_coming")
	# Raining, two birds perched.
	logic.weather = KeepyLogic.Weather.ACTIVE
	logic.force_left = 30.0
	logic._rain_left = 30.0
	logic.raining = true
	logic.birds = 2
	logic._bird_stay = 60.0
	await _hold(game, 0.48, 120)
	await _shot("rain_birds")
	logic.raining = false
	logic.weather = KeepyLogic.Weather.CALM
	logic.force = ""
	logic._next_force = 1.0e9
	await _hold(game, 0.5, 120)
	# A bird incoming.
	_stage_force(logic, "bird", 0.9)
	await _hold(game, 0.5, 30)
	await _shot("bird_incoming")
	logic.weather = KeepyLogic.Weather.CALM
	logic.force = ""
	logic.birds = 0
	# The downdraft rolling in.
	_stage_force(logic, "downdraft", 1.4)
	await _hold(game, 0.5, 40)
	await _shot("downdraft")
	logic.weather = KeepyLogic.Weather.CALM
	logic.force = ""
	logic._next_force = 1.0e9
	await _hold(game, 0.5, 60)
	# A pop.
	logic.h = 0.002
	logic._grace = 0.0
	logic.smoothed = 0.0
	for i in 9:
		await process_frame
	await _shot("pop")
	await _hold(game, 0.5, 260)
	# Steer: wind off to the right, the fan slid partway under it.
	logic.steer = true
	logic.wind = KeepyLogic.WIND_MAX
	logic.wind_target = KeepyLogic.WIND_MAX
	logic.wind_gain = 1.0
	logic._next_wind = 1.0e9
	for i in 200:
		logic.fan_target = 0.3
		logic.fan_x = 0.3
		await process_frame
	await _shot("steer_wind")
	# The summary.
	_session.request_end()
	deadline = Time.get_ticks_msec() + 15000
	while _director.phase_name() not in ["SUMMARY", "IDLE"] and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 150:
		await process_frame
	_save("summary")
	quit()


## Holds the balloon at `h` for `frames` frames (the simulator's power set to what holds it).
func _hold(game: Node, h: float, frames: int) -> void:
	var bus: Node = root.get_node("InputBus")
	var logic: KeepyLogic = game.logic
	for i in frames:
		var watts := KeepyLogic.power_for(h, logic.weight())
		bus._sim_cadence = watts / (0.3 + bus._sim_resistance * 0.045)
		if logic.balloon == KeepyLogic.Balloon.FLYING:
			logic.h = move_toward(logic.h, h, 1.0 / 60.0 * 0.4)
		await process_frame


## A force `seconds` into its warning (the rest still to come).
func _stage_force(logic: KeepyLogic, force: String, seconds: float) -> void:
	_director.game._handle({"type": "telegraph", "force": force})
	logic.force = force
	logic.weather = KeepyLogic.Weather.TELEGRAPH
	logic.force_left = KeepyLogic.WARNING[force] - seconds + 0.5


func _shot(name: String) -> void:
	await process_frame
	_save(name)


func _save(name: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/keepy_%s.png" % [_out, name]
	img.save_png(path)
	var line := "CAPTURE %s %dx%d" % [path, img.get_width(), img.get_height()]
	if _stats:
		line += " draw_calls=%d primitives=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	print(line)


## A scripted rider for `seconds`: about half of FTP, answering the weather (more power under rain
## and birds, a burst on a downdraft's warning), with a climb to the high band now and then to
## shake birds off; with Steer, leaning into the wind.
func _ride(game: Node, seconds: float, bus: Node) -> void:
	var logic: KeepyLogic = game.logic
	logic._next_force = 3.0
	var held := 0
	for frame in roundi(seconds * 30.0):
		if logic.steer:
			# Lean (the arrow keys) toward the windsock until the fan is under the balloon.
			var key := 0
			if logic.x - logic.fan_x > 0.2:
				key = KEY_RIGHT
			elif logic.x - logic.fan_x < -0.2:
				key = KEY_LEFT
			if key != held:
				if held != 0:
					_key(held, false)
				if key != 0:
					_key(key, true)
				held = key
		var t := frame / 30.0
		var target := 0.52 * 200.0 + (logic.weight() - 80.0) * 1.3
		if fmod(t, 30.0) > 20.0 or logic.birds > 0 and fmod(t, 12.0) > 6.0:
			target = 0.66 * 200.0 + (logic.weight() - 80.0) * 1.3
		if logic.force == "downdraft" and logic.weather != KeepyLogic.Weather.CALM:
			target = 0.85 * 200.0
		if t > 50.0 and t < 56.0:
			target = 40.0  # let one pop, for the recording
		bus._sim_cadence = move_toward(bus._sim_cadence, target / (0.3 + bus._sim_resistance * 0.045), 0.8)
		await process_frame
	if held != 0:
		_key(held, false)


func _key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
