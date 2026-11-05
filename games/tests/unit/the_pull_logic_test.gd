extends GdUnitTestSuite
## The Pull's rules (#79): the drag curve, speed integration, the forgiving stall with the
## bike's once-a-second readings, Full Pull, the modes and the stars. DESIGN.md is the spec.

const DT := 1.0 / 30.0
const FTP := 200.0


func _logic(difficulty := "standard", mode := "open", rounds := 1, duration := -1.0, best := 0.0) -> PullLogic:
	return PullLogic.new({"ftp_watts": FTP}, difficulty, mode, rounds, duration, best)


## Steps until `until` is true or `seconds` pass. `power` is a Callable(t) -> watts, sampled as
## the bike reports it: a new reading every `report_sec`. Returns every event; `clock` holds the
## seconds run in `clock[0]`.
func _run(logic: PullLogic, seconds: float, power: Callable, until := Callable(), clock := [0.0],
		report_sec := 1.0) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var reading := 0.0
	var next_report := 0.0
	for i in roundi(seconds / DT):
		if clock[0] >= next_report:
			reading = power.call(clock[0])
			next_report += report_sec
		events.append_array(logic.step(DT, reading, clock[0]))
		clock[0] += DT
		if until.is_valid() and until.call():
			break
	return events


func _steady(watts: float) -> Callable:
	return func(_t: float) -> float: return watts


func _find(events: Array[Dictionary], type: String) -> Dictionary:
	for e in events:
		if e.type == type:
			return e
	return {}


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type).size()


## One pull at steady power, from the horn: returns its pull_end event.
func _one_pull(logic: PullLogic, watts: float) -> Dictionary:
	var events := _run(logic, 900.0, _steady(watts), func() -> bool: return logic.phase == PullLogic.Phase.RESULT)
	return _find(events, "pull_end")


# --- Drag ---

func test_drag_starts_at_30_percent_and_reaches_ftp_at_d_ref() -> void:
	var logic := _logic()
	assert_float(logic.required_at(0.0)).is_equal_approx(60.0, 0.001)
	assert_float(logic.required_at(150.0)).is_equal_approx(130.0, 0.001)
	assert_float(logic.required_at(300.0)).is_equal_approx(FTP, 0.001)


func test_difficulty_and_params_set_d_ref() -> void:
	assert_float(_logic("easy").d_ref).is_equal(360.0)
	assert_float(_logic("hard").d_ref).is_equal(250.0)
	var tuned := PullLogic.new({"ftp_watts": FTP, "d_ref_m": 280.0, "full_factor": 1.1})
	assert_float(tuned.d_ref).is_equal(280.0)
	assert_float(tuned.full_m).is_equal_approx(308.0, 0.001)


func test_full_pull_line_needs_108_percent() -> void:
	var logic := _logic()
	assert_float(logic.required_at(logic.full_m) / FTP).is_equal_approx(1.084, 0.001)


# --- Speed ---

func test_set_phase_holds_the_sled_then_the_horn() -> void:
	var logic := _logic()
	var events := _run(logic, PullLogic.SET_SEC - 0.1, _steady(400.0))
	assert_float(logic.distance).is_equal(0.0)
	assert_int(_count(events, "go")).is_equal(0)
	events = _run(logic, 0.3, _steady(400.0))
	assert_int(_count(events, "go")).is_equal(1)
	assert_int(logic.phase).is_equal(PullLogic.Phase.PULL)


func test_speed_follows_the_square_root_of_the_gap() -> void:
	var logic := _logic()
	assert_float(logic.target_speed(FTP, 0.0)).is_equal_approx(PullLogic.V_MAX, 0.001)
	# A quarter of the gap: half the speed.
	assert_float(logic.target_speed(60.0 + 0.25 * 0.7 * FTP, 0.0)).is_equal_approx(PullLogic.V_MAX / 2.0, 0.001)
	assert_float(logic.target_speed(30.0, 0.0)).is_equal(0.0)
	# A sprint is capped.
	assert_float(logic.target_speed(10000.0, 0.0)).is_equal_approx(PullLogic.V_MAX * sqrt(PullLogic.G_CAP), 0.001)


func test_speed_eases_and_never_goes_backwards() -> void:
	var logic := _logic()
	_run(logic, PullLogic.SET_SEC + 10.0, _steady(FTP))
	var fast := logic.speed
	var before := logic.distance
	assert_float(fast).is_greater(1.5)
	# No power at all: the sled slows at DECEL, and the distance never drops.
	_run(logic, 1.0, _steady(0.0))
	assert_float(logic.speed).is_less(fast)
	assert_float(logic.speed).is_greater(fast - PullLogic.DECEL * 1.1)
	assert_float(logic.distance).is_greater_equal(before)
	_run(logic, 8.0, _steady(0.0))
	assert_float(logic.speed).is_equal(0.0)


func test_distance_points_are_ten_a_metre() -> void:
	var logic := _logic()
	var points := [0.0]
	for i in roundi((PullLogic.SET_SEC + 30.0) / DT):
		logic.step(DT, FTP)
		points[0] += logic.last_points
	assert_float(points[0]).is_equal_approx(logic.distance * 10.0, 0.01)


# --- A pull's length ---

func test_a_steady_ftp_pull_lasts_three_to_five_minutes_at_every_difficulty() -> void:
	for difficulty in ["easy", "standard", "hard"]:
		var logic := _logic(difficulty)
		var end := _one_pull(logic, FTP)
		assert_str(end.how).is_equal("stall")
		assert_float(end.sec / 60.0).override_failure_message("%s pull %.2f min" % [difficulty, end.sec / 60.0]).is_between(3.0, 5.0)
		# It stalls just short of d_ref, where the sled needs FTP.
		assert_float(end.distance / logic.d_ref).is_between(0.97, 1.0)


func test_half_ftp_goes_about_a_quarter_of_the_way() -> void:
	var end := _one_pull(_logic(), FTP * 0.5)
	assert_float(end.distance).is_between(75.0, 95.0)
	assert_float(end.sec / 60.0).is_between(1.5, 2.5)


func test_more_watts_go_further() -> void:
	var last := 0.0
	for share in [0.4, 0.6, 0.8, 1.0]:
		var d: float = _one_pull(_logic(), FTP * share).distance
		assert_float(d).is_greater(last)
		last = d


# --- Stall ---

func test_stall_needs_five_seconds_of_crawling_with_a_warning_ahead() -> void:
	var logic := _logic()
	_run(logic, PullLogic.SET_SEC + 20.0, _steady(FTP))
	# Stop pedalling: the sled eases down, crawls, warns, then stalls.
	var events: Array[Dictionary] = []
	var crawl_at := -1.0
	var warn_at := -1.0
	var stall_at := -1.0
	var t := 0.0
	while logic.phase == PullLogic.Phase.PULL and t < 30.0:
		for e in logic.step(DT, 0.0):
			events.append(e)
			if e.type == "dig_in":
				warn_at = t
			elif e.type == "pull_end":
				stall_at = t
		if crawl_at < 0.0 and logic.speed < PullLogic.CRAWL:
			crawl_at = t
		t += DT
	assert_str(_find(events, "pull_end").how).is_equal("stall")
	assert_float(stall_at - crawl_at).is_equal_approx(PullLogic.STALL_SEC, 0.1)
	assert_float(stall_at - warn_at).is_greater_equal(2.0)


func test_a_slow_start_isnt_a_stall() -> void:
	var logic := _logic()
	# No pedalling for 12 s after the horn, then a normal pull.
	var events := _run(logic, PullLogic.SET_SEC + 12.0, _steady(0.0))
	assert_int(_count(events, "pull_end")).is_equal(0)
	_run(logic, 30.0, _steady(FTP))
	assert_int(logic.phase).is_equal(PullLogic.Phase.PULL)
	assert_float(logic.distance).is_greater(20.0)


func test_never_pedalling_stalls_after_the_grace() -> void:
	var logic := _logic()
	var clock := [0.0]
	var events := _run(logic, 60.0, _steady(0.0), func() -> bool: return logic.phase == PullLogic.Phase.RESULT, clock)
	assert_float(_find(events, "pull_end").distance).is_equal(0.0)
	assert_float(clock[0]).is_equal_approx(PullLogic.SET_SEC + PullLogic.GRACE_SEC + PullLogic.STALL_SEC, 0.2)


func test_noisy_once_a_second_readings_dont_stall_early() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var steady := _one_pull(_logic(), FTP)
	var noisy_logic := _logic()
	var events := _run(noisy_logic, 900.0, func(_t: float) -> float: return FTP * rng.randf_range(0.85, 1.15),
		func() -> bool: return noisy_logic.phase == PullLogic.Phase.RESULT)
	var noisy := _find(events, "pull_end")
	assert_float(noisy.distance).is_greater(steady.distance * 0.97)
	assert_float(noisy.sec).is_greater(steady.sec * 0.9)


func test_a_dropped_reading_mid_pull_doesnt_stall() -> void:
	var logic := _logic()
	# 0.9 FTP, with one reading of 0 W every 20 s (a missed pedal stroke), near the end too.
	var events := _run(logic, 900.0, func(t: float) -> float: return 0.0 if fmod(t, 20.0) < 1.0 and t > 10.0 else FTP * 0.9,
		func() -> bool: return logic.phase == PullLogic.Phase.RESULT)
	var steady := _one_pull(_logic(), FTP * 0.9)
	assert_float(_find(events, "pull_end").distance).is_greater(steady.distance * 0.97)


func test_picking_up_again_clears_the_warning() -> void:
	var logic := _logic()
	_run(logic, PullLogic.SET_SEC + 20.0, _steady(FTP))
	var events := _run(logic, 20.0, _steady(0.0), func() -> bool: return logic.warned)
	assert_int(_count(events, "dig_in")).is_equal(1)
	events = _run(logic, 6.0, _steady(FTP * 1.5))
	assert_int(_count(events, "dig_in_clear")).is_equal(1)
	assert_int(logic.phase).is_equal(PullLogic.Phase.PULL)


func test_sensor_loss_freezes_the_sled_and_the_stall_clock() -> void:
	var logic := _logic()
	_run(logic, PullLogic.SET_SEC + 20.0, _steady(FTP))
	_run(logic, 20.0, _steady(0.0), func() -> bool: return logic.warned)
	var d := logic.distance
	var stall := logic.stall_sec
	for i in 300:
		logic.step(DT, 0.0, 0.0, false)
	assert_float(logic.distance).is_equal(d)
	assert_float(logic.stall_sec).is_equal(stall)
	assert_int(logic.phase).is_equal(PullLogic.Phase.PULL)


# --- Full Pull and the best ---

func test_full_pull_ends_with_the_bonus() -> void:
	var logic := _logic()
	var end := _one_pull(logic, FTP * 1.15)
	assert_str(end.how).is_equal("full")
	assert_float(end.distance).is_equal_approx(logic.full_m, 0.001)
	assert_float(end.points).is_equal(PullLogic.FULL_PULL_BONUS)
	assert_int(logic.full_pulls).is_equal(1)


func test_boards_every_25_metres() -> void:
	var logic := _logic()
	var events := _run(logic, 900.0, _steady(FTP), func() -> bool: return logic.phase == PullLogic.Phase.RESULT)
	var boards := events.filter(func(e: Dictionary) -> bool: return e.type == "board")
	assert_int(boards.size()).is_equal(floori(logic.best_pull_m / 25.0))
	assert_float(boards[0].metres).is_equal(25.0)


func test_best_flag_events_and_a_new_best() -> void:
	var logic := _logic("standard", "open", 1, -1.0, 150.0)
	var events := _run(logic, 900.0, _steady(FTP), func() -> bool: return logic.phase == PullLogic.Phase.RESULT)
	assert_int(_count(events, "best_near")).is_equal(1)
	assert_int(_count(events, "best_passed")).is_equal(1)
	assert_bool(_find(events, "pull_end").new_best).is_true()
	assert_float(logic.best_distance).is_greater(290.0)


func test_short_of_the_best_isnt_a_new_best() -> void:
	var logic := _logic("standard", "open", 1, -1.0, 280.0)
	var end := _one_pull(logic, FTP * 0.6)
	assert_bool(end.new_best).is_false()
	assert_float(logic.best_distance).is_equal(280.0)


# --- Modes ---

func test_rounds_play_n_pulls_with_a_60_second_rest() -> void:
	var logic := _logic("standard", "rounds", 2, 600.0)
	var events := _run(logic, 1200.0, _steady(FTP * 0.5), func() -> bool: return logic.is_done())
	assert_int(_count(events, "pull_end")).is_equal(2)
	assert_int(_count(events, "set")).is_equal(1)
	assert_float(_find(events, "recovery").sec).is_equal(PullLogic.REST_SEC)
	assert_int(_count(events, "done")).is_equal(1)


func test_timed_ride_starts_pulls_until_the_timer_and_lets_the_last_finish() -> void:
	var logic := _logic("standard", "timed", 1, 240.0)
	var clock := [0.0]
	var events := _run(logic, 600.0, _steady(FTP * 0.5), func() -> bool: return logic.is_done(), clock)
	# Half-FTP pulls last about two minutes; with a 30 s rest, the second starts and finishes.
	assert_int(_count(events, "pull_end")).is_equal(2)
	assert_float(_find(events, "recovery").sec).is_equal(PullLogic.TIMED_REST_SEC)
	assert_float(clock[0]).is_greater(240.0)
	assert_float(clock[0]).is_less(240.0 * PullLogic.OVERTIME + PullLogic.RESULT_SEC)


func test_timed_ride_starts_no_pull_when_the_rest_would_use_up_the_time() -> void:
	# Half-FTP: the pull and its result end near 122 s; 150 - 122 - 30 s of rest leaves no pull.
	var logic := _logic("standard", "timed", 1, 150.0)
	var events := _run(logic, 600.0, _steady(FTP * 0.5), func() -> bool: return logic.is_done())
	assert_int(_count(events, "pull_end")).is_equal(1)
	assert_int(_count(events, "recovery")).is_equal(0)


func test_overtime_guard_ends_a_long_pull_before_kotlins_hard_stop() -> void:
	var logic := _logic("standard", "timed", 1, 120.0)
	var clock := [0.0]
	var events := _run(logic, 900.0, _steady(FTP), func() -> bool: return logic.is_done(), clock)
	var end := _find(events, "pull_end")
	assert_str(end.how).is_equal("time")
	assert_float(end.distance).is_greater(100.0)
	assert_float(clock[0]).is_less(120.0 * 1.5)


func test_open_ride_keeps_pulling_and_end_now_counts_the_pull() -> void:
	var logic := _logic()
	var events := _run(logic, 900.0, _steady(FTP * 0.5), func() -> bool: return logic.pull_index == 3 and logic.phase == PullLogic.Phase.PULL)
	assert_int(_count(events, "pull_end")).is_equal(2)
	_run(logic, 20.0, _steady(FTP * 0.5))
	var end := logic.end_now()
	assert_str(end.how).is_equal("time")
	assert_float(end.distance).is_greater(10.0)
	assert_bool(logic.is_done()).is_true()
	assert_dict(logic.end_now()).is_empty()


# --- Stars (best-pull points × the effort multiplier) ---

func _stars(points: float, d_ref: float) -> int:
	return Stars.count(points, PullLogic.star_thresholds_for(d_ref))


func test_thresholds_follow_d_ref() -> void:
	assert_array(PullLogic.star_thresholds_for(300.0)).is_equal([600, 2001, 3600])
	assert_array(PullLogic.star_thresholds_for(360.0)).is_equal([720, 2401, 4320])


func test_ftp_at_one_x_stays_short_of_three_stars_and_one_point_three_reaches_it() -> void:
	for difficulty in ["easy", "standard", "hard"]:
		var logic := _logic(difficulty)
		var end := _one_pull(logic, FTP)
		var points := PullLogic.pull_points(end.distance, false)
		assert_int(_stars(points, logic.d_ref)).override_failure_message("%s 1.0x" % difficulty).is_equal(2)
		assert_int(_stars(points * 1.3, logic.d_ref)).override_failure_message("%s 1.3x" % difficulty).is_equal(3)


func test_half_ftp_earns_a_star_and_a_full_pull_earns_three() -> void:
	var logic := _logic()
	var half := _one_pull(logic, FTP * 0.5)
	assert_int(_stars(PullLogic.pull_points(half.distance, false), logic.d_ref)).is_equal(1)
	var full_logic := _logic()
	var full := _one_pull(full_logic, FTP * 1.15)
	assert_int(_stars(PullLogic.pull_points(full.distance, true), full_logic.d_ref)).is_equal(3)


func test_hud_numbers_share_one_rounding() -> void:
	var logic := _logic()
	logic.distance = 123.9999
	assert_int(PullLogic.shown_m(logic.distance)).is_equal(124)
	logic.distance = 123.6
	assert_int(PullLogic.shown_m(logic.distance)).is_equal(123)
	assert_int(logic.shown_need()).is_equal(roundi(logic.required_watts()))
