extends GdUnitTestSuite
## Watt Lane's scene with the framework (#78): every power number on the HUD agrees (the ride
## panel shows the rules' smoothed watts and turns gold exactly inside the rules' band), the status
## widget fits its slot with the longest texts and its countdown follows the announced jump, the
## world bends its rails along the course, and the result carries the stats.

const DT := 1.0 / 30.0
const SEGMENT := {"game_id": "watt_lane", "role": "work", "difficulty": "standard",
	"duration_sec": 300, "end_mode": "timer", "seed": 21, "effort": true, "params": {"ftp_watts": 200}}


func _game(segment := SEGMENT) -> Game:
	var game: Game = auto_free(load("res://games/watt_lane/WattLane.tscn").instantiate())
	game.hud = auto_free(Hud.new())
	add_child(game.hud)
	add_child(game)
	game.prepare(segment)
	game.start(segment)
	return game


## Steps the game's frame with a fixed power reading (no InputBus: the logic and the view only).
func _ride(game: Game, seconds: float, power: float) -> void:
	for i in roundi(seconds / DT):
		var events: Array[Dictionary] = game.logic.step(DT, power)
		for e in events:
			game._handle(e)
		var up: Dictionary = game.logic.upcoming()
		game.world.update_view(DT, game.logic.course, game.logic.time, game.logic.smoothed, game.logic.in_lane,
			float(up.get("at", -1.0)), bool(up.get("up", true)))
		game._update_status()


func test_the_ride_panel_shows_the_rules_power_and_its_gold_matches_the_band() -> void:
	var game := _game()
	var metrics: RideMetrics = game.hud.metrics
	var hi: int = game.logic.lane_hi()
	_ride(game, 4.0, float(hi))
	assert_float(metrics.shown_power()).is_equal(game.logic.smoothed)
	assert_int(roundi(metrics.shown_power())).is_equal(game.logic.shown_watts)
	assert_bool(game.logic.in_lane).is_true()
	assert_object(metrics.power_color(metrics.shown_power())).is_equal(HudTheme.STAR_ON)
	_ride(game, 4.0, float(hi) + 1.0)
	assert_bool(game.logic.in_lane).is_false()
	assert_object(metrics.power_color(metrics.shown_power())).is_equal(HudTheme.WARN)
	var status: WattLaneStatus = _status(game)
	assert_str(status.lane.text).is_equal("%d–%d" % [game.logic.lane_lo(), game.logic.lane_hi()])
	assert_str(status.alert_kind()).is_equal(WattLaneStatus.ALERT_EASE)


func test_every_frame_the_in_lane_verdict_and_the_gold_agree() -> void:
	var game := _game()
	var metrics: RideMetrics = game.hud.metrics
	for i in 900:
		var t: float = game.logic.time
		var power: float = game.logic.course.visual_centre_at(t + 1.5) + 30.0 * sin(t * 0.7)
		_ride(game, DT, power)
		var gold: bool = metrics.power_color(metrics.shown_power()) == HudTheme.STAR_ON
		assert_bool(gold).override_failure_message("t=%.1f W=%d band=%s" % [t, game.logic.shown_watts, game.logic.band()]).is_equal(game.logic.in_lane)


func test_the_countdown_chip_names_the_next_lane_and_counts_down() -> void:
	var game := _game()
	var course: WattLaneCourse = game.logic.course
	var j := course.next_jump_after(0.0)
	var status := _status(game)
	_ride(game, course.times[j] - WattLaneLogic.ANNOUNCE_SEC - 0.5, float(course.watts[0]))
	assert_bool(status.countdown.visible).is_false()
	_ride(game, 1.0, float(course.watts[0]))
	assert_bool(status.countdown.visible).is_true()
	var w := course.watts[j]
	var verb := "UP" if w > course.watts[j - 1] else "DOWN"
	assert_str(status.countdown_label.text).is_equal("%s %d–%d in 5" % [verb, w - game.logic.width / 2, w + game.logic.width / 2])
	_ride(game, 3.0, float(course.watts[0]))
	assert_str(status.countdown_label.text).ends_with("in 2")
	_ride(game, 2.5, float(w))
	assert_bool(status.countdown.visible).is_false()


func test_the_status_widget_fits_its_slot_with_the_longest_texts() -> void:
	var status: WattLaneStatus = auto_free(WattLaneStatus.new(load("res://games/watt_lane/WattLane.gd").look))
	add_child(status)
	status.set_lane(880, 960)  # 3 digits: FTP 500 tops out near 425
	status.set_info(100, 2.5)
	status.set_alert(WattLaneStatus.ALERT_PEDAL)
	await get_tree().process_frame
	_assert_fits(status)
	status.set_countdown(false, 880, 960, 5)
	await get_tree().process_frame
	_assert_fits(status)
	assert_bool(status.info.visible).is_false()  # the chip takes the row
	status.set_countdown(true, 0, 0, -1)
	await get_tree().process_frame
	assert_bool(status.info.visible).is_true()
	assert_bool(status.alert.visible).is_true()


func _assert_fits(status: WattLaneStatus) -> void:
	var size := status.get_combined_minimum_size()
	assert_float(size.x).is_less_equal(850.0)
	assert_float(size.y).is_less_equal(120.0)
	for l in [status.lane, status.caption, status.info, status.countdown_label, status.alert_label]:
		if l.visible:
			assert_int(l.get_theme_font_size("font_size")).is_greater_equal(34)


func test_the_rails_follow_the_course_ahead() -> void:
	var game := _game()
	_ride(game, 1.0, 120.0)
	var world: WattLaneWorld = game.world
	var t: float = game.logic.time
	for i in [0, 20, 63]:
		var expect := world.x_of(game.logic.course.visual_centre_at(t + i * WattLaneWorld.ROW_LEN / WattLaneWorld.SPEED))
		assert_float(world.get("_offsets")[i]).is_equal_approx(expect, 0.001)
	assert_float(world.bike_x).is_equal_approx(world.x_of(game.logic.smoothed), 0.5)


func test_the_road_is_a_watt_scale() -> void:
	var world: WattLaneWorld = auto_free(WattLaneWorld.new())
	add_child(world)
	world.setup(200.0, 40)
	assert_float(world.x_of(0.575 * 200.0)).is_equal_approx(0.0, 0.001)
	assert_float(world.x_of(200.0)).is_equal_approx(WattLaneWorld.ROAD_HALF, 0.001)
	assert_float(world.x_of(2000.0)).is_equal_approx(WattLaneWorld.ROAD_HALF + WattLaneWorld.SHOULDER, 0.001)
	assert_float(world.x_of(0.0)).is_equal_approx(-WattLaneWorld.ROAD_HALF - WattLaneWorld.SHOULDER, 0.001)


func test_the_result_carries_the_stats_and_the_panel_lets_go() -> void:
	var game := _game()
	_ride(game, 30.0, float(game.logic.course.watts[0]))
	game.played_sec = 30.0
	var result: Dictionary = game.finish()
	for key in ["in_lane_pct", "longest_streak_sec", "avg_power", "jumps", "jumps_caught"]:
		assert_bool(result.stats.has(key)).override_failure_message(key).is_true()
	assert_int(result.stats.jumps).is_equal(1)
	game.hud.clear_widgets()
	assert_float(game.hud.metrics.shown_power()).is_equal(InputBus.power)


func test_stopping_says_pedal_and_ends_the_streak() -> void:
	var game := _game()
	_ride(game, 8.0, float(game.logic.course.watts[0]))
	assert_float(game.logic.streak_sec).is_greater(5.0)
	_ride(game, 5.0, 0.0)
	assert_str(_status(game).alert_kind()).is_equal(WattLaneStatus.ALERT_PEDAL)
	assert_float(game.logic.streak_sec).is_equal(0.0)
	assert_float(game.world.bike_x).is_less(-WattLaneWorld.ROAD_HALF)  # on the left shoulder


func test_a_warm_up_starts_low() -> void:
	var seg := SEGMENT.duplicate(true)
	seg.role = "warmup"
	var game := _game(seg)
	assert_bool(game.logic.warmup).is_true()
	assert_int(game.logic.course.centre_at(0.0)).is_equal(game.logic.course.lane_min)


func _status(game: Game) -> WattLaneStatus:
	return game.get("_status")
