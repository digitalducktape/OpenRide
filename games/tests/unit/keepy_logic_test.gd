extends GdUnitTestSuite
## Keepy Uppy's rules (#77), driven by scripted power at 60 Hz (games/keepy_uppy/DESIGN.md).

const DT := 1.0 / 60.0
const FTP := 200.0
const PARAMS := {"ftp_watts": 200.0, "weight_watts": 16.0, "height_watts": 150.0, "rain_watts": 8.0,
	"bird_watts": 4.0, "downdraft_watts": 16.0}


## Steps `seconds` at `power` (a float, or a Callable(logic) -> float); returns every event.
func _ride(logic: KeepyLogic, seconds: float, power, lean := 0.0, tracking := true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		var p: float = power.call(logic) if power is Callable else float(power)
		events.append_array(logic.step(DT, p, lean, tracking))
	return events


func _types(events: Array[Dictionary]) -> Array:
	return events.map(func(e): return e.type)


## A logic with the weather and the gusts out of the way, to test the column alone.
func _calm(steer := false, difficulty := "standard") -> KeepyLogic:
	var logic := KeepyLogic.new(1, PARAMS if difficulty == "standard" else {"ftp_watts": FTP}, difficulty, steer)
	logic._next_force = 1.0e9
	logic._next_gust = 1.0e9
	logic._next_wind = 1.0e9
	return logic


func _thresholds() -> Dictionary:
	var game: Game = load("res://games/keepy_uppy/KeepyUppy.tscn").instantiate()
	var info := game.info()
	game.free()
	return info.star_thresholds


# --- Lift against weight ---

func test_a_comfortable_third_of_ftp_holds_the_mid_band() -> void:
	var logic := _calm()
	_ride(logic, 20.0, 0.33 * FTP)
	assert_int(logic.band).is_equal(KeepyLogic.Band.MID)
	# The mid band starts at about 27% of FTP and the high band at about 57% (2026-11 retune).
	assert_float(KeepyLogic.power_for(KeepyLogic.MID_FROM, 16.0, 150.0) / FTP).is_between(0.25, 0.29)
	assert_float(KeepyLogic.power_for(KeepyLogic.HIGH_FROM, 16.0, 150.0) / FTP).is_between(0.55, 0.60)


func test_high_band_takes_more_work_and_light_pedalling_floats_it_low() -> void:
	var logic := _calm()
	_ride(logic, 20.0, 0.62 * FTP)
	assert_int(logic.band).is_equal(KeepyLogic.Band.HIGH)
	var low := _calm()
	_ride(low, 30.0, 0.15 * FTP)
	assert_int(low.band).is_equal(KeepyLogic.Band.LOW)
	assert_int(low.balloon).is_equal(KeepyLogic.Balloon.FLYING)
	assert_float(low.h).is_greater(0.05)
	assert_int(low.pops).is_equal(0)


func test_above_its_need_it_climbs_and_below_it_sinks() -> void:
	var logic := _calm()
	_ride(logic, 4.0, 0.33 * FTP)
	var h0 := logic.h
	_ride(logic, 1.0, 0.6 * FTP)
	assert_float(logic.h).is_greater(h0)
	_ride(logic, 4.0, 0.1 * FTP)
	assert_float(logic.h).is_less(h0)


func test_difficulty_sets_the_weight_and_the_height_watts() -> void:
	for d in [["easy", 12.0, 130.0], ["standard", 16.0, 150.0], ["hard", 20.0, 170.0]]:
		var logic := KeepyLogic.new(1, {"ftp_watts": 200.0}, d[0])
		assert_float(logic.base_weight).is_equal_approx(d[1], 0.01)
		assert_float(logic.height_watts).is_equal_approx(d[2], 0.01)


func test_power_is_smoothed_over_about_two_seconds() -> void:
	var logic := _calm()
	_ride(logic, 5.0, 100.0)
	_ride(logic, 2.0, 200.0)
	assert_float(logic.smoothed).is_between(180.0, 192.0)


func test_a_stopped_balloon_floats_down_slowly_and_warns_well_before_the_pop() -> void:
	var logic := _calm()
	_ride(logic, 10.0, 0.33 * FTP)  # rests at about 0.33
	var t := 0.0
	var warned_at := -1.0
	while logic.balloon == KeepyLogic.Balloon.FLYING and t < 30.0:
		for e in logic.step(DT, 0.0):
			if e.type == "sinking":
				warned_at = t
		t += DT
	# The sink rate is capped at 0.06 a second, so 0.33 takes over 5 s.
	assert_float(t).is_greater(5.0)
	assert_float(warned_at).is_greater(0.0)
	assert_float(t - warned_at).is_greater(2.0)
	assert_int(logic.balloon).is_equal(KeepyLogic.Balloon.POPPED)


## The 2026-11 retune's core goal: a rider at 30% of FTP keeps the balloon up all round, in the
## mid band most of the time, with the weather on.
func test_a_rider_at_thirty_percent_of_ftp_holds_the_mid_band_through_the_weather() -> void:
	var logic := KeepyLogic.new(3, {"ftp_watts": FTP}, "standard")
	var mid := 0.0
	for i in roundi(120.0 / DT):
		logic.step(DT, 0.30 * FTP + 6.0 * (1.0 if logic.raining else 0.0))
		if logic.band >= KeepyLogic.Band.MID:
			mid += DT
	assert_int(logic.pops).is_equal(0)
	assert_float(mid / 120.0).is_greater(0.6)


func test_the_first_balloon_holds_while_the_rider_gets_going() -> void:
	var logic := _calm()
	_ride(logic, 2.5, 0.0)
	assert_float(logic.h).is_equal_approx(KeepyLogic.START_HEIGHT, 0.001)


# --- Bands and points ---

func test_bands_score_one_two_and_three_times() -> void:
	assert_int(KeepyLogic.band_of(0.2)).is_equal(KeepyLogic.Band.LOW)
	assert_int(KeepyLogic.band_of(0.5)).is_equal(KeepyLogic.Band.MID)
	assert_int(KeepyLogic.band_of(0.8)).is_equal(KeepyLogic.Band.HIGH)
	for target in [[0.2, 10.0], [0.4, 20.0], [0.65, 30.0]]:
		var logic := _calm()
		_ride(logic, 20.0, target[0] * FTP)
		var points := 0.0
		for i in 60:
			logic.step(DT, target[0] * FTP)
			points += logic.last_points
		assert_float(points).is_equal_approx(target[1], 0.01)


func test_no_points_without_the_power_to_leave_the_grille() -> void:
	var logic := _calm()
	# Stopped, the first balloon held by its grace: nothing.
	for i in roundi(4.0 / DT):
		logic.step(DT, 0.0, 0.0, true)
		assert_float(logic.last_points).is_equal(0.0)
	# Pedalling under the weight, the balloon sinking: nothing.
	logic = _calm()
	logic.h = 0.5
	for i in roundi(2.0 / DT):
		logic.step(DT, 10.0, 0.0, true)
		assert_float(logic.last_points).is_equal(0.0)
	# At the weight and above: it scores.
	_ride(logic, 8.0, 100.0)
	logic.step(DT, 100.0, 0.0, true)
	assert_float(logic.last_points).is_greater(0.0)
	# Stopping scores nothing from that frame on, though the balloon is still high.
	logic.h = 0.9
	for i in roundi(2.0 / DT):
		logic.step(DT, 0.0, 0.0, true)
		assert_float(logic.last_points).is_equal(0.0)
	assert_float(logic.h).is_greater(0.0)


func test_band_changes_are_events() -> void:
	var logic := _calm()
	var events := _ride(logic, 15.0, 0.8 * FTP)
	var bands := events.filter(func(e): return e.type == "band")
	assert_int(bands[-1].band).is_equal(KeepyLogic.Band.HIGH)


# --- Pushing forces: each warned at least 2 s ahead ---

func test_every_force_is_warned_at_least_two_seconds_ahead() -> void:
	var logic := KeepyLogic.new(5, PARAMS)
	logic._next_gust = 1.0e9
	var t := 0.0
	var warned := {}
	var seen := {}
	for i in roundi(600.0 / DT):
		t += DT
		for e in logic.step(DT, 0.67 * FTP):
			if e.type == "telegraph":
				warned[e.force] = t
				assert_float(e.warning).is_greater_equal(2.0)
			elif e.type == "force_start":
				assert_bool(warned.has(e.force)).is_true()
				assert_float(t - warned[e.force]).is_greater_equal(2.0 - DT)
				seen[e.force] = true
	assert_array(seen.keys()).contains_exactly_in_any_order(["rain", "bird", "downdraft"])


## Starts `name` now (its warning already over).
func _force(logic: KeepyLogic, name: String) -> Array[Dictionary]:
	logic.force = name
	logic.weather = KeepyLogic.Weather.TELEGRAPH
	logic.force_left = 0.0
	var events := logic.step(DT, logic.smoothed)
	logic._next_force = 1.0e9  # and no other force after it
	return events


func test_rain_makes_the_balloon_a_little_heavier() -> void:
	var logic := _calm()
	_ride(logic, 10.0, 0.54 * FTP)
	var dry := logic.h
	assert_array(_types(_force(logic, "rain"))).contains(["force_start"])
	assert_bool(logic.raining).is_true()
	assert_float(logic.weight()).is_equal_approx(24.0, 0.01)
	_ride(logic, 6.0, 0.54 * FTP)
	assert_float(logic.h).is_between(dry - 0.08, dry - 0.03)
	# It lasts 8-12 s, then the weight is back.
	_ride(logic, 7.0, 0.54 * FTP)
	assert_bool(logic.raining).is_false()
	assert_float(logic.weight()).is_equal_approx(16.0, 0.01)


func test_birds_land_one_at_a_time_and_add_two_percent_each() -> void:
	var logic := _calm()
	_ride(logic, 5.0, 0.42 * FTP)
	for n in [1, 2, 3]:
		var events := _force(logic, "bird")
		assert_array(_types(events)).contains(["bird_land"])
		assert_int(logic.birds).is_equal(n)
	assert_float(logic.weight()).is_equal_approx(16.0 + 3 * 4.0, 0.01)
	# With three perched, the weather never picks another bird.
	for i in 50:
		assert_str(logic._pick_force()).is_not_equal("bird")


func test_three_seconds_in_the_high_band_shakes_the_birds_off() -> void:
	var logic := _calm()
	_ride(logic, 5.0, 0.42 * FTP)
	_force(logic, "bird")
	_force(logic, "bird")
	# Mid: they stay.
	_ride(logic, 10.0, 0.54 * FTP)
	assert_int(logic.birds).is_equal(2)
	var events := _ride(logic, 15.0, 0.9 * FTP)
	var shaken := events.filter(func(e): return e.type == "birds_shaken")
	assert_int(shaken.size()).is_equal(1)
	assert_int(shaken[0].count).is_equal(2)
	assert_int(logic.birds).is_equal(0)
	assert_int(logic.birds_shaken).is_equal(2)


func test_birds_fly_off_by_themselves_after_a_while_unscored() -> void:
	var logic := _calm()
	_ride(logic, 5.0, 0.42 * FTP)
	_force(logic, "bird")
	_ride(logic, KeepyLogic.BIRD_STAY - 1.0, 0.54 * FTP)
	assert_int(logic.birds).is_equal(1)
	var events := _ride(logic, 2.0, 0.54 * FTP)
	assert_array(_types(events)).contains(["birds_leave"])
	assert_int(logic.birds).is_equal(0)
	assert_int(logic.birds_shaken).is_equal(0)


func test_shaking_needs_three_seconds_in_a_row() -> void:
	var logic := _calm()
	_ride(logic, 15.0, 0.67 * FTP)
	_force(logic, "bird")
	_ride(logic, 2.0, 0.67 * FTP)
	assert_float(logic.shake_progress).is_greater(0.5)
	logic.h = 0.5  # knocked out of the band
	logic.step(DT, 0.67 * FTP)
	assert_float(logic.shake_progress).is_equal(0.0)
	assert_int(logic.birds).is_equal(1)


func test_an_unanswered_downdraft_drops_the_balloon_a_little_but_not_to_the_ground() -> void:
	var logic := _calm()
	_ride(logic, 20.0, 0.44 * FTP)
	var before := logic.h
	_force(logic, "downdraft")
	var events := _ride(logic, 2.0, 0.44 * FTP)
	assert_int(logic.balloon).is_equal(KeepyLogic.Balloon.FLYING)
	# It sinks toward where the extra weight balances: about 8% of FTP over 75% a full height.
	assert_float(logic.h).is_between(before - 0.12, before - 0.03)
	assert_array(_types(events)).contains(["force_end"])


func test_a_downdraft_over_a_balloon_skimming_the_grille_pops_it() -> void:
	var logic := _calm()
	_ride(logic, 20.0, 0.12 * FTP)
	assert_float(logic.h).is_less(0.1)
	_force(logic, "downdraft")
	var events := _ride(logic, 2.0, 0.12 * FTP)
	assert_array(_types(events)).contains(["pop"])


func test_a_burst_answers_the_downdraft() -> void:
	var logic := _calm()
	_ride(logic, 20.0, 0.9 * FTP)  # high, as a rider who spun up in the warning
	_force(logic, "downdraft")
	var events := _ride(logic, 2.0, 1.0 * FTP)
	var ended := events.filter(func(e): return e.type == "force_end")
	assert_bool(ended[0].beaten).is_true()
	assert_int(logic.downdrafts_beaten).is_equal(1)


func test_gusts_in_the_high_band_are_warned_two_seconds_ahead_and_small() -> void:
	var logic := _calm()
	_ride(logic, 15.0, 0.67 * FTP)
	logic._next_gust = 0.5
	var t := 0.0
	var warned := -1.0
	var hit := -1.0
	var lowest := 1.0
	for i in roundi(5.0 / DT):
		t += DT
		for e in logic.step(DT, 0.67 * FTP):
			if e.type == "gust_warn":
				warned = t
			elif e.type == "gust":
				hit = t
		lowest = minf(lowest, logic.h)
	assert_float(warned).is_greater(0.0)
	assert_float(hit - warned).is_greater_equal(2.0 - DT)
	assert_float(lowest).is_greater(0.5)


func test_leaving_the_high_band_calls_the_gust_off() -> void:
	var logic := _calm()
	_ride(logic, 15.0, 0.67 * FTP)
	logic._next_gust = 0.0
	logic.step(DT, 0.67 * FTP)
	assert_str(logic.gust).is_equal("warn")
	logic.h = 0.5
	logic.step(DT, 0.42 * FTP)
	logic.step(DT, 0.42 * FTP)
	assert_str(logic.gust).is_equal("")


# --- The ground: pop and a new balloon ---

func test_touching_the_ground_pops_and_a_new_balloon_arrives_in_three_seconds() -> void:
	var logic := _calm()
	_ride(logic, 5.0, 0.42 * FTP)
	_force(logic, "bird")
	logic.h = 0.001
	logic._grace = 0.0
	logic.smoothed = 0.0
	var events := logic.step(DT, 0.0)
	assert_array(_types(events)).contains(["pop", "birds_scatter"])
	var pop: Dictionary = events.filter(func(e): return e.type == "pop")[0]
	assert_float(pop.points).is_equal(50.0)
	assert_int(logic.pops).is_equal(1)
	assert_int(logic.birds).is_equal(0)
	# Nothing scores while the new balloon is on its way.
	var t := 0.0
	var points := 0.0
	var dispatched := -1.0
	while logic.balloon != KeepyLogic.Balloon.FLYING and t < 10.0:
		t += DT
		for e in logic.step(DT, 0.42 * FTP):
			if e.type == "dispatch":
				dispatched = t
		points += logic.last_points
	assert_float(points).is_equal(0.0)
	assert_float(dispatched).is_greater(0.0)
	assert_float(t).is_equal_approx(3.0, 0.05)
	assert_float(logic.h).is_equal_approx(KeepyLogic.START_HEIGHT, 0.001)
	# And the game goes on.
	_ride(logic, 2.0, 0.42 * FTP)
	assert_float(logic.last_points).is_greater(0.0)


func test_the_weather_waits_after_a_new_balloon() -> void:
	var logic := KeepyLogic.new(2, PARAMS)
	logic._next_force = 0.5
	logic.h = 0.001
	logic._grace = 0.0
	logic._primed = true
	logic.step(DT, 0.0)
	assert_int(logic.balloon).is_equal(KeepyLogic.Balloon.POPPED)
	_ride(logic, 3.1, 0.42 * FTP)
	assert_int(logic.weather).is_equal(KeepyLogic.Weather.CALM)
	assert_float(logic._next_force).is_greater(KeepyLogic.CALM_AFTER_ARRIVE - 0.2)


func test_sensor_loss_freezes_everything() -> void:
	var logic := _calm()
	_ride(logic, 5.0, 0.42 * FTP)
	var h := logic.h
	for i in 600:
		logic.step(DT, 0.0, 0.0, false, true)
		assert_float(logic.last_points).is_equal(0.0)
	assert_float(logic.h).is_equal(h)


# --- Steer ---

func test_steer_off_never_loses_lift() -> void:
	var logic := KeepyLogic.new(3, PARAMS, "standard", false)
	_ride(logic, 30.0, 0.42 * FTP, 1.0)
	assert_float(logic.efficiency).is_equal(1.0)
	assert_float(logic.fan_x).is_equal(0.0)


func test_lean_has_a_dead_zone_and_a_soft_curve() -> void:
	assert_float(KeepyLogic.lean_to_fan(0.1)).is_equal(0.0)
	assert_float(KeepyLogic.lean_to_fan(-0.1)).is_equal(0.0)
	# A small sway past the dead zone moves the fan centimetres, not tens of them.
	assert_float(absf(KeepyLogic.lean_to_fan(0.25))).is_less(0.15)
	assert_float(KeepyLogic.lean_to_fan(1.0)).is_equal_approx(KeepyLogic.FAN_RANGE, 0.001)
	assert_float(KeepyLogic.lean_to_fan(-1.0)).is_equal_approx(-KeepyLogic.FAN_RANGE, 0.001)


func test_sitting_straight_brings_the_fan_home() -> void:
	var logic := _calm(true)
	_ride(logic, 3.0, 0.42 * FTP, 1.0)
	assert_float(logic.fan_x).is_greater(1.0)
	_ride(logic, 3.0, 0.42 * FTP, 0.0)
	assert_float(absf(logic.fan_x)).is_less(0.02)


func test_the_fan_is_smoothed_and_rate_limited() -> void:
	var logic := _calm(true)
	var last := 0.0
	for i in 120:
		logic.step(DT, 0.42 * FTP, 1.0 if i % 2 == 0 else -1.0, true)  # jitter flipping every frame
		assert_float(absf(logic.fan_x - last)).is_less_equal(KeepyLogic.FAN_SPEED * DT + 0.0001)
		last = logic.fan_x
	assert_float(absf(logic.fan_x)).is_less(0.15)


func test_lift_loss_grows_with_the_offset_past_a_free_zone() -> void:
	assert_float(KeepyLogic.steer_efficiency(0.2)).is_equal(1.0)
	assert_float(KeepyLogic.steer_efficiency(-0.25)).is_equal(1.0)
	assert_float(KeepyLogic.steer_efficiency(0.725)).is_equal_approx(0.75, 0.001)
	assert_float(KeepyLogic.steer_efficiency(2.0)).is_equal_approx(0.5, 0.001)


func _windy() -> KeepyLogic:
	var logic := _calm(true)
	logic.wind = KeepyLogic.WIND_MAX
	logic.wind_target = KeepyLogic.WIND_MAX
	logic.wind_gain = 1.0
	return logic


func test_wind_pushes_the_balloon_off_and_leaning_into_it_wins_the_lift_back() -> void:
	var drifting := _windy()
	_ride(drifting, 20.0, 0.54 * FTP, 0.0)
	assert_float(drifting.x).is_greater(0.55)
	assert_float(drifting.efficiency).is_less(0.85)
	var leaning := _windy()
	_ride(leaning, 20.0, 0.54 * FTP, 0.75)
	assert_float(leaning.efficiency).is_equal(1.0)
	assert_float(leaning.h).is_greater(drifting.h + 0.1)


func test_leaning_the_wrong_way_can_drop_the_balloon() -> void:
	var logic := _windy()
	var events := _ride(logic, 30.0, 0.15 * FTP, -1.0)
	assert_array(_types(events)).contains(["pop"])


func test_without_a_face_the_wind_dies_and_the_fan_centres() -> void:
	var logic := _windy()
	_ride(logic, 2.0, 0.42 * FTP, 1.0, true)
	_ride(logic, 10.0, 0.42 * FTP, 1.0, false)
	assert_float(logic.wind_gain).is_equal(0.0)
	assert_float(absf(logic.fan_x)).is_less(0.02)
	assert_float(logic.efficiency).is_equal(1.0)


func test_the_wind_changes_every_six_to_ten_seconds() -> void:
	var logic := KeepyLogic.new(9, PARAMS, "standard", true)
	logic._next_force = 1.0e9
	var events := _ride(logic, 60.0, 0.42 * FTP)
	var winds := events.filter(func(e): return e.type == "wind")
	assert_int(winds.size()).is_between(6, 11)
	for w in winds:
		assert_float(absf(w.target)).is_less_equal(KeepyLogic.WIND_MAX)


# --- Determinism, stats and stars ---

func test_the_same_seed_brings_the_same_weather() -> void:
	var a := KeepyLogic.new(42, PARAMS)
	var b := KeepyLogic.new(42, PARAMS)
	var ea := _types(_ride(a, 120.0, 0.6 * FTP))
	var eb := _types(_ride(b, 120.0, 0.6 * FTP))
	assert_array(ea).is_equal(eb)
	assert_bool(ea.has("telegraph")).is_true()


func test_stats_count_high_time_and_power() -> void:
	var logic := _calm()
	_ride(logic, 20.0, 0.9 * FTP)
	assert_float(logic.seconds_high).is_greater(10.0)
	assert_float(logic.avg_power()).is_equal_approx(180.0, 0.5)
	assert_float(logic.best_air).is_equal_approx(20.0, 0.1)


## Points a minute over a 5-minute ride with the weather on, at a power the rider chooses.
func _points_a_minute(power: Callable, seed_value := 11) -> float:
	var logic := KeepyLogic.new(seed_value, PARAMS)
	var points := 0.0
	var minutes := 5.0
	for i in roundi(minutes * 60.0 / DT):
		for e in logic.step(DT, power.call(logic)):
			if e.type == "pop":
				points = maxf(points - e.points, 0.0)
		points += logic.last_points
	return points / minutes


func test_a_rider_who_never_lifts_it_scores_nothing() -> void:
	assert_float(_points_a_minute(func(_l): return 0.0)).is_equal(0.0)
	assert_float(_points_a_minute(func(_l): return 0.05 * FTP)).is_equal(0.0)


func test_steady_mid_earns_two_stars() -> void:
	var stars: Array = _thresholds().standard
	# A comfortable rider: about 40% of FTP, adding the rain's and birds' weight when they come.
	var ppm := _points_a_minute(func(l: KeepyLogic): return 0.40 * FTP + (l.weight() - 16.0) * 1.25)
	assert_float(ppm).is_between(float(stars[1]), float(stars[2]) - 1.0)


func test_a_perfect_run_at_one_times_stays_short_of_three_stars() -> void:
	var stars: Array = _thresholds().standard
	# Always as high as the column goes: the best a rider can do at 1.0×.
	var ppm := _points_a_minute(func(_l): return 2.0 * FTP)
	assert_float(ppm).is_less(float(stars[2]))
	assert_float(ppm).is_greater(float(stars[1]))


func test_three_stars_needs_about_one_point_three_times_effort() -> void:
	var stars: Array = _thresholds().standard
	# A strong rider riding high (about 65% of FTP) and answering the weather.
	var ppm := _points_a_minute(func(l: KeepyLogic): return 0.65 * FTP + (l.weight() - 16.0) * 1.5)
	assert_float(ppm).is_less(float(stars[2]))
	assert_float(ppm * 1.3).is_greater_equal(float(stars[2]))


func test_the_intro_s_rounded_watts_rest_in_the_mid_band() -> void:
	# The target line rounds to 5 W: at that figure, the balloon still settles in the mid band.
	for ftp in [100.0, 140.0, 200.0, 300.0]:
		var w: float = 0.08 * ftp
		var span: float = 0.75 * ftp
		var said := roundf(KeepyLogic.power_for(KeepyLogic.TARGET_HEIGHT, w, span) / 5.0) * 5.0
		var h := KeepyLogic.resting_height(said, w, span)
		assert_float(h).override_failure_message("%d W against %d W rests at %.2f" % [said, w, h]) \
			.is_between(KeepyLogic.MID_FROM, KeepyLogic.HIGH_FROM)
