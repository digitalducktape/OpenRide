extends Game
## Balloon Pump (#76): the bike drives an air pump at a daylight fairground stall. Fill balloons
## as fast as you can; each one pushes back harder as it fills, so the last part asks for the
## knob. A full balloon ties itself off and floats up into the bunch over the stall.
##
## Rules: `PumpLogic` (tested headless; DESIGN.md is the design record). View: `PumpStage` (2D, drawn
## in code on the full canvas, Safe Cracker's way; ART_BIBLE.md). HUD widget: `PumpStatus`. Audio: `PumpAudio` (rendered music and effects). This scene wires them to the framework: declarations, scoring through award(),
## the Mode option, the result's variant and stats.

## The look (framework/ui/UI_STYLE.md §4): a daylight fairground stall. Candy pink on deep plum,
## badges leaning a little; distinct from Tug's rope orange and every other game's accent.
const PumpAudioScript := preload("res://games/balloon_pump/PumpAudio.gd")

static var look := GameTheme.new(Color("ff5fa2"), Color("2b0f2a"), 0.1)

const INTRO_ICON := Vector2(160, 200)  ## each balloon's box on the intro card
## The place changes after every Race heat, or after this many balloons in Max (ART_BIBLE §6).
const BALLOONS_PER_PLACE := 6
## The gauge's scale ends this far past the biggest balloon's top line.
const GAUGE_HEADROOM := 1.4

var logic: PumpLogic
var world: PumpStage

var _status: PumpStatus
var _audio = PumpAudioScript.new()

var _place := 0
var _gauge_max := 100.0

var _mode_name := "max"
var _message_left := 0.0


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "balloon_pump"
	i.title = "Balloon Pump"
	i.how_to = "Pedal to pump; the last bit of each balloon pushes back"
	i.supports = ["minutes", "rounds", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work", "recovery"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points a minute (DESIGN.md §4; pump_logic_test checks them): a strong steady ride at 60% of
	# FTP and 1.0× is 2 stars, the same ride at 1.3× effort is 3.
	i.star_thresholds = {
		"easy": [300, 600, 1000],
		"standard": [350, 650, 1050],
		"hard": [400, 700, 1100],
	}
	# Race adds a time bonus for heats won early.
	i.variant_star_thresholds = {"race": {
		"easy": [400, 750, 1150],
		"standard": [350, 700, 1100],
		"hard": [300, 650, 1050],
	}}
	# The summary's tiles beside points and time: the balloons filled, gold, and the heats won.
	i.summary_stats = [
		{"key": "balloons", "label": "balloons"},
		{"key": "gold", "label": "gold"},
		{"key": "heats_won", "label": "heats won", "of": "heats"},
	]
	i.options = [
		{"key": "mode", "label": "Mode", "choices": ["race", "max"],
			"labels": ["Race", "Max"], "default": "race", "kind": "segmented"},
	]
	return i


func ui_theme() -> GameTheme:
	return look


## The intro card's picture: in Race the heat's goal, then the four balloons, big, with their
## points (gold labelled "Gold ×3"), so the kinds are known before the first one loads. Every
## number comes from the segment's params (the race's size and length) or the rules' constants.
func intro_visual() -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	var goal := race_line(segment)
	if not goal.is_empty():
		var g := look.label(goal, HudTheme.BODY, GameTheme.TARGET, true)
		g.name = "RaceLine"
		g.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(g)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 40)
	box.add_child(row)
	for kind in ["small", "medium", "large", "gold"]:
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.alignment = BoxContainer.ALIGNMENT_END
		var icon := Control.new()
		icon.name = "Balloon_%s" % kind
		icon.custom_minimum_size = INTRO_ICON
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var size: float = PumpArt.BALLOON_RADIUS[kind] / PumpArt.BALLOON_RADIUS.large
		icon.draw.connect(func() -> void:
			var b := ShapeBatch.new()
			PumpStatus._balloon(b, Vector2(INTRO_ICON.x * 0.5, INTRO_ICON.y * 0.43), 4.4 * size, PumpArt.BALLOON_COLORS[kind], look.ink, kind == "gold")
			b.draw(icon))
		col.add_child(icon)
		var points := PumpLogic.POINTS_PER_AIR * float(PumpLogic.KINDS[kind].air)
		var text := "Gold ×%d" % roundi(PumpLogic.GOLD_FACTOR) if kind == "gold" else "%d pts" % roundi(points)
		var l := look.label(text, HudTheme.SMALL + 6, GameTheme.TARGET if kind == "gold" else GameTheme.INK, true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		row.add_child(col)
	return box


## The intro card's how-to (rider-approved copy), broken at its sentence so "end" isn't left alone
## on a line.
func how_to_text(_seg: Dictionary) -> String:
	return "Pedal to pump up balloons.\nEach one gets harder to fill near the end"


## "Race: fill N balloons in M:SS" from the segment's params; "" outside Race.
func race_line(seg: Dictionary) -> String:
	if _mode_for(seg) != "race":
		return ""
	return "Race: fill %d balloons in %s" % [_race_target(seg), _clock(_race_sec(seg))]


func target_text(seg: Dictionary) -> String:
	var p: Dictionary = seg.get("params", {})
	var ftp := float(p.get("ftp_watts", PumpLogic.DEFAULT_FTP))
	var recovery := str(seg.get("role", "free")) == "recovery"
	var line := PumpLogic.LINE_RECOVERY if recovery else PumpLogic.LINE_WORK
	var lo := float(p.get("push_lo_watts", ftp * line.x))
	var hi := float(p.get("push_hi_watts", ftp * line.y))
	# The biggest balloon's top line: past it, every balloon finishes.
	var top := lo + (hi - lo) * float(PumpLogic.KINDS.large.line)
	return "Get above %d W to finish each balloon" % roundi(top)


## Circuits always play Max (issue #76); a Just Ride plays the rider's Mode.
func _mode_for(seg: Dictionary) -> String:
	if str(seg.get("role", "free")) != "free":
		return "max"
	return option("mode")


func _race_target(seg: Dictionary) -> int:
	return int(seg.get("params", {}).get("race_balloons", PumpLogic.RACE_TARGET))


func _race_sec(seg: Dictionary) -> float:
	return float(seg.get("params", {}).get("race_sec", PumpLogic.HEAT_SEC))


static func _clock(sec: float) -> String:
	var s := roundi(sec)
	return "%d:%02d" % [s / 60, s % 60]


func _ready() -> void:
	PumpAudioScript.register()
	world = PumpStage.new()
	world.name = "Stage"
	add_child(world)


func _on_prepare(seg: Dictionary) -> void:
	_mode_name = _mode_for(seg)
	var rounds := 0
	if str(seg.get("end_mode", "timer")) == "game" and params.has("rounds"):
		rounds = maxi(int(params.rounds), 1)
	var recovery := str(seg.get("role", "free")) == "recovery"
	logic = PumpLogic.new(rng.seed, params, _mode_name, rounds > 0, rounds, recovery)
	variant = "race" if _mode_name == "race" else ""
	_gauge_max = logic.line_at(1.0, "large") * GAUGE_HEADROOM
	hud.set_skin(look.hud_skin())
	_status = PumpStatus.new(look)
	hud.add_widget(_status)
	# One watts reading on screen: the ride panel shows the smoothed watts the rules use, with a
	# gauge ticked at the biggest balloon's push line, and its rpm gauge at the "keep pumping" floor.
	hud.metrics.set_power_source(func() -> float: return logic.smoothed)
	hud.metrics.set_power_band(logic.line_at(1.0, "large"))
	hud.metrics.set_cadence_band(PumpLogic.KEEP_PUMPING_RPM)
	_audio = PumpAudioScript.new()
	PumpAudioScript.start_music()
	PumpStage.prebuild()
	_place = rng.randi_range(0, PumpPlaces.count() - 1)
	world.set_place(_place)
	world.set_balloons(logic.kind, logic.next_kind)
	_update_world(0.0)
	world.prewarm()
	_update_status()


func _on_frame(delta: float) -> void:
	var events := logic.step(delta, InputBus.power, InputBus.cadence, InputBus.sensors_ok)
	for event in events:
		_handle(event)
		_audio.on_event(event)
	_audio.step(delta, logic, InputBus.cadence)
	AudioDirector.set_intensity(PumpAudioScript.intensity(logic))
	_update_world(delta)
	_update_status()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	won = logic.race_won()


func _handle(event: Dictionary) -> void:
	match event.type:
		"filled":
			award(event.points)
			world.tie_off(event.kind)
			if logic.mode != "race" and logic.balloons % BALLOONS_PER_PLACE == 0:
				_next_place()
			if event.gold:
				_show_message("Gold! +%d" % roundi(event.points), 1.5, GameTheme.TARGET)
		"heat_start":
			if int(event.heat) > 1:
				_next_place()
			if logic.mode == "race":
				_show_message("Fill %d in %s!" % [event.target, _clock(event.sec)], 2.0)
		"warn_time":
			_show_message("10 s left!", 1.5, GameTheme.WARN)
		"heat_end":
			if event.bonus > 0.0:
				award(event.bonus)
			if event.won == true:
				world.celebrate()
				_show_message("Race won! +%d" % roundi(event.bonus), PumpLogic.BREAK_SEC, GameTheme.GOOD)
			elif event.won == false:
				_show_message("Time! %d filled" % event.balloons, PumpLogic.BREAK_SEC, GameTheme.WARN)
			else:
				_show_message("%d balloons!" % event.balloons, PumpLogic.BREAK_SEC, GameTheme.GOOD)
		"loaded":
			world.set_balloons(event.kind, event.next)
		"over":
			end_segment()


## The result's stats, built once at the end.
func finish() -> Dictionary:
	if logic == null:
		return super.finish()
	stats = {
		"mode": _mode_name,
		"balloons": logic.balloons,
		"gold": logic.gold,
		"avg_power": roundi(logic.avg_power()),
		"peak_power": roundi(logic.peak_power),
		"fastest_balloon_sec": snappedf(logic.fastest_balloon_sec, 0.1),
	}
	# The race's result, for the summary's tiles; Max has none.
	if logic.mode == "race":
		stats["heats"] = logic.heats_done
		stats["heats_won"] = logic.heats_won
	return super.finish()


## The hub card's picture (tests/capture_hub_cards.gd): a bunch already up and a big balloon
## nearly full on the nozzle.
func pose_for_card() -> void:
	world.pose(["medium", "small", "large", "gold", "small", "medium", "large", "small", "medium", "small",
		"large", "medium"], "large", 0.85)


## The next place (a heat ends, or every few balloons in Max): never the same twice running.
func _next_place() -> void:
	_place = (_place + 1 + rng.randi_range(0, PumpPlaces.count() - 2)) % PumpPlaces.count()
	world.set_place(_place)


func _update_world(delta: float) -> void:
	var loaded := logic.has_balloon()
	world.update_view(delta, logic.fill, logic.leaking, logic.open, logic.smoothed / _gauge_max,
		logic.push_line() / _gauge_max, InputBus.cadence if playing else 0.0, loaded)


func _update_status() -> void:
	var state := "filling"
	match logic.phase:
		PumpLogic.Phase.BREAK, PumpLogic.Phase.OVER:
			state = "rest"
		PumpLogic.Phase.TIE, PumpLogic.Phase.LOAD:
			state = "full"
		_:
			if logic.keep_pumping and playing:
				state = "pedal"
			elif logic.open < 0.5:
				state = "push"
	_status.set_state(logic.smoothed / _gauge_max, logic.push_line() / _gauge_max, state)
	_status.set_count(logic.balloons)
	_status.set_race(logic.heat_balloons, logic.race_target if logic.mode == "race" else 0, logic.heat_left)
	_status.set_next(logic.next_kind)


func _show_message(text: String, seconds: float, color := GameTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
