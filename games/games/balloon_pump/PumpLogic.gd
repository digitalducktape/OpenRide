class_name PumpLogic
extends RefCounted
## Balloon Pump's rules (#76), apart from drawing so they're tested headless. The rider's watts,
## smoothed over about 2 s, are the pump's air. A balloon on the nozzle takes air only while the
## smoothed power is over its push line, which rises as it fills (steepest at the end); below the
## line it leaks back slowly. A full balloon ties off and the next one goes on. DESIGN.md (this
## folder) is the design record: every number here is explained there.
##
## Two modes: "max" (fill as many as you can) and "race" (fill `race_target` balloons within a
## heat of `heat_sec`). With heats, a heat ends on the target (race) or the clock, a short break
## follows, and after `heats_total` heats (0 = no limit) the game is over. "max" without heats is
## one long run that never ends by itself.
##
## A small enum FSM (godot-prompter state-machine: enum-based, under 5 states, no enter/exit
## logic worth nodes): FILL → TIE → LOAD → FILL, with BREAK between heats and OVER at the end.

enum Phase { FILL, TIE, LOAD, BREAK, OVER }

const DEFAULT_FTP := 150.0  ## Kotlin's fallback FTP
## The push line as shares of FTP, empty and full (a medium balloon): work, then recovery.
const LINE_WORK := Vector2(0.20, 0.45)
const LINE_RECOVERY := Vector2(0.15, 0.30)
const LINE_EXP := 3.0  ## the line's curve: lo + (hi - lo) × k × f^LINE_EXP
const VALVE := 0.03  ## of FTP: the flow ramps from 0 at the line to full this far above it
const FILL_K := 0.25  ## balloon air a second per unit of power / FTP
const LEAK := 0.025  ## of a balloon a second, below the line
const SMOOTH_SEC := 1.0  ## the power's smoothing time constant (about a 2 s average)
const RECOVERY_GAIN := 1.4  ## recovery fills faster, so a gentle ride still fills
const TIE_SEC := 1.0
const LOAD_SEC := 0.8
const BREAK_SEC := 4.0
const HEAT_SEC := 120.0
const RACE_TARGET := 5
const BONUS_PER_SEC := 2.0  ## points a second left in a won Race heat
const POINTS_PER_AIR := 100.0
const GOLD_FACTOR := 3.0
const GOLD_CHANCE := 0.125
const GOLD_FROM := 2  ## the first balloons are never gold
const WARN_SEC := 10.0  ## a Race heat warns this long before its end
const KEEP_PUMPING_RPM := 40.0

## Each kind's air (fill units) and push-line scale.
const KINDS := {
	"small": {"air": 1.0, "line": 0.8},
	"medium": {"air": 1.5, "line": 1.0},
	"large": {"air": 2.0, "line": 1.12},
	"gold": {"air": 1.5, "line": 1.0},
}
## The draw's weights for the plain kinds.
const WEIGHTS := {"small": 0.35, "medium": 0.40, "large": 0.25}

var mode := "max"  ## "max" or "race"
var ftp := DEFAULT_FTP
var recovery := false
var phase := Phase.LOAD
var heats := false  ## whether play is in heats
var heat_sec := HEAT_SEC
var heats_total := 0  ## 0: no limit
var race_target := RACE_TARGET
var heat := 0  ## the current heat, from 1
var heat_left := 0.0
var heat_balloons := 0  ## balloons this heat
var heats_won := 0
var heats_done := 0

var kind := "small"  ## the balloon on the nozzle
var next_kind := "medium"  ## the one on the rack
var fill := 0.0  ## 0-1, the balloon on the nozzle
var smoothed := 0.0  ## W
var open := 0.0  ## 0-1, how far the valve is open
var flow := 0.0  ## balloons a second going in now (0 while leaking)
var leaking := false
var keep_pumping := false
var phase_left := LOAD_SEC

var balloons := 0
var gold := 0
var peak_power := 0.0
var fastest_balloon_sec := 0.0

var _rng := RandomNumberGenerator.new()
var _lo := 0.0  ## W, the push line empty (medium)
var _hi := 0.0  ## W, the push line full (medium)
var _cap := INF  ## W, the power counted for flow
var _gain := 1.0
var _drawn := 0  ## balloons drawn so far
var _last_gold := false
var _started := false
var _warned := false
var _balloon_sec := 0.0
var _power_sum := 0.0
var _power_sec := 0.0
var _need_load := true  ## no balloon on the nozzle (one is loaded after a break)


## `params` as Kotlin sends them (ftp_watts, push_lo_watts, push_hi_watts, power_cap_watts,
## race_balloons, race_sec); anything missing takes the design's default.
func _init(seed_value: int, params := {}, new_mode := "max", use_heats := false, total_heats := 0,
		is_recovery := false) -> void:
	_rng.seed = seed_value
	mode = new_mode
	recovery = is_recovery
	heats = use_heats or mode == "race"
	heats_total = maxi(total_heats, 0)
	ftp = maxf(float(params.get("ftp_watts", params.get("ftp", DEFAULT_FTP))), 1.0)
	var line := LINE_RECOVERY if recovery else LINE_WORK
	_lo = float(params.get("push_lo_watts", ftp * line.x))
	_hi = float(params.get("push_hi_watts", ftp * line.y))
	if recovery:
		_cap = float(params.get("power_cap_watts", ftp * 0.6))
		_gain = RECOVERY_GAIN
	heat_sec = maxf(float(params.get("race_sec", HEAT_SEC)), 10.0)
	race_target = maxi(int(params.get("race_balloons", RACE_TARGET)), 1)
	kind = _draw()
	next_kind = _draw()
	heat_left = heat_sec


## The push line in watts for a balloon of `of_kind` at fill `f`.
func line_at(f: float, of_kind := kind) -> float:
	var k: float = KINDS[of_kind].line
	return _lo + (_hi - _lo) * k * pow(clampf(f, 0.0, 1.0), LINE_EXP)


## The push line now, for the balloon on the nozzle.
func push_line() -> float:
	return line_at(fill)


## The push line once the balloon on the nozzle is full: the most it will ask.
func top_line() -> float:
	return line_at(1.0)


func air(of_kind := kind) -> float:
	return KINDS[of_kind].air


func points_for(of_kind: String) -> float:
	return POINTS_PER_AIR * air(of_kind) * (GOLD_FACTOR if of_kind == "gold" else 1.0)


func avg_power() -> float:
	return _power_sum / _power_sec if _power_sec > 0.0 else 0.0


## Whether a balloon sits on the nozzle (not while one ties off or the next loads).
func has_balloon() -> bool:
	return not _need_load


func is_over() -> bool:
	return phase == Phase.OVER


## Whether the rider has won more Race heats than they lost (null outside Race, or before any).
func race_won() -> Variant:
	if mode != "race" or heats_done == 0:
		return null
	return heats_won > heats_done - heats_won


## Advances by `delta` seconds. `sensors_ok` false holds everything (no fill, no leak, no clock).
## Returns the events, in order ({type: …}):
##   heat_start {heat, target (0 in max), sec}
##   filled {kind, points, gold, sec}: a balloon is full and tied off (award `points`)
##   loaded {kind, next}: the next balloon is on the nozzle
##   warn_time {left}: a Race heat's last seconds
##   heat_end {heat, won (race) or null, balloons, bonus, time_left}
##   over: the last heat's break is done; end the segment
func step(delta: float, power: float, cadence: float, sensors_ok := true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if phase == Phase.OVER:
		return events
	if not sensors_ok:
		smoothed = 0.0
		open = 0.0
		flow = 0.0
		leaking = false
		return events
	if not _started:
		_started = true
		if heats:
			_start_heat(events)
	smoothed += (power - smoothed) * (1.0 - exp(-delta / SMOOTH_SEC))
	keep_pumping = cadence < KEEP_PUMPING_RPM
	if phase != Phase.BREAK:
		peak_power = maxf(peak_power, power)
		_power_sum += power * delta
		_power_sec += delta
	match phase:
		Phase.FILL:
			_step_fill(delta, events)
		Phase.TIE:
			_hold_flow()
			phase_left -= delta
			if phase_left <= 0.0:
				_begin_load()
		Phase.LOAD:
			_hold_flow()
			phase_left -= delta
			if phase_left <= 0.0:
				_need_load = false
				phase = Phase.FILL
				_balloon_sec = 0.0
				events.append({"type": "loaded", "kind": kind, "next": next_kind})
		Phase.BREAK:
			_hold_flow()
			phase_left -= delta
			if phase_left <= 0.0:
				_after_break(events)
			return events
	if heats and phase != Phase.BREAK and phase != Phase.OVER:
		_step_clock(delta, events)
	return events


func _step_fill(delta: float, events: Array[Dictionary]) -> void:
	_balloon_sec += delta
	var line := push_line()
	var counted := minf(smoothed, _cap)
	open = smoothstep(line, line + VALVE * ftp, counted)
	leaking = counted < line
	flow = FILL_K * _gain * counted / ftp / air() * open
	if leaking:
		fill = maxf(fill - LEAK * delta, 0.0)
	else:
		fill = minf(fill + flow * delta, 1.0)
	if fill >= 1.0:
		_tie(events)


## While a balloon isn't filling, the gauge still reads but nothing flows.
func _hold_flow() -> void:
	open = 0.0
	flow = 0.0
	leaking = false


func _tie(events: Array[Dictionary]) -> void:
	var tied := kind
	balloons += 1
	heat_balloons += 1
	if tied == "gold":
		gold += 1
	if fastest_balloon_sec <= 0.0 or _balloon_sec < fastest_balloon_sec:
		fastest_balloon_sec = _balloon_sec
	events.append({"type": "filled", "kind": tied, "points": points_for(tied), "gold": tied == "gold",
		"sec": _balloon_sec})
	fill = 0.0
	_hold_flow()
	_need_load = true
	kind = next_kind
	next_kind = _draw()
	if mode == "race" and heats and heat_balloons >= race_target:
		_end_heat(true, events)
		return
	phase = Phase.TIE
	phase_left = TIE_SEC


func _begin_load() -> void:
	phase = Phase.LOAD
	phase_left = LOAD_SEC


func _step_clock(delta: float, events: Array[Dictionary]) -> void:
	heat_left = maxf(heat_left - delta, 0.0)
	if mode == "race" and not _warned and heat_left <= WARN_SEC:
		_warned = true
		events.append({"type": "warn_time", "left": heat_left})
	if heat_left <= 0.0:
		_end_heat(mode == "race" and heat_balloons >= race_target, events)


func _end_heat(won: bool, events: Array[Dictionary]) -> void:
	var bonus := BONUS_PER_SEC * heat_left if won else 0.0
	heats_done += 1
	if won:
		heats_won += 1
	events.append({"type": "heat_end", "heat": heat, "won": won if mode == "race" else null,
		"balloons": heat_balloons, "bonus": bonus, "time_left": heat_left})
	phase = Phase.BREAK
	phase_left = BREAK_SEC
	_hold_flow()


func _after_break(events: Array[Dictionary]) -> void:
	if heats_total > 0 and heats_done >= heats_total:
		phase = Phase.OVER
		events.append({"type": "over"})
		return
	_start_heat(events)
	if _need_load:
		_begin_load()
	else:
		phase = Phase.FILL


func _start_heat(events: Array[Dictionary]) -> void:
	heat += 1
	heat_left = heat_sec
	heat_balloons = 0
	_warned = false
	events.append({"type": "heat_start", "heat": heat, "target": race_target if mode == "race" else 0,
		"sec": heat_sec})


## The next balloon's kind, from the segment's seed: the first is always small, never gold among
## the first GOLD_FROM, never two golds in a row.
func _draw() -> String:
	var index := _drawn
	_drawn += 1
	var r := _rng.randf()
	var pick := _rng.randf()
	if index == 0:
		return "small"  # an easy first balloon teaches the push line before a big one
	if index >= GOLD_FROM and not _last_gold and r < GOLD_CHANCE:
		_last_gold = true
		return "gold"
	_last_gold = false
	var acc := 0.0
	for k in WEIGHTS:
		acc += WEIGHTS[k]
		if pick < acc:
			return k
	return "large"
