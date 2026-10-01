extends Game
## Dodge Ball (#39): ride a wide road in first person; lean to dodge the balls rolling and
## bouncing at you. Pedal above the cadence floor to keep your shield; push past the power
## target to double your points.
##
## Rules: `DodgeBallLogic` (tested headless). View: `DodgeWorld` (3D). Audio: `DodgeAudio`.
## This scene wires them to the framework: declarations, HUD widgets, scoring through
## award()/penalize(), music and effects through AudioDirector, and the rider's options
## (scene lighting and camera roll) through `GameOptions`.

const DodgeAudioScript := preload("res://games/dodge_ball/DodgeAudio.gd")
const DodgeWorldScript := preload("res://games/dodge_ball/DodgeWorld.gd")

const MUSIC_STYLE := {
	"name": "drive",
	# Drums and bass always; stabs above the cadence floor; the lead over the power target.
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
const SPEED_PER_RPM := 0.11  ## road m/s per rpm: 90 rpm is about 36 km/h
const SCREEN_FX_LAYER := 5  ## under the HUD (10)
## The 3D view renders into a SubViewport at this share of the screen's resolution, drawn
## scaled up under the HUD (which stays sharp): the tablet's GPU is fill-rate bound at full
## 1080p. (Viewport.scaling_3d_scale below 1 hung the GL Compatibility renderer on the tablet.)
const RENDER_SCALE := 0.67
## MSAA 2x halved the frame rate on the tablet (measured), so it stays off.
const MSAA := Viewport.MSAA_DISABLED
## Overrides are read from here when the file exists (a dev aid), for tuning on the tablet without rebuilding:
## [render] scale=0.75 msaa=0|1|2.
const TUNING_PATH := "user://dodge_tuning.cfg"

var logic: DodgeBallLogic
var world: DodgeWorld

var _status: DodgeStatus
var _fx_layer: CanvasLayer
var _fx_mat: ShaderMaterial
var _fx_rect: ColorRect
var _banner: Label
var _flash := 0.0
var _power_glow := 0.0
var _run_awarded := 0.0
var _best_awarded := 0.0
var _round_limit := -1.0  ## seconds, for a rounds Just Ride (end_mode game)
var _view: SubViewport
var _perf_usec := 0
var _perf_frames := 0
var _perf_left := 5.0


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "dodge_ball"
	i.title = "Dodge Ball"
	i.how_to = "Lean to dodge the balls. Pedal above the floor to keep your shield"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work"]
	i.tracker_mode = "lean_x"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points per minute of gameplay. A perfect two-minute Just Ride at 1.0× with the power bonus
	# all the way scores about 1190 / 1470 / 1760 a minute on easy / standard / hard (waves raise
	# the rate), so 3 stars needs the effort multiplier as well (epic #31). To be tuned on the
	# bike after the look-and-sound approval.
	i.star_thresholds = {
		"easy": [240, 640, 1300],
		"standard": [300, 800, 1600],
		"hard": [360, 950, 1900],
	}
	i.options = [
		{"key": "scene", "label": "Scene", "choices": ["auto", "dawn", "day", "dusk", "night"],
			"labels": ["Time of day", "Dawn", "Day", "Dusk", "Night"], "default": "auto"},
		{"key": "camera_roll", "label": "Camera tilt", "choices": ["on", "off"],
			"labels": ["On", "Off"], "default": "on"},
	]
	return i


func target_text(seg: Dictionary) -> String:
	var p: Dictionary = seg.get("params", {})
	var floor_rpm := float(p.get("cadence_floor", DodgeBallLogic.LEVELS.get(str(seg.get("difficulty", "standard")),
		DodgeBallLogic.LEVELS.standard).cadence_floor))
	var text := "Keep above %d rpm" % roundi(floor_rpm)
	if float(p.get("target_watts", 0.0)) > 0.0:
		text += " · %d W doubles your points" % roundi(float(p.target_watts))
	return text


func _ready() -> void:
	DodgeAudioScript.register()
	var tuning := ConfigFile.new()
	var tuned := tuning.load(TUNING_PATH) == OK
	world = DodgeWorldScript.new()
	if tuned and tuning.has_section("world"):
		for key in tuning.get_section_keys("world"):
			world.tuning[key] = bool(tuning.get_value("world", key))
	world.name = "World"
	var scale := clampf(float(tuning.get_value("render", "scale", RENDER_SCALE)) if tuned else RENDER_SCALE, 0.4, 1.0)
	_view = SubViewport.new()
	_view.name = "View3D"
	_view.size = Vector2i(roundi(HudTheme.W * scale), roundi(HudTheme.H * scale))
	_view.msaa_3d = int(tuning.get_value("render", "msaa", MSAA)) if tuned else MSAA
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	_view.add_child(world)
	var shown := TextureRect.new()
	shown.name = "View3DImage"
	shown.texture = _view.get_texture()
	shown.size = Vector2(HudTheme.W, HudTheme.H)
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shown)
	world.ball_bounced.connect(func(loud: float): AudioDirector.play_sfx("ball_bounce", linear_to_db(loud) - 6.0, randf_range(0.9, 1.1)))
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = SCREEN_FX_LAYER
	add_child(_fx_layer)
	var rect := ColorRect.new()
	rect.size = Vector2(HudTheme.W, HudTheme.H)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = load("res://games/dodge_ball/shaders/screen_fx.gdshader")
	rect.material = _fx_mat
	rect.visible = false
	_fx_layer.add_child(rect)
	_fx_rect = rect
	_banner = HudTheme.label("", HudTheme.BIG)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.size = Vector2(HudTheme.W, 140)
	_banner.position = Vector2(0, 560)  # over the road, clear of the HUD widgets
	_banner.add_theme_constant_override("outline_size", 16)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	_banner.visible = false
	_fx_layer.add_child(_banner)
	print("OPENRIDE_GAMES dodge_ball render scale=%.2f size=%s msaa=%d tuned=%s world=%s" % [scale, _view.size,
		_view.msaa_3d, tuned, world.tuning])


func _on_prepare(seg: Dictionary) -> void:
	var lives_mode := str(seg.get("role", "free")) == "free"
	logic = DodgeBallLogic.new(rng.seed, difficulty, params, lives_mode)
	_run_awarded = 0.0
	_best_awarded = 0.0
	_round_limit = -1.0
	if str(seg.get("end_mode", "timer")) == "game" and float(seg.get("duration_sec", -1)) > 0.0:
		_round_limit = maxf(1.0, float(params.get("rounds", 1))) * DodgeBallLogic.ROUND_SEC
	_apply_options()

	_status = DodgeStatus.new(logic.cadence_floor, logic.has_lives)
	hud.add_widget(_status)

	AudioDirector.play_music(MUSIC_STYLE, logic.cadence_floor, int(seg.get("seed", 0)))
	AudioDirector.set_intensity(0.6)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, DodgeAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, DodgeAudioScript.sfx_effects())
	# Draw one frame of the road at rest behind the intro card.
	world.update_view(0.0, logic, 0.0, 0.0)


func _on_option_changed(_key: String, _value: String) -> void:
	_apply_options()


func _apply_options() -> void:
	world.set_time_of_day(DodgeTimeOfDay.load_preset(DodgeTimeOfDay.resolve(option("scene"))))
	world.roll_enabled = option("camera_roll") == "on"


func _on_frame(delta: float) -> void:
	var started := Time.get_ticks_usec()
	_frame(delta)
	_perf_usec += Time.get_ticks_usec() - started
	_perf_frames += 1
	_perf_left -= delta
	if _perf_left <= 0.0:
		# For checking the 60 fps budget on the tablet (docs/GAMES.md, "Capturing logs").
		print("OPENRIDE_GAMES dodge_ball perf game_ms=%.2f process_ms=%.2f draw_calls=%d objects=%d" % [
			_perf_usec / 1000.0 / maxi(_perf_frames, 1),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		_perf_usec = 0
		_perf_frames = 0
		_perf_left = 5.0


func _frame(delta: float) -> void:
	var cadence := InputBus.cadence
	var power := InputBus.power
	var events := logic.step(delta, InputBus.lean_x, cadence, power)
	for event in events:
		_handle(event)
	world.update_view(delta, logic, cadence * SPEED_PER_RPM, InputBus.lean_x)

	var bonus_on := logic.power_multiplier(power) > 1.0
	_power_glow = move_toward(_power_glow, 1.0 if bonus_on else 0.0, delta * 3.0)
	_flash = maxf(0.0, _flash - delta * 2.2)
	# The full-screen overlay costs fill rate on the tablet: draw it only while it shows something.
	_fx_rect.visible = (_flash > 0.0 or _power_glow > 0.0) and world.tuning.get("screenfx", true)
	if _fx_rect.visible:
		_fx_mat.set_shader_parameter("power", _power_glow * 0.6)
		_fx_mat.set_shader_parameter("flash", _flash)
	_status.set_state(logic.shield, cadence < logic.cadence_floor, bonus_on, logic.streak, maxi(logic.lives, 0), logic.wave)
	if logic.game_over_left > 0.0:
		_banner.text = "Game over! Next run in %d" % ceili(logic.game_over_left)
	AudioDirector.set_intensity(0.9 if bonus_on else (0.6 if cadence >= logic.cadence_floor else 0.25))
	stats = {
		"dodges": logic.dodges,
		"hits": logic.hits,
		"pct_time_above_floor": roundi(logic.pct_time_above_floor()),
		"avg_power": roundi(logic.avg_power()),
		"longest_streak": logic.longest_streak,
		"runs": logic.run,
	}
	if _round_limit > 0.0 and played_sec >= _round_limit:
		end_segment()


func _handle(event: Dictionary) -> void:
	match event.type:
		"spawn":
			AudioDirector.play_sfx("launch_whoosh", -9.0, randf_range(0.85, 1.15))
		"dodge":
			var got := award(event.points)
			_run_awarded += got
			_best_awarded = maxf(_best_awarded, _run_awarded)
			world.dodge_fx(event.ball, got, event.points > DodgeBallLogic.DODGE_POINTS)
			AudioDirector.play_sfx("dodge_tick", -4.0, 1.0 + 0.04 * mini(logic.streak, 10))
		"streak":
			world.streak_fx()
			AudioDirector.play_sfx("streak_chime", 0.0, [1.0, 1.122, 1.335][DodgeBallLogic.STREAK_CHIMES.find(event.count)])
			_pop(_status)
		"shield_break":
			world.shield_fx(event.ball.x1, event.ball.kind)
			_flash = 0.45
			AudioDirector.play_sfx("shield_break")
			AudioDirector.play_sfx("shield_zap")
		"shield_ready":
			world.shield_ready_fx()
			AudioDirector.play_sfx("shield_ready")
		"hit":
			world.hit_fx(event.ball.x1, event.ball.kind)
			_flash = 0.8
			AudioDirector.play_sfx("hit_thud")
			AudioDirector.play_sfx("hit_body")
			if event.penalty > 0.0:
				penalize(event.penalty)
			_pop(_status)
		"wave":
			_show_banner("Wave %d" % event.wave, 1.6)
			AudioDirector.play_sfx("streak_chime", -3.0, 0.75)
		"game_over":
			_banner.visible = true
			AudioDirector.play_sfx("game_over")
		"new_run":
			_run_awarded = 0.0
			_show_banner("Run %d: go!" % event.run, 1.4)


## In a Just Ride with several runs, the score is the best run (#39, "Result").
func score() -> float:
	return _best_awarded if logic and logic.run > 1 else super()


func _show_banner(text: String, seconds: float) -> void:
	_banner.text = text
	_banner.visible = true
	_banner.modulate.a = 1.0
	var tween := _banner.create_tween()
	tween.tween_interval(seconds)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.4)
	tween.tween_callback(func():
		_banner.visible = false
		_banner.modulate.a = 1.0)


func _pop(widget: Control) -> void:
	widget.pivot_offset = widget.size / 2.0
	var tween := widget.create_tween()
	tween.tween_property(widget, "scale", Vector2(1.18, 1.18), 0.08)
	tween.tween_property(widget, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
