extends Game
## Cadence Karaoke (#42): a rhythm game for your legs. The one speed number is the target rpm:
## ride to it, and move it whenever you like with − and + (5 rpm a step; internally "pace"). In first person down a neon tunnel, the
## beat is a line inside a box and an orb is you: on the line when your cadence matches the target,
## in front of the box at 10 rpm or more above it, behind the box at 10 or more below. The music plays at exactly
## the target cadence, one beat per pedal stroke, and its lead only plays while you're in the band,
## so staying on the beat completes the song.
##
## Rules: `CadenceLogic` (tested headless). View: `CadenceWorld` (3D). Audio: `CadenceAudio`. This
## scene wires them to the framework: declarations, the HUD widget and the target buttons, scoring
## through award() (no effort multiplier: this game rewards staying easy), music and effects
## through AudioDirector, and the rider's options (metronome, look) through `GameOptions`.

const CadenceAudioScript := preload("res://games/cadence_karaoke/CadenceAudio.gd")

## "Neon Lines" (CadenceMusic: a sample bank and a score from games/tools/music), laid out by
## SongSequencer at the target cadence: one beat a pedal stroke from 70 rpm, two below. A pace
## change swaps in on a phrase boundary and carries on from the same place in the song. The bed
## (drums, bass) always; the harmony in time, and the lead only while on target.
const MUSIC_STYLE := {
	"name": "neon_lines",
	"song": "res://games/cadence_karaoke/CadenceMusic.gd",
	"bars": 24,
	"swap_keeps_place": true,
	"stem_gates": {"harmony": 0.2, "lead": 0.99},
}
const RENDER_SCALE := 0.62
const MSAA := Viewport.MSAA_DISABLED
const CONTROLS_LAYER := 6  ## under the HUD (10)
const RETEMPO_SEC := 6.0  ## how often a moving target (a profile) asks for a new tempo
const SWAP_TIMEOUT_SEC := 16.0  ## a pace change that hasn't heard a tempo swap applies anyway
const NO_MUSIC_DELAY_SEC := 1.5  ## ... and with no music playing, almost at once
const BAND_COLOR_STEP := 1.0
const INK := Color("12052a")  ## the synthwave stage's deep violet (UI_STYLE.md §4)
const BUTTON_SIZE := Vector2(300, HudTheme.BUTTON_HEIGHT)
const BUTTON_GAP := 60
const BUTTON_MARGIN := 30  ## from the bottom edge

var logic: CadenceLogic
var world: CadenceWorld

## The 3D view: the world renders in it, and its image draws it over the whole canvas.
var view: StageView3D
var _status: CadenceStatus
var _minus: Button
var _plus: Button
var _controls: HBoxContainer  ## the − and + buttons, bottom centre
## The segment's look, from the tunnel's neon (`world.theme_color`); rebuilt when the rider's
## colour option changes.
var _look: GameTheme
var _beat_phase := 0.0
var _beat_flare := 0.0
var _requested_tempo := 0
var _retempo_left := RETEMPO_SEC
var _pending_wait := 0.0
var _seed := 0
var _band_for := -1
var _circuit := false


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "cadence_karaoke"
	i.title = "Cadence Karaoke"
	i.how_to = "Pedal with the beat and keep the orb on the beat line"
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
		{"key": "metronome", "label": "Metronome", "choices": ["off", "on"],
			"labels": ["Off", "On"], "default": "off", "kind": "segmented"},
		{"key": "look", "label": "Color", "choices": ["auto", "cyan", "green", "violet", "pink"],
			"labels": ["By workout part", "Cyan", "Green", "Violet", "Pink"], "default": "auto"},
	]
	return i


func how_to_text(_seg: Dictionary) -> String:
	return "Pedal to the beat. Tap − or + to change the pace"


func ui_theme() -> GameTheme:
	return _look


func target_text(seg: Dictionary) -> String:
	var profile: Array = seg.get("params", {}).get("cadence_profile", [])
	var rpm := float(profile[0].rpm) if not profile.is_empty() else float(CadenceLogic.DEFAULT_PACE)
	return "Start around %d rpm" % roundi(rpm)


func _ready() -> void:
	CadenceAudioScript.register()
	world = CadenceWorld.new()
	world.name = "World"
	# No vignette in the image: the tunnel's look is its own.
	view = StageView3D.new(RENDER_SCALE)
	view.vignette = 0.0
	view.msaa_3d = MSAA
	add_child(view)
	view.add_child(world)
	add_child(view.image)
	# The target buttons (−5 and +5 rpm), bottom centre: far from End (top right). Built here in
	# the free segment's look; `_on_prepare` restyles them in the segment's.
	var layer := CanvasLayer.new()
	layer.name = "Controls"
	layer.layer = CONTROLS_LAYER
	add_child(layer)
	_look = _make_look(CadenceWorld.THEMES.free)
	_controls = HBoxContainer.new()
	_controls.name = "PaceButtons"
	_controls.add_theme_constant_override("separation", BUTTON_GAP)
	_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_controls)
	_minus = _pace_button("−5", -1)
	_plus = _pace_button("+5", 1)
	_controls.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, BUTTON_MARGIN)
	_controls.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_controls.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_controls.visible = false  # until play starts: the intro card stays clean


## A pace button: "−5" big and "rpm" as a caption, so it says what moves.
func _pace_button(value: String, steps: int) -> Button:
	var b := _look.button("", func(): adjust_pace(steps), GameTheme.PRIMARY)
	b.name = "Slower" if steps < 0 else "Faster"
	b.custom_minimum_size = BUTTON_SIZE
	var box := HBoxContainer.new()
	box.name = "Face"
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	b.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for text in [value, "rpm"]:
		var l := Label.new()
		l.name = "Value" if text == value else "Unit"
		l.text = text
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		box.add_child(l)
	_controls.add_child(b)
	_style_pace_button(b)
	return b


func _style_pace_button(b: Button) -> void:
	_look.style_button(b, GameTheme.PRIMARY)
	_look.style_label(b.get_node("Face/Value"), HudTheme.MEDIUM, GameTheme.INK, true)
	_look.style_label(b.get_node("Face/Unit"), HudTheme.SMALL, GameTheme.MUTED, true)


static func _make_look(neon: Color) -> GameTheme:
	return GameTheme.new(neon, INK, 0.25, true)


## The look follows the tunnel's neon: the HUD skin, the status widget and the buttons.
func _restyle() -> void:
	_look = _make_look(world.theme_color)
	hud.set_skin(_look.hud_skin())
	if _status:
		_status.apply_theme(_look)
	for b in [_minus, _plus]:
		_style_pace_button(b)
	ui_theme_changed.emit()  # the intro card, the pause screen and the summary follow


func _on_prepare(seg: Dictionary) -> void:
	_circuit = params.has("cadence_profile")
	var rules := params.duplicate()
	if str(seg.get("role", "free")) == "free":
		# A Just Ride caps power at 75% of FTP (Endurance).
		rules["power_cap_watts"] = float(params.get("ftp_watts", 0.0)) * 0.75
	logic = CadenceLogic.new(difficulty, rules)
	hud.metrics.set_power_source(smoothed_power)
	_seed = int(seg.get("seed", 0))
	_beat_phase = 0.0
	_pending_wait = 0.0
	_retempo_left = RETEMPO_SEC
	_band_for = -1
	_apply_look()
	_status = null
	_restyle()
	_status = CadenceStatus.new(_look)
	hud.add_widget(_status)
	_controls.visible = false
	_requested_tempo = roundi(logic.target())
	AudioDirector.play_music(MUSIC_STYLE, float(_requested_tempo), _seed)
	AudioDirector.set_intensity(0.4)
	GameAudio.apply_mix(CadenceAudioScript.music_effects(), CadenceAudioScript.sfx_effects())
	if not AudioDirector.tempo_swapped.is_connected(_on_tempo_swapped):
		AudioDirector.tempo_swapped.connect(_on_tempo_swapped)
	world.update_view(0.0, 0.0, logic.band_fraction(), 0.0, "out", false, 0.0, logic.target() / 60.0)
	_update_status()


## The ride panel's W: the rules' smoothed power (the "Ease off" freeze is judged on it). A bound
## method, so the panel's Callable stops being valid if the game is freed before `clear_widgets`.
func smoothed_power() -> float:
	return logic.smoothed_power if logic and logic.smoothed_power >= 0.0 else InputBus.power


func _on_start() -> void:
	_update_buttons()
	GameTheme.fade(_controls, true)


func _exit_tree() -> void:
	if AudioDirector.tempo_swapped.is_connected(_on_tempo_swapped):
		AudioDirector.tempo_swapped.disconnect(_on_tempo_swapped)


func _on_option_changed(key: String, _value: String) -> void:
	_apply_look()
	if key == "look" and hud:
		_restyle()  # a re-skin re-lays out the HUD: fine here, on the pause screen


func _unhandled_key_input(event: InputEvent) -> void:
	if not playing or paused or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_COMMA:
		adjust_pace(-1)
	elif event.keycode == KEY_PERIOD:
		adjust_pace(1)


## The rider asks for a faster (+1) or slower (-1) pace, 5 rpm a step. It takes effect at the next
## phase boundary, together with the music's new tempo.
func adjust_pace(steps: int) -> void:
	if logic == null or not logic.request_pace(steps):
		return
	GameTheme.pop(_minus if steps < 0 else _plus, 1.15)
	_update_buttons()
	_request_tempo(roundi(logic.target() + logic.pending_adjust))
	_pending_wait = 0.0
	_show_message("Next: %d rpm, on the next bar" % roundi(logic.target() + logic.pending_adjust), 2.0)


## Greys out − at the slowest pace and + at the fastest (request_pace would refuse them).
func _update_buttons() -> void:
	if logic == null:
		return
	var wanted := logic.pace() + logic.pending_adjust
	for pair in [[_minus, wanted <= CadenceLogic.PACE_MIN], [_plus, wanted >= CadenceLogic.PACE_MAX]]:
		var b: Button = pair[0]
		if b.disabled != pair[1]:
			b.disabled = pair[1]
			b.modulate.a = 0.4 if b.disabled else 1.0


func _request_tempo(rpm: int) -> void:
	_requested_tempo = clampi(rpm, int(CadenceLogic.TARGET_MIN), int(CadenceLogic.TARGET_MAX))
	AudioDirector.play_music(MUSIC_STYLE, float(_requested_tempo), _seed)


func _on_tempo_swapped(_key: String, _since: float) -> void:
	if logic and logic.apply_pending():
		_pending_wait = 0.0
		_show_message("Target: %d rpm" % roundi(logic.target()), 1.6)


func _apply_look() -> void:
	var look := option("look")
	var role := str(segment.get("role", "free"))
	world.set_theme(role if look == "auto" else look)


func _on_frame(delta: float) -> void:
	var cadence := InputBus.cadence
	var events := logic.step(delta, cadence, InputBus.power)
	if logic.last_points > 0.0:
		award(logic.last_points)
	for event in events:
		_handle(event)
	_beat(delta)
	_follow_the_music(delta)
	var state := "out"
	if logic.in_bonus:
		state = "in_bonus"
	elif logic.in_band:
		state = "in_band"
	elif absf(logic.gap) <= logic.band_fraction() * 2.0 and cadence > 0.0:
		state = "near"
	var streak := clampf(logic.streak_sec / (CadenceLogic.STREAK_STEP_SEC * 4.0), 0.0, 1.0)
	world.beat = _beat_flare
	world.update_view(delta, logic.gap, logic.band_fraction(), _beat_phase, state, logic.frozen, streak, logic.target() / 60.0)
	_update_bands()
	_update_status()
	AudioDirector.set_intensity(1.0 if logic.in_band and not logic.frozen else 0.4)
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
			_status.streak_up(logic.streak_multiplier())
		"band_exit":
			AudioDirector.play_sfx("band_exit")
			world.orb_flash = 1.0
		"ease_off":
			AudioDirector.play_sfx("ease_off_chime")
			GameMix.duck_for_moment(1.0)
			_show_message("Ease off a little", 2.0, HudTheme.WARN)
		"recovered":
			hud.hide_message()


## The beat: one a pedal stroke at the target cadence. The visual flares on it and, if the rider
## asked for it, a tick plays. (The music's own beat grid can't be read back, so this clock is
## the target's, which the music is laid out at (two music beats a stroke below 70 rpm); check the
## alignment on the bike.)
func _beat(delta: float) -> void:
	_beat_phase += delta * logic.target() / 60.0
	if _beat_phase >= 1.0:
		_beat_phase -= 1.0
		_beat_flare = 1.0
		if _status:
			_status.beat()
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


func _update_bands() -> void:
	var rpm := roundi(logic.target())
	if rpm != _band_for:
		_band_for = rpm
		hud.metrics.set_cadence_band(float(rpm) - logic.tolerance, float(rpm) + logic.tolerance)


func _update_status() -> void:
	# The one speed number for the rider is the hero: the target rpm the orb follows. − and +
	# shift it, and a circuit's profile moves it.
	_status.set_target(roundi(logic.target()))
	var next_text := ""
	if logic.pending_adjust != 0:
		next_text = "%d %s" % [roundi(logic.target() + logic.pending_adjust), _swap_eta_text()]
	_status.set_next(next_text)
	_status.set_info(roundi(logic.pct_in_band()), logic.streak_multiplier())
	var alert := CadenceStatus.ALERT_NONE
	if logic.frozen:
		alert = CadenceStatus.ALERT_EASE
	elif logic.cadence < 20.0:
		alert = CadenceStatus.ALERT_PEDAL
	elif not logic.in_band:
		alert = CadenceStatus.ALERT_SLOW if logic.gap > 0.0 else CadenceStatus.ALERT_FAST
	_status.set_alert(alert)
	_update_buttons()


## "in 7 s" until the pending pace takes effect, or "soon" while the new tempo is still rendering.
func _swap_eta_text() -> String:
	var left := AudioDirector.seconds_to_swap()
	if not AudioDirector.is_music_playing():
		left = NO_MUSIC_DELAY_SEC - _pending_wait
	if left < 0.0:
		return "soon"
	return "in %d s" % maxi(ceili(left), 1)


func _show_message(text: String, seconds: float, color := HudTheme.INK) -> void:
	hud.show_message(text, color, seconds)
