extends Game
## Safe Cracker (#41): dial the resistance knob to the numbers of a combination and hold each
## one to click a tumbler, a skill game that doubles as active recovery. Pedal too hard and the
## alarm trips; pedal too gently and the dial loses power. Each safe cracked opens the next, in a
## different random place, harder than the last: the goal is how many safes you can get into.
##
## Rules: `SafeLogic` (tested headless). Drawing: `SafeBackdrop`, `SafeBody` and `SafeDial`, all
## shapes drawn in code. Audio: `SafeAudio`. This scene wires them to the framework:
## declarations, the HUD widget, scoring through award(), music and effects through
## AudioDirector, and the rider's options (place, hints, sound) through `GameOptions`.

const SafeAudioScript := preload("res://games/safe_cracker/SafeAudio.gd")

const MUSIC_STYLE := {
	"name": "noir",
	# Drums and bass always; the harmony and lead come in when the rider is steady.
	"stem_gates": {"harmony": 0.3, "lead": 0.6},
}
const BODY_HOME := Vector2(960, 645)  ## the door's centre on the 1920x1080 canvas
const SLIDE_FROM := 1500.0  ## a new safe slides in from the right
const DOOR_SEC := 1.3

var logic: SafeLogic

var _backdrop: SafeBackdrop
var _body_root: Node2D
var _body: SafeBody
var _dial: SafeDial
var _status: SafeStatus
var _place := 0
var _place_rng := RandomNumberGenerator.new()
var _tick_left := 0.0
var _message_left := 0.0
var _door_tween: Tween
var _slide_tween: Tween


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "safe_cracker"
	i.title = "Safe Cracker"
	i.how_to = "Turn the resistance knob to each number and hold it"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["recovery"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = false
	i.stars_per_minute = true
	# Points per minute of gameplay. A vault is worth up to 1200 (1000 less 5 a second and 100 an
	# alarm, plus 200 for opening it), so the stars come mostly from how many safes you open a
	# minute: effort can't earn them here. safe_logic_test models a rider turning the knob at
	# 2 units/s (a careful rider: 2 stars) and at 4+ (a quick, accurate one: 3 stars), with the
	# reading lagging the knob by 0.6 s. Provisional: tune on the bike, where real lag and
	# overshoot will slow everyone down.
	i.star_thresholds = {
		"easy": [500, 1300, 2600],
		"standard": [500, 1200, 2500],
		"hard": [450, 1100, 2050],
	}
	i.options = [
		{"key": "scene", "label": "Place", "choices": ["random", "office", "bank", "museum", "cabin", "lab", "library"],
			"labels": ["Random", "Night office", "Bank vault", "Museum hall", "Ship's cabin", "Laboratory", "Old library"],
			"default": "random"},
		{"key": "hints", "label": "Target number", "choices": ["show", "hide"],
			"labels": ["Show it", "Hide it"], "default": "show"},
		{"key": "sound", "label": "Click sounds", "choices": ["on", "off"],
			"labels": ["On", "Off"], "default": "on"},
	]
	return i


func how_to_text(_seg: Dictionary) -> String:
	return "Turn the resistance knob to each number and hold it. Crack as many safes as you can"


func target_text(seg: Dictionary) -> String:
	var cap := float(seg.get("params", {}).get("power_cap_watts", 0.0))
	return "Keep your power under %d W, or the alarm trips" % roundi(cap) if cap > 0.0 else "Pedal gently: easy spinning"


func _ready() -> void:
	SafeAudioScript.register()
	var wall := ColorRect.new()  # under everything, so a frame is never empty
	wall.color = Color(0.05, 0.05, 0.07)
	wall.size = SafePlaces.SIZE
	wall.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(wall)
	_backdrop = SafeBackdrop.new()
	_backdrop.name = "Backdrop"
	add_child(_backdrop)
	_body_root = Node2D.new()
	_body_root.name = "SafeRoot"
	_body_root.position = BODY_HOME
	add_child(_body_root)
	_body = SafeBody.new()
	_body.name = "Body"
	_body_root.add_child(_body)
	_dial = SafeDial.new()
	_dial.name = "Dial"
	_body_root.add_child(_dial)


func _on_prepare(seg: Dictionary) -> void:
	logic = SafeLogic.new(rng.seed, difficulty, params, str(seg.get("role", "free")) != "free")
	_place_rng.seed = rng.seed + 1
	_place = _pick_place(-1)
	_show_place()
	_apply_dial()
	_status = SafeStatus.new()
	hud.add_widget(_status)
	hud.metrics.set_cadence_band(logic.cadence_min)
	AudioDirector.play_music(MUSIC_STYLE, logic.cadence_min + 15.0, int(seg.get("seed", 0)))
	AudioDirector.set_intensity(0.5)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, SafeAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, SafeAudioScript.sfx_effects())
	_update_status()


func _on_option_changed(key: String, _value: String) -> void:
	if key == "scene":
		_place = _pick_place(-1)
		_show_place()


func _pick_place(not_index: int) -> int:
	var fixed := SafePlaces.index_of(option("scene"))
	return fixed if fixed >= 0 else SafePlaces.random_index(_place_rng, not_index)


func _show_place() -> void:
	_backdrop.set_place(_place)
	_body.set_place(_place)
	var place := SafePlaces.place(_place)
	_dial.colour = place.safe
	_dial.accent = place.accent


func _on_frame(delta: float) -> void:
	var events := logic.step(delta, InputBus.resistance, InputBus.cadence, InputBus.power)
	for event in events:
		_handle(event)
	_apply_dial()
	_update_status()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	var hidden := logic.hidden or option("hints") == "hide"
	if hidden and not logic.is_open() and logic.powered and option("sound") == "on":
		_tick_left -= delta
		var closeness := logic.closeness()
		if closeness > 0.15 and _tick_left <= 0.0:
			_tick_left = lerpf(0.9, 0.12, closeness * closeness)
			AudioDirector.play_sfx("proximity_tick", -4.0, lerpf(0.9, 1.4, closeness))
	AudioDirector.set_intensity(0.15 if logic.alarm_left > 0.0 else 0.5)
	won = logic.cracked >= 1
	stats = {
		"vaults": logic.cracked,
		"fastest_crack": snappedf(maxf(logic.fastest, 0.0), 0.1),
		"alarms": logic.total_alarms,
		"avg_power": roundi(logic.avg_power()),
	}


func _apply_dial() -> void:
	var hidden := logic.hidden or option("hints") == "hide"
	_dial.reading = logic.reading
	_dial.target = logic.target()
	_dial.tolerance = logic.tolerance
	_dial.target_hidden = hidden
	_dial.hold_frac = clampf(logic.progress / logic.hold_sec, 0.0, 1.0)
	_dial.closeness = logic.closeness()
	_dial.powered = logic.powered
	_dial.tumblers_done = logic.tumbler
	_dial.tumblers_total = logic.combo.size()
	_dial.alarm = clampf(logic.alarm_left / SafeLogic.ALARM_SHOW_SEC, 0.0, 1.0)
	_dial.refresh()


func _update_status() -> void:
	var hidden := logic.hidden or option("hints") == "hide"
	var cap := logic.power_cap
	var power_text := "Easy on the pedals: under %d W" % roundi(cap) if cap > 0.0 else "Easy on the pedals"
	var alert := ""
	if logic.alarm_left > 0.0:
		alert = "ALARM"
	elif not logic.powered:
		alert = "PEDAL"
	_status.set_state("VAULT %d · %d cracked" % [logic.vault, logic.cracked],
		"Follow the ticks" if hidden else "Target %d" % logic.target(), power_text, alert,
		cap > 0.0 and InputBus.power > cap)


func _handle(event: Dictionary) -> void:
	match event.type:
		"tumbler":
			if option("sound") == "on":
				AudioDirector.play_sfx("tumbler_click", -2.0, 1.0 + 0.06 * event.index)
		"alarm":
			AudioDirector.play_sfx("soft_alarm")
			_show_message("Easy on the pedals!", 1.6, HudTheme.WARN)
		"vault_open":
			award(event.points)
			AudioDirector.play_sfx("vault_open")
			AudioDirector.play_sfx("door_creak", -6.0)
			_show_message("Safe cracked! +%d" % roundi(event.points), SafeLogic.OPEN_SEC, HudTheme.GOOD)
			if _door_tween:
				_door_tween.kill()
			_door_tween = create_tween()
			_door_tween.tween_property(_dial, "door_open", 1.0, DOOR_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
			_dial.refresh()
		"new_vault":
			_dial.door_open = 0.0
			_place = _pick_place(_place)
			_show_place()
			_body_root.position.x = BODY_HOME.x + SLIDE_FROM
			if _slide_tween:
				_slide_tween.kill()
			_slide_tween = create_tween()
			_slide_tween.tween_property(_body_root, "position:x", BODY_HOME.x, 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _show_message(text: String, seconds: float, color := HudTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
