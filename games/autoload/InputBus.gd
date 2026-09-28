extends Node
## Every game's live inputs, refreshed once per frame (Bridge contract v1, docs/GAMES.md).
##
## On the bike this polls `OpenRideBridge.get_input_frame()` before any game processes. When
## the bridge singleton is absent (the editor on a desktop), it synthesises the same frames
## from the keyboard:
##   Left/Right = lean x, W/S = lean depth, +/- = cadence, [ ] = resistance,
##   Space = stand (toggle). P (pause) and Esc (end session) belong to Session.
## Games read the fields below and never touch the bridge themselves.

signal frame_updated

const BRIDGE := "OpenRideBridge"

## Input frame layout (contract indices).
const VERSION := 1
const I_VERSION := 0
const I_CADENCE := 1
const I_POWER := 2
const I_RESISTANCE := 3
const I_SPEED := 4
const I_HEART_RATE := 5
const I_LEAN_X := 6
const I_LEAN_DEPTH := 7
const I_STANDING := 8
const I_TRACKER_STATE := 9
const I_SEGMENT_TIME_LEFT := 10
const I_SENSORS_OK := 11
const FRAME_SIZE := 12

## tracker_state values.
const TRACKER_OFF := 0
const TRACKER_NEEDS_CALIBRATION := 1
const TRACKER_CALIBRATING := 2
const TRACKER_TRACKING := 3
const TRACKER_FACE_LOST := 4

var cadence := 0.0  ## rpm
var power := 0.0  ## watts
var resistance := 0.0  ## 0-100
var speed := 0.0  ## mph
var heart_rate := -1.0  ## bpm, -1 with no strap
var lean_x := 0.0  ## -1 (rider's left) .. +1 (right)
var lean_depth := 0.0  ## -1 (back) .. +1 (in); 0 when disabled
var standing := false
var tracker_state := TRACKER_OFF
var segment_time_left := -1.0  ## gameplay seconds left, -1 when open-ended
## While false, games freeze scoring and show the "sensors not detected" banner.
var sensors_ok := false
## The latest raw frame, for debugging.
var frame := PackedFloat64Array()

var _bridge: Object = null
var _warned_bad_frame := false

# Keyboard simulator state (desktop only).
const SIM_CADENCE_RATE := 40.0  # rpm per second while +/- is held
const SIM_RESISTANCE_RATE := 25.0  # points per second while [ or ] is held
const SIM_LEAN_RATE := 4.0  # full lean in a quarter second
var _sim_cadence := 80.0
var _sim_resistance := 35.0
var _sim_lean_x := 0.0
var _sim_lean_depth := 0.0
var _sim_standing := false


func _ready() -> void:
	# Read before any game, and keep reading while a game pauses the scene tree.
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	if Engine.has_singleton(BRIDGE):
		_bridge = Engine.get_singleton(BRIDGE)
	print("OPENRIDE_GAMES input %s" % ("bridge" if _bridge else "keyboard simulator"))


func is_simulated() -> bool:
	return _bridge == null


func _process(delta: float) -> void:
	var f: PackedFloat64Array = _bridge.get_input_frame() if _bridge else _simulate(delta)
	if f.size() < FRAME_SIZE or int(f[I_VERSION]) != VERSION:
		if not _warned_bad_frame:
			push_warning("InputBus: unexpected input frame %s" % [f])
			_warned_bad_frame = true
		return
	frame = f
	cadence = f[I_CADENCE]
	power = f[I_POWER]
	resistance = f[I_RESISTANCE]
	speed = f[I_SPEED]
	heart_rate = f[I_HEART_RATE]
	lean_x = f[I_LEAN_X]
	lean_depth = f[I_LEAN_DEPTH]
	standing = f[I_STANDING] > 0.5
	tracker_state = int(f[I_TRACKER_STATE])
	segment_time_left = f[I_SEGMENT_TIME_LEFT]
	sensors_ok = f[I_SENSORS_OK] > 0.5
	frame_updated.emit()


func _input(event: InputEvent) -> void:
	if _bridge or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		_sim_standing = not _sim_standing
		get_viewport().set_input_as_handled()


func _simulate(delta: float) -> PackedFloat64Array:
	_sim_lean_x = move_toward(_sim_lean_x, _key_axis([KEY_LEFT], [KEY_RIGHT]), SIM_LEAN_RATE * delta)
	_sim_lean_depth = move_toward(_sim_lean_depth, _key_axis([KEY_S], [KEY_W]), SIM_LEAN_RATE * delta)
	_sim_cadence = clampf(
		_sim_cadence + _key_axis([KEY_MINUS, KEY_KP_SUBTRACT], [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]) * SIM_CADENCE_RATE * delta,
		0.0, 140.0)
	_sim_resistance = clampf(
		_sim_resistance + _key_axis([KEY_BRACKETLEFT], [KEY_BRACKETRIGHT]) * SIM_RESISTANCE_RATE * delta,
		0.0, 100.0)
	var watts := sim_power(_sim_cadence, _sim_resistance)
	var f := PackedFloat64Array()
	f.resize(FRAME_SIZE)
	f[I_VERSION] = VERSION
	f[I_CADENCE] = roundf(_sim_cadence)
	f[I_POWER] = roundf(watts)
	f[I_RESISTANCE] = roundf(_sim_resistance)
	f[I_SPEED] = sim_speed(watts)
	f[I_HEART_RATE] = -1.0
	f[I_LEAN_X] = _sim_lean_x
	f[I_LEAN_DEPTH] = _sim_lean_depth
	f[I_STANDING] = 1.0 if _sim_standing else 0.0
	f[I_TRACKER_STATE] = TRACKER_TRACKING
	f[I_SEGMENT_TIME_LEFT] = Session.local_time_left()
	f[I_SENSORS_OK] = 1.0
	return f


## A rough stand-in for the bike's power, good enough to play with: ~190 W at 90 rpm / 40%.
static func sim_power(rpm: float, resistance_pct: float) -> float:
	return rpm * (0.3 + resistance_pct * 0.045)


## A rough stand-in for the app's derived speed, in mph.
static func sim_speed(watts: float) -> float:
	return sqrt(maxf(watts, 0.0)) * 1.3


func _key_axis(negative: Array, positive: Array) -> float:
	var value := 0.0
	for key in negative:
		if Input.is_key_pressed(key):
			value -= 1.0
			break
	for key in positive:
		if Input.is_key_pressed(key):
			value += 1.0
			break
	return value
