class_name KartPerfLog
extends RefCounted
## Kart Race's developer frame-cost log (#43), only with KartRace.DEV_TUNING: every PERF_LOG_SEC
## it prints one `OPENRIDE_GAMES kart_race perf` line (the game's, the ticks', the views' and the
## HUD's time, the process step, the frame, every viewport's render time, draw calls). Off in
## every build: KartRace makes one only when DEV_TUNING is set.

const PERF_LOG_SEC := 5.0

var usec := 0
var frames := 0
var dc_max := 0  ## the most draw calls in one frame since the last perf line
var ticks := 0  ## logic ticks since the last perf line, and their time
var tick_usec := 0
var sync_usec := 0  ## _sync_views and _update_hud time
var hud_usec := 0
var proc_ms := 0.0  ## the engine's process time per frame, summed
var render_cpu := 0.0  ## every viewport's measured render time, summed
var render_gpu := 0.0
var vps: Array[Viewport] = []
## Each viewport's last measured render time: a viewport that didn't render this frame (an idle
## bake) keeps reporting its last render's time, so only a changed value counts.
var vp_last := {}
var vp_renders := 0  ## viewport renders counted since the last perf line
var frame_ms := 0.0
var frame_max := 0.0
var game_max := 0
var first: Probe
var last: Probe
var left := PERF_LOG_SEC


## Stamps the time it processes (first and last in the frame, by priority).
class Probe extends Node:
	var stamp := 0
	var prev := 0

	func _process(_delta: float) -> void:
		prev = stamp
		stamp = Time.get_ticks_usec()


## Adds the two probes to `tree`'s root (deferred), first and last in the frame.
func add_probes(tree: SceneTree) -> void:
	first = Probe.new()
	first.process_priority = -1000000
	last = Probe.new()
	last.process_priority = 1000000
	tree.root.add_child.call_deferred(first)
	tree.root.add_child.call_deferred(last)


func free_probes() -> void:
	for probe in [first, last]:
		if probe and is_instance_valid(probe):
			probe.queue_free()


## One frame of `game` (its _frame took `started` to now): sums it. `view` is the 3D view (always
## counted). True when the line is due: the caller then calls `flush`.
func sample(game: Node, view: Viewport, delta: float, started: int) -> bool:
	usec += Time.get_ticks_usec() - started
	frames += 1
	game_max = maxi(game_max, Time.get_ticks_usec() - started)
	# The whole process step (the first and last _process of the frame, the probes) and the frame
	# (first probe to first probe), both for the frame before this one.
	if first and first.prev > 0:
		proc_ms += (last.stamp - first.prev) / 1000.0 if last.stamp > first.prev else 0.0
		var ms := (first.stamp - first.prev) / 1000.0
		frame_ms += ms
		frame_max = maxf(frame_max, ms)
	for vp: Viewport in vps:
		if is_instance_valid(vp):
			var rid := vp.get_viewport_rid()
			var cpu := RenderingServer.viewport_get_measured_render_time_cpu(rid)
			var always := vp == view or vp == game.get_viewport()
			if always or cpu != float(vp_last.get(rid, -1.0)):
				render_cpu += cpu
				render_gpu += RenderingServer.viewport_get_measured_render_time_gpu(rid)
				vp_renders += 1
			vp_last[rid] = cpu
	dc_max = maxi(dc_max, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
	left -= delta
	return left <= 0.0


## Prints the line and starts the next period. `game_state` fills the line's tail: [karts, track
## id, "_rev" or "", flow name, tracker state, tier].
func flush(game: Node, game_state: Array) -> void:
	var n := maxi(frames, 1)
	print("OPENRIDE_GAMES kart_race perf game_ms=%.2f ticks=%.2f tick_ms=%.2f sync_ms=%.2f hud_ms=%.2f process_ms=%.2f frame_ms=%.2f frame_max_ms=%.1f game_max_ms=%.1f render_cpu_ms=%.2f render_gpu_ms=%.2f viewports=%d vp_renders=%.2f fps=%d draw_calls=%d draw_calls_max=%d objects=%d primitives=%d karts=%d track=%s%s flow=%s tracker=%d tier=%d" % ([
		usec / 1000.0 / n,
		float(ticks) / n,
		tick_usec / 1000.0 / maxi(ticks, 1),
		sync_usec / 1000.0 / n,
		hud_usec / 1000.0 / n,
		proc_ms / n,
		frame_ms / n,
		frame_max,
		game_max / 1000.0,
		render_cpu / n,
		render_gpu / n,
		vps.size(),
		float(vp_renders) / n,
		Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		dc_max,
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)] + game_state))
	usec = 0
	frames = 0
	ticks = 0
	tick_usec = 0
	sync_usec = 0
	hud_usec = 0
	proc_ms = 0.0
	render_cpu = 0.0
	render_gpu = 0.0
	frame_ms = 0.0
	frame_max = 0.0
	game_max = 0
	# Every viewport that renders (the 3D view, the bakes, the screen), measured.
	vp_renders = 0
	vp_last.clear()
	vps.clear()
	vps.append(game.get_viewport())
	for vp: Node in game.find_children("*", "SubViewport", true, false):
		vps.append(vp)
	for vp: Viewport in vps:
		RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
	dc_max = 0
	left = PERF_LOG_SEC
