extends GdUnitTestSuite
## Cadence Karaoke's rules (#42), driven by scripted cadence and power.

const DT := 1.0 / 60.0


func _run(logic: CadenceLogic, seconds: float, cadence: float, power := 50.0) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		events.append_array(logic.step(DT, cadence, power))
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e): return e.type)


func test_the_default_pace_is_80_and_steady_has_no_shape() -> void:
	var logic := CadenceLogic.new()
	assert_float(logic.target_at(0.0)).is_equal(80.0)
	assert_float(logic.target_at(500.0)).is_equal(80.0)
	assert_int(logic.pace()).is_equal(80)


func test_profile_points_are_interpolated_and_the_last_is_held_or_cycled() -> void:
	var points := [{"t": 0.0, "rpm": 70.0}, {"t": 60.0, "rpm": 90.0}, {"t": 120.0, "rpm": 80.0}]
	var logic := CadenceLogic.new("standard", {"cadence_profile": points})
	assert_float(logic.target_at(0.0)).is_equal(70.0)
	assert_float(logic.target_at(30.0)).is_equal(80.0)
	assert_float(logic.target_at(60.0)).is_equal(90.0)
	assert_float(logic.target_at(90.0)).is_equal(85.0)
	assert_float(logic.target_at(120.0)).is_equal(80.0)
	assert_float(logic.target_at(150.0)).is_equal(logic.target_at(30.0))  # an open-ended ride cycles it


func test_the_shapes_move_around_the_riders_pace() -> void:
	var pyramid := CadenceLogic.new("standard", {}, "pyramid")
	assert_float(pyramid.target_at(0.0)).is_equal(70.0)
	assert_float(pyramid.target_at(180.0)).is_equal(90.0)
	assert_float(pyramid.target_at(360.0)).is_equal(70.0)
	var builds := CadenceLogic.new("standard", {}, "builds")
	assert_float(builds.target_at(0.0)).is_equal(80.0)
	assert_float(builds.target_at(60.0)).is_equal(85.0)
	assert_float(builds.target_at(120.0)).is_equal(90.0)
	assert_float(builds.target_at(180.0)).is_equal(80.0)
	var spinups := CadenceLogic.new("standard", {}, "spinups")
	assert_float(spinups.target_at(10.0)).is_equal(95.0)
	assert_float(spinups.target_at(40.0)).is_equal(80.0)
	assert_float(spinups.target_at(95.0)).is_equal(95.0)


func test_bands_follow_difficulty() -> void:
	assert_float(CadenceLogic.new("easy").tolerance).is_equal(7.0)
	assert_float(CadenceLogic.new("standard").tolerance).is_equal(5.0)
	assert_float(CadenceLogic.new("hard").tolerance).is_equal(4.0)
	assert_float(CadenceLogic.new("standard", {"tolerance_rpm": 3}).tolerance).is_equal(3.0)


func test_points_come_only_inside_the_band_with_a_bonus_tier() -> void:
	var inside := CadenceLogic.new()
	_run(inside, 1.0, 84.0)  # 4 rpm off: in the band, not the bonus
	assert_float(inside.band_sec).is_equal_approx(1.0, 0.02)
	var outside := CadenceLogic.new()
	_run(outside, 1.0, 90.0)
	assert_float(outside.band_sec).is_equal(0.0)
	var plain := CadenceLogic.new()
	plain.step(1.0, 84.0, 50.0)
	assert_float(plain.last_points).is_equal(CadenceLogic.POINTS_PER_SEC)
	var bonus := CadenceLogic.new()
	bonus.step(1.0, 81.0, 50.0)
	assert_float(bonus.last_points).is_equal(CadenceLogic.POINTS_PER_SEC * CadenceLogic.BONUS_FACTOR)
	var stopped := CadenceLogic.new()
	stopped.step(1.0, 0.0, 0.0)
	assert_float(stopped.last_points).is_equal(0.0)


func test_the_streak_multiplier_grows_and_a_short_wobble_is_forgiven() -> void:
	var logic := CadenceLogic.new()
	var events := _run(logic, 21.0, 80.0)
	assert_array(_types(events)).contains(["streak"])
	assert_float(logic.streak_multiplier()).is_equal(1.5)
	_run(logic, 0.6, 100.0)  # inside the 1 s grace
	assert_float(logic.streak_sec).is_greater(20.0)
	events = _run(logic, 1.0, 100.0)
	assert_array(_types(events)).contains(["band_exit"])
	assert_float(logic.streak_sec).is_equal(0.0)
	assert_float(logic.longest_streak).is_greater(20.0)
	assert_float(logic.streak_multiplier()).is_equal(1.0)


func test_the_multiplier_stops_at_two() -> void:
	var logic := CadenceLogic.new()
	_run(logic, 80.0, 80.0)
	assert_float(logic.streak_multiplier()).is_equal(CadenceLogic.STREAK_MULT_MAX)


func test_power_well_over_the_cap_freezes_scoring_and_recovers() -> void:
	var logic := CadenceLogic.new("standard", {"power_cap_watts": 90.0})
	_run(logic, 1.0, 80.0, 80.0)
	var scored := logic.band_sec
	assert_float(scored).is_greater(0.9)
	var events := _run(logic, 3.0, 80.0, 200.0)  # far over 1.25 × 90 W, smoothed
	assert_array(_types(events)).contains(["ease_off"])
	assert_bool(logic.frozen).is_true()
	assert_float(logic.band_sec).is_less(scored + 1.5)
	events = _run(logic, 4.0, 80.0, 50.0)
	assert_array(_types(events)).contains(["recovered"])
	assert_bool(logic.frozen).is_false()


func test_power_a_little_over_the_cap_is_fine() -> void:
	var logic := CadenceLogic.new("standard", {"power_cap_watts": 90.0})
	var events := _run(logic, 10.0, 80.0, 108.0)  # under 1.25 × 90 = 112.5
	assert_array(_types(events)).not_contains(["ease_off"])


func test_no_cap_never_freezes() -> void:
	var logic := CadenceLogic.new()
	_run(logic, 5.0, 80.0, 600.0)
	assert_bool(logic.frozen).is_false()


func test_a_pace_change_waits_for_the_boundary_then_shifts_every_target() -> void:
	var logic := CadenceLogic.new("standard", {}, "pyramid")
	var before := logic.target_at(180.0)
	assert_bool(logic.request_pace(1)).is_true()
	assert_float(logic.target_at(180.0)).is_equal(before)  # not yet
	assert_int(logic.pending_adjust).is_equal(5)
	assert_bool(logic.apply_pending()).is_true()
	assert_float(logic.target_at(180.0)).is_equal(before + 5.0)
	assert_int(logic.pace()).is_equal(85)
	assert_bool(logic.apply_pending()).is_false()


func test_requests_stack_and_stay_in_range() -> void:
	var logic := CadenceLogic.new()
	logic.request_pace(1)
	logic.request_pace(1)
	assert_int(logic.pending_adjust).is_equal(10)
	logic.apply_pending()
	assert_int(logic.pace()).is_equal(90)
	for i in 20:
		logic.request_pace(1)
	logic.apply_pending()
	assert_int(logic.pace()).is_equal(CadenceLogic.PACE_MAX)
	assert_bool(logic.request_pace(1)).is_false()
	for i in 20:
		logic.request_pace(-1)
	logic.apply_pending()
	assert_int(logic.pace()).is_equal(CadenceLogic.PACE_MIN)


func test_stats() -> void:
	var logic := CadenceLogic.new()
	_run(logic, 6.0, 80.0, 60.0)
	_run(logic, 4.0, 110.0, 100.0)
	assert_float(logic.pct_in_band()).is_equal_approx(60.0, 1.0)
	assert_float(logic.avg_cadence()).is_equal_approx(92.0, 0.5)
	assert_float(logic.avg_power()).is_equal_approx(76.0, 0.5)


## Points a minute of a 3-minute ride by a rider who stays near the target, `wobble` rpm off at most
## (two slow waves, so the error isn't a constant).
func _wobbly_points_per_minute(wobble: float, difficulty: String) -> float:
	var logic := CadenceLogic.new(difficulty)
	var points := 0.0
	var minutes := 3.0
	for i in roundi(minutes * 60.0 / DT):
		var t := float(i) * DT
		var off := wobble * (0.6 * sin(t * 1.3) + 0.4 * sin(t * 3.1 + 1.0))
		logic.step(DT, logic.target() + off, 60.0)
		points += logic.last_points
	return points / minutes


func test_steady_riders_earn_stars_by_how_steady_they_are() -> void:
	var info := GameRegistry.info("cadence_karaoke")
	for difficulty in ["easy", "standard", "hard"]:
		var very_steady := _wobbly_points_per_minute(2.0, difficulty)
		assert_int(Stars.for_score(very_steady, info, difficulty, 60.0, "")).is_equal(3)
		var average := _wobbly_points_per_minute(6.0, difficulty)
		assert_int(Stars.for_score(average, info, difficulty, 60.0, "")).is_equal(2)
		var wanders := _wobbly_points_per_minute(12.0, difficulty)
		assert_int(Stars.for_score(wanders, info, difficulty, 60.0, "")).is_less(2)
