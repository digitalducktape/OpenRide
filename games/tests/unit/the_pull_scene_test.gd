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
