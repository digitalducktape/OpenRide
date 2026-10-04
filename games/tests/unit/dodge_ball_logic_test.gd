extends GdUnitTestSuite
## Dodge Ball's rules (#39), driven by scripted frames, plus the scene's pause and options.

const DT := 1.0 / 60.0
const FLOOR := 85.0
const TARGET := 200.0


func _logic(lives := true, params := {}, play_mode := "dodge") -> DodgeBallLogic:
	var p := {"cadence_floor": FLOOR, "target_watts": TARGET}
	p.merge(params, true)
	return DodgeBallLogic.new(1234, "standard", p, lives, play_mode)


## Runs `seconds` of frames; `lean` may be a Callable(logic) -> float. Returns all events.
func _run(logic: DodgeBallLogic, seconds: float, lean, cadence: float, power := 150.0) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		var l: float = lean.call(logic) if lean is Callable else float(lean)
		events.append_array(logic.step(DT, l, cadence, power))
	return events


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(e): return e.type == type).size()


## A lean that steers the bike away from the next ball to arrive.
func _dodger(logic: DodgeBallLogic) -> float:
	if logic.balls.is_empty():
		return 0.0
	var next: Dictionary = logic.balls[0]
	for b in logic.balls:
		if b.eta < next.eta:
			next = b
	var away := -1.0 if next.x1 > 0.0 else 1.0
	return away / DodgeBallLogic.STEERING_GAIN


## A lean that keeps the bike under the next ball to arrive.
func _chaser(logic: DodgeBallLogic) -> float:
	if logic.balls.is_empty():
		return 0.0
	var next: Dictionary = logic.balls[0]
	for b in logic.balls:
		if b.eta < next.eta:
			next = b
	return next.x1 / DodgeBallLogic.RIDER_RANGE / DodgeBallLogic.STEERING_GAIN


func test_lean_moves_the_bike_across_the_road() -> void:
	assert_float(DodgeBallLogic.x_for_lean(0.0)).is_equal(0.0)
	assert_float(DodgeBallLogic.x_for_lean(1.0)).is_equal(DodgeBallLogic.RIDER_RANGE)
	assert_float(DodgeBallLogic.x_for_lean(-3.0)).is_equal(-DodgeBallLogic.RIDER_RANGE)
	assert_float(DodgeBallLogic.x_for_lean(1.0 / DodgeBallLogic.STEERING_GAIN)).is_equal_approx(DodgeBallLogic.RIDER_RANGE, 0.001)
	assert_float(DodgeBallLogic.RIDER_RANGE + DodgeBallLogic.RIDER_HALF).is_less(DodgeBallLogic.ROAD_HALF)


func test_collision_is_ball_plus_bike_width() -> void:
	var reach := DodgeBallLogic.BALL_RADIUS + DodgeBallLogic.RIDER_HALF
	assert_bool(DodgeBallLogic.touches(1.0, 1.0)).is_true()
	assert_bool(DodgeBallLogic.touches(1.0 + reach - 0.01, 1.0)).is_true()
	assert_bool(DodgeBallLogic.touches(1.0 + reach + 0.01, 1.0)).is_false()


func test_every_ball_is_warned_at_least_0_8_s_ahead() -> void:
	var logic := _logic()
	var events := _run(logic, 150.0, _dodger, 95.0)
	var spawns := events.filter(func(e): return e.type == "spawn")
	assert_int(spawns.size()).is_greater(100)
	for e in spawns:
		assert_float(e.ball.eta0).is_greater_equal(DodgeBallLogic.WARNING_SEC)
		assert_float(e.ball.eta0).is_less_equal(DodgeBallLogic.SPAWN_ETA + 2.0)


func test_arrivals_never_bunch_up() -> void:
	var logic := _logic()
	var arrivals: Array[float] = []
	var t := 0.0
	for i in roundi(120.0 / DT):
		t += DT
		for e in logic.step(DT, _dodger(logic), 95.0, 150.0):
			if e.type == "spawn":
				arrivals.append(t + e.ball.eta0)
	arrivals.sort()
	for i in range(1, arrivals.size()):
		var gap := arrivals[i] - arrivals[i - 1]
		# Doubles arrive together; anything else is at least MIN_GAP_SEC apart.
		assert_bool(gap < 0.001 or gap >= DodgeBallLogic.MIN_GAP_SEC - 0.001).is_true()


func test_dodging_scores_ten_and_hitting_breaks_the_streak() -> void:
	var logic := _logic()
	var events := _run(logic, 30.0, _dodger, 95.0, 150.0)
	assert_int(logic.dodges).is_greater(10)
	for e in events.filter(func(e): return e.type == "dodge"):
		assert_float(e.points).is_equal(DodgeBallLogic.DODGE_POINTS)
	var chaser := _logic()
	_run(chaser, 30.0, _chaser, 95.0)
	assert_int(chaser.hits).is_greater(0)
	assert_int(chaser.longest_streak).is_less(chaser.hits + chaser.dodges)


func test_power_bonus_doubles_points() -> void:
	var logic := _logic()
	assert_float(logic.power_multiplier(TARGET - 1.0)).is_equal(1.0)
	assert_float(logic.power_multiplier(TARGET)).is_equal(2.0)
	var events := _run(logic, 20.0, _dodger, 95.0, TARGET + 20.0)
	var dodges := events.filter(func(e): return e.type == "dodge")
	assert_int(dodges.size()).is_greater(0)
	for e in dodges:
		assert_float(e.points).is_equal(DodgeBallLogic.DODGE_POINTS * DodgeBallLogic.POWER_BONUS)
	# No target: no bonus.
	assert_float(_logic(true, {"target_watts": 0.0}).power_multiplier(500.0)).is_equal(1.0)


func test_shield_drains_below_the_floor_and_refills_above() -> void:
	var logic := _logic()
	_run(logic, 1.0, _dodger, FLOOR - 1.0)
	assert_float(logic.shield).is_equal_approx(1.0 - 1.0 / DodgeBallLogic.SHIELD_DRAIN_SEC, 0.02)
	_run(logic, DodgeBallLogic.SHIELD_DRAIN_SEC, _dodger, FLOOR - 1.0)
	assert_float(logic.shield).is_equal(0.0)
	assert_bool(logic.shield_up()).is_false()
	# At the floor counts as above it.
	var events := _run(logic, DodgeBallLogic.SHIELD_REFILL_SEC + 0.1, _dodger, FLOOR)
	assert_float(logic.shield).is_equal(1.0)
	assert_int(_count(events, "shield_ready")).is_equal(1)


func test_a_hit_with_the_shield_up_only_breaks_the_shield() -> void:
	var logic := _logic()
	var events: Array[Dictionary] = []
	while logic.hits == 0:
		events.append_array(logic.step(DT, _chaser(logic), FLOOR + 10.0, 150.0))
	assert_int(_count(events, "shield_break")).is_equal(1)
	assert_int(_count(events, "hit")).is_equal(0)
	assert_int(logic.lives).is_equal(DodgeBallLogic.LIVES)
	assert_float(logic.shield).is_equal(0.0)


func test_a_hit_with_the_shield_down_costs_a_life_in_just_ride() -> void:
	var logic := _logic()
	logic.shield = 0.0
	var events: Array[Dictionary] = []
	while logic.hits == 0:
		events.append_array(logic.step(DT, _chaser(logic), FLOOR - 20.0, 150.0))
	var hit: Dictionary = events.filter(func(e): return e.type == "hit")[0]
	assert_int(logic.lives).is_equal(DodgeBallLogic.LIVES - 1)
	assert_float(hit.penalty).is_equal(0.0)


func test_a_hit_with_the_shield_down_costs_50_in_a_circuit() -> void:
	var logic := _logic(false)
	_run(logic, 20.0, _dodger, 95.0)
	var before := logic.run_points
	assert_float(before).is_greater(DodgeBallLogic.PENALTY)
	logic.shield = 0.0
	var events: Array[Dictionary] = []
	while logic.hits == 0:
		events.append_array(logic.step(DT, _chaser(logic), FLOOR - 20.0, 150.0))
	var hit: Dictionary = events.filter(func(e): return e.type == "hit")[0]
	assert_float(hit.penalty).is_equal(DodgeBallLogic.PENALTY)
	assert_int(logic.lives).is_equal(DodgeBallLogic.LIVES)
	assert_float(logic.run_points).is_less_equal(before - DodgeBallLogic.PENALTY + 2.0 * DodgeBallLogic.DODGE_POINTS)


func test_losing_every_life_ends_the_run_then_a_new_one_starts() -> void:
	var logic := _logic()
	_run(logic, 10.0, _dodger, 95.0)
	var first := logic.run_points
	var events := _run(logic, 60.0, _chaser, FLOOR - 30.0)
	assert_int(_count(events, "game_over")).is_greater_equal(1)
	assert_int(_count(events, "new_run")).is_greater_equal(1)
	assert_int(logic.run).is_greater(1)
	# The best run is kept as the score.
	assert_float(logic.best_run_points).is_greater_equal(first)
	# During the card nothing spawns.
	var over := _logic()
	over.shield = 0.0
	while over.game_over_left <= 0.0:
		over.step(DT, _chaser(over), FLOOR - 30.0, 150.0)
	assert_int(_count(_run(over, DodgeBallLogic.GAME_OVER_SEC - 0.1, 0.0, 95.0), "spawn")).is_equal(0)


func test_waves_raise_the_rate_and_add_ball_types() -> void:
	var logic := _logic()
	var events := _run(logic, 200.0, _dodger, 95.0)
	var waves := events.filter(func(e): return e.type == "wave").map(func(e): return e.wave)
	assert_array(waves).contains([2, 3])
	assert_float(logic.rate_at(90.0, 3)).is_greater(logic.rate_at(90.0, 1))
	assert_float(logic.rate_at(0.0)).is_equal_approx(0.6, 0.001)
	assert_float(logic.rate_at(DodgeBallLogic.RAMP_SEC)).is_equal_approx(1.5, 0.001)
	var kinds := {}
	for e in events.filter(func(e): return e.type == "spawn"):
		kinds[e.ball.kind] = true
	assert_bool(kinds.has("curve") and kinds.has("double")).is_true()
	# Circuits have no waves and no special balls.
	var circuit := _logic(false)
	var circuit_events := _run(circuit, 200.0, _dodger, 95.0)
	assert_int(_count(circuit_events, "wave")).is_equal(0)
	for e in circuit_events.filter(func(e): return e.type == "spawn"):
		assert_str(e.ball.kind).is_equal("plain")


func test_curve_balls_land_where_they_were_warned() -> void:
	var ball := {"x0": 3.0, "x1": 0.0, "eta": 2.0, "eta0": 2.0}
	assert_float(DodgeBallLogic.ball_x(ball)).is_equal(3.0)
	ball.eta = 0.0
	assert_float(DodgeBallLogic.ball_x(ball)).is_equal(0.0)


func test_stats_track_floor_time_and_power() -> void:
	var logic := _logic()
	_run(logic, 10.0, 0.0, FLOOR + 5.0, 100.0)
	_run(logic, 10.0, 0.0, FLOOR - 5.0, 300.0)
	assert_float(logic.pct_time_above_floor()).is_equal_approx(50.0, 1.0)
	assert_float(logic.avg_power()).is_equal_approx(200.0, 1.0)


func test_streak_chimes_at_5_10_20() -> void:
	var logic := _logic()
	var events := _run(logic, 60.0, _dodger, 95.0)
	var counts := events.filter(func(e): return e.type == "streak").map(func(e): return e.count)
	assert_array(counts).contains([5, 10, 20])


## Points a minute for a perfect rider (every ball dodged or caught) at 1.0×.
func _perfect_per_minute(difficulty: String, lives: bool, seconds: float, bonus: bool, play_mode := "dodge") -> float:
	var logic := DodgeBallLogic.new(99, difficulty, {"target_watts": TARGET}, lives, play_mode)
	var steer := _chaser if play_mode == "catch" else _dodger
	var events := _run(logic, seconds, steer, 100.0, TARGET + 50.0 if bonus else TARGET - 50.0)
	var points := 0.0
	for e in events:
		if e.type in ["dodge", "catch"]:
			points += e.points
	return points / (seconds / 60.0)


func test_stars_two_for_a_perfect_ride_three_needs_the_bonus_and_effort() -> void:
	var info: GameInfo = auto_free(load("res://games/dodge_ball/DodgeBall.gd").new()).info()
	assert_array(info.validate()).is_empty()
	for play_mode in DodgeBallLogic.MODES:
		var table: Dictionary = info.thresholds_for("catch" if play_mode == "catch" else "")
		for difficulty in ["easy", "standard", "hard"]:
			var t: Array = table[difficulty]
			# A 90 s circuit slot (no lives or waves) and a two-minute Just Ride.
			for setup in [[false, 90.0], [true, 120.0]]:
				var what := "%s %s %s" % [play_mode, difficulty, "just ride" if setup[0] else "circuit"]
				var plain := _perfect_per_minute(difficulty, setup[0], setup[1], false, play_mode)
				var bonus := _perfect_per_minute(difficulty, setup[0], setup[1], true, play_mode)
				# A perfect ride at 1.0× reaches 2 stars without the power bonus…
				assert_float(plain).override_failure_message("%s: perfect %.0f < 2 stars %d" % [what, plain, t[1]]).is_greater_equal(float(t[1]))
				# …and even with the bonus stays short of 3, which needs the effort multiplier (≤ 1.5×).
				assert_float(bonus).override_failure_message("%s: bonus %.0f reaches 3 stars %d" % [what, bonus, t[2]]).is_less(float(t[2]))
				assert_float(bonus * 1.5).override_failure_message("%s: 3 stars %d out of reach (%.0f)" % [what, t[2], bonus * 1.5]).is_greater_equal(float(t[2]))


# --- Speed ---

func test_road_speed_follows_cadence() -> void:
	assert_float(DodgeBallLogic.road_speed(0.0)).is_equal(0.0)
	assert_float(DodgeBallLogic.road_speed(-5.0)).is_equal(0.0)
	var cruise := DodgeBallLogic.road_speed(60.0)
	var fast := DodgeBallLogic.road_speed(100.0)
	assert_float(cruise).is_between(7.0, 11.0)  # a slow cruise
	assert_float(fast).is_greater_equal(20.0)  # clearly fast
	assert_float(fast / cruise).is_greater_equal(2.2)  # and you feel the difference
	var last := -1.0
	for rpm in range(0, 160, 5):
		var v := DodgeBallLogic.road_speed(rpm)
		assert_float(v).is_greater_equal(last)
		last = v
	assert_float(DodgeBallLogic.road_speed(200.0)).is_equal(DodgeBallLogic.SPEED_MAX)


func test_ball_timing_ignores_speed() -> void:
	# The same seed spawns the same arrivals at 40 rpm and at 120 rpm: fairness doesn't depend on
	# how fast the road goes.
	var slow := _logic(false)  # a circuit: no lives, so no game over at 40 rpm
	var fast := _logic(false)
	var a := _run(slow, 30.0, 0.0, 40.0).filter(func(e): return e.type == "spawn").map(func(e): return e.ball.eta0)
	var b := _run(fast, 30.0, 0.0, 120.0).filter(func(e): return e.type == "spawn").map(func(e): return e.ball.eta0)
	assert_array(a).is_equal(b)


# --- Catch mode ---

func test_catching_scores_and_builds_the_streak() -> void:
	var logic := _logic(true, {}, "catch")
	var events := _run(logic, 30.0, _chaser, 95.0, TARGET + 10.0)
	var catches := events.filter(func(e): return e.type == "catch")
	assert_int(catches.size()).is_greater(15)
	assert_int(logic.misses).is_equal(0)  # every ball is reachable
	for e in catches:
		assert_float(e.points).is_equal(DodgeBallLogic.DODGE_POINTS * DodgeBallLogic.POWER_BONUS)
	assert_int(logic.longest_streak).is_equal(catches.size())
	assert_int(_count(events, "dodge")).is_equal(0)


func test_every_catch_ball_is_within_reach() -> void:
	var logic := _logic(true, {}, "catch")
	var arrivals: Array = []
	var t := 0.0
	for i in roundi(200.0 / DT):
		t += DT
		for e in logic.step(DT, _chaser(logic), 95.0, 150.0):
			if e.type == "spawn":
				assert_str(e.ball.kind).is_not_equal("double")  # no doubles in Catch
				arrivals.append([t + e.ball.eta0, e.ball.x1])
	for i in range(1, arrivals.size()):
		var gap: float = arrivals[i][0] - arrivals[i - 1][0]
		var dx: float = absf(arrivals[i][1] - arrivals[i - 1][1])
		assert_float(dx).is_less_equal(DodgeBallLogic.REACH_SPEED * gap + 0.001)


func test_a_miss_costs_the_streak_and_three_in_a_row_a_life() -> void:
	var logic := _logic(true, {}, "catch")
	_run(logic, 10.0, _chaser, 95.0)
	assert_int(logic.streak).is_greater(2)
	var before := logic.run_points
	var events := _run(logic, 6.0, _dodger, 95.0)  # now steer away from every ball
	assert_int(logic.streak).is_equal(0)
	assert_int(_count(events, "miss")).is_greater_equal(3)
	assert_int(logic.lives).is_less(DodgeBallLogic.LIVES)
	assert_float(logic.run_points).is_equal(before)  # nothing taken off


func test_a_catch_with_the_shield_down_is_fumbled() -> void:
	var logic := _logic(true, {}, "catch")
	var events := _run(logic, 12.0, _chaser, FLOOR - 20.0)  # the shield drains in 3 s
	assert_int(_count(events, "fumble")).is_greater(0)
	for e in events.filter(func(e): return e.type == "catch"):
		assert_float(e.ball.eta0).is_greater(0.0)
	assert_int(logic.fumbles).is_greater(0)
	assert_float(logic.shield).is_equal(0.0)


func test_catch_circuits_never_take_points_off() -> void:
	var logic := _logic(false, {}, "catch")
	var events := _run(logic, 30.0, _dodger, 95.0)
	assert_int(_count(events, "miss")).is_greater(10)
	assert_int(_count(events, "game_over")).is_equal(0)
	assert_float(logic.run_points).is_equal(0.0)


func test_switching_mode_keeps_thrown_balls_and_resets_the_streak() -> void:
	var logic := _logic()
	_run(logic, 10.0, _dodger, 95.0)
	var thrown := logic.balls.duplicate()
	assert_bool(thrown.is_empty()).is_false()
	logic.set_mode("catch")
	assert_int(logic.streak).is_equal(0)
	for ball in thrown:
		assert_str(ball.mode).is_equal("dodge")
	var events := _run(logic, 5.0, _chaser, 95.0)
	var new_balls := events.filter(func(e): return e.type == "spawn")
	assert_str(new_balls[0].ball.mode).is_equal("catch")


func test_time_of_day_follows_the_clock() -> void:
	assert_str(DodgeTimeOfDay.for_hour(6)).is_equal("dawn")
	assert_str(DodgeTimeOfDay.for_hour(12)).is_equal("day")
	assert_str(DodgeTimeOfDay.for_hour(18)).is_equal("dusk")
	assert_str(DodgeTimeOfDay.for_hour(23)).is_equal("night")
	assert_str(DodgeTimeOfDay.for_hour(3)).is_equal("night")
	assert_str(DodgeTimeOfDay.resolve("dusk", 12)).is_equal("dusk")
	assert_str(DodgeTimeOfDay.resolve("auto", 12)).is_equal("day")
	for name in DodgeTimeOfDay.NAMES:
		assert_object(DodgeTimeOfDay.load_preset(name)).is_not_null()
