extends GdUnitTestSuite
## Dodge Ball's rules (#39), driven by scripted frames, plus the scene's pause and options.

const DT := 1.0 / 60.0
const FLOOR := 85.0
const TARGET := 200.0


func _logic(lives := true, params := {}) -> DodgeBallLogic:
	var p := {"cadence_floor": FLOOR, "target_watts": TARGET}
	p.merge(params, true)
	return DodgeBallLogic.new(1234, "standard", p, lives)


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


func test_a_perfect_run_at_1x_stays_short_of_three_stars() -> void:
	var info: GameInfo = auto_free(load("res://games/dodge_ball/DodgeBall.gd").new()).info()
	assert_array(info.validate()).is_empty()
	for difficulty in ["easy", "standard", "hard"]:
		var level: Dictionary = DodgeBallLogic.LEVELS[difficulty]
		var logic := DodgeBallLogic.new(99, difficulty, {"target_watts": TARGET}, true)
		_run(logic, 120.0, _dodger, 100.0, TARGET + 50.0)
		var per_minute := logic.dodges * DodgeBallLogic.DODGE_POINTS * 2.0 / 2.0
		assert_float(per_minute).is_less(float(info.star_thresholds[difficulty][2]))
		assert_float(per_minute * 1.5).is_greater(float(info.star_thresholds[difficulty][2]))
		assert_float(level.cadence_floor).is_greater(0.0)


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
