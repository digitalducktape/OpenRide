extends Game
## Dodge Ball (#39): ride a wide road in first person, at a speed that follows your cadence.
## In Dodge mode, lean to keep away from the balls rolling and bouncing at you; in Catch mode,
## lean into them. Pedal above the cadence floor to keep your shield; push past the power target
## to double your points.
##
## Rules: `DodgeBallLogic` (tested headless). View: `DodgeWorld` (3D). Audio: `DodgeAudio`.
## This scene wires them to the framework: declarations, HUD widgets and ride-metric bands,
## scoring through award()/penalize(), music and effects through AudioDirector, the rider's
## options (mode, scene lighting, camera tilt) through `GameOptions`, and the result's variant.

const DodgeAudioScript := preload("res://games/dodge_ball/DodgeAudio.gd")
const DodgeWorldScript := preload("res://games/dodge_ball/DodgeWorld.gd")
const ModeBadgeScript := preload("res://games/dodge_ball/ModeBadge.gd")

const DodgeMusic := preload("res://games/dodge_ball/DodgeMusic.gd")

## "Incoming!" (DodgeMusic, rendered by games/tools/music): the bed (drums, bass) always; the
## harmony (chugs, stabs, pads) once riding briskly; the lead over the power target.
const MUSIC_STYLE := {
	"name": "incoming",
	"stem_files": DodgeMusic.STEM_FILES,
	"loop_from": DodgeMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
const SCREEN_FX_LAYER := 5  ## under the HUD (10)
## The 3D view renders into a SubViewport at this share of the screen's resolution, drawn
## scaled up under the HUD (which stays sharp): the tablet's GPU is fill-rate bound at full
## 1080p. (Viewport.scaling_3d_scale below 1 hung the GL Compatibility renderer on the tablet.)
const RENDER_SCALE := 0.62
## MSAA 2x halved the frame rate on the tablet (measured), so it stays off.
const MSAA := Viewport.MSAA_DISABLED
## Developer aid, off in every build: set true to read `user://dodge_tuning.cfg` (render scale,
## MSAA and [world] switches, docs/GAMES.md) and log the frame cost every 5 s.
const DEV_TUNING := false
const TUNING_PATH := "user://dodge_tuning.cfg"
## The wind's level at full speed, and how far below that it starts.
const WIND_DB := -10.0
const WIND_RANGE_DB := 30.0

var logic: DodgeBallLogic
var world: DodgeWorld

var _status: DodgeStatus
var _fx_layer: CanvasLayer
var _fx_mat: ShaderMaterial
var _fx_rect: ColorRect
var _wind: AudioStreamPlayer
var _flash := 0.0
var _power_glow := 0.0
var _run_awarded := 0.0
var _best_awarded := 0.0
var _round_limit := -1.0  ## seconds, for a rounds Just Ride (end_mode game)
var _view: SubViewport
## The tablet's one quality step: the 3D view from _full_scale to 0.55 if play stays under 54 fps.
var governor := RenderScaleStep.new()
var _full_scale := RENDER_SCALE
var _view_scale := RENDER_SCALE  ## the scale the 3D view renders at now
var _mode_sec := {"dodge": 0.0, "catch": 0.0}
var _message_left := 0.0
var _perf_usec := 0
var _perf_frames := 0
var _perf_left := 5.0


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "dodge_ball"
	i.title = "Dodge Ball"
	i.how_to = "Lean to dodge the balls, or to catch them in Catch mode"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work"]
	i.tracker_mode = "lean_x"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points per minute of gameplay. Every ball is worth 10 at 1.0×, 20 with the power bonus. A
	# perfect ride without the bonus reaches 2 stars; 3 stars takes the bonus and some effort
	# multiplier as well (dodge_ball_logic_test checks this for 90 s circuit slots and two-minute
	# Just Rides).
	i.star_thresholds = {
		"easy": [200, 450, 1300],
		"standard": [240, 560, 1600],
		"hard": [280, 660, 1900],
	}
	# Catch: the same balls, all of them scoring when caught, so the same thresholds hold.
	i.variant_star_thresholds = {"catch": i.star_thresholds.duplicate(true)}
	i.options = [
		{"key": "mode", "label": "Mode", "choices": ["dodge", "catch"],
			"labels": ["Dodge the balls", "Catch the balls"], "default": "dodge", "kind": "segmented"},
		{"key": "scene", "label": "Scene", "choices": ["auto", "dawn", "day", "dusk", "night"],
			"labels": ["Time of day", "Dawn", "Day", "Dusk", "Night"], "default": "auto",
			"group": "More options"},
		{"key": "camera_roll", "label": "Camera tilt", "choices": ["on", "off"],
			"labels": ["On", "Off"], "default": "on", "kind": "segmented", "group": "More options"},
	]
	return i


func how_to_text(_seg: Dictionary) -> String:
	if option("mode") == "catch":
		return "CATCH the balls! Lean into the gold balls to score"
	return "DODGE the balls! Lean away from the red balls"


## Dodge Ball's look (`DodgeStatus.look`): the session styles the intro card and the pause
## screen with it, and `_on_prepare` skins the HUD.
func ui_theme() -> GameTheme:
	return DodgeStatus.look


func intro_visual() -> Control:
	return ModeBadgeScript.new(option("mode") == "catch")


func target_text(seg: Dictionary) -> String:
	var p: Dictionary = seg.get("params", {})
	var floor_rpm := float(p.get("cadence_floor", DodgeBallLogic.LEVELS.get(str(seg.get("difficulty", "standard")),
		DodgeBallLogic.LEVELS.standard).cadence_floor))
	var text := "Keep your cadence above %d rpm" % roundi(floor_rpm)
	if float(p.get("target_watts", 0.0)) > 0.0:
		text += " · Hold %d W for double points" % roundi(float(p.target_watts))
	return text


func _ready() -> void:
	DodgeAudioScript.register()
	var tuning := ConfigFile.new()
	var tuned := DEV_TUNING and tuning.load(TUNING_PATH) == OK
	world = DodgeWorldScript.new()
	if tuned and tuning.has_section("world"):
		for key in tuning.get_section_keys("world"):
			world.tuning[key] = bool(tuning.get_value("world", key))
	world.name = "World"
	var scale := clampf(float(tuning.get_value("render", "scale", RENDER_SCALE)) if tuned else RENDER_SCALE, 0.4, 1.0)
	_full_scale = scale
	_view = SubViewport.new()
	_view.name = "View3D"
	_set_render_scale(scale)
	_view.msaa_3d = int(tuning.get_value("render", "msaa", MSAA)) if tuned else MSAA
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	_view.add_child(world)
	var shown := TextureRect.new()
	shown.name = "View3DImage"
	shown.texture = _view.get_texture()
	shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shown)
	Stage.bleed(shown)  # the whole window, past the centred stage (#57)
	world.ball_bounced.connect(func(loud: float): AudioDirector.play_sfx("ball_bounce", linear_to_db(loud) - 10.0, randf_range(0.9, 1.1)))
	_fx_layer = CanvasLayer.new()
	_fx_layer.layer = SCREEN_FX_LAYER
	add_child(_fx_layer)
	var rect := ColorRect.new()
	Stage.bleed(rect)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = load("res://games/dodge_ball/shaders/screen_fx.gdshader")
	rect.material = _fx_mat
	rect.visible = false
	_fx_layer.add_child(rect)
	_fx_rect = rect
	# Wind, louder with speed: a looping noise on the effects bus.
	_wind = AudioStreamPlayer.new()
	_wind.bus = AudioDirector.SFX_BUS
	_wind.stream = SfxSynth.stream("wind")
	_wind.volume_db = -80.0
	add_child(_wind)
	if tuned:
		print("OPENRIDE_GAMES dodge_ball render scale=%.2f size=%s msaa=%d world=%s" % [scale, _view.size,
			_view.msaa_3d, world.tuning])


func _on_prepare(seg: Dictionary) -> void:
	var lives_mode := str(seg.get("role", "free")) == "free"
	logic = DodgeBallLogic.new(rng.seed, difficulty, params, lives_mode, option("mode"))
	_run_awarded = 0.0
	_best_awarded = 0.0
	_mode_sec = {"dodge": 0.0, "catch": 0.0}
	_round_limit = -1.0
	if str(seg.get("end_mode", "timer")) == "game" and float(seg.get("duration_sec", -1)) > 0.0:
		_round_limit = maxf(1.0, float(params.get("rounds", 1))) * DodgeBallLogic.ROUND_SEC
	_apply_options()
	governor = RenderScaleStep.new()
	_set_render_scale(_full_scale)

	hud.set_skin(DodgeStatus.look.hud_skin())
	_status = DodgeStatus.new(logic.cadence_floor, logic.has_lives, logic.is_catch())
	hud.add_widget(_status)
	hud.metrics.set_cadence_band(logic.cadence_floor)
	if logic.target_watts > 0.0:
		hud.metrics.set_power_band(logic.target_watts)

	# A rendered track at its own tempo: the same request every segment, so it plays on.
	AudioDirector.play_music(MUSIC_STYLE, DodgeMusic.BPM)
	AudioDirector.set_intensity(0.6)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, DodgeAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, DodgeAudioScript.sfx_effects())
	AudioDirector.set_bus_effects(AudioDirector.MASTER_BUS, GameMix.master_effects())
	# Draw one frame of the road at rest behind the intro card, and warm up the effects there.
	world.update_view(0.0, logic, 0.0, 0.0)
	world.prewarm()


func _on_start() -> void:
	_wind.play()


func _on_pause() -> void:
	_wind.stream_paused = true


func _on_resume() -> void:
	_wind.stream_paused = false


func _on_option_changed(key: String, _value: String) -> void:
	_apply_options()
	if key == "mode" and logic:
		logic.set_mode(option("mode"))
		if _status:
			_status.set_catch(logic.is_catch())
		_show_message("Catch the balls!" if logic.is_catch() else "Dodge the balls!", 2.0)


## The 3D view renders at `scale` of the screen's resolution (drawn scaled up under the HUD).
func _set_render_scale(scale: float) -> void:
	_view_scale = scale
	var size := Stage.view_size(scale)
	if _view.size != size:
		_view.size = size


func _apply_options() -> void:
	world.set_time_of_day(DodgeTimeOfDay.load_preset(DodgeTimeOfDay.resolve(option("scene"))))
	world.roll_enabled = option("camera_roll") == "on"


func _on_frame(delta: float) -> void:
	if not DEV_TUNING:
		_frame(delta)
		return
	var started := Time.get_ticks_usec()
	_frame(delta)
	_perf_usec += Time.get_ticks_usec() - started
	_perf_frames += 1
	_perf_left -= delta
	if _perf_left <= 0.0:
		print("OPENRIDE_GAMES dodge_ball perf game_ms=%.2f process_ms=%.2f draw_calls=%d objects=%d" % [
			_perf_usec / 1000.0 / maxi(_perf_frames, 1),
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)])
		_perf_usec = 0
		_perf_frames = 0
		_perf_left = 5.0


func _frame(delta: float) -> void:
	if governor.sample(delta, true):
		_set_render_scale(governor.render_scale(_full_scale))
		print("OPENRIDE_GAMES dodge_ball quality tier=%d fps=%.1f scale=%.2f" % [
			governor.tier, governor.last_fps, governor.render_scale(_full_scale)])
	var cadence := InputBus.cadence
	var power := InputBus.power
	_mode_sec[logic.mode] += delta
	var events := logic.step(delta, InputBus.lean_x, cadence, power)
	for event in events:
		_handle(event)
	world.update_view(delta, logic, DodgeBallLogic.road_speed(cadence), InputBus.lean_x)

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
		hud.show_message("Game over! Best run: %d\nNext run in %d" % [roundi(_best_run()), ceili(logic.game_over_left)],
			GameTheme.BAD)
	elif _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	# Speed you can hear: the wind rises with the road speed, and the music fills out above the
	# floor and again over the power target.
	var speed := clampf(world.road_speed / DodgeWorld.FAST_SPEED, 0.0, 1.0)
	_wind.volume_db = WIND_DB - WIND_RANGE_DB * (1.0 - speed) if speed > 0.02 else -80.0
	var intensity := 0.25
	if bonus_on:
		intensity = 0.9
	elif cadence >= logic.cadence_floor:
		intensity = 0.6
	AudioDirector.set_intensity(intensity)
	variant = "catch" if _mode_sec.catch > _mode_sec.dodge else ""
	stats = {
		"mode": "catch" if variant == "catch" else "dodge",
		"dodges": logic.dodges,
		"hits": logic.hits,
		"catches": logic.catches,
		"misses": logic.misses,
		"fumbles": logic.fumbles,
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
			world.note_spawn(event.ball)
			AudioDirector.play_sfx("launch_whoosh", -10.0, randf_range(0.85, 1.15))
		"dodge":
			var got := _score(event.points)
			world.dodge_fx(event.ball, got, event.points > DodgeBallLogic.DODGE_POINTS)
			_pop_score(got)
			AudioDirector.play_sfx("dodge_tick", 1.0, 1.0 + 0.04 * mini(logic.streak, 10))
		"catch":
			var got := _score(event.points)
			world.catch_fx(event.ball, got, event.points > DodgeBallLogic.DODGE_POINTS)
			_pop_score(got)
			AudioDirector.play_sfx("catch_chime", 1.0, 1.0 + 0.05 * mini(logic.streak, 10))
		"miss":
			world.miss_fx(event.ball)
			AudioDirector.play_sfx("miss_whiff", -3.0)
			_streak_lost()
		"fumble":
			world.fumble_fx(event.ball)
			AudioDirector.play_sfx("fumble_thud")
			AudioDirector.play_sfx("ball_bounce", -4.0, 0.8)
			_show_message("Pedal up to hold on!", 1.2)
			_streak_lost()
		"streak":
			world.streak_fx()
			AudioDirector.play_sfx("streak_chime", 0.0, [1.0, 1.122, 1.335][DodgeBallLogic.STREAK_CHIMES.find(event.count)])
			GameTheme.pop(_status.streak_label, 1.35)
		"shield_break":
			world.shield_fx(event.ball.x1, event.ball.kind)
			_flash = 0.45
			AudioDirector.play_sfx("shield_break", -4.0)
			AudioDirector.play_sfx("shield_zap", -3.0)
			GameMix.duck_for_moment(0.5)
		"shield_ready":
			world.shield_ready_fx()
			AudioDirector.play_sfx("shield_ready")
		"hit":
			world.hit_fx(event.ball.x1, event.ball.kind)
			_flash = 0.8
			AudioDirector.play_sfx("hit_thud", -2.0)
			AudioDirector.play_sfx("hit_body", -2.0)
			GameMix.duck_for_moment(0.6)
			if event.penalty > 0.0:
				var taken := penalize(event.penalty)
				_run_awarded = maxf(0.0, _run_awarded - taken)
				world.penalty_fx(event.ball.x1, taken)
			# The loss on what was lost: a life (Just Ride) or the shield bar (circuit).
			var lost: Control = _status.lives_box if _status.lives_box.visible else _status.bar
			GameTheme.pop(lost, 0.8)
			GameTheme.flash(lost)
			_streak_lost()
		"wave":
			_show_message("Wave %d" % event.wave, 1.6)
			AudioDirector.play_sfx("streak_chime", -3.0, 0.75)
			GameMix.duck_for_moment(0.8)
		"game_over":
			AudioDirector.play_sfx("game_over")
			GameMix.duck_for_sting(2.2)
		"new_run":
			_best_awarded = _best_run()  # the run as it ended, penalties taken off
			_run_awarded = 0.0
			_show_message("Run %d: go!" % event.run, 1.4)


func _score(points: float) -> float:
	var got := award(points)
	_run_awarded += got
	return got


## The best run so far: the finished ones as they ended, or this one if it's ahead.
func _best_run() -> float:
	return maxf(_best_awarded, _run_awarded)


## In a Just Ride with several runs, the score is the best run (#39, "Result").
func score() -> float:
	return _best_run() if logic and logic.run > 1 else super()


func _show_message(text: String, seconds: float) -> void:
	hud.show_message(text)
	_message_left = seconds


## Juice on the element that changed (UI_STYLE.md, "Motion"): a new score pops the HUD's score.
## It's a compact BigNumber with no panel of its own, so scaling it never moves its neighbours.
func _pop_score(got: float) -> void:
	if got > 0.0 and hud and hud.score:
		GameTheme.pop(hud.score, 1.12)


## A broken streak (a miss, a fumble, a hit) pops the streak down.
func _streak_lost() -> void:
	if _status and _status.streak_label.text != "STREAK 0":
		GameTheme.pop(_status.streak_label, 0.8)
