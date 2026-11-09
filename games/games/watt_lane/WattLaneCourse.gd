class_name WattLaneCourse
extends RefCounted
## Watt Lane's course (#78): where the lane's centre sits over time, in watts on a 5 W grid
## (DESIGN.md, "The lane"). A lead-in hold, then slow drifts in 5 W steps and announced jumps, at
## least JUMP_GAP_SEC apart. Generated ahead in chunks from a seed, so an open-ended ride never
## runs out and the same seed always gives the same course.
##
## The course is a list of steps: from `times[i]` the centre is `watts[i]`; `jumps[i]` marks a
## jump (announced) as opposed to a drift step (not announced). `centre_at` is the rules' value;
## `visual_centre_at` eases between steps for the rails on the road and carries no number.

const GRID := 5  ## watts: every centre is a multiple of this
const LEAD_IN_SEC := 10.0
const FIRST_DRIFT_SEC := Vector2(10.0, 14.0)  ## the first jump lands 20-24 s in
const DRIFT_SEC := Vector2(20.0, 26.0)  ## then a jump every 20-26 s
const DRIFT_RATE := 0.01  ## of FTP a second, at most
const JUMP_WORK := Vector2(0.12, 0.20)  ## of FTP
const JUMP_WARMUP := Vector2(0.06, 0.10)
const JUMP_MIN_WATTS := 10
const FLOOR_FTP := 0.15  ## a widened range never puts the centre under this share of FTP
const JUMP_RAMP_SEC := 0.6  ## the rails bend over this either side of a jump (visual only)
const AHEAD_SEC := 60.0  ## generated at least this far ahead of what is asked

var times := PackedFloat64Array()
var watts := PackedInt32Array()
var jumps := PackedByteArray()
var lane_min := 0  ## the centre's range, watts
var lane_max := 0
var ftp := 150.0
var warmup := false
var jump_min := 0  ## watts: every jump moves the centre at least this far (over half a lane)
var jump_max := 0

var _rng := RandomNumberGenerator.new()
var _until := 0.0  ## generated up to this time
var _last_up := false


## `width`: the lane's width in watts. A jump always moves the centre more than half of it, so
## a rider who stays put leaves the new lane; the centre's range widens (mostly upward, never
## under FLOOR_FTP) when it is too narrow for such a jump either way from its middle.
func _init(seed_value: int, centre_min: int, centre_max: int, ftp_watts: float, is_warmup := false, width := 40) -> void:
	_rng.seed = seed_value
	ftp = maxf(ftp_watts, 50.0)
	warmup = is_warmup
	var sizes := JUMP_WARMUP if warmup else JUMP_WORK
	jump_min = maxi(maxi(snap(sizes.x * ftp), JUMP_MIN_WATTS), width / 2 + GRID)
	jump_max = maxi(snap(sizes.y * ftp), jump_min)
	lane_min = snap(centre_min)
	lane_max = maxi(snap(centre_max), lane_min + GRID)
	var short := 2 * jump_min - (lane_max - lane_min)
	if short > 0:
		var down := mini(snap(short / 2.0), maxi(lane_min - snap(FLOOR_FTP * ftp), 0))
		lane_min -= down
		lane_max += short - down
	_last_up = _rng.randf() < 0.5
	var start := snap(lerpf(float(lane_min), float(lane_max), 0.0 if warmup else 1.0 / 3.0))
	_add(0.0, start, false)
	_until = LEAD_IN_SEC
	ensure(AHEAD_SEC)


## Watts rounded to the course's 5 W grid.
static func snap(value: float) -> int:
	return roundi(value / GRID) * GRID


## Generates the course at least AHEAD_SEC past `t`.
func ensure(t: float) -> void:
	while _until < t + AHEAD_SEC:
		_add_phase()


## The rules' lane centre at `t` (watts).
func centre_at(t: float) -> int:
	return watts[index_at(t)]


## The index of the step in force at `t`.
func index_at(t: float) -> int:
	ensure(t)
	var i := times.bsearch(t, false) - 1  # the last step at or before t
	return clampi(i, 0, times.size() - 1)


## The first jump strictly after `t`, or -1 (never, once generated far enough).
func next_jump_after(t: float) -> int:
	ensure(t)
	for i in range(index_at(t) + 1, times.size()):
		if jumps[i] == 1:
			return i
	return -1


## The last jump at or before `t`, or -1.
func last_jump_at(t: float) -> int:
	for i in range(index_at(t), 0, -1):
		if jumps[i] == 1:
			return i
	return -1


## The centre for drawing: drift steps ease linearly into the next, jumps bend over
## ±JUMP_RAMP_SEC. Never more than one 5 W step from `centre_at` outside a jump.
func visual_centre_at(t: float) -> float:
	var i := index_at(t)
	var n := i + 1
	if n < times.size() and jumps[n] == 1 and t > times[n] - JUMP_RAMP_SEC:
		return _ramp(watts[i], watts[n], times[n], t)
	if i > 0 and jumps[i] == 1 and t < times[i] + JUMP_RAMP_SEC:
		return _ramp(watts[i - 1], watts[i], times[i], t)
	if n < times.size() and jumps[n] == 0:
		var span := times[n] - times[i]
		return lerpf(float(watts[i]), float(watts[n]), clampf((t - times[i]) / span, 0.0, 1.0))
	return float(watts[i])


func _ramp(from: int, to: int, at: float, t: float) -> float:
	var k := smoothstep(at - JUMP_RAMP_SEC, at + JUMP_RAMP_SEC, t)
	return lerpf(float(from), float(to), k)


## One drift, then one jump at its end.
func _add_phase() -> void:
	var span := FIRST_DRIFT_SEC if _jump_count() == 0 else DRIFT_SEC
	var length := _rng.randf_range(span.x, span.y)
	var start := _until
	var from := watts[watts.size() - 1]
	var target := snap(_rng.randf_range(float(lane_min), float(lane_max)))
	var step_sec := float(GRID) / (DRIFT_RATE * ftp)
	var count := mini(absi(target - from) / GRID, floori(length / step_sec) - 1)
	var dir := signi(target - from)
	for k in maxi(count, 0):
		_add(start + length * float(k + 1) / float(count + 1), from + dir * GRID * (k + 1), false)
	_until = start + length
	_add(_until, _jump_to(watts[watts.size() - 1]), true)


## Where a jump from `from` lands: 12-20% of FTP (warm-up 6-10%) and over half a lane, to the side with room,
## alternating when both have it (a warm-up climbs while it can).
func _jump_to(from: int) -> int:
	var size := snap(_rng.randf_range(float(jump_min), float(jump_max)))
	var room_up := lane_max - from
	var room_down := from - lane_min
	var up: bool
	if room_up >= size and room_down >= size:
		up = true if warmup else not _last_up
	elif room_up >= size or room_down >= size:
		up = room_up >= size
	else:
		up = room_up >= room_down
		size = maxi(floori(float(maxi(room_up, room_down)) / GRID) * GRID, GRID)
	_last_up = up
	return from + size if up else from - size


func _add(t: float, w: int, jump: bool) -> void:
	times.append(t)
	watts.append(w)
	jumps.append(1 if jump else 0)


func _jump_count() -> int:
	return jumps.count(1)
