class_name PullLogic
extends RefCounted
## The Pull's rules (#79), apart from drawing so they're tested headless. A chain from the bike
## to a weighted sled: the further it goes, the more watts it needs (the weight box slides
## forward), until the rider maxes out and the sled stalls. Distance is the score. The design,
## its formulas and its tuning are in DESIGN.md (this folder).
##
## Phases (an enum FSM; DESIGN.md "The pull"):
##   SET       the look back at the sled; the horn ends it (announced SET_SEC ahead)
##   PULL      the sled moves; ends in a stall, a Full Pull or the overtime guard ("time")
##   RESULT    the distance shows
##   RECOVERY  a rest card, then the next pull's SET
##   DONE      no more pulls: the scene ends the segment
## Modes: "rounds" (N pulls), "timed" (pulls until the timer ends; a running pull finishes) and
## "open" (pulls until the rider ends the session).

enum Phase { SET, PULL, RESULT, RECOVERY, DONE }

const DEFAULT_FTP := 150.0
## The distance at which the sled needs exactly FTP, per difficulty (Kotlin sends `d_ref_m`).
## Tuned so a steady pull at FTP lasts 3-5 minutes: ~4.5, ~3.8 and ~3.2.
const D_REF := {"easy": 360.0, "standard": 300.0, "hard": 250.0}
const BASE_SHARE := 0.30  ## the sled's need at the start, × FTP
const RISE_SHARE := 0.70  ## what it adds by d_ref, × FTP
const FULL_FACTOR := 1.12  ## the Full Pull line, × d_ref (needs 108% of FTP there)
const V_MAX := 2.5  ## m/s at the start for a rider at FTP
const G_FULL := 0.70  ## the gap (× FTP) that gives V_MAX
const G_CAP := 1.5  ## a sprint tops out at sqrt(1.5) × V_MAX
const ACCEL := 0.6  ## m/s² at most, speeding up
const DECEL := 0.5  ## m/s² at most, slowing down
const POWER_TAU := 1.5  ## seconds: the power's smoothing (the bike reports about once a second)
const CRAWL := 0.2  ## m/s: below this the sled is crawling
const STALL_SEC := 5.0  ## crawling this long in a row ends the pull
const WARN_SEC := 1.5  ## "Dig in!" after this long crawling (3.5 s before the stall)
const ROLLING_M := 1.0  ## the stall clock runs once the sled has rolled this far...
const GRACE_SEC := 15.0  ## ...or this long after the horn
const SET_SEC := 3.5
const RESULT_SEC := 4.0
const REST_SEC := 60.0  ## between pulls in rounds and open rides
const TIMED_REST_SEC := 30.0  ## between pulls in a timed ride
## A timed ride starts a new pull if at least this would be left after the rest ("new pulls
## until the timer ends"; a 60 s floor ended a 5-minute ride at 4 minutes).
const MIN_PULL_LEFT := 10.0
const OVERTIME := 1.3  ## a pull still going at this × the length ends ("time"); Kotlin stops at 1.5
const POINTS_PER_M := 10.0
const FULL_PULL_BONUS := 500.0
const BOARD_EVERY := 25.0  ## metres between distance boards
const BEST_NEAR := 15.0  ## metres before the best flag that the crowd starts to rise
## Stars from the best pull's points, as shares of d_ref × POINTS_PER_M (DESIGN.md "Scoring").
const STAR_SHARES := [0.2, 0.667, 1.2]

var phase := Phase.SET
var mode := "open"
var rounds := 1
var duration := -1.0  ## the segment's length in seconds, -1 open-ended
var ftp := DEFAULT_FTP
var d_ref := 300.0
var full_m := 336.0
var distance := 0.0  ## this pull's metres
var speed := 0.0  ## m/s
var smoothed_power := 0.0
var pull_index := 0  ## 1-based once the first SET starts
var pulls_done := 0
var full_pulls := 0
var phase_left := SET_SEC  ## seconds left of SET, RESULT or RECOVERY
var pull_sec := 0.0  ## this pull's seconds since the horn
var stall_sec := 0.0  ## seconds crawling in a row
var warned := false  ## "Dig in!" is showing
var best_distance := 0.0  ## the rider's best (this difficulty), before or during this ride
var best_pull_m := 0.0  ## this ride's best pull
var best_pull_sec := 0.0
var last_end := ""  ## how the last pull ended: "stall", "full" or "time"
var last_points := 0.0  ## this step's distance points (the scene awards them)

var _started := false  ## the stall clock is running
var _near_sent := false
var _passed_sent := false
var _best_at_start := 0.0  ## the best when this pull started (the flag on the track)


## `params`: the segment's (ftp_watts, d_ref_m, full_factor). `new_mode`: "rounds", "timed" or
## "open". `best_m`: the rider's best distance so far at this difficulty (0 for none).
func _init(params := {}, difficulty := "standard", new_mode := "open", new_rounds := 1,
		duration_sec := -1.0, best_m := 0.0) -> void:
	ftp = maxf(float(params.get("ftp_watts", params.get("ftp", DEFAULT_FTP))), 1.0)
	d_ref = maxf(float(params.get("d_ref_m", D_REF.get(difficulty, D_REF.standard))), 10.0)
	full_m = d_ref * float(params.get("full_factor", FULL_FACTOR))
	mode = new_mode
	rounds = maxi(new_rounds, 1)
	duration = duration_sec
	best_distance = maxf(best_m, 0.0)
	_begin_set()


## The sled's need at `d` metres, in watts: FTP × (0.30 + 0.70 × d / d_ref).
func required_at(d: float) -> float:
	return ftp * (BASE_SHARE + RISE_SHARE * d / d_ref)


## The sled's need now, in watts.
func required_watts() -> float:
	return required_at(distance)


## The need as the HUD shows it (whole watts): the widget and the ride metrics read this.
func shown_need() -> int:
	return roundi(required_watts())


## Metres as the HUD shows them (floored), so the hero, the bar and the flag agree.
static func shown_m(metres: float) -> int:
	return floori(metres + 0.0001)


## The speed the sled heads for with `power` at `d` metres (DESIGN.md "Speed").
func target_speed(power: float, d: float) -> float:
	var gap := (power - required_at(d)) / ftp
	return V_MAX * sqrt(clampf(gap / G_FULL, 0.0, G_CAP))


## 0 at the sled's rear, 1 at its front: where the weight box sits (it reaches the front at the
## Full Pull line).
func box_t() -> float:
	return clampf(distance / full_m, 0.0, 1.0)


## How close the sled is to stalling, 0-1 (the stall clock against STALL_SEC).
func stall_t() -> float:
	return clampf(stall_sec / STALL_SEC, 0.0, 1.0)


## A pull's points: its distance, plus the bonus for a Full Pull (before the effort multiplier).
static func pull_points(metres: float, full: bool) -> float:
	return metres * POINTS_PER_M + (FULL_PULL_BONUS if full else 0.0)


## The star thresholds (best-pull points) for a sled with this d_ref.
static func star_thresholds_for(d_ref_m: float) -> Array:
	return STAR_SHARES.map(func(s: float) -> int: return roundi(s * d_ref_m * POINTS_PER_M))


func is_done() -> bool:
	return phase == Phase.DONE


## Advances by `delta` seconds. `power`: the bike's watts (raw; smoothed here). `clock_sec`: the
## segment's gameplay seconds so far (for the timed ride and the overtime guard).
## `sensors_ok` false freezes the sled and the stall clock. Returns the events ({type: …}):
## "set" (pull), "go" (pull), "board" (metres), "dig_in", "dig_in_clear", "best_near",
## "best_passed", "pull_end" (how, distance, sec, points, new_best, pull), "recovery" (sec,
## next_pull) and "done".
func step(delta: float, power: float, clock_sec := 0.0, sensors_ok := true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	last_points = 0.0
	if phase == Phase.DONE:
		return events
	if phase == Phase.PULL and _overtime(clock_sec):
		_end_pull("time", events)
		return events
	if not sensors_ok:
		return events
	smoothed_power += (power - smoothed_power) * (1.0 - exp(-delta / POWER_TAU))
	match phase:
		Phase.SET:
			phase_left -= delta
			if phase_left <= 0.0:
				phase = Phase.PULL
				events.append({"type": "go", "pull": pull_index})
		Phase.PULL:
			_step_pull(delta, events)
		Phase.RESULT:
			phase_left -= delta
			if phase_left <= 0.0:
				_after_result(clock_sec, events)
		Phase.RECOVERY:
			phase_left -= delta
			if phase_left <= 0.0:
				_begin_set()
				events.append({"type": "set", "pull": pull_index})
	return events


## Ends the ride now (the rider ended an open session mid-pull): a pull in progress counts as
## it stands. Returns its pull_end event, or {} between pulls.
func end_now() -> Dictionary:
	var events: Array[Dictionary] = []
	if phase == Phase.PULL:
		_end_pull("time", events)
	phase = Phase.DONE
	return events[0] if not events.is_empty() else {}


func _step_pull(delta: float, events: Array[Dictionary]) -> void:
	pull_sec += delta
	var target := target_speed(smoothed_power, distance)
	if target > speed:
		speed = minf(speed + ACCEL * delta, target)
	else:
		speed = maxf(speed - DECEL * delta, target)
	speed = maxf(speed, 0.0)
	var before := distance
	distance = minf(distance + speed * delta, full_m)
	last_points = (distance - before) * POINTS_PER_M
	if floori(distance / BOARD_EVERY) > floori(before / BOARD_EVERY):
		events.append({"type": "board", "metres": floori(distance / BOARD_EVERY) * BOARD_EVERY})
	_check_best(events)
	if distance >= full_m:
		_end_pull("full", events)
		return
	_step_stall(delta, events)


func _step_stall(delta: float, events: Array[Dictionary]) -> void:
	if not _started:
		_started = distance >= ROLLING_M or pull_sec >= GRACE_SEC
		if not _started:
			return
	if speed < CRAWL:
		stall_sec += delta
		if stall_sec >= WARN_SEC and not warned:
			warned = true
			events.append({"type": "dig_in"})
		if stall_sec >= STALL_SEC:
			_end_pull("stall", events)
	else:
		stall_sec = 0.0
		if warned:
			warned = false
			events.append({"type": "dig_in_clear"})


func _check_best(events: Array[Dictionary]) -> void:
	if _best_at_start <= 0.0:
		return
	if not _near_sent and distance >= _best_at_start - BEST_NEAR:
		_near_sent = true
		events.append({"type": "best_near"})
	if not _passed_sent and distance > _best_at_start:
		_passed_sent = true
		events.append({"type": "best_passed"})


func _overtime(clock_sec: float) -> bool:
	return duration > 0.0 and clock_sec >= duration * OVERTIME


func _end_pull(how: String, events: Array[Dictionary]) -> void:
	pulls_done += 1
	last_end = how
	var full := how == "full"
	if full:
		full_pulls += 1
	var new_best := distance > best_distance
	best_distance = maxf(best_distance, distance)
	if distance > best_pull_m:
		best_pull_m = distance
		best_pull_sec = pull_sec
	if warned:
		warned = false
	events.append({"type": "pull_end", "how": how, "distance": distance, "sec": pull_sec,
		"points": FULL_PULL_BONUS if full else 0.0, "new_best": new_best, "pull": pull_index})
	phase = Phase.RESULT
	phase_left = RESULT_SEC
	speed = 0.0


func _after_result(clock_sec: float, events: Array[Dictionary]) -> void:
	if not _another_pull(clock_sec):
		phase = Phase.DONE
		events.append({"type": "done"})
		return
	phase = Phase.RECOVERY
	phase_left = rest_sec()
	events.append({"type": "recovery", "sec": phase_left, "next_pull": pull_index + 1})


## The rest between pulls in this mode.
func rest_sec() -> float:
	return TIMED_REST_SEC if mode == "timed" else REST_SEC


## Whether another pull follows this one's result.
func _another_pull(clock_sec: float) -> bool:
	if last_end == "time" and duration > 0.0:
		return false  # the overtime guard: Kotlin's hard stop is close
	match mode:
		"rounds":
			return pulls_done < rounds
		"timed":
			return duration - clock_sec - rest_sec() >= MIN_PULL_LEFT
	return true


func _begin_set() -> void:
	phase = Phase.SET
	phase_left = SET_SEC
	pull_index += 1
	distance = 0.0
	speed = 0.0
	pull_sec = 0.0
	stall_sec = 0.0
	warned = false
	_started = false
	_near_sent = false
	_passed_sent = false
	_best_at_start = best_distance
