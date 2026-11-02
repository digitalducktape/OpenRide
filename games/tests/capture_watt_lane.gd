extends SceneTree
## Desktop capture of Watt Lane (#78; not headless, needs a window):
##   $GODOT_BIN --path games --resolution 1920x1008 -s res://tests/capture_watt_lane.gd -- --out=DIR [--play=40]
##   add `--write-movie FILE.avi --fixed-fps 30` for a recording with the game's own mix.
## A scripted rider (the keyboard simulator's + and −) follows the lane with a little lag, misses
## part of one jump on purpose and drifts off the lane for a few seconds, so the shots show the
## intro card, riding in the lane, an announced jump (chevrons, countdown), off the lane, and the
## summary. --measure=SEC instead rides for SEC seconds with vsync off and prints the 3D view's
## draw calls and frame times. --role=warmup plays a warm-up.

const FTP := 250.0

var _session: Node
var _director: Node
var _held := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://captures"
	var play_sec := 40.0
	var role := "work"
	var measure_sec := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
		elif arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg.begins_with("--measure="):
			measure_sec = float(arg.get_slice("=", 1))
	DirAccess.make_dir_recursive_absolute(out)
	_session = root.get_node("Session")
	_director = _session.director
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": roundi(play_sec) + 10,
		"segments": [{"game_id": "watt_lane", "role": role, "duration_sec": roundi(play_sec), "seed": 21,
			"params": {"ftp_watts": FTP}}]})
	var bus: Node = root.get_node("InputBus")
	for frame in 120:  # the intro card
		await process_frame
		if frame == 100:
			_shot(out, "wl_1_intro")
	if OS.get_cmdline_user_args().has("--card"):
		await create_timer(2.5).timeout
		_shot(out, "wl_card_raw")
	var deadline := Time.get_ticks_msec() + 20000
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline:
		await process_frame
	var game: Node = _director.game
	if game == null or _director.phase_name() != "PLAYING":
		print("CAPTURE FAILED: the game never started")
		quit(1)
		return
	if measure_sec > 0.0:
		await _measure(game, bus, measure_sec)
		quit()
		return
	var shots := {}
	var frame := 0
	while is_instance_valid(game) and _director.phase_name() == "PLAYING":
		var t: float = game.logic.time
		var off := 0.0
		if t > 30.0 and t < 36.0:
			off = -45.0  # eases right off the lane for a few seconds
		await _ride(game, bus, off)
		frame += 1
		if not is_instance_valid(game):
			break
		var up: Dictionary = game.logic.upcoming()
		if not shots.has("play") and t > 14.0 and game.logic.in_lane:
			shots["play"] = _shot(out, "wl_2_in_lane")
		if not shots.has("jump") and not up.is_empty() and float(up.at) < 3.0:
			shots["jump"] = _shot(out, "wl_3_jump_announced")
		if not shots.has("bend") and not up.is_empty() and float(up.at) < 1.0:
			shots["bend"] = _shot(out, "wl_4_jump_bend")
		if not shots.has("off") and t > 34.5:
			shots["off"] = _shot(out, "wl_5_off_lane")
	_ride_stop()
	deadline = Time.get_ticks_msec() + 20000
	while not _director.summary_screen.visible and Time.get_ticks_msec() < deadline:
		await process_frame
	await create_timer(1.5).timeout
	_shot(out, "wl_6_summary")
	quit()


func _shot(out: String, name: String) -> bool:
	var path := "%s/%s.png" % [out, name]
	root.get_viewport().get_texture().get_image().save_png(path)
	print("CAPTURE %s" % path)
	return true


## One frame of the scripted rider: + or − to bring the power toward the lane's centre a moment
## ahead (the 3 s window lags), plus `off` watts.
func _ride(game: Node, bus: Node, off := 0.0) -> void:
	if not is_instance_valid(game) or game.logic == null:
		await process_frame
		return
	var want: float = game.logic.course.visual_centre_at(game.logic.time + 1.2) + off
	var key := 0
	if bus.power < want - 4.0:
		key = KEY_EQUAL
	elif bus.power > want + 4.0:
		key = KEY_MINUS
	if key != _held:
		if _held != 0:
			_key(_held, false)
		if key != 0:
			_key(key, true)
		_held = key
	await process_frame


func _ride_stop() -> void:
	if _held != 0:
		_key(_held, false)
		_held = 0


func _key(keycode: int, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = pressed
	Input.parse_input_event(e)


func _measure(game: Node, bus: Node, seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var view: SubViewport = game.get("_view")
	var rid := view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	for i in 120:
		await _ride(game, bus)
	var frames := 0
	var draws := 0.0
	var prims := 0.0
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < seconds * 1e6:
		await _ride(game, bus)
		frames += 1
		draws += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		prims += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var ms := (Time.get_ticks_usec() - start) / 1000.0 / frames
	print("MEASURE watt_lane frames=%d frame_ms=%.2f view_draws=%.1f view_prims=%.0f gpu_ms=%.2f cpu_ms=%.2f" % [
		frames, ms, draws / frames, prims / frames, RenderingServer.viewport_get_measured_render_time_gpu(rid),
		RenderingServer.viewport_get_measured_render_time_cpu(rid)])
	_ride_stop()
