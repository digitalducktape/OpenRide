extends Game
## Gate Crasher (#80): show jumping in first person from the saddle. Pedal to canter round a course
## of fences, and stand up on the bike at each take-off line to clear it. DESIGN.md has the rules
## and the tuning; ART_BIBLE.md the look.
##
## Rules: `GateLogic` (tested headless). Course: `GateCourse`. View: `GateWorld` (3D). HUD widget:
## `GateStatus`. This scene wires them to the framework: declarations, the widget and the ride
## metrics' power band, scoring through award() and penalize(), the music, effects and callouts,
## and the result.
##
## The rider's watts show only in the ride panel; the pace appears there as the band's tick.

const GateMusic := preload("res://games/gate_crasher/GateMusic.gd")

## "Clear Round" (GateMusic): the bed always; the harmony (and the horn call, over the intro card)
## from the start; the lead, which has the hook, at a canter, dropping out for LEAD_REST_SEC after a rail.
const MUSIC_STYLE := {
	"name": "clear_round",
	"stem_files": GateMusic.STEM_FILES,
	"loop_from": GateMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
## Points a minute (`stars_per_minute`). 3 stars sits above a perfect ride flat out at 1.0x and
## below a perfect ride at pace at 1.3x (gate_crasher_logic_test).
const STARS := {"easy": [220.0, 500.0, 860.0], "standard": [260.0, 560.0, 880.0], "hard": [300.0, 600.0, 900.0]}
## The 3D view renders into a SubViewport at this share of the screen's resolution, drawn scaled
## up under the HUD (Dodge Ball's pattern: the tablet's GPU is fill-rate bound at 1080p).
const RENDER_SCALE := 0.62
const RESULT_END_DELAY := 2.5  ## after the last round, the segment ends this much later
const CALLOUT_SEC := 1.3
const MIN_STRIDE_SPEED := 1.0  ## m/s: under this the hoofbeats stop
const CANTER_SPEED := 4.0  ## m/s: the lead comes in
const LEAD_REST_SEC := 6.0  ## after a rail, the tune stays out this long: until about the next fence

## The look (framework/ui/UI_STYLE.md): rosette teal on a dark pine, a slight lean.
static var look := GameTheme.new(GateMeshes.ACCENT, GateMeshes.INK, 0.08)

var logic: GateLogic
var world: GateWorld

var _view: SubViewport
var _shown: MeshInstance2D
var _status: GateStatus
var _mode := "open"
var _stage := 0
var _message_left := 0.0
var _round_faults := 0
var _end_left := -1.0
var _lead_rest := 0.0
var _band_set := false
## Steps the 3D view down to a lower render scale if the frame rate stays low.
var governor := RenderScaleStep.new()
var _view_scale := RENDER_SCALE


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "gate_crasher"
	i.title = "Gate Crasher"
	i.how_to = "Pedal to canter, and stand up at the line to jump"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work"]
	i.tracker_mode = "lean_stand"  # camera only: the stand is the game
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	i.star_thresholds = STARS
	i.summary_stats = [{"key": "clears", "label": "clear jumps", "of": "fences"}, {"key": "faults", "label": "faults"},
		{"key": "clear_rounds", "label": "clear rounds"}]
	return i


func how_to_text(seg: Dictionary) -> String:
	return "Stand on the last chime: you have %.1f s either side of the line" % (_level_logic(seg).window_sec / 2.0)


## The intro card's target, every number from the segment.
func target_text(seg: Dictionary) -> String:
	var l := _level_logic(seg)
	return "%d fences a round at %d W" % [l.fences, roundi(l.pace_watts)]


func _level_logic(seg: Dictionary) -> GateLogic:
	return GateLogic.new(seg.get("params", {}), str(seg.get("difficulty", "standard")))


## The intro card's picture: the fence, the line and the jump.
func intro_visual() -> Control:
	return GateIntroArt.new(look)


func ui_theme() -> GameTheme:
	return look


## rounds (a rounds Just Ride), timed or open.
static func _mode_for(seg: Dictionary) -> String:
	if float(seg.get("duration_sec", -1)) < 0.0:
		return "open"
	if str(seg.get("end_mode", "timer")) == "game" and seg.get("params", {}).has("rounds"):
		return "rounds"
	return "timed"


func _ready() -> void:
	GateAudio.register()
	world = GateWorld.new()
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
	_mode = _mode_for(seg)
	logic = GateLogic.new(params, difficulty, _mode, int(params.get("rounds", 1)))
	_stage = 0
	_round_faults = 0
	_end_left = -1.0
	_lead_rest = 0.0
	_band_set = false
	governor = RenderScaleStep.new()
	_set_render_scale(RENDER_SCALE)
	world.build(logic.fences, logic.spacing, GateLogic.LINE_GAP, GateLogic.V_PACE)
	world.set_marker(0, 0)
	hud.set_skin(look.hud_skin())
	_status = GateStatus.new(look)
	hud.add_widget(_status)
	_status.set_fences(logic.fences)
	_update_status()
	AudioDirector.play_music(MUSIC_STYLE, GateMusic.BPM)
	AudioDirector.set_intensity(0.6)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, GateAudio.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, GateAudio.sfx_effects())
	AudioDirector.set_bus_effects(AudioDirector.MASTER_BUS, GameMix.master_effects())
	world.update_view(0.0, 0.0, 0.0, 0.0, 0.0, GateLogic.CIRCLE_RADIUS)
	world.prewarm()


func _on_frame(delta: float) -> void:
	if governor.sample(delta, logic.phase == GateLogic.Phase.RIDE):
		_set_render_scale(governor.render_scale(RENDER_SCALE))
		print("OPENRIDE_GAMES gate_crasher quality tier=%d fps=%.1f scale=%.2f" % [
			governor.tier, governor.last_fps, governor.render_scale(RENDER_SCALE)])
	# Anything but tracking: a stand can't be seen, so no fence may be judged (a failed calibration
	# reads 0, and on the tablet it faulted every fence before this).
	var camera_ok := InputBus.tracker_state == InputBus.TRACKER_TRACKING
	var events := logic.step(delta, InputBus.power, InputBus.cadence, InputBus.standing, camera_ok, InputBus.sensors_ok)
	if logic.last_points > 0.0:
		award(logic.last_points)
	for event in events:
		_handle(event)
	world.update_view(delta, logic.distance, logic.speed, logic.arc_height(), logic.circle_angle, GateLogic.CIRCLE_RADIUS)
	world.set_marker(logic.fence % logic.fences, _stage)
	if world.take_stride() and logic.speed >= MIN_STRIDE_SPEED and logic.arc_height() <= 0.0:
		AudioDirector.play_sfx("hoof_canter", -12.0)
	_lead_rest = maxf(_lead_rest - delta, 0.0)
	AudioDirector.set_intensity(1.0 if logic.speed >= CANTER_SPEED and _lead_rest <= 0.0 else 0.6)
	_update_status()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	if _end_left >= 0.0:
		_end_left -= delta
		if _end_left < 0.0:
			end_segment()


func _update_status() -> void:
	_status.set_progress(logic.fence_in_round(), logic.round_index, logic.results)
	if logic.phase == GateLogic.Phase.CIRCLE:
		_status.set_chip("circling", 0)
	elif playing and not logic.pedalling:
		_status.set_chip("pedal", 0)
	elif _round_faults > 0:
		_status.set_chip("faults", _round_faults)
	else:
		_status.set_chip("clear", 0)
	if not _band_set:
		_band_set = true
		hud.metrics.set_power_band(roundi(logic.pace_watts))


func _handle(event: Dictionary) -> void:
	match event.type:
		"beat":
			_stage = 4 - int(event.n)
			AudioDirector.play_sfx("count_tick", -5.0)
			_show_message(str(event.n), 0.8, GameTheme.TARGET)
		"sit_first":
			AudioDirector.play_sfx("rein_warn", -4.0)
		"line":
			_stage = 4
			AudioDirector.play_sfx("line_chime", -2.0)
			_show_message("STAND!", 1.0, look.accent)
		"stand_ok":
			AudioDirector.play_sfx("take_chime", -2.0)
		"jump":
			AudioDirector.play_sfx("lift_off", -5.0)
		"land":
			AudioDirector.play_sfx("landing", -3.0)
			world.landing_dust()
		"clear":
			_stage = 0
			award(event.points)
			GameTheme.pop(hud.score, 1.15)
			_show_message("Clear!", CALLOUT_SEC, look.accent)
		"fault":
			_stage = 0
			penalize(event.penalty)
			_round_faults += GateLogic.FAULTS_PER_RAIL
			_lead_rest = LEAD_REST_SEC
			world.knock_rail(event.fence)
			AudioDirector.play_sfx("rail_clatter", -1.0)
			GameMix.duck_for_moment(1.0)
			_show_message("4 faults: too early" if event.why == "early" else "4 faults: too late", CALLOUT_SEC + 0.4, GameTheme.BAD)
		"no_pedal":
			_stage = 0
			AudioDirector.play_sfx("rein_warn", -4.0)
			_show_message("Keep pedalling!", CALLOUT_SEC, GameTheme.WARN)
		"round_end":
			_round_ended(event)
		"circle":
			_stage = 0
			AudioDirector.play_sfx("rein_warn", -4.0)
			_show_message("Can't see you: circling", 2.5, GameTheme.WARN)
		"circle_end":
			hud.hide_message()
			_message_left = 0.0
		"done":
			_end_left = RESULT_END_DELAY


func _round_ended(event: Dictionary) -> void:
	_round_faults = 0
	if event.clear:
		award(event.bonus)
		world.clear_round_burst()
		AudioDirector.play_sfx("clear_round")
		AudioDirector.play_sfx("applause", -6.0)
		GameMix.duck_for_sting(2.5)
		_show_message("Clear round!", 2.2, GameTheme.TARGET)
	else:
		AudioDirector.play_sfx("applause", -14.0)
	if logic.phase != GateLogic.Phase.DONE:
		world.reset_rails()


func finish() -> Dictionary:
	if logic == null:
		return super.finish()
	stats = {
		"clears": logic.clears,
		"fences": logic.fences_done,
		"faults": logic.faults,
		"clear_rounds": logic.clear_rounds,
		"avg_power": roundi(logic.avg_power()),
	}
	return super.finish()


## The hub card's picture: the first fence, from just past its line.
func pose_for_card() -> void:
	world.update_view(0.0, logic.line_s(0) + 2.0, 0.0, 0.0, 0.0, GateLogic.CIRCLE_RADIUS)


func _fit_view() -> void:
	_shown.position = -Stage.pad
	_shown.mesh = PullMeshes.view_image(Stage.visible_size)
	_set_render_scale(_view_scale)


## The 3D view renders at `scale` of the screen's resolution (drawn scaled up under the HUD).
func _set_render_scale(scale: float) -> void:
	_view_scale = scale
	var size := Stage.view_size(scale)
	if _view.size != size:
		_view.size = size


func _show_message(text: String, seconds: float, color := GameTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
