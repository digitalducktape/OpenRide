extends SceneTree
## Gate Crasher's review captures (#80). Not headless; needs a window:
##   $GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_gate.gd -- --out=DIR
## Plays a local Just Ride with a scripted rider (the simulator's cadence, resistance and stand,
## with the real detector's 0.5 s lag) and saves full-size PNGs:
##   gate_crasher_1_intro.png     the intro card
##   gate_crasher_2_canter.png    cantering, the ears and the mane
##   gate_crasher_3_count.png     the chevrons lit on the approach
##   gate_crasher_4_jump.png      in the air over a fence
##   gate_crasher_5_fault.png     a rail down
##   gate_crasher_6_circle.png    the lost-camera circle
##   gate_crasher_7_clear.png     the clear round's callout
##   gate_crasher_8_summary.png   the session summary
## Each line prints the frame rate and draw calls. With --play=SECONDS it instead rides for a
## recording (add --write-movie FILE.avi --fixed-fps 30). With --silhouette it saves the horse in
## solid black on white, full size and at 240 px (ART_BIBLE §10).

var _session: Node
var _director: Node
var _bus: Node
var _out := "user://captures"
var _play := 0.0
var _silhouette := false
var _miss_fence := -1


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			_play = float(arg.get_slice("=", 1))
		elif arg == "--silhouette":
			_silhouette = true
	DirAccess.make_dir_recursive_absolute(_out)
	_session = root.get_node("Session")
	_director = _session.director
	_bus = root.get_node("InputBus")
	_bus._sim_cadence = 0.0
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": 600,
		"segments": [{"game_id": "gate_crasher", "role": "free", "duration_sec": 600, "end_mode": "timer"}]})
	var deadline := Time.get_ticks_msec() + 40000
	while _bus.tracker_state != 3 and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.0).timeout
	if _play <= 0.0 and not _silhouette:
		await _shot("1_intro")
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline:
		await process_frame
	if _director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	var game: Node = _director.game
	if _silhouette:
		await _black_horse(game)
		quit()
		return
	_bus._sim_cadence = 85.0
	_bus._sim_resistance = 34.0
	if _play > 0.0:
		_miss_fence = 2
		var frames := int(_play * 30.0)
		for i in frames:
			_rider(game)
			await process_frame
		quit()
		return
	await _until(game, func(): return game.logic.speed > 7.0 and game.logic.eta() > 3.3)
	await _shot("2_canter")
	await _until(game, func(): return game._stage == 3)
	await create_timer(0.3).timeout
	await _shot("3_count")
	await _until(game, func(): return game.logic.arc_height() > 1.2)
	await _shot("4_jump")
	_miss_fence = game.logic.fence + 1
	await _until(game, func(): return game.logic.faults > 0)
	await create_timer(0.35).timeout
	await _shot("5_fault")
	_miss_fence = -1
	# The rider leaves the frame for a moment.
	var lost := Time.get_ticks_msec()
	game.logic._start_circle([])
	game._handle({"type": "circle"})
	while Time.get_ticks_msec() - lost < 2000:
		game.logic.circle_angle = minf(game.logic.circle_angle, 2.0)
		await process_frame
	await _shot("6_circle")
	await _until(game, func(): return game.logic.phase == GateLogic.Phase.RIDE)
	# Skip ahead to a last clean fence of a clean round.
	game.logic.results.clear()
	for i in game.logic.fences - 1:
		game.logic.results.append(GateLogic.Call.CLEAR)
	game.logic.fence = game.logic.fences * 2 - 1
	game.logic.distance = game.logic.line_s(game.logic.fence) - 40.0
	game._round_faults = 0
	await _until(game, func(): return game.logic.clear_rounds > 0)
	await create_timer(0.4).timeout
	await _shot("7_clear")
	_session.request_end()
	var deadline2 := Time.get_ticks_msec() + 15000
	while not _director.summary_screen.visible and Time.get_ticks_msec() < deadline2:
		await process_frame
	await create_timer(1.2).timeout
	await _shot("8_summary")
	quit()


func _until(game: Node, test: Callable) -> void:
	var deadline := Time.get_ticks_msec() + 60000
	while not test.call() and Time.get_ticks_msec() < deadline:
		_rider(game)
		await process_frame


## A rider who stands on the line and sits after the fence, seen through the detector's lag.
func _rider(game: Node) -> void:
	var l: GateLogic = game.logic
	var past := l.distance - l.line_s(l.fence)
	var up := l.speed > 1.0 and past >= l.speed * l.lag and past < GateLogic.LINE_GAP and l.fence != _miss_fence
	_bus._sim_standing = up


func _black_horse(game: Node) -> void:
	var world: GateWorld = game.world
	var black := StandardMaterial3D.new()
	black.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	black.albedo_color = Color.BLACK
	for node: Node in world.get_children():
		if node is MeshInstance3D or node is MultiMeshInstance3D:
			node.visible = false
	var horse: MeshInstance3D = world.get_node("Rig/Horse")
	horse.material_override = black
	world.get_node("Environment").environment.background_color = Color.WHITE
	game.hud.visible = false
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(_out.path_join("gate_crasher_silhouette.png"))
	img.resize(240, 126, Image.INTERPOLATE_LANCZOS)
	img.save_png(_out.path_join("gate_crasher_silhouette_small.png"))


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(_out.path_join("gate_crasher_%s.png" % name))
	print("%s: %.0f fps, %d draw calls" % [name, Engine.get_frames_per_second(),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)])
