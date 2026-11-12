class_name WattLaneLogic
extends RefCounted
## Watt Lane's rules (#78; DESIGN.md), apart from drawing so they're tested headless.
##
## Your power, averaged over a 3 s window and rounded to whole watts (`shown_watts`, the one
## power number every part of the HUD shows), is your place across the road. The lane is a band
## of watts, `lane_lo()`-`lane_hi()` on a 5 W grid, whose centre follows a `WattLaneCourse`:
## slow drifts and jumps. Each jump is announced ANNOUNCE_SEC ahead, and from PRE_SEC before it
## to POST_SEC after it either lane counts. In the lane you score POINTS_PER_SEC a second times a
## streak multiplier; the streak survives GRACE_SEC outside, then resets.

const SMOOTH_SEC := 3.0
const BIN_SEC := 0.1  ## the window's resolution
const ANNOUNCE_SEC := 5.0
const PRE_SEC := 1.5  ## before a jump, the new lane counts too
const POST_SEC := 3.5  ## after it, the old lane still counts (and a catch can happen)
const GRACE_SEC := 1.0
const POINTS_PER_SEC := 10.0
const STREAK_STEP_SEC := 5.0  ## +0.5 to the multiplier for each
const STREAK_MAX := 3.0
const WARMUP_FACTOR := 1.25  ## a warm-up has no effort multiplier: its points count this much
## Width (share of FTP, floor in watts) and centre range (shares of FTP) by difficulty. Kotlin
## sends the scaled values (`lane_width_watts`, `lane_min_watts`, `lane_max_watts`); these are the
## fallback from `ftp_watts`, and the same maths.
const WIDTH := {"easy": [0.25, 40], "standard": [0.20, 30], "hard": [0.15, 30]}
const RANGE := {"easy": [0.20, 0.35], "standard": [0.22, 0.40], "hard": [0.32, 0.55]}
const WARMUP_RANGE := [0.18, 0.32]
const DEFAULT_FTP := 150.0
## Stars: points per minute, every difficulty (DESIGN.md, "Scoring"). A perfect ride at 1.0×
## effort earns 1550-1800 a minute (2 stars); 3 stars needs about 1.3×.
const STARS := [250, 1200, 2000]

var ftp := DEFAULT_FTP
var width := 40  ## watts, a multiple of 10
var warmup := false
var course: WattLaneCourse

var time := 0.0
var smoothed := 0.0  ## the window average (watts)
var shown_watts := 0  ## round(smoothed): the number on screen and in the rules
var in_lane := false
var streak_sec := 0.0
var longest_streak := 0.0
var last_points := 0.0  ## this step's points, before the effort multiplier (the scene awards them)
var lane_sec := 0.0
var total_sec := 0.0
var power_sum := 0.0
var jumps := 0  ## jumps that have happened
var jumps_caught := 0

var _bin_pw := PackedFloat64Array()
var _bin_dt := PackedFloat64Array()
var _bin := 0
var _grace_left := 0.0
var _announced := -1  ## the course index of the last jump announced
var _counted := 0  ## the last countdown number sent for it
var _passed := -1  ## the last jump whose moment has passed
var _catching := -1  ## the jump being watched for a catch, or -1
var _caught := false


func _init(difficulty := "standard", params := {}, seed_value := 0, role := "work") -> void:
	ftp = float(params.get("ftp_watts", DEFAULT_FTP))
	if ftp <= 0.0:
		ftp = DEFAULT_FTP
	warmup = role == "warmup"
	var w: Array = WIDTH.get(difficulty, WIDTH.standard)
	var fallback_width := maxi(ceili(ftp * float(w[0]) / 10.0) * 10, int(w[1]))
	width = ceili(float(params.get("lane_width_watts", fallback_width)) / 10.0) * 10
	var r: Array = WARMUP_RANGE if warmup else RANGE.get(difficulty, RANGE.standard)
	var lo := int(params.get("lane_min_watts", roundi(ftp * float(r[0]))))
	var hi := int(params.get("lane_max_watts", roundi(ftp * float(r[1]))))
	course = WattLaneCourse.new(seed_value, lo, hi, ftp, warmup, width)
	_bin_pw.resize(roundi(SMOOTH_SEC / BIN_SEC))
	_bin_dt.resize(_bin_pw.size())


## The current lane's bounds (watts, inclusive).
func lane_lo() -> int:
	return course.centre_at(time) - width / 2


func lane_hi() -> int:
	return course.centre_at(time) + width / 2


## The band the rules use right now, as (lo, hi): the lane, or both lanes in a switch window.
func band() -> Vector2i:
	var lo := lane_lo()
	var hi := lane_hi()
	var j := _switching(time)
	if j >= 0:
		var other := course.watts[j - 1] if time >= course.times[j] else course.watts[j]
		lo = mini(lo, other - width / 2)
		hi = maxi(hi, other + width / 2)
	return Vector2i(lo, hi)


## The jump index whose switch window holds `t`, or -1.
func _switching(t: float) -> int:
	var j := course.next_jump_after(t)
	if j >= 0 and t >= course.times[j] - PRE_SEC:
		return j
	j = course.last_jump_at(t)
	if j > 0 and t < course.times[j] + POST_SEC:
		return j
	return -1


## The announced jump ahead: {at (seconds left), from, to, up, lo, hi (the new lane)}, or {}.
func upcoming() -> Dictionary:
	var j := course.next_jump_after(time)
	if j < 0 or course.times[j] - time > ANNOUNCE_SEC:
		return {}
	var to := course.watts[j]
	return {"at": course.times[j] - time, "from": course.watts[j - 1], "to": to,
		"up": to > course.watts[j - 1], "lo": to - width / 2, "hi": to + width / 2}


func streak_multiplier() -> float:
	return minf(1.0 + 0.5 * floorf(streak_sec / STREAK_STEP_SEC), STREAK_MAX)


func in_lane_pct() -> float:
	return 100.0 * lane_sec / total_sec if total_sec > 0.0 else 0.0


func avg_power() -> float:
	return power_sum / total_sec if total_sec > 0.0 else 0.0


## Where you are against the band: -1 under it, 0 inside, 1 over it.
func side() -> int:
	var b := band()
	return -1 if shown_watts < b.x else (1 if shown_watts > b.y else 0)


## Advances `delta` seconds with the live power reading (W). Returns the events
## ({type: ...}): announce {to, up, lo, hi}, count {n}, jump {up}, caught, missed,
## streak {multiplier}, lane_exit, lane_enter.
func step(delta: float, power: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	last_points = 0.0
	time += delta
	total_sec += delta
	power_sum += power * delta
	_smooth(delta, power)
	_jump_events(events)
	var b := band()
	var was_in := in_lane
	in_lane = shown_watts >= b.x and shown_watts <= b.y
	if in_lane and not was_in:
		events.append({"type": "lane_enter"})
	_catch(events)
	_score(delta, events)
	return events


func _smooth(delta: float, power: float) -> void:
	_bin_pw[_bin] += power * delta
	_bin_dt[_bin] += delta
	if _bin_dt[_bin] >= BIN_SEC - 1e-6:
		_bin = (_bin + 1) % _bin_pw.size()
		_bin_pw[_bin] = 0.0
		_bin_dt[_bin] = 0.0
	var pw := 0.0
	var dt := 0.0
	for i in _bin_pw.size():
		pw += _bin_pw[i]
		dt += _bin_dt[i]
	smoothed = pw / dt if dt > 0.0 else power
	shown_watts = roundi(smoothed)


func _jump_events(events: Array[Dictionary]) -> void:
	var up := upcoming()
	var j := course.next_jump_after(time)
	if not up.is_empty() and j != _announced:
		_announced = j
		_counted = 0
		events.append({"type": "announce", "to": up.to, "up": up.up, "lo": up.lo, "hi": up.hi})
	if not up.is_empty():
		var n := ceili(float(up.at))
		if n <= 3 and n >= 1 and n != _counted:
			_counted = n
			events.append({"type": "count", "n": n})
	var last := course.last_jump_at(time)
	if last > 0 and last != _passed:
		_passed = last
		jumps += 1
		_catching = last
		_caught = false
		events.append({"type": "jump", "up": course.watts[last] > course.watts[last - 1]})


## A jump is caught once the rider is in the new lane on its own within POST_SEC.
func _catch(events: Array[Dictionary]) -> void:
	if _catching < 0:
		return
	if not _caught and shown_watts >= lane_lo() and shown_watts <= lane_hi():
		_caught = true
		jumps_caught += 1
		events.append({"type": "caught"})
	if time >= course.times[_catching] + POST_SEC:
		if not _caught:
			events.append({"type": "missed"})
		_catching = -1


func _score(delta: float, events: Array[Dictionary]) -> void:
	if in_lane:
		_grace_left = GRACE_SEC
		lane_sec += delta
		var before := streak_multiplier()
		streak_sec += delta
		longest_streak = maxf(longest_streak, streak_sec)
		last_points = POINTS_PER_SEC * before * delta * (WARMUP_FACTOR if warmup else 1.0)
		if streak_multiplier() > before:
			events.append({"type": "streak", "multiplier": streak_multiplier()})
	elif streak_sec > 0.0:
		_grace_left -= delta
		if _grace_left <= 0.0:
			streak_sec = 0.0
			events.append({"type": "lane_exit"})
