extends GdUnitTestSuite
## Safe Cracker's rules (#41), driven by scripted resistance, cadence and power.

const DT := 1.0 / 60.0
const PARAMS := {"power_cap_watts": 90.0}


func _run(logic: SafeLogic, seconds: float, resistance: float, cadence := 80.0, power := 60.0) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		events.append_array(logic.step(DT, resistance, cadence, power))
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e): return e.type)


func _logic(difficulty := "standard", params := PARAMS, circuit := false) -> SafeLogic:
	return SafeLogic.new(3, difficulty, params, circuit)


func test_combinations_stay_in_range_and_apart() -> void:
	for seed_value in 40:
		var logic := SafeLogic.new(seed_value, "hard", {})
		assert_int(logic.combo.size()).is_equal(5)
		for i in logic.combo.size():
			assert_int(logic.combo[i]).is_between(15, 40)
			if i > 0:
				assert_int(absi(logic.combo[i] - logic.combo[i - 1])).is_greater_equal(6)


func test_lengths_follow_circuit_and_difficulty() -> void:
	assert_int(_logic("easy").combo.size()).is_equal(3)
	assert_int(_logic("standard").combo.size()).is_equal(4)
	assert_int(_logic("hard").combo.size()).is_equal(5)
	assert_int(_logic("hard", PARAMS, true).combo.size()).is_equal(3)
	assert_int(_logic("standard", {"combo_length": 5}).combo.size()).is_equal(5)


func test_difficulty_sets_tolerance_and_hold() -> void:
	assert_float(_logic("easy").tolerance).is_equal(3.0)
	assert_float(_logic("easy").hold_sec).is_equal(1.2)
	assert_float(_logic("standard").tolerance).is_equal(2.0)
	assert_float(_logic("standard").hold_sec).is_equal(1.5)
	assert_float(_logic("hard").hold_sec).is_equal(2.0)


func test_holding_the_target_clicks_a_tumbler_after_the_hold_time() -> void:
	var logic := _logic()
	var target := float(logic.target())
	var events := _run(logic, 1.4, target)
	assert_array(_types(events)).not_contains(["tumbler"])
	events = _run(logic, 0.2, target)
	assert_array(_types(events)).contains(["tumbler"])
	assert_int(logic.tumbler).is_equal(1)
	assert_float(logic.progress).is_equal(0.0)


func test_the_tolerance_edge_counts() -> void:
	var logic := _logic()
	_run(logic, 1.6, float(logic.target()) + 2.0)  # exactly ±2 on standard
	assert_int(logic.tumbler).is_equal(1)
	var outside := _logic()
	_run(outside, 3.0, float(outside.target()) + 2.5)
	assert_int(outside.tumbler).is_equal(0)


func test_a_short_slip_keeps_progress_but_a_long_one_drains_it() -> void:
	var logic := _logic()
	var target := float(logic.target())
	_run(logic, 1.0, target)
	var held := logic.progress
	assert_float(held).is_greater(0.9)
	_run(logic, 0.3, target + 10.0)  # inside the 0.4 s grace: the reading is just late
	assert_float(logic.progress).is_equal_approx(held, 0.001)
	_run(logic, 0.9, target + 10.0)  # well past it
	assert_float(logic.progress).is_less(held - 0.3)


func test_an_unpowered_dial_pauses_the_hold() -> void:
	var logic := _logic()
	var target := float(logic.target())
	_run(logic, 0.6, target)
	var held := logic.progress
	_run(logic, 2.0, target, 40.0)  # under the cadence floor
	assert_float(logic.progress).is_equal(held)
	assert_bool(logic.powered).is_false()
	assert_int(logic.tumbler).is_equal(0)


func test_power_well_over_the_cap_trips_the_alarm_and_resets_the_tumbler() -> void:
	var logic := _logic()
	logic.progress = 0.7
	# Resistance far from the target, so no tumbler clicks; power at twice the cap.
	var events := _run(logic, 4.0, 90.0, 80.0, 180.0)
	assert_array(_types(events)).contains(["alarm"])
	assert_int(logic.alarms).is_equal(1)
	assert_float(logic.alarm_left).is_greater(0.0)
	assert_float(logic.progress).is_equal(0.0)


func test_ordinary_pedalling_a_little_over_the_cap_doesnt_trip_it() -> void:
	# The cap is 90 W; the alarm needs power over 25% above it (112 W), smoothed.
	var logic := _logic()
	var events := _run(logic, 20.0, 90.0, 80.0, 105.0)
	assert_array(_types(events)).not_contains(["alarm"])


func test_a_burst_over_the_alarm_level_is_forgiven() -> void:
	var logic := _logic()
	_run(logic, 3.0, 90.0, 80.0, 60.0)
	var events := _run(logic, 2.0, 90.0, 80.0, 200.0)  # a short spike, smoothed away
	assert_array(_types(events)).not_contains(["alarm"])
	_run(logic, 5.0, 90.0, 80.0, 60.0)
	assert_float(logic.over_sec).is_equal(0.0)


func test_cracking_every_tumbler_opens_the_safe_and_the_next_comes_after_the_door() -> void:
	var logic := _logic("easy")
	var events: Array[Dictionary] = []
	for i in logic.combo.size():
		events.append_array(_run(logic, 1.4, float(logic.combo[i])))
	assert_array(_types(events)).contains(["vault_open"])
	assert_bool(logic.is_open()).is_true()
	assert_int(logic.cracked).is_equal(1)
	var open: Dictionary = events.filter(func(e): return e.type == "vault_open")[0]
	assert_float(open.points).is_equal(SafeLogic.vault_points(open.seconds, 0))
	events = _run(logic, SafeLogic.OPEN_SEC + 0.1, 30.0)
	assert_array(_types(events)).contains(["new_vault"])
	assert_int(logic.vault).is_equal(2)
	assert_bool(logic.is_open()).is_false()


func test_vault_points_reward_speed_and_clean_cracks() -> void:
	assert_float(SafeLogic.vault_points(0.0, 0)).is_equal(1200.0)
	assert_float(SafeLogic.vault_points(20.0, 0)).is_equal(1100.0)
	assert_float(SafeLogic.vault_points(20.0, 2)).is_equal(900.0)
	assert_float(SafeLogic.vault_points(1000.0, 0)).is_equal(SafeLogic.COMPLETION_BONUS)


func test_later_safes_are_harder() -> void:
	var logic := _logic("easy")
	var first_length := logic.combo.size()
	var first_tolerance := logic.tolerance
	var first_hold := logic.hold_sec
	for n in 3:
		logic._start_vault(logic.vault + 1)
	assert_int(logic.vault).is_equal(4)
	assert_int(logic.combo.size()).is_greater(first_length)
	assert_float(logic.tolerance).is_less(first_tolerance)
	assert_float(logic.hold_sec).is_less(first_hold)
	assert_bool(logic.hidden).is_true()  # hidden targets from vault 4
	logic._start_vault(30)
	assert_int(logic.combo.size()).is_less_equal(SafeLogic.MAX_LENGTH)
	assert_float(logic.tolerance).is_greater_equal(1.0)
	assert_float(logic.hold_sec).is_greater_equal(0.9)


func test_hard_hides_the_target_from_the_first_safe() -> void:
	assert_bool(_logic("hard").hidden).is_true()
	assert_bool(_logic("standard").hidden).is_false()
	assert_bool(_logic("standard", {"hidden_target": true}).hidden).is_true()


func test_closeness_follows_the_reading() -> void:
	var logic := _logic()
	var target := float(logic.target())
	logic.step(DT, target, 80.0, 50.0)
	assert_float(logic.closeness()).is_equal(1.0)
	logic.step(DT, target + 12.5, 80.0, 50.0)
	assert_float(logic.closeness()).is_equal_approx(0.5, 0.001)
	logic.step(DT, target + 40.0, 80.0, 50.0)
	assert_float(logic.closeness()).is_equal(0.0)


func test_the_same_seed_gives_the_same_combinations() -> void:
	assert_array(SafeLogic.new(9, "standard", {}).combo).is_equal(SafeLogic.new(9, "standard", {}).combo)


func test_a_narrow_range_still_makes_a_combination() -> void:
	var logic := SafeLogic.new(1, "standard", {"res_min": 30, "res_max": 34})
	assert_int(logic.combo.size()).is_equal(4)
	for n in logic.combo:
		assert_int(n).is_between(30, 34)


## Points a minute of a `minutes`-long ride by a modelled rider: the knob moves `speed` units/s
## toward the target (stopping once the reading is near it) and the reading lags the knob by a
## first-order 0.6 s.
func _rider_points_per_minute(speed: float, difficulty: String, minutes := 4.0) -> float:
	var logic := SafeLogic.new(5, difficulty, {"power_cap_watts": 90.0}, false)
	var knob := 30.0
	var lagged := 30.0
	var points := 0.0
	for i in roundi(minutes * 60.0 / DT):
		var want := float(logic.target()) if not logic.is_open() else 30.0
		if absf(lagged - want) > logic.tolerance * 0.6:
			knob = move_toward(knob, want, speed * DT)
		lagged += (knob - lagged) * (DT / 0.6)
		for e in logic.step(DT, lagged, 80.0, 60.0):
			if e.type == "vault_open":
				points += e.points
	return points / minutes


func test_a_careful_rider_earns_two_stars_and_a_quick_accurate_one_three() -> void:
	var info := GameRegistry.info("safe_cracker")
	for difficulty in ["easy", "standard", "hard"]:
		var careful := _rider_points_per_minute(2.0, difficulty)
		assert_int(Stars.for_score(careful, info, difficulty, 60.0, "")).is_equal(2)
		var quick := _rider_points_per_minute(8.0, difficulty)
		assert_int(Stars.for_score(quick, info, difficulty, 60.0, "")).is_equal(3)
		# Barely moving the knob earns nothing.
		assert_int(Stars.for_score(_rider_points_per_minute(0.3, difficulty), info, difficulty, 60.0, "")).is_less(2)
