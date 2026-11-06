extends GdUnitTestSuite
## Ready for Launch's rules (#82): fuel integration, phase timing, the climb, the milestones,
## launches filling a slot, and the stars. FTP 200: line 100 W, full 120 W, target 210 W.

const FTP := 200.0
const DT := 1.0 / 30.0
const PARAMS := {"ftp_watts": FTP, "fuel_line_watts": 100.0, "fuel_full_watts": 120.0, "target_watts": 210.0}
## The stars, from ReadyForLaunch.info (points a minute).
const STARS: Array = [300.0, 950.0, 2000.0]


func _logic(duration := 90.0, rounds := 0) -> LaunchLogic:
	return LaunchLogic.new(PARAMS, "standard", duration, rounds)


## Rides for `seconds` at `power`; returns points scored and adds events to `events`.
func _ride(l: LaunchLogic, seconds: float, power: float, events: Array = []) -> float:
	var points := 0.0
	for i in roundi(seconds / DT):
		for e in l.step(DT, power):
			events.append(e)
		points += l.last_points
	return points


func _types(events: Array) -> Array:
	return events.map(func(e): return e.type)


## One whole launch: `fuel_w` to T-0, then `push_w`, then an easy spin.
func _launch(l: LaunchLogic, fuel_w: float, push_w: float, events: Array = []) -> float:
	var p := _ride(l, l.fuel_sec + LaunchLogic.COUNT_SEC, fuel_w, events)
	p += _ride(l, LaunchLogic.PUSH_SEC, push_w, events)
	p += _ride(l, l.coast_sec + LaunchLogic.RESULT_SEC - 0.1, 90.0, events)
	return p


func test_a_launch_is_ninety_seconds_of_fuel_count_push_coast_and_result() -> void:
	assert_float(LaunchLogic.FUEL_SEC + LaunchLogic.COUNT_SEC + LaunchLogic.PUSH_SEC + LaunchLogic.COAST_SEC
		+ LaunchLogic.RESULT_SEC).is_equal(LaunchLogic.LAUNCH_SEC)
	var l := _logic()
	assert_int(l.planned).is_equal(1)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.FUEL)
	_ride(l, 44.9, 120.0)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.FUEL)
	_ride(l, 0.2, 120.0)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.COUNT)
	_ride(l, 9.8, 120.0)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.COUNT)
	_ride(l, 0.2, 210.0)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.PUSH)
	_ride(l, 18.0, 150.0)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.COAST)
	_ride(l, 15.0, 90.0)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.RESULT)


func test_holding_sixty_percent_of_ftp_fills_the_tank_with_headroom() -> void:
	var l := _logic()
	var events := []
	_ride(l, 45.0, 120.0, events)
	assert_int(l.fuel_pct()).is_equal(100)
	assert_array(_types(events)).contains(["tank_full"])
	assert_float(l.fuel_mult()).is_equal_approx(1.5, 0.001)


func test_no_fuel_flows_at_or_below_the_line() -> void:
	var l := _logic()
	_ride(l, 45.0, 100.0)
	assert_float(l.fuel).is_equal(0.0)
	assert_float(l.fuel_mult()).is_equal(0.5)


func test_the_tank_fills_with_the_energy_above_the_line() -> void:
	var l := _logic()
	_ride(l, 45.0, 110.0)  # half way from the line to full
	assert_float(l.fuel).is_between(0.5, 0.6)


func test_a_short_sprint_cannot_fill_the_tank() -> void:
	var l := _logic()
	_ride(l, 10.0, 400.0)
	_ride(l, 35.0, 60.0)
	assert_float(l.fuel).is_less(0.45)


func test_fuel_locks_at_the_count() -> void:
	var l := _logic()
	_ride(l, 45.1, 110.0)
	var at_count := l.fuel
	_ride(l, 9.0, 200.0)
	assert_float(l.fuel).is_equal(at_count)


func test_the_count_announces_every_second_and_warns_ten_seconds_ahead() -> void:
	var l := _logic()
	var events := []
	_ride(l, 55.1, 120.0, events)
	var counts: Array = events.filter(func(e): return e.type == "count").map(func(e): return e.n)
	assert_array(counts).is_equal([10, 9, 8, 7, 6, 5, 4, 3, 2, 1])
	assert_array(_types(events)).contains(["count_start", "ignition"])


func test_climb_is_power_times_the_fuel_multiplier() -> void:
	var full := _logic()
	var empty := _logic()
	_launch(full, 120.0, 210.0)
	_launch(empty, 100.0, 210.0)
	# A full tank climbs three times as far as an empty one on the same push (1.5 against 0.5).
	assert_float(full.climb / empty.climb).is_between(2.9, 3.1)
	var harder := _logic()
	var easier := _logic()
	_launch(harder, 100.0, 210.0)
	_launch(easier, 100.0, 105.0)
	assert_float(harder.climb / easier.climb).is_between(1.9, 2.1)


func test_power_past_the_cap_adds_no_climb() -> void:
	var cap := _logic()
	var over := _logic()
	_launch(cap, 100.0, 210.0 * LaunchLogic.PUSH_CAP)
	_launch(over, 100.0, 900.0)
	assert_float(over.climb).is_equal_approx(cap.climb, 0.5)


func test_a_rider_who_never_pedals_scores_nothing_and_the_launch_is_scrubbed() -> void:
	var l := _logic()
	var events := []
	var points := _ride(l, 90.0, 0.0, events)
	assert_float(points).is_equal(0.0)
	assert_float(l.climb).is_equal(0.0)
	assert_bool(l.scrubbed).is_true()
	assert_int(l.launches).is_equal(0)
	assert_array(_types(events)).contains(["scrub"])
	assert_array(_types(events)).not_contains(["liftoff"])


func test_stopping_during_the_push_or_the_coast_stops_the_climb_and_the_points_at_once() -> void:
	var l := _logic()
	_ride(l, 55.0, 120.0)
	_ride(l, 10.0, 210.0)
	var climbed := l.climb
	assert_float(climbed).is_greater(0.0)
	assert_float(_ride(l, 8.0, 0.0)).is_equal(0.0)
	assert_float(l.climb).is_equal(climbed)
	assert_float(_ride(l, 14.0, 0.0)).is_equal(0.0)
	assert_float(l.climb).is_equal(climbed)


func test_the_coast_climbs_while_the_rider_spins_easily() -> void:
	var l := _logic()
	_ride(l, 55.0, 120.0)
	_ride(l, 18.0, 210.0)
	var before := l.climb
	_ride(l, 10.0, 60.0)
	assert_float(l.climb).is_greater(before + 2.0)


func test_the_clamps_let_go_only_once_the_push_passes_a_quarter_of_the_target() -> void:
	var cold := _logic()
	_ride(cold, 55.0, 30.0)
	_ride(cold, 6.0, 40.0)
	assert_bool(cold.lifted).is_false()
	assert_float(cold.climb).is_equal(0.0)
	_ride(cold, 3.0, 120.0)
	assert_bool(cold.lifted).is_true()


func test_milestones_pass_in_order_with_their_bonuses() -> void:
	var l := _logic()
	var events := []
	_launch(l, 120.0, 273.0, events)
	var seen: Array = events.filter(func(e): return e.type == "milestone")
	assert_array(seen.map(func(e): return e.id)).is_equal(["clouds", "edge", "orbit", "moon"])
	assert_array(seen.map(func(e): return e.bonus)).is_equal([100, 200, 300, 500])
	assert_int(l.moons).is_equal(1)
	assert_str(l.reached_name()).is_equal("The Moon")


func test_a_full_tank_and_the_target_reach_orbit_and_an_empty_tank_the_clouds() -> void:
	var l := _logic()
	_launch(l, 120.0, 210.0)
	assert_str(l.reached_name()).is_equal("Orbit")
	var e := _logic()
	_launch(e, 100.0, 210.0)
	assert_str(e.reached_name()).is_equal("Clouds")


func test_the_moon_caps_the_climb_and_ends_the_push_early_without_changing_the_launch_length() -> void:
	var l := _logic()
	var events := []
	_ride(l, 55.1, 120.0, events)
	_ride(l, 10.0, 400.0, events)
	l.climb = 33.9  # most of the way: a push arrives early only from here
	_ride(l, 1.0, 400.0, events)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.COAST)
	assert_float(l.climb).is_equal(34.0)
	_ride(l, 90.0 - 55.1 - 11.0 - 2.2, 90.0, events)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.COAST)
	_ride(l, 0.4, 90.0, events)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.RESULT)
	assert_int(l.moons).is_equal(1)


func test_kilometres_meet_each_milestone_and_only_ever_rise() -> void:
	for m in LaunchLogic.MILESTONES:
		assert_float(LaunchLogic.km_for(m.at)).is_equal_approx(m.km, 0.01)
	assert_float(LaunchLogic.km_for(0.0)).is_equal(0.0)
	var last := -1.0
	for i in 400:
		var k := LaunchLogic.km_for(i * 0.1)
		assert_bool(k >= last).is_true()
		last = k


func test_launches_fill_a_slot_exactly() -> void:
	var slots := [[90, 1, 90.0], [120, 1, 120.0], [150, 1, 150.0], [180, 2, 90.0], [240, 2, 120.0], [300, 3, 100.0],
		[600, 6, 100.0], [3600, 40, 90.0]]
	for pair in slots:
		var l := LaunchLogic.new(PARAMS, "standard", float(pair[0]))
		assert_int(l.planned).is_equal(pair[1])
		assert_float(l.launch_sec).is_equal_approx(pair[2], 0.01)
		assert_float(l.fuel_sec + LaunchLogic.COUNT_SEC + LaunchLogic.PUSH_SEC + l.coast_sec
			+ LaunchLogic.RESULT_SEC).is_equal_approx(pair[2], 0.01)


func test_a_slot_flies_each_launch_then_holds_for_the_timer() -> void:
	var l := _logic(300.0)
	var events := []
	_ride(l, 301.0, 120.0, events)
	assert_int(l.launch).is_equal(3)
	assert_array(_types(events).filter(func(t): return t == "next_launch")).has_size(2)
	assert_bool(l.finished).is_false()
	_ride(l, 30.0, 120.0, events)
	assert_int(l.launch).is_equal(3)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.RESULT)


func test_rounds_end_on_the_last_launch() -> void:
	var l := LaunchLogic.new(PARAMS, "standard", 180.0, 2)
	var events := []
	_ride(l, 181.0, 120.0, events)
	assert_bool(l.finished).is_true()
	assert_array(_types(events)).contains(["finished"])


func test_open_ended_launches_go_on() -> void:
	var l := _logic(-1.0)
	assert_int(l.planned).is_equal(0)
	_ride(l, 400.0, 120.0)
	assert_int(l.launch).is_equal(5)
	assert_bool(l.finished).is_false()


func test_each_launch_starts_with_an_empty_tank_on_the_ground() -> void:
	var l := _logic(-1.0)
	_ride(l, 91.0, 150.0)
	assert_int(l.launch).is_equal(2)
	assert_int(l.phase).is_equal(LaunchLogic.Phase.FUEL)
	assert_float(l.climb).is_equal(0.0)
	assert_float(l.best_climb).is_greater(0.0)
	assert_bool(l.lifted).is_false()


func test_sensor_loss_freezes_fuel_and_climb_but_the_clock_runs() -> void:
	var l := _logic()
	_ride(l, 10.0, 120.0)
	var fuel := l.fuel
	var left := l.phase_left
	for i in 30:
		l.step(DT, 120.0, true)
	assert_float(l.fuel).is_equal(fuel)
	assert_float(l.phase_left).is_less(left)
	_ride(l, 50.0, 210.0)
	var climbed := l.climb
	assert_float(climbed).is_greater(0.0)
	var got := 0.0
	for i in 30:
		l.step(DT, 210.0, true)
		got += l.last_points
	assert_float(got).is_equal(0.0)
	assert_float(l.climb).is_equal(climbed)


func test_stats_add_up_across_launches() -> void:
	var l := _logic(-1.0)
	_launch(l, 120.0, 210.0)
	_ride(l, 0.2, 110.0)
	_launch(l, 110.0, 150.0)
	assert_int(l.launches).is_equal(2)
	assert_int(l.fuel_pct_avg()).is_between(70, 85)
	assert_float(l.best_km()).is_equal_approx(LaunchLogic.km_for(l.best_climb), 0.01)
	assert_float(l.peak_power).is_between(200.0, 211.0)


## Points a minute over a whole launch at effort `multiplier` (the scene's `award` applies it).
func _per_minute(l: LaunchLogic, fuel_w: float, push_w: float, multiplier: float) -> float:
	return _launch(l, fuel_w, push_w) * multiplier / (l.launch_sec / 60.0)


func test_a_perfect_run_at_one_times_effort_stays_short_of_three_stars() -> void:
	assert_float(_per_minute(_logic(), 120.0, 900.0, 1.0)).is_less(STARS[2])
	# 3 stars takes about 1.3× effort on that same perfect run.
	assert_float(_per_minute(_logic(), 120.0, 900.0, 1.3)).is_greater_equal(STARS[2])
	assert_float(_per_minute(_logic(), 120.0, 900.0, 1.15)).is_less(STARS[2])


func test_the_lower_stars_fall_where_the_design_says() -> void:
	# A full tank and the target reach orbit: 2 stars. An empty tank and the target: 1 star.
	assert_float(_per_minute(_logic(), 120.0, 210.0, 1.0)).is_between(STARS[1], STARS[2])
	assert_float(_per_minute(_logic(), 100.0, 210.0, 1.0)).is_between(STARS[0], STARS[1])


func test_stars_hold_in_a_slot_that_doesnt_divide_into_ninety_seconds() -> void:
	for sec in [120.0, 150.0]:
		var perfect := _per_minute(_logic(sec), 120.0, 900.0, 1.0)
		assert_float(perfect).is_equal_approx(_per_minute(_logic(), 120.0, 900.0, 1.0), 40.0)
