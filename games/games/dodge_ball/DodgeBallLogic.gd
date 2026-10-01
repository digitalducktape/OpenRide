class_name DodgeBallLogic
extends RefCounted
## Dodge Ball's rules (#39), apart from drawing so they're tested headless. The scene
## (`DodgeBall.gd`) only shows them in 3D.
##
## The rider leans to move the bike across a wide road; balls roll at them. Everything is timed
## in seconds, not metres, so the 0.8 s warning holds at any road speed: a ball exists from
## `SPAWN_ETA` seconds before it reaches the rider's line, and its landing spot is marked the
## whole time. The scene turns `eta` into a distance with its smoothed road speed.
##
## - Shield: drains while cadence < cadence_floor and refills above it. A hit with the shield
##   up breaks it; with it down, the rider loses a life (Just Ride) or 50 points (circuit).
## - Power bonus: power >= target_watts doubles a dodge's points.
## - Rate ramps from ball_rate_start to ball_rate_end over RAMP_SEC. In a Just Ride a new wave
##   every WAVE_SEC raises the rate and adds curve balls (wave 2+) and doubles (wave 3+).
## - Just Ride: three lives; losing them ends the run, a GAME_OVER_SEC card follows, then a
##   new run. The best run is the score.

const ROAD_HALF := 6.0  ## metres from the centre line to the kerb
const RIDER_RANGE := 4.4  ## full lean puts the bike this far from the centre
## Lean → position gain, as the demo's (tuned on the bike): the edge comes at lean_x ~0.77.
const STEERING_GAIN := 1.3
const RIDER_HALF := 0.45  ## half the bike-and-rider's width
const BALL_RADIUS := 0.45
const WARNING_SEC := 0.8  ## the landing spot is marked at least this long before arrival
const SPAWN_ETA := 2.6  ## a ball appears this long before reaching the rider's line
const MIN_GAP_SEC := 0.45  ## never two arrivals closer than this (doubles arrive together)
const DOUBLE_GAP := 2.4  ## metres between a double's two balls
const AIM_CHANCE := 0.4
const DODGE_POINTS := 10.0
const POWER_BONUS := 2.0
const PENALTY := 50.0
const LIVES := 3
const WAVE_SEC := 60.0
const RAMP_SEC := 90.0
const ROUND_SEC := 90.0
const GAME_OVER_SEC := 5.0
const SHIELD_DRAIN_SEC := 3.0  ## full to empty below the floor
const SHIELD_REFILL_SEC := 4.0  ## empty to full above it
const STREAK_CHIMES := [5, 10, 20]

## Per difficulty: the defaults when Kotlin's params don't say.
const LEVELS := {
	"easy": {"cadence_floor": 75.0, "rate_start": 0.5, "rate_end": 1.2},
	"standard": {"cadence_floor": 85.0, "rate_start": 0.6, "rate_end": 1.5},
	"hard": {"cadence_floor": 90.0, "rate_start": 0.7, "rate_end": 1.8},
}

var cadence_floor := 85.0
var target_watts := 0.0  ## 0: no power bonus
var rate_start := 0.6
var rate_end := 1.5
var has_lives := true  ## Just Ride: lives and runs; circuit: penalties

var rider_x := 0.0
var shield := 1.0
var lives := LIVES
var wave := 1
var run := 1
var run_time := 0.0  ## seconds into this run (waves and the ramp follow it)
var game_over_left := 0.0  ## > 0 while the game-over card shows
## Live balls: {id, kind, x0, x1, eta, eta0}. x moves from x0 to x1 (curve balls) as eta runs
## down; x1 is where it lands, which is what the warning marks.
var balls: Array[Dictionary] = []

var dodges := 0
var hits := 0
var streak := 0
var longest_streak := 0
var run_points := 0.0  ## this run's points as the rules count them (before the effort multiplier)
var best_run_points := 0.0
var time_total := 0.0
var time_above_floor := 0.0
var power_sum := 0.0

var _rng := RandomNumberGenerator.new()
var _spawn_left := 0.6
var _next_id := 0
var _last_arrival := -INF


func _init(seed_value: int, difficulty := "standard", params := {}, lives_mode := true) -> void:
	_rng.seed = seed_value
	var level: Dictionary = LEVELS.get(difficulty, LEVELS.standard)
	cadence_floor = float(params.get("cadence_floor", level.cadence_floor))
	target_watts = float(params.get("target_watts", 0.0))
	rate_start = float(params.get("ball_rate_start", level.rate_start))
	rate_end = float(params.get("ball_rate_end", level.rate_end))
	has_lives = lives_mode


## The bike's x for a lean from -1 (left) to +1 (right).
static func x_for_lean(lean: float) -> float:
	return clampf(lean * STEERING_GAIN, -1.0, 1.0) * RIDER_RANGE


## Balls a second at `t` seconds into a run, in `w`ave.
func rate_at(t: float, w := 1) -> float:
	var r := lerpf(rate_start, rate_end, clampf(t / RAMP_SEC, 0.0, 1.0))
	return r * (1.0 + 0.15 * (w - 1)) if has_lives else r


func shield_up() -> bool:
	return shield > 0.0


func power_multiplier(power: float) -> float:
	return POWER_BONUS if target_watts > 0.0 and power >= target_watts else 1.0


func pct_time_above_floor() -> float:
	return 100.0 * time_above_floor / time_total if time_total > 0.0 else 0.0


func avg_power() -> float:
	return power_sum / time_total if time_total > 0.0 else 0.0


## A ball's current x (curve balls bend towards where they land).
static func ball_x(ball: Dictionary) -> float:
	var t := 1.0 - clampf(ball.eta / ball.eta0, 0.0, 1.0)
	return lerpf(ball.x0, ball.x1, 1.0 - pow(1.0 - t, 2.0))


## Whether a ball landing at `x` hits a bike at `rider`.
static func touches(x: float, rider: float) -> bool:
	return absf(x - rider) < BALL_RADIUS + RIDER_HALF


## Advances one frame. Returns events for the scene:
##   {type: "spawn", ball}: a new ball (its warning shows from now)
##   {type: "dodge", ball, points, streak}: points before the effort multiplier
##   {type: "streak", count}: 5 / 10 / 20 in a row
##   {type: "shield_break", ball} · {type: "hit", ball, penalty, lives}
##   {type: "shield_ready"}: the shield is full again
##   {type: "wave", wave} · {type: "game_over", run, points} · {type: "new_run", run}
func step(delta: float, lean: float, cadence: float, power: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	time_total += delta
	power_sum += power * delta
	if cadence >= cadence_floor:
		time_above_floor += delta
	rider_x = x_for_lean(lean)
	if game_over_left > 0.0:
		game_over_left -= delta
		if game_over_left <= 0.0:
			_new_run()
			events.append({"type": "new_run", "run": run})
		return events

	var was_full := shield >= 1.0
	if cadence >= cadence_floor:
		shield = minf(1.0, shield + delta / SHIELD_REFILL_SEC)
	else:
		shield = maxf(0.0, shield - delta / SHIELD_DRAIN_SEC)
	if shield >= 1.0 and not was_full:
		events.append({"type": "shield_ready"})

	run_time += delta
	if has_lives:
		var w := 1 + int(run_time / WAVE_SEC)
		if w != wave:
			wave = w
			events.append({"type": "wave", "wave": wave})

	_spawn_left -= delta
	if _spawn_left <= 0.0:
		_spawn(events)
		_spawn_left += 1.0 / maxf(0.05, rate_at(run_time, wave))

	var kept: Array[Dictionary] = []
	for ball in balls:
		ball.eta -= delta
		if ball.eta > 0.0:
			kept.append(ball)
			continue
		if touches(ball.x1, rider_x):
			_hit(ball, events)
			if game_over_left > 0.0:
				kept.clear()
				break
		else:
			dodges += 1
			streak += 1
			longest_streak = maxi(longest_streak, streak)
			var points := DODGE_POINTS * power_multiplier(power)
			run_points += points
			best_run_points = maxf(best_run_points, run_points)
			events.append({"type": "dodge", "ball": ball, "points": points, "streak": streak})
			if streak in STREAK_CHIMES:
				events.append({"type": "streak", "count": streak})
	balls = kept
	return events


func _hit(ball: Dictionary, events: Array[Dictionary]) -> void:
	hits += 1
	streak = 0
	if shield_up():
		shield = 0.0
		events.append({"type": "shield_break", "ball": ball})
		return
	if has_lives:
		lives -= 1
		events.append({"type": "hit", "ball": ball, "penalty": 0.0, "lives": lives})
		if lives <= 0:
			game_over_left = GAME_OVER_SEC
			events.append({"type": "game_over", "run": run, "points": run_points})
	else:
		run_points = maxf(0.0, run_points - PENALTY)
		events.append({"type": "hit", "ball": ball, "penalty": PENALTY, "lives": lives})


func _new_run() -> void:
	run += 1
	lives = LIVES
	wave = 1
	run_time = 0.0
	run_points = 0.0
	shield = 1.0
	streak = 0
	balls.clear()
	_spawn_left = 1.0
	_last_arrival = -INF


func _spawn(events: Array[Dictionary]) -> void:
	# Arrivals are spaced at least MIN_GAP_SEC apart, so every dodge stays possible.
	var arrival := time_total + SPAWN_ETA
	if arrival - _last_arrival < MIN_GAP_SEC:
		arrival = _last_arrival + MIN_GAP_SEC
	_last_arrival = arrival
	var eta := arrival - time_total
	var kind := "plain"
	if has_lives and wave >= 3 and _rng.randf() < 0.3:
		kind = "double"
	elif has_lives and wave >= 2 and _rng.randf() < 0.35:
		kind = "curve"
	var x1: float
	if _rng.randf() < AIM_CHANCE:
		x1 = clampf(rider_x + _rng.randf_range(-0.4, 0.4), -RIDER_RANGE, RIDER_RANGE)
	else:
		x1 = _rng.randf_range(-RIDER_RANGE, RIDER_RANGE)
	if kind == "double":
		# Two balls with a gap between them to ride through.
		var centre := clampf(x1, -RIDER_RANGE + DOUBLE_GAP / 2, RIDER_RANGE - DOUBLE_GAP / 2)
		_add_ball("double", centre - DOUBLE_GAP / 2 - BALL_RADIUS, eta, events)
		_add_ball("double", centre + DOUBLE_GAP / 2 + BALL_RADIUS, eta, events)
		return
	var x0 := x1
	if kind == "curve":
		x0 = clampf(x1 + (3.0 if _rng.randf() < 0.5 else -3.0), -ROAD_HALF + 0.5, ROAD_HALF - 0.5)
	_add_ball(kind, x1, eta, events, x0)


func _add_ball(kind: String, x1: float, eta: float, events: Array[Dictionary], x0 := NAN) -> void:
	var ball := {"id": _next_id, "kind": kind, "x0": x1 if is_nan(x0) else x0, "x1": x1, "eta": eta, "eta0": eta}
	_next_id += 1
	balls.append(ball)
	events.append({"type": "spawn", "ball": ball})
