class_name SafeLogic
extends RefCounted
## Safe Cracker's rules (#41), apart from drawing so they're tested headless. Dial the resistance
## knob to each number of a combination and hold it there to click a tumbler; crack the safe and
## the next, harder one comes. Pedal too hard (power over the cap for ALARM_AFTER seconds) and
## the alarm trips and resets the tumbler; pedal under the cadence floor and the dial loses
## power, which pauses the hold.
##
## The resistance reading lags the knob (the bike's board reports it late), so a slip off the
## target doesn't reset the hold at once: it keeps its progress for GRACE_SEC, then fades.

enum Phase { CRACKING, OPENING }

## Per difficulty: the tolerance (±), the hold time in seconds, and the combination length of a
## Just Ride's first safe.
const LEVELS := {
	"easy": {"tolerance": 3.0, "hold_sec": 1.2, "length": 3},
	"standard": {"tolerance": 2.0, "hold_sec": 1.5, "length": 4},
	"hard": {"tolerance": 2.0, "hold_sec": 2.0, "length": 5},
}
const CIRCUIT_LENGTH := 3
const MAX_LENGTH := 6
const MIN_GAP := 6.0  ## each number is at least this far from the one before
const DEFAULT_RES_MIN := 15.0
const DEFAULT_RES_MAX := 40.0
const DEFAULT_CADENCE_MIN := 60.0
const GRACE_SEC := 0.4  ## a slip off target this short costs nothing (the knob's lag)
const FADE_RATE := 1.5  ## after the grace, progress drains this many times as fast as it filled
## The alarm is easy-going on purpose (the first version tripped for ordinary pedalling at the
## resistances the dial asks for): it trips when power, smoothed over about a second, stays
## over ALARM_HEADROOM times the recovery cap for ALARM_AFTER seconds.
const ALARM_HEADROOM := 1.25
const ALARM_AFTER := 2.5
const POWER_SMOOTHING_SEC := 1.0
const ALARM_SHOW_SEC := 2.5
const OPEN_SEC := 2.6  ## the door swings open this long
const HIDDEN_FROM_VAULT := 4
const TIME_PENALTY := 5.0  ## points off a vault per second
const ALARM_PENALTY := 100.0
const START_POINTS := 1000.0
const COMPLETION_BONUS := 200.0
## Closer than this to the target counts as "warm" for the proximity tick; the tick speeds up as
## the reading closes in.
const WARM_RANGE := 25.0

var phase := Phase.CRACKING
var vault := 1  ## the safe being cracked, from 1
var combo: Array[int] = []
var tumbler := 0  ## the next tumbler to click
var tolerance := 2.0
var hold_sec := 1.5
var hidden := false  ## the target number isn't shown (the rider follows the proximity tick)
var progress := 0.0  ## seconds held on the target
var reading := 0.0  ## the last resistance reading
var powered := true  ## cadence at or above the floor
var in_tolerance := false
var cracked := 0
var total_alarms := 0
var alarms := 0  ## this vault's
var alarm_left := 0.0  ## the alarm light's remaining seconds
var over_sec := 0.0
var smoothed_power := -1.0  ## power smoothed over POWER_SMOOTHING_SEC; -1 before the first sample
var vault_sec := 0.0
var fastest := -1.0
var phase_left := 0.0
var power_cap := 0.0  ## watts; 0 = no cap
var cadence_min := DEFAULT_CADENCE_MIN
var res_min := DEFAULT_RES_MIN
var res_max := DEFAULT_RES_MAX
var avg_power_sum := 0.0
var avg_power_sec := 0.0

var _rng := RandomNumberGenerator.new()
var _difficulty := "standard"
var _params := {}
var _circuit := false
var _grace_left := 0.0


func _init(seed_value: int, difficulty := "standard", params := {}, in_circuit := false) -> void:
	_rng.seed = seed_value
	_difficulty = difficulty if LEVELS.has(difficulty) else "standard"
	_params = params
	_circuit = in_circuit
	power_cap = float(params.get("power_cap_watts", params.get("power_cap", 0.0)))
	cadence_min = float(params.get("cadence_min", DEFAULT_CADENCE_MIN))
	res_min = float(params.get("res_min", DEFAULT_RES_MIN))
	res_max = maxf(float(params.get("res_max", DEFAULT_RES_MAX)), res_min + 1.0)
	_start_vault(1)


## The number to dial now.
func target() -> int:
	return combo[mini(tumbler, combo.size() - 1)]


func is_open() -> bool:
	return phase == Phase.OPENING


## How close the reading is to the target, 0 (far) to 1 (on it): what the proximity tick follows.
func closeness() -> float:
	return clampf(1.0 - absf(reading - float(target())) / WARM_RANGE, 0.0, 1.0)


func avg_power() -> float:
	return avg_power_sum / avg_power_sec if avg_power_sec > 0.0 else 0.0


## Points for a vault cracked in `seconds` with `alarm_count` alarms.
static func vault_points(seconds: float, alarm_count: int) -> float:
	return maxf(START_POINTS - TIME_PENALTY * seconds - ALARM_PENALTY * alarm_count, 0.0) + COMPLETION_BONUS


## Advances by `delta` seconds with the resistance reading (0-100), cadence (rpm) and power (W).
## Returns the events ({type: ...}): "tumbler" (index), "alarm", "vault_open" (vault, seconds,
## alarms, points) and "new_vault" (vault, length).
func step(delta: float, resistance: float, cadence: float, power: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	reading = resistance
	powered = cadence >= cadence_min
	alarm_left = maxf(alarm_left - delta, 0.0)
	smoothed_power = power if smoothed_power < 0.0 else lerpf(smoothed_power, power, minf(delta / POWER_SMOOTHING_SEC, 1.0))
	avg_power_sum += power * delta
	avg_power_sec += delta
	if phase == Phase.OPENING:
		phase_left -= delta
		if phase_left <= 0.0:
			_start_vault(vault + 1)
			events.append({"type": "new_vault", "vault": vault, "length": combo.size()})
		return events
	vault_sec += delta
	_update_alarm(delta, events)
	_update_hold(delta, events)
	return events


func _update_alarm(delta: float, events: Array[Dictionary]) -> void:
	if power_cap > 0.0 and smoothed_power > power_cap * ALARM_HEADROOM:
		over_sec += delta
		if over_sec >= ALARM_AFTER:
			over_sec = 0.0
			alarms += 1
			total_alarms += 1
			alarm_left = ALARM_SHOW_SEC
			progress = 0.0
			_grace_left = 0.0
			events.append({"type": "alarm"})
	else:
		over_sec = maxf(over_sec - delta * 2.0, 0.0)


func _update_hold(delta: float, events: Array[Dictionary]) -> void:
	in_tolerance = absf(reading - float(target())) <= tolerance
	if not powered:
		return  # an unpowered dial pauses the hold
	if in_tolerance:
		_grace_left = GRACE_SEC
		progress += delta
		if progress >= hold_sec:
			_click(events)
	elif _grace_left > 0.0:
		_grace_left -= delta  # the reading may just be late: keep the progress for a moment
	else:
		progress = maxf(progress - delta * FADE_RATE, 0.0)


func _click(events: Array[Dictionary]) -> void:
	events.append({"type": "tumbler", "index": tumbler})
	tumbler += 1
	progress = 0.0
	_grace_left = 0.0
	if tumbler < combo.size():
		return
	cracked += 1
	var points := vault_points(vault_sec, alarms)
	if fastest < 0.0 or vault_sec < fastest:
		fastest = vault_sec
	events.append({"type": "vault_open", "vault": vault, "seconds": vault_sec, "alarms": alarms, "points": points})
	phase = Phase.OPENING
	phase_left = OPEN_SEC


func _start_vault(number: int) -> void:
	vault = number
	phase = Phase.CRACKING
	tumbler = 0
	progress = 0.0
	alarms = 0
	over_sec = 0.0
	vault_sec = 0.0
	_grace_left = 0.0
	var level: Dictionary = LEVELS[_difficulty]
	var base_length := int(_params.get("combo_length", CIRCUIT_LENGTH if _circuit else level.length))
	var length := mini(base_length + (number - 1) / 2, MAX_LENGTH)
	tolerance = maxf(float(level.tolerance) - 0.25 * (number - 1), 1.0)
	hold_sec = maxf(float(level.hold_sec) - 0.1 * (number - 1), 0.9)
	hidden = bool(_params.get("hidden_target", false)) or _difficulty == "hard" or number >= HIDDEN_FROM_VAULT
	combo = _draw_combination(length)


## `length` numbers in [res_min, res_max], each at least MIN_GAP from the one before.
func _draw_combination(length: int) -> Array[int]:
	var numbers: Array[int] = []
	var lo := ceili(res_min)
	var hi := floori(res_max)
	while numbers.size() < length:
		var pick := _rng.randi_range(lo, hi)
		var previous := numbers[-1] if not numbers.is_empty() else -1000
		if absi(pick - previous) >= int(MIN_GAP):
			numbers.append(pick)
		elif hi - lo < int(MIN_GAP) * 2:
			# A range too narrow to find a number by luck: alternate its two ends.
			numbers.append(hi if previous <= (lo + hi) / 2 else lo)
	return numbers
