class_name EffortMeter
extends RefCounted
## The effort multiplier's maths, kept pure so it's tested headless (epic #31, "Effort
## multiplier"). The `Effort` autoload feeds it the live frame; games only call
## `Effort.award(points)`.
##
##   multiplier = 1 + 0.5 × clamp((resistance − 30) / 30, 0, 1)
##
## 1.0× at resistance ≤ 30%, 1.5× at ≥ 60%, only while cadence ≥ 60 rpm (the grinding guard),
## and always 1.0× in segments with `effort: false`.

const RESISTANCE_FLOOR := 30.0  ## at or below: 1.0×
const RESISTANCE_SPAN := 30.0  ## 30 → 60% resistance spans the whole bonus
const MAX_BONUS := 0.5  ## 1.5× at the top
const MIN_CADENCE := 60.0  ## grinding guard, rpm

var enabled := false  ## the segment's `effort` flag
var score := 0.0  ## points awarded this segment, multiplier included
var multiplier := 1.0  ## the latest sample

var _weighted_sum := 0.0
var _sampled_sec := 0.0


## The multiplier for these inputs, whether or not a segment is running.
static func multiplier_for(resistance: float, cadence: float, effort_on: bool) -> float:
	if not effort_on or cadence < MIN_CADENCE:
		return 1.0
	return 1.0 + MAX_BONUS * clampf((resistance - RESISTANCE_FLOOR) / RESISTANCE_SPAN, 0.0, 1.0)


## A new segment: zero the score and the average.
func reset(effort_on: bool) -> void:
	enabled = effort_on
	score = 0.0
	multiplier = 1.0
	_weighted_sum = 0.0
	_sampled_sec = 0.0


## One gameplay frame: updates `multiplier` and the time-weighted average. Call it only while
## scoring counts (playing, not paused, sensors ok).
func sample(delta: float, resistance: float, cadence: float) -> float:
	multiplier = multiplier_for(resistance, cadence, enabled)
	if delta > 0.0:
		_weighted_sum += multiplier * delta
		_sampled_sec += delta
	return multiplier


## Adds `points` × the current multiplier to the score and returns what was added.
func award(points: float) -> float:
	var awarded := points * multiplier
	score += awarded
	return awarded


## `stats.effort_avg`: the time-weighted average multiplier over the sampled gameplay, 1.0 when
## nothing was sampled.
func average() -> float:
	return _weighted_sum / _sampled_sec if _sampled_sec > 0.0 else 1.0
