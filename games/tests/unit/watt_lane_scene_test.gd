extends GdUnitTestSuite
## Watt Lane's scene with the framework (#78): every power number on the HUD agrees (the ride
## panel shows the rules' smoothed watts and turns gold exactly inside the rules' band), the status
## widget fits its slot with the longest texts and its countdown follows the announced jump, the
## track's band follows the course with power as height, and the result carries the stats.

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
		game.track.update_view(DT, game.logic.course, game.logic.time, game.logic.smoothed, game.logic.in_lane,
			float(up.get("at", -1.0)), bool(up.get("up", true)), int(up.get("lo", 0)), int(up.get("hi", 0)))
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
	_ride(game, 0.1, float(hi) + 1.0)
	assert_bool(game.logic.in_lane).is_false()
	assert_object(metrics.power_color(metrics.shown_power())).is_equal(HudTheme.WARN)
	var status: WattLaneStatus = _status(game)
	assert_str(status.lane.text).is_equal("%d–%d" % [game.logic.lane_lo(), game.logic.lane_hi()])
	assert_str(status.alert_kind()).is_equal(WattLaneStatus.ALERT_EASE)
	assert_str(status.alert_label.text).is_equal("EASE 1 W")  # how far off, in the panel's watts


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
	assert_str(status.countdown_label.text).is_equal("%d–%d in 5" % [w - game.logic.width / 2, w + game.logic.width / 2])
	_ride(game, 3.0, float(course.watts[0]))
	assert_str(status.countdown_label.text).ends_with("in 2")
	_ride(game, 2.5, float(w))
	assert_bool(status.countdown.visible).is_false()


func test_the_status_widget_fits_its_slot_and_never_changes_width() -> void:
	var status: WattLaneStatus = auto_free(WattLaneStatus.new(load("res://games/watt_lane/WattLane.gd").look))
	add_child(status)
	status.set_lane(880, 960)  # 3 digits: FTP 500 tops out near 425
	status.set_info(true, 2.5)
	await get_tree().process_frame
	_assert_fits(status)
	var width := status.get_combined_minimum_size().x
	status.set_alert(WattLaneStatus.ALERT_EASE, 120)
	await get_tree().process_frame
	_assert_fits(status)
	assert_float(status.get_combined_minimum_size().x).is_equal(width)
	assert_bool(status.info.visible).is_false()  # the alert takes the row
	status.set_countdown(false, 880, 960, 5)
	await get_tree().process_frame
	_assert_fits(status)
	assert_float(status.get_combined_minimum_size().x).is_equal(width)
	assert_bool(status.alert.visible).is_false()  # the chip takes the row
	status.set_countdown(true, 0, 0, -1)
	await get_tree().process_frame
	assert_bool(status.alert.visible).is_true()
	status.set_alert(WattLaneStatus.ALERT_NONE)
	await get_tree().process_frame
	assert_bool(status.info.visible).is_true()
	assert_str(status.info.text).is_equal("IN LANE")


func test_the_summary_shows_in_lane_streak_and_steps_caught() -> void:
	var game: Game = auto_free(load("res://games/watt_lane/WattLane.tscn").instantiate())
	var info := game.declared()
	var stats := {"in_lane_pct": 82, "longest_streak_sec": 41, "jumps": 4, "jumps_caught": 3}
	var tiles := SummaryScreen._stat_tiles(info, [{"stats": stats}])
	assert_array(tiles).is_equal([["82%", "in lane"], ["41 s", "best streak"], ["3/4", "steps caught"]])


func _assert_fits(status: WattLaneStatus) -> void:
	var size := status.get_combined_minimum_size()
	assert_float(size.x).is_less_equal(850.0)
	assert_float(size.y).is_less_equal(120.0)
	for l in [status.caption, status.streak, status.info, status.countdown_label, status.alert_label]:
		assert_int(l.get_theme_font_size("font_size")).is_greater_equal(42)  # readable at 1 m


func test_the_lane_follows_the_course_ahead() -> void:
	var game := _game()
	_ride(game, 1.0, 120.0)
	var track: WattLaneTrack = game.track
	var t: float = game.logic.time
	var half := float(game.logic.width) / 2.0
	for i in [0, 20, 40, 63]:
		var x: float = track.get("_x0") + i * track.get("_dx")
		var centre: float = game.logic.course.visual_centre_at(WattLaneTrack.time_at(x, t))
		assert_float(track.get("_hi")[i]).is_equal_approx(track.y_of(centre + half), 0.01)
		assert_float(track.get("_lo")[i]).is_equal_approx(track.y_of(centre - half), 0.01)
	assert_float(track.cursor_y).is_equal_approx(track.y_of(game.logic.smoothed), 2.0)


func test_more_watts_is_higher() -> void:
	var track: WattLaneTrack = auto_free(WattLaneTrack.new())
	add_child(track)
	track.ftp = 200.0
	assert_float(track.y_of(0.6 * 200.0)).is_equal_approx(WattLaneTrack.MID_Y, 0.01)
	assert_float(track.y_of(0.725 * 200.0)).is_equal_approx(WattLaneTrack.guide_y(1), 0.01)  # a guide every 12.5%
	assert_float(track.y_of(150.0)).is_less(track.y_of(100.0))
	assert_float(track.y_of(2000.0)).is_equal(WattLaneTrack.TOP_Y)
	assert_float(track.y_of(0.0)).is_equal(WattLaneTrack.BOTTOM_Y)


func test_an_announced_step_shows_its_watts_where_it_lands() -> void:
	var game := _game()
	var course: WattLaneCourse = game.logic.course
	var j := course.next_jump_after(0.0)
	_ride(game, course.times[j] - 3.0, float(course.watts[0]))
	var track: WattLaneTrack = game.track
	var w := course.watts[j]
	assert_bool(track.label.visible).is_true()
	assert_str(track.label.text).is_equal("%d–%d W" % [w - game.logic.width / 2, w + game.logic.width / 2])
	assert_float(track.label.position.x).is_equal_approx(WattLaneTrack.RIDER_X + 3.0 * WattLaneTrack.SPEED + 22.0, 6.0)


func test_the_cursor_is_an_angular_chevron() -> void:
	# The silhouette check (ART_BIBLE.md): a moving marker never has a round head with a tail.
	var shape := WattLaneTrack.chevron()
	assert_int(shape.size()).is_equal(4)
	var tip := shape[1]
	assert_float(tip.x).is_greater(0.0)  # points along the lane, to the right
	for p in shape:
		assert_float(absf(p.y)).is_less_equal(34.0)


func test_the_field_follows_the_lane_and_draws_nothing_per_frame() -> void:
	var game := _game()
	_ride(game, 2.0, float(game.logic.course.watts[0]))
	game.backdrop.update_view(DT, game.track.scroll, 0.5, game.track.lane_mid(), true)
	var mat: ShaderMaterial = game.backdrop.field.material
	assert_float(mat.get_shader_parameter("scroll")).is_equal(game.track.scroll)
	assert_float(mat.get_shader_parameter("lane_mid")).is_equal_approx(game.track.y_of(game.logic.course.visual_centre_at(game.logic.time)), 2.0)
	assert_int(game.backdrop.get_child_count()).is_equal(1)  # one rect, no geometry


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
	assert_float(game.track.cursor_y).is_equal_approx(WattLaneTrack.BOTTOM_Y, 1.0)  # at the foot of the field


func test_a_warm_up_starts_low() -> void:
	var seg := SEGMENT.duplicate(true)
	seg.role = "warmup"
	var game := _game(seg)
	assert_bool(game.logic.warmup).is_true()
	assert_int(game.logic.course.centre_at(0.0)).is_equal(game.logic.course.lane_min)


func _status(game: Game) -> WattLaneStatus:
	return game.get("_status")
