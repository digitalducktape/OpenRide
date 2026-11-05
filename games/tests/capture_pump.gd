extends SceneTree
## Desktop screenshots and a recording of Balloon Pump (#76; not headless, needs a window):
##   $GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_pump.gd -- --out=DIR
## Plays a local Race Just Ride (5 balloons in 2:00) with a scripted rider who spins lightly,
## stalls under the push line, then turns the knob up to finish each balloon, and saves full-size
## PNGs (with --places, instead every place posed, the HUD hidden): the intro card, filling, pushing under the line, a tie-off on its way to the bunch, a gold
## balloon, the Race won, and the summary. With --play=SECONDS it only rides (for Movie Maker:
## add --write-movie FILE.avi --fixed-fps 30), and stops.

var _session: Node
var _director: Node
var _bus: Node
var _out := "user://captures"
var _shot_seen := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var play_sec := 0.0
	var places := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
		elif arg == "--places":
			places = true
	DirAccess.make_dir_recursive_absolute(_out)
	_session = root.get_node("Session")
	_director = _session.director
	_bus = root.get_node("InputBus")
	_bus._sim_cadence = 0.0
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": 600,
		"segments": [{"game_id": "balloon_pump", "role": "free", "duration_sec": 600, "end_mode": "timer",
			"params": {"ftp_watts": 150.0, "race_balloons": 5, "race_sec": 120}}]})
	await create_timer(4.0).timeout
	if play_sec <= 0.0:
		_shot("1_intro")
	var deadline := Time.get_ticks_msec() + 30000
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline:
		await process_frame
	if _director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	var game: Node = _director.game
	if places:
		# Every place, posed with a bunch up and a big balloon nearly full (--places).
		_director.hud.visible = false
		game.set_paused(true)  # hold the pose: no frames move the balloon
		game.pose_for_card()
		for i in PumpPlaces.count():
			game.world.set_place(i)
			await create_timer(0.8).timeout
			_shot("place_%s" % PumpPlaces.place(i).id)
		quit()
		return
	if play_sec > 0.0:
		await _ride(game, play_sec, false)
		quit()
		return
	await _ride(game, 150.0, true)
	_session.request_end()
	deadline = Time.get_ticks_msec() + 15000
	while not _director.summary_screen.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.6).timeout
	_shot("7_summary")
	quit()


## The scripted rider: spins at 85 rpm with the knob low (about 30% of FTP) until the balloon
## stalls under its push line for a second and a half, then turns it up to about 70% until it ties.
## The fourth balloon is made gold for its still.
func _ride(game: Node, seconds: float, shots: bool) -> void:
	var start := Time.get_ticks_msec()
	var last := start
	var stalled := 0.0
	var dig := false
	var tied := 0
	var golded := false
	while Time.get_ticks_msec() - start < seconds * 1000.0:
		var now := Time.get_ticks_msec()
		var dt := (now - last) / 1000.0
		last = now
		var logic: PumpLogic = game.logic
		if logic.phase == PumpLogic.Phase.FILL and logic.open < 0.5 and logic.fill > 0.3:
			stalled += dt
		else:
			stalled = 0.0
		if stalled > 1.5:
			dig = true
		if logic.phase != PumpLogic.Phase.FILL:
			dig = false
		_bus._sim_cadence = 85.0
		_bus._sim_resistance = 42.0 if dig else 6.0
		if not golded and logic.balloons == 2 and logic.phase == PumpLogic.Phase.FILL:
			golded = true
			logic.next_kind = "gold"
			game.world.set_balloons(logic.kind, "gold")
		if shots:
			if logic.fill > 0.5 and not logic.leaking and logic.open > 0.9 and logic.balloons >= 1:
				_once("2_filling")
			if dig == false and stalled > 1.0 and logic.balloons >= 1:
				_once("3_push")
			if logic.balloons > tied:
				tied = logic.balloons
				if tied == 2:
					await create_timer(0.55).timeout
					_once("4_tie_off")
				if logic.gold > 0:
					await create_timer(0.35).timeout
					_once("5_gold")
			if logic.phase == PumpLogic.Phase.BREAK and logic.heats_won > 0:
				await create_timer(0.6).timeout
				_once("6_race_won")
				return
		await process_frame


func _once(state: String) -> void:
	if _shot_seen.has(state):
		return
	_shot_seen[state] = true
	_shot(state)


func _shot(state: String) -> void:
	var img := root.get_viewport().get_texture().get_image()
	var path := "%s/balloon_pump_%s.png" % [_out, state]
	img.save_png(path)
	print("CAPTURE %s fps=%d draw_calls=%d" % [path, Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])
