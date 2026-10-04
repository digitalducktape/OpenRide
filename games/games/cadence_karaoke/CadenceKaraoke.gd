extends Game
## Cadence Karaoke (#42): a rhythm game for your legs. Pick your own pace (a target cadence) and
## ride to it, adjusting it whenever you like with − and +. In first person down a neon tunnel, a
## glowing rail ahead is the target and an orb is your cadence: keep the orb on the rail. The
## music plays at exactly the target cadence, one beat per pedal stroke, and its lead only plays
## while you're in the band, so staying on target completes the song.
##
## Rules: `CadenceLogic` (tested headless). View: `CadenceWorld` (3D). Audio: `CadenceAudio`. This
## scene wires them to the framework: declarations, the HUD widget and the pace buttons, scoring
## through award() (no effort multiplier: this game rewards staying easy), music and effects
## through AudioDirector, and the rider's options (profile, metronome, look) through `GameOptions`.

const CadenceAudioScript := preload("res://games/cadence_karaoke/CadenceAudio.gd")

const MUSIC_STYLE := {
	"name": "bright",
	# Drums and bass always; the harmony in time, and the lead only while on target.
	"stem_gates": {"harmony": 0.2, "lead": 0.99},
}
const RENDER_SCALE := 0.62
const MSAA := Viewport.MSAA_DISABLED
const CONTROLS_LAYER := 6  ## under the HUD (10)
const RETEMPO_SEC := 6.0  ## how often a moving target (a profile) asks for a new tempo
const SWAP_TIMEOUT_SEC := 16.0  ## a pace change that hasn't heard a tempo swap applies anyway
const NO_MUSIC_DELAY_SEC := 1.5  ## ... and with no music playing, almost at once
const BAND_COLOR_STEP := 1.0

var logic: CadenceLogic
var world: CadenceWorld

var _view: SubViewport
var _status: CadenceStatus
var _minus: Button
var _plus: Button
var _beat_phase := 0.0
var _beat_flare := 0.0
var _requested_tempo := 0
var _retempo_left := RETEMPO_SEC
var _pending_wait := 0.0
var _message_left := 0.0
var _seed := 0
var _band_for := -1
var _targets := PackedFloat32Array()
var _circuit := false


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "cadence_karaoke"
	i.title = "Cadence Karaoke"
	i.how_to = "Pick your pace and keep your cadence on the rail"
	i.supports = ["minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.roles = ["warmup", "recovery", "cooldown"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = false
	i.stars_per_minute = true
	# Points per minute of gameplay. In the band you earn 10 a second, 15 in the bonus band, times
	# a streak multiplier that grows to 2.0 after 40 s. Measured with a modelled rider whose
	# cadence wobbles around the target by at most W rpm: W = 2 earns about 1700 a minute, W = 6
	# about 1100-1370 and W = 12 under 900 (cadence_logic_test pins the stars for these riders).
	# No effort multiplier: the stars reward steadiness, not watts.
	i.star_thresholds = {
		"easy": [300, 1000, 1500],
		"standard": [300, 1000, 1500],
		"hard": [300, 1000, 1500],
	}
	i.options = [
		{"key": "profile", "label": "Workout shape", "choices": ["steady", "pyramid", "builds", "spinups"],
			"labels": ["Steady pace", "Pyramids", "Cadence builds", "Spin-ups"], "default": "steady"},
		{"key": "metronome", "label": "Metronome", "choices": ["off", "on"],
			"labels": ["Off", "On"], "default": "off"},
		{"key": "look", "label": "Colour", "choices": ["auto", "cyan", "green", "violet", "pink"],
			"labels": ["By workout part", "Cyan", "Green", "Violet", "Pink"], "default": "auto"},
	]
	return i


func how_to_text(seg: Dictionary) -> String:
	if seg.get("params", {}).has("cadence_profile"):
		return "Keep your cadence on the rail. − and + shift the whole target if you need to"
	return "Pick your pace with − and +, then keep your cadence on the rail"


func target_text(seg: Dictionary) -> String:
	var profile: Array = seg.get("params", {}).get("cadence_profile", [])
	var rpm := float(profile[0].rpm) if not profile.is_empty() else float(CadenceLogic.DEFAULT_PACE)
	return "Start around %d rpm" % roundi(rpm)


func _ready() -> void:
	CadenceAudioScript.register()
	world = CadenceWorld.new()
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
	_targets.resize(CadenceWorld.RAIL_POINTS)
	# The pace buttons, along the bottom of the view.
	var layer := CanvasLayer.new()
	layer.layer = CONTROLS_LAYER
	add_child(layer)
	_minus = HudTheme.button("−  5", func(): adjust_pace(-1), Color(0.18, 0.24, 0.42, 0.92))
	_plus = HudTheme.button("+  5", func(): adjust_pace(1), Color(0.18, 0.24, 0.42, 0.92))
	for button in [_minus, _plus]:
		button.custom_minimum_size = Vector2(220, HudTheme.BUTTON_HEIGHT)
		button.size = Vector2(220, HudTheme.BUTTON_HEIGHT)
		layer.add_child(button)
	_minus.position = Vector2(HudTheme.W / 2.0 - 250.0, HudTheme.H - HudTheme.BUTTON_HEIGHT - 30.0)
	_plus.position = Vector2(HudTheme.W / 2.0 + 30.0, HudTheme.H - HudTheme.BUTTON_HEIGHT - 30.0)


func _on_prepare(seg: Dictionary) -> void:
	_circuit = params.has("cadence_profile")
	var shape := "steady" if _circuit else option("profile")
	var rules := params.duplicate()
	if str(seg.get("role", "free")) == "free":
		# A Just Ride caps only Endurance (steady), at 75% of FTP; the other shapes have none.
		rules["power_cap_watts"] = float(params.get("ftp_watts", 0.0)) * 0.75 if shape == "steady" else 0.0
	logic = CadenceLogic.new(difficulty, rules, shape)
	_seed = int(seg.get("seed", 0))
	_beat_phase = 0.0
	_pending_wait = 0.0
	_retempo_left = RETEMPO_SEC
	_band_for = -1
	_apply_look()
	_status = CadenceStatus.new()
	hud.add_widget(_status)
	_requested_tempo = roundi(logic.target())
	AudioDirector.play_music(MUSIC_STYLE, float(_requested_tempo), _seed)
	AudioDirector.set_intensity(0.4)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, CadenceAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, CadenceAudioScript.sfx_effects())
	if not AudioDirector.tempo_swapped.is_connected(_on_tempo_swapped):
		AudioDirector.tempo_swapped.connect(_on_tempo_swapped)
	_fill_targets()
	world.update_view(0.0, _targets, 0.0, logic.tolerance, "out", false, 0.0, logic.target() / 60.0)
	_update_status()


func _exit_tree() -> void:
	if AudioDirector.tempo_swapped.is_connected(_on_tempo_swapped):
		AudioDirector.tempo_swapped.disconnect(_on_tempo_swapped)


func _on_option_changed(_key: String, _value: String) -> void:
	_apply_look()
	if _key == "profile" and logic and not _circuit:
		logic.shape = option("profile")


func _unhandled_key_input(event: InputEvent) -> void:
	if not playing or paused or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_COMMA:
		adjust_pace(-1)
	elif event.keycode == KEY_PERIOD:
		adjust_pace(1)


## The rider asks for a faster (+1) or slower (-1) pace, 5 rpm a step. It takes effect at the next
## phrase boundary, together with the music's new tempo.
func adjust_pace(steps: int) -> void:
	if logic == null or not logic.request_pace(steps):
		return
	_request_tempo(roundi(logic.target() + logic.pending_adjust))
	_pending_wait = 0.0
	_show_message("Pace → %d rpm at the next phrase" % (logic.pace() + logic.pending_adjust), 2.0)


func _request_tempo(rpm: int) -> void:
	_requested_tempo = clampi(rpm, int(CadenceLogic.TARGET_MIN), int(CadenceLogic.TARGET_MAX))
	AudioDirector.play_music(MUSIC_STYLE, float(_requested_tempo), _seed)


func _on_tempo_swapped(_key: String, _since: float) -> void:
	if logic and logic.apply_pending():
		_pending_wait = 0.0
		_show_message("Pace: %d rpm" % logic.pace(), 1.6)


func _apply_look() -> void:
	var look := option("look")
	var role := str(segment.get("role", "free"))
	world.set_theme_color(CadenceWorld.THEMES.get(role if look == "auto" else look, CadenceWorld.THEMES.free))


func _on_frame(delta: float) -> void:
	var cadence := InputBus.cadence
	var events := logic.step(delta, cadence, InputBus.power)
	if logic.last_points > 0.0:
		award(logic.last_points)
	for event in events:
		_handle(event)
	_beat(delta)
	_follow_the_music(delta)
	_fill_targets()
	var state := "out"
	if logic.in_bonus:
		state = "in_bonus"
	elif logic.in_band:
		state = "in_band"
	elif absf(cadence - logic.target()) <= logic.tolerance * 2.0 and cadence > 0.0:
		state = "near"
	var streak := clampf(logic.streak_sec / (CadenceLogic.STREAK_STEP_SEC * 4.0), 0.0, 1.0)
	world.beat = _beat_flare
	world.update_view(delta, _targets, cadence, logic.tolerance, state, logic.frozen, streak, logic.target() / 60.0)
	_update_bands()
	_update_status()
	AudioDirector.set_intensity(1.0 if logic.in_band and not logic.frozen else 0.4)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	stats = {
		"pct_in_band": roundi(logic.pct_in_band()),
		"longest_streak": roundi(logic.longest_streak),
		"avg_cadence": roundi(logic.avg_cadence()),
		"avg_power": roundi(logic.avg_power()),
		"pace": logic.pace(),
	}


func _handle(event: Dictionary) -> void:
	match event.type:
		"streak":
			AudioDirector.play_sfx("streak_up", -3.0, 1.0 + 0.04 * float(event.seconds) / CadenceLogic.STREAK_STEP_SEC)
		"band_exit":
			AudioDirector.play_sfx("band_exit")
			world.orb_flash = 1.0
		"ease_off":
			AudioDirector.play_sfx("ease_off_chime")
			_show_message("Ease off a little", 2.0, HudTheme.WARN)
		"recovered":
			_message_left = 0.01


## The beat: one a pedal stroke at the target cadence. The visual flares on it and, if the rider
## asked for it, a tick plays. (The music's own beat grid can't be read back, so this clock is
## the target's, which the music is rendered at; check the alignment on the bike.)
func _beat(delta: float) -> void:
	_beat_phase += delta * logic.target() / 60.0
	if _beat_phase >= 1.0:
		_beat_phase -= 1.0
		_beat_flare = 1.0
		if option("metronome") == "on":
			AudioDirector.play_sfx("beat_tick", -6.0)
	_beat_flare = maxf(_beat_flare - delta * 5.0, 0.0)


## Keeps the music's tempo near a moving target, and applies a pace change that never heard its
## tempo swap (no music, or a slow render).
func _follow_the_music(delta: float) -> void:
	if logic.pending_adjust != 0:
		_pending_wait += delta
		var limit := SWAP_TIMEOUT_SEC if AudioDirector.is_music_playing() else NO_MUSIC_DELAY_SEC
		if _pending_wait >= limit:
			_on_tempo_swapped("", 0.0)
		return
	_retempo_left -= delta
	if _retempo_left <= 0.0:
		_retempo_left = RETEMPO_SEC
		var want := roundi(logic.target_at(logic.time + 10.0))
		if absi(want - _requested_tempo) >= 3:
			_request_tempo(want)


func _fill_targets() -> void:
	var n := CadenceWorld.RAIL_POINTS
	for i in n:
		_targets[i] = logic.target_at(logic.time + CadenceLogic.LOOKAHEAD_SEC * float(i) / (n - 1))


func _update_bands() -> void:
	var rpm := roundi(logic.target())
	if rpm != _band_for:
		_band_for = rpm
		hud.metrics.set_cadence_band(float(rpm) - logic.tolerance, float(rpm) + logic.tolerance)


func _update_status() -> void:
	var pace_text := "PACE %d rpm" % logic.pace()
	var next_text := "→ %d next phrase" % (logic.pace() + logic.pending_adjust) if logic.pending_adjust != 0 else ""
	var info_text := "In band %d%% · streak ×%s" % [roundi(logic.pct_in_band()), String.num(logic.streak_multiplier(), 2)]
	var alert := ""
	if logic.frozen:
		alert = "EASE OFF"
	elif logic.cadence < 20.0:
		alert = "Pedal"
	_status.set_state(pace_text, next_text, info_text, alert)


func _show_message(text: String, seconds: float, color := HudTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
