class_name TugLogic
extends RefCounted
## Tug of War's rules (#40), apart from drawing so they're tested headless: the rider's watts
## against a bot's watts over a rope. `p` is the rope marker in [-1, 1]: +1 is the rider's
## win, -1 the bot's. Rounds end when the marker reaches either end, or at the buzzer, where
## p > 0 wins. The bot holds `bot_watts` and surges to `surge_watts` for SURGE_SEC at random,
## telegraphed TELEGRAPH_SEC early. Three ways to play:
##   endless  rounds repeat until the segment timer ends (circuits and timed Just Rides)
##   match    best of N rounds
##   ladder   each win faces a stronger bot (+LADDER_STEP of FTP); the first loss ends it
## Between rounds of a match or ladder a RECOVERY card runs (the next bot's watts are shown);
## an endless run goes straight on after the round's result.

enum Phase { ROUND, ROUND_END, RECOVERY, MATCH_END }

## dp/dt = K × (power − bot_watts) / ftp. Holding 20% of FTP above the bot wins in 1 / (0.2 K)
## = 20 s; holding exactly its watts is a stalemate.
const K := 0.25
const DEFAULT_FTP := 200.0
## The bot's watts as a share of FTP. Deliberately low: a person pedalling along comfortably
## makes about half their FTP, so beating the bot takes a little more than that, not an effort
## at threshold (the rider's feedback on the first version, whose bot held 110%).
const BOT_FACTOR := 0.6
const SURGE_FACTOR := 0.8
const SURGE_SEC := 5.0
const TELEGRAPH_SEC := 1.0
const SURGE_GAP_MIN := 12.0  ## at least this long between two surges' starts
const SURGE_GAP_JITTER := 8.0
const FIRST_SURGE_MIN := 8.0
const FIRST_SURGE_JITTER := 8.0
const SURGE_HELD := 0.2  ## a surge is answered if p never fell more than this during it
const BRACE_SLOWDOWN := 0.75  ## brace lean: p falls at this share of its speed during a surge
const LADDER_STEP := 0.05  ## each rung's bot is this much of FTP stronger
const ROUND_SEC := 60.0
const ROUND_END_SEC := 3.0  ## the result (and the loser's fall) shows this long
const RECOVERY_SEC := 60.0
const KEEP_PEDALING_RPM := 50.0
const WIN_POINTS := 1000.0
## Points per second for each watt the rider is over the bot, awarded through the effort
## multiplier. A margin is only ever a bonus: being behind costs nothing but rope.
const MARGIN_POINTS := 0.15

var phase := Phase.ROUND
var mode := "endless"  ## "endless", "match" or "ladder"
var best_of := 3
var ftp := DEFAULT_FTP
var rung := 0  ## ladder: wins so far
var round_index := 1
var wins := 0
var losses := 0
var p := 0.0
var round_left := ROUND_SEC
var phase_left := 0.0  ## seconds left of ROUND_END or RECOVERY
var base_bot := 0.0  ## the first rung's bot, in watts
var base_surge := 0.0
var round_won := false  ## the last round's result, during ROUND_END
var match_over := false
var rider_power := 0.0
var keep_pedaling := false
var last_margin_points := 0.0  ## this step's margin points (the scene awards them)
var surge_state := ""  ## "", "telegraph" or "surge"
var surges := 0
var surges_answered := 0
var peak_power := 0.0
var braced := false

var _rng := RandomNumberGenerator.new()
var _round_sec := ROUND_SEC
var _round_time := 0.0
var _next_surge := 0.0  ## round time at which the next surge starts
var _surge_left := 0.0
var _surge_start_p := 0.0
var _surge_min_p := 0.0
var _power_sum := 0.0
var _power_sec := 0.0
var _margin_sum := 0.0  ## this round's margin integrated over time
var _margin_sec := 0.0
var _all_margin_sum := 0.0
var _all_margin_sec := 0.0
var _all_best_margin := 0.0


func _init(seed_value: int, params := {}, new_mode := "endless", new_best_of := 3) -> void:
	_rng.seed = seed_value
	ftp = maxf(float(params.get("ftp_watts", params.get("ftp", DEFAULT_FTP))), 1.0)
	base_bot = float(params.get("bot_watts", ftp * BOT_FACTOR))
	base_surge = float(params.get("surge_watts", ftp * SURGE_FACTOR))
	_round_sec = float(params.get("round_sec", ROUND_SEC))
	mode = new_mode
	best_of = maxi(new_best_of, 1)
	_reset_round()


## The bot's steady watts this round (the ladder raises them by LADDER_STEP of FTP a rung).
func bot_watts() -> float:
	return base_bot + ftp * LADDER_STEP * rung


func surge_watts() -> float:
	return base_surge + ftp * LADDER_STEP * rung


## The bot's watts now: its surge watts during a surge, otherwise its steady watts.
func bot_power_now() -> float:
	return surge_watts() if surge_state == "surge" else bot_watts()


## The bot of the next ladder rung or the next round, for the recovery card.
func next_bot_watts() -> float:
	return base_bot + ftp * LADDER_STEP * (rung + (1 if mode == "ladder" and round_won else 0))


func is_over() -> bool:
	return phase == Phase.MATCH_END


## Rounds needed to take a match.
func rounds_to_win() -> int:
	return best_of / 2 + 1


## Whether the rider has won more rounds than they lost.
func rider_won() -> bool:
	return wins > losses


func avg_power() -> float:
	return _power_sum / _power_sec if _power_sec > 0.0 else 0.0


## The average margin, in watts, over all rounds played so far.
func avg_margin() -> float:
	return _all_margin_sum / _all_margin_sec if _all_margin_sec > 0.0 else 0.0


## The biggest margin of victory in watts averaged over a won round, the ladder's "best".
func best_margin() -> float:
	return _all_best_margin


func round_margin() -> float:
	return _margin_sum / _margin_sec if _margin_sec > 0.0 else 0.0


## Advances by `delta` seconds with the rider's power, cadence, and whether the rider is bracing
## (leaning in; only counts when the option is on and a surge is on). Returns the events
## ({type: ...}): "telegraph", "surge_start", "surge_end" (answered), "round_end" (won, margin,
## points), "recovery_start", "round_start", "match_end".
func step(delta: float, power: float, cadence: float, brace := false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	last_margin_points = 0.0
	rider_power = power
	keep_pedaling = cadence < KEEP_PEDALING_RPM
	braced = brace
	match phase:
		Phase.ROUND:
			_step_round(delta, power, events)
		Phase.ROUND_END:
			phase_left -= delta
			if phase_left <= 0.0:
				_after_round_end(events)
		Phase.RECOVERY:
			phase_left -= delta
			if phase_left <= 0.0:
				_advance_round()
				events.append({"type": "round_start", "round": round_index, "bot_watts": bot_watts()})
	return events


func _step_round(delta: float, power: float, events: Array[Dictionary]) -> void:
	_round_time += delta
	round_left = maxf(_round_sec - _round_time, 0.0)
	peak_power = maxf(peak_power, power)
	_power_sum += power * delta
	_power_sec += delta
	_update_surge(delta, events)
	var margin := power - bot_power_now()
	_margin_sum += margin * delta
	_margin_sec += delta
	_all_margin_sum += margin * delta
	_all_margin_sec += delta
	last_margin_points = maxf(margin, 0.0) * MARGIN_POINTS * delta
	var dp := K * margin / ftp * delta
	if dp < 0.0 and surge_state == "surge" and braced:
		dp *= BRACE_SLOWDOWN
	p = clampf(p + dp, -1.0, 1.0)
	if surge_state == "surge":
		_surge_min_p = minf(_surge_min_p, p)
	if p >= 1.0:
		_end_round(true, events)
	elif p <= -1.0:
		_end_round(false, events)
	elif round_left <= 0.0:
		_end_round(p > 0.0, events)


func _update_surge(delta: float, events: Array[Dictionary]) -> void:
	if surge_state == "surge":
		_surge_left -= delta
		if _surge_left <= 0.0:
			_finish_surge(events)
		return
	if _round_time >= _next_surge:
		surge_state = "surge"
		_surge_left = SURGE_SEC
		_surge_start_p = p
		_surge_min_p = p
		surges += 1
		events.append({"type": "surge_start"})
	elif surge_state == "" and _round_time >= _next_surge - TELEGRAPH_SEC:
		surge_state = "telegraph"
		events.append({"type": "telegraph"})


func _finish_surge(events: Array[Dictionary]) -> void:
	var answered := _surge_start_p - _surge_min_p <= SURGE_HELD
	if answered:
		surges_answered += 1
	surge_state = ""
	_next_surge = _round_time + SURGE_GAP_MIN - SURGE_SEC + _rng.randf() * SURGE_GAP_JITTER
	events.append({"type": "surge_end", "answered": answered})


func _end_round(won: bool, events: Array[Dictionary]) -> void:
	if surge_state == "surge":
		_finish_surge(events)
	surge_state = ""
	round_won = won
	var margin := round_margin()
	if won:
		wins += 1
		_all_best_margin = maxf(_all_best_margin, margin)
	else:
		losses += 1
	events.append({"type": "round_end", "won": won, "margin": margin,
		"points": WIN_POINTS if won else 0.0, "round": round_index})
	phase = Phase.ROUND_END
	phase_left = ROUND_END_SEC


func _after_round_end(events: Array[Dictionary]) -> void:
	if _match_decided():
		phase = Phase.MATCH_END
		match_over = true
		events.append({"type": "match_end", "won": rider_won()})
		return
	if mode == "endless":
		_advance_round()
		events.append({"type": "round_start", "round": round_index, "bot_watts": bot_watts()})
		return
	phase = Phase.RECOVERY
	phase_left = RECOVERY_SEC
	events.append({"type": "recovery_start", "next_bot_watts": next_bot_watts()})


func _match_decided() -> bool:
	match mode:
		"ladder":
			return not round_won
		"match":
			return wins >= rounds_to_win() or losses >= rounds_to_win()
	return false


## The next round: a win on the ladder moves up a rung.
func _advance_round() -> void:
	if mode == "ladder" and round_won:
		rung += 1
	round_index += 1
	_reset_round()


func _reset_round() -> void:
	phase = Phase.ROUND
	p = 0.0
	_round_time = 0.0
	round_left = _round_sec
	surge_state = ""
	_margin_sum = 0.0
	_margin_sec = 0.0
	_next_surge = FIRST_SURGE_MIN + _rng.randf() * FIRST_SURGE_JITTER
