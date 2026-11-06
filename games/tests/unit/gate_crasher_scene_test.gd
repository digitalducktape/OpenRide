extends GdUnitTestSuite
## Gate Crasher's scene wiring (#80): the camera declaration, the intro copy from the segment, one
## place for the watts, scoring only while pedalling, the summary, and the bounds: nothing clipped
## by the frame or a HUD panel.

const DT := 1.0 / 60.0
const FRAME := Vector2(1920.0, 1080.0)
const STATUS_BUDGET := Vector2(820.0, 120.0)
const HUD_BOTTOM := 320.0  ## the ride panel's bottom edge, the lowest of the top bar's panels
const SHADERS := ["ground", "scenery", "sky", "crowd", "marker"]

var game: Node


func before_test() -> void:
	game = load("res://games/gate_crasher/GateCrasher.tscn").instantiate()
	game.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(game.hud)
	add_child(game)
	game.prepare({"game_id": "gate_crasher", "role": "work", "difficulty": "standard", "duration_sec": -1,
		"end_mode": "game", "seed": 7, "params": {"ftp_watts": 200.0, "pace_watts": 110.0, "window_sec": 1.2, "fences": 8}})
	game.start()
	game.set_process(false)
	InputBus.sensors_ok = true
	InputBus.tracker_state = InputBus.TRACKER_TRACKING
	InputBus.standing = false
	InputBus.cadence = 85.0
	Effort.begin_segment(false)
	Effort.set_live(true)


func after_test() -> void:
	Effort.set_live(false)
	game.free()
	InputBus.standing = false
	InputBus.tracker_state = InputBus.TRACKER_OFF


func _ride(seconds: float, watts := 110.0) -> void:
	InputBus.power = watts
	for i in roundi(seconds / DT):
		game._on_frame(DT)


func _ride_to_line() -> void:
	InputBus.power = 110.0
	var guard := 0
	while game.logic.distance < game.logic.line_s(game.logic.fence) and guard < 10000:
		game._on_frame(DT)
		guard += 1


func _texts(node: Node) -> Array:
	var out := []
	for label: Label in node.find_children("*", "Label", true, false):
		out.append(label.text)
	return out


func _project(camera: Camera3D, at: Vector3) -> Vector2:
	return camera.unproject_position(at) * FRAME / Vector2(camera.get_viewport().size)


func test_it_declares_the_camera_so_camera_off_circuits_skip_it() -> void:
	var info: GameInfo = game.declared()
	assert_str(info.tracker_mode).is_equal("lean_stand")
	assert_bool(info.uses_camera()).is_true()
	assert_array(info.roles).is_equal(["work"])


func test_every_shader_compiles() -> void:
	for name in SHADERS:
		var shader := load("res://games/gate_crasher/shaders/%s.gdshader" % name) as Shader
		assert_bool(shader.get_shader_uniform_list().size() > 0).override_failure_message(name).is_true()


func test_the_intro_copy_comes_from_the_segment() -> void:
	var seg := {"difficulty": "hard", "params": {"pace_watts": 137.0, "fences": 6, "window_sec": 1.4}}
	assert_str(game.target_text(seg)).is_equal("6 fences a round at 137 W")
	assert_str(game.how_to_text(seg)).contains("0.7 s")


func test_the_intro_picture_is_a_real_drawing() -> void:
	var art: Control = auto_free(game.intro_visual())
	assert_object(art).is_not_null()
	assert_float(art.custom_minimum_size.x).is_greater(400.0)


func test_watts_show_once_through_the_ride_panel() -> void:
	_ride(5.0, 237.0)
	for text: String in _texts(game._status):
		assert_str(text).not_contains("237")
		assert_str(text).not_contains("110")
		assert_str(text).not_contains("W")
		assert_str(text).not_contains("×")
	assert_float(game.hud.metrics.power_low).is_equal(110.0)


func test_a_stand_on_the_line_scores_and_the_status_counts_it() -> void:
	_ride_to_line()
	_ride(0.4)
	InputBus.standing = true
	var before: float = Effort.score
	_ride(3.0)
	InputBus.standing = false
	assert_int(game.logic.clears).is_equal(1)
	assert_float(Effort.score).is_greater(before)
	assert_str(game._status.fence_label.text).is_equal("FENCE 2/8")
	assert_str(game._status.chip_state()).is_equal("clear")


func test_a_rail_down_shows_on_the_status_and_takes_points() -> void:
	_ride_to_line()
	_ride(3.0)
	assert_int(game.logic.faults).is_equal(4)
	assert_str(game._status.chip_label.text).is_equal("4 FAULTS")
	assert_bool(game.hud.is_showing_message()).is_true()


func test_nothing_scores_without_pedalling() -> void:
	_ride(4.0)
	var score: float = Effort.score
	InputBus.cadence = 0.0
	_ride(5.0, 0.0)
	assert_float(Effort.score).is_equal(score)
	assert_str(game._status.chip_label.text).is_equal("PEDAL ON")


func test_a_lost_camera_shows_the_circle() -> void:
	_ride(2.0)
	InputBus.tracker_state = InputBus.TRACKER_FACE_LOST
	_ride(1.0)
	assert_int(game.logic.phase).is_equal(GateLogic.Phase.CIRCLE)
	assert_str(game._status.chip_label.text).is_equal("CIRCLING")


func test_the_summary_tiles_come_from_the_stats() -> void:
	_ride_to_line()
	_ride(3.0)
	var result: Dictionary = game.finish()
	for tile: Dictionary in game.declared().summary_stats:
		assert_bool(result.stats.has(tile.key)).override_failure_message(tile.key).is_true()
		if tile.has("of"):
			assert_bool(result.stats.has(tile.of)).is_true()
	assert_int(result.stats.fences).is_equal(1)
	assert_int(result.stats.faults).is_equal(4)
	assert_bool(result.stats.has("avg_power")).is_true()


# --- Bounds ---

func test_the_status_widget_fits_its_budget_with_the_longest_texts() -> void:
	var status := GateStatus.new()
	add_child(status)
	status.set_fences(GateLogic.max_fences())
	status.set_progress(GateLogic.max_fences(), 88, [] as Array[int])
	for state: Array in [["clear", 0], ["faults", 32], ["circling", 0], ["pedal", 0]]:
		status.set_chip(state[0], state[1])
		await await_idle_frame()
		var size := status.get_combined_minimum_size()
		assert_float(size.x).override_failure_message("%s: %s" % [state, size]).is_less_equal(STATUS_BUDGET.x)
		assert_float(size.y).override_failure_message("%s: %s" % [state, size]).is_less_equal(STATUS_BUDGET.y)
	status.free()


func test_the_ears_stay_in_the_frame_and_clear_of_the_hud_and_the_horse_fills_only_the_bottom() -> void:
	var world: GateWorld = game.world
	world.update_view(0.0, 0.0, 0.0, 0.0, 0.0, 7.0)
	var horse: MeshInstance3D = world.get_node("Rig/Horse")
	var box := horse.global_transform * horse.get_aabb()
	var top := box.position.y + box.size.y
	var tip := Vector3(0.0, top, box.position.z + box.size.z * 0.3)
	var at := _project(world.camera, tip)
	assert_float(at.y).is_between(HUD_BOTTOM, FRAME.y)
	# The poll, under the ears: the horse keeps to the bottom third of the picture.
	var rig: Node3D = world.get_node("Rig")
	var poll := rig.global_transform * Vector3(0.0, GateWorld.EYE_HEIGHT - 0.6, -1.78)
	assert_float(_project(world.camera, poll).y).is_greater(FRAME.y * 0.62)
	# Wide across the bottom: never a narrow column.
	var left := rig.global_transform * Vector3(-0.3, GateWorld.EYE_HEIGHT - 0.7, -1.78)
	var right := rig.global_transform * Vector3(0.3, GateWorld.EYE_HEIGHT - 0.7, -1.78)
	assert_float(_project(world.camera, right).x - _project(world.camera, left).x).is_greater(200.0)


func test_a_fence_at_the_take_off_line_is_whole_in_the_frame_and_under_the_hud() -> void:
	var world: GateWorld = game.world
	var l: GateLogic = game.logic
	for k in l.fences:
		var line := l.line_s(k)
		world.update_view(0.0, line, GateLogic.V_PACE, 0.0, 0.0, 7.0)
		var f := GateCourse.frame(l.fence_s(k))
		var corners := [Vector3(-GateMeshes.RAIL_WIDTH / 2.0, 0.0, 0.0), Vector3(GateMeshes.RAIL_WIDTH / 2.0, 0.0, 0.0),
			Vector3(-GateMeshes.RAIL_WIDTH / 2.0, 1.75, 0.0), Vector3(GateMeshes.RAIL_WIDTH / 2.0, 1.75, 0.0)]
		for corner: Vector3 in corners:
			var at := _project(world.camera, f * corner)
			assert_float(at.x).override_failure_message("fence %d x %s" % [k, at]).is_between(0.0, FRAME.x)
			assert_float(at.y).override_failure_message("fence %d y %s" % [k, at]).is_between(HUD_BOTTOM, FRAME.y)


func test_the_take_off_line_shows_either_side_of_the_horse_three_seconds_out() -> void:
	var world: GateWorld = game.world
	var l: GateLogic = game.logic
	var s := l.line_s(0) - GateLogic.BEATS[0] * GateLogic.V_PACE
	world.update_view(0.0, s, GateLogic.V_PACE, 0.0, 0.0, 7.0)
	var at := _project(world.camera, GateCourse.frame(l.line_s(0)).origin)
	assert_float(at.y).is_between(HUD_BOTTOM, FRAME.y * 0.62)
