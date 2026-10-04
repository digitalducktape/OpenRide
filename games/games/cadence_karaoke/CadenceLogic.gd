class_name CadenceLogic
extends RefCounted
## Cadence Karaoke's rules (#42), apart from drawing so they're tested headless. The rider
## picks a pace (a target cadence) and rides to it; the target line is that pace, shaped by a
## profile, and a change to the pace lands on a phrase boundary together with the music's new
## tempo. Points come while the cadence is inside a band around the target, more in a tight
## bonus band, with a streak multiplier. Power well over the cap freezes scoring ("ease off").

## The band around the target, by difficulty (rpm).
const BANDS := {"easy": 7.0, "standard": 5.0, "hard": 4.0}
const BONUS_BAND := 2.0
const GRACE_SEC := 1.0  ## the streak survives this long outside the band (the reading is noisy)
const POINTS_PER_SEC := 10.0
const BONUS_FACTOR := 1.5
const STREAK_STEP_SEC := 10.0  ## the multiplier grows by 0.25 for each
const STREAK_MULT_MAX := 2.0
## The cap is easy-going on purpose (the lesson of Tug of War and Safe Cracker): scoring freezes
## only when power, smoothed over about a second, stays above POWER_HEADROOM times the cap.
const POWER_HEADROOM := 1.25
const POWER_SMOOTHING_SEC := 1.0
const DEFAULT_PACE := 80
const PACE_MIN := 50
const PACE_MAX := 110
const PACE_STEP := 5
const TARGET_MIN := 40.0
const TARGET_MAX := 120.0
const LOOKAHEAD_SEC := 12.0
const SHAPES := ["steady", "pyramid", "builds", "spinups"]

var time := 0.0
var base_pace := DEFAULT_PACE  ## the rider's pace before any adjustment
var pace_adjust := 0  ## rpm added to every target, in steps of PACE_STEP, applied at a phrase boundary
var pending_adjust := 0  ## requested, waiting for the boundary
var shape := "steady"
var profile: Array = []  ## [{t, rpm}] from the circuit; empty in Just Ride
var tolerance := 5.0
var power_cap := 0.0  ## watts; 0 = none
var smoothed_power := -1.0
var in_band := false
var in_bonus := false
var frozen := false  ## scoring is frozen: ease off
var streak_sec := 0.0
var longest_streak := 0.0
var last_points := 0.0  ## this step's points (the scene awards them)
var cadence := 0.0
var band_sec := 0.0
var total_sec := 0.0
var cadence_sum := 0.0
var power_sum := 0.0

var _grace_left := 0.0
var _next_streak_mark := STREAK_STEP_SEC


func _init(difficulty := "standard", params := {}, new_shape := "steady") -> void:
	tolerance = float(params.get("tolerance_rpm", BANDS.get(difficulty, BANDS.standard)))
	power_cap = float(params.get("power_cap_watts", params.get("power_cap", 0.0)))
	base_pace = int(params.get("pace", DEFAULT_PACE))
	profile = params.get("cadence_profile", [])
	shape = new_shape if new_shape in SHAPES else "steady"


## The target at `at` seconds: the circuit's profile (interpolated) or the shape around the
## rider's pace, plus the rider's adjustment.
func target_at(at: float) -> float:
	var rpm := float(base_pace) + _shape_offset(at)
	if not profile.is_empty():
		rpm = _profile_rpm(at)
	return clampf(rpm + pace_adjust, TARGET_MIN, TARGET_MAX)


func target() -> float:
	return target_at(time)


## The rider's pace now: what − and + step.
func pace() -> int:
	return base_pace + pace_adjust


## Asks for a pace change of `steps` × PACE_STEP rpm; it waits for `apply_pending`. The pace
## stays between PACE_MIN and PACE_MAX. Returns whether anything changed.
func request_pace(steps: int) -> bool:
	var wanted := clampi(pace() + pending_adjust + steps * PACE_STEP, PACE_MIN, PACE_MAX)
	var delta := wanted - pace()
	if delta == pending_adjust:
		return false
	pending_adjust = delta
	return true


## The phrase boundary (or a timeout) has arrived: the pending change takes effect.
func apply_pending() -> bool:
	if pending_adjust == 0:
		return false
	pace_adjust += pending_adjust
	pending_adjust = 0
	return true


func pct_in_band() -> float:
	return 100.0 * band_sec / total_sec if total_sec > 0.0 else 0.0


func avg_cadence() -> float:
	return cadence_sum / total_sec if total_sec > 0.0 else 0.0


func avg_power() -> float:
	return power_sum / total_sec if total_sec > 0.0 else 0.0


func streak_multiplier() -> float:
	return minf(1.0 + 0.25 * floorf(streak_sec / STREAK_STEP_SEC), STREAK_MULT_MAX)


## Advances by `delta` seconds with the live cadence (rpm) and power (W). Returns the events
## ({type: ...}): "band_exit" (the streak ended), "streak" (seconds), "ease_off" and "recovered".
func step(delta: float, new_cadence: float, power: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	last_points = 0.0
	time += delta
	total_sec += delta
	cadence = new_cadence
	cadence_sum += new_cadence * delta
	power_sum += power * delta
	smoothed_power = power if smoothed_power < 0.0 else lerpf(smoothed_power, power, minf(delta / POWER_SMOOTHING_SEC, 1.0))
	var was_frozen := frozen
	frozen = power_cap > 0.0 and smoothed_power > power_cap * POWER_HEADROOM
	if frozen != was_frozen:
		events.append({"type": "ease_off" if frozen else "recovered"})
	var error := absf(new_cadence - target())
	in_band = new_cadence > 0.0 and error <= tolerance
	in_bonus = in_band and error <= BONUS_BAND
	if frozen:
		return events
	if in_band:
		_grace_left = GRACE_SEC
		band_sec += delta
		var rate := POINTS_PER_SEC * (BONUS_FACTOR if in_bonus else 1.0) * streak_multiplier()
		last_points = rate * delta
		streak_sec += delta
		longest_streak = maxf(longest_streak, streak_sec)
		if streak_sec >= _next_streak_mark:
			events.append({"type": "streak", "seconds": _next_streak_mark})
			_next_streak_mark += STREAK_STEP_SEC
	elif streak_sec > 0.0:
		_grace_left -= delta
		if _grace_left <= 0.0:
			streak_sec = 0.0
			_next_streak_mark = STREAK_STEP_SEC
			events.append({"type": "band_exit"})
	return events


func _shape_offset(at: float) -> float:
	match shape:
		"pyramid":  # -10 up to +10 and back over six minutes
			var phase := fposmod(at / 360.0, 1.0)
			return -10.0 + 20.0 * (1.0 - absf(1.0 - 2.0 * phase))
		"builds":  # +5 rpm a minute, to +15, then back to the start
			return 5.0 * fposmod(at / 60.0, 3.0)
		"spinups":  # 30 s up, 60 s easy
			return 15.0 if fposmod(at, 90.0) < 30.0 else 0.0
	return 0.0


func _profile_rpm(at: float) -> float:
	var last: Dictionary = profile[-1]
	var length := float(last.get("t", 0.0))
	if length > 0.0 and at > length:
		at = fposmod(at, length)  # an open-ended ride cycles the profile
	var previous: Dictionary = profile[0]
	for point in profile:
		if float(point.t) >= at:
			var span := float(point.t) - float(previous.t)
			if span <= 0.0:
				return float(point.rpm)
			return lerpf(float(previous.rpm), float(point.rpm), (at - float(previous.t)) / span)
		previous = point
	return float(last.rpm)
