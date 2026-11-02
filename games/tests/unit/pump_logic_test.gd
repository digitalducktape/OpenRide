extends GdUnitTestSuite
## Balloon Pump's rules (#76), driven by scripted power. DESIGN.md §4 has the formulas.

const DT := 1.0 / 30.0
const FTP := 200.0
const PARAMS := {"ftp_watts": 200.0}
const PumpGame := preload("res://games/balloon_pump/BalloonPump.gd")


func _run(logic: PumpLogic, seconds: float, power: float, until := Callable(), cadence := 85.0) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		events.append_array(logic.step(DT, power, cadence))
		if until.is_valid() and until.call():
			break
	return events


func _find(events: Array[Dictionary], type: String) -> Dictionary:
	for e in events:
		if e.type == type:
			return e
	return {}


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(e): return e.type == type).size()


## A logic whose nozzle holds `kind`, loaded and filling, with the power already smoothed.
func _filling(kind: String, power: float, params := PARAMS, recovery := false) -> PumpLogic:
	var logic := PumpLogic.new(7, params, "max", false, 0, recovery)
	logic.kind = kind
	logic.next_kind = "small"
	_run(logic, 1.0, 0.0, func(): return logic.phase == PumpLogic.Phase.FILL)
	logic.smoothed = power
	return logic


func test_the_first_balloon_loads_then_fills() -> void:
	var logic := PumpLogic.new(1, PARAMS)
	assert_int(logic.phase).is_equal(PumpLogic.Phase.LOAD)
	var events := _run(logic, 1.0, 100.0)
	assert_bool(_find(events, "loaded").is_empty()).is_false()
	assert_int(logic.phase).is_equal(PumpLogic.Phase.FILL)


func test_more_watts_fill_faster() -> void:
	# A medium balloon at 50% of FTP fills in 1.5 / (0.25 × 0.5) = 12 s; at 80% in 7.5 s.
	var times := []
	for watts in [100.0, 160.0]:
		var logic := _filling("medium", watts)
		var t := 0.0
		while logic.phase == PumpLogic.Phase.FILL and t < 30.0:
			logic.step(DT, watts, 85.0)
			t += DT
		times.append(t)
	assert_float(times[0]).is_between(11.5, 13.0)
	assert_float(times[1]).is_between(7.3, 8.3)


func test_bigger_balloons_take_more_air() -> void:
	var times := {}
	for kind in ["small", "medium", "large"]:
		var logic := _filling(kind, 120.0)
		var t := 0.0
		while logic.phase == PumpLogic.Phase.FILL and t < 40.0:
			logic.step(DT, 120.0, 85.0)
			t += DT
		times[kind] = t
	assert_float(times.small).is_less(times.medium)
	assert_float(times.medium).is_less(times.large)
	assert_float(times.large / times.small).is_between(1.9, 2.1)


func test_the_push_line_rises_as_the_balloon_fills() -> void:
	var logic := PumpLogic.new(1, PARAMS)
	# Work: 20% of FTP empty, 45% full for a medium; the curve is f³.
	assert_float(logic.line_at(0.0, "medium")).is_equal_approx(40.0, 0.01)
	assert_float(logic.line_at(1.0, "medium")).is_equal_approx(90.0, 0.01)
	assert_float(logic.line_at(0.5, "medium")).is_equal_approx(40.0 + 50.0 * 0.125, 0.01)
	assert_float(logic.line_at(1.0, "small")).is_equal_approx(80.0, 0.01)
	assert_float(logic.line_at(1.0, "large")).is_equal_approx(96.0, 0.01)
	# No balloon asks for more than about half of FTP.
	for kind in PumpLogic.KINDS:
		assert_float(logic.line_at(1.0, kind)).is_less_equal(FTP * 0.5)


func test_spinning_lightly_gets_most_of_the_way_then_stalls() -> void:
	# 30% of FTP: a medium stalls where 0.2 + 0.25 f³ = 0.3, f ≈ 0.74.
	var logic := _filling("medium", 60.0)
	_run(logic, 40.0, 60.0)
	assert_int(logic.phase).is_equal(PumpLogic.Phase.FILL)
	assert_float(logic.fill).is_between(0.68, 0.76)
	# Turning it up to the line and past it finishes the balloon.
	var events := _run(logic, 20.0, 100.0, func(): return logic.phase != PumpLogic.Phase.FILL)
	assert_bool(_find(events, "filled").is_empty()).is_false()


func test_below_the_line_the_balloon_leaks_slowly_and_never_pops() -> void:
	var logic := _filling("medium", 120.0)
	_run(logic, 6.0, 120.0)
	var before := logic.fill
	assert_float(before).is_greater(0.4)
	# Once the smoothing has dropped below the line (about 1.4 s), 2.5% of a balloon a second.
	var events := _run(logic, 2.0, 20.0)
	assert_bool(logic.leaking).is_true()
	var mid := logic.fill
	assert_float(mid).is_greater(before - 0.02)
	events.append_array(_run(logic, 2.0, 20.0))
	assert_float(mid - logic.fill).is_equal_approx(2.0 * PumpLogic.LEAK, 0.003)
	events.append_array(_run(logic, 120.0, 0.0))
	assert_float(logic.fill).is_equal(0.0)
	assert_int(_count(events, "filled")).is_equal(0)
	assert_int(logic.phase).is_equal(PumpLogic.Phase.FILL)


func test_the_valve_opens_softly_over_the_line() -> void:
	var logic := _filling("medium", 0.0)
	logic.fill = 0.5
	var line := logic.push_line()
	logic.smoothed = line + 0.5
	logic.step(0.0001, line + 0.5, 85.0)
	assert_float(logic.open).is_between(0.0, 0.1)
	logic.smoothed = line + PumpLogic.VALVE * FTP + 1.0
	logic.step(0.0001, logic.smoothed, 85.0)
	assert_float(logic.open).is_equal_approx(1.0, 0.001)


func test_power_is_smoothed_over_about_two_seconds() -> void:
	var logic := PumpLogic.new(1, PARAMS)
	_run(logic, 1.0, 200.0)
	assert_float(logic.smoothed).is_between(120.0, 135.0)  # 1 - e^-1 ≈ 63%
	_run(logic, 2.0, 200.0)
	assert_float(logic.smoothed).is_greater(185.0)


func test_tie_off_awards_by_size_and_loads_the_next() -> void:
	var logic := _filling("large", 150.0)
	var events := _run(logic, 30.0, 150.0, func(): return logic.phase == PumpLogic.Phase.FILL and logic.balloons == 1)
	var filled := _find(events, "filled")
	assert_float(filled.points).is_equal(200.0)
	assert_bool(filled.gold).is_false()
	assert_str(_find(events, "loaded").kind).is_equal("small")
	assert_int(logic.balloons).is_equal(1)
	assert_float(logic.fill).is_equal(0.0)
	# Gold is a medium's air at three times the points.
	assert_float(logic.points_for("gold")).is_equal(450.0)
	assert_float(logic.points_for("small")).is_equal(100.0)


func test_tie_and_load_take_their_time() -> void:
	var logic := _filling("small", 200.0)
	var t_filled := -1.0
	var t_loaded := -1.0
	var t := 0.0
	while t < 20.0 and t_loaded < 0.0:
		for e in logic.step(DT, 200.0, 85.0):
			if e.type == "filled":
				t_filled = t
			elif e.type == "loaded":
				t_loaded = t
		t += DT
	assert_float(t_loaded - t_filled).is_between(PumpLogic.TIE_SEC + PumpLogic.LOAD_SEC - 0.1, PumpLogic.TIE_SEC + PumpLogic.LOAD_SEC + 0.1)


func test_gold_balloons_are_rare_never_early_and_never_twice_in_a_row() -> void:
	var golds := 0
	var draws := 0
	for seed in 20:
		var logic := PumpLogic.new(seed, PARAMS)
		var kinds := [logic.kind, logic.next_kind]
		for i in 60:
			kinds.append(logic._draw())
		assert_str(kinds[0]).is_equal("small")
		assert_str(kinds[1]).is_not_equal("gold")
		for i in range(1, kinds.size()):
			assert_bool(kinds[i] == "gold" and kinds[i - 1] == "gold").is_false()
		golds += kinds.count("gold")
		draws += kinds.size()
	assert_float(float(golds) / draws).is_between(0.07, 0.16)


func test_the_same_seed_gives_the_same_balloons() -> void:
	var a := PumpLogic.new(42, PARAMS)
	var b := PumpLogic.new(42, PARAMS)
	for i in 20:
		assert_str(a._draw()).is_equal(b._draw())


func test_max_without_heats_never_ends_by_itself() -> void:
	var logic := PumpLogic.new(3, PARAMS, "max")
	var events := _run(logic, 600.0, 120.0)
	assert_int(_count(events, "heat_start")).is_equal(0)
	assert_int(_count(events, "over")).is_equal(0)
	assert_int(logic.balloons).is_greater(30)


func test_race_heat_won_on_the_target_with_a_time_bonus() -> void:
	var logic := PumpLogic.new(3, PARAMS.merged({"race_balloons": 3}), "race", true, 1)
	var events := _run(logic, 130.0, 160.0, func(): return logic.phase == PumpLogic.Phase.BREAK)
	assert_int(_find(events, "heat_start").target).is_equal(3)
	var end := _find(events, "heat_end")
	assert_bool(end.won).is_true()
	assert_int(end.balloons).is_equal(3)
	assert_float(end.time_left).is_greater(60.0)
	assert_float(end.bonus).is_equal_approx(PumpLogic.BONUS_PER_SEC * end.time_left, 0.001)
	# One heat asked for: the break, then over.
	events = _run(logic, 10.0, 160.0)
	assert_int(_count(events, "over")).is_equal(1)
	assert_bool(logic.is_over()).is_true()
	assert_bool(logic.race_won()).is_true()


func test_race_heat_lost_on_the_clock_warns_first_and_keeps_the_balloon() -> void:
	var logic := PumpLogic.new(3, PARAMS.merged({"race_balloons": 50}), "race", true, 2)
	var events := _run(logic, 125.0, 120.0, func(): return logic.phase == PumpLogic.Phase.BREAK)
	var warn := _find(events, "warn_time")
	assert_float(warn.left).is_between(9.9, 10.0)
	var end := _find(events, "heat_end")
	assert_bool(end.won).is_false()
	assert_float(end.bonus).is_equal(0.0)
	assert_float(end.time_left).is_equal(0.0)
	# The break holds the balloon (no leak) and the next heat carries on with it.
	var held := logic.fill
	events = _run(logic, PumpLogic.BREAK_SEC - 0.5, 0.0)
	assert_float(logic.fill).is_equal(held)
	events = _run(logic, 1.0, 0.0)
	assert_int(_find(events, "heat_start").heat).is_equal(2)
	assert_int(logic.heat_balloons).is_equal(0)
	assert_float(logic.heat_left).is_greater(PumpLogic.HEAT_SEC - 1.0)


func test_race_in_a_timed_slot_plays_heats_back_to_back() -> void:
	var logic := PumpLogic.new(5, PARAMS.merged({"race_balloons": 2, "race_sec": 60}), "race", true, 0)
	var events := _run(logic, 600.0, 150.0)
	assert_int(_count(events, "heat_end")).is_greater(5)
	assert_int(_count(events, "over")).is_equal(0)
	assert_int(logic.heats_won).is_equal(logic.heats_done)


func test_max_in_rounds_ends_after_its_heats_with_no_winner() -> void:
	var logic := PumpLogic.new(5, PARAMS.merged({"race_sec": 30}), "max", true, 2)
	var events := _run(logic, 80.0, 150.0)
	var ends := events.filter(func(e): return e.type == "heat_end")
	assert_int(ends.size()).is_equal(2)
	assert_that(ends[0].won).is_null()
	assert_int(_count(events, "over")).is_equal(1)
	assert_that(logic.race_won()).is_null()


func test_sensor_loss_holds_the_balloon() -> void:
	var logic := _filling("medium", 120.0)
	_run(logic, 4.0, 120.0)
	var held := logic.fill
	for i in 90:
		logic.step(DT, 0.0, 0.0, false)
	assert_float(logic.fill).is_equal(held)
	assert_float(logic.smoothed).is_equal(0.0)


func test_recovery_has_a_gentle_line_a_cap_and_a_faster_flow() -> void:
	var logic := _filling("medium", 0.0, PARAMS.merged({"power_cap_watts": 120.0}), true)
	assert_float(logic.line_at(0.0)).is_equal_approx(30.0, 0.01)
	assert_float(logic.line_at(1.0)).is_equal_approx(60.0, 0.01)
	# 80 W fills a medium in 1.5 / (0.25 × 1.4 × 0.4) ≈ 10.7 s; 200 W counts only the 120 W cap.
	var times := []
	for watts in [80.0, 200.0, 120.0]:
		var l := _filling("medium", watts, PARAMS.merged({"power_cap_watts": 120.0}), true)
		var t := 0.0
		while l.phase == PumpLogic.Phase.FILL and t < 30.0:
			l.step(DT, watts, 85.0)
			t += DT
		times.append(t)
	assert_float(times[0]).is_between(10.2, 11.5)
	assert_float(times[1]).is_equal_approx(times[2], 0.1)


func test_keep_pumping_under_forty_rpm() -> void:
	var logic := PumpLogic.new(1, PARAMS)
	logic.step(DT, 50.0, 30.0)
	assert_bool(logic.keep_pumping).is_true()
	logic.step(DT, 50.0, 70.0)
	assert_bool(logic.keep_pumping).is_false()


func test_stats_track_power() -> void:
	var logic := PumpLogic.new(1, PARAMS)
	_run(logic, 5.0, 100.0)
	_run(logic, 5.0, 200.0)
	assert_float(logic.avg_power()).is_equal_approx(150.0, 1.0)
	assert_float(logic.peak_power).is_equal(200.0)


# --- Stars (epic #31): 3 stars needs about 1.3× effort; a perfect run at 1.0× stays short ---

## Points a minute over `seconds` for a rider who rides at `share` of FTP and, when a balloon has
## stalled for 2 s, digs in to just over its top line until it's tied (DESIGN.md §4).
func _points_a_minute(mode: String, share: float, target := 5, seconds := 600.0, seed := 1) -> float:
	var logic := PumpLogic.new(seed, PARAMS.merged({"race_balloons": target}), mode, mode == "race")
	var points := 0.0
	var stuck := 0.0
	var dig := false
	var t := 0.0
	while t < seconds:
		var watts := FTP * share
		if logic.phase == PumpLogic.Phase.FILL and logic.open < 0.5:
			stuck += DT
		else:
			stuck = 0.0
		if stuck > 2.0:
			dig = true
		if logic.phase != PumpLogic.Phase.FILL:
			dig = false
		if dig:
			watts = maxf(watts, logic.top_line() * 1.08)
		for e in logic.step(DT, watts, 85.0):
			if e.type == "filled":
				points += e.points
			elif e.type == "heat_end":
				points += e.bonus
		t += DT
	return points / (seconds / 60.0)


func _stars(per_minute: float, difficulty: String, variant: String) -> int:
	var info: GameInfo = auto_free(PumpGame.new()).info()
	return Stars.for_score(per_minute, info, difficulty, 60.0, variant)


func test_stars_need_about_one_point_three_times_effort() -> void:
	var targets := {"easy": 4, "standard": 5, "hard": 7}
	for difficulty in targets:
		for variant in ["", "race"]:
			var mode := "race" if variant == "race" else "max"
			var perfect := 0.0
			for seed in 3:
				perfect += _points_a_minute(mode, 0.6, targets[difficulty], 600.0, seed + 1) / 3.0
			# A strong, steady ride at 60% of FTP and 1.0× is 2 stars, short of 3.
			assert_int(_stars(perfect, difficulty, variant)).override_failure_message(
				"%s %s perfect %.0f" % [difficulty, variant, perfect]).is_equal(2)
			# The same ride at 1.3× (about 48% resistance) earns 3.
			assert_int(_stars(perfect * 1.3, difficulty, variant)).override_failure_message(
				"%s %s 1.3x %.0f" % [difficulty, variant, perfect * 1.3]).is_equal(3)


func test_an_easy_ride_earns_a_star_and_more_work_more_points() -> void:
	var light := _points_a_minute("max", 0.3)
	var steady := _points_a_minute("max", 0.5)
	var strong := _points_a_minute("max", 0.8)
	assert_float(light).is_less(steady)
	assert_float(steady).is_less(strong)
	assert_int(_stars(light, "standard", "")).is_equal(1)
	assert_int(_stars(steady, "standard", "")).is_equal(2)
