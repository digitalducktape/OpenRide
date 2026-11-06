extends SceneTree
## Desktop screenshots of Ready for Launch (not headless; needs a window):
##   $GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_launch.gd -- --out=DIR
## Plays a local Just Ride and stages each moment by hand: the intro card, fuelling, the count,
## ignition, the clouds, the edge of space, orbit, the Moon, then ends the ride for the summary.
## --stats also prints each shot's draw calls and primitives. --places takes one still per place.
## --place=ID stages the shots there, --mark=N (0-2) with that rocket. --silhouette draws every
## rocket and the capsule in solid black at full and small size (ART_BIBLE §3's check). With
## --play=SECONDS it rides with a scripted rider instead (for Movie Maker: add --write-movie
## FILE.avi --fixed-fps 30).

var _session: Node
var _director: Node
var _out := "user://captures"
var _stats := false
var _places := false
var _mark := -1
var _short := false  ## --short: with --play, only the last few seconds of the fuelling


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var play_sec := 0.0
	var place_id := "random"
	var silhouette := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
		elif arg == "--stats":
			_stats = true
		elif arg == "--short":
			_short = true
		elif arg == "--places":
			_places = true
		elif arg == "--silhouette":
			silhouette = true
		elif arg.begins_with("--place="):
			place_id = arg.get_slice("=", 1)
		elif arg.begins_with("--mark="):
			_mark = int(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(_out)
	if silhouette:
		await _silhouettes()
		quit()
		return
	_session = root.get_node("Session")
	_director = _session.director
	# Loaded at run time: a SceneTree script compiles before the autoloads exist.
	var options: Variant = load("res://framework/GameOptions.gd")
	var registry: Variant = load("res://games/Registry.gd")
	options.set_value(registry.info("ready_for_launch"), "place", place_id)
	var bus: Node = root.get_node("InputBus")
	bus._sim_resistance = 30.0
	bus._sim_cadence = 75.0
	var duration := 300 if play_sec > 0.0 else 600
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": duration,
		"segments": [{"game_id": "ready_for_launch", "role": "free", "duration_sec": duration, "end_mode": "timer",
			"seed": 5, "params": {"ftp_watts": 200.0, "fuel_line_watts": 100.0, "fuel_full_watts": 120.0, "target_watts": 210.0}}]})
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
		if _mark >= 0:
			game._mark = _mark
			game._stage_launch()
		await _ride(game, play_sec, bus)
		quit()
		return
	var logic: LaunchLogic = game.logic
	if _mark >= 0:
		game._mark = _mark
		game._stage_launch()
	if _places:
		for i in LaunchPlaces.count():
			game._place = i
			game._mark = i
			game._stage_launch()
			logic.fuel = 0.35 + 0.2 * i
			await _frames(30)
			await _shot("place_%s" % LaunchPlaces.place(i).id)
		quit()
		return
	# Fuelling, the tank part full.
	logic.fuel = 0.62
	_power(bus, 125.0)
	await _frames(90)
	await _shot("fuel")
	# The count, four to go.
	logic.phase_left = 0.05
	await _frames(6)
	logic.phase_left = 4.2
	await _frames(40)
	await _shot("count")
	# Ignition and the first metres.
	logic.fuel = 1.0
	logic.phase_left = 0.1
	_power(bus, 240.0)
	await _frames(40)
	await _shot("ignition")
	logic.phase_left = 40.0
	await _frames(50)
	await _shot("liftoff")
	await _fly(game, logic, 4.2, 70)
	await _shot("clouds")
	await _fly(game, logic, 7.0, 90)
	await _shot("above_clouds")
	await _fly(game, logic, 14.0, 90)
	await _shot("edge")
	await _fly(game, logic, 23.0, 90)
	await _shot("orbit")
	await _fly(game, logic, 29.0, 90)
	await _shot("moon_near")
	await _fly(game, logic, 34.0, 200)
	await _shot("moon")
	_session.request_end()
	deadline = Time.get_ticks_msec() + 15000
	while _director.phase_name() not in ["SUMMARY", "IDLE"] and Time.get_ticks_msec() < deadline:
		await process_frame
	for i in 150:
		await process_frame
	_save("summary")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _power(bus: Node, watts: float) -> void:
	bus._sim_cadence = watts / (0.3 + bus._sim_resistance * 0.045)


## Lifts the rocket to `climb` through the logic, so milestones and stages fire, and holds there.
func _fly(game: Node, logic: LaunchLogic, climb: float, frames: int) -> void:
	var events: Array[Dictionary] = []
	logic.phase_left = 600.0
	var was := logic.milestone
	logic._rise(climb - logic.climb, events)
	if logic.phase == LaunchLogic.Phase.COAST:
		logic.phase_left = 600.0
	for e in events:
		game._handle(e)
	if was != logic.milestone:
		print("CAPTURE reached ", logic.reached_name())
	for i in frames:
		logic.climb = minf(climb, 34.0)
		logic.speed = 1.0
		await process_frame


func _shot(shot: String) -> void:
	await process_frame
	_save(shot)


func _save(shot: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/launch_%s.png" % [_out, shot]
	img.save_png(path)
	var line := "CAPTURE %s %dx%d" % [path, img.get_width(), img.get_height()]
	if _stats:
		line += " draw_calls=%d primitives=%d" % [Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	print(line)


## A scripted rider for `seconds`: steady through the fuelling, spinning up on the count, all out on
## the push, an easy spin after.
func _ride(game: Node, seconds: float, bus: Node) -> void:
	var logic: LaunchLogic = game.logic
	if _short:
		logic.fuel = 0.8
		logic.phase_left = 5.0
	for frame in roundi(seconds * 30.0):
		var want := 125.0
		match logic.phase:
			LaunchLogic.Phase.COUNT:
				want = 150.0
			LaunchLogic.Phase.PUSH:
				want = 270.0
			LaunchLogic.Phase.COAST, LaunchLogic.Phase.RESULT:
				want = 90.0
		bus._sim_cadence = move_toward(bus._sim_cadence, want / (0.3 + bus._sim_resistance * 0.045), 2.0)
		await process_frame


## Every rocket in solid black on white: at full size, at thumbnail size, and each state of the
## stack through a flight, the rider's check against unintended shapes.
func _silhouettes() -> void:
	var stage := Node2D.new()
	root.add_child(stage)
	var bg := ColorRect.new()
	bg.color = Color.WHITE
	bg.size = Vector2(2200, 1100)
	stage.add_child(bg)
	var rockets: Array[LaunchRocket] = []
	for mark in 3:
		var r := LaunchRocket.new()
		stage.add_child(r)
		r.setup(mark)
		r.position = Vector2(260 + mark * 400, 860)
		r.modulate = Color.BLACK
		rockets.append(r)
		var small := LaunchRocket.new()
		stage.add_child(small)
		small.setup(mark)
		small.position = Vector2(1400 + mark * 150, 300)
		small.scale = Vector2(0.14, 0.14)
		small.modulate = Color.BLACK
		var mid := LaunchRocket.new()
		stage.add_child(mid)
		mid.setup(mark)
		mid.position = Vector2(1400 + mark * 150, 620)
		mid.scale = Vector2(0.3, 0.3)
		mid.modulate = Color.BLACK
		for k in 3:
			var part := LaunchRocket.new()
			stage.add_child(part)
			part.setup(mark)
			for d in k + 1:
				if part.drop_stage():
					part._falling[-1].node.visible = false
			part.position = Vector2(1400 + mark * 150 + k * 44, 950 + part.offsets[part.bottom] * 0.14)
			part.scale = Vector2(0.14, 0.14)
			part.modulate = Color.BLACK
	await _frames(12)
	_save("silhouette")
