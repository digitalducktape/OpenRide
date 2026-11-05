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

const TugMusic := preload("res://games/tug_of_war/TugMusic.gd")

## "Heave Together" (TugMusic, rendered by games/tools/music): the bed (stomps, claps, bass)
## always; the harmony (strums, accordion) once the rope is tight; the lead in a surge.
const MUSIC_STYLE := {
	"name": "heave_together",
	"stem_files": TugMusic.STEM_FILES,
	"loop_from": TugMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.55, "lead": 0.9},
}
const MUSIC_BPM := TugMusic.BPM
## The lost-round flash: the 3D view's image is tinted toward the river (its modulate, free in
## the draw that scales it up) instead of a full-screen blended overlay, a full-resolution pass
## the tablet pays about 5 fps for.
const FLASH_TINT := Color(0.25, 0.55, 0.8)
const FLASH_FADE := 1.2  ## the flash's strength falls this much a second
## The 3D view renders into a SubViewport at this share of the screen's resolution, drawn
## scaled up under the HUD (see DodgeBall.gd: the tablet's GPU is fill-rate bound at 1080p).
const RENDER_SCALE := 0.62
const MSAA := Viewport.MSAA_DISABLED
const BRACE_LEAN := 0.5  ## lean_depth above this counts as leaning in
const FALL_SPLASH_DELAY := 0.7  ## the splash sound lands this long after a round ends

## The look (framework/ui/UI_STYLE.md): a rustic riverside fairground. Rope orange on bark
## brown, badges leaning a little; the display face stays upright (solid, not swooshy).
static var look := GameTheme.new(Color("ff9f1c"), Color("2a160b"), 0.12)

var logic: TugLogic
var world: TugWorld

var _view: SubViewport
var _status: TugStatus
var _shown: MeshInstance2D
var _view_scale := RENDER_SCALE  ## the scale the 3D view renders at now
var _flash := 0.0  ## 0-1: the lost-round flash
var _creak_left := 0.0
var _message_left := 0.0
var _mode_name := "match"
var _endless := false
var _tension := 0.5
var _best_rung := 0
var _results: Array[bool] = []  ## each round's result in order (true: won), for the pips
## Steps the 3D view down to a lower render scale if the frame rate stays low in a round.
var governor := RenderScaleStep.new()


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
			"labels": ["Match", "Ladder"], "default": "match", "kind": "segmented"},
		{"key": "length", "label": "Match length", "choices": ["3", "5"],
			"labels": ["Best of 3", "Best of 5"], "default": "3", "kind": "segmented"},
		{"key": "scene", "label": "Scene", "choices": ["auto", "dawn", "day", "dusk", "night"],
			"labels": ["Time of day", "Dawn", "Day", "Dusk", "Night"], "default": "auto",
			"group": "More options"},
		{"key": "brace", "label": "Brace lean", "choices": ["off", "on"],
			"labels": ["Off", "On"], "default": "off", "kind": "segmented", "group": "More options"},
	]
	return i


## The camera runs only for brace lean, which reads the depth axis.
func tracker_mode_for_segment(_segment: Dictionary) -> String:
	return "lean_2d" if option("brace") == "on" else "off"


func how_to_text(seg: Dictionary) -> String:
	if _is_endless(seg):
		return "Out-pull the bot, round after round"
	if option("mode") == "ladder":
		return "Climb the ladder: every win faces a stronger bot"
	return "Win the match: best of %s rounds" % option("length")


func target_text(seg: Dictionary) -> String:
	var p: Dictionary = seg.get("params", {})
	var ftp := float(p.get("ftp_watts", p.get("ftp", TugLogic.DEFAULT_FTP)))
	var bot := float(p.get("bot_watts", ftp * TugLogic.BOT_FACTOR))
	return "Pull harder than the bot's %d W" % roundi(bot)


func ui_theme() -> GameTheme:
	return look


## The intro card's picture: the first bot's head, colour and name.
func intro_visual() -> Control:
	return TugBotPortrait.new(look, world.bot_name(), world.bot_color(), world.bot_has_horns())


func _is_endless(seg: Dictionary) -> bool:
	return str(seg.get("end_mode", "timer")) == "timer" and float(seg.get("duration_sec", -1)) > 0.0


func _ready() -> void:
	TugAudioScript.register()
	world = TugWorld.new()
	world.name = "World"
	_view = SubViewport.new()
	_view.name = "View3D"
	_set_render_scale(RENDER_SCALE)
	_view.msaa_3d = MSAA
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	_view.add_child(world)
	# The view scaled up to the screen: a grid with the vignette in its vertex colours
	# (TugMeshes.view_image), one draw like a TextureRect, and no vignette left per pixel.
	var shown := MeshInstance2D.new()
	shown.name = "View3DImage"
	shown.texture = _view.get_texture()
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(shown)
	_shown = shown
	_fit_view()
	Stage.changed.connect(_fit_view)


func _on_prepare(seg: Dictionary) -> void:
	_endless = _is_endless(seg)
	_mode_name = "endless" if _endless else option("mode")
	var best_of := int(option("length"))
	if str(seg.get("end_mode", "timer")) == "game" and params.has("rounds"):
		best_of = maxi(int(params.rounds), 1)
		best_of += 1 - best_of % 2  # best-of needs an odd count
	logic = TugLogic.new(rng.seed, params, _mode_name, best_of)
	governor = RenderScaleStep.new()
	_set_render_scale(RENDER_SCALE)
	_best_rung = 0
	_results = []
	_apply_options()
	hud.set_skin(look.hud_skin())
	_status = TugStatus.new(look)
	hud.add_widget(_status)
	_set_bot(0)
	_update_rounds()
	AudioDirector.play_music(MUSIC_STYLE, MUSIC_BPM)
	AudioDirector.set_intensity(0.5)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, TugAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, TugAudioScript.sfx_effects())
	AudioDirector.set_bus_effects(AudioDirector.MASTER_BUS, GameMix.master_effects())
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
	if governor.sample(delta, logic.phase == TugLogic.Phase.ROUND):
		_set_render_scale(governor.render_scale(RENDER_SCALE))
		print("OPENRIDE_GAMES tug_of_war quality tier=%d fps=%.1f scale=%.2f" % [
			governor.tier, governor.last_fps, governor.render_scale(RENDER_SCALE)])
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
	if _flash > 0.0:
		_flash = move_toward(_flash, 0.0, delta * FLASH_FADE)
		_shown.modulate = Color.WHITE.lerp(FLASH_TINT, _flash)
	won = logic.rider_won()
	variant = "ladder" if _mode_name == "ladder" else ""


## The result's stats, built once at the end rather than a new Dictionary every frame.
func finish() -> Dictionary:
	if logic == null:
		return super.finish()
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
	return super.finish()


func _handle(event: Dictionary) -> void:
	match event.type:
		"telegraph":
			AudioDirector.play_sfx("surge_drumroll", -2.0)
			GameMix.duck_for_moment(1.2)
			_show_message("Surge coming!", 1.0, GameTheme.WARN)
		"surge_start":
			AudioDirector.play_sfx("rope_creak", -2.0, 0.7)
		"surge_end":
			if event.answered:
				_show_message("Held it!", 1.2, GameTheme.GOOD)
				AudioDirector.play_sfx("crowd_swell", -8.0)
		"round_end":
			world.excitement = 1.0
			_results.append(bool(event.won))
			_update_rounds()
			if event.won:
				award(event.points)
				_best_rung = maxi(_best_rung, logic.rung + 1)
				world.fall(true)
				AudioDirector.play_sfx("win_sting")
				AudioDirector.play_sfx("crowd_swell", -4.0)
				GameMix.duck_for_sting(2.0)
				_show_message("Round won! +%d" % roundi(event.points), TugLogic.ROUND_END_SEC, GameTheme.GOOD)
				GameTheme.pop(hud.score, 1.2)
			else:
				world.fall(false)
				AudioDirector.play_sfx("lose_sting")
				GameMix.duck_for_sting(2.0)
				_flash = 0.9
				_shown.modulate = Color.WHITE.lerp(FLASH_TINT, _flash)
				_show_message("Pulled in!", TugLogic.ROUND_END_SEC, GameTheme.BAD)
			get_tree().create_timer(FALL_SPLASH_DELAY).timeout.connect(func(): AudioDirector.play_sfx("splash"))
		"recovery_start":
			world.reset_round()
			_set_bot(logic.rung + (1 if _mode_name == "ladder" and logic.round_won else 0))
			_show_message("NEXT: %s %d W" % [world.bot_name(), roundi(event.next_bot_watts)], 4.0, _status.bot_color)
		"round_start":
			world.reset_round()
			_set_bot(logic.rung)
			_update_rounds()
			_show_message("Round %d: %s %d W" % [event.round, world.bot_name(), roundi(event.bot_watts)], 2.5, _status.bot_color)
		"match_end":
			_show_message("Match won!" if event.won else "Match over", 2.5,
				GameTheme.GOOD if event.won else GameTheme.WARN)
			get_tree().create_timer(2.5).timeout.connect(end_segment)



func _update_status() -> void:
	var alert := ""
	if logic.keep_pedaling:
		alert = "pedal"
	elif logic.phase == TugLogic.Phase.RECOVERY:
		alert = "rest"
	_status.set_state(logic.rider_power, logic.bot_power_now(), logic.p if logic.phase != TugLogic.Phase.RECOVERY else 0.0,
		logic.surge_state, alert, ceili(logic.phase_left) if alert == "rest" else 0)


## The status widget's round line: pips in a match, the rung on the ladder, wins when endless.
func _update_rounds() -> void:
	_status.set_rounds(_mode_name, logic.best_of, _results, logic.rung + 1)


## A new bot in the world and on the status widget.
func _set_bot(rung: int) -> void:
	world.set_bot(rung)
	_status.set_bot(world.bot_name(), world.bot_color())


## The 3D view renders at `scale` of the screen's resolution (drawn scaled up under the HUD).
func _set_render_scale(scale: float) -> void:
	_view_scale = scale
	var size := Stage.view_size(scale)
	if _view.size != size:
		_view.size = size


## The view over the whole window, past the centred stage (#57), whenever the window changes.
func _fit_view() -> void:
	_shown.position = -Stage.pad
	_shown.mesh = TugMeshes.view_image(Stage.visible_size)
	_set_render_scale(_view_scale)


func _show_message(text: String, seconds: float, color := GameTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
