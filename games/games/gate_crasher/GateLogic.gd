class_name GateLogic
extends RefCounted
## Gate Crasher's rules (#80), headless and tested by `gate_crasher_logic_test`. DESIGN.md has the
## reasoning and the tuning. The scene feeds it one `step` a frame and reacts to its events.
##
## The rider pedals to canter round the course and stands at each take-off line. The camera's
## StandingDetector reports a stand `lag` (0.5 s) after it happens and a sit 1.5 s after, so:
##   - the window is measured in detection time: a stand on the line reads `lag` later, in the
##     window's middle, and `window_sec` is the rider's real margin, half either side of the line;
##   - a fence is only judged on a stand that STARTS in the window, so riding out of the saddle
##     clears nothing;
##   - fences are at least MIN_GAP_SEC apart at top speed, so the sit reads before the next line.
##
## Events (`step` returns them in order), all Dictionaries with a `type`:
##   beat {n}          the countdown, n = 3, 2, 1, at that many seconds to the line
##   sit_first         the rider is up at the first beat: sit, or the fence is early
##   line              the line is under the horse
##   stand_ok          a stand read in the window: the fence will be clear
##   jump, land        the horse leaves and meets the ground (`arc_height` has the arc)
##   clear {points, fence}          over the fence
##   fault {why, penalty, fence}    a rail down; why is "early" or "late"
##   no_pedal {fence}  over the fence without pedalling: it scores nothing
##   round_end {clear, bonus, round}
##   circle, circle_end  the camera lost the rider, and the circle back to the approach
##   done              the last round of a rounds ride is over

enum Phase { RIDE, CIRCLE, DONE }
enum Zone { APPROACH, WINDOW, JUDGED }
enum Call { NONE, CLEAR, EARLY, LATE, NO_PEDAL }

## Per difficulty, for a segment without Kotlin's params: pace as a share of FTP and the window.
const LEVELS := {
	"easy": {"pace_share": 0.25, "window_sec": 1.4},
	"standard": {"pace_share": 0.32, "window_sec": 1.2},
	"hard": {"pace_share": 0.42, "window_sec": 1.2},
}
const DEFAULT_FTP := 200.0
const FENCES := 8  ## a round
const STAND_LAG := 0.5  ## StandingDetector's standEnterMs
const SIT_LAG := 1.5  ## StandingDetector's standExitMs
const MIN_GAP_SEC := 5.0  ## between fences at top speed

const V_WALK := 4.5  ## m/s, the slowest canter
const V_PACE := 8.5  ## at pace_watts
const V_MAX := 10.0  ## at MAX_SHARE of pace_watts; the fence spacing depends on this cap
const MAX_SHARE := 1.3
const MOVE_SHARE := 0.1  ## of pace_watts, under which the horse stops
const PEDAL_RPM := 30.0
const ACCEL := 2.0
const DECEL := 2.5
const POWER_TAU := 1.5  ## seconds: the bike reads about once a second

const LINE_GAP := 18.0  ## metres from the take-off line to the fence
const TAKEOFF := 4.0  ## metres from the fence where the horse leaves the ground, and lands after
const JUMP_CLEAR := 1.45  ## metres: the arc's top over a clear fence...
const JUMP_FAULT := 0.75  ## ...and over one that loses a rail
const BEATS := [3.0, 2.0, 1.0]  ## seconds to the line

const CLEAR_POINTS := 50.0
const METRE_POINTS := 0.25
const ROUND_BONUS := 100.0
const FAULT_PENALTY := 30.0
const FAULTS_PER_RAIL := 4

const CIRCLE_RADIUS := 7.0
const CIRCLE_SPEED := 6.0
const REAPPROACH_SEC := 3.2  ## the circle comes out this far (at pace) from the line

var pace_watts: float
var window_sec: float
var lag: float
var fences: int
var spacing: float
var mode: String  ## "rounds", "timed" or "open"
var rounds: int

var phase := Phase.RIDE
var distance := 0.0  ## metres ridden, along the loop
var speed := 0.0
var smooth_power := 0.0
var last_points := 0.0  ## this step's points for ground covered
var pedalling := false

var fence := 0  ## the next fence, counted from the ride's start
var zone := Zone.APPROACH
var call := Call.NONE
var window_left := 0.0
var circle_angle := 0.0  ## radians round the circle, 0 on the course

var round_index := 1
var results: Array[int] = []  ## this round's Calls, by fence
var clears := 0
var fences_done := 0
var faults := 0
var clear_rounds := 0
var rounds_done := 0
var ride_sec := 0.0
var power_sum := 0.0

var _beats_done := 0
var _was_standing := false
var _arc_from := -1.0
var _arc_apex := 0.0
var _circle_from := 0.0
var _circle_to := 0.0


func _init(p: Dictionary = {}, level := "standard", ride_mode := "open", ride_rounds := 1) -> void:
	var defaults: Dictionary = LEVELS.get(level, LEVELS.standard)
	pace_watts = maxf(float(p.get("pace_watts", float(p.get("ftp_watts", DEFAULT_FTP)) * defaults.pace_share)), 1.0)
	window_sec = float(p.get("window_sec", defaults.window_sec))
	lag = float(p.get("stand_lag_sec", STAND_LAG))
	fences = mini(maxi(int(p.get("fences", FENCES)), 1), max_fences())
	spacing = GateCourse.LENGTH / fences
	mode = ride_mode
	rounds = maxi(ride_rounds, 1)


## The most fences a lap can hold and keep them MIN_GAP_SEC apart at V_MAX.
static func max_fences() -> int:
	return floori(GateCourse.LENGTH / (V_MAX * MIN_GAP_SEC))


## Where fence `k` stands, counted from the ride's start. The last of a lap is on the start.
func fence_s(k: int) -> float:
	return (k + 1) * spacing


func line_s(k: int) -> float:
	return fence_s(k) - LINE_GAP


## The fence's number in this round, from 1.
func fence_in_round() -> int:
	return fence % fences + 1


## Seconds to the next line at this speed (0 once it's passed, INF while halted).
func eta() -> float:
	if speed < 0.5:
		return INF
	return maxf(line_s(fence) - distance, 0.0) / speed


## Seconds before the line that the window opens: a stand read then began half a window early.
func window_lead() -> float:
	return window_sec / 2.0 - lag


## The canter a smoothed `power` asks for.
func target_speed(power: float) -> float:
	var share := power / pace_watts
	if share < MOVE_SHARE:
		return 0.0
	if share <= 1.0:
		return lerpf(V_WALK, V_PACE, (share - MOVE_SHARE) / (1.0 - MOVE_SHARE))
	return lerpf(V_PACE, V_MAX, minf((share - 1.0) / (MAX_SHARE - 1.0), 1.0))


## The horse's height off the ground now (metres).
func arc_height() -> float:
	if _arc_from < 0.0:
		return 0.0
	var u := clampf((distance - _arc_from) / (2.0 * TAKEOFF), 0.0, 1.0)
	return 4.0 * u * (1.0 - u) * _arc_apex


func avg_power() -> float:
	return power_sum / ride_sec if ride_sec > 0.0 else 0.0


func step(delta: float, power: float, cadence: float, standing: bool, camera_ok: bool, sensors_ok: bool) -> Array:
	var events := []
	last_points = 0.0
	var rose := standing and not _was_standing
	_was_standing = standing
	if not sensors_ok:
		return events  # everything holds until the bike reads again
	pedalling = cadence >= PEDAL_RPM
	smooth_power += (power - smooth_power) * (1.0 - exp(-delta / POWER_TAU))
	if pedalling:
		ride_sec += delta
		power_sum += power * delta
	if phase == Phase.DONE:
		speed = move_toward(speed, 0.0, DECEL * delta)
		distance += speed * delta
		return events
	if phase == Phase.RIDE and not camera_ok:
		_start_circle(events)
	if phase == Phase.CIRCLE:
		_step_circle(delta, camera_ok, events)
		return events
	var target := target_speed(smooth_power) if pedalling else 0.0
	speed = move_toward(speed, target, (ACCEL if target > speed else DECEL) * delta)
	var moved := speed * delta
	distance += moved
	if pedalling:
		last_points = moved * METRE_POINTS
	_step_arc(events)
	_step_fence(delta, standing, rose, events)
	return events


func _step_fence(delta: float, standing: bool, rose: bool, events: Array) -> void:
	var left := eta()
	while _beats_done < BEATS.size() and left <= BEATS[_beats_done]:
		events.append({"type": "beat", "n": roundi(BEATS[_beats_done])})
		if _beats_done == 0 and standing:
			events.append({"type": "sit_first"})
		_beats_done += 1
	if zone == Zone.APPROACH and speed >= 1.0 and left <= window_lead():
		zone = Zone.WINDOW
		window_left = window_sec
		if standing and not rose:
			_judge(Call.EARLY)
	if zone == Zone.WINDOW:
		if rose:
			_judge(Call.CLEAR)
			events.append({"type": "stand_ok"})
		else:
			window_left -= delta
			if window_left <= 0.0:
				_judge(Call.LATE)
	if _beats_done == BEATS.size() and distance >= line_s(fence):
		_beats_done += 1
		events.append({"type": "line"})
	if _arc_from < 0.0 and distance >= fence_s(fence) - TAKEOFF:
		_arc_from = fence_s(fence) - TAKEOFF
		_arc_apex = JUMP_CLEAR if call == Call.CLEAR else JUMP_FAULT
		events.append({"type": "jump"})
	if distance >= fence_s(fence):
		_cross(events)


func _judge(result: Call) -> void:
	call = result
	zone = Zone.JUDGED


## The horse is over the fence: its result counts now.
func _cross(events: Array) -> void:
	var at := fence % fences
	var result := call
	if result == Call.NONE:
		result = Call.LATE
	if not pedalling:
		result = Call.NO_PEDAL
	fences_done += 1
	results.append(result)
	match result:
		Call.CLEAR:
			clears += 1
			events.append({"type": "clear", "points": CLEAR_POINTS, "fence": at})
		Call.NO_PEDAL:
			events.append({"type": "no_pedal", "fence": at})
		_:
			faults += FAULTS_PER_RAIL
			events.append({"type": "fault", "why": "early" if result == Call.EARLY else "late",
				"penalty": FAULT_PENALTY, "fence": at})
	fence += 1
	zone = Zone.APPROACH
	call = Call.NONE
	_beats_done = 0
	if fence % fences == 0:
		_end_round(events)


func _end_round(events: Array) -> void:
	var clean := results.all(func(r: int) -> bool: return r == Call.CLEAR)
	if clean:
		clear_rounds += 1
	rounds_done += 1
	events.append({"type": "round_end", "clear": clean, "bonus": ROUND_BONUS if clean else 0.0, "round": round_index})
	if mode == "rounds" and rounds_done >= rounds:
		phase = Phase.DONE
		events.append({"type": "done"})
		return
	round_index += 1
	results.clear()


func _step_arc(events: Array) -> void:
	if _arc_from >= 0.0 and distance >= _arc_from + 2.0 * TAKEOFF:
		_arc_from = -1.0
		events.append({"type": "land"})


## The camera lost the rider: no fence can be judged, so the horse circles. A fence already in
## play starts over, and the circle comes out far enough back for a whole countdown.
func _start_circle(events: Array) -> void:
	phase = Phase.CIRCLE
	circle_angle = 0.0
	zone = Zone.APPROACH
	call = Call.NONE
	_beats_done = 0
	_arc_from = -1.0
	_circle_from = distance
	_circle_to = minf(distance, line_s(fence) - REAPPROACH_SEC * V_PACE)
	events.append({"type": "circle"})


## Round the circle at a steady canter while pedalling, sliding back along the course as it goes.
## It only ends on the course, facing the way it came, so a rider seen again finishes the turn.
func _step_circle(delta: float, camera_ok: bool, events: Array) -> void:
	speed = move_toward(speed, CIRCLE_SPEED if pedalling else 0.0, DECEL * delta)
	if camera_ok and circle_angle == 0.0 and speed < 0.5:
		_end_circle(events)  # halted and never left the course
		return
	circle_angle += speed / CIRCLE_RADIUS * delta
	distance = lerpf(_circle_from, _circle_to, minf(circle_angle / TAU, 1.0))
	if circle_angle >= TAU:
		_circle_from = _circle_to
		circle_angle -= TAU
		if camera_ok:
			_end_circle(events)


func _end_circle(events: Array) -> void:
	phase = Phase.RIDE
	circle_angle = 0.0
	events.append({"type": "circle_end"})
