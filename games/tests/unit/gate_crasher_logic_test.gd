extends GdUnitTestSuite
## Gate Crasher's rules (#80): the take-off window with the camera's lag included, the fault
## rules, the spacing, the lost-camera circle, no scoring without pedalling, and the stars.

const DT := 1.0 / 60.0
const STAR_TABLE := "res://games/gate_crasher/GateCrasher.gd"

var logic: GateLogic
var events: Array = []
var points := 0.0


## A rider through the real detector's lags: `stand_at` is the seconds from the line that the rider
## really stands (null: stays seated). The stand reads `lag` later, and the sit SIT_LAG after they
## sit, 1 s after standing.
class Rider:
	var stand_at = 0.0
	var up_since := -1.0
	var sit_since := -1.0
	var reads := false
	var clock := 0.0
	var done_fence := -1

	func standing(l: GateLogic, delta: float) -> bool:
		clock += delta
		var to_line := (l.line_s(l.fence) - l.distance) / maxf(l.speed, 0.5)
		if stand_at != null and done_fence != l.fence and l.speed > 1.0 and to_line <= -float(stand_at):
			done_fence = l.fence
			up_since = clock
		if up_since >= 0.0 and not reads and clock - up_since >= l.lag:
			reads = true
		if up_since >= 0.0 and clock - up_since >= 1.0:
			up_since = -1.0
			sit_since = clock
		if sit_since >= 0.0 and clock - sit_since >= GateLogic.SIT_LAG:
			sit_since = -1.0
			reads = false
		return reads


func before_test() -> void:
	logic = GateLogic.new({"pace_watts": 110.0, "window_sec": 1.2})
	events = []
	points = 0.0


func _step(watts: float, standing := false, camera := true, rpm := 85.0, sensors := true) -> Array:
	var e: Array = logic.step(DT, watts, rpm, standing, camera, sensors)
	events.append_array(e)
	points += logic.last_points
	return e


func _types() -> Array:
	return events.map(func(e: Dictionary) -> String: return e.type)


func _count(type: String) -> int:
	return _types().count(type)


func _ride_with(rider: Rider, watts: float, until_fence: int) -> void:
	var guard := 0
	while logic.fence < until_fence and logic.phase != GateLogic.Phase.DONE and guard < 60000:
		_step(watts, rider.standing(logic, DT))
		guard += 1


## Rides until `seconds` from the next line.
func _ride_to_eta(watts: float, seconds: float) -> void:
	var guard := 0
	while (logic.speed < 1.0 or logic.eta() > seconds) and guard < 20000:
		_step(watts)
		guard += 1


func test_a_stand_on_the_line_clears_the_fence() -> void:
	_ride_with(Rider.new(), 110.0, 1)
	assert_int(logic.clears).is_equal(1)
	assert_int(logic.faults).is_equal(0)
	assert_int(_count("stand_ok")).is_equal(1)


func test_the_window_is_half_its_width_either_side_of_the_line_with_the_lag_included() -> void:
	for case in [[-0.55, true], [0.55, true], [-0.75, false], [0.75, false]]:
		before_test()
		var rider := Rider.new()
		rider.stand_at = case[0]
		_ride_with(rider, 110.0, 1)
		assert_int(logic.clears).override_failure_message("stand at %s" % case[0]).is_equal(1 if case[1] else 0)
		assert_int(logic.faults).override_failure_message("stand at %s" % case[0]).is_equal(0 if case[1] else 4)


func test_a_stand_that_reads_before_the_window_is_early() -> void:
	var rider := Rider.new()
	rider.stand_at = -1.5
	_ride_with(rider, 110.0, 1)
	var fault: Dictionary = events.filter(func(e): return e.type == "fault")[0]
	assert_str(fault.why).is_equal("early")


func test_staying_seated_knocks_a_rail_late() -> void:
	var rider := Rider.new()
	rider.stand_at = null
	_ride_with(rider, 110.0, 1)
	var fault: Dictionary = events.filter(func(e): return e.type == "fault")[0]
	assert_str(fault.why).is_equal("late")
	assert_int(logic.faults).is_equal(GateLogic.FAULTS_PER_RAIL)
	assert_float(fault.penalty).is_greater(0.0)


func test_riding_out_of_the_saddle_clears_nothing() -> void:
	while logic.fence < 1:
		_step(110.0, true)
	assert_int(logic.clears).is_equal(0)
	assert_int(logic.faults).is_equal(GateLogic.FAULTS_PER_RAIL)
	assert_int(_count("sit_first")).is_equal(1)


func test_the_countdown_gives_three_beats_then_the_line_at_every_fence() -> void:
	_ride_with(Rider.new(), 110.0, 3)
	assert_int(_count("beat")).is_equal(9)
	assert_int(_count("line")).is_equal(3)
	var beats: Array = events.filter(func(e): return e.type == "beat").map(func(e): return e.n)
	assert_array(beats.slice(0, 3)).is_equal([3, 2, 1])


func test_fences_are_at_least_five_seconds_apart_at_top_speed() -> void:
	assert_float(logic.spacing / GateLogic.V_MAX).is_greater_equal(GateLogic.MIN_GAP_SEC)
	var crowded := GateLogic.new({"fences": 40})
	assert_float(crowded.spacing / GateLogic.V_MAX).is_greater_equal(GateLogic.MIN_GAP_SEC)


func test_the_sit_reads_before_the_next_window_at_top_speed() -> void:
	# The latest stand (half a window after the line), held 1 s, reads seated this long after it:
	var seated_at := logic.window_sec / 2.0 + 1.0 + GateLogic.SIT_LAG
	var next_window := logic.spacing / GateLogic.V_MAX - logic.window_lead()
	assert_float(seated_at).is_less(next_window)
	var rider := Rider.new()
	rider.stand_at = 0.55
	_ride_with(rider, 500.0, GateLogic.FENCES)
	assert_int(logic.clears).is_equal(GateLogic.FENCES)


func test_the_window_closes_before_the_horse_leaves_the_ground_at_top_speed() -> void:
	for level in GateLogic.LEVELS:
		var l := GateLogic.new({}, level)
		var closes_after_line: float = l.window_sec - l.window_lead()
		assert_float(closes_after_line * GateLogic.V_MAX).is_less(GateLogic.LINE_GAP - GateLogic.TAKEOFF)


func test_a_clear_round_pays_the_bonus_and_a_rail_does_not() -> void:
	var rider := Rider.new()
	_ride_with(rider, 110.0, GateLogic.FENCES)
	var end: Dictionary = events.filter(func(e): return e.type == "round_end")[0]
	assert_bool(end.clear).is_true()
	assert_float(end.bonus).is_equal(GateLogic.ROUND_BONUS)
	assert_int(logic.clear_rounds).is_equal(1)
	# The next round: seated for one fence.
	rider.stand_at = null
	_ride_with(rider, 110.0, GateLogic.FENCES + 1)
	rider.stand_at = 0.0
	_ride_with(rider, 110.0, GateLogic.FENCES * 2)
	var second: Dictionary = events.filter(func(e): return e.type == "round_end")[1]
	assert_bool(second.clear).is_false()
	assert_float(second.bonus).is_equal(0.0)
	assert_int(logic.clear_rounds).is_equal(1)


func test_a_rounds_ride_ends_after_its_last_round() -> void:
	logic = GateLogic.new({"pace_watts": 110.0, "fences": 2}, "standard", "rounds", 2)
	_ride_with(Rider.new(), 110.0, 99)
	assert_int(logic.phase).is_equal(GateLogic.Phase.DONE)
	assert_int(logic.rounds_done).is_equal(2)
	assert_int(_count("done")).is_equal(1)


func test_nothing_scores_without_pedalling() -> void:
	_ride_to_eta(110.0, 1.0)
	points = 0.0
	events.clear()
	# The horse coasts on, the rider stands in the window, the legs have stopped.
	for i in 300:
		_step(0.0, i > 60, true, 0.0)
	assert_float(points).is_equal(0.0)
	assert_int(logic.clears).is_equal(0)
	assert_int(_count("clear")).is_equal(0)


func test_the_horse_stops_without_pedalling() -> void:
	_ride_to_eta(110.0, 2.0)
	for i in 600:
		_step(0.0, false, true, 0.0)
	assert_float(logic.speed).is_equal(0.0)


func test_a_fence_crossed_without_pedalling_is_not_a_fault_and_spoils_the_clear_round() -> void:
	logic = GateLogic.new({"pace_watts": 110.0, "fences": 2})
	var rider := Rider.new()
	_ride_with(rider, 110.0, 1)
	var guard := 0
	while logic.fence < 2 and guard < 20000:
		# Legs stop just before the fence, with the speed still carrying the horse over it.
		var near: bool = logic.fence_s(1) - logic.distance < 3.0
		_step(0.0 if near else 110.0, rider.standing(logic, DT), true, 0.0 if near else 85.0)
		guard += 1
	assert_int(logic.faults).is_equal(0)
	assert_int(_count("no_pedal")).is_equal(1)
	assert_int(logic.clear_rounds).is_equal(0)


func test_speed_follows_power_and_stops_at_the_cap() -> void:
	assert_float(logic.target_speed(110.0)).is_equal(GateLogic.V_PACE)
	assert_float(logic.target_speed(9.0)).is_equal(0.0)
	assert_float(logic.target_speed(60.0)).is_between(GateLogic.V_WALK, GateLogic.V_PACE)
	assert_float(logic.target_speed(1000.0)).is_equal(GateLogic.V_MAX)


func test_a_lost_camera_circles_and_judges_nothing() -> void:
	_ride_to_eta(110.0, 0.05)
	var fence := logic.fence
	for i in 600:
		_step(110.0, false, false)
	assert_int(logic.phase).is_equal(GateLogic.Phase.CIRCLE)
	assert_int(logic.fence).is_equal(fence)
	assert_int(logic.faults).is_equal(0)
	assert_int(_count("circle")).is_equal(1)
	# Standing while unseen doesn't count, and no points come in.
	points = 0.0
	for i in 60:
		_step(110.0, true, false)
	assert_float(points).is_equal(0.0)


func test_the_circle_ends_once_the_rider_is_seen_with_a_whole_countdown_ahead() -> void:
	_ride_to_eta(110.0, 0.5)
	for i in 120:
		_step(110.0, false, false)
	var guard := 0
	while logic.phase == GateLogic.Phase.CIRCLE and guard < 2000:
		_step(110.0)
		guard += 1
	assert_int(logic.phase).is_equal(GateLogic.Phase.RIDE)
	assert_int(_count("circle_end")).is_equal(1)
	assert_float(logic.line_s(logic.fence) - logic.distance).is_greater_equal(GateLogic.BEATS[0] * GateLogic.V_PACE)
	events.clear()
	_ride_with(Rider.new(), 110.0, logic.fence + 1)
	assert_int(_count("beat")).is_equal(3)
	assert_int(logic.faults).is_equal(0)


func test_a_lost_sensor_freezes_the_ride() -> void:
	_ride_to_eta(110.0, 2.0)
	var at := logic.distance
	for i in 120:
		_step(110.0, false, true, 85.0, false)
	assert_float(logic.distance).is_equal(at)


func test_params_set_the_pace_and_window_and_levels_fill_in() -> void:
	var l := GateLogic.new({"ftp_watts": 300.0}, "hard")
	assert_float(l.pace_watts).is_equal_approx(195.0, 0.01)
	assert_float(l.window_sec).is_equal(1.2)
	assert_float(GateLogic.new({"pace_watts": 123.0, "window_sec": 1.3}).pace_watts).is_equal(123.0)
	assert_float(GateLogic.new({"window_sec": 1.3}).window_sec).is_equal(1.3)


## Points a minute over two rounds of a perfect ride at `watts_share` of pace, with `multiplier`
## applied as Effort does.
func _perfect_rate(level: String, watts_share: float, multiplier: float) -> float:
	logic = GateLogic.new({"pace_watts": 110.0}, level)
	var rider := Rider.new()
	var score := 0.0
	var sec := 0.0
	while logic.fence < GateLogic.FENCES * 2:
		var e: Array = logic.step(DT, 110.0 * watts_share, 85.0, rider.standing(logic, DT), true, true)
		sec += DT
		score += logic.last_points * multiplier
		for ev: Dictionary in e:
			score += float(ev.get("points", 0.0)) * multiplier + float(ev.get("bonus", 0.0)) * multiplier
	return score / sec * 60.0


func test_stars_a_perfect_ride_at_1x_stays_short_of_three_and_1_3x_reaches_them() -> void:
	var table: Dictionary = load(STAR_TABLE).STARS
	for level in table:
		var three: float = table[level][2]
		assert_float(_perfect_rate(level, 1.3, 1.0)).override_failure_message("%s flat out at 1.0x" % level).is_less(three)
		assert_float(_perfect_rate(level, 1.0, 1.3)).override_failure_message("%s at pace, 1.3x" % level).is_greater_equal(three)
