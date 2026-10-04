extends Node
## Scoring with the effort multiplier: higher resistance scores more (epic #31, "Effort
## multiplier"; the maths is in `EffortMeter`).
##
## Games award points only through `Effort.award(points)`, so none can forget the multiplier
## or the freezes. Points count only during gameplay, while the session isn't paused and the
## sensors are ok (the "sensors not detected" banner freezes scoring). `Session` starts each
## segment here, switches scoring on and off, and reads `score` and `average()` for the result.

signal awarded(points: float)  ## after every award that counted, multiplier included

## Whether this segment's points are multiplied (its `effort` flag). The HUD badge shows only
## when true.
var enabled: bool:
	get:
		return _meter.enabled
## The current multiplier, 1.0-1.5.
var multiplier: float:
	get:
		return _meter.multiplier
## The segment's score so far.
var score: float:
	get:
		return _meter.score

var _meter := EffortMeter.new()
var _live := false


func _ready() -> void:
	# After InputBus (-1000) has read the frame, before any game awards points.
	process_priority = -900
	process_mode = Node.PROCESS_MODE_ALWAYS


## A new segment (Session calls this on segment_started): zero the score and the average.
func begin_segment(effort_on: bool) -> void:
	_meter.reset(effort_on)
	_live = false


## Session turns scoring on for gameplay, and off for the intro card, the ending and after.
func set_live(live: bool) -> void:
	_live = live


## Whether an award would count right now.
func is_scoring() -> bool:
	return _live and not Session.paused and InputBus.sensors_ok


## Awards `points` × the multiplier and returns what counted: 0 while scoring is frozen.
func award(points: float) -> float:
	if points == 0.0 or not is_scoring():
		return 0.0
	var added := _meter.award(points)
	awarded.emit(added)
	return added


## Takes `points` off the score, without the multiplier (a penalty, e.g. Dodge Ball's -50 for
## a hit with the shield down). Returns what was taken: 0 while scoring is frozen. The score
## never drops below zero.
func penalize(points: float) -> float:
	if points <= 0.0 or not is_scoring():
		return 0.0
	var taken := minf(points, _meter.score)
	_meter.score -= taken
	return taken


## `stats.effort_avg`: the average multiplier over the segment's scoring time.
func average() -> float:
	return _meter.average()


func _process(delta: float) -> void:
	if is_scoring():
		_meter.sample(delta, InputBus.resistance, InputBus.cadence)
	else:
		# Keep the badge truthful while frozen, without counting the time.
		_meter.multiplier = EffortMeter.multiplier_for(InputBus.resistance, InputBus.cadence, _meter.enabled)
