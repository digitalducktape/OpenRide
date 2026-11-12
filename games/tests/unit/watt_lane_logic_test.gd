extends GdUnitTestSuite
## Watt Lane's rules (#78), driven by scripted power: smoothing, lane membership, the course,
## announce timing, the switch window, catches, streaks and the stars.

const DT := 0.05
## A fixed 40 W lane over 70-105 W, so the timing and scoring tests don't move with a retune.
const LANE := {"ftp_watts": 150, "lane_width_watts": 40, "lane_min_watts": 70, "lane_max_watts": 105}


func _run(logic: WattLaneLogic, seconds: float, power: Variant) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	for i in roundi(seconds / DT):
		var p: float = power.call(logic) if power is Callable else float(power)
		var step := logic.step(DT, p)
		for e in step:
			e["time"] = logic.time
		events.append_array(step)
	return events


func _of(events: Array[Dictionary], type: String) -> Array[Dictionary]:
	return events.filter(func(e): return e.type == type)


## A rider who follows the lane, leading by the window's mean delay.
func _perfect(logic: WattLaneLogic) -> float:
	return logic.course.visual_centre_at(logic.time + 1.5)


# --- Smoothing ---

func test_steady_power_reads_as_itself() -> void:
	var logic := WattLaneLogic.new()
	_run(logic, 5.0, 123.0)
	assert_int(logic.shown_watts).is_equal(123)
	assert_float(logic.smoothed).is_equal_approx(123.0, 0.01)


func test_a_step_ramps_across_three_seconds() -> void:
	var logic := WattLaneLogic.new()
	_run(logic, 4.0, 100.0)
	_run(logic, 1.5, 160.0)
	assert_float(logic.smoothed).is_equal_approx(130.0, 2.0)  # half way after half the window
	_run(logic, 1.6, 160.0)
	assert_int(logic.shown_watts).is_equal(160)  # all the way after 3 s


func test_a_spike_moves_you_only_a_little() -> void:
	var logic := WattLaneLogic.new()
	_run(logic, 4.0, 100.0)
	_run(logic, 0.5, 400.0)
	assert_float(logic.smoothed).is_less(160.0)


# --- The lane ---

func test_width_by_difficulty_with_floors_on_a_10_w_grid() -> void:
	assert_int(WattLaneLogic.new("easy").width).is_equal(40)
	assert_int(WattLaneLogic.new("standard").width).is_equal(30)
	assert_int(WattLaneLogic.new("hard").width).is_equal(30)
	assert_int(WattLaneLogic.new("standard", {"ftp_watts": 300}).width).is_equal(60)
	assert_int(WattLaneLogic.new("hard", {"ftp_watts": 260}).width).is_equal(40)
	assert_int(WattLaneLogic.new("standard", {"lane_width_watts": 45}).width).is_equal(50)


func test_bounds_are_on_the_5_w_grid_and_inside_the_range() -> void:
	for difficulty in ["easy", "standard", "hard"]:
		var logic := WattLaneLogic.new(difficulty, {"ftp_watts": 210}, 7)
		for i in 600:
			logic.time = float(i)
			assert_int(logic.lane_lo() % 5).is_equal(0)
			assert_int(logic.lane_hi() - logic.lane_lo()).is_equal(logic.width)
			var centre := logic.course.centre_at(logic.time)
			assert_int(centre).is_between(logic.course.lane_min, logic.course.lane_max)


func test_membership_is_inclusive_and_uses_the_shown_number() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 1)
	_run(logic, 4.0, float(logic.lane_hi()))
	assert_bool(logic.in_lane).is_true()
	_run(logic, 4.0, float(logic.lane_hi()) + 1.0)
	assert_bool(logic.in_lane).is_false()
	assert_int(logic.side()).is_equal(1)
	_run(logic, 4.0, float(logic.lane_lo()))
	assert_bool(logic.in_lane).is_true()


func test_the_kotlin_params_win() -> void:
	var logic := WattLaneLogic.new("standard", {"ftp_watts": 200, "lane_min_watts": 100, "lane_max_watts": 160,
		"lane_width_watts": 40})
	for i in 300:
		assert_int(logic.course.centre_at(float(i))).is_between(100, 160)


# --- The course ---

func test_the_same_seed_gives_the_same_course() -> void:
	var a := WattLaneCourse.new(42, 70, 105, 150.0)
	var b := WattLaneCourse.new(42, 70, 105, 150.0)
	var c := WattLaneCourse.new(43, 70, 105, 150.0)
	a.ensure(600.0)
	b.ensure(600.0)
	c.ensure(600.0)
	assert_array(Array(a.watts)).is_equal(Array(b.watts))
	assert_array(Array(a.times)).is_equal(Array(b.times))
	assert_bool(Array(a.watts) == Array(c.watts) and Array(a.times) == Array(c.times)).is_false()


func test_jumps_are_big_spaced_and_the_first_comes_after_the_lead_in() -> void:
	for seed_value in 20:
		var c := WattLaneCourse.new(seed_value, 70, 105, 150.0)
		c.ensure(900.0)
		var last := -100.0
		var first := true
		for i in range(1, c.times.size()):
			if c.jumps[i] == 0:
				assert_int(absi(c.watts[i] - c.watts[i - 1])).is_equal(5)  # drifts step 5 W
				continue
			if first:
				assert_float(c.times[i]).is_between(20.0, 24.0)
				first = false
			assert_float(c.times[i] - last).is_greater_equal(20.0)
			last = c.times[i]
			assert_int(absi(c.watts[i] - c.watts[i - 1])).is_greater_equal(25)  # over half the 40 W lane


func test_a_narrow_range_widens_so_every_jump_clears_half_a_lane() -> void:
	var c := WattLaneCourse.new(1, 70, 105, 150.0, false, 40)
	assert_int(c.jump_min).is_equal(25)
	assert_int(c.lane_max - c.lane_min).is_greater_equal(50)
	assert_int(c.lane_min).is_greater_equal(45)
	for difficulty in ["easy", "standard", "hard"]:
		for ftp in [100.0, 150.0, 250.0, 400.0]:
			var logic := WattLaneLogic.new(difficulty, {"ftp_watts": ftp}, 3)
			logic.course.ensure(600.0)
			for i in range(1, logic.course.times.size()):
				if logic.course.jumps[i] == 1:
					assert_int(absi(logic.course.watts[i] - logic.course.watts[i - 1])).is_greater(logic.width / 2)


func test_drifts_never_outrun_the_rate() -> void:
	var c := WattLaneCourse.new(5, 70, 105, 150.0)
	c.ensure(900.0)
	for i in range(1, c.times.size()):
		if c.jumps[i] == 0:
			assert_float(c.times[i] - c.times[i - 1]).is_greater_equal(5.0 / 1.5 - 0.01)


func test_a_warm_up_starts_low_and_climbs() -> void:
	var c := WattLaneCourse.new(3, 50, 80, 150.0, true)
	assert_int(c.centre_at(0.0)).is_equal(c.lane_min)
	var j := c.next_jump_after(0.0)
	assert_int(c.watts[j]).is_greater(c.watts[j - 1])


func test_an_open_ride_never_runs_out() -> void:
	var c := WattLaneCourse.new(9, 70, 105, 150.0)
	assert_int(c.next_jump_after(3000.0)).is_greater(0)
	assert_float(c.times[c.next_jump_after(3000.0)]).is_greater(3000.0)


func test_the_visual_centre_eases_but_stays_near_the_rules() -> void:
	var c := WattLaneCourse.new(11, 70, 105, 150.0)
	for i in 1200:
		var t := float(i) * 0.25
		var j := c.last_jump_at(t)
		var nj := c.next_jump_after(t)
		var near_jump := (j > 0 and t - c.times[j] < 1.0) or (nj > 0 and c.times[nj] - t < 1.0)
		if not near_jump:
			assert_float(absf(c.visual_centre_at(t) - c.centre_at(t))).is_less_equal(5.0)


# --- Announcing and the switch ---

func test_each_jump_is_announced_five_seconds_ahead_then_counted_down() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 21)
	var events := _run(logic, 120.0, _perfect)
	var announces := _of(events, "announce")
	var jumps := _of(events, "jump")
	assert_int(announces.size()).is_greater_equal(4)
	for k in jumps.size():
		assert_float(jumps[k].time - announces[k].time).is_between(WattLaneLogic.ANNOUNCE_SEC - DT, WattLaneLogic.ANNOUNCE_SEC + DT)
	var counts := _of(events, "count").slice(0, 3).map(func(e): return e.n)
	assert_array(counts).is_equal([3, 2, 1])


func test_the_announce_names_the_new_lane() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 21)
	var events := _run(logic, 30.0, _perfect)
	var a: Dictionary = _of(events, "announce")[0]
	var j := logic.course.next_jump_after(0.0)
	assert_int(a.lo).is_equal(logic.course.watts[j] - 20)
	assert_int(a.hi).is_equal(logic.course.watts[j] + 20)
	assert_bool(a.up).is_equal(logic.course.watts[j] > logic.course.watts[j - 1])


func test_either_lane_counts_in_the_switch_window() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 21)
	var j := logic.course.next_jump_after(0.0)
	var old := logic.course.watts[j - 1]
	var new := logic.course.watts[j]
	logic.time = logic.course.times[j] - 1.0
	var b := logic.band()
	assert_int(b.x).is_equal(mini(old, new) - 20)
	assert_int(b.y).is_equal(maxi(old, new) + 20)
	logic.time = logic.course.times[j] + 3.0
	assert_int(logic.band().x).is_equal(b.x)
	logic.time = logic.course.times[j] + 4.0
	assert_int(logic.band().y - logic.band().x).is_equal(40)  # one lane again


func test_holding_the_old_lane_misses_the_jump_and_following_catches_it() -> void:
	var stay := WattLaneLogic.new("standard", LANE, 21)
	var j := stay.course.next_jump_after(0.0)
	var old := float(stay.course.watts[j - 1])
	var events := _run(stay, stay.course.times[j] + 4.0, old)
	assert_int(_of(events, "missed").size()).is_equal(1)
	assert_int(stay.jumps_caught).is_equal(0)
	var follow := WattLaneLogic.new("standard", LANE, 21)
	events = _run(follow, follow.course.times[j] + 4.0, _perfect)
	assert_int(_of(events, "caught").size()).is_equal(1)
	assert_int(_of(events, "lane_exit").size()).is_equal(0)


func test_a_rider_who_reacts_only_at_the_jump_still_catches_it() -> void:
	# The bike's lag: a new reading about once a second, so the rider's change lands up to 1 s late.
	var logic := WattLaneLogic.new("standard", LANE, 21)
	var j := logic.course.next_jump_after(0.0)
	var at := logic.course.times[j]
	var lagged := func(l: WattLaneLogic) -> float:
		return float(l.course.watts[j] if l.time >= at + 1.0 else l.course.watts[j - 1])
	var events := _run(logic, at + 4.0, lagged)
	assert_int(_of(events, "caught").size()).is_equal(1)


# --- Scoring ---

func test_the_streak_grows_to_three_and_survives_a_short_slip() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 21)
	var centre := float(logic.course.centre_at(0.0))
	var events := _run(logic, 9.9, centre)
	_run(logic, 0.1, centre)
	assert_float(logic.streak_multiplier()).is_equal(2.0)
	_run(logic, 0.6, 0.0)  # the window still reads near the lane: still in
	var before := logic.streak_sec
	assert_float(before).is_greater(9.0)
	events = _run(logic, 3.0, 0.0)
	assert_int(_of(events, "lane_exit").size()).is_equal(1)
	assert_float(logic.streak_sec).is_equal(0.0)


func test_points_only_come_in_the_lane() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 21)
	var total := 0.0
	for i in 100:
		logic.step(DT, 0.0)
		total += logic.last_points
	assert_float(total).is_equal(0.0)


func _per_minute(seconds: float, effort: float, role := "work", seed_value := 21) -> float:
	var logic := WattLaneLogic.new("standard", LANE, seed_value, role)
	var total := 0.0
	for i in roundi(seconds / DT):
		logic.step(DT, _perfect(logic))
		total += logic.last_points * effort
	return total / (seconds / 60.0)


func _stars(per_minute: float) -> int:
	return Stars.count(per_minute, WattLaneLogic.STARS)


func test_a_perfect_ride_at_one_times_effort_stays_short_of_three_stars() -> void:
	for seconds in [60.0, 90.0, 600.0]:
		var pm := _per_minute(seconds, 1.0)
		assert_int(_stars(pm)).is_equal(2)


func test_three_stars_takes_about_one_point_three_times_effort() -> void:
	for seconds in [60.0, 90.0, 600.0]:
		assert_int(_stars(_per_minute(seconds, 1.3))).is_equal(3)
		if seconds < 120.0:  # a short slot spends a third of itself building the streak
			assert_int(_stars(_per_minute(seconds, 1.15))).is_less(3)


func test_a_clean_warm_up_can_earn_three_stars() -> void:
	assert_int(_stars(_per_minute(180.0, 1.0, "warmup"))).is_equal(3)


func test_a_rider_in_the_lane_half_the_time_earns_one_star() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 21)
	var total := 0.0
	for i in roundi(120.0 / DT):
		var on := fmod(logic.time, 20.0) < 10.0
		logic.step(DT, _perfect(logic) if on else 0.0)
		total += logic.last_points
	assert_int(_stars(total / 2.0)).is_equal(1)


## The 2026-11 retune's core goal: the lane sits around a comfortable 30-35% of FTP, so a rider
## who follows it averages about that, and a steady 30% rider is in it much of the time.
func test_a_rider_at_thirty_percent_of_ftp_rides_the_lane() -> void:
	for ftp: float in [140.0, 200.0]:
		var follower := WattLaneLogic.new("standard", {"ftp_watts": ftp}, 5)
		var steady := WattLaneLogic.new("standard", {"ftp_watts": ftp}, 5)
		var power_sum := 0.0
		var steady_in := 0.0
		var steady_points := 0.0
		for i in roundi(600.0 / DT):
			var p := _perfect(follower)
			power_sum += p * DT
			follower.step(DT, p)
			steady.step(DT, 0.30 * ftp)
			steady_points += steady.last_points
			if steady.in_lane:
				steady_in += DT
		var mean_share: float = power_sum / 600.0 / ftp
		assert_float(mean_share).override_failure_message("FTP %d: the lane averages %.2f of FTP" % [ftp, mean_share]) \
			.is_between(0.25, 0.38)
		assert_float(steady_in / 600.0).override_failure_message("FTP %d: 30%% is in the lane %.2f of the time" % [ftp, steady_in / 600.0]) \
			.is_greater(0.4)
		assert_int(_stars(steady_points / 10.0)).is_greater_equal(1)


func test_stats() -> void:
	var logic := WattLaneLogic.new("standard", LANE, 21)
	_run(logic, 60.0, _perfect)
	assert_float(logic.in_lane_pct()).is_greater(95.0)
	assert_float(logic.longest_streak).is_greater(50.0)
	assert_int(logic.jumps).is_greater_equal(1)
	assert_int(logic.jumps_caught).is_equal(logic.jumps)
	assert_float(logic.avg_power()).is_greater(50.0)
