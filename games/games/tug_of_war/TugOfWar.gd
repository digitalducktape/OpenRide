extends Game
## Tug of War (#40): your watts against a bot's, over a rope across a river, in first person.
## Pull harder than the bot to haul it off its pier; ease off and you're pulled in. The bot
## surges now and then, telegraphed a second early by a drum roll and a bracing pose.
##
## Rules: `TugLogic` (tested headless). View: `TugWorld` (3D). Audio: `TugAudio`. This scene
## wires them to the framework: declarations, the HUD widget, scoring through award(), music and
## effects through AudioDirector, the rider's options (mode, scene lighting, match length, brace
## lean) through `GameOptions`, and the result's variant.
##
## Camera: off unless the rider turned brace lean on, which needs the depth axis (lean in
## during a surge to slow the slip); `tracker_mode_for_segment` decides at each segment.

const TugAudioScript := preload("res://games/tug_of_war/TugAudio.gd")

const MUSIC_STYLE := {
	"name": "heave",
	# Drums and bass always; the harmony once the rope is tight; the lead in a surge.
	"stem_gates": {"harmony": 0.55, "lead": 0.9},
}
const MUSIC_BPM := 80.0
const SCREEN_FX_LAYER := 5  ## under the HUD (10)
## The 3D view renders into a SubViewport at this share of the screen's resolution, drawn
## scaled up under the HUD (see DodgeBall.gd: the tablet's GPU is fill-rate bound at 1080p).
const RENDER_SCALE := 0.62
const MSAA := Viewport.MSAA_DISABLED
const BRACE_LEAN := 0.5  ## lean_depth above this counts as leaning in
const FALL_SPLASH_DELAY := 0.7  ## the splash sound lands this long after a round ends

var logic: TugLogic
var world: TugWorld

var _view: SubViewport
var _status: TugStatus
var _flash_rect: ColorRect
var _creak_left := 0.0
var _message_left := 0.0
var _mode_name := "match"
var _endless := false
var _tension := 0.5
var _best_rung := 0


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "tug_of_war"
	i.title = "Tug of War"
	i.how_to = "Pull harder than the bot"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points per minute of gameplay: each round won is worth 1000 and every watt over the bot
	# adds points by the second. Holding 15% of FTP over the bot all the time (a perfect ride at
	# 1.0×) earns about 2250 a minute, which is 2 stars; 3 stars takes about 1.3× effort on top
	# (tug_logic_test checks this). Barely beating the bot wins a round at the buzzer for about
	# 850 a minute, a star at most.
	i.star_thresholds = {
		"easy": [800, 1700, 2900],
		"standard": [900, 1800, 2900],
		"hard": [1000, 1900, 3000],
	}
	# The ladder (each win faces a stronger bot): the same points a minute.
	i.variant_star_thresholds = {"ladder": i.star_thresholds.duplicate(true)}
	i.options = [
		{"key": "mode", "label": "Mode", "choices": ["match", "ladder"],
			"labels": ["Match", "Ladder"], "default": "match"},
		{"key": "length", "label": "Match length", "choices": ["3", "5"],
			"labels": ["Best of 3", "Best of 5"], "default": "3"},
		{"key": "scene", "label": "Scene", "choices": ["auto", "dawn", "day", "dusk", "night"],
			"labels": ["Time of day", "Dawn", "Day", "Dusk", "Night"], "default": "auto"},
		{"key": "brace", "label": "Brace lean", "choices": ["off", "on"],
			"labels": ["Off", "On"], "default": "off"},
	]
	return i


## The camera runs only for brace lean, which reads the depth axis.
func tracker_mode_for_segment(_segment: Dictionary) -> String:
	return "lean_2d" if option("brace") == "on" else "off"


func how_to_text(seg: Dictionary) -> String:
	if _is_endless(seg):
		return "Pull harder than the bot. Win round after round until time is up"
	if option("mode") == "ladder":
		return "Climb the ladder: every win faces a stronger bot"
	return "Win the match: best of %s rounds" % option("length")


func target_text(seg: Dictionary) -> String:
	var p: Dictionary = seg.get("params", {})
	var ftp := float(p.get("ftp_watts", p.get("ftp", TugLogic.DEFAULT_FTP)))
	var bot := float(p.get("bot_watts", ftp * TugLogic.BOT_FACTOR))
	return "Beat the bot's %d W" % roundi(bot)


func _is_endless(seg: Dictionary) -> bool:
	return str(seg.get("end_mode", "timer")) == "timer" and float(seg.get("duration_sec", -1)) > 0.0


func _ready() -> void:
	TugAudioScript.register()
	world = TugWorld.new()
	world.name = "World"
	_view = SubViewport.new()
	_view.name = "View3D"
	_view.size = Vector2i(roundi(HudTheme.W * RENDER_SCALE), roundi(HudTheme.H * RENDER_SCALE))
	_view.msaa_3d = MSAA
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
	var fx_layer := CanvasLayer.new()
	fx_layer.layer = SCREEN_FX_LAYER
	add_child(fx_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.size = Vector2(HudTheme.W, HudTheme.H)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.color = Color(0.1, 0.35, 0.55, 0.0)
	_flash_rect.visible = false
	fx_layer.add_child(_flash_rect)


func _on_prepare(seg: Dictionary) -> void:
	_endless = _is_endless(seg)
	_mode_name = "endless" if _endless else option("mode")
	var best_of := int(option("length"))
	if str(seg.get("end_mode", "timer")) == "game" and params.has("rounds"):
		best_of = maxi(int(params.rounds), 1)
		best_of += 1 - best_of % 2  # best-of needs an odd count
	logic = TugLogic.new(rng.seed, params, _mode_name, best_of)
	_best_rung = 0
	_apply_options()
	_status = TugStatus.new()
	hud.add_widget(_status)
	world.set_bot(0)
	AudioDirector.play_music(MUSIC_STYLE, MUSIC_BPM, int(seg.get("seed", 0)))
	AudioDirector.set_intensity(0.5)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, TugAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, TugAudioScript.sfx_effects())
	# One frame of the pier at rest behind the intro card, and the effects warmed up.
	world.update_view(0.0, 0.0, 0.5, "", 0.0)
	world.prewarm()
	_update_status()


func _on_option_changed(key: String, _value: String) -> void:
	_apply_options()
	if key == "brace":
		# Switch the camera on or off at once; Kotlin calibrates on the first camera mode.
		Session.set_tracker_mode("lean_2d" if option("brace") == "on" else "off")


func _apply_options() -> void:
	world.set_time_of_day(DodgeTimeOfDay.load_preset(DodgeTimeOfDay.resolve(option("scene"))))


func _on_frame(delta: float) -> void:
	var power := InputBus.power
	var cadence := InputBus.cadence
	var brace := option("brace") == "on" and InputBus.lean_depth > BRACE_LEAN
	var events := logic.step(delta, power, cadence, brace)
	if logic.last_margin_points > 0.0:
		award(logic.last_margin_points)
	for event in events:
		_handle(event)
	var margin := power - logic.bot_power_now()
	_tension = clampf(0.5 + absf(margin) / logic.ftp * 1.5, 0.5, 1.0)
	var resting := logic.phase == TugLogic.Phase.RECOVERY
	world.excitement = move_toward(world.excitement, 0.0 if resting else clampf(0.2 + absf(logic.p), 0.0, 1.0)
		if logic.phase == TugLogic.Phase.ROUND else 1.0, delta * 1.5)
	world.update_view(delta, 0.0 if resting else logic.p, 0.5 if resting else _tension, logic.surge_state, cadence)
	_update_status()
	_creak_left -= delta
	if _creak_left <= 0.0 and logic.phase == TugLogic.Phase.ROUND and _tension > 0.65:
		_creak_left = lerpf(1.6, 0.5, (_tension - 0.65) / 0.35)
		AudioDirector.play_sfx("rope_creak", -6.0, lerpf(0.8, 1.4, _tension))
	var intensity := 0.5
	if logic.surge_state == "surge":
		intensity = 1.0
	elif logic.phase == TugLogic.Phase.ROUND and _tension > 0.8:
		intensity = 0.85
	elif resting:
		intensity = 0.3
	AudioDirector.set_intensity(intensity)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	if _flash_rect.visible:
		_flash_rect.color.a = move_toward(_flash_rect.color.a, 0.0, delta * 1.2)
		_flash_rect.visible = _flash_rect.color.a > 0.0
	won = logic.rider_won()
	variant = "ladder" if _mode_name == "ladder" else ""
	stats = {
		"mode": _mode_name,
		"rounds_won": logic.wins,
		"rounds_lost": logic.losses,
		"best_rung": _best_rung,
		"avg_power": roundi(logic.avg_power()),
		"peak_power": roundi(logic.peak_power),
		"avg_margin": roundi(logic.avg_margin()),
		"best_margin": roundi(logic.best_margin()),
		"surges": logic.surges,
		"surges_answered": logic.surges_answered,
	}


func _handle(event: Dictionary) -> void:
	match event.type:
		"telegraph":
			AudioDirector.play_sfx("surge_drumroll", -2.0)
			_show_message("Surge coming!", 1.0, HudTheme.WARN)
		"surge_start":
			AudioDirector.play_sfx("rope_creak", -2.0, 0.7)
		"surge_end":
			if event.answered:
				_show_message("Held it!", 1.2, HudTheme.GOOD)
				AudioDirector.play_sfx("crowd_swell", -8.0)
		"round_end":
			world.excitement = 1.0
			if event.won:
				award(event.points)
				_best_rung = maxi(_best_rung, logic.rung + 1)
				world.fall(true)
				AudioDirector.play_sfx("win_sting")
				AudioDirector.play_sfx("crowd_swell")
				_show_message("Round won!", TugLogic.ROUND_END_SEC, HudTheme.GOOD)
			else:
				world.fall(false)
				AudioDirector.play_sfx("lose_sting")
				_flash_rect.color = Color(0.1, 0.35, 0.55, 0.9)
				_flash_rect.visible = true
				_show_message("Pulled in!", TugLogic.ROUND_END_SEC, HudTheme.BAD)
			get_tree().create_timer(FALL_SPLASH_DELAY).timeout.connect(func(): AudioDirector.play_sfx("splash"))
		"recovery_start":
			world.reset_round()
			world.set_bot(logic.rung + (1 if _mode_name == "ladder" and logic.round_won else 0))
			_show_message("Recover. Next: %s, %d W" % [world.bot_name(), roundi(event.next_bot_watts)], 4.0)
		"round_start":
			world.reset_round()
			world.set_bot(logic.rung)
			_show_message("Round %d: %s, %d W" % [event.round, world.bot_name(), roundi(event.bot_watts)], 2.5)
		"match_end":
			_show_message("Match won!" if event.won else "Match over", 2.5,
				HudTheme.GOOD if event.won else HudTheme.WARN)
			get_tree().create_timer(2.5).timeout.connect(end_segment)



func _update_status() -> void:
	var round_info := "Round %d · %d-%d · %s" % [logic.round_index, logic.wins, logic.losses, world.bot_name()]
	var alert := ""
	if logic.keep_pedaling:
		alert = "Keep pedaling"
	elif logic.surge_state == "telegraph":
		alert = "SURGE!"
	elif logic.phase == TugLogic.Phase.RECOVERY:
		alert = "Recover %ds" % ceili(logic.phase_left)
	_status.set_state(logic.rider_power, logic.bot_power_now(), logic.p if logic.phase != TugLogic.Phase.RECOVERY else 0.0,
		logic.surge_state, round_info, alert)


func _show_message(text: String, seconds: float, color := HudTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
