extends SceneTree
## Safe Cracker's tablet cost, measured on the desktop (needs a window):
##   $GODOT_BIN --path games -s res://tests/measure_safe.gd
## The tablet (PowerVR GX6250) is fill-bound: every 2D layer is blended, so what it pays for is
## how many pixels each frame shades, not the draw calls. This prints, per place, the pixels
## each layer covers (canvas px, clipped to the 1920x1080 canvas; "screens" = /2.07 M) as the
## rider sees it in play, then with the intro card up; how many `MeshBatch2D` batches are rebuilt a
## frame in the intro and in play (should be ~0: static layers redraw only on a change); and the
## CPU time to build each place's room, body and door, and a place change's longest frame.
##
## Pixels: every MeshBatch2D triangle (via `MeshBatch2D.probe`), and each visible ColorRect,
## TextureRect, Panel, PanelContainer and Sprite2D as its rect (text and particles are left out: small).

const SCREEN := Rect2(0, 0, 1920, 1080)
const FULL := 1920.0 * 1080.0

var _session: Node
var _director: Node
var _fill := {}  ## CanvasItem -> pixels of its latest batch
var _flushes := 0
var _verts := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	MeshBatch2D.probe = _on_flush
	_session = root.get_node("Session")
	_director = _session.director
	_session._local.start({"kind": "just_ride", "plan_id": "measure", "difficulty": "standard", "total_sec": -1,
		"segments": [{"game_id": "safe_cracker", "role": "free", "duration_sec": -1,
			"params": {"power_cap_watts": 120.0}}]})
	var deadline := Time.get_ticks_msec() + 30000
	while _director.game == null or not _director.intro_card.visible:
		if Time.get_ticks_msec() > deadline:
			print("MEASURE FAILED: no intro")
			quit(1)
			return
		await process_frame
	# The intro: wait for the build, then count rebuilds a frame.
	for i in 10:
		await process_frame
	var game: Node = _director.game
	_report_fill("intro (place %s)" % SafePlaces.place(game._place).id)
	await _count_rebuilds("intro", 60, null)
	while _director.phase_name() != "PLAYING" and Time.get_ticks_msec() < deadline + 30000:
		await process_frame
	if _director.phase_name() != "PLAYING":
		print("MEASURE FAILED: the game never started")
		quit(1)
		return
	await _count_rebuilds("play, needle sweeping", 120, game)
	# A place change's longest frame, first built and built ahead (desktop ms; the tablet's CPU
	# is several times slower).
	MeshBatch2D.forget_built()
	MeshBatch2D.probe = Callable()  # the fill count is slow: off while timing
	for ahead in [false, true]:
		var line := PackedStringArray()
		for place in ["office", "bank", "museum", "cabin", "lab", "library"]:
			var worst := 0.0
			var t := Time.get_ticks_usec()
			game.change_option("scene", place)
			for i in 3:
				await process_frame
				var now := Time.get_ticks_usec()
				worst = maxf(worst, (now - t) / 1000.0)
				t = now
			line.append("%s %.1f" % [place, worst])
		print("PLACE CHANGE %s, longest frame ms: %s" % ["built ahead" if ahead else "first build", ", ".join(line)])
	MeshBatch2D.probe = _on_flush
	for place in ["office", "bank", "museum", "cabin", "lab", "library"]:
		game.change_option("scene", place)
		for i in 6:
			await process_frame
		_report_fill("play %s" % place)
	game._dial.door_open = 0.6
	game._dial.refresh()
	for i in 3:
		await process_frame
	_report_fill("play library, door half open")
	game._dial.door_open = 0.0
	game.logic.alarm_left = 2.0
	game._handle({"type": "alarm"})
	await create_timer(0.6).timeout
	_report_fill("play library, alarm")
	game.logic.alarm_left = 0.0
	_build_times()
	quit()


func _on_flush(ci: CanvasItem, points: PackedVector2Array, indices: PackedInt32Array) -> void:
	_flushes += 1
	_verts += points.size()
	var xf := ci.get_global_transform()
	var area := 0.0
	for k in range(0, indices.size(), 3):
		var a := xf * points[indices[k]]
		var b := xf * points[indices[k + 1]]
		var c := xf * points[indices[k + 2]]
		var lo := Vector2(minf(a.x, minf(b.x, c.x)), minf(a.y, minf(b.y, c.y)))
		var hi := Vector2(maxf(a.x, maxf(b.x, c.x)), maxf(a.y, maxf(b.y, c.y)))
		if lo.x >= 0.0 and lo.y >= 0.0 and hi.x <= SCREEN.size.x and hi.y <= SCREEN.size.y:
			area += absf((b - a).cross(c - a)) * 0.5
		elif hi.x > 0.0 and hi.y > 0.0 and lo.x < SCREEN.size.x and lo.y < SCREEN.size.y:
			for poly in Geometry2D.intersect_polygons(PackedVector2Array([a, b, c]),
					PackedVector2Array([Vector2.ZERO, Vector2(SCREEN.size.x, 0), SCREEN.size, Vector2(0, SCREEN.size.y)])):
				area += absf(_poly_area(poly))
	_fill[ci] = area


static func _poly_area(p: PackedVector2Array) -> float:
	var s := 0.0
	for i in p.size():
		s += p[i].cross(p[(i + 1) % p.size()])
	return s * 0.5


## Pixels per layer: the MeshBatch2D batches of visible items, then the plain rects.
func _report_fill(label: String) -> void:
	var rows := []
	var total := 0.0
	for ci in _fill.keys():
		if not is_instance_valid(ci) or not (ci as CanvasItem).is_visible_in_tree() or _in_bake(ci):
			continue
		rows.append([str((ci as Node).get_path()).get_file(), _fill[ci]])
	_rects(root, rows)
	rows.sort_custom(func(x, y): return x[1] > y[1])
	var lines := PackedStringArray()
	for r in rows:
		total += r[1]
		if r[1] >= 20000.0:
			lines.append("  %-28s %7.0fk px  %.2f screens" % [r[0], r[1] / 1000.0, r[1] / FULL])
	print("FILL %s: %.2f screens (%.0fk px)" % [label, total / FULL, total / 1000.0])
	print("\n".join(lines))


static func _in_bake(n: Node) -> bool:
	return n.get_viewport() is SubViewport


func _rects(n: Node, rows: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is CanvasLayer and not (n as CanvasLayer).visible:
		return
	if n is SubViewport:
		return  # a bake: its pixels are paid once, not a frame
	if n is Sprite2D and (n as Sprite2D).is_visible_in_tree() and (n as Sprite2D).texture:
		var sp := n as Sprite2D
		var gr := sp.get_global_transform() * sp.get_rect()
		var r2 := gr.intersection(SCREEN)
		if r2.get_area() > 0.0:
			rows.append(["%s/%s (texture)" % [n.get_parent().name, n.name], r2.get_area()])
	if (n is ColorRect or n is TextureRect or n is Panel or n is PanelContainer) and (n as Control).is_visible_in_tree():
		var r := (n as Control).get_global_rect().intersection(SCREEN)
		if n is PanelContainer and (n as Control).get_theme_stylebox("panel") is StyleBoxEmpty:
			r = Rect2()
		if r.get_area() > 0.0:
			rows.append(["%s/%s" % [n.get_parent().name, n.name], r.get_area()])
	for c in n.get_children():
		_rects(c, rows)


## MeshBatch2D batches rebuilt a frame (should be ~0), and the process time.
func _count_rebuilds(label: String, frames: int, game: Node) -> void:
	_flushes = 0
	_verts = 0
	var proc := 0.0
	for f in frames:
		if game:
			game.logic.reading = 50.0 + 45.0 * sin(f * 0.05)
		await process_frame
		proc += Performance.get_monitor(Performance.TIME_PROCESS)
	print("REBUILDS %s: %.2f batches/frame, %.0f vertices/frame, process %.2f ms/frame (desktop)" % [
		label, float(_flushes) / frames, float(_verts) / frames, proc * 1000.0 / frames])


## CPU to build each place's batches (what a place change costs, once).
func _build_times() -> void:
	var dial := SafeDial.new()
	var door := SafeDoor.new()
	door.dial = dial
	for i in SafePlaces.count():
		dial.colour = SafePlaces.place(i).safe
		dial.accent = SafePlaces.place(i).accent
		dial.place_index = i
		var t0 := Time.get_ticks_usec()
		var m := MeshBatch2D.new()
		SafePlaces.build_room(m, i)
		var room_v := m.vertex_count()
		var t1 := Time.get_ticks_usec()
		m = MeshBatch2D.new()
		var body := SafeBody.new()
		body.place_index = i
		body.build(m)
		var body_v := m.vertex_count()
		var t2 := Time.get_ticks_usec()
		m = MeshBatch2D.new()
		door.build(m)
		var t3 := Time.get_ticks_usec()
		var door_v := m.vertex_count()
		m = MeshBatch2D.new()
		SafeBody.build_vault(m, dial.colour)
		var t4 := Time.get_ticks_usec()
		print("BUILD %-8s room %5.1f ms (%d verts)  body %5.1f ms (%d)  door %5.1f ms (%d)  vault %5.1f ms (%d)" % [
			SafePlaces.place(i).id, (t1 - t0) / 1000.0, room_v, (t2 - t1) / 1000.0, body_v, (t3 - t2) / 1000.0, door_v,
			(t4 - t3) / 1000.0, m.vertex_count()])
		body.free()
	door.free()
	dial.free()
