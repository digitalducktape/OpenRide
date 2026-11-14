extends GdUnitTestSuite
## Kart Race's handling (#43, Phase 2 Task A1): drift entry with the lean (and its jitter and
## face-loss guards), spark tiers, the knob, mini-turbos, boost pads, the rocket start, drafting,
## climbs with standing, spin-outs, kart contacts, the steering assist's tuning and the bots'
## drift helpers.

const Fixtures := preload("res://tests/kart_fixtures.gd")
const DT := 1.0 / 60.0


func _kart(track: KartTrackModel, s := 0.0, d := 0.0, id := 0) -> KartState:
	var k := KartState.new()
	k.id = id
	var p := track.sample(s)
	k.s = s
	k.d = d
	k.pos = track.position_at(s, d)
	k.heading = atan2(-p.tangent.x, -p.tangent.z)
	return k


func _in(power := 150.0, lean := 0.0) -> KartInput:
	var inp := KartInput.new()
	inp.power_w = power
	inp.cadence = 85.0
	inp.lean = lean
	return inp


func _run(physics: KartPhysics, k: KartState, inp: KartInput, track: KartTrackModel, seconds: float) -> void:
	for i in roundi(seconds / DT):
		physics.step(k, inp, track, DT)


## A long straight, the kart up to speed at its middle.
func _cruising(physics: KartPhysics, s_back := 300.0) -> Array:
	var track := KartTrackModel.new(Fixtures.oval(800.0))
	var k := _kart(track, track.length - s_back)
	_run(physics, k, _in(), track, 12.0)
	return [track, k]


## A wide circle (every turn a left), the kart at cruise on it: long left drifts stay on the road.
func _circling(physics: KartPhysics) -> Array:
	var track := KartTrackModel.new(Fixtures.circle(40.0, 32, 7.0))
	var k := _kart(track, 10.0)
	k.speed = 20.0
	k.v_bike = 20.0 / KartPhysics.SPEED_SCALE
	return [track, k]


func _events(physics: KartPhysics) -> Dictionary:
	var log := {"drift": [], "tier": [], "boost": []}
	physics.events = KartRaceEvents.new()
	physics.events.drift_started.connect(func(id: int, dir: int): log.drift.append([id, dir]))
	physics.events.drift_tier.connect(func(id: int, tier: int): log.tier.append([id, tier]))
	physics.events.boost_started.connect(func(id: int, kind: String, tier: int): log.boost.append([id, kind, tier]))
	return log


# --- Drift entry ---

func test_a_drift_starts_only_after_a_hard_lean_held_for_0_12_s() -> void:
	var physics := KartPhysics.new()
	var log := _events(physics)
	var setup := _cruising(physics)
	var track: KartTrackModel = setup[0]
	var k: KartState = setup[1]
	assert_float(k.speed).is_greater(0.4 * physics.top_speed)
	# 0.10 s isn't enough.
	_run(physics, k, _in(150.0, 0.8), track, 0.10)
	assert_int(k.drift_dir).is_equal(0)
	_run(physics, k, _in(), track, 1.0)
	# Nor is a lean just under the threshold, however long.
	_run(physics, k, _in(150.0, 0.6), track, 1.0)
	assert_int(k.drift_dir).is_equal(0)
	_run(physics, k, _in(), track, 1.0)
	assert_bool(log.drift.is_empty()).is_true()
	# 0.65 held for 0.15 s is: a drift to the right.
	_run(physics, k, _in(150.0, 0.65), track, 0.15)
	assert_int(k.drift_dir).is_equal(1)
	assert_array(log.drift).is_equal([[0, 1]])


func test_no_drift_below_40_percent_of_top_speed() -> void:
	var physics := KartPhysics.new()
	var track := KartTrackModel.new(Fixtures.oval(800.0))
	var k := _kart(track, track.length - 300.0)
	k.speed = 0.35 * physics.top_speed
	k.v_bike = k.speed / KartPhysics.SPEED_SCALE
	_run(physics, k, _in(0.0, -1.0), track, 0.5)
	assert_int(k.drift_dir).is_equal(0)


func test_lean_jitter_never_starts_a_drift_or_swerves_off_the_road() -> void:
	for wave in ["sine", "square"]:
		var physics := KartPhysics.new()
		var log := _events(physics)
		var track := KartTrackModel.new(Fixtures.meadow())
		var k := _kart(track, 20.0)
		k.speed = 18.0
		k.v_bike = 18.0 / KartPhysics.SPEED_SCALE
		var walls := [0]
		physics.events.wall_bump.connect(func(_id: int, _s: float): walls[0] += 1)
		var inp := _in()
		for i in roundi(30.0 / DT):
			var phase := TAU * 5.0 * i * DT
			inp.lean = 0.7 * (sin(phase) if wave == "sine" else signf(sin(phase) + 0.0001))
			physics.step(k, inp, track, DT)
			assert_float(absf(k.d)).override_failure_message("%s jitter: off the road at %.0f m (d %.2f)" % [wave, k.s, k.d]) \
				.is_less(track.half_width(k.s) + KartTrackModel.KERB_WIDTH)
		assert_array(log.drift).override_failure_message("%s jitter started a drift" % wave).is_empty()
		assert_int(walls[0]).is_equal(0)


func test_a_lean_easing_to_zero_after_face_loss_never_starts_a_drift() -> void:
	var physics := KartPhysics.new()
	physics.assist = 0.0  # even with the assist off, the kart holds the road while the face is lost
	var log := _events(physics)
	var track := KartTrackModel.new(Fixtures.meadow())
	var k := _kart(track, 200.0)
	k.speed = 20.0
	k.v_bike = 20.0 / KartPhysics.SPEED_SCALE
	var inp := _in(150.0, 0.4)
	_run(physics, k, inp, track, 0.5)
	# The face is lost: the last reading spikes to 0.9, then the lean eases to 0 over 0.6 s.
	inp.tracking = false
	for i in roundi(4.0 / DT):
		inp.lean = maxf(0.0, 0.9 * (1.0 - i * DT / 0.6))
		physics.step(k, inp, track, DT)
		assert_float(absf(k.d)).is_less(track.half_width(k.s) + KartTrackModel.KERB_WIDTH)
	assert_array(log.drift).is_empty()
	assert_int(k.drift_dir).is_equal(0)


func test_a_drift_hops_then_slides_nose_into_the_turn() -> void:
	var physics := KartPhysics.new()
	physics.assist = 0.0  # on a straight, the assist bends the arc toward the road's (none)
	var setup := _cruising(physics)
	var track: KartTrackModel = setup[0]
	var k: KartState = setup[1]
	var peak := 0.0
	for i in 20:
		physics.step(k, _in(150.0, -0.9), track, DT)
		peak = maxf(peak, k.hop)
	assert_int(k.drift_dir).is_equal(-1)
	assert_float(peak).is_between(0.15, 0.6)
	_run(physics, k, _in(150.0, -0.9), track, 0.1)
	assert_float(k.hop).is_equal(0.0)
	# A left drift: the nose swings left (+), and the kart turns left (the yaw grows).
	assert_float(k.slide).is_greater(0.2)
	var yaw := k.heading
	_run(physics, k, _in(150.0, -0.9), track, 0.15)
	assert_float(angle_difference(yaw, k.heading)).is_greater(0.1)
	# Leaning further in tightens the slide; easing toward the centre widens it.
	var tight := KartState.new()
	var wide := KartState.new()
	for pair in [[tight, -1.0], [wide, -0.4]]:
		var kk: KartState = pair[0]
		var t2 := track
		var start := _kart(t2, t2.length - 300.0)
		kk.pos = start.pos
		kk.s = start.s
		kk.heading = start.heading
		kk.speed = 20.0
		kk.v_bike = 20.0 / KartPhysics.SPEED_SCALE
		physics.assist = 0.0
		_run(physics, kk, _in(150.0, -0.9), t2, 0.4)
		var h0 := kk.heading
		_run(physics, kk, _in(150.0, float(pair[1])), t2, 0.1)
		kk.set_meta("turn", angle_difference(h0, kk.heading))
	assert_float(float(tight.get_meta("turn"))).is_greater(float(wide.get_meta("turn")) * 1.5)


# --- Charge, tiers, the knob and the mini-turbo ---

func _tier_times(physics: KartPhysics, resistance: float, rise := 0.0) -> Array:
	var log := _events(physics)
	var setup := _circling(physics)
	var track: KartTrackModel = setup[0]
	var k: KartState = setup[1]
	var inp := _in(150.0, -0.7)
	inp.resistance = resistance
	var times := []
	var t := 0.0
	var started := -1.0
	while t < 4.0:
		physics.step(k, inp, track, DT)
		t += DT
		if started < 0.0 and k.drift_dir != 0:
			started = t
			inp.resistance = resistance + rise
		if log.tier.size() > times.size():
			times.append(t - started)
	return [times, log, k]


func test_spark_tiers_arrive_at_0_9_2_0_and_3_4_s() -> void:
	var r := _tier_times(KartPhysics.new(), 10.0)
	var times: Array = r[0]
	assert_int(times.size()).is_equal(3)
	assert_float(times[0]).is_equal_approx(0.9, 0.035)
	assert_float(times[1]).is_equal_approx(2.0, 0.035)
	assert_float(times[2]).is_equal_approx(3.4, 0.035)
	assert_array(r[1].tier.map(func(e): return e[1])).is_equal([1, 2, 3])
	assert_bool((r[2] as KartState).knob_boosting).is_false()


func test_snaking_on_a_straight_charges_slowly() -> void:
	var physics := KartPhysics.new()
	physics.assist = 0.0
	var log := _events(physics)
	var setup := _cruising(physics, 380.0)
	var track: KartTrackModel = setup[0]
	var k: KartState = setup[1]
	_run(physics, k, _in(150.0, 0.8), track, 1.2)
	assert_int(k.drift_dir).is_equal(1)
	assert_array(log.tier).is_empty()
	assert_float(k.drift_charge).is_less(0.35)


func test_the_knob_charges_1_6_times_faster() -> void:
	# Resistance at or over drift_resistance.
	var physics := KartPhysics.new()
	var r := _tier_times(physics, physics.drift_resistance)
	assert_float(r[0][0]).is_equal_approx(0.9 / 1.6, 0.035)
	assert_float(r[0][2]).is_equal_approx(3.4 / 1.6, 0.035)
	assert_bool((r[2] as KartState).knob_boosting).is_true()
	# Or a rise of 5 since the drift began.
	var rose := _tier_times(KartPhysics.new(), 20.0, 5.0)
	assert_float(rose[0][1]).is_equal_approx(2.0 / 1.6, 0.035)
	# A rise of 4 isn't enough.
	var small := _tier_times(KartPhysics.new(), 20.0, 4.0)
	assert_float(small[0][1]).is_equal_approx(2.0, 0.035)


func _release_after(charge_sec: float) -> Array:
	var physics := KartPhysics.new()
	var log := _events(physics)
	var setup := _circling(physics)
	var track: KartTrackModel = setup[0]
	var k: KartState = setup[1]
	_run(physics, k, _in(150.0, -0.7), track, 0.15 + charge_sec)
	assert_int(k.drift_dir).is_equal(-1)
	_run(physics, k, _in(150.0, -0.1), track, 0.2)
	return [k, log]


func test_easing_off_releases_a_mini_turbo_by_tier() -> void:
	var expect := [[0.5, 0.0], [1.2, 0.5], [2.3, 0.9], [3.7, 1.4]]
	for e in expect:
		var r := _release_after(float(e[0]))
		var k: KartState = r[0]
		var log: Dictionary = r[1]
		assert_int(k.drift_dir).is_equal(0)
		assert_int(k.drift_tier).is_equal(0)
		assert_float(k.drift_charge).is_equal(0.0)
		if float(e[1]) == 0.0:
			assert_array(log.boost).is_empty()
			assert_float(k.boost_time).is_equal(0.0)
		else:
			var tier := 1 if float(e[1]) == 0.5 else (2 if float(e[1]) == 0.9 else 3)
			assert_array(log.boost).is_equal([[0, "drift", tier]])
			# The boost started up to 0.05 s ago (the 0.15 s release window inside 0.2 s).
			assert_float(k.boost_time).is_between(float(e[1]) - 0.07, float(e[1]))
			assert_str(k.boost_kind).is_equal("drift")


func test_a_brief_ease_doesnt_release_the_drift() -> void:
	var physics := KartPhysics.new()
	var setup := _circling(physics)
	var track: KartTrackModel = setup[0]
	var k: KartState = setup[1]
	_run(physics, k, _in(150.0, -0.7), track, 0.5)
	_run(physics, k, _in(150.0, -0.1), track, 0.1)
	_run(physics, k, _in(150.0, -0.7), track, 0.2)
	assert_int(k.drift_dir).is_equal(-1)


func test_a_mini_turbo_punches() -> void:
	var r := _release_after(3.7)
	var k: KartState = r[0]
	var cruise := KartPhysics.steady_bike_speed(150.0, 0.0) * KartPhysics.SPEED_SCALE
	assert_float(k.speed).is_greater(cruise * 1.15)


# --- Boost pads, the rocket start ---

func test_a_boost_pad_boosts_once_per_visit() -> void:
	var track := KartTrackModel.new(Fixtures.meadow())
	var pad: Dictionary = {}
	for z in track.zones:
		if str(z.type) == "boost":
			pad = z
			break
	assert_bool(pad.is_empty()).is_false()
	for lane in [float(pad.d), 0.0]:
		var physics := KartPhysics.new()
		var log := _events(physics)
		var k := _kart(track, track.wrap(float(pad.s0) - 30.0), lane)
		k.heading = track.yaw_at(k.s)
		k.speed = 20.0
		k.v_bike = 20.0 / KartPhysics.SPEED_SCALE
		var inp := _in()
		var on_pad_speed := 0.0
		for i in roundi(2.0 / DT):
			physics.step(k, inp, track, DT)
			if k.on_pad:
				on_pad_speed = k.speed
		if lane == 0.0:
			assert_array(log.boost).is_empty()
		else:
			assert_array(log.boost).is_equal([[0, "pad", 0]])
			assert_float(on_pad_speed).is_greater(20.0)


func _countdown_race(cadence_at: Callable) -> Array:
	var race := KartRaceLogic.new()
	var racers := []
	for i in 2:
		racers.append({"racer_id": "r%d" % i})
	race.setup(KartTrackModel.new(Fixtures.meadow()), racers, 3)
	var log := {"boost": []}
	race.events.boost_started.connect(func(id: int, kind: String, tier: int): log.boost.append([id, kind, tier]))
	race.start_countdown(3.0)
	var inputs := [_in(), _in()]
	inputs[1].cadence = 0.0
	inputs[1].power_w = 0.0
	while race.phase == KartRaceLogic.Phase.COUNTDOWN:
		inputs[0].cadence = cadence_at.call(race.countdown)
		race.step(DT, inputs)
	inputs[0].cadence = 85.0
	race.step(DT, inputs)
	return [race, log]


func test_a_rocket_start_needs_cadence_70_in_the_2_window() -> void:
	# Pedalling hard through "2".
	var r := _countdown_race(func(left: float): return 80.0 if left <= 2.0 and left > 1.0 else 0.0)
	assert_array(r[1].boost).is_equal([[0, "start", 1]])
	var k: KartState = r[0].karts[0]
	assert_float(k.boost_time).is_greater(1.0)
	assert_float(k.speed).is_greater(5.0)
	# The idle kart gets nothing.
	assert_float((r[0].karts[1] as KartState).boost_time).is_equal(0.0)
	# Just under 70, or only on "3" or "1": nothing.
	for f in [func(left: float): return 68.0,
			func(left: float): return 90.0 if left > 2.0 else 0.0,
			func(left: float): return 90.0 if left <= 1.0 else 0.0]:
		var none := _countdown_race(f)
		assert_array(none[1].boost).is_empty()


# --- Drafting, climbs ---

func _pair(gap: float, lateral: float, same_way := true) -> KartState:
	var a := KartState.new()
	a.id = 0
	a.heading = 0.0  # facing -Z
	a.speed = 20.0
	var b := KartState.new()
	b.id = 1
	b.heading = 0.0 if same_way else PI
	b.speed = 20.0
	b.pos = Vector3(lateral, 0.0, -gap)
	KartPhysics.update_drafts([a, b])
	if gap > 0.0:
		assert_float(b.draft).is_equal(0.0)  # the leader never drafts the kart behind
	return a


func test_draft_fires_only_inside_its_geometry() -> void:
	assert_float(_pair(4.0, 0.0).draft).is_equal(1.0)
	assert_float(_pair(1.6, 1.4).draft).is_greater(0.5)
	assert_float(_pair(7.9, 0.0).draft).is_greater(0.0)
	for outside in [[1.2, 0.0], [8.3, 0.0], [4.0, 1.7], [4.0, -1.7], [-4.0, 0.0]]:
		assert_float(_pair(outside[0], outside[1]).draft).override_failure_message("drafted at %s" % [outside]).is_equal(0.0)
	assert_float(_pair(4.0, 0.0, false).draft).is_equal(0.0)


func test_drafting_in_a_race_raises_the_speed() -> void:
	var track := KartTrackModel.new(Fixtures.oval(800.0))
	var physics := KartPhysics.new()
	var lead := _kart(track, track.length - 300.0, 0.0, 1)
	var tail := _kart(track, track.length - 304.0, 0.0, 0)
	var alone := _kart(track, track.length - 304.0, 3.5, 2)
	for k in [lead, tail, alone]:
		k.speed = 20.0
		k.v_bike = 20.0 / KartPhysics.SPEED_SCALE
	for i in roundi(3.0 / DT):
		KartPhysics.update_drafts([lead, tail, alone])
		for k in [lead, tail, alone]:
			physics.step(k, _in(), track, DT)
		tail.pos = lead.pos - lead.forward() * 4.0  # hold the gap
	assert_float(tail.draft).is_equal(1.0)
	assert_float(tail.v_bike).is_greater(alone.v_bike + 0.1)


func test_standing_on_a_climb_cuts_drag_by_20_percent() -> void:
	var track := KartTrackModel.new(Fixtures.meadow())
	var climb: Dictionary = {}
	for z in track.zones:
		if str(z.type) == "climb":
			climb = z
	var mid := track.wrap(float(climb.s0) + 40.0)
	var results := {}
	for standing in [false, true]:
		var physics := KartPhysics.new()
		var k := _kart(track, mid)
		k.v_bike = 6.0
		k.speed = 6.0 * KartPhysics.SPEED_SCALE
		var inp := _in()
		inp.standing = standing
		physics.step(k, inp, track, DT)
		results[standing] = k.v_bike
		assert_bool(k.climbing).is_true()
		assert_bool(k.standing_bonus).is_equal(standing)
	var resist := KartPhysics.bike_resistance(6.0, track.grade(mid) * KartPhysics.GRADE_EFFECT)
	var expected := 0.2 * resist / KartPhysics.INERTIA_KG * DT
	assert_float(float(results[true]) - float(results[false])).is_equal_approx(expected, expected * 0.1)
	# Off the climb, standing changes nothing.
	var flat := {}
	for standing in [false, true]:
		var physics := KartPhysics.new()
		var k := _kart(track, 100.0)
		k.v_bike = 6.0
		var inp := _in()
		inp.standing = standing
		physics.step(k, inp, track, DT)
		flat[standing] = k.v_bike
		assert_bool(k.climbing).is_false()
	assert_float(float(flat[true])).is_equal(float(flat[false]))


# --- Spin-outs, contacts ---

func test_a_spin_out_cancels_the_drift_and_the_boost() -> void:
	var physics := KartPhysics.new()
	var log := _events(physics)
	var setup := _circling(physics)
	var track: KartTrackModel = setup[0]
	var k: KartState = setup[1]
	_run(physics, k, _in(150.0, -0.7), track, 2.5)
	physics.apply_boost(k, 2.0)
	assert_int(k.drift_tier).is_equal(2)
	assert_bool(physics.apply_spinout(k)).is_true()
	assert_int(k.drift_dir).is_equal(0)
	assert_int(k.drift_tier).is_equal(0)
	assert_float(k.boost_time).is_equal(0.0)
	_run(physics, k, _in(150.0, -0.1), track, 0.5)
	assert_array(log.boost).is_empty()


func test_a_rear_end_contact_trades_speed() -> void:
	var a := KartState.new()
	a.id = 0
	a.speed = 25.0
	a.pos = Vector3(0, 0, 0)
	var b := KartState.new()
	b.id = 1
	b.speed = 15.0
	b.pos = Vector3(0, 0, -1.5)  # just ahead of a, both facing -Z
	var hits := KartPhysics.resolve_contacts([a, b])
	assert_int(hits.size()).is_equal(1)
	assert_float(a.speed).is_less(25.0)
	assert_float(b.speed).is_greater(15.0)
	assert_float(a.speed + b.speed).is_equal_approx(40.0, 0.01)  # equal weights: momentum kept
	assert_float(float(hits[0][2])).is_greater(0.3)


func test_a_side_contact_nudges_the_heading_apart() -> void:
	var a := KartState.new()
	a.id = 0
	a.speed = 20.0
	a.heading = -0.2  # angled right, into b
	a.pos = Vector3(0, 0, 0)
	var b := KartState.new()
	b.id = 1
	b.speed = 20.0
	b.pos = Vector3(1.5, 0, 0)
	KartPhysics.resolve_contacts([a, b])
	assert_float(a.heading).is_greater(-0.2)


# --- Tuning: the assist ---

func _lap(assist: float, lean: Callable) -> Dictionary:
	var track := KartTrackModel.new(Fixtures.meadow())
	var physics := KartPhysics.new()
	physics.assist = assist
	physics.events = KartRaceEvents.new()
	var out := {"walls": 0, "max_out": -99.0, "drifts": 0, "done": false}
	physics.events.wall_bump.connect(func(_id: int, _s: float): out.walls += 1)
	physics.events.drift_started.connect(func(_id: int, _d: int): out.drifts += 1)
	var k := _kart(track, 1.0)
	var inp := _in()
	var travelled := 0.0
	var t := 0.0
	while t < 150.0 and travelled < track.length:
		inp.lean = lean.call(t)
		var prev := k.s
		physics.step(k, inp, track, DT)
		travelled += track.delta(prev, k.s)
		t += DT
		out.max_out = maxf(out.max_out, absf(k.d) - track.half_width(k.s))
		if k.surface == KartTrackModel.Surface.WALL or absf(k.d) > track.half_width(k.s) + track.verge - 0.05:
			out.walls += 1
	out.done = travelled >= track.length
	return out


func test_with_assist_high_lean_0_laps_meadow_ring_without_touching_a_wall() -> void:
	var r := _lap(1.0, func(_t: float): return 0.0)
	assert_bool(r.done).is_true()
	assert_int(r.walls).is_equal(0)
	assert_float(r.max_out).is_less(0.0)  # on the road all the way


func test_with_assist_off_lean_0_hits_the_wall() -> void:
	var r := _lap(0.0, func(_t: float): return 0.0)
	assert_int(r.walls).is_greater(0)


func test_with_assist_high_a_rider_who_barely_leans_stays_on_the_road() -> void:
	# A slight constant lean one way, then the other, with tracker noise on top.
	for bias in [0.2, -0.2]:
		var r := _lap(1.0, func(t: float): return bias + 0.1 * sin(t * 7.3) + 0.05 * sin(t * 23.0))
		assert_bool(r.done).is_true()
		assert_int(r.walls).is_equal(0)
		assert_float(r.max_out).override_failure_message("bias %.1f: %.2f m past the edge" % [bias, r.max_out]) \
			.is_less(KartTrackModel.KERB_WIDTH)
		assert_int(r.drifts).is_equal(0)


func test_with_assist_low_a_rough_lean_still_gets_round() -> void:
	var track := KartTrackModel.new(Fixtures.meadow())
	var r := _lap(0.5, func(t: float): return 0.0)
	assert_bool(r.done).is_true()
	assert_int(r.walls).is_equal(0)


# --- The bots' drift helpers ---

func test_wants_drift_points_into_a_tight_corner_only() -> void:
	var physics := KartPhysics.new()
	var circle := KartTrackModel.new(Fixtures.circle(30.0, 24, 6.0))
	var k := _kart(circle, 10.0)
	k.speed = 20.0
	assert_int(physics.wants_drift(k, circle)).is_equal(-1)  # an anticlockwise circle turns left
	var oval := KartTrackModel.new(Fixtures.oval(800.0))
	var s := _kart(oval, oval.length - 300.0)
	s.speed = 20.0
	assert_int(physics.wants_drift(s, oval)).is_equal(0)
	k.speed = 5.0
	assert_int(physics.wants_drift(k, circle)).is_equal(0)


func test_lean_for_drift_inverts_the_drift_turn() -> void:
	var physics := KartPhysics.new()
	var circle := KartTrackModel.new(Fixtures.circle(40.0, 24, 6.0))
	var k := _kart(circle, 10.0)
	k.speed = 20.0
	k.drift_dir = -1
	for c in [0.02, 0.035, 0.05]:
		var lean := physics.lean_for_drift(k, circle, c)
		assert_float(lean).is_less(-KartPhysics.RELEASE_LEAN)
		assert_float(physics.drift_curvature(k, circle, lean)).is_equal_approx(c, 0.002)
