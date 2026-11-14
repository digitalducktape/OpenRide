class_name KartBotDriver
extends RefCounted
## A bot's driving (#43, spec "Opponents"). It produces the same `KartInput` the rider's pedals and
## lean do, and goes through the same `KartPhysics`, so the race is honest.
##
## - **Power:** its share of the rider's FTP, wandering ±4% slowly (simplex noise) for life. It
##   never reacts to the rider: no rubber-banding. Your watts decide the race.
## - **Line:** pure pursuit of a point ahead on the track's racing line, shifted by its own
##   `line_offset` (eased out in sharp corners), clamped inside the road's edge. The lateral
##   target moves at a capped rate, so the bot never swerves.
## - **Modes** (an enum FSM; one target lane each, highest priority first):
##   DODGE (goo or a puck in its lane ahead) → PASS (a slower kart ahead in its lane: pick a side
##   and hold it until clear) → CRUISE (its line; drawn to a pod row when it holds no item).
##   Side-by-side karts push the target lane apart in every mode.
## - **Cadence:** each persona pedals at its own cadence (CADENCES), wandering a few rpm. Only
##   some personas (`rocket`) spin up for the rocket start in the countdown; the rest are lazy
##   off the line.
## - **Drift** (a sub-state driven by the physics' own `KartState.drift_dir`): where
##   `KartPhysics.wants_drift` says a corner is worth it and the bot's drift skill rolls yes, it
##   pulses a hard lean (the physics' entry), giving up after DRIFT_ENTRY_MAX if no drift starts.
##   While the physics drifts, `lean_for_drift` gives the lean for the arc pure pursuit wants;
##   it releases (eases under the release lean) when the corner ends, it slips DRIFT_SLIP off its
##   line, or the widest arc (`drift_curvature`) is still too tight. Outside a drift the lean
##   stays under MAX_STEER_LEAN, so a drift never starts by accident.
## - **Items:** through `KartItemLogic.wants_use` with its item skill (and hazards and pods from
##   the same logic). Set `items` when the race's item logic exists.
##
## profile: {power_pct, line_offset, drift_skill, item_skill, aggression}

enum Mode { CRUISE, PASS, DODGE }

const POWER_WANDER := 0.04  ## ± share of the bot's power, slowly over time
const WANDER_HZ := 0.01  ## a wander over minutes, not seconds
const LOOKAHEAD_SEC := 0.6
const LOOKAHEAD_MIN := 6.0
const LOOKAHEAD_MAX := 18.0
const EDGE_MARGIN := 1.2  ## the bot's line keeps this far inside the road's edge
const CADENCE := 85.0  ## the default cadence (rpm) for a profile without one
const CADENCE_WANDER := 4.0  ## ± rpm, slowly
const RESISTANCE := 30.0
const LATERAL_RATE := 2.4  ## m/s: how fast the target lane moves
const DODGE_RATE := 4.5
## Line offsets fade out in corners sharper than this (1/m), so the bots take the apex.
const OFFSET_FADE_CURV := 0.025

## Overtaking: karts within this lane width ahead are in the way.
const LANE := 1.9
const PASS_GAP := [2.7, 2.1]  ## lateral clearance when passing, careful .. aggressive
const PASS_LOOK_SEC := [0.7, 1.1]  ## look this many seconds ahead (by speed), careful .. aggressive
const PASS_LOOK_MIN := 8.0
const BESIDE := 2.6  ## m along the track: karts this close are side by side
const SIDE_GAP := 2.2  ## m across the road kept from a kart alongside

## Drift entry: a pulse of this lean (over the physics' DRIFT_LEAN), given up after
## DRIFT_ENTRY_MAX seconds if the physics hasn't started a drift.
const DRIFT_ENTRY_LEAN := 0.8
const DRIFT_ENTRY_MAX := 0.35
const DRIFT_ENTRY_PSI := 0.18  ## rad: only from a kart running roughly along the road
const DRIFT_COOLDOWN := 1.5  ## s after a drift before the next
const DRIFT_HOLD_LEAN := 0.4  ## the least lean toward the drift while holding it (release is 0.3)
const DRIFT_RELEASE_LEAN := 0.1  ## the lean while letting go (under the release threshold)
const DRIFT_SLIP := 2.2  ## m inside its line before it lets go
const DRIFT_TIGHT_OFF := 0.7  ## m inside its line while even the widest arc is too tight: cash it
const DRIFT_EDGE := 1.3  ## m from the road's inside edge: let go
const DRIFT_MIN_SEC := 0.6  ## hold at least this long before an early release
const DRIFT_OUTSIDE := 1.0  ## m: the drift's line starts this far toward the outside

## Outside a drift the lean stays under the physics' drift entry (0.65), so drifts are only ever
## on purpose.
const MAX_STEER_LEAN := 0.6
const POD_LOOK := 40.0
const HAZARD_LOOK_SEC := 1.4
const ROCKET_CADENCE := 92.0  ## over the physics' 70 rpm through the "2"
const LAZY_SHARE := 0.6  ## a lazy starter's countdown cadence share (under 70 rpm)

## Seven distinct personalities (in kart order 1..7): line offset, drift, items, aggression,
## cadence (rpm) and whether it manages the rocket start.
const PERSONAS := [
	{"line_offset": -1.5, "drift_skill": 0.85, "item_skill": 0.8, "aggression": 0.7, "cadence": 92.0, "rocket": true},
	{"line_offset": 1.5, "drift_skill": 0.7, "item_skill": 0.6, "aggression": 0.9, "cadence": 96.0, "rocket": true},
	{"line_offset": -0.5, "drift_skill": 0.55, "item_skill": 0.9, "aggression": 0.4, "cadence": 82.0, "rocket": false},
	{"line_offset": 0.5, "drift_skill": 0.9, "item_skill": 0.5, "aggression": 0.6, "cadence": 88.0, "rocket": true},
	{"line_offset": -2.0, "drift_skill": 0.4, "item_skill": 0.7, "aggression": 0.3, "cadence": 74.0, "rocket": false},
	{"line_offset": 2.0, "drift_skill": 0.6, "item_skill": 0.4, "aggression": 0.8, "cadence": 90.0, "rocket": false},
	{"line_offset": 0.0, "drift_skill": 0.3, "item_skill": 0.55, "aggression": 0.5, "cadence": 78.0, "rocket": false},
]

var profile: Dictionary
var ftp_w: float
var power_pct: float
var line_offset: float
var drift_skill: float
var item_skill: float
var aggression: float
var cadence: float  ## rpm, its own (wandering ± CADENCE_WANDER)
var rocket: bool  ## spins up for the rocket start
## The race's item logic (hazards, pods, the item policy); null races without items.
var items: KartItemLogic = null
var mode := Mode.CRUISE
## Driving state, readable for tests and debugging.
var drifting := 0  ## -1 / +1 while holding a drift (lean direction), 0 otherwise
var lane := NAN  ## the current target d

var _noise := FastNoiseLite.new()
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _input := KartInput.new()
var _pass_side := 0.0
var _pass_id := -1
var _drift_t := 0.0  ## seconds in the current entry pulse or drift
var _releasing := false  ## easing off to cash the mini-turbo
var _slid := false  ## the physics started the drift this bot asked for
var _corner_decided := false
var _corner_drift := false
var _drift_cool := 0.0


func _init(bot_profile: Dictionary, rider_ftp_w: float, rng_seed: int) -> void:
	profile = bot_profile
	ftp_w = rider_ftp_w
	power_pct = float(profile.get("power_pct", 0.6))
	line_offset = float(profile.get("line_offset", 0.0))
	drift_skill = clampf(float(profile.get("drift_skill", 0.5)), 0.0, 1.0)
	item_skill = clampf(float(profile.get("item_skill", 0.5)), 0.0, 1.0)
	aggression = clampf(float(profile.get("aggression", 0.5)), 0.0, 1.0)
	_noise.seed = rng_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = WANDER_HZ
	_rng.seed = rng_seed
	cadence = float(profile.get("cadence", CADENCE))
	rocket = bool(profile.get("rocket", false))


## The profile for bot number `index` (0..6, kart id − 1) at `power_pct` of the rider's FTP.
static func profile_for(index: int, pct: float) -> Dictionary:
	var p: Dictionary = PERSONAS[posmod(index, PERSONAS.size())].duplicate()
	p["power_pct"] = pct
	return p


## The watts the bot pedals at `t` seconds into its life.
func power_at(t: float) -> float:
	return ftp_w * power_pct * (1.0 + POWER_WANDER * clampf(_noise.get_noise_1d(t) * 1.6, -1.0, 1.0))


func think(k: KartState, race: KartRaceLogic, dt: float) -> KartInput:
	_t += dt
	var track := race.track
	_input.power_w = power_at(_t)
	_input.resistance = RESISTANCE
	_input.use_item = false
	_input.standing = false
	if race.phase == KartRaceLogic.Phase.COUNTDOWN or race.phase == KartRaceLogic.Phase.GRID:
		# Some bots nail the rocket start (cadence up through the countdown), some don't.
		_input.cadence = ROCKET_CADENCE if rocket else cadence * LAZY_SHARE
		_input.lean = 0.0
		lane = k.d
		return _input
	_input.cadence = cadence + CADENCE_WANDER * clampf(_noise.get_noise_1d(_t + 977.0) * 1.6, -1.0, 1.0)
	if is_nan(lane):
		lane = k.d
	if k.spin_time > 0.0:
		_input.lean = 0.0
		drifting = 0
		_releasing = false
		lane = k.d
		return _input
	if items:
		_input.use_item = items.wants_use(k.id, item_skill)

	var ahead := clampf(k.speed * LOOKAHEAD_SEC, LOOKAHEAD_MIN, LOOKAHEAD_MAX)
	var s_ahead := track.wrap(k.s + ahead)
	var limit := maxf(0.0, track.half_width(s_ahead) - EDGE_MARGIN)
	var want := _lane_for(k, race, s_ahead)
	want = _keep_apart(k, race, want)
	var rate := DODGE_RATE if mode == Mode.DODGE else LATERAL_RATE
	lane = clampf(move_toward(lane, want, rate * dt), -limit, limit)

	# Pure pursuit toward the lane ahead.
	var target := track.position_at(s_ahead, lane)
	var to := target - k.pos
	var alpha := angle_difference(k.heading, atan2(-to.x, -to.z))  # + = the target is to the left
	var dist := maxf(1.0, Vector2(to.x, to.z).length())
	var curvature := 2.0 * sin(alpha) / dist  # the pursuit arc, 1/m, + = left
	var lean := clampf(race.physics.lean_for_yaw_rate(k, track, k.speed * curvature), -MAX_STEER_LEAN, MAX_STEER_LEAN)
	_input.lean = _drift(k, race.physics, track, lean, curvature, dt)
	return _input


## The lane (d) the bot wants at `s_ahead`: dodge, pass, a pod, or its own line.
func _lane_for(k: KartState, race: KartRaceLogic, s_ahead: float) -> float:
	var track := race.track
	var curv := absf(track.curvature(s_ahead))
	var fade := clampf(1.0 - curv / OFFSET_FADE_CURV, 0.0, 1.0)
	var own := track.racing_line(s_ahead) + line_offset * fade
	if drifting != 0:
		# Start the slide a little outside: the drift tightens it.
		own += float(drifting) * DRIFT_OUTSIDE * clampf(1.0 - _drift_t, 0.0, 1.0)
	if items:
		var dodge := items.dodge_d(k.s, lane, maxf(12.0, k.speed * HAZARD_LOOK_SEC))
		if not is_nan(dodge):
			mode = Mode.DODGE
			return dodge
	var passing := _pass_lane(k, race)
	if not is_nan(passing):
		mode = Mode.PASS
		return passing
	mode = Mode.CRUISE
	if items and k.item == "" and k.roulette_time <= 0.0 and item_skill > 0.3:
		var pod := items.pod_d(k.s, lane, POD_LOOK)
		if not is_nan(pod) and absf(pod - own) < 3.5:
			return lerpf(own, pod, item_skill)
	return own


## A slower kart ahead in the bot's lane: the lane beside it (a side chosen once, kept until the
## pass is done), or NAN when the way is clear.
func _pass_lane(k: KartState, race: KartRaceLogic) -> float:
	var track := race.track
	var look := maxf(PASS_LOOK_MIN, k.speed * lerpf(PASS_LOOK_SEC[0], PASS_LOOK_SEC[1], aggression))
	var block := -1
	var block_ds := INF
	var length := track.length
	for o: KartState in race.karts:
		if o.id == k.id:
			continue
		var ds := fposmod(o.s - k.s, length)  # track.delta, inline (hot: every kart, every think)
		if ds > length * 0.5:
			ds -= length
		if ds <= 0.5 or ds > look or ds >= block_ds:
			continue
		if absf(o.d - lane) > LANE and o.id != _pass_id:
			continue
		if o.speed > k.speed + 0.5 and o.id != _pass_id:
			continue  # pulling away: no need
		block = o.id
		block_ds = ds
	if block < 0:
		_pass_id = -1
		return NAN
	var o: KartState = race.karts[block]
	var gap := lerpf(PASS_GAP[0], PASS_GAP[1], aggression)
	var limit := maxf(0.0, track.half_width(o.s) - EDGE_MARGIN)
	if block != _pass_id:
		_pass_id = block
		# The side with room, preferring the inside of what comes next.
		var inside := -signf(track.curvature(track.wrap(o.s + 20.0)))
		var room_r := limit - (o.d + gap)
		var room_l := (o.d - gap) + limit
		if room_r < 0.0 and room_l < 0.0:
			_pass_side = 1.0 if room_r > room_l else -1.0
		elif room_r < 0.0:
			_pass_side = -1.0
		elif room_l < 0.0:
			_pass_side = 1.0
		elif absf(inside) > 0.0 and absf(track.curvature(track.wrap(o.s + 20.0))) > 0.006:
			_pass_side = inside
		else:
			_pass_side = 1.0 if lane >= o.d else -1.0
	if absf(o.d - lane) > gap + 0.4 and track.delta(k.s, o.s) < 1.0:
		return NAN
	return clampf(o.d + _pass_side * gap, -limit, limit)


## Pushes the wanted lane away from karts alongside.
func _keep_apart(k: KartState, race: KartRaceLogic, want: float) -> float:
	var length := race.track.length
	for o: KartState in race.karts:
		if o.id == k.id:
			continue
		var ds := fposmod(o.s - k.s, length)  # track.delta, inline
		if ds > length * 0.5:
			ds -= length
		if absf(ds) > BESIDE:
			continue
		var dd := k.d - o.d
		if absf(dd) >= SIDE_GAP:
			continue
		var side := signf(dd) if absf(dd) > 0.05 else (1.0 if k.id > o.id else -1.0)
		var away := o.d + side * SIDE_GAP
		want = maxf(want, away) if side > 0.0 else minf(want, away)
	return want


## The lean, with the drift on top. `lean` is the normal steering (under the drift entry),
## `curvature` the pursuit arc (1/m, + = left). The physics' `k.drift_dir` is the truth: the bot
## only asks for a drift with an entry pulse, then steers it with `lean_for_drift`.
func _drift(k: KartState, physics: KartPhysics, track: KartTrackModel, lean: float, curvature: float, dt: float) -> float:
	_drift_cool = maxf(0.0, _drift_cool - dt)
	if k.drift_dir != 0:
		if not _slid or drifting != k.drift_dir:  # the drift has just started
			drifting = k.drift_dir
			_drift_t = 0.0
			_releasing = false
			_slid = true
		_drift_t += dt
		var dir := float(k.drift_dir)
		if _releasing:
			return dir * DRIFT_RELEASE_LEAN
		var toward := curvature * -dir  # the arc it wants, toward the drift
		var widest := physics.drift_curvature(k, track, dir * KartPhysics.DRIFT_WIDE_LEAN)
		var off := (k.d - lane) * dir  # + = inside its line (toward the drift)
		var over := _bend_toward(track, k.s, -dir) < KartPhysics.DRIFT_WORTH_K * 0.5
		var edge := track.half_width(k.s) - k.d * dir  # metres to the road's inside edge
		if _drift_t >= DRIFT_MIN_SEC and (over or off > DRIFT_SLIP or edge < DRIFT_EDGE \
				or (toward < widest * 0.5 and off > DRIFT_TIGHT_OFF and k.drift_tier >= 1)):
			_release()
			return dir * DRIFT_RELEASE_LEAN
		return dir * maxf(DRIFT_HOLD_LEAN, physics.lean_for_drift(k, track, toward) * dir)
	if _releasing or _slid or (drifting != 0 and _drift_t >= DRIFT_ENTRY_MAX):
		# The drift ended (or never started): back to the line, a cooldown before the next.
		if not _releasing:
			_release()
		_releasing = false
		_slid = false
		drifting = 0
	if drifting != 0:
		# The entry pulse: hold the hard lean until the physics starts the drift.
		_drift_t += dt
		return float(drifting) * DRIFT_ENTRY_LEAN
	var want := physics.wants_drift(k, track)
	if want == 0:
		_corner_decided = false
		return lean
	if not _corner_decided:
		_corner_decided = true
		_corner_drift = _rng.randf() < drift_skill
	if not _corner_drift or mode == Mode.DODGE or _drift_cool > 0.0:
		return lean
	# Start from the line or outside it, running along the road.
	if (k.d - lane) * want > 0.3 or absf(angle_difference(track.yaw_at(k.s), k.heading)) > DRIFT_ENTRY_PSI:
		return lean
	drifting = want
	_drift_t = 0.0
	return float(drifting) * DRIFT_ENTRY_LEAN


func _release() -> void:
	_releasing = true
	_drift_cool = DRIFT_COOLDOWN


## How much the road bends toward `turn` (+1 left, -1 right) here and just ahead (1/m, the
## smaller of the two samples).
func _bend_toward(track: KartTrackModel, s: float, turn: float) -> float:
	return minf(track.curvature(s) * turn, track.curvature(track.wrap(s + 8.0)) * turn)
