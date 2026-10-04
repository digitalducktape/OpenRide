extends GdUnitTestSuite
## Tug of War's rules (#40), driven by scripted power.

const DT := 1.0 / 60.0
const FTP := 200.0
const PARAMS := {"ftp": 200.0, "bot_watts": 220.0, "surge_watts": 260.0}


## Runs frames at a fixed power until `seconds` pass or `until` (checked each frame) is true;
## returns all events.
func _run(logic: TugLogic, seconds: float, power: float, brace := false, until := Callable()) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		events.append_array(logic.step(DT, power, 80.0, brace))
		if until.is_valid() and until.call():
			break
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e): return e.type)


func _find(events: Array[Dictionary], type: String) -> Dictionary:
	for e in events:
		if e.type == type:
			return e
	return {}


## A logic with no surges in the way, to test the rope alone.
func _calm(mode := "endless", best_of := 3) -> TugLogic:
	var logic := TugLogic.new(1, PARAMS, mode, best_of)
	logic._next_surge = 1000.0
	return logic


func test_equal_watts_is_a_stalemate() -> void:
	var logic := _calm()
	_run(logic, 40.0, 220.0)
	assert_float(logic.p).is_equal_approx(0.0, 0.0001)
	assert_int(logic.phase).is_equal(TugLogic.Phase.ROUND)


func test_twenty_percent_over_wins_in_about_twenty_seconds() -> void:
	var logic := _calm()
	# 20% of FTP above the bot: 220 + 40 = 260 W.
	var t := 0.0
	var won := false
	for i in roundi(40.0 / DT):
		t += DT
		for e in logic.step(DT, 260.0, 80.0):
			if e.type == "round_end":
				won = e.won
		if logic.phase != TugLogic.Phase.ROUND:
			break
	assert_bool(won).is_true()
	assert_float(t).is_between(19.0, 21.0)


func test_behind_pulls_the_rope_the_other_way() -> void:
	var logic := _calm()
	# 40 W (20% of FTP) short: p reaches -1 in 20 s, and the round stops there.
	var events := _run(logic, 60.0, 180.0, false, func(): return logic.phase != TugLogic.Phase.ROUND)
	var end := _find(events, "round_end")
	assert_bool(end.is_empty()).is_false()
	assert_bool(end.won).is_false()
	assert_int(logic.losses).is_equal(1)
	assert_float(logic.p).is_equal(-1.0)


func test_buzzer_decides_by_the_side_of_the_rope() -> void:
	var logic := _calm()
	# A sliver over the bot for the whole round: p stays under +1, above 0 at the buzzer.
	var events := _run(logic, 61.0, 225.0)
	var end := _find(events, "round_end")
	assert_bool(end.won).is_true()
	assert_float(logic.p).is_between(0.0, 1.0)
	# A dead heat at the buzzer is a loss: p must be above 0.
	var tied := _calm()
	var tied_events := _run(tied, 61.0, 220.0)
	assert_bool(_find(tied_events, "round_end").won).is_false()


func test_surges_are_telegraphed_a_second_early_and_spaced() -> void:
	var logic := TugLogic.new(7, PARAMS, "endless")
	var surge_starts: Array[float] = []
	var telegraph_gaps: Array[float] = []
	var clock := 0.0
	var telegraph_at := -1.0
	# Hold the stalemate so the round never ends; watch two minutes of surges.
	for i in roundi(110.0 / DT):
		clock += DT
		var power := logic.bot_power_now()
		for e in logic.step(DT, power, 80.0):
			match e.type:
				"telegraph":
					telegraph_at = clock
				"surge_start":
					surge_starts.append(clock)
					telegraph_gaps.append(clock - telegraph_at)
		if logic.phase != TugLogic.Phase.ROUND:
			# A dead heat is lost at each buzzer; start the clock over for the next round.
			surge_starts.append(-1.0)
			clock = 0.0
			telegraph_at = -1.0
	assert_int(surge_starts.size()).is_greater(2)
	for gap in telegraph_gaps:
		assert_float(gap).is_equal_approx(TugLogic.TELEGRAPH_SEC, 0.05)
	for i in range(1, surge_starts.size()):
		if surge_starts[i] > 0.0 and surge_starts[i - 1] > 0.0:
			assert_float(surge_starts[i] - surge_starts[i - 1]).is_greater_equal(TugLogic.SURGE_GAP_MIN - 0.05)


func test_a_surge_lifts_the_bot_for_five_seconds() -> void:
	var logic := TugLogic.new(3, PARAMS, "endless")
	logic._next_surge = 2.0
	var seen_surge := 0.0
	for i in roundi(10.0 / DT):
		logic.step(DT, 200.0, 80.0)
		if logic.surge_state == "surge":
			assert_float(logic.bot_power_now()).is_equal(260.0)
			seen_surge += DT
	assert_float(seen_surge).is_equal_approx(TugLogic.SURGE_SEC, 0.1)


func test_a_surge_is_answered_when_the_rope_holds() -> void:
	var held := TugLogic.new(3, PARAMS, "endless")
	held._next_surge = 2.0
	var events := _run(held, 9.0, 260.0)  # matches the surge: p never falls
	assert_bool(_find(events, "surge_end").answered).is_true()
	assert_int(held.surges_answered).is_equal(1)
	var lost := TugLogic.new(3, PARAMS, "endless")
	lost._next_surge = 2.0
	var lost_events: Array[Dictionary] = []
	# Easy pedalling through the surge: p drops by 0.25 * 60/200 * 5 = 0.375 > 0.2.
	for i in roundi(9.0 / DT):
		lost_events.append_array(lost.step(DT, 200.0, 80.0))
	assert_bool(_find(lost_events, "surge_end").answered).is_false()


func test_brace_slows_the_fall_only_during_a_surge() -> void:
	var a := TugLogic.new(3, PARAMS, "endless")
	var b := TugLogic.new(3, PARAMS, "endless")
	a._next_surge = 0.5
	b._next_surge = 0.5
	_run(a, 4.0, 200.0, false)
	_run(b, 4.0, 200.0, true)
	assert_float(b.p).is_greater(a.p)
	# Outside a surge a brace changes nothing.
	var c := _calm()
	var d := _calm()
	_run(c, 4.0, 200.0, false)
	_run(d, 4.0, 200.0, true)
	assert_float(c.p).is_equal_approx(d.p, 0.0001)


func test_brace_never_adds_to_a_gain() -> void:
	var a := TugLogic.new(3, PARAMS, "endless")
	var b := TugLogic.new(3, PARAMS, "endless")
	a._next_surge = 0.5
	b._next_surge = 0.5
	_run(a, 4.0, 300.0, false)
	_run(b, 4.0, 300.0, true)
	assert_float(a.p).is_equal_approx(b.p, 0.0001)


func test_margin_points_only_for_watts_over_the_bot() -> void:
	var logic := _calm()
	logic.step(1.0, 250.0, 80.0)  # 30 W over
	assert_float(logic.last_margin_points).is_equal_approx(30.0 * TugLogic.MARGIN_POINTS, 0.001)
	logic.step(1.0, 150.0, 80.0)
	assert_float(logic.last_margin_points).is_equal(0.0)


func test_low_cadence_only_sets_the_flag() -> void:
	var logic := _calm()
	logic.step(DT, 220.0, 40.0)
	assert_bool(logic.keep_pedaling).is_true()
	logic.step(DT, 220.0, 60.0)
	assert_bool(logic.keep_pedaling).is_false()


func test_match_is_best_of_n_and_recovery_runs_between_rounds() -> void:
	var logic := _calm("match", 3)
	var events := _run(logic, 40.0, 300.0, false, func(): return logic.phase != TugLogic.Phase.ROUND)
	assert_int(logic.wins).is_equal(1)
	assert_int(logic.phase).is_equal(TugLogic.Phase.ROUND_END)
	events = _run(logic, TugLogic.ROUND_END_SEC + 0.1, 300.0)
	assert_array(_types(events)).contains(["recovery_start"])
	assert_int(logic.phase).is_equal(TugLogic.Phase.RECOVERY)
	events = _run(logic, TugLogic.RECOVERY_SEC + 0.1, 0.0)
	assert_array(_types(events)).contains(["round_start"])
	assert_int(logic.phase).is_equal(TugLogic.Phase.ROUND)
	logic._next_surge = 1000.0
	# Win the second round: two wins settle a best of three.
	_run(logic, 40.0, 300.0, false, func(): return logic.phase != TugLogic.Phase.ROUND)
	events = _run(logic, TugLogic.ROUND_END_SEC + 0.1, 0.0)
	assert_array(_types(events)).contains(["match_end"])
	assert_bool(logic.is_over()).is_true()
	assert_bool(logic.rider_won()).is_true()


func test_ladder_raises_the_bot_each_win_and_ends_on_the_first_loss() -> void:
	var logic := _calm("ladder")
	assert_float(logic.bot_watts()).is_equal(220.0)
	_run(logic, 40.0, 400.0, false, func(): return logic.phase != TugLogic.Phase.ROUND)
	_run(logic, TugLogic.ROUND_END_SEC + 0.1, 0.0)
	assert_float(logic.next_bot_watts()).is_equal(220.0 + 10.0)
	_run(logic, TugLogic.RECOVERY_SEC + 0.1, 0.0)
	assert_int(logic.rung).is_equal(1)
	assert_float(logic.bot_watts()).is_equal(230.0)
	logic._next_surge = 1000.0
	_run(logic, 70.0, 0.0, false, func(): return logic.phase != TugLogic.Phase.ROUND)
	var events := _run(logic, TugLogic.ROUND_END_SEC + 0.1, 0.0)
	assert_array(_types(events)).contains(["match_end"])
	assert_int(logic.wins).is_equal(1)
	assert_int(logic.losses).is_equal(1)
	assert_bool(logic.rider_won()).is_false()


func test_endless_repeats_rounds_without_recovery() -> void:
	var logic := _calm("endless")
	_run(logic, 40.0, 300.0, false, func(): return logic.phase != TugLogic.Phase.ROUND)
	var events := _run(logic, TugLogic.ROUND_END_SEC + 0.1, 300.0)
	assert_array(_types(events)).contains(["round_start"])
	assert_int(logic.phase).is_equal(TugLogic.Phase.ROUND)
	assert_int(logic.round_index).is_equal(2)
	# The rope starts the new round at the middle (a few frames of pulling since).
	assert_float(logic.p).is_between(0.0, 0.05)


func test_the_same_seed_schedules_the_same_surges() -> void:
	var a := TugLogic.new(11, PARAMS, "endless")
	var b := TugLogic.new(11, PARAMS, "endless")
	assert_float(a._next_surge).is_equal(b._next_surge)
	var c := TugLogic.new(12, PARAMS, "endless")
	assert_float(a._next_surge).is_not_equal(c._next_surge)


## Points a minute of a 5-minute endless ride that always holds `over` of FTP above the bot's
## watts (answering its surges), scaled by the effort multiplier `mult`.
func _points_per_minute(over: float, mult: float) -> float:
	var logic := TugLogic.new(5, PARAMS, "endless")
	var points := 0.0
	var minutes := 5.0
	for i in roundi(minutes * 60.0 / DT):
		var power := logic.bot_power_now() + over * FTP
		var events := logic.step(DT, power, 80.0)
		points += logic.last_margin_points * mult
		for e in events:
			if e.type == "round_end":
				points += e.points * mult
	return points / minutes


func test_a_perfect_ride_reaches_two_stars_and_three_needs_effort() -> void:
	var info := GameRegistry.info("tug_of_war")
	for difficulty in ["easy", "standard", "hard"]:
		# Holding 15% of FTP over the bot all the time, at 1.0×.
		var perfect := _points_per_minute(0.15, 1.0)
		assert_int(Stars.for_score(perfect, info, difficulty, 60.0, "")).is_equal(2)
		# The same ride with a 1.35× effort multiplier earns the third star.
		var strong := _points_per_minute(0.15, 1.35)
		assert_int(Stars.for_score(strong, info, difficulty, 60.0, "")).is_equal(3)
		# A tie-ish ride (just over the bot) earns little.
		var easy_ride := _points_per_minute(0.02, 1.0)
		assert_int(Stars.for_score(easy_ride, info, difficulty, 60.0, "")).is_less(2)
