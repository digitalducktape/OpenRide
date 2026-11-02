extends Game
## Balloon Pump (#76): the bike drives an air pump at a daylight fairground stall. Fill balloons
## as fast as you can; each one pushes back harder as it fills, so the last part asks for the
## knob. A full balloon ties itself off and floats up into the bunch over the stall.
##
## Rules: `PumpLogic` (tested headless; DESIGN.md is the design record). View: `PumpWorld` (3D,
## ART_BIBLE.md). This scene wires them to the framework: declarations, scoring through award(),
## the Mode option, the result's variant and stats.

## The look (framework/ui/UI_STYLE.md §4): a daylight fairground stall. Candy pink on deep plum,
## badges leaning a little; distinct from Tug's rope orange and every other game's accent.
static var look := GameTheme.new(Color("ff5fa2"), Color("2b0f2a"), 0.1)

## The 3D view renders into a SubViewport at this share of the window's resolution, drawn scaled
## up under the HUD (Dodge Ball's and Tug's tablet recipe: the GPU is fill-rate bound at 1080p).
const RENDER_SCALE := 0.62
## The gauge's scale ends this far past the biggest balloon's top line.
const GAUGE_HEADROOM := 1.4

var logic: PumpLogic
var world: PumpWorld

var _view: SubViewport
var _shown: MeshInstance2D
var _view_scale := RENDER_SCALE
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
	i.options = [
		{"key": "mode", "label": "Mode", "choices": ["race", "max"],
			"labels": ["Race", "Max"], "default": "race", "kind": "segmented"},
	]
	return i


func ui_theme() -> GameTheme:
	return look


func how_to_text(seg: Dictionary) -> String:
	if _mode_for(seg) == "race":
		return "Race: fill %d balloons in %s" % [_race_target(seg), _clock(_race_sec(seg))]
	return "Fill as many balloons as you can"


func target_text(seg: Dictionary) -> String:
	var p: Dictionary = seg.get("params", {})
	var ftp := float(p.get("ftp_watts", PumpLogic.DEFAULT_FTP))
	var recovery := str(seg.get("role", "free")) == "recovery"
	var hi := float(p.get("push_hi_watts", ftp * (PumpLogic.LINE_RECOVERY.y if recovery else PumpLogic.LINE_WORK.y)))
	return "Push past %d W to finish a balloon" % roundi(hi)


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
	world = PumpWorld.new()
	world.name = "World"
	_view = SubViewport.new()
	_view.name = "View3D"
	_view.msaa_3d = Viewport.MSAA_DISABLED
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	_view.add_child(world)
	_shown = MeshInstance2D.new()
	_shown.name = "View3DImage"
	_shown.texture = _view.get_texture()
	_shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_shown)
	_fit_view()
	Stage.changed.connect(_fit_view)


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
	world.set_balloons(logic.kind, logic.next_kind)
	_update_world(0.0)
	world.prewarm()


func _on_frame(delta: float) -> void:
	var events := logic.step(delta, InputBus.power, InputBus.cadence, InputBus.sensors_ok)
	for event in events:
		_handle(event)
	_update_world(delta)
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
			if event.gold:
				_show_message("Gold! +%d" % roundi(event.points), 1.5, GameTheme.TARGET)
		"heat_start":
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
		"heats": logic.heats_done,
		"heats_won": logic.heats_won,
		"fastest_balloon_sec": snappedf(logic.fastest_balloon_sec, 0.1),
	}
	return super.finish()


func _update_world(delta: float) -> void:
	var loaded := logic.has_balloon()
	world.update_view(delta, logic.fill, logic.leaking, logic.open, logic.smoothed / _gauge_max,
		logic.push_line() / _gauge_max, InputBus.cadence if playing else 0.0, loaded)


## The 3D view renders at `scale` of the window's resolution (drawn scaled up under the HUD).
func _set_render_scale(scale: float) -> void:
	_view_scale = scale
	var size := Stage.view_size(scale)
	if _view.size != size:
		_view.size = size


## The view over the whole window, past the centred stage (#57), whenever the window changes.
func _fit_view() -> void:
	_shown.position = -Stage.pad
	_shown.mesh = PumpMeshes.view_image(Stage.visible_size)
	_set_render_scale(_view_scale)


func _show_message(text: String, seconds: float, color := GameTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
