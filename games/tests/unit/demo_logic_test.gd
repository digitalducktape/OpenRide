extends GdUnitTestSuite
## The demo game's rules, driven by scripted frames.

const DT := 1.0 / 60.0


## Runs `seconds` of frames at a fixed lean and cadence; returns all events.
func _run(logic: DemoLogic, seconds: float, lean: float, cadence: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		events.append_array(logic.step(DT, lean, cadence))
	return events


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(e): return e.type == type).size()


func test_lean_maps_to_the_screen_with_margins() -> void:
	assert_float(DemoLogic.x_for_lean(0.0)).is_equal(960.0)
	assert_float(DemoLogic.x_for_lean(-1.0)).is_equal(DemoLogic.EDGE)
	assert_float(DemoLogic.x_for_lean(1.0)).is_equal(1920.0 - DemoLogic.EDGE)
	assert_float(DemoLogic.x_for_lean(3.0)).is_equal(1920.0 - DemoLogic.EDGE)
	# The gain puts the edge short of full lock.
	assert_float(DemoLogic.x_for_lean(-1.0 / DemoLogic.STEERING_GAIN)).is_equal_approx(DemoLogic.EDGE, 0.01)
	assert_float(DemoLogic.x_for_lean(0.5)).is_equal_approx(960.0 + 0.5 * DemoLogic.STEERING_GAIN * (960.0 - DemoLogic.EDGE), 0.01)


func test_hits_follow_the_triangle_not_a_box() -> void:
	var tip := Vector2(960, DemoLogic.PLAYER_Y - 50)
	# Beside the tip, clear of the triangle but inside the old base-wide box (95 px): a miss.
	assert_bool(DemoLogic.touches_player(tip + Vector2(80, 0), 960)).is_false()
	assert_bool(DemoLogic.touches_player(tip + Vector2(35, 0), 960)).is_true()
	# Touching a base corner: a hit.
	assert_bool(DemoLogic.touches_player(Vector2(960 + 55 + 35, DemoLogic.PLAYER_Y + 40), 960)).is_true()
	assert_bool(DemoLogic.touches_player(Vector2(960 + 55 + 45, DemoLogic.PLAYER_Y + 40), 960)).is_false()


func test_cadence_speeds_the_balls() -> void:
	assert_float(DemoLogic.fall_speed(90.0)).is_greater(DemoLogic.fall_speed(60.0))
	assert_float(DemoLogic.fall_speed(-5.0)).is_equal(DemoLogic.BASE_SPEED)


func test_spawns_follow_the_difficulty() -> void:
	var easy := _count(_run(DemoLogic.new(1, "easy"), 12.0, 0.0, 80.0), "spawn")
	var hard := _count(_run(DemoLogic.new(1, "hard"), 12.0, 0.0, 80.0), "spawn")
	assert_int(easy).is_equal(10)  # every 1.2 s, the first after 0.5 s
	assert_int(hard).is_greater(easy)


func test_every_ball_is_either_dodged_or_hits() -> void:
	var logic := DemoLogic.new(7, "standard")
	var events := _run(logic, 30.0, 0.0, 80.0)
	assert_int(_count(events, "dodge") + _count(events, "hit") + logic.balls.size()).is_equal(_count(events, "spawn"))
	assert_int(logic.hits).is_greater(0)  # aimed balls hit a rider who never moves
	assert_int(logic.dodged).is_greater(0)


func test_a_ball_straight_down_the_middle_hits_a_centred_rider() -> void:
	var logic := DemoLogic.new(1)
	logic.balls = [Vector2(960, DemoLogic.PLAYER_Y - 5)]
	var events := logic.step(DT, 0.0, 80.0)
	assert_int(_count(events, "hit")).is_equal(1)
	assert_int(logic.streak).is_equal(0)
	assert_array(logic.balls).is_empty()


func test_leaning_away_dodges_it_and_scores() -> void:
	var logic := DemoLogic.new(1)
	logic.balls = [Vector2(960, DemoLogic.PLAYER_Y - 5)]
	var events: Array[Dictionary] = []
	for i in 60:
		events.append_array(logic.step(DT, 1.0, 80.0).filter(func(e): return e.type != "spawn"))
		logic.balls = logic.balls.filter(func(b): return absf(b.x - 960) < 1)  # ignore new spawns
	assert_int(_count(events, "hit")).is_equal(0)
	assert_int(_count(events, "dodge")).is_equal(1)
	assert_float(events[0].points).is_equal(DemoLogic.DODGE_POINTS)


func test_streak_bonus_grows_and_caps() -> void:
	var logic := DemoLogic.new(1)
	var points := []
	for i in 10:
		logic.balls = [Vector2(100, DemoLogic.FIELD.y + DemoLogic.BALL_RADIUS - 0.1)]
		for e in logic.step(0.001, 1.0, 80.0):
			if e.type == "dodge":
				points.append(e.points)
	assert_array(points).is_equal([10.0, 11.0, 12.0, 13.0, 14.0, 15.0, 15.0, 15.0, 15.0, 15.0])
	assert_int(logic.best_streak).is_equal(10)


func test_dodges_below_the_cadence_floor_score_nothing() -> void:
	var logic := DemoLogic.new(1, "standard")
	logic.balls = [Vector2(100, DemoLogic.FIELD.y + DemoLogic.BALL_RADIUS - 0.1)]
	var events := logic.step(0.01, 1.0, logic.cadence_floor - 1.0)
	assert_float(events.filter(func(e): return e.type == "dodge")[0].points).is_equal(0.0)
	assert_int(logic.streak).is_equal(0)


func test_params_override_the_cadence_floor() -> void:
	assert_float(DemoLogic.new(1, "hard", 82.0).cadence_floor).is_equal(82.0)
	assert_float(DemoLogic.new(1, "hard").cadence_floor).is_equal(70.0)


func test_same_seed_same_game() -> void:
	var a := DemoLogic.new(42)
	var b := DemoLogic.new(42)
	_run(a, 20.0, 0.3, 85.0)
	_run(b, 20.0, 0.3, 85.0)
	assert_array(a.balls).is_equal(b.balls)
	assert_int(a.hits).is_equal(b.hits)


func test_perfect_play_at_1x_misses_three_stars() -> void:
	# The best a rider can do without the effort multiplier: every dodge at the full bonus.
	var info := GameRegistry.info("demo")
	for difficulty in ["easy", "standard", "hard"]:
		var per_minute: float = 60.0 / DemoLogic.LEVELS[difficulty].spawn_sec * (DemoLogic.DODGE_POINTS + DemoLogic.STREAK_BONUS_MAX)
		assert_int(Stars.count(per_minute, info.star_thresholds[difficulty])).is_equal(2)
		assert_int(Stars.count(per_minute * 1.3 * 0.85, info.star_thresholds[difficulty])).is_equal(3)
