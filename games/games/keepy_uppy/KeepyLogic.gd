class_name KeepyLogic
extends RefCounted
## Keepy Uppy's rules (#77), apart from drawing so they're tested headless: a balloon held up by
## a fan the rider's pedalling drives, and weather that pushes it down. DESIGN.md (this folder)
## is the source of every number here.
##
## Two small enum machines (godot-prompter state-machine, enum-based: few states, no
## enter/exit beyond a line or two, and headless-testable):
##   balloon  FLYING → POPPED (it touched the ground) → ARRIVING (a new one drifts in) → FLYING
##   weather  CALM → TELEGRAPH (the warning, 2-3 s) → ACTIVE (rain, a bird landing, a downdraft)
##            → CALM
## Plus the high band's gusts (warned 2 s ahead) and, with Steer on, the wind and the fan's rail.
##
## `step` returns events ({type: …}) for the scene's sounds, messages and views; the scene awards
## `last_points` and penalizes on "pop".

enum Balloon { FLYING, POPPED, ARRIVING }
enum Weather { CALM, TELEGRAPH, ACTIVE }
enum Band { LOW, MID, HIGH }

const DEFAULT_FTP := 150.0
## The balloon's weight as a share of FTP when the segment doesn't send `weight_watts`.
const WEIGHT_SHARE := {"easy": 0.30, "standard": 0.40, "hard": 0.50}
const RAIN_SHARE := 0.10
const BIRD_SHARE := 0.05
const DOWNDRAFT_SHARE := 0.20

## Power is smoothed with this time constant: a step is 86% in after 2 s ("smoothed (2 s)").
const SMOOTH_TAU := 1.0
## The column weakens with height: lift = power × (1 − FALLOFF × h).
const FALLOFF := 0.45
const SINK_MAX := 0.15  ## height a second: balloons are floaty
const CLIMB_MAX := 0.25
const DOWNDRAFT_SINK := 0.25  ## a downdraft lifts the floaty limit to this
const MID_FROM := 0.35
const HIGH_FROM := 0.65
const BASE_POINTS := 10.0  ## a second, times the band (1×, 2×, 3×)
const POP_PENALTY := 50.0

const START_HEIGHT := 0.4
## The first balloon, and each new one, holds its height this long (no sinking) while the rider
## gets going.
const START_GRACE := 3.0
const ARRIVE_GRACE := 1.5
const POP_SEC := 1.2  ## the pieces fall; then the new balloon is dispatched
const ARRIVE_SEC := 1.8  ## it drifts in: back in the air 3 s after the pop
const CALM_AFTER_ARRIVE := 4.0  ## the weather waits at least this long after a new balloon

## The weather: one force at a time.
const FIRST_FORCE_MIN := 8.0
const FIRST_FORCE_JITTER := 6.0
const FORCE_GAP_MIN := 10.0
const FORCE_GAP_JITTER := 6.0
const FORCE_WEIGHTS := {"rain": 0.35, "bird": 0.40, "downdraft": 0.25}
const WARNING := {"rain": 3.0, "bird": 2.5, "downdraft": 2.5}
const RAIN_MIN := 8.0
const RAIN_JITTER := 4.0
const DOWNDRAFT_SEC := 1.5
const MAX_BIRDS := 3
const SHAKE_SEC := 3.0  ## in the high band this long in a row shakes every bird off
## Birds get bored: they fly off by themselves this long after the last one landed (not counted
## as shaken), so a rider who never rides high isn't buried under them.
const BIRD_STAY := 20.0

## The high band's gusts.
const GUST_GAP_MIN := 6.0
const GUST_GAP_JITTER := 4.0
const GUST_WARNING := 2.0
const GUST_SEC := 0.6
const GUST_SINK := 0.2

## Steer (DESIGN.md "Steer"; the forgiving lean is for #71).
const LEAN_DEAD := 0.12
const LEAN_CURVE := 1.6
const FAN_RANGE := 1.6  ## metres either side at full lean
const FAN_TAU := 0.35
const FAN_SPEED := 1.6  ## metres a second at most
## The wind carries the balloon toward `wind` metres off the middle with this time constant...
const DRIFT_TAU := 2.0
## ...while the column pulls it a little toward the fan's centre, per second.
const CENTRING := 0.15
const FREE := 0.25  ## metres off-centre with no lift lost
const EDGE := 1.2  ## metres off-centre where the loss is full
const MAX_LOSS := 0.5
const WIND_MAX := 0.8  ## metres: how far off the middle the wind carries the balloon
const WIND_EASE_SEC := 3.0  ## a new wind is fully in after this
const WIND_GAP_MIN := 6.0
const WIND_GAP_JITTER := 4.0
const WIND_FADE_SEC := 2.0  ## without a face the wind dies away over this
const X_LIMIT := 3.0

var ftp := DEFAULT_FTP
var base_weight := DEFAULT_FTP * 0.4
var rain_watts := DEFAULT_FTP * RAIN_SHARE
var bird_watts := DEFAULT_FTP * BIRD_SHARE
var downdraft_watts := DEFAULT_FTP * DOWNDRAFT_SHARE
var steer := false

var balloon := Balloon.FLYING
var weather := Weather.CALM
var force := ""  ## the weather's force while it warns or acts: "rain", "bird" or "downdraft"
var force_left := 0.0  ## seconds left of its warning or its action
var h := START_HEIGHT
var rate := 0.0  ## height a second, this step
var smoothed := 0.0
var band := Band.MID
var birds := 0
var raining := false
var gust := ""  ## "", "warn" or "gust"
var gust_left := 0.0
var shake_progress := 0.0  ## 0-1 toward shaking the birds off
var state_left := 0.0  ## seconds left of POPPED or ARRIVING
var last_points := 0.0  ## this step's points (the scene awards them)

## Steer state, in metres along the fan's rail (+x is the rider's right).
var x := 0.0  ## the balloon
var fan_x := 0.0
var fan_target := 0.0
var wind := 0.0  ## metres: where the wind carries the balloon now
var wind_target := 0.0  ## the new wind, shown on the windsock as soon as it's chosen
var wind_gain := 0.0  ## 0-1: the wind fades out while the tracker can't see the rider
var efficiency := 1.0

## Stats.
var pops := 0
var seconds_high := 0.0
var birds_shaken := 0
var downdrafts := 0
var downdrafts_beaten := 0
var best_air := 0.0
var air := 0.0  ## this balloon's time up

var _rng := RandomNumberGenerator.new()
var _primed := false
var _grace := START_GRACE
var _next_force := 0.0
var _next_gust := 0.0
var _next_wind := 0.0
var _rain_left := 0.0
var _bird_stay := 0.0
var _downdraft_band := Band.MID
var _downdraft_low := Band.MID
var _power_sum := 0.0
var _power_sec := 0.0


func _init(seed_value: int, params := {}, new_difficulty := "standard", new_steer := false) -> void:
	_rng.seed = seed_value
	ftp = maxf(float(params.get("ftp_watts", params.get("ftp", DEFAULT_FTP))), 1.0)
	var share: float = WEIGHT_SHARE.get(new_difficulty, 0.4)
	base_weight = float(params.get("weight_watts", ftp * share))
	rain_watts = float(params.get("rain_watts", ftp * RAIN_SHARE))
	bird_watts = float(params.get("bird_watts", ftp * BIRD_SHARE))
	downdraft_watts = float(params.get("downdraft_watts", ftp * DOWNDRAFT_SHARE))
	steer = new_steer
	_next_force = FIRST_FORCE_MIN + _rng.randf() * FIRST_FORCE_JITTER
	_next_gust = _gust_gap()
	_next_wind = 0.0
	band = band_of(h)


## The weight the fan holds up now: the balloon, the rain and the birds (and a downdraft's push).
func weight() -> float:
	var w := base_weight + birds * bird_watts
	if raining:
		w += rain_watts
	if weather == Weather.ACTIVE and force == "downdraft":
		w += downdraft_watts
	return w


## The fan's lift at height `at_h`, from the smoothed power and the steer offset.
func lift(at_h: float) -> float:
	return smoothed * efficiency * (1.0 - FALLOFF * at_h)


## Where the balloon comes to rest at a steady `power` and weight `w` (no steer loss).
static func resting_height(power: float, w: float) -> float:
	if power <= w:
		return 0.0
	return clampf((1.0 - w / power) / FALLOFF, 0.0, 1.0)


## The steady power that holds the balloon at height `at_h` against weight `w`.
static func power_for(at_h: float, w: float) -> float:
	return w / (1.0 - FALLOFF * at_h)


static func band_of(height: float) -> Band:
	if height >= HIGH_FROM:
		return Band.HIGH
	if height >= MID_FROM:
		return Band.MID
	return Band.LOW


## The points multiplier of a band.
static func multiplier(b: Band) -> int:
	return int(b) + 1


func avg_power() -> float:
	return _power_sum / _power_sec if _power_sec > 0.0 else 0.0


## The fan's wanted place for a lean (-1..1): a dead zone, then a soft curve, so small sways
## barely move it and sitting straight always brings it home (#71).
static func lean_to_fan(lean: float) -> float:
	var t := clampf((absf(lean) - LEAN_DEAD) / (1.0 - LEAN_DEAD), 0.0, 1.0)
	return signf(lean) * pow(t, LEAN_CURVE) * FAN_RANGE


## The lift kept with the balloon `offset` metres off the fan's centre.
static func steer_efficiency(offset: float) -> float:
	return 1.0 - MAX_LOSS * clampf((absf(offset) - FREE) / (EDGE - FREE), 0.0, 1.0)


## Advances by `delta` seconds. `power` in watts, `lean` the tracker's lean_x, `tracking` whether
## the tracker sees the rider, `frozen` while the sensors are lost (nothing moves or scores).
## Returns the events: "telegraph" (force, warning), "force_start" (force), "force_end" (force,
## beaten for a downdraft), "bird_land" (birds), "birds_shaken" (count), "birds_scatter",
## "gust_warn", "gust", "band" (band, was), "pop", "dispatch", "arrive", "wind" (target).
func step(delta: float, power: float, lean := 0.0, tracking := false, frozen := false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	last_points = 0.0
	if frozen or delta <= 0.0:
		return events
	if not _primed:
		_primed = true
		smoothed = power
	smoothed += (power - smoothed) * (1.0 - exp(-delta / SMOOTH_TAU))
	_power_sum += power * delta
	_power_sec += delta
	_step_steer(delta, lean, tracking, events)
	match balloon:
		Balloon.FLYING:
			_step_flying(delta, events)
		Balloon.POPPED:
			state_left -= delta
			if state_left <= 0.0:
				balloon = Balloon.ARRIVING
				state_left = ARRIVE_SEC
				events.append({"type": "dispatch"})
		Balloon.ARRIVING:
			state_left -= delta
			if state_left <= 0.0:
				_arrive(events)
	if balloon == Balloon.FLYING or weather == Weather.ACTIVE:
		_step_weather(delta, events)
	return events


func _step_flying(delta: float, events: Array[Dictionary]) -> void:
	var w := weight()
	var sink_max := SINK_MAX
	if weather == Weather.ACTIVE and force == "downdraft":
		sink_max = DOWNDRAFT_SINK
	rate = clampf((lift(h) - w) / maxf(w, 1.0), -sink_max, CLIMB_MAX)
	if _grace > 0.0:
		_grace -= delta
		rate = maxf(rate, 0.0)
	_step_gust(delta, events)
	if gust == "gust":
		rate -= GUST_SINK
	h = clampf(h + rate * delta, 0.0, 1.0)
	air += delta
	best_air = maxf(best_air, air)
	var now := band_of(h)
	if now != band:
		events.append({"type": "band", "band": now, "was": band})
		band = now
	if weather == Weather.ACTIVE and force == "downdraft":
		if band < _downdraft_low:
			_downdraft_low = band
	if band == Band.HIGH:
		seconds_high += delta
	_step_birds(delta, events)
	if h <= 0.0:
		_pop(events)
		return
	last_points = BASE_POINTS * multiplier(band) * delta


func _step_birds(delta: float, events: Array[Dictionary]) -> void:
	if birds == 0:
		shake_progress = 0.0
		return
	_bird_stay -= delta
	if _bird_stay <= 0.0:
		birds = 0
		shake_progress = 0.0
		events.append({"type": "birds_leave"})
		return
	if band != Band.HIGH:
		shake_progress = 0.0
		return
	shake_progress += delta / SHAKE_SEC
	if shake_progress >= 1.0:
		events.append({"type": "birds_shaken", "count": birds})
		birds_shaken += birds
		birds = 0
		shake_progress = 0.0


func _step_gust(delta: float, events: Array[Dictionary]) -> void:
	match gust:
		"gust":
			gust_left -= delta
			if gust_left <= 0.0:
				gust = ""
				_next_gust = _gust_gap()
		"warn":
			if band != Band.HIGH:
				gust = ""
				_next_gust = _gust_gap()
				return
			gust_left -= delta
			if gust_left <= 0.0:
				gust = "gust"
				gust_left = GUST_SEC
				events.append({"type": "gust"})
		_:
			if band != Band.HIGH:
				return
			_next_gust -= delta
			if _next_gust <= 0.0:
				gust = "warn"
				gust_left = GUST_WARNING
				events.append({"type": "gust_warn", "warning": GUST_WARNING})


func _step_weather(delta: float, events: Array[Dictionary]) -> void:
	if raining:
		_rain_left -= delta
	match weather:
		Weather.CALM:
			_next_force -= delta
			if _next_force <= 0.0:
				force = _pick_force()
				weather = Weather.TELEGRAPH
				force_left = WARNING[force]
				events.append({"type": "telegraph", "force": force, "warning": force_left})
		Weather.TELEGRAPH:
			force_left -= delta
			if force_left <= 0.0:
				_start_force(events)
		Weather.ACTIVE:
			force_left -= delta
			if force == "rain":
				force_left = _rain_left
			if force_left <= 0.0:
				_end_force(events)


func _start_force(events: Array[Dictionary]) -> void:
	weather = Weather.ACTIVE
	events.append({"type": "force_start", "force": force})
	match force:
		"rain":
			raining = true
			_rain_left = RAIN_MIN + _rng.randf() * RAIN_JITTER
			force_left = _rain_left
		"bird":
			birds = mini(birds + 1, MAX_BIRDS)
			_bird_stay = BIRD_STAY
			events.append({"type": "bird_land", "birds": birds})
			_end_force(events)
		"downdraft":
			downdrafts += 1
			force_left = DOWNDRAFT_SEC
			_downdraft_band = band
			_downdraft_low = band


func _end_force(events: Array[Dictionary]) -> void:
	var ended := {"type": "force_end", "force": force}
	match force:
		"rain":
			raining = false
		"downdraft":
			var beaten := balloon == Balloon.FLYING and _downdraft_low >= _downdraft_band
			if beaten:
				downdrafts_beaten += 1
			ended["beaten"] = beaten
	events.append(ended)
	weather = Weather.CALM
	force = ""
	force_left = 0.0
	_next_force = FORCE_GAP_MIN + _rng.randf() * FORCE_GAP_JITTER


func _pick_force() -> String:
	var weights := FORCE_WEIGHTS.duplicate()
	if birds >= MAX_BIRDS:
		weights.erase("bird")
	var total := 0.0
	for k in weights:
		total += weights[k]
	var roll := _rng.randf() * total
	for k in weights:
		roll -= weights[k]
		if roll <= 0.0:
			return k
	return weights.keys()[-1]


func _pop(events: Array[Dictionary]) -> void:
	h = 0.0
	rate = 0.0
	pops += 1
	air = 0.0
	balloon = Balloon.POPPED
	state_left = POP_SEC
	gust = ""
	shake_progress = 0.0
	events.append({"type": "pop", "points": POP_PENALTY})
	if birds > 0:
		birds = 0
		events.append({"type": "birds_scatter"})
	# A warning or a downdraft is called off; rain is weather and carries on.
	if weather == Weather.TELEGRAPH or (weather == Weather.ACTIVE and force == "downdraft"):
		if weather == Weather.ACTIVE:
			_end_force(events)
		weather = Weather.CALM
		force = ""


func _arrive(events: Array[Dictionary]) -> void:
	balloon = Balloon.FLYING
	h = START_HEIGHT
	_grace = ARRIVE_GRACE
	x = fan_x
	band = band_of(h)
	_next_force = maxf(_next_force, CALM_AFTER_ARRIVE)
	_next_gust = _gust_gap()
	events.append({"type": "arrive"})


func _gust_gap() -> float:
	return GUST_GAP_MIN + _rng.randf() * GUST_GAP_JITTER


func _step_steer(delta: float, lean: float, tracking: bool, events: Array[Dictionary]) -> void:
	if not steer:
		efficiency = 1.0
		return
	fan_target = lean_to_fan(lean) if tracking else 0.0
	var eased := fan_x + (fan_target - fan_x) * (1.0 - exp(-delta / FAN_TAU))
	fan_x = move_toward(fan_x, eased, FAN_SPEED * delta)
	wind_gain = move_toward(wind_gain, 1.0 if tracking else 0.0, delta / WIND_FADE_SEC)
	_next_wind -= delta
	if _next_wind <= 0.0:
		_next_wind = WIND_GAP_MIN + _rng.randf() * WIND_GAP_JITTER
		wind_target = _rng.randf_range(-WIND_MAX, WIND_MAX)
		events.append({"type": "wind", "target": wind_target})
	wind = move_toward(wind, wind_target, 2.0 * WIND_MAX / WIND_EASE_SEC * delta)
	if balloon == Balloon.FLYING:
		x += ((wind * wind_gain - x) / DRIFT_TAU + CENTRING * (fan_x - x)) * delta
		x = clampf(x, -X_LIMIT, X_LIMIT)
	else:
		x = fan_x
	efficiency = steer_efficiency(x - fan_x)
