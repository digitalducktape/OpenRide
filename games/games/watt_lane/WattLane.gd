extends Game
## Watt Lane (#78): a chevron cursor following an illuminated horizontal lane. Your power is
## the cursor's height; the lane comes in from the right and steps up or down. Hold the wattage,
## then the next one. Every step is shown ahead and announced 5 s before with chevrons, its new
## watts, a countdown chip and a chime (rider's decisions, 2026-11-02: 2D and horizontal, so no
## one reads a change as "lean"; abstract, with a chevron cursor). DESIGN.md has the rules.
##
## Rules: `WattLaneLogic` (tested headless). View: `WattLaneBackdrop` (the abstract field) and
## `WattLaneTrack` (the lane and the cursor), 2D on the full canvas. HUD: `WattLaneStatus`.
## Audio: `WattLaneAudio`. This scene wires them to the framework: declarations, scoring through
## award() (the effort multiplier applies in work), music and effects through AudioDirector, and
## the HUD's one power number (the ride panel shows the rules' smoothed watts).

const WattLaneAudioScript := preload("res://games/watt_lane/WattLaneAudio.gd")
const WattLaneMusic := preload("res://games/watt_lane/WattLaneMusic.gd")

## "Live Wire": the bed always; the harmony near the lane; the lead only in it.
const MUSIC_STYLE := {
	"name": "live_wire",
	"stem_files": WattLaneMusic.STEM_FILES,
	"loop_from": WattLaneMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.45, "lead": 0.9},
}
const HUM_DB := {true: -15.0, false: -24.0}  ## the hum's level in and out of the lane
const HUM_FADE := 0.6  ## seconds for the hum to swap
const PEDAL_WATTS := 15.0  ## under this (smoothed) the alert says PEDAL

## The look (ART_BIBLE.md §4, framework/ui/UI_STYLE.md): copper (the wires) on dusk navy,
## upright. Not lime: an accent must never read as a meaning colour (green, GOOD).
static var look := GameTheme.new(Color("f0875a"), Color("0f1a2e"), 0.0)

var logic: WattLaneLogic
var backdrop: WattLaneBackdrop
var track: WattLaneTrack

var _status: WattLaneStatus
var _hum_in: AudioStreamPlayer
var _hum_out: AudioStreamPlayer
var _beat := 0.0
var _beat_phase := 0.0
var _beats := 0
var _band := Vector2i(-1, -1)


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "watt_lane"
	i.title = "Watt Lane"
	i.how_to = "More watts move you up. Keep the chevron in the lit lane"
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
	i.summary_stats = [
		{"key": "in_lane_pct", "label": "in lane", "suffix": "%"},
		{"key": "longest_streak_sec", "label": "best streak", "suffix": " s"},
		{"key": "jumps_caught", "of": "jumps", "label": "steps caught"},
	]
	return i


func how_to_text(_seg: Dictionary) -> String:
	return "More watts move you up. Keep the chevron in the lit lane"


func target_text(seg: Dictionary) -> String:
	var preview := WattLaneLogic.new(str(seg.get("difficulty", "standard")), seg.get("params", {}),
		int(seg.get("seed", 0)), str(seg.get("role", "work")))
	return "Start between %d and %d W" % [preview.lane_lo(), preview.lane_hi()]


func ui_theme() -> GameTheme:
	return look


## The ride panel's W: the rules' smoothed power (one number on the whole HUD). A bound method,
## so the panel's Callable stops being valid if the game is freed before `clear_widgets`.
func smoothed_power() -> float:
	return logic.smoothed if logic else InputBus.power


## The intro card's picture: the hub card (the lane and the cursor).
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
	backdrop = WattLaneBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	track = WattLaneTrack.new()
	track.name = "Track"
	add_child(track)
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


func _on_prepare(seg: Dictionary) -> void:
	logic = WattLaneLogic.new(difficulty, params, int(seg.get("seed", 0)), str(seg.get("role", "work")))
	track.setup(logic.ftp, logic.width, look, backdrop.tile_texture())
	backdrop.set_beat_px(60.0 / WattLaneMusic.BPM * WattLaneTrack.SPEED)
	hud.set_skin(look.hud_skin())
	_status = WattLaneStatus.new(look)
	hud.add_widget(_status)
	hud.metrics.set_power_source(smoothed_power)
	_band = Vector2i(-1, -1)
	AudioDirector.play_music(MUSIC_STYLE, WattLaneMusic.BPM)
	AudioDirector.set_intensity(0.5)
	GameAudio.apply_mix(WattLaneAudioScript.music_effects(), WattLaneAudioScript.sfx_effects())
	# The rider starts in the lane's middle on the intro card: one frame of the lane at rest.
	var centre := float(logic.course.centre_at(0.0))
	track.update_view(0.0, logic.course, 0.0, centre, true, -1.0, true)
	backdrop.update_view(track.scroll, 0.0)
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
	_music_beat(delta)
	track.update_view(delta, logic.course, logic.time, logic.smoothed, logic.in_lane,
		float(up.get("at", -1.0)), bool(up.get("up", true)), int(up.get("lo", 0)), int(up.get("hi", 0)), _beat)
	backdrop.update_view(track.scroll, _beat)
	_update_status()
	_update_audio(delta)


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
			track.caught()
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
	_status.set_info(logic.in_lane, logic.streak_multiplier())
	var up := logic.upcoming()
	if up.is_empty():
		_status.set_countdown(true, 0, 0, -1)
	else:
		_status.set_countdown(bool(up.up), int(up.lo), int(up.hi), ceili(float(up.at)) if float(up.at) > 0.05 else 0)
	# Off the lane: which way, and how far in whole watts from the band the rules use.
	var band := logic.band()
	var alert := WattLaneStatus.ALERT_NONE
	var off := 0
	if logic.smoothed < PEDAL_WATTS:
		alert = WattLaneStatus.ALERT_PEDAL
	elif logic.shown_watts < band.x:
		alert = WattLaneStatus.ALERT_PUSH
		off = band.x - logic.shown_watts
	elif logic.shown_watts > band.y:
		alert = WattLaneStatus.ALERT_EASE
		off = logic.shown_watts - band.y
	_status.set_alert(alert, off)
	# The ride panel's gold follows the rules' band (both lanes in a switch window).
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


## The music's beat (WattLaneMusic.BPM) as a flare that decays: the lane's edges, the field's
## beat lines and the cursor's glow pulse with it. Visual only, on the game's own clock.
func _music_beat(delta: float) -> void:
	_beat_phase += delta * WattLaneMusic.BPM / 60.0
	if _beat_phase >= 1.0:
		_beat_phase = fmod(_beat_phase, 1.0)
		_beat = 1.0
		_beats += 1
	_beat = maxf(_beat - delta * 3.5, 0.0)


func _show_message(text: String, seconds: float, color := GameTheme.INK) -> void:
	hud.show_message(text, color, seconds)
