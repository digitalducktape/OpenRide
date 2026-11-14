class_name KartPhysics
extends RefCounted
## Kart Race's arcade physics (#43, DESIGN.md "Physics"), stepped at a fixed 60 Hz in track space.
## Every kart, the rider's and the bots', goes through the same model, so the race is honest:
##
## - **Drive power** (rider feedback 2026-10-19: "100 rpm barely moved the kart"; the bike read
##   16-20 W at 100 rpm and 0-8% resistance): the bike is driven by the measured watts plus a
##   cadence term, `drive_power = watts + spin_watts(cadence)`. Spinning alone gets a lively
##   cruise (SPIN_W at SPIN_FULL_RPM), and resistance, through the watts, adds speed on top. Both
##   rise with cadence and with resistance; no pedalling is 0 W, so the kart coasts to a stop.
##   The bots feed the same model (their watts and cadence), and the bike's inertia smooths the
##   sensors' jitter.
## - **A virtual bike** turns the drive power into speed: P/max(v, 2) − (rolling + climbing + air) = m·a,
##   with the issue's numbers (85 kg, Crr 0.005, CdA 0.32 m², ρ 1.2). The steady speed matches
##   the power balance exactly; only the inertia is lighter than a real bike's (INERTIA_KG), so
##   the kart answers the pedals in seconds rather than half a minute. With no pedalling a gentle
##   coast brake stops it in about 15 s, and it never rolls backwards. On a climb the climbing
##   force is capped at what the watts push at CLIMB_CRAWL, so a weak rider crawls, never stalls.
## - **The kart** runs at the bike's speed × SPEED_SCALE, times its surface and boost multipliers,
##   approaching that target at KART_ACCEL / KART_DECEL (so bumps and caps ease in and out).
## - **Steering**: the lean, with a dead zone and a curve, sets a yaw rate. The assist (the
##   rider's option) adds the road's curvature and a pull back parallel to the road, so a rider
##   who leans roughly right still follows the road, and a held lean moves the kart across it.
## - **Surfaces**: kerbs are as fast as the road; off-road caps the speed at 55% (a boost halves
##   the penalty) and adds rolling drag; the wall bounces the kart back in and costs speed.
##
## - **Drift** (`_update_drift`): a hard lean (|lean| >= DRIFT_LEAN) held for DRIFT_HOLD at 40% of
##   `top_speed` hops the kart into a slide. Leaning further in tightens the arc, easing toward
##   the centre widens it (the assist bends the arc toward the road's). The charge earns spark
##   tiers at TIER_SEC in a corner (× KNOB_RATE while the resistance knob is up; a quarter of the
##   rate on a straight, so snaking doesn't pay), and easing below
##   RELEASE_LEAN for RELEASE_HOLD releases a mini-turbo (TURBO_SEC by tier). Timers use the raw
##   lean, so tracker jitter (a sign flip resets the hold) and a lean easing to 0 after face loss
##   (`KartInput.tracking` false) never start one.
## - **Boosts** (mini-turbo, pad, rocket start, the turbo item through `apply_boost`) multiply the
##   target speed, push at once, accelerate hard and don't bleed speed until they run out.
## - **Pads** and **climbs** come from the track's zones; standing on a climb cuts the drag 20%.
## - **The rocket start** (`countdown_step`, `launch`): cadence >= 70 for ROCKET_HOLD in the
##   countdown's "2" window.
## - **Drafting** (`update_drafts`, once a tick for the whole field) cuts CdA by 30% within
##   1.5-8 m behind another kart and under 1.6 m off its line.
## Logic only: no nodes. Deterministic: the same inputs give the same states.

const SPEED_SCALE := 2.4

# The virtual bike (issue #43).
const MASS_KG := 85.0
const G := 9.81
const C_RR := 0.005
const CDA := 0.32
const RHO := 1.2
## Drafting cuts CdA by up to this share (CdA × 0.7 in a full draft).
const DRAFT_CDA_CUT := 0.3
## Below this bike speed the pedal force stops growing (P / v would be infinite at rest).
const MIN_FORCE_SPEED := 2.0
## The inertia the pedals push against. A real 85 kg rider takes ~25 s to reach a steady speed;
## this makes it ~10 s. Weight still counts in full on hills (MASS_KG).
const INERTIA_KG := 20.0
## With no pedalling, a gentle brake (fading out by COAST_BRAKE_FADE_W) stops the kart in ~15 s.
const COAST_BRAKE_N := 3.0
const COAST_BRAKE_FADE_W := 30.0
## Climbs: the climbing force is capped at what the watts push at this bike speed (m/s; a kart
## crawl of about 6 m/s), so no pedalling rider stalls on a climb (a 60 W rider on 7%).
const CLIMB_CRAWL := 2.5
## The share of the road's grade the bike feels (a kart track's hills at full grade would crawl
## up at 20 km/h and fly down at 120).
const GRADE_EFFECT := 0.5

# The kart.
const KART_ACCEL := 9.0  ## m/s², toward a higher target speed
const KART_DECEL := 7.0  ## m/s², toward a lower one
const OFFROAD_CAP := 0.55
const OFFROAD_CRR := 4.0  ## rolling resistance × this off-road
const BOOST_MULT := 1.35
const BOOST_PUSH := 3.0  ## m/s added at once when a boost starts
const SPIN_SEC := 1.0
const SPIN_SPEED := 0.4  ## a spin-out cuts the speed to this share
const KART_RADIUS := 0.95  ## for kart-kart contacts

## Boosts accelerate this hard toward their target, and bleed at most this much above it.
const BOOST_ACCEL := 24.0
const BOOST_HOLD_DECEL := 1.0
const PAD_SEC := 1.0
const PAD_PUSH := 4.0
const PAD_GRACE := 0.6  ## metres beyond a pad's half-width that still count (the kart's half-width)
const STAND_DRAG_CUT := 0.2  ## standing on a climb

# Drive power: the cadence term, 0 below SPIN_FROM_RPM, rising linearly to SPIN_W at
# SPIN_FULL_RPM, and on to SPIN_MAX_SHARE × SPIN_W (115 rpm) for the sprinters.
const SPIN_W := 80.0
const SPIN_FROM_RPM := 30.0
const SPIN_FULL_RPM := 100.0
const SPIN_MAX_SHARE := 1.15
## The cadence the reference cruise (`reference_speed`) assumes, rpm.
const REF_CADENCE := 85.0
## The reference cruise's share of FTP (the drift thresholds and the GP's lap estimate).
const REF_FTP_SHARE := 0.6

# The rocket start: cadence at least ROCKET_CADENCE for ROCKET_HOLD while "2" shows.
const ROCKET_CADENCE := 70.0
const ROCKET_WINDOW := Vector2(1.0, 2.0)  ## countdown seconds left: (after, up to and including]
const ROCKET_HOLD := 0.3
const ROCKET_SEC := 1.3
const ROCKET_PUSH := 6.0
const ROCKET_BIKE_SPEED := 4.5  ## the bike's speed at a rocket launch (m/s)

# Drafting.
const DRAFT_MIN := 1.5
const DRAFT_MAX := 8.0
const DRAFT_FADE := 6.0  ## full strength up to here, fading to 0 at DRAFT_MAX
const DRAFT_LATERAL := 1.6

# The drift.
const DRIFT_LEAN := 0.65  ## |lean| to start one ...
const DRIFT_HOLD := 0.12  ## ... held this long (seconds) ...
const DRIFT_MIN_SHARE := 0.4  ## ... at this share of top_speed
const DRIFT_END_SHARE := 0.3  ## the drift ends (releasing its boost) below this share
const RELEASE_LEAN := 0.3  ## the lean toward the drift below which it releases ...
const RELEASE_HOLD := 0.15  ## ... after this long
const DRIFT_COOLDOWN := 0.2  ## before another drift may start
const DRIFT_WIDE_LEAN := 0.35  ## the in-lean that drifts widest (between it and RELEASE_LEAN: widest)
const DRIFT_K_WIDE := 1.0 / 60.0  ## the drift arc's curvature (1/m) at its widest ...
const DRIFT_K_TIGHT := 1.0 / 13.0  ## ... and tightest
const DRIFT_ASSIST := 0.85  ## the share of the road's curvature the assist bends the arc toward
const DRIFT_MAX_YAW := 2.3  ## rad/s
const DRIFT_SPEED := 0.97  ## the target speed share while drifting
const TIER_SEC := [0.9, 2.0, 3.4]  ## charge for spark tiers 1-3
const TURBO_SEC := [0.5, 0.9, 1.4]  ## the mini-turbo by tier
const TURBO_PUSH := [2.5, 3.5, 5.0]
const KNOB_RATE := 1.6  ## charge rate with the knob up
## The charge runs at full rate where the road curves toward the drift at least this much (1/m),
## and at STRAIGHT_CHARGE on a straight or against the bend (snaking for boosts doesn't pay).
const DRIFT_CHARGE_K := 0.008
const STRAIGHT_CHARGE := 0.25
const KNOB_RISE := 5.0  ## a resistance rise since the drift began that counts as the knob
const HOP_SEC := 0.28  ## the hop at the drift's start
const HOP_HEIGHT := 0.32
const SLIDE_WIDE := 0.38  ## the body's slide angle (radians) at the widest arc ...
const SLIDE_TIGHT := 0.72  ## ... and the tightest
const SLIDE_RATE := 9.0  ## 1/s, toward the slide angle
## Bots: a corner at least this tight (1/m) over the next stretch is worth a drift.
const DRIFT_WORTH_K := 1.0 / 70.0

# Kart-kart contacts.
const CONTACT_BOUNCE := 0.3  ## restitution along the contact normal
const CONTACT_TURN := 0.6  ## the share of the velocity's new direction the heading takes
const CONTACT_MAX_TURN := 0.15  ## radians per contact
const CONTACT_BUMP_SPEED := 15.0  ## m/s of closing speed for a full-strength bump

# Steering.
## Since #71 lean_x arrives already shaped by the tracker (dead zone and expo), so these stack
## on it: at Normal sensitivity half a head lean steers ~0.05 of full (0.10 before), and a drift
## starts at ~86% of full-lock head lean (77%). Kept as they were because the bots, the bot field
## order and the star thresholds are tuned on them (a 0 / 1.0 curve and DRIFT_LEAN 0.5-0.6 were
## tried: bot races reorder and kart_scoring_test's strong ride falls below its bound). Ride it.
const DEAD_ZONE := 0.06
const STEER_CURVE := 1.4  ## lean past the dead zone, to this power
const STEER_RATE := 1.4  ## rad/s at full lean
const MIN_TURN_RADIUS := 9.0  ## so slow karts can't spin on the spot
## The assist's pull back parallel to the road, 1/s.
const ALIGN_GAIN := 2.0
## Below this speed the assist's pull fades out (no turning on the spot).
const ALIGN_FULL_SPEED := 5.0
## The lean's response lag, 1/s: a little weight, and tracker jitter is filtered.
const STEER_RESPONSE := 12.0
## The assist's edge guard: from EDGE_MARGIN inside the road's edge, over EDGE_BAND metres, it
## turns the kart back parallel and EDGE_ANGLE inward (EDGE_GAIN, 1/s).
const EDGE_MARGIN := 1.0
const EDGE_BAND := 1.5
const EDGE_ANGLE := 0.12
const EDGE_GAIN := 3.5

# Walls.
const WALL_SPEED_LOSS := 0.6  ## × the sine of the impact angle
const WALL_BOUNCE := 0.3  ## the share of the impact angle kept, mirrored away from the wall
const WALL_BUMP_SPEED := 15.0  ## m/s across the wall for a full-strength bump

## 0 off, 0.5 low, 1 high: the share of the assist (curvature feed-forward and alignment).
var assist := 1.0
## Drift charges faster while resistance is at least this.
var drift_resistance := 40.0
## The kart speed (m/s) the drift thresholds are shares of: about a kart's cruise at the rider's
## race power (KartRace sets it to `reference_speed(ftp)`; about 21 at 150 W FTP).
var top_speed := 20.0
## When set (KartRaceLogic does), the physics emits wall bumps (and, in Phase 2, drift and boost
## events) into it.
var events: KartRaceEvents = null

## Scratch for update_drafts (each kart's forward x and z), reused every tick.
static var _fx_scratch := PackedFloat64Array()
static var _fz_scratch := PackedFloat64Array()


## The cadence term of the drive power, watts: 0 up to SPIN_FROM_RPM, SPIN_W at SPIN_FULL_RPM,
## capped at SPIN_MAX_SHARE × SPIN_W. Monotonic.
static func spin_watts(cadence: float) -> float:
	var x := (cadence - SPIN_FROM_RPM) / (SPIN_FULL_RPM - SPIN_FROM_RPM)
	return SPIN_W * clampf(x, 0.0, SPIN_MAX_SHARE)


## What drives the virtual bike, watts: the measured watts plus the cadence term. 0 when not
## pedalling (no watts, no cadence).
static func drive_power(power_w: float, cadence: float) -> float:
	return maxf(power_w, 0.0) + spin_watts(cadence)


## The kart speed (m/s) of the reference cruise on the flat: REF_FTP_SHARE of `ftp_w` at
## REF_CADENCE. The drift thresholds (`top_speed`) and the GP's lap estimate use it.
static func reference_speed(ftp_w: float) -> float:
	return steady_bike_speed(drive_power(REF_FTP_SHARE * maxf(ftp_w, 1.0), REF_CADENCE), 0.0) * SPEED_SCALE


## The bike speed (m/s) that `power_w` holds on `grade` (dy/ds) in a `draft` (0..1): the root
## of P = v·(Crr·m·g·cosθ + m·g·sinθ + ½·ρ·CdA·v²).
static func steady_bike_speed(power_w: float, grade: float, draft := 0.0) -> float:
	var lo := 0.0
	var hi := 60.0
	if hi * bike_resistance(hi, grade, draft) - power_w < 0.0:
		return hi
	for i in 60:
		var mid := (lo + hi) * 0.5
		if mid * bike_resistance(mid, grade, draft) - power_w < 0.0:
			lo = mid
		else:
			hi = mid
	return lo


## The forces against the bike at speed v, newtons: rolling (× crr_mult), climbing and air.
static func bike_resistance(v: float, grade: float, draft := 0.0, crr_mult := 1.0) -> float:
	var theta := atan(grade)
	return C_RR * crr_mult * MASS_KG * G * cos(theta) + MASS_KG * G * sin(theta) \
		+ 0.5 * RHO * CDA * (1.0 - DRAFT_CDA_CUT * clampf(draft, 0.0, 1.0)) * v * v


## Lean (-1..1) through the dead zone and the response curve: the steering share, -1..1.
static func shape_lean(lean: float) -> float:
	var a := absf(lean)
	if a <= DEAD_ZONE:
		return 0.0
	return signf(lean) * pow(minf(1.0, (a - DEAD_ZONE) / (1.0 - DEAD_ZONE)), STEER_CURVE)


## The lean that `shape_lean` turns into `steer` (for bots that know the yaw rate they want).
static func lean_for_steer(steer: float) -> float:
	var a := absf(steer)
	if a <= 0.0:
		return 0.0
	return signf(steer) * (DEAD_ZONE + (1.0 - DEAD_ZONE) * pow(minf(1.0, a), 1.0 / STEER_CURVE))


## The yaw rate (rad/s) a full lean gives at `speed`.
static func max_yaw_rate(speed: float) -> float:
	return minf(STEER_RATE, speed / MIN_TURN_RADIUS)


## The lean (-1..1) that, on top of the assist, turns the kart at `yaw_rate` (+ = left).
func lean_for_yaw_rate(k: KartState, track: KartTrackModel, yaw_rate: float) -> float:
	var full := max_yaw_rate(k.speed)
	if full <= 0.0:
		return 0.0
	return lean_for_steer(clampf(-(yaw_rate - assist_yaw_rate(k, track)) / full, -1.0, 1.0))


## The assist's share of the yaw rate (rad/s, + = left): the road's curvature and a pull back
## parallel to it.
func assist_yaw_rate(k: KartState, track: KartTrackModel) -> float:
	return _assist_yaw(k, track, assist)


## The assist at strength `a`: the road's curvature, the pull parallel and the edge guard.
func _assist_yaw(k: KartState, track: KartTrackModel, a: float) -> float:
	if a <= 0.0:
		return 0.0
	var psi := angle_difference(track.yaw_at(k.s), k.heading)
	var pull := ALIGN_GAIN * minf(1.0, k.speed / ALIGN_FULL_SPEED)
	return a * (track.curvature(k.s) * k.speed - pull * psi + _edge_guard(k, track, psi))


## Near the edge: turn back parallel to the road and a little inward (rad/s, + = left).
func _edge_guard(k: KartState, track: KartTrackModel, psi: float) -> float:
	var over := absf(k.d) - (track.half_width(k.s) - EDGE_MARGIN)
	if over <= 0.0:
		return 0.0
	var band := minf(2.0, over / EDGE_BAND)
	var want := signf(k.d) * EDGE_ANGLE * minf(1.0, band)
	return EDGE_GAIN * band * (want - psi) * minf(1.0, k.speed / ALIGN_FULL_SPEED)


## The assist's strength this tick: the rider's, or full while the tracker has lost the face.
func _assist_now(inp: KartInput) -> float:
	return assist if inp.tracking else maxf(assist, 1.0)


func step(k: KartState, inp: KartInput, track: KartTrackModel, dt: float) -> void:
	var spinning := k.spin_time > 0.0
	k.spin_time = maxf(0.0, k.spin_time - dt)
	k.boost_time = maxf(0.0, k.boost_time - dt)
	k.shield_time = maxf(0.0, k.shield_time - dt)
	k.drift_cool = maxf(0.0, k.drift_cool - dt)
	var offroad := k.surface == KartTrackModel.Surface.OFFROAD
	_zones(k, inp, track)

	# The virtual bike: pedal force against rolling, climbing and air (standing cuts it on climbs).
	var grade := track.grade(k.s) * GRADE_EFFECT
	var crr := OFFROAD_CRR if offroad else 1.0
	var resist := bike_resistance(k.v_bike, grade, k.draft, crr)
	var drive := drive_power(inp.power_w, inp.cadence)
	if grade > 0.0 and drive > 0.0:
		# The climb's floor: the climbing force never exceeds what the rider's watts can push at
		# CLIMB_CRAWL, so a weak rider crawls up a steep climb instead of stalling. Riders who
		# can climb at their own pace never feel it.
		var flat := bike_resistance(k.v_bike, 0.0, k.draft, crr)
		var cap := maxf(0.0, drive / CLIMB_CRAWL - bike_resistance(CLIMB_CRAWL, 0.0, k.draft, crr))
		resist = flat + minf(resist - flat, cap)
	if k.standing_bonus:
		resist *= 1.0 - STAND_DRAG_CUT
	var brake := COAST_BRAKE_N * clampf(1.0 - drive / COAST_BRAKE_FADE_W, 0.0, 1.0)
	var force := drive / maxf(k.v_bike, MIN_FORCE_SPEED) - resist - brake
	k.v_bike = maxf(0.0, k.v_bike + force / INERTIA_KG * dt)

	# The kart's speed eases toward the bike's, scaled by surface, boost and drift.
	var boosting := k.boost_time > 0.0
	var target := k.v_bike * SPEED_SCALE
	if offroad:
		target *= OFFROAD_CAP if not boosting else 1.0 - (1.0 - OFFROAD_CAP) * 0.5
	if boosting:
		target *= BOOST_MULT
	if k.drift_dir != 0:
		target *= DRIFT_SPEED
	if spinning:
		target = minf(target, k.speed)
	var rate := KART_ACCEL if target > k.speed else KART_DECEL
	if boosting:
		rate = BOOST_ACCEL if target > k.speed else BOOST_HOLD_DECEL
	k.speed = move_toward(k.speed, target, rate * dt)

	# Steering: the lean (after its response lag) plus the assist, or the drift; none while
	# spinning out.
	k.lean_smooth = lerpf(k.lean_smooth, inp.lean, 1.0 - exp(-STEER_RESPONSE * dt))
	var yaw_rate := 0.0
	if spinning:
		k.drift_hold = 0.0
	else:
		yaw_rate = -shape_lean(k.lean_smooth) * max_yaw_rate(k.speed) + _assist_yaw(k, track, _assist_now(inp))
		yaw_rate += _update_drift(k, inp, track, dt)
	k.steer = clampf(-yaw_rate / STEER_RATE, -1.0, 1.0)
	k.heading = wrapf(k.heading + yaw_rate * dt, -PI, PI)
	_pose_drift(k, dt)

	# Move, then find where on the track that is.
	var p := track.project(k.pos + k.forward() * k.speed * dt, k.s)
	var edge := track.half_width(p.s)
	var reach := edge + track.verge
	if absf(p.d) > reach:
		p = _hit_wall(k, track, p, reach)
		edge = track.half_width(p.s)
	k.pos = p.position
	k.s = p.s
	k.d = p.d
	k.surface = KartTrackModel.surface_beside(edge, track.verge, p.d)
	k.normal = p.normal


## The countdown (inputs don't move the karts yet): counts the rocket start's cadence while "2"
## shows. `countdown` is the seconds left before this tick.
func countdown_step(k: KartState, inp: KartInput, countdown: float, dt: float) -> void:
	if countdown > ROCKET_WINDOW.x and countdown <= ROCKET_WINDOW.y and inp.cadence >= ROCKET_CADENCE:
		k.rocket_hold += dt


## GO: a kart that earned the rocket start launches with a boost.
func launch(k: KartState) -> void:
	if k.rocket_hold >= ROCKET_HOLD - 0.0001:
		k.v_bike = maxf(k.v_bike, ROCKET_BIKE_SPEED)
		k.speed = maxf(k.speed, k.v_bike * SPEED_SCALE * 0.5)
		apply_boost(k, ROCKET_SEC, ROCKET_PUSH, "start")
		k.boost_tier = 1
		if events:
			events.boost_started.emit(k.id, "start", 1)
	k.rocket_hold = 0.0


## Starts (or extends) a boost: BOOST_MULT on the target speed for `seconds`, and a push. It
## emits nothing: the caller emits `boost_started` with its kind (the turbo item: the items).
func apply_boost(k: KartState, seconds: float, push := BOOST_PUSH, kind := "item") -> void:
	k.boost_time = maxf(k.boost_time, seconds)
	k.speed += push
	k.boost_kind = kind
	k.boost_tier = 0


## A pull (the Draft Magnet) for one tick: the kart's speed rises toward `want_speed` at
## `accel` (m/s², never slowing it), and it slides across toward `to_d` at `lateral` m/s,
## staying on the road; it counts as a full draft this tick (for the views). No pull while
## spinning out. Items call it after the race's step, once a tick.
func apply_pull(k: KartState, track: KartTrackModel, want_speed: float, accel: float, to_d: float,
		lateral: float, dt: float) -> void:
	if k.spin_time > 0.0:
		return
	k.draft = 1.0
	if k.speed < want_speed:
		k.speed = minf(want_speed, k.speed + accel * dt)
	var limit := track.half_width(k.s)
	if absf(k.d) > limit:
		return  # off the road: no sideways tug (the edge guard brings it back)
	var d := clampf(move_toward(k.d, to_d, lateral * dt), -limit, limit)
	if d != k.d:
		var p := track.project(track.position_at(k.s, d), k.s)
		k.pos = p.position
		k.d = p.d


## Spins the kart out (SPIN_SEC without control, the speed cut to SPIN_SPEED). A shield absorbs
## it instead and is used up: then it returns false.
func apply_spinout(k: KartState) -> bool:
	if k.shield_time > 0.0:
		k.shield_time = 0.0
		return false
	_end_drift(k, false)
	k.boost_time = 0.0
	k.spin_time = SPIN_SEC
	k.speed *= SPIN_SPEED
	return true


## Pushes overlapping karts apart (circles of KART_RADIUS, in the horizontal plane), the lighter
## one further, and trades their velocities along the contact (a rear-ender slows the chaser and
## shoves the leader; a side swipe nudges both headings apart). Returns [[a_id, b_id, strength
## 0..1], ...] for the pairs that touched.
static func resolve_contacts(karts: Array) -> Array:
	var hits := []
	var reach := 2.0 * KART_RADIUS
	var touch := reach - 0.001  # karts pushed apart last time sit at `reach`, give or take rounding
	for i in karts.size():
		var a: KartState = karts[i]
		for j in range(i + 1, karts.size()):
			var b: KartState = karts[j]
			var dx := b.pos.x - a.pos.x
			var dz := b.pos.z - a.pos.z
			var dist2 := dx * dx + dz * dz
			if dist2 >= touch * touch or absf(b.pos.y - a.pos.y) > 2.0:
				continue
			var dist := sqrt(dist2)
			var n := Vector3(dx / dist, 0.0, dz / dist) if dist > 0.0001 else Vector3.RIGHT
			var overlap := reach - dist
			var total := a.weight + b.weight
			a.pos -= n * overlap * (b.weight / total)
			b.pos += n * overlap * (a.weight / total)
			var closing := _trade(a, b, n)
			hits.append([a.id, b.id, clampf(maxf(overlap / reach, closing / CONTACT_BUMP_SPEED), 0.0, 1.0)])
	return hits


## A contact's impulse along n (a → b): returns the closing speed it removed (m/s, >= 0).
static func _trade(a: KartState, b: KartState, n: Vector3) -> float:
	var fa := a.forward()
	var fb := b.forward()
	var va := fa * a.speed
	var vb := fb * b.speed
	var closing := (vb - va).dot(n)
	if closing >= 0.0:
		return 0.0
	var j := -(1.0 + CONTACT_BOUNCE) * closing / (1.0 / a.weight + 1.0 / b.weight)
	va -= n * (j / a.weight)
	vb += n * (j / b.weight)
	_take_velocity(a, va, fa)
	_take_velocity(b, vb, fb)
	return -closing


## A kart's speed and heading after a contact left it moving at `v` (it faced `f`).
static func _take_velocity(k: KartState, v: Vector3, f: Vector3) -> void:
	k.speed = maxf(0.0, v.dot(f))
	if v.length_squared() > 1.0:
		var turn := angle_difference(k.heading, atan2(-v.x, -v.z)) * CONTACT_TURN
		k.heading = wrapf(k.heading + clampf(turn, -CONTACT_MAX_TURN, CONTACT_MAX_TURN), -PI, PI)


## Every kart's draft this tick (0..1): within DRAFT_MIN..DRAFT_MAX metres behind another kart
## going the same way, under DRAFT_LATERAL metres off its line; fading over the last stretch.
static func update_drafts(karts: Array) -> void:
	var n := karts.size()
	# Each kart's heading once (not once per pair): the main thread is the tablet's limit.
	_fx_scratch.resize(n)
	_fz_scratch.resize(n)
	for i in n:
		var h: float = (karts[i] as KartState).heading
		_fx_scratch[i] = -sin(h)
		_fz_scratch[i] = -cos(h)
	for i in n:
		var a: KartState = karts[i]
		var best := 0.0
		var fx := _fx_scratch[i]
		var fz := _fz_scratch[i]
		for j in n:
			var b: KartState = karts[j]
			if j == i or b.speed < 3.0:
				continue
			var rx := b.pos.x - a.pos.x
			var rz := b.pos.z - a.pos.z
			var along := rx * fx + rz * fz
			if along < DRAFT_MIN or along > DRAFT_MAX:
				continue
			if absf(rx * -fz + rz * fx) >= DRAFT_LATERAL or absf(b.pos.y - a.pos.y) > 2.0:
				continue
			if _fx_scratch[j] * fx + _fz_scratch[j] * fz < 0.7:
				continue
			best = maxf(best, 1.0 - smoothstep(DRAFT_FADE, DRAFT_MAX, along))
		a.draft = best


## Bots: the drift direction (+1 right, -1 left) a corner just ahead is worth, or 0.
func wants_drift(k: KartState, track: KartTrackModel) -> int:
	if k.drift_dir != 0:
		return k.drift_dir
	if k.speed < DRIFT_MIN_SHARE * top_speed * 1.1:
		return 0
	var sign := 0.0
	for ahead in [6.0, 14.0, 22.0]:
		var c := track.curvature(track.wrap(k.s + ahead))
		if absf(c) < DRIFT_WORTH_K or (sign != 0.0 and signf(c) != sign):
			return 0
		sign = signf(c)
	return -int(sign)


## The drift arc's curvature (1/m, toward the drift, > 0) that `lean` gives kart k (its drift
## direction, or the lean's when it isn't drifting), with the assist's bend toward the road.
func drift_curvature(k: KartState, track: KartTrackModel, lean: float) -> float:
	var dir := k.drift_dir if k.drift_dir != 0 else int(signf(lean))
	return _drift_curv(k, track, dir, lean, assist)


## Bots: the lean that drifts k (already drifting) on an arc of `curvature` (1/m, toward the
## drift). Never eased far enough to release it.
func lean_for_drift(k: KartState, track: KartTrackModel, curvature: float) -> float:
	var dir := k.drift_dir if k.drift_dir != 0 else 1
	var base := curvature - assist * DRIFT_ASSIST * (track.curvature(k.s) * -dir - _k_mid())
	var t := clampf((base - DRIFT_K_WIDE) / (DRIFT_K_TIGHT - DRIFT_K_WIDE), 0.0, 1.0)
	return dir * lerpf(DRIFT_WIDE_LEAN, 1.0, t)


static func _k_mid() -> float:
	return (DRIFT_K_WIDE + DRIFT_K_TIGHT) * 0.5


func _drift_curv(k: KartState, track: KartTrackModel, dir: int, lean: float, a: float) -> float:
	var t := clampf((lean * dir - DRIFT_WIDE_LEAN) / (1.0 - DRIFT_WIDE_LEAN), 0.0, 1.0)
	var c := lerpf(DRIFT_K_WIDE, DRIFT_K_TIGHT, t)
	c += a * DRIFT_ASSIST * (track.curvature(k.s) * -dir - _k_mid())
	return clampf(c, DRIFT_K_WIDE * 0.5, DRIFT_K_TIGHT * 1.2)


## The drift: entry, charge, tiers, release into a mini-turbo, the knob. Returns the yaw rate
## (rad/s, + = left) to add to the lean-and-assist steering: while drifting, the difference to
## the drift's own arc (blended in over the hop). Emits drift_started / drift_tier /
## boost_started through `events`.
func _update_drift(k: KartState, inp: KartInput, track: KartTrackModel, dt: float) -> float:
	if k.drift_dir == 0:
		# Entry: a hard lean, the same way, held; any sign flip or ease restarts the clock.
		var dir := int(signf(inp.lean))
		if absf(inp.lean) >= DRIFT_LEAN and dir == k.drift_hold_dir:
			k.drift_hold += dt
		else:
			k.drift_hold = dt if absf(inp.lean) >= DRIFT_LEAN else 0.0
			k.drift_hold_dir = dir
		if not inp.tracking:
			k.drift_hold = 0.0
		if k.drift_hold >= DRIFT_HOLD - 0.0001 and k.drift_cool <= 0.0 \
				and k.speed >= DRIFT_MIN_SHARE * top_speed and k.surface != KartTrackModel.Surface.OFFROAD:
			_start_drift(k, dir, inp)
		else:
			return 0.0
	else:
		k.drift_time += dt
		# The knob: resistance up at the drift's level, or risen since it began.
		k.knob_boosting = inp.resistance >= drift_resistance or inp.resistance - k.drift_res0 >= KNOB_RISE - 0.0001
		if k.surface != KartTrackModel.Surface.OFFROAD:
			# Full rate in a corner the drift turns into; slow on straights, so snaking for
			# mini-turbos doesn't pay.
			var corner := clampf(track.curvature(k.s) * -k.drift_dir / DRIFT_CHARGE_K, STRAIGHT_CHARGE, 1.0)
			k.drift_charge += dt * corner * (KNOB_RATE if k.knob_boosting else 1.0)
		while k.drift_tier < TIER_SEC.size() and k.drift_charge >= float(TIER_SEC[k.drift_tier]) - 0.0001:
			k.drift_tier += 1
			if events:
				events.drift_tier.emit(k.id, k.drift_tier)
		# Release: eased off toward the centre (or the other way) long enough; or too slow to slide.
		if inp.lean * k.drift_dir < RELEASE_LEAN:
			k.drift_release += dt
		else:
			k.drift_release = 0.0
		if k.drift_release >= RELEASE_HOLD - 0.0001 or k.speed < DRIFT_END_SHARE * top_speed:
			_end_drift(k, true)
			return 0.0
	# The drift's arc, blended in over the hop.
	var a := _assist_now(inp)
	var c := _drift_curv(k, track, k.drift_dir, k.lean_smooth, a)
	var psi := angle_difference(track.yaw_at(k.s), k.heading)
	var drift_yaw := clampf(-k.drift_dir * c * k.speed + a * _edge_guard(k, track, psi), -DRIFT_MAX_YAW, DRIFT_MAX_YAW)
	var normal := -shape_lean(k.lean_smooth) * max_yaw_rate(k.speed) + _assist_yaw(k, track, a)
	return (drift_yaw - normal) * smoothstep(0.0, HOP_SEC, k.drift_time)


func _start_drift(k: KartState, dir: int, inp: KartInput) -> void:
	k.drift_dir = dir
	k.drift_time = 0.0
	k.drift_charge = 0.0
	k.drift_tier = 0
	k.drift_release = 0.0
	k.drift_res0 = inp.resistance
	k.knob_boosting = false
	k.drift_hold = 0.0
	if events:
		events.drift_started.emit(k.id, dir)


## Ends the drift; with `boost`, a mini-turbo by its tier.
func _end_drift(k: KartState, boost: bool) -> void:
	if k.drift_dir == 0:
		return
	var tier := k.drift_tier
	k.drift_dir = 0
	k.drift_charge = 0.0
	k.drift_tier = 0
	k.drift_release = 0.0
	k.knob_boosting = false
	k.drift_hold = 0.0
	k.drift_cool = DRIFT_COOLDOWN
	if boost and tier > 0:
		apply_boost(k, TURBO_SEC[tier - 1], TURBO_PUSH[tier - 1], "drift")
		k.boost_tier = tier
		if events:
			events.boost_started.emit(k.id, "drift", tier)


## The drift's look for the views: the hop at its start and the body's slide angle.
func _pose_drift(k: KartState, dt: float) -> void:
	var goal := 0.0
	if k.drift_dir != 0:
		k.hop = HOP_HEIGHT * sin(PI * k.drift_time / HOP_SEC) if k.drift_time < HOP_SEC else 0.0
		var t := clampf((k.lean_smooth * k.drift_dir - DRIFT_WIDE_LEAN) / (1.0 - DRIFT_WIDE_LEAN), 0.0, 1.0)
		goal = -k.drift_dir * lerpf(SLIDE_WIDE, SLIDE_TIGHT, t)
	else:
		k.hop = 0.0
	k.slide = lerpf(k.slide, goal, 1.0 - exp(-SLIDE_RATE * dt))


## Climb and pad zones under the kart (its s and d before this tick's move).
func _zones(k: KartState, inp: KartInput, track: KartTrackModel) -> void:
	var flags := track.zone_flags(k.s, k.d, PAD_GRACE)
	var climbing := (flags & KartTrackModel.ZONE_CLIMB) != 0
	var pad := (flags & KartTrackModel.ZONE_PAD) != 0
	k.climbing = climbing
	k.standing_bonus = climbing and inp.standing
	if pad and not k.on_pad:
		apply_boost(k, PAD_SEC, PAD_PUSH, "pad")
		if events:
			events.boost_started.emit(k.id, "pad", 0)
	k.on_pad = pad


## The kart went past the barrier: put it back against it, and when it was heading into it,
## bounce it off and take speed in proportion to the impact angle.
func _hit_wall(k: KartState, track: KartTrackModel, p: KartTrackPoint, reach: float) -> KartTrackPoint:
	var side := signf(p.d)
	var road_yaw := track.yaw_at(p.s)
	var psi := angle_difference(road_yaw, k.heading)
	# The share of the kart's speed going across the road toward this wall (d grows as -sin ψ).
	var into := -sin(psi) * side
	if into > 0.0:
		var strength := clampf(into * k.speed / WALL_BUMP_SPEED, 0.0, 1.0)
		k.speed *= 1.0 - WALL_SPEED_LOSS * into
		k.heading = wrapf(road_yaw - psi * WALL_BOUNCE, -PI, PI)
		if events and strength >= 0.05:
			events.wall_bump.emit(k.id, strength)
	var inside := side * (reach - 0.01)
	var back := track.project(track.position_at(p.s, inside), p.s)
	return back
