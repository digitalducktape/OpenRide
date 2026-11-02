extends Game
## Watt Lane (#78): a glowing highway at night. Your power is your place across the road; stay
## inside a lane of watts that drifts and jumps. Every jump is announced 5 s ahead with chevrons
## on the road, a countdown chip and a chime (rider's decision). DESIGN.md has the rules.
##
## Rules: `WattLaneLogic` (tested headless). View: `WattLaneWorld` (3D). HUD: `WattLaneStatus`.
## Audio: `WattLaneAudio`. This scene wires them to the framework: declarations, scoring through
## award() (the effort multiplier applies in work), music and effects through AudioDirector, and
## the HUD's one power number (the ride panel shows the rules' smoothed watts).

const WattLaneAudioScript := preload("res://games/watt_lane/WattLaneAudio.gd")
const WattLaneMusic := preload("res://games/watt_lane/WattLaneMusic.gd")

## "Night Current": the bed always; the harmony near the lane; the lead only in it.
const MUSIC_STYLE := {
	"name": "night_current",
	"stem_files": WattLaneMusic.STEM_FILES,
	"loop_from": WattLaneMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.45, "lead": 0.9},
}
const RENDER_SCALE := 0.62
const MSAA := Viewport.MSAA_DISABLED
const HUM_DB := {true: -15.0, false: -24.0}  ## the hum's level in and out of the lane
const HUM_FADE := 0.6  ## seconds for the hum to swap
const PEDAL_WATTS := 15.0  ## under this (smoothed) the alert says PEDAL

## The look (ART_BIBLE.md §4, framework/ui/UI_STYLE.md): volt lime on night petrol, upright.
static var look := GameTheme.new(Color("c8ff3e"), Color("061418"), 0.0)

var logic: WattLaneLogic
var world: WattLaneWorld

var _view: SubViewport
var _shown: TextureRect
var _status: WattLaneStatus
var _hum_in: AudioStreamPlayer
var _hum_out: AudioStreamPlayer
var _message_left := 0.0
var _beat := 0.0
var _beat_phase := 0.0
var _band := Vector2i(-1, -1)


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "watt_lane"
	i.title = "Watt Lane"
	i.how_to = "Your power is your place: ride inside the lane"
	i.supports = ["minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.roles = ["work", "warmup"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points per minute (WattLaneLogic.STARS, DESIGN.md "Scoring"): a perfect ride at 1.0× effort
	# earns 1550-1800 a minute (2 stars); 3 stars takes about 1.3× (watt_lane_logic_test).
	var stars: Array = WattLaneLogic.STARS
	i.star_thresholds = {"easy": stars.duplicate(), "standard": stars.duplicate(), "hard": stars.duplicate()}
	return i


func how_to_text(_seg: Dictionary) -> String:
	return "More watts move you right. Stay between the rails"


func target_text(seg: Dictionary) -> String:
	var preview := WattLaneLogic.new(str(seg.get("difficulty", "standard")), seg.get("params", {}),
		int(seg.get("seed", 0)), str(seg.get("role", "work")))
	return "Start in %d–%d W" % [preview.lane_lo(), preview.lane_hi()]


func ui_theme() -> GameTheme:
	return look


## The ride panel's W: the rules' smoothed power (one number on the whole HUD). A bound method,
## so the panel's Callable stops being valid if the game is freed before `clear_widgets`.
func smoothed_power() -> float:
	return logic.smoothed if logic else InputBus.power


## The hub card's framing (tests/capture_hub_cards.gd): the bike and its trail from behind.
func showcase() -> void:
	world.chase = true


## The intro card's picture: the hub card (the light-bike and its trail from behind).
func intro_visual() -> Control:
	const CARD := "res://games/watt_lane/hub_card.png"
	if not ResourceLoader.exists(CARD):
		return null
	var tex := load(CARD) as Texture2D
	var pic := TextureRect.new()
	pic.texture = tex
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pic.custom_minimum_size = Vector2(384, 216)
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return pic


func _ready() -> void:
	WattLaneAudioScript.register()
	world = WattLaneWorld.new()
	world.name = "World"
	_view = SubViewport.new()
	_view.name = "View3D"
	_view.msaa_3d = MSAA
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	_view.add_child(world)
	_shown = TextureRect.new()
	_shown.name = "View3DImage"
	_shown.texture = _view.get_texture()
	_shown.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_shown.stretch_mode = TextureRect.STRETCH_SCALE
	_shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_shown.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shown)
	Stage.bleed(_shown)  # the whole window, past the centred stage (#57)
	_fit_view()
	Stage.changed.connect(_fit_view)
	_hum_in = _hum_player("HumIn", true)
	_hum_out = _hum_player("HumOut", false)


func _hum_player(node_name: String, bright: bool) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = node_name
	p.stream = WattLaneAudioScript.hum(bright)
	p.bus = AudioDirector.SFX_BUS
	p.volume_db = -80.0
	add_child(p)
	return p


func _fit_view() -> void:
	_view.size = Stage.view_size(RENDER_SCALE)


func _on_prepare(seg: Dictionary) -> void:
	logic = WattLaneLogic.new(difficulty, params, int(seg.get("seed", 0)), str(seg.get("role", "work")))
	world.setup(logic.ftp, logic.width)
	hud.set_skin(look.hud_skin())
	_status = WattLaneStatus.new(look)
	hud.add_widget(_status)
	hud.metrics.set_power_source(smoothed_power)
	_band = Vector2i(-1, -1)
	AudioDirector.play_music(MUSIC_STYLE, WattLaneMusic.BPM)
	AudioDirector.set_intensity(0.5)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, WattLaneAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, WattLaneAudioScript.sfx_effects())
	AudioDirector.set_bus_effects(AudioDirector.MASTER_BUS, GameMix.master_effects())
	# The rider starts in the lane's middle on the intro card: one frame of the road at rest.
	var centre := float(logic.course.centre_at(0.0))
	world.update_view(0.0, logic.course, 0.0, centre, true, -1.0, true)
	_update_status()


func _on_start() -> void:
	for p in [_hum_in, _hum_out]:
		p.play()


func _on_pause() -> void:
	for p in [_hum_in, _hum_out]:
		p.stream_paused = true


func _on_resume() -> void:
	for p in [_hum_in, _hum_out]:
		p.stream_paused = false


func _on_frame(delta: float) -> void:
	var events := logic.step(delta, InputBus.power)
	if logic.last_points > 0.0:
		award(logic.last_points)
	for event in events:
		_handle(event)
	var up := logic.upcoming()
	_pedal_beat(delta)
	world.update_view(delta, logic.course, logic.time, logic.smoothed, logic.in_lane,
		float(up.get("at", -1.0)), bool(up.get("up", true)), _beat)
	_update_status()
	_update_audio(delta)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()


func _handle(event: Dictionary) -> void:
	match event.type:
		"announce":
			AudioDirector.play_sfx("jump_chime", -1.0)
			GameMix.duck_for_moment(1.2)
		"count":
			AudioDirector.play_sfx("count_tick", -8.0, 1.0 + 0.06 * (3 - int(event.n)))
		"jump":
			AudioDirector.play_sfx("lane_shift", -3.0)
		"caught":
			world.flash = 1.0
			AudioDirector.play_sfx("caught", -2.0)
			_show_message("Caught it!", 1.2, GameTheme.GOOD)
		"missed":
			AudioDirector.play_sfx("missed", -6.0)
		"streak":
			_status.streak_up(float(event.multiplier))
			AudioDirector.play_sfx("streak_up", 0.0, 0.9 + 0.1 * float(event.multiplier))
		"lane_exit":
			AudioDirector.play_sfx("off_buzz", -3.0)


## The result's stats, built once at the end.
func finish() -> Dictionary:
	if logic != null:
		stats = {
			"in_lane_pct": roundi(logic.in_lane_pct()),
			"longest_streak_sec": roundi(logic.longest_streak),
			"avg_power": roundi(logic.avg_power()),
			"jumps": logic.jumps,
			"jumps_caught": logic.jumps_caught,
		}
	return super.finish()


func _update_status() -> void:
	_status.set_lane(logic.lane_lo(), logic.lane_hi())
	_status.set_info(roundi(logic.in_lane_pct()), logic.streak_multiplier())
	var up := logic.upcoming()
	if up.is_empty():
		_status.set_countdown(true, 0, 0, -1)
	else:
		_status.set_countdown(bool(up.up), int(up.lo), int(up.hi), ceili(float(up.at)) if float(up.at) > 0.05 else 0)
	var alert := WattLaneStatus.ALERT_NONE
	if logic.smoothed < PEDAL_WATTS:
		alert = WattLaneStatus.ALERT_PEDAL
	elif logic.side() < 0:
		alert = WattLaneStatus.ALERT_PUSH
	elif logic.side() > 0:
		alert = WattLaneStatus.ALERT_EASE
	_status.set_alert(alert)
	# The ride panel's gold follows the rules' band (both lanes in a switch window).
	var band := logic.band()
	if band != _band:
		_band = band
		hud.metrics.set_power_band(float(band.x), float(band.y))


## The hum brightens in the lane; the music's lead plays only in it, the harmony near it.
func _update_audio(delta: float) -> void:
	var step := delta / HUM_FADE * 30.0
	_hum_in.volume_db = move_toward(_hum_in.volume_db, HUM_DB[true] if logic.in_lane else -60.0, step)
	_hum_out.volume_db = move_toward(_hum_out.volume_db, -60.0 if logic.in_lane else HUM_DB[false], step)
	var intensity := 0.3
	if logic.in_lane:
		intensity = 1.0
	elif absi(logic.shown_watts - (logic.lane_lo() + logic.lane_hi()) / 2) < logic.width:
		intensity = 0.6
	AudioDirector.set_intensity(intensity)


## A soft pulse on the bike's nose once a pedal stroke (cadence), visual only.
func _pedal_beat(delta: float) -> void:
	_beat_phase += delta * InputBus.cadence / 60.0
	if _beat_phase >= 1.0:
		_beat_phase = fmod(_beat_phase, 1.0)
		_beat = 1.0
	_beat = maxf(_beat - delta * 4.0, 0.0)


func _show_message(text: String, seconds: float, color := GameTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
