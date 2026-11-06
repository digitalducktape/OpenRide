class_name GridLogic
extends RefCounted
## Power Grid's rules (#81), apart from drawing so they're tested headless. The rider's watts,
## averaged over about 5 s, are the town's supply. Demand follows an evening curve; the rider
## meets it at 90% of it (10% headroom). As demand rises the districts come online: houses,
## streetlights, the funfair, the stadium. Falling short dims the newest district, then turns it
## off; catching up relights it. Nothing is ever taken away: the score just stops growing.
## DESIGN.md (this folder) is the design record: every number here is explained there.
##
## Districts are a prefix: `powered` of the `online` districts have power, newest last, so the
## next to go is always the newest. A storm's downed line takes one powered district out
## (`down_index`) until it's repaired, without touching the prefix.
##
## The storm is a small enum FSM (godot-prompter state-machine: enum-based; three states, no
## enter/exit logic worth nodes): CALM → WARNING → DOWN → CALM. The brown-out is plain timers.

enum Storm { CALM, WARNING, DOWN }

const DEFAULT_FTP := 150.0  ## Kotlin's fallback FTP
const HEADROOM := 0.9  ## the rider meets demand at this share of it
const SMOOTH_TAU := 2.5  ## s: the power's time constant (about a 5 s average)
const PEDAL_RPM := 30.0  ## under this the rider isn't pedalling: nothing scores, whatever the average says
const EVENING_MAX := 300.0  ## s: a longer work ride is several evenings
const START_GRACE := 6.0  ## s: no brown-out while the rider settles
## The demand (u, 0-1 along the evening's range) at which each district comes online.
const STEPS := [0.0, 0.3, 0.6, 0.9]
const DISTRICTS := ["Houses", "Streetlights", "Funfair", "Stadium"]
const COUNT := 4
const SOON_SEC := 4.0  ## a district is announced this long before it comes online
const RELIGHT_SEC := 1.5  ## s of meeting demand per district relit
## Work: short this long before the newest district starts to dim, then this long to go dark.
const SHORT_SEC := 1.0
const DIM_SEC := 3.0
## The easy roles forgive more: a warm-up must feel easy and a recovery restful.
const SHORT_SEC_EASY := 3.0
const DIM_SEC_EASY := 5.0
const POINTS_PER_DISTRICT := 5.0  ## a second, while meeting demand
## The easy roles have no effort multiplier, so this stands in for it: a clean easy ride earns
## its three stars by keeping the lights on, not by working harder (DESIGN.md §4).
const EASY_GAIN := 1.4
## Demand's range as shares of FTP (the fallback for Kotlin's params).
const WORK_SHARES := {"easy": Vector2(0.40, 0.60), "standard": Vector2(0.45, 0.70), "hard": Vector2(0.50, 0.75)}
const WARM_SHARES := Vector2(0.30, 0.50)  ## warm-up and cool-down
const RECOVERY_SHARES := Vector2(0.30, 0.42)
const CAP_SHARES := {"warmup": 0.65, "cooldown": 0.65, "recovery": 0.60}
const STORM_SHARE := 0.15  ## of FTP: the extra a repair asks
const STORM_WARN_SEC := 3.0
const STORM_REPAIR_SEC := 10.0
const STORM_WINDOW_SEC := 30.0  ## then the line crew fixes it, with no bonus
const STORM_BONUS := 100.0
const STORM_DRAIN := 0.25  ## of a second of repair lost per second under the line
const STORM_FIRST := Vector2(20.0, 32.0)  ## s into the ride
const STORM_GAP := Vector2(50.0, 80.0)  ## s between storms
const STORM_LAST_LEFT := 20.0  ## no storm with less time left
const STORM_RETRY := 8.0  ## s, when there's nothing lit for a storm to hit
const TAIL_FROM := 0.88  ## of an evening: a following evening starts winding down here

var role := "work"
var ftp := DEFAULT_FTP
var lo := 0.0  ## W, demand at its lowest
var hi := 0.0  ## W, demand at its peak
var cap := INF  ## W, the role's power cap (easy roles)
var storm_watts := 0.0  ## W, the extra a repair asks
var storms_on := false
var evening := 1
var evenings := 1  ## 0: no limit (open-ended)
var evening_sec := EVENING_MAX

var t := 0.0  ## s into this evening
var elapsed := 0.0  ## s of play
var supply := 0.0  ## W, the smoothed power: the number on the ride panel
var demand := 0.0  ## W, now
var pedalling := false
var meeting := false
var earned := 0.0  ## points the last step earned (award them)
var online := 1  ## districts demand has brought online
var powered := 1  ## of those, how many have power
var dim := 0.0  ## 0-1, how far the newest powered district has dimmed

var storm := Storm.CALM
var storm_left := 0.0  ## s to the strike (WARNING), or to the crew's fix (DOWN)
var repair := 0.0  ## s of repair done
var repair_need := 0.0  ## W: held for the whole storm, so the callout stays true
var down_index := -1  ## the district on the downed line

var storms := 0
var storms_restored := 0
var districts_max := 1

var _rng := RandomNumberGenerator.new()
var _duration := 0.0
var _started := false
var _short := 0.0
var _met := 0.0
var _dimming := false
var _announced := 1  ## districts already online or announced as coming
var _full_shown := false
var _next_storm := 0.0
var _lit_sum := 0.0
var _online_sum := 0.0
var _power_sum := 0.0
var _power_sec := 0.0


## `params` as Kotlin sends them (ftp_watts, demand_lo_watts, demand_hi_watts, storm_watts,
## power_cap_watts); anything missing takes the design's default. `new_role` is the segment's
## role ("free" plays like work). `duration` is the segment's seconds (<= 0 is open-ended).
func _init(seed_value: int, params := {}, new_role := "work", duration := -1.0, difficulty := "standard") -> void:
	_rng.seed = seed_value
	role = new_role
	_duration = duration
	ftp = maxf(float(params.get("ftp_watts", params.get("ftp", DEFAULT_FTP))), 1.0)
	var shares := default_shares(role, difficulty)
	lo = float(params.get("demand_lo_watts", ftp * shares.x))
	hi = maxf(float(params.get("demand_hi_watts", ftp * shares.y)), lo)
	storm_watts = float(params.get("storm_watts", ftp * STORM_SHARE))
	storms_on = not is_easy()
	if is_easy():
		cap = float(params.get("power_cap_watts", ftp * float(CAP_SHARES.get(role, 0.65))))
		hi = minf(hi, cap)
		lo = minf(lo, hi)
		evening_sec = duration if duration > 0.0 else EVENING_MAX
	elif duration > 0.0:
		evenings = maxi(ceili(duration / EVENING_MAX), 1)
		evening_sec = duration / evenings
	else:
		evenings = 0
	_next_storm = _rng.randf_range(STORM_FIRST.x, STORM_FIRST.y)
	online = online_at(u_at(0.0))
	powered = online
	_announced = online
	demand = demand_at(0.0)


## Demand's range (shares of FTP) for a role and difficulty. Difficulty never moves an easy role.
static func default_shares(for_role: String, difficulty: String) -> Vector2:
	match for_role:
		"warmup", "cooldown":
			return WARM_SHARES
		"recovery":
			return RECOVERY_SHARES
	return WORK_SHARES.get(difficulty, WORK_SHARES.standard)


## Whether this is a warm-up, cool-down or recovery: easy, restful, no storms.
func is_easy() -> bool:
	return role in ["warmup", "cooldown", "recovery"]


## The evening's curve: u (0-1 along demand's range) at `p` (0-1 through the evening).
##   work:     rises to its peak by 72%, holds; a following evening winds down from 88%
##   warm-up:  rises gently all the way; a cool-down is that in reverse: the town goes to bed
##   recovery: one low, gentle swell and back
static func curve(for_role: String, p: float, wind_down := false) -> float:
	p = clampf(p, 0.0, 1.0)
	match for_role:
		"warmup":
			return smoothstep(0.0, 0.85, p)
		"cooldown":
			return 1.0 - smoothstep(0.15, 1.0, p)
		"recovery":
			return sin(PI * p)
	var u := smoothstep(0.0, 0.72, p)
	if wind_down:
		u *= 1.0 - smoothstep(TAIL_FROM, 1.0, p)
	return u


## Where the curve stands `at` seconds into this evening.
func u_at(at: float) -> float:
	return curve(role, at / evening_sec, _winds_down())


## Demand in watts `at` seconds into this evening.
func demand_at(at: float) -> float:
	return lerpf(lo, hi, u_at(at))


## The watts that meet demand now.
func need() -> float:
	return demand * HEADROOM


## The watts that will meet demand `ahead` seconds from now.
func need_ahead(ahead: float) -> float:
	return demand_at(t + ahead) * HEADROOM


## The watts the gauge's line sits at now: a storm's repair, or what meets demand.
func target() -> float:
	return repair_need if storm == Storm.DOWN else need()


## Districts with power, without the one on a downed line.
func lit() -> int:
	return maxi(powered - (1 if down_index >= 0 and down_index < powered else 0), 0)


## How many districts the curve has online at u.
static func online_at(u: float) -> int:
	var n := 1
	for i in range(1, COUNT):
		if u >= float(STEPS[i]) - 0.0001:
			n = i + 1
	return n


## District `i`'s level for the view: 0 dark, 1 full; the newest powered one dims.
func level(i: int) -> float:
	if i >= powered or i == down_index:
		return 0.0
	return 1.0 - dim if i == powered - 1 else 1.0


## The sky: 0 dusk, 1 full night, over each evening.
func night() -> float:
	return smoothstep(0.03, 0.8, t / evening_sec)


## The share of the online town that was lit, as a whole percentage.
func lit_pct() -> int:
	return roundi(100.0 * _lit_sum / _online_sum) if _online_sum > 0.0 else 0


func avg_power() -> float:
	return _power_sum / _power_sec if _power_sec > 0.0 else 0.0


## In an easy role: over the cap, the extra watts gain nothing.
func over_cap() -> bool:
	return supply > cap


func _winds_down() -> bool:
	return not is_easy() and (evenings == 0 or evening < evenings)


func _short_sec() -> float:
	return SHORT_SEC_EASY if is_easy() else SHORT_SEC


func _dim_sec() -> float:
	return DIM_SEC_EASY if is_easy() else DIM_SEC


## Advances by `delta` seconds. `sensors_ok` false holds the whole town as it is. Returns the
## events, in order ({type: …}):
##   district_soon {index, need}: it comes online in about SOON_SEC
##   district_on {index}: demand brought it online with power
##   district_missed {index, need}: it came online but the rider's short: it stays dark
##   district_rest {index}: demand fell away (a cool-down, an evening's end): it switches off quietly
##   dimming {index, need}: the newest district has started to dim
##   district_out {index, need}: it went dark
##   relit {index}: catching up brought it back
##   full_town: all four lit, once an evening
##   storm_warn {need, sec}: lightning; the strike is `sec` away, and the repair will ask `need`
##   strike {index, need, sec}: the line's down
##   restored {index, bonus}: the rider repaired it (award `bonus`)
##   crew_fixed {index}: the window ran out; the line's back with no bonus
##   evening {number}: a new evening starts
func step(delta: float, power: float, cadence: float, sensors_ok := true) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	earned = 0.0
	if not sensors_ok:
		meeting = false
		return events
	if not _started:
		_started = true
		supply = power
	else:
		supply += (power - supply) * (1.0 - exp(-delta / SMOOTH_TAU))
	elapsed += delta
	t += delta
	if t >= evening_sec and (evenings == 0 or evening < evenings):
		t -= evening_sec
		evening += 1
		_announced = 1
		_full_shown = false
		events.append({"type": "evening", "number": evening})
	demand = demand_at(t)
	pedalling = cadence >= PEDAL_RPM and power > 0.0
	meeting = pedalling and supply >= need()
	_power_sum += power * delta
	_power_sec += delta
	_step_online(events)
	_step_power(delta, events)
	if storms_on:
		_step_storm(delta, events)
	var now := lit()
	districts_max = maxi(districts_max, now)
	_lit_sum += now * delta
	_online_sum += online * delta
	if now >= COUNT and not _full_shown:
		_full_shown = true
		events.append({"type": "full_town"})
	if meeting:
		earned = POINTS_PER_DISTRICT * now * delta * (EASY_GAIN if is_easy() else 1.0)
	return events


func _step_online(events: Array[Dictionary]) -> void:
	var want := online_at(u_at(t))
	while online < want:
		online += 1
		var index := online - 1
		if meeting and powered == index:
			powered += 1
			events.append({"type": "district_on", "index": index})
		else:
			events.append({"type": "district_missed", "index": index, "need": need()})
	while online > want:
		online -= 1
		if powered > online:
			powered = online
			dim = 0.0
			_dimming = false
		events.append({"type": "district_rest", "index": online})
	_announced = maxi(_announced, online)
	# A rising curve announces the next district ahead of time.
	if _announced < COUNT and online_at(u_at(t + SOON_SEC)) > _announced:
		events.append({"type": "district_soon", "index": _announced, "need": need_ahead(SOON_SEC)})
		_announced += 1


func _step_power(delta: float, events: Array[Dictionary]) -> void:
	if meeting:
		_short = 0.0
		dim = move_toward(dim, 0.0, delta / 0.5)
		_dimming = false
		_met += delta
		if powered < online and _met >= RELIGHT_SEC:
			_met = 0.0
			powered += 1
			events.append({"type": "relit", "index": powered - 1})
		return
	_met = 0.0
	if elapsed < START_GRACE or powered <= 0:
		return
	_short += delta
	if _short <= _short_sec():
		return
	if not _dimming:
		_dimming = true
		events.append({"type": "dimming", "index": powered - 1, "need": need()})
	dim = (_short - _short_sec()) / _dim_sec()
	if dim >= 1.0:
		powered -= 1
		dim = 0.0
		_dimming = false
		_short = _short_sec()
		events.append({"type": "district_out", "index": powered, "need": need()})


func _step_storm(delta: float, events: Array[Dictionary]) -> void:
	match storm:
		Storm.CALM:
			_next_storm -= delta
			if _next_storm <= 0.0:
				_try_storm(events)
		Storm.WARNING:
			storm_left -= delta
			if storm_left <= 0.0:
				_strike(events)
		Storm.DOWN:
			storm_left -= delta
			if pedalling and supply >= repair_need:
				repair += delta
			else:
				repair = maxf(repair - STORM_DRAIN * delta, 0.0)
			if repair >= STORM_REPAIR_SEC:
				storms_restored += 1
				events.append({"type": "restored", "index": down_index, "bonus": STORM_BONUS})
				_end_storm()
			elif storm_left <= 0.0:
				events.append({"type": "crew_fixed", "index": down_index})
				_end_storm()


## A storm starts unless the ride is about to end, the evening is winding down or nothing's lit.
func _try_storm(events: Array[Dictionary]) -> void:
	var left := _duration - elapsed if _duration > 0.0 else INF
	if left < STORM_LAST_LEFT:
		_next_storm = INF
		return
	if lit() <= 0 or (_winds_down() and t / evening_sec >= TAIL_FROM - 0.08):
		_next_storm = STORM_RETRY
		return
	storm = Storm.WARNING
	storm_left = STORM_WARN_SEC
	repair_need = need_ahead(STORM_WARN_SEC) + storm_watts
	events.append({"type": "storm_warn", "need": repair_need, "sec": STORM_WARN_SEC})


func _strike(events: Array[Dictionary]) -> void:
	if lit() <= 0:
		storm = Storm.CALM
		_next_storm = STORM_RETRY
		return
	storm = Storm.DOWN
	storms += 1
	down_index = powered - 1
	dim = 0.0
	repair = 0.0
	storm_left = STORM_WINDOW_SEC
	events.append({"type": "strike", "index": down_index, "need": repair_need, "sec": STORM_REPAIR_SEC})


func _end_storm() -> void:
	storm = Storm.CALM
	down_index = -1
	repair = 0.0
	_next_storm = _rng.randf_range(STORM_GAP.x, STORM_GAP.y)
