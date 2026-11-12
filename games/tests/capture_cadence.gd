extends SceneTree
## Desktop capture of Cadence Karaoke (not headless; needs a window):
##   $GODOT_BIN --path games --write-movie FILE.avi --fixed-fps 30 -s res://tests/capture_cadence.gd -- --play=45 --out=DIR
## A scripted rider follows the target with a little wobble, drifts off it for a while, then asks
## for a faster pace, so the clip shows the band, the streak, the ease-off and a pace change.
## --nohud hides the HUD (the graphics review's stills). --looks=cyan,green,violet,pink instead
## saves one still per tunnel colour (`cad_look_<name>.png`), 3 s into riding on the target.
## --measure=SEC rides on the target for SEC seconds with vsync off and prints the 3D view's
## draw calls, primitives and objects (RenderingServer render info of the SubViewport), its GPU
## and CPU render time and the whole frame's time: the graphics budget check on the desktop.
## --overdraw saves `cad_overdraw.png`, the 3D view with the overdraw debug draw (additive
## layers show brighter).

var _session: Node
var _director: Node
var _held := 0  ## the key the scripted rider holds


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://captures"
	var play_sec := 45.0
	var role := "free"
	var hud := true
	var looks: PackedStringArray = []
	var measure_sec := 0.0
	var overdraw := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg.begins_with("--play="):
			play_sec = float(arg.get_slice("=", 1))
		elif arg.begins_with("--role="):
			role = arg.get_slice("=", 1)
		elif arg == "--nohud":
			hud = false
		elif arg.begins_with("--looks="):
			looks = arg.get_slice("=", 1).split(",")
		elif arg.begins_with("--measure="):
			measure_sec = float(arg.get_slice("=", 1))
		elif arg == "--overdraw":
			overdraw = true
	DirAccess.make_dir_recursive_absolute(out)
	_session = root.get_node("Session")
	_director = _session.director
	Engine.time_scale = 4.0
	_session._local.start({"kind": "just_ride", "plan_id": "capture", "difficulty": "standard", "total_sec": -1,
		"segments": [{"game_id": "cadence_karaoke", "role": role, "duration_sec": -1,
			"params": {"power_cap_watts": 90.0}}]})
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
	game.change_option("look", "auto")
	var bus: Node = root.get_node("InputBus")
	if measure_sec > 0.0:
		await _measure(game, bus, measure_sec)
		quit()
		return
	if overdraw:
		var view: SubViewport = game.get("view")
		view.debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
		for frame in 90:
			await _ride(game, bus, frame / 30.0)
		var img := view.get_texture().get_image()
		img.save_png("%s/cad_overdraw.png" % out)
		var sum := 0.0
		var count := 0
		for y in range(0, img.get_height(), 4):
			for x in range(0, img.get_width(), 4):
				sum += img.get_pixel(x, y).g
				count += 1
		print("CAPTURE %s/cad_overdraw.png mean_green=%.3f (higher = more layers)" % [out, sum / count])
		quit()
		return
	for look in looks:
		game.change_option("look", look)
		for frame in 90:
			await _ride(game, bus, frame / 30.0)
		root.get_viewport().get_texture().get_image().save_png("%s/cad_look_%s.png" % [out, look])
		print("CAPTURE %s/cad_look_%s.png fps=%d" % [out, look, Engine.get_frames_per_second()])
	if not looks.is_empty():
		quit()
		return
	var shots := {90: "a", 270: "b", 600: "c", 900: "d", 1200: "e"}
	for frame in roundi(play_sec * 30.0):
		var t := frame / 30.0
		var off := 0.0
		if t > 18.0 and t < 24.0:
			off = 16.0  # drifts well off the target
		if frame == 30 * 28:
			game.adjust_pace(1)  # asks for a faster pace
		await _ride(game, bus, t, off)
		if shots.has(frame):
			root.get_viewport().get_texture().get_image().save_png("%s/cad_%s.png" % [out, shots[frame]])
			print("CAPTURE %s/cad_%s.png" % [out, shots[frame]])
	_ride_stop()
	quit()


## One frame of the scripted rider: holds + or − to follow the target (plus `off` rpm) with a
## little wobble.
func _ride(game: Node, bus: Node, t: float, off := 0.0) -> void:
	var want: float = game.logic.target() + off + 2.5 * sin(t * 1.7)
	var key := 0
	if bus.cadence < want - 1.2:
		key = KEY_EQUAL
	elif bus.cadence > want + 1.2:
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


## Rides on the target for 4 s to settle, then for `seconds` with vsync off, and prints the 3D
## view's averages.
func _measure(game: Node, bus: Node, seconds: float) -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var view: SubViewport = game.get("view")
	var rid := view.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	var t := 0.0
	while t < 4.0:
		await _ride(game, bus, t)
		t += 1.0 / 60.0
	var frames := 0
	var sums := {"draws": 0.0, "prims": 0.0, "objects": 0.0, "gpu": 0.0, "cpu": 0.0}
	var start := Time.get_ticks_usec()
	var worst := 0.0
	var last := start
	while Time.get_ticks_usec() - start < seconds * 1e6:
		await _ride(game, bus, t)
		t += 1.0 / 60.0
		var now := Time.get_ticks_usec()
		worst = maxf(worst, (now - last) / 1000.0)
		last = now
		frames += 1
		sums.draws += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
		sums.prims += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
		sums.objects += RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_OBJECTS_IN_FRAME)
		sums.gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
		sums.cpu += RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_ride_stop()
	var elapsed := (Time.get_ticks_usec() - start) / 1000.0
	var n := float(maxi(frames, 1))
	print("MEASURE frames=%d frame_ms=%.3f worst_ms=%.1f view3d: draws=%.1f prims=%.0f objects=%.1f gpu_ms=%.3f cpu_ms=%.3f total_draws=%d" % [
		frames, elapsed / n, worst, sums.draws / n, sums.prims / n, sums.objects / n, sums.gpu / n,
		sums.cpu / n, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)])


func _key(keycode: Key, pressed: bool) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.pressed = pressed
	Input.parse_input_event(ev)
