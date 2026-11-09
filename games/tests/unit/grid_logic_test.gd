extends GdUnitTestSuite
## Power Grid's rules (#81): the demand curve per role, meeting demand with headroom, brown-out and
## relight, storms, the stars. A rider here is a number, or a function of the logic: the watts now.

const DT := 0.1
const FTP := 200.0
const GridGame := preload("res://games/power_grid/PowerGrid.gd")


func _logic(role := "work", duration := 300.0, difficulty := "standard", seed_value := 7) -> GridLogic:
	return GridLogic.new(seed_value, {"ftp_watts": FTP}, role, duration, difficulty)


## Rides `seconds` at `watts` (a Callable taking the logic, or a number). Returns the events.
func _ride(l: GridLogic, seconds: float, watts: Variant, rpm := 85.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		var w: float = watts.call(l) if watts is Callable else float(watts)
		out.append_array(l.step(DT, w, rpm))
	return out


func _count(events: Array[Dictionary], type: String) -> int:
	return events.filter(func(e): return e.type == type).size()


func _first(events: Array[Dictionary], type: String) -> Dictionary:
	for e in events:
		if e.type == type:
			return e
	return {}


## A rider who always just meets demand and repairs every line.
func _steady(l: GridLogic) -> float:
	var over := l.repair_need if l.storm != GridLogic.Storm.CALM else 0.0
	return maxf(l.need_ahead(3.0), over) * 1.04


## Points a minute for a rider `watts`, with `effort` as the multiplier (work only).
func _per_minute(l: GridLogic, seconds: float, watts: Variant, effort := 1.0) -> float:
	var points := 0.0
	for i in roundi(seconds / DT):
		var w: float = watts.call(l) if watts is Callable else float(watts)
		for e in l.step(DT, w, 85.0):
			if e.type == "restored":
				points += float(e.bonus) * effort
		points += l.earned * effort
	return points / seconds * 60.0


# --- The curve ---

func test_work_demand_runs_from_15_to_33_percent_of_ftp() -> void:
	var l := _logic("work", 300.0)
	assert_float(l.demand_at(0.0)).is_equal_approx(30.0, 0.01)
	assert_float(l.demand_at(0.72 * 300.0)).is_equal_approx(66.0, 0.01)
	assert_float(l.demand_at(300.0)).is_equal_approx(66.0, 0.01)


func test_a_warm_up_rises_gently_within_12_to_27_percent() -> void:
	var l := _logic("warmup", 180.0)
	assert_float(l.demand_at(0.0)).is_equal_approx(24.0, 0.01)
	assert_float(l.demand_at(180.0)).is_equal_approx(54.0, 0.01)
	var last := 0.0
	for i in 19:
		var d := l.demand_at(i * 10.0)
		assert_bool(d >= last).is_true()
		last = d


func test_a_cool_down_is_the_town_going_to_bed() -> void:
	var l := _logic("cooldown", 180.0)
	assert_float(l.demand_at(0.0)).is_equal_approx(54.0, 0.01)
	assert_float(l.demand_at(180.0)).is_equal_approx(24.0, 0.01)
	assert_int(l.online).is_equal(4)
	assert_int(l.powered).is_equal(4)


func test_a_recovery_stays_low_and_ends_where_it_began() -> void:
	var l := _logic("recovery", 90.0)
	assert_float(l.demand_at(0.0)).is_equal_approx(24.0, 0.01)
	assert_float(l.demand_at(45.0)).is_equal_approx(44.0, 0.01)
	assert_float(l.demand_at(90.0)).is_equal_approx(24.0, 0.01)


func test_every_easy_role_stays_under_its_power_cap() -> void:
	for role in ["warmup", "cooldown", "recovery"]:
		var l := GridLogic.new(1, {"ftp_watts": FTP, "demand_lo_watts": 60, "demand_hi_watts": 500}, role, 180.0)
		for i in 19:
			assert_float(l.demand_at(i * 10.0)).is_less_equal(l.cap)
		assert_float(l.cap).is_equal_approx(FTP * float(GridLogic.CAP_SHARES[role]), 0.01)


func test_difficulty_moves_work_but_never_an_easy_role() -> void:
	assert_float(_logic("work", 300.0, "hard").hi).is_greater(_logic("work", 300.0, "easy").hi)
	assert_float(_logic("recovery", 90.0, "hard").hi).is_equal(_logic("recovery", 90.0, "easy").hi)


func test_params_override_the_defaults() -> void:
	var l := GridLogic.new(1, {"ftp_watts": 300, "demand_lo_watts": 111, "demand_hi_watts": 222, "storm_watts": 33}, "work", 300.0)
	assert_float(l.lo).is_equal(111.0)
	assert_float(l.hi).is_equal(222.0)
	assert_float(l.storm_watts).is_equal(33.0)


func test_a_long_ride_is_several_evenings_each_winding_down() -> void:
	var l := _logic("work", 1200.0)
	assert_int(l.evenings).is_equal(4)
	assert_float(l.evening_sec).is_equal(300.0)
	assert_float(l.demand_at(299.9)).is_less(l.lo + 2.0)
	var events := _ride(l, 310.0, _steady)
	assert_int(_first(events, "evening").number).is_equal(2)
	assert_int(l.evening).is_equal(2)


func test_the_last_evening_holds_its_peak_to_the_end() -> void:
	var l := _logic("work", 600.0)
	l.evening = 2
	assert_float(l.demand_at(299.0)).is_equal_approx(l.hi, 0.01)


func test_an_open_ride_keeps_having_evenings() -> void:
	var l := _logic("work", -1.0)
	assert_int(l.evenings).is_equal(0)
	var events := _ride(l, 620.0, _steady)
	assert_int(_count(events, "evening")).is_equal(2)


func test_a_one_minute_slot_still_reaches_the_stadium() -> void:
	var l := _logic("work", 60.0)
	_ride(l, 60.0, _steady)
	assert_int(l.online).is_equal(4)


# --- Meeting demand ---

func test_demand_is_met_at_90_percent_of_it() -> void:
	var l := _logic("work", 300.0)
	l.step(DT, 27.5, 85.0)
	assert_bool(l.meeting).is_true()
	var m := _logic("work", 300.0)
	m.step(DT, 26.0, 85.0)
	assert_bool(m.meeting).is_false()


func test_supply_is_about_a_five_second_average() -> void:
	var l := _logic("work", 300.0)
	l.step(DT, 100.0, 85.0)
	assert_float(l.supply).is_equal(100.0)
	_ride(l, 5.0, 200.0)
	assert_float(l.supply).is_between(180.0, 192.0)


func test_a_rider_who_stops_pedalling_scores_nothing_at_once() -> void:
	var l := _logic("work", 300.0)
	_ride(l, 10.0, 200.0)
	assert_float(l.earned).is_greater(0.0)
	l.step(DT, 0.0, 0.0)
	assert_float(l.supply).is_greater(l.need())  # the average still reads high
	assert_bool(l.meeting).is_false()
	assert_float(l.earned).is_equal(0.0)


func test_no_score_without_pedalling_from_the_start() -> void:
	var l := _logic("work", 300.0)
	for i in 600:
		l.step(DT, 0.0, 0.0)
		assert_float(l.earned).is_equal(0.0)
	var m := _logic("work", 300.0)
	for i in 600:
		m.step(DT, 300.0, 10.0)  # a stale power reading with the pedals stopped
		assert_float(m.earned).is_equal(0.0)


func test_points_a_second_are_per_district_lit() -> void:
	var l := _logic("work", 300.0)
	l.step(DT, 200.0, 85.0)
	assert_float(l.earned).is_equal_approx(GridLogic.POINTS_PER_DISTRICT * DT, 0.0001)
	l.t = 0.45 * 300.0
	l.online = 3
	l.powered = 3
	l.step(DT, 200.0, 85.0)
	assert_float(l.earned).is_equal_approx(GridLogic.POINTS_PER_DISTRICT * 3.0 * DT, 0.0001)


func test_sensor_loss_holds_the_town() -> void:
	var l := _logic("work", 300.0)
	_ride(l, 10.0, 200.0)
	var t := l.t
	for i in 100:
		assert_array(l.step(DT, 0.0, 0.0, false)).is_empty()
	assert_float(l.t).is_equal(t)
	assert_float(l.earned).is_equal(0.0)
	assert_int(l.powered).is_equal(1)


# --- Districts ---

func test_districts_come_online_in_order_and_each_is_announced_ahead() -> void:
	var l := _logic("work", 300.0)
	l.storms_on = false
	var on_at := {}
	var soon_at := {}
	for i in 3000:
		for e in l.step(DT, _steady(l), 85.0):
			if e.type == "district_on" and not on_at.has(e.index):
				on_at[e.index] = l.elapsed
			if e.type == "district_soon":
				soon_at[e.index] = l.elapsed
				assert_float(float(e.need)).is_between(GridLogic.HEADROOM * l.lo, GridLogic.HEADROOM * l.hi)
	for index in [1, 2, 3]:
		assert_bool(on_at.has(index)).is_true()
		assert_float(on_at[index] - soon_at[index]).is_greater_equal(2.0)
	assert_bool(on_at[1] < on_at[2] and on_at[2] < on_at[3]).is_true()


func test_a_one_minute_slot_still_warns_two_seconds_ahead() -> void:
	var l := _logic("work", 60.0)
	l.storms_on = false
	var soon_at := {}
	for i in 600:
		for e in l.step(DT, _steady(l), 85.0):
			if e.type == "district_soon":
				soon_at[e.index] = l.elapsed
			if e.type == "district_on":
				assert_float(l.elapsed - soon_at[e.index]).is_greater_equal(2.0)


# --- Brown-out ---

func _full_town(l: GridLogic) -> void:
	l.storms_on = false
	_ride(l, 280.0, _steady)
	assert_int(l.lit()).is_equal(4)


func test_falling_short_dims_the_newest_then_turns_it_off_and_relights() -> void:
	var l := _logic("work", 300.0)
	_full_town(l)
	var events := _ride(l, GridLogic.SHORT_SEC + 0.5, 10.0)
	# The supply takes a while to fall under the line; ride on until it dims.
	while _count(events, "dimming") == 0:
		events.append_array(_ride(l, 0.5, 10.0))
	assert_int(_first(events, "dimming").index).is_equal(3)
	assert_float(float(_first(events, "dimming").need)).is_equal_approx(l.need(), 1.0)
	assert_int(l.powered).is_equal(4)
	var out := _ride(l, GridLogic.DIM_SEC + 0.2, 10.0)
	assert_int(_first(out, "district_out").index).is_equal(3)
	assert_int(l.powered).is_equal(3)
	assert_float(l.level(3)).is_equal(0.0)
	var back := _ride(l, 12.0, 200.0)
	assert_int(_first(back, "relit").index).is_equal(3)
	assert_int(l.lit()).is_equal(4)


func test_the_dim_gives_at_least_two_seconds_before_the_dark() -> void:
	assert_float(GridLogic.DIM_SEC).is_greater_equal(2.0)
	assert_float(GridLogic.DIM_SEC_EASY).is_greater(GridLogic.DIM_SEC)


func test_a_brown_out_never_takes_points_away() -> void:
	var l := _logic("work", 300.0)
	_full_town(l)
	for i in 400:
		l.step(DT, 0.0, 0.0)
		assert_float(l.earned).is_greater_equal(0.0)
	assert_int(l.lit()).is_equal(0)


func test_no_brown_out_while_the_rider_settles() -> void:
	var l := _logic("work", 300.0)
	var events := _ride(l, GridLogic.START_GRACE - 0.2, 0.0, 0.0)
	assert_int(_count(events, "dimming")).is_equal(0)


func test_a_district_coming_online_while_short_stays_dark_until_caught_up() -> void:
	var l := _logic("work", 300.0)
	l.storms_on = false
	_ride(l, 60.0, _steady)
	var events := _ride(l, 80.0, 10.0)
	assert_int(_count(events, "district_missed")).is_greater_equal(1)
	assert_int(l.powered).is_less(l.online)
	_ride(l, 40.0, 200.0)
	assert_int(l.powered).is_equal(l.online)


func test_a_recovery_forgives_more_than_work() -> void:
	var easy := _logic("recovery", 90.0)
	var work := _logic("work", 90.0)
	work.storms_on = false
	var t_easy := 0.0
	var t_work := 0.0
	_ride(easy, 8.0, 100.0)
	_ride(work, 8.0, 100.0)
	while _count(easy.step(DT, 0.0, 85.0), "dimming") == 0 and t_easy < 30.0:
		t_easy += DT
	while _count(work.step(DT, 0.0, 85.0), "dimming") == 0 and t_work < 30.0:
		t_work += DT
	assert_float(t_easy).is_greater(t_work)


func test_a_cool_down_switches_districts_off_quietly_without_a_brown_out() -> void:
	var l := _logic("cooldown", 180.0)
	var events := _ride(l, 180.0, _steady)
	assert_int(_count(events, "district_rest")).is_equal(3)
	assert_int(_count(events, "dimming")).is_equal(0)
	assert_int(l.lit()).is_equal(1)


# --- Storms ---

func _to_strike(l: GridLogic, watts: Variant) -> Dictionary:
	for i in 2000:
		var w: float = watts.call(l) if watts is Callable else float(watts)
		for e in l.step(DT, w, 85.0):
			if e.type == "strike":
				return e
	return {}


func test_storms_only_come_in_work() -> void:
	for role in ["warmup", "cooldown", "recovery"]:
		var l := _logic(role, 600.0)
		assert_int(_count(_ride(l, 600.0, _steady), "storm_warn")).is_equal(0)
	assert_bool(_logic("free", 600.0).storms_on).is_true()


func test_lightning_warns_three_seconds_ahead_with_the_watts_it_will_ask() -> void:
	var l := _logic("work", 300.0)
	var warned := -1.0
	var asked := 0.0
	for i in 2000:
		for e in l.step(DT, _steady(l), 85.0):
			if e.type == "storm_warn":
				warned = l.elapsed
				asked = e.need
			if e.type == "strike":
				assert_float(l.elapsed - warned).is_greater_equal(GridLogic.STORM_WARN_SEC - 0.11)
				assert_float(float(e.need)).is_equal(asked)
				assert_float(float(e.need)).is_equal_approx(l.need() + l.storm_watts, 2.0)
				return
	fail("no strike")


func test_a_downed_line_takes_out_the_newest_lit_district() -> void:
	var l := _logic("work", 300.0)
	var e := _to_strike(l, _steady)
	assert_int(e.index).is_equal(l.powered - 1)
	assert_int(l.lit()).is_equal(l.powered - 1)
	assert_float(l.level(e.index)).is_equal(0.0)


func test_ten_seconds_over_the_repair_line_restores_it_for_a_bonus() -> void:
	var l := _logic("work", 300.0)
	var strike := _to_strike(l, _steady)
	var events := _ride(l, GridLogic.STORM_REPAIR_SEC + 0.5, l.repair_need + 0.2 * FTP)
	assert_int(_first(events, "restored").index).is_equal(strike.index)
	assert_float(float(_first(events, "restored").bonus)).is_equal(GridLogic.STORM_BONUS)
	assert_int(l.storms_restored).is_equal(1)
	assert_int(l.down_index).is_equal(-1)
	assert_int(l.storm).is_equal(GridLogic.Storm.CALM)


func test_a_slip_keeps_most_of_the_repair() -> void:
	var l := _logic("work", 300.0)
	_to_strike(l, _steady)
	_ride(l, 6.0, l.repair_need + 0.2 * FTP)
	var done := l.repair
	assert_float(done).is_greater(4.0)
	l.supply = 0.0
	l.step(1.0, 0.0, 85.0)
	assert_float(l.repair).is_equal_approx(done - GridLogic.STORM_DRAIN, 0.01)


func test_a_rider_who_cant_repair_it_loses_nothing_the_crew_fixes_it() -> void:
	var l := _logic("work", 300.0)
	var strike := _to_strike(l, func(g: GridLogic) -> float: return g.need_ahead(3.0) * 1.03)
	var events := _ride(l, GridLogic.STORM_WINDOW_SEC + 0.5, func(g: GridLogic) -> float: return g.need_ahead(3.0) * 1.03)
	assert_int(_first(events, "crew_fixed").index).is_equal(strike.index)
	assert_int(_count(events, "restored")).is_equal(0)
	assert_int(l.storms_restored).is_equal(0)
	assert_int(l.storms).is_equal(1)
	assert_int(l.down_index).is_equal(-1)


func test_no_storm_too_near_the_end() -> void:
	for seed_value in 12:
		var l := _logic("work", 60.0, "standard", seed_value)
		var warned_at := []
		for i in 600:
			for e in l.step(DT, _steady(l), 85.0):
				if e.type == "storm_warn":
					warned_at.append(l.elapsed)
		for at in warned_at:
			assert_float(60.0 - at).is_greater_equal(GridLogic.STORM_LAST_LEFT)


func test_a_stopped_rider_never_repairs() -> void:
	var l := _logic("work", 300.0)
	_to_strike(l, 300.0)
	var events: Array[Dictionary] = []
	for i in 100:
		events.append_array(l.step(DT, 300.0, 5.0))
	assert_int(_count(events, "restored")).is_equal(0)
	assert_float(l.repair).is_equal(0.0)


# --- Stats ---

func test_lit_pct_and_districts_max() -> void:
	var l := _logic("work", 300.0)
	l.storms_on = false
	_ride(l, 300.0, _steady)
	assert_int(l.lit_pct()).is_equal(100)
	assert_int(l.districts_max).is_equal(4)
	var m := _logic("work", 300.0)
	_ride(m, 60.0, 0.0, 0.0)
	assert_int(m.lit_pct()).is_less(30)


func test_avg_power_is_the_raw_power() -> void:
	var l := _logic("work", 300.0)
	_ride(l, 10.0, 150.0)
	assert_float(l.avg_power()).is_equal_approx(150.0, 0.01)


# --- Stars ---

func _thresholds() -> Array:
	var game = auto_free(GridGame.new())
	return game.info().star_thresholds.standard


func test_a_perfect_ride_at_1x_stays_short_of_three_stars_and_1_3x_reaches_it() -> void:
	var t := _thresholds()
	for seconds in [60.0, 90.0, 300.0, 600.0, 1800.0]:
		for seed_value in 8:
			var perfect := _per_minute(_logic("work", seconds, "standard", seed_value), seconds, _steady, 1.0)
			assert_float(perfect).override_failure_message("%.0f s, seed %d: %.0f a minute" % [seconds, seed_value, perfect]).is_less(float(t[2]))
			var effort := _per_minute(_logic("work", seconds, "standard", seed_value), seconds, _steady, 1.35)
			assert_float(effort).override_failure_message("%.0f s at 1.35x, seed %d: %.0f a minute" % [seconds, seed_value, effort]).is_greater_equal(float(t[2]))


func test_a_clean_easy_ride_earns_three_stars_without_any_multiplier() -> void:
	var t := _thresholds()
	for setup in [["warmup", 180.0], ["cooldown", 180.0], ["recovery", 90.0]]:
		var l := _logic(setup[0], setup[1])
		assert_float(_per_minute(l, setup[1], _steady)).is_greater_equal(float(t[2]))


## The 2026-11 retune's core goal: light pedalling lights the houses, and a steady 30% of FTP
## keeps the whole town lit through a standard work evening.
func test_a_rider_at_thirty_percent_of_ftp_holds_demand_all_evening() -> void:
	var light := _logic("work", 300.0)
	_ride(light, 20.0, 0.15 * FTP)
	assert_bool(light.meeting).is_true()
	assert_int(light.lit()).is_greater_equal(1)
	for difficulty in ["easy", "standard"]:
		var l := _logic("work", 300.0, difficulty)
		l.storms_on = false
		var events := _ride(l, 300.0, 0.30 * FTP)
		assert_int(_count(events, "district_out")).override_failure_message(difficulty).is_equal(0)
		assert_int(l.lit_pct()).override_failure_message(difficulty).is_greater_equal(98)
		assert_int(l.districts_max).is_equal(GridLogic.COUNT)


func test_half_the_ride_on_target_is_about_one_star() -> void:
	var t := _thresholds()
	var l := _logic("work", 300.0)
	l.storms_on = false
	var pm := _per_minute(l, 300.0, func(g: GridLogic) -> float: return _steady(g) if fmod(g.elapsed, 40.0) < 20.0 else 10.0)
	assert_float(pm).is_between(float(t[0]), float(t[1]))
