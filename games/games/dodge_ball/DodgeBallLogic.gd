class_name DodgeBallLogic
extends RefCounted
## Dodge Ball's rules (#39), apart from drawing so they're tested headless. The scene
## (`DodgeBall.gd`) only shows them in 3D.
##
## The rider leans to move the bike across a wide road; balls roll at them. Everything is timed
## in seconds, not metres, so the 0.8 s warning holds at any road speed: a ball exists from
## `SPAWN_ETA` seconds before it reaches the rider's line, and where it arrives is marked the
## whole time. The road's speed follows cadence (`road_speed`), and the scene places each ball by
## its seconds to go.
##
## Two modes, chosen by the rider (the game's "Mode" option):
##
## **Dodge** (the default): keep away from the balls.
## - A ball that passes clear scores DODGE_POINTS (× the power bonus) and builds the streak.
## - Shield: drains while cadence < cadence_floor and refills above it. A hit with the shield
##   up breaks it; with it down, the rider loses a life (Just Ride) or PENALTY points (circuit).
##
## **Catch**: steer into the balls.
## - A ball caught with the shield up scores the same points (× the power bonus) and builds the
##   streak. Pedalling below the floor drains the shield as in Dodge, and a ball caught with the
##   shield down is fumbled: no points, and the streak is lost.
## - A missed ball costs the streak; in a Just Ride, three misses in a row cost a life. Nothing
##   is ever taken off the score.
## - Every ball can be reached: each one arrives within reach of where the last one did, at a
##   lateral speed a rider manages (REACH_SPEED), and there are no doubles.
##
## Both: power >= target_watts doubles points; the rate ramps from ball_rate_start to
## ball_rate_end over RAMP_SEC; in a Just Ride a new wave every WAVE_SEC raises it (capped) and
## adds curve balls (wave 2+) and, in Dodge, doubles (wave 3+); three lives per run, a
## GAME_OVER_SEC card, then a new run, and the best run is the score.

const MODES := ["dodge", "catch"]

const ROAD_HALF := 6.0  ## metres from the centre line to the kerb
const RIDER_RANGE := 4.4  ## full lean puts the bike this far from the centre
## Lean → position gain, as the demo's (tuned on the bike): the edge comes at lean_x ~0.77.
const STEERING_GAIN := 1.3
const RIDER_HALF := 0.45  ## half the bike-and-rider's width
const BALL_RADIUS := 0.45
const WARNING_SEC := 0.8  ## where a ball arrives is marked at least this long before
const SPAWN_ETA := 2.6  ## a ball appears this long before reaching the rider's line
const MIN_GAP_SEC := 0.45  ## never two arrivals closer than this (doubles arrive together)
const DOUBLE_GAP := 2.4  ## metres between a double's two balls
const AIM_CHANCE := 0.4
## Catch mode: metres a second of sideways travel a rider can count on between two balls (on
## the bike, steering across the screen took about 1.2 s for 8.8 m, so this is comfortable).
const REACH_SPEED := 3.0
const CATCH_MISSES_PER_LIFE := 3
const DODGE_POINTS := 10.0
const POWER_BONUS := 2.0
const PENALTY := 50.0
const LIVES := 3
const WAVE_SEC := 60.0
const WAVE_STEP := 0.15  ## each wave adds this share to the rate…
const WAVE_MAX := 1.6  ## …up to this many times the ramp's rate
const RATE_CAP := 2.4  ## balls a second, whatever the params and waves say
const RAMP_SEC := 90.0
const ROUND_SEC := 90.0
const GAME_OVER_SEC := 5.0
const SHIELD_DRAIN_SEC := 3.0  ## full to empty below the floor
const SHIELD_REFILL_SEC := 4.0  ## empty to full above it
const STREAK_CHIMES := [5, 10, 20]

## Road speed (m/s) for a cadence: proportional to cadence squared plus a little linear term,
## so it is clearly slow at 60 rpm (about 9 m/s, a cruise), fast at 100 (22 m/s) and stops at 0.
## Cadence rather than power: it's what the rider feels in their legs, it answers at once, and
## the power already has its own reward (the bonus).
const SPEED_SQUARE := 0.0018
const SPEED_LINEAR := 0.04
const SPEED_MAX := 32.0

## Per difficulty: the defaults when Kotlin's params don't say.
const LEVELS := {
	"easy": {"cadence_floor": 75.0, "rate_start": 0.5, "rate_end": 1.2},
	"standard": {"cadence_floor": 85.0, "rate_start": 0.6, "rate_end": 1.5},
	"hard": {"cadence_floor": 90.0, "rate_start": 0.7, "rate_end": 1.8},
}

var mode := "dodge"
var cadence_floor := 85.0
var target_watts := 0.0  ## 0: no power bonus
var rate_start := 0.6
var rate_end := 1.5
var has_lives := true  ## Just Ride: lives and runs; circuit: penalties (Dodge) or none (Catch)

var rider_x := 0.0
var shield := 1.0
var lives := LIVES
var wave := 1
var run := 1
var run_time := 0.0  ## seconds into this run (waves and the ramp follow it)
var game_over_left := 0.0  ## > 0 while the game-over card shows
## Live balls: {id, kind, x0, x1, eta, eta0}. x moves from x0 to x1 (curve balls) as eta runs
## down; x1 is where it arrives, which is what the warning marks.
var balls: Array[Dictionary] = []

var dodges := 0  ## balls passed clear (Dodge)
var catches := 0  ## balls caught with the shield up (Catch)
var hits := 0  ## balls that hit the bike (Dodge)
var misses := 0  ## balls missed (Catch)
var fumbles := 0  ## balls caught with the shield down (Catch)
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
var _last_x := 0.0  ## where the last ball arrives (Catch keeps the next within reach)
var _misses_in_row := 0


func _init(seed_value: int, difficulty := "standard", params := {}, lives_mode := true, play_mode := "dodge") -> void:
	_rng.seed = seed_value
	var level: Dictionary = LEVELS.get(difficulty, LEVELS.standard)
	cadence_floor = float(params.get("cadence_floor", level.cadence_floor))
	target_watts = float(params.get("target_watts", 0.0))
	rate_start = float(params.get("ball_rate_start", level.rate_start))
	rate_end = float(params.get("ball_rate_end", level.rate_end))
	has_lives = lives_mode
	mode = play_mode if play_mode in MODES else "dodge"


func is_catch() -> bool:
	return mode == "catch"


## Switches mode from the next ball on (the rider changed the option mid-ride). Balls already on
## the road keep the rules they were thrown under, and the streak starts again.
func set_mode(new_mode: String) -> void:
	if new_mode in MODES and new_mode != mode:
		mode = new_mode
		streak = 0
		_misses_in_row = 0
		for ball in balls:
			ball["mode"] = ball.get("mode", mode)


## The bike's x for a lean from -1 (left) to +1 (right).
static func x_for_lean(lean: float) -> float:
	return clampf(lean * STEERING_GAIN, -1.0, 1.0) * RIDER_RANGE


## Road speed in m/s for a cadence (see SPEED_SQUARE): 0 at 0 rpm.
static func road_speed(cadence: float) -> float:
	var c := maxf(cadence, 0.0)
	return minf(SPEED_SQUARE * c * c + SPEED_LINEAR * c, SPEED_MAX)


## Balls a second at `t` seconds into a run, in `w`ave.
func rate_at(t: float, w := 1) -> float:
	var r := lerpf(rate_start, rate_end, clampf(t / RAMP_SEC, 0.0, 1.0))
	if has_lives:
		r *= minf(1.0 + WAVE_STEP * (w - 1), WAVE_MAX)
	return minf(r, RATE_CAP)


func shield_up() -> bool:
	return shield > 0.0


func power_multiplier(power: float) -> float:
	return POWER_BONUS if target_watts > 0.0 and power >= target_watts else 1.0


func pct_time_above_floor() -> float:
	return 100.0 * time_above_floor / time_total if time_total > 0.0 else 0.0


func avg_power() -> float:
	return power_sum / time_total if time_total > 0.0 else 0.0


## Balls that scored: dodges in Dodge, catches in Catch.
func scored_balls() -> int:
	return catches if is_catch() else dodges


## A ball's current x (curve balls bend towards where they arrive).
static func ball_x(ball: Dictionary) -> float:
	var t := 1.0 - clampf(ball.eta / ball.eta0, 0.0, 1.0)
	return lerpf(ball.x0, ball.x1, 1.0 - pow(1.0 - t, 2.0))


## Whether a ball arriving at `x` meets a bike at `rider`.
static func touches(x: float, rider: float) -> bool:
	return absf(x - rider) < BALL_RADIUS + RIDER_HALF


## Advances one frame. Returns events for the scene:
##   {type: "spawn", ball}: a new ball (its warning shows from now)
##   Dodge: {type: "dodge", ball, points, streak} · {type: "shield_break", ball}
##          {type: "hit", ball, penalty, lives}
##   Catch: {type: "catch", ball, points, streak} · {type: "fumble", ball}
##          {type: "miss", ball, lives}
##   {type: "streak", count}: 5 / 10 / 20 in a row
##   {type: "shield_ready"}: the shield is full again
##   {type: "wave", wave} · {type: "game_over", run, points} · {type: "new_run", run}
## Points are before the effort multiplier.
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
		var met := touches(ball.x1, rider_x)
		if ball.get("mode", mode) == "catch":
			_arrive_catch(ball, met, power, events)
		else:
			_arrive_dodge(ball, met, power, events)
		if game_over_left > 0.0:
			kept.clear()
			break
	balls = kept
	return events


func _arrive_dodge(ball: Dictionary, met: bool, power: float, events: Array[Dictionary]) -> void:
	if met:
		_hit(ball, events)
		return
	dodges += 1
	_score(ball, "dodge", power, events)


func _arrive_catch(ball: Dictionary, met: bool, power: float, events: Array[Dictionary]) -> void:
	if met and shield_up():
		catches += 1
		_misses_in_row = 0
		_score(ball, "catch", power, events)
		return
	streak = 0
	if met:
		# Caught with the shield down: it slips out of the rider's hands.
		fumbles += 1
		_misses_in_row = 0
		events.append({"type": "fumble", "ball": ball})
		return
	misses += 1
	_misses_in_row += 1
	if has_lives and _misses_in_row >= CATCH_MISSES_PER_LIFE:
		_misses_in_row = 0
		lives -= 1
	events.append({"type": "miss", "ball": ball, "lives": lives})
	if has_lives and lives <= 0:
		game_over_left = GAME_OVER_SEC
		events.append({"type": "game_over", "run": run, "points": run_points})


func _score(ball: Dictionary, type: String, power: float, events: Array[Dictionary]) -> void:
	streak += 1
	longest_streak = maxi(longest_streak, streak)
	var points := DODGE_POINTS * power_multiplier(power)
	run_points += points
	best_run_points = maxf(best_run_points, run_points)
	events.append({"type": type, "ball": ball, "points": points, "streak": streak})
	if streak in STREAK_CHIMES:
		events.append({"type": "streak", "count": streak})


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
	_misses_in_row = 0
	balls.clear()
	_spawn_left = 1.0
	_last_arrival = -INF


func _spawn(events: Array[Dictionary]) -> void:
	# Arrivals are spaced at least MIN_GAP_SEC apart, so every ball stays playable.
	var arrival := time_total + SPAWN_ETA
	if arrival - _last_arrival < MIN_GAP_SEC:
		arrival = _last_arrival + MIN_GAP_SEC
	var gap := arrival - _last_arrival
	_last_arrival = arrival
	var eta := arrival - time_total
	var kind := "plain"
	if has_lives and wave >= 3 and not is_catch() and _rng.randf() < 0.3:
		kind = "double"
	elif has_lives and wave >= 2 and _rng.randf() < 0.35:
		kind = "curve"
	var x1: float
	if is_catch():
		# Within reach of where the last ball arrives, at a comfortable sideways speed.
		var reach := minf(REACH_SPEED * gap, 2.0 * RIDER_RANGE)
		x1 = clampf(_last_x + _rng.randf_range(-reach, reach), -RIDER_RANGE, RIDER_RANGE)
	elif _rng.randf() < AIM_CHANCE:
		x1 = clampf(rider_x + _rng.randf_range(-0.4, 0.4), -RIDER_RANGE, RIDER_RANGE)
	else:
		x1 = _rng.randf_range(-RIDER_RANGE, RIDER_RANGE)
	_last_x = x1
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
	var ball := {"id": _next_id, "kind": kind, "mode": mode, "x0": x1 if is_nan(x0) else x0, "x1": x1,
		"eta": eta, "eta0": eta}
	_next_id += 1
	balls.append(ball)
	events.append({"type": "spawn", "ball": ball})
