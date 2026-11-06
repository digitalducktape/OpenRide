class_name LaunchLogic
extends RefCounted
## Ready for Launch's rules (#82), apart from drawing so they're tested headless. DESIGN.md (this
## folder) is the source of every number here.
##
## Each round is one launch, an enum machine (godot-prompter state-machine, enum-based: the phases
## share one clock and run headless):
##   FUEL (steady effort fills the tank) → COUNT (T-10, keep spinning) → PUSH (all out: the climb
##   is power × the fuel multiplier) → COAST (momentum, an easy spin keeps it climbing) → RESULT
## then the next launch, until the slot, the rounds or the rider ends it. A slot's launches share
## its length evenly, so a 1:30 slot plays exactly one and no launch is ever cut off short.
##
## Altitude is `climb`, in climb units; `km_for` maps it to the kilometres on screen. Every point
## comes from climb gained while pedalling (`last_points`, which the scene awards), so a rider who
## doesn't pedal never scores. `step` returns events ({type: …}) for the scene's sounds and views.

enum Phase { FUEL, COUNT, PUSH, COAST, RESULT }

const DEFAULT_FTP := 150.0
## When the segment doesn't send them (Kotlin's GameCatalog sends all three).
const LINE_SHARE := {"easy": 0.45, "standard": 0.50, "hard": 0.55}
const FULL_SHARE := {"easy": 0.55, "standard": 0.60, "hard": 0.65}
const TARGET_SHARE := {"easy": 0.90, "standard": 1.05, "hard": 1.20}

## Power is smoothed with this time constant: a step is 86% in after 2 s. The bike reports about
## once a second. The ride panel shows this same figure, so the HUD agrees with the rules.
const SMOOTH_TAU := 1.0

## One launch: 90 s, so a 1:30 circuit slot plays one.
const LAUNCH_SEC := 90.0
const FUEL_SEC := 45.0
const COUNT_SEC := 10.0
const PUSH_SEC := 18.0
const COAST_SEC := 15.0
const RESULT_SEC := 2.0
## A slot that doesn't divide into 90 s launches spreads the spare time: this share into fuelling,
## the rest into the coast. Points scale with the launch's length, so stars per minute hold.
const SLACK_TO_FUEL := 0.6
const PUSH_WARN_SEC := 3.0  ## "ease off soon" comes this long before the push ends

## Holding `fuel_full_watts` fills the tank in this share of the fuelling (the headroom), and the
## flow is capped at FLOW_CAP × that rate, so the tank wants a steady effort, not a short sprint.
const FILL_SHARE := 0.9
const FLOW_CAP := 1.25
const FUEL_MIN_MULT := 0.5  ## an empty tank
const FUEL_MAX_MULT := 1.5  ## a full one

## The push. Climb a second = CLIMB_RATE × power share of the target × the fuel multiplier.
const CLIMB_RATE := 1.0
const PUSH_CAP := 1.3  ## power beyond this share of the target adds no climb
const LIFT_SHARE := 0.25  ## the clamps let go at this share of the target
const SPEED_TAU := 0.6  ## the rocket's speed eases to what the power asks for
const COAST_TAU := 3.0  ## momentum fades with this time constant
## Below this share of FTP the rider isn't pedalling: no climb, no points. The raw reading, so
## stopping stops the climb at once rather than after the smoothing.
const PEDAL_SHARE := 0.1

const POINTS_PER_CLIMB := 40.0
## Where each stage goes (climb units), the kilometres shown there, and the bonus. The stars
## (ReadyForLaunch.info) follow from these: the Moon caps a launch at 34 × 40 + 1100 = 2460.
const MILESTONES := [
	{"id": "clouds", "name": "Clouds", "at": 5.0, "km": 12.0, "bonus": 100.0},
	{"id": "edge", "name": "Edge of space", "at": 12.0, "km": 100.0, "bonus": 200.0},
	{"id": "orbit", "name": "Orbit", "at": 22.0, "km": 400.0, "bonus": 300.0},
	{"id": "moon", "name": "The Moon", "at": 34.0, "km": 384400.0, "bonus": 500.0},
]

var ftp := DEFAULT_FTP
var fuel_line := DEFAULT_FTP * 0.5  ## watts: fuel flows above this
var fuel_full := DEFAULT_FTP * 0.6  ## watts: held, this fills the tank
var target := DEFAULT_FTP * 1.05  ## watts: 1.0 of the push's power share

var phase := Phase.FUEL
var phase_left := 0.0  ## seconds left in this phase
var launch := 0  ## 1-based, the launch in progress
var planned := 0  ## launches in this segment; 0 is open-ended
var launch_sec := LAUNCH_SEC
var fuel_sec := FUEL_SEC
var coast_sec := COAST_SEC
var points_scale := 1.0
var finished := false  ## every planned launch has flown and the segment may end

var smoothed := 0.0  ## watts: what the rules use and the HUD shows
var fuel := 0.0  ## the tank, 0-1
var flowing := false  ## fuel is going in right now
var tank_full := false
var climb := 0.0  ## altitude, in climb units
var speed := 0.0  ## climb units a second
var lifted := false  ## the clamps let go this launch
var scrubbed := false  ## the push ended with the rocket still on the pad
var milestone := -1  ## the highest passed this launch (index into MILESTONES)
var last_points := 0.0  ## to award this step

## Stats.
var launches := 0  ## lifted off
var best_climb := 0.0
var peak_power := 0.0
var moons := 0

var _fuel_sum := 0.0
var _counted := 0  ## launches that reached the count
var _ends_itself := false  ## rounds end on the last launch; a timed slot holds for the timer
var _started := false
var _next_count := 0  ## the next whole second of the count to announce
var _warned_push := false


## `duration_sec` < 0 is open-ended; `rounds` > 0 flies that many launches and ends.
func _init(params := {}, difficulty := "standard", duration_sec := -1.0, rounds := 0) -> void:
	_ends_itself = rounds > 0
	ftp = maxf(float(params.get("ftp_watts", DEFAULT_FTP)), 1.0)
	fuel_line = float(params.get("fuel_line_watts", ftp * LINE_SHARE.get(difficulty, 0.5)))
	fuel_full = maxf(float(params.get("fuel_full_watts", ftp * FULL_SHARE.get(difficulty, 0.6))), fuel_line + 1.0)
	target = maxf(float(params.get("target_watts", ftp * TARGET_SHARE.get(difficulty, 1.05))), 1.0)
	if rounds > 0:
		planned = rounds
	elif duration_sec > 0.0:
		planned = maxi(1, floori(duration_sec / LAUNCH_SEC))
		launch_sec = maxf(duration_sec / planned, LAUNCH_SEC)
	var slack := launch_sec - LAUNCH_SEC
	fuel_sec = FUEL_SEC + slack * SLACK_TO_FUEL
	coast_sec = COAST_SEC + slack * (1.0 - SLACK_TO_FUEL)
	points_scale = launch_sec / LAUNCH_SEC
	_begin_launch()


## The multiplier the climb gets from the tank: 0.5 empty, 1.5 full.
func fuel_mult() -> float:
	return lerpf(FUEL_MIN_MULT, FUEL_MAX_MULT, fuel)


## The tank as a whole percentage (the status widget's and the stats' figure).
func fuel_pct() -> int:
	return roundi(fuel * 100.0)


## Seconds until T-0; 0 from the push on.
func t_minus() -> float:
	match phase:
		Phase.FUEL:
			return phase_left + COUNT_SEC
		Phase.COUNT:
			return phase_left
	return 0.0


## The power share of the push's target that counts toward the climb.
func push_share() -> float:
	return clampf(smoothed / target, 0.0, PUSH_CAP)


## Kilometres on screen for a climb: linear to the clouds, then a geometric step per milestone,
## so a rider sees a steady climb and the Moon really is 384,400 km away.
static func km_for(c: float) -> float:
	var prev_at := 0.0
	var prev_km := 0.0
	for m: Dictionary in MILESTONES:
		var at: float = m.at
		var km_at: float = m.km
		if c < at:
			var t := (c - prev_at) / (at - prev_at)
			return lerpf(prev_km, km_at, t) if prev_km <= 0.0 else prev_km * pow(km_at / prev_km, t)
		prev_at = at
		prev_km = km_at
	return prev_km


func km() -> float:
	return km_for(climb)


func best_km() -> float:
	return km_for(best_climb)


## The tank's average at T-0 over the launches that got there, as a whole percentage.
func fuel_pct_avg() -> int:
	return roundi(_fuel_sum / maxi(_counted, 1) * 100.0)


## The name of the farthest place this launch reached, "" below the clouds.
func reached_name() -> String:
	return "" if milestone < 0 else str(MILESTONES[milestone].name)


## One frame. `power` is the raw reading; `frozen` is sensor loss (nothing counts, the clock runs).
func step(delta: float, power: float, frozen := false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	last_points = 0.0
	if finished:
		return events
	if not frozen:
		_smooth(delta, power)
		peak_power = maxf(peak_power, smoothed)
	phase_left -= delta
	match phase:
		Phase.FUEL:
			if not frozen:
				_fuel_step(delta, events)
			if phase_left <= 0.0:
				_enter_count(events)
		Phase.COUNT:
			_count_step(events)
		Phase.PUSH:
			_push_step(delta, power, frozen, events)
		Phase.COAST:
			_coast_step(delta, power, frozen, events)
		Phase.RESULT:
			if phase_left <= 0.0:
				_end_launch(events)
	return events


func _smooth(delta: float, power: float) -> void:
	if not _started:
		_started = true
		smoothed = power  # the rider is already spinning behind the intro card
		return
	smoothed += (power - smoothed) * (1.0 - exp(-delta / SMOOTH_TAU))


func _fuel_step(delta: float, events: Array[Dictionary]) -> void:
	var was := flowing
	flowing = smoothed > fuel_line and not tank_full
	if flowing != was:
		events.append({"type": "fuel_on" if flowing else "fuel_off"})
	if not flowing:
		return
	var full_rate := 1.0 / (fuel_sec * FILL_SHARE)
	var rate := (smoothed - fuel_line) / (fuel_full - fuel_line) * full_rate
	fuel = minf(fuel + minf(rate, full_rate * FLOW_CAP) * delta, 1.0)
	if fuel >= 1.0:
		tank_full = true
		flowing = false
		events.append({"type": "fuel_off"})
		events.append({"type": "tank_full"})


func _enter_count(events: Array[Dictionary]) -> void:
	phase = Phase.COUNT
	phase_left += COUNT_SEC
	flowing = false
	_next_count = int(COUNT_SEC)
	_fuel_sum += fuel
	_counted += 1
	events.append({"type": "fuel_off"})
	events.append({"type": "count_start", "fuel": fuel_pct(), "mult": fuel_mult()})
	_count_step(events)


func _count_step(events: Array[Dictionary]) -> void:
	while _next_count >= 1 and phase_left <= _next_count:
		events.append({"type": "count", "n": _next_count})
		_next_count -= 1
	if phase_left <= 0.0:
		phase = Phase.PUSH
		phase_left += PUSH_SEC
		_warned_push = false
		events.append({"type": "ignition"})


func _push_step(delta: float, power: float, frozen: bool, events: Array[Dictionary]) -> void:
	var pedalling := not frozen and power >= ftp * PEDAL_SHARE
	var share := push_share() if pedalling else 0.0
	if not lifted and share >= LIFT_SHARE:
		lifted = true
		launches += 1
		events.append({"type": "liftoff"})
	if lifted:
		var want := CLIMB_RATE * share * fuel_mult()
		speed += (want - speed) * (1.0 - exp(-delta / SPEED_TAU))
		if pedalling:
			_rise(speed * delta, events)
	if phase != Phase.PUSH:
		return  # the Moon ended the push early
	if not _warned_push and phase_left <= PUSH_WARN_SEC:
		_warned_push = true
		if lifted:
			events.append({"type": "push_ending"})
	if phase_left <= 0.0:
		_enter_coast(events)


func _coast_step(delta: float, power: float, frozen: bool, events: Array[Dictionary]) -> void:
	speed *= exp(-delta / COAST_TAU)
	if lifted and not frozen and power >= ftp * PEDAL_SHARE:
		_rise(speed * delta, events)
	if phase_left <= 0.0:
		phase = Phase.RESULT
		phase_left += RESULT_SEC
		events.append({"type": "result", "km": km(), "reached": reached_name(), "scrubbed": scrubbed})


func _enter_coast(events: Array[Dictionary]) -> void:
	phase = Phase.COAST
	phase_left += coast_sec
	scrubbed = not lifted
	events.append({"type": "scrub" if scrubbed else "coast"})


## Climbs by `by` (capped at the Moon), scoring it and passing milestones.
func _rise(by: float, events: Array[Dictionary]) -> void:
	var top: float = MILESTONES[-1].at
	var gained := minf(by, top - climb)
	if gained <= 0.0:
		return
	climb += gained
	best_climb = maxf(best_climb, climb)
	last_points += gained * POINTS_PER_CLIMB * points_scale
	while milestone + 1 < MILESTONES.size() and climb >= float(MILESTONES[milestone + 1].at) - 0.0001:
		milestone += 1
		var bonus: float = MILESTONES[milestone].bonus
		last_points += bonus * points_scale
		events.append({"type": "milestone", "index": milestone, "id": MILESTONES[milestone].id,
			"name": MILESTONES[milestone].name, "bonus": roundi(bonus * points_scale)})
	if climb < top - 0.0001:
		return
	moons += 1
	if phase == Phase.PUSH:
		# Arrived: the push's remaining seconds become rest, so the launch keeps its length.
		phase = Phase.COAST
		phase_left += coast_sec
		events.append({"type": "coast", "arrived": true})


func _end_launch(events: Array[Dictionary]) -> void:
	if planned > 0 and launch >= planned:
		if _ends_itself:
			finished = true
			events.append({"type": "finished"})
		else:
			phase_left = 3600.0  # the slot's timer ends it
		return
	_begin_launch()
	events.append({"type": "next_launch", "launch": launch})


func _begin_launch() -> void:
	launch += 1
	phase = Phase.FUEL
	phase_left = fuel_sec
	fuel = 0.0
	flowing = false
	tank_full = false
	climb = 0.0
	speed = 0.0
	lifted = false
	scrubbed = false
	milestone = -1
