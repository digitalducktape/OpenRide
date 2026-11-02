extends GdUnitTestSuite
## Keepy Uppy's scene wiring (#77): the camera only with Steer on, scoring and the pop's penalty
## through the framework, the stats at finish, the HUD widget's states, and the world following
## the logic.

var game: Node


func _make(steer := "off", seg_extra := {}) -> Node:
	GameOptions.set_value(GameRegistry.info("keepy_uppy"), "steer", steer)
	var g: Node = load("res://games/keepy_uppy/KeepyUppy.tscn").instantiate()
	g.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(g.hud)
	add_child(g)
	var seg := {"game_id": "keepy_uppy", "role": "free", "difficulty": "standard", "duration_sec": -1,
		"end_mode": "game", "seed": 7, "params": {"ftp_watts": 200.0, "weight_watts": 80.0}}
	seg.merge(seg_extra, true)
	g.prepare(seg)
	return g


func before_test() -> void:
	game = _make()
	game.start()
	game.set_process(false)


func after_test() -> void:
	if is_instance_valid(game):
		game.free()
	GameOptions.set_value(GameRegistry.info("keepy_uppy"), "steer", "off")


func test_the_camera_runs_only_with_steer_on() -> void:
	assert_str(game.tracker_mode_for_segment({})).is_equal("off")
	game.free()
	game = _make("on")
	assert_str(game.tracker_mode_for_segment({})).is_equal("lean_x")
	assert_bool(game.logic.steer).is_true()
	assert_str(game.how_to_text({})).contains("lean")


func test_the_declarations_match_the_issue() -> void:
	var i: GameInfo = game.info()
	assert_array(i.validate()).is_empty()
	assert_array(i.roles).is_equal(["work"])
	assert_str(i.tracker_mode).is_equal("off")
	assert_bool(i.effort_in_just_ride).is_true()
	assert_bool(i.stars_per_minute).is_true()
	assert_array(i.supports).contains_exactly_in_any_order(["rounds", "minutes", "open"])


func test_the_target_line_names_the_mid_band_power() -> void:
	# 80 W of balloon floats at mid-air at 80 / (1 - 0.45 × 0.5) ≈ 103 W, rounded to 105.
	assert_str(game.target_text({"params": {"ftp_watts": 200.0, "weight_watts": 80.0}})).contains("105 W")


func test_a_pop_takes_fifty_points_off_through_the_framework() -> void:
	Effort.begin_segment(false)
	Effort.set_live(true)
	game.award(500.0)
	var before := Effort.score
	assert_float(before).is_greater(0.0)
	game._handle({"type": "pop", "points": 50.0})
	assert_float(Effort.score).is_equal_approx(before - 50.0, 0.01)
	Effort.set_live(false)


func test_stats_are_built_at_finish() -> void:
	for i in 30:
		game._on_frame(1.0 / 60.0)
	assert_dict(game.stats).is_empty()
	var result: Dictionary = game.finish()
	for key in ["pops", "seconds_high", "birds_shaken", "avg_power", "downdrafts", "downdrafts_beaten", "best_air"]:
		assert_bool(result.stats.has(key)).override_failure_message("stats lacks %s" % key).is_true()
	assert_str(result.variant).is_equal("")


func test_the_balloon_follows_the_logic_height() -> void:
	game.logic.h = 0.9
	game.world.update_view(1.0 / 60.0, game.logic)
	var high: Vector3 = game.world.balloon_position()
	game.logic.h = 0.1
	game.world.update_view(1.0 / 60.0, game.logic)
	assert_float(high.y - game.world.balloon_position().y).is_greater(3.5)


func test_a_rounds_ride_ends_after_its_minutes() -> void:
	game.free()
	game = _make("off", {"params": {"ftp_watts": 200.0, "rounds": 1}})
	game.start()
	game.set_process(false)
	var ended := [false]
	game.ended.connect(func(): ended[0] = true)
	game.played_sec = 59.0
	game._on_frame(1.0 / 60.0)
	assert_bool(ended[0]).is_false()
	game.played_sec = 60.0
	game._on_frame(1.0 / 60.0)
	assert_bool(ended[0]).is_true()


func test_the_status_widget_fits_its_budget_and_shows_every_warning() -> void:
	var s: KeepyStatus = game._status
	for warning in KeepyStatus.WARNINGS.keys():
		s.set_state(KeepyLogic.Band.HIGH, warning, 3, 0.5, true, -1.0)
		s.reset_size()
		await get_tree().process_frame
		assert_float(s.get_combined_minimum_size().x).is_less_equal(800.0)
		assert_float(s.get_combined_minimum_size().y).is_less_equal(125.0)
	for l: Label in s.find_children("*", "Label", true, false):
		assert_int(l.get_theme_font_size("font_size")).is_greater_equal(HudTheme.SMALL)
