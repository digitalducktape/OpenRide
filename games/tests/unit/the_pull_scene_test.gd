extends GdUnitTestSuite
## The Pull's scene wiring (#79): every HUD number agrees with every other (the rider's ask), the
## status widget's budget, the modes, the result's stats and its best-pull stars.

const DT := 1.0 / 60.0
const BESTS := "user://test_the_pull_bests.cfg"

var game: Node


func before_test() -> void:
	PullBests.path = BESTS
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BESTS))
	game = load("res://games/the_pull/ThePull.tscn").instantiate()
	game.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(game.hud)
	add_child(game)
	game.prepare({"game_id": "the_pull", "role": "free", "difficulty": "standard", "duration_sec": -1,
		"end_mode": "game", "seed": 7, "params": {"ftp_watts": 200.0}})
	game.start()
	game.set_process(false)
	InputBus.sensors_ok = true


func after_test() -> void:
	game.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(BESTS))
	PullBests.path = PullBests.DEFAULT_PATH


func _ride(seconds: float, watts: float) -> void:
	InputBus.power = watts
	InputBus.sensors_ok = true
	for i in roundi(seconds / DT):
		game._on_frame(DT)


func _texts(node: Node) -> Array:
	var out := []
	for label: Label in node.find_children("*", "Label", true, false):
		out.append(label.text)
	return out


func test_the_sleds_need_agrees_in_the_widget_and_the_ride_metrics() -> void:
	_ride(PullLogic.SET_SEC + 20.0, 200.0)
	assert_int(game.logic.phase).is_equal(PullLogic.Phase.PULL)
	var need: int = game.logic.shown_need()
	assert_int(game.shown_need()).is_equal(need)
	assert_float(game.hud.metrics.power_low).is_equal(float(need))
	assert_str(game._status.chip_label.text).is_equal("SLED NEEDS %d W" % need)


func test_the_widget_never_shows_the_riders_watts() -> void:
	_ride(PullLogic.SET_SEC + 10.0, 237.0)
	for text in _texts(game._status):
		assert_str(text).not_contains("237")


func test_the_distance_agrees_with_the_logic() -> void:
	_ride(PullLogic.SET_SEC + 30.0, 200.0)
	var shown := PullLogic.shown_m(game.logic.distance)
	assert_str(game._status.distance_label.text).is_equal(str(shown))


func test_between_pulls_the_power_band_clears() -> void:
	_ride(PullLogic.SET_SEC + 1.0, 200.0)
	_ride(60.0, 0.0)  # stall
	assert_int(game.logic.phase).is_not_equal(PullLogic.Phase.PULL)
	assert_int(game.shown_need()).is_equal(-1)
	assert_float(game.hud.metrics.power_low).is_equal(-INF)


func test_the_dig_in_chip_counts_down_to_the_stall() -> void:
	_ride(PullLogic.SET_SEC + 15.0, 200.0)
	InputBus.power = 0.0
	while not game.logic.warned:
		game._on_frame(DT)
	assert_str(game._status.chip_state()).is_equal("dig_in")
	assert_str(game._status.chip_label.text).is_equal("DIG IN! %d" % ceili(PullLogic.STALL_SEC - game.logic.stall_sec))


func test_the_widget_fits_its_budget_with_the_longest_texts() -> void:
	var status := PullStatus.new(game.look)
	add_child(status)
	status.set_distance(1888)
	status.set_pull(5, 5)
	status.set_chip("need", 1888)
	var size := status.get_combined_minimum_size()
	assert_float(size.x).is_less_equal(820.0)
	assert_float(size.y).is_less_equal(120.0)
	for label: Label in status.find_children("*", "Label", true, false):
		assert_int(label.get_theme_font_size("font_size")).is_greater_equal(HudTheme.SMALL)
	status.free()


func test_modes_from_the_segment() -> void:
	assert_str(game._mode_for({"duration_sec": -1})).is_equal("open")
	assert_str(game._mode_for({"duration_sec": 600, "end_mode": "game", "params": {"rounds": 2}})).is_equal("rounds")
	assert_str(game._mode_for({"duration_sec": 600, "end_mode": "game", "params": {}})).is_equal("timed")
	assert_str(game._mode_for({"duration_sec": 600, "end_mode": "timer", "params": {}})).is_equal("timed")


func test_declarations_match_the_issue() -> void:
	var info: GameInfo = game.declared()
	assert_str(info.timed_end_mode).is_equal("game")
	assert_array(info.roles).is_empty()
	assert_array(info.supports).contains_exactly(["rounds", "minutes", "open"])
	assert_bool(info.effort_in_just_ride).is_true()
	assert_bool(info.stars_per_minute).is_false()


func test_stars_come_from_the_best_pull_not_the_sum() -> void:
	_ride(PullLogic.SET_SEC + 5.0, 200.0)
	game._best_pull_points = 2500.0  # one pull at 2 stars; the session's sum may be larger
	var result: Dictionary = game.finish()
	assert_int(result.stars).is_equal(2)
	for key in ["distance_m", "best_distance_m", "peak_power", "pull_sec", "pulls", "full_pulls"]:
		assert_bool(result.stats.has(key)).override_failure_message("stats lacks %s" % key).is_true()


func test_peak_power_is_the_raw_reading_the_metrics_showed() -> void:
	_ride(PullLogic.SET_SEC + 2.0, 180.0)
	_ride(1.0, 333.0)
	_ride(2.0, 180.0)
	assert_int(game.finish().stats.peak_power).is_equal(333)


func test_ending_mid_pull_counts_it_and_saves_the_best() -> void:
	_ride(PullLogic.SET_SEC + 40.0, 200.0)
	var metres: float = game.logic.distance
	game.finishing = true
	game._on_finish_requested()
	assert_bool(game.has_ended()).is_true()
	assert_float(PullBests.get_best("standard")).is_equal_approx(snappedf(metres, 0.01), 0.01)


func test_the_last_result_ends_the_segment_in_game_time() -> void:
	_ride(PullLogic.SET_SEC + 1.0, 200.0)
	game._finish_soon()
	_ride(1.0, 0.0)
	# Game frames count it down, so a pause (no game frames) holds it.
	assert_bool(game.has_ended()).is_false()
	_ride(float(game.RESULT_END_DELAY), 0.0)
	assert_bool(game.has_ended()).is_true()


func test_the_intro_target_comes_from_the_segment() -> void:
	var seg := {"difficulty": "hard", "params": {"ftp_watts": 250.0, "d_ref_m": 280.0, "full_factor": 1.1}}
	assert_str(game.target_text(seg)).is_equal("Reach the Full Pull line at %d m" % PullLogic.shown_m(280.0 * 1.1))
	# Without params, the difficulty's own sled.
	assert_str(game.target_text({"difficulty": "easy"})).is_equal(
		"Reach the Full Pull line at %d m" % PullLogic.shown_m(PullLogic.D_REF.easy * PullLogic.FULL_FACTOR))
	PullBests.offer("hard", 187.4)
	assert_str(game.target_text(seg)).is_equal("Your best: 187 m")
	var art: Control = game.intro_visual()
	assert_object(art).is_not_null()
	art.free()


## Where a point in the rig's space lands on the stage (canvas pixels), through the 3D view.
func _on_stage(rig_point: Vector3) -> Vector2:
	var world: PullWorld = game.world
	var view: SubViewport = game.get_node("View3D")
	var p: Vector2 = world.camera.unproject_position(world.get_node("Rig").to_global(rig_point))
	return p / Vector2(view.size) * Stage.visible_size - Stage.pad


## The stage rect a box in the rig's space covers (its eight corners).
func _stage_rect(centre: Vector3, half: Vector3) -> Rect2:
	var rect := Rect2(_on_stage(centre), Vector2.ZERO)
	for x in [-1.0, 1.0]:
		for y in [-1.0, 1.0]:
			for z in [-1.0, 1.0]:
				rect = rect.expand(_on_stage(centre + half * Vector3(x, y, z)))
	return rect


func test_nothing_is_clipped_by_the_frame_or_a_hud_panel() -> void:
	_ride(PullLogic.SET_SEC + 5.0, 200.0)  # facing the track, mid-pull
	game.hud.show_message("FULL PULL! 1888 m", GameTheme.GOOD)  # the longest centre message
	game._status.set_distance(1888)
	game._status.set_chip("need", 1888)
	for i in 4:
		await get_tree().process_frame
	var stage := Rect2(Vector2.ZERO, Vector2(HudTheme.W, HudTheme.H))
	var hud: Hud = game.hud
	var panels := {"ride panel": hud.ride_panel, "clock": hud.clock_panel, "pause": hud.pause_button,
		"end": hud.end_button, "status widget": game._status, "message": hud._message}
	var mirror := _stage_rect(PullWorld.MIRROR, Vector3(PullWorld.MIRROR_SIZE.x / 2.0 + 0.012, PullWorld.MIRROR_SIZE.y / 2.0 + 0.012, 0.01))
	var things := {"mirror": mirror}
	for side in [-1.0, 1.0]:
		things["fist %d" % side] = _stage_rect(PullWorld.BARS + Vector3(side * 0.24, 0.035, 0.02), Vector3(0.08, 0.07, 0.07))
	for thing in things:
		var rect: Rect2 = things[thing]
		assert_float(rect.size.x).override_failure_message("%s projects to nothing" % thing).is_greater(40.0)
		assert_bool(stage.encloses(rect)).override_failure_message("%s %s leaves the frame" % [thing, rect]).is_true()
		for name in panels:
			var panel: Control = panels[name]
			var box := panel.get_global_rect()
			if name == "message":
				# The label spans the row; its text is centred.
				var w := panel.get_theme_font("font").get_string_size(panel.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
					panel.get_theme_font_size("font_size")).x
				box = Rect2(box.get_center().x - w / 2.0, box.position.y, w, box.size.y)
			assert_bool(rect.intersects(box)).override_failure_message("%s %s is under the %s %s" % [thing, rect, name, box]).is_false()
	# The HUD's own pieces stay on the stage.
	for name in panels:
		if name != "message":
			assert_bool(stage.encloses((panels[name] as Control).get_global_rect())).override_failure_message(name).is_true()
