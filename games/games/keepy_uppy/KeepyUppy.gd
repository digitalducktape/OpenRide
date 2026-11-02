extends Game
## Keepy Uppy (#77): keep a balloon in the air over a fan your pedalling drives, while the
## weather tries to push it down. Ride higher for more points; touch the ground and it pops, and
## a new balloon is on its way.
##
## Rules: `KeepyLogic` (tested headless; DESIGN.md). View: `KeepyWorld` (3D, ART_BIBLE.md).
## HUD widget: `KeepyStatus`. Audio: `KeepyAudio` and the rendered "Meadow Breeze"
## (`KeepyMusic`). This scene wires them to the framework: declarations, scoring through award()
## and penalize(), music and effects through AudioDirector, and the rider's Steer option.
##
## Camera: off unless the rider turned Steer on (Tug of War's brace-lean precedent):
## `tracker_mode_for_segment` returns `lean_x` only then, so the camera runs only for riders who
## use it.

const KeepyAudioScript := preload("res://games/keepy_uppy/KeepyAudio.gd")
const KeepyMusic := preload("res://games/keepy_uppy/KeepyMusic.gd")

## "Meadow Breeze": the bed always; the harmony once the balloon is off the ground (mid band),
## the lead in the high band.
const MUSIC_STYLE := {
	"name": "meadow_breeze",
	"stem_files": KeepyMusic.STEM_FILES,
	"loop_from": KeepyMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
const MUSIC_BPM := KeepyMusic.BPM
## The 3D view renders into a SubViewport at this share of the screen (the family's tablet
## recipe: fill-rate bound at 1080p), drawn scaled up under the HUD, which stays sharp.
const RENDER_SCALE := 0.62
const MSAA := Viewport.MSAA_DISABLED
const ROUND_SEC := 60.0  ## a "round" of a rounds Just Ride: a minute of air time
const HUM_DB := -9.0  ## the fan's hum at full lift
const RAIN_DB := -10.0
const SQUEAK_BELOW := 0.1  ## the balloon squeaks on the grille below this height, sinking
const MESSAGE_SEC := 1.6

## The look (framework/ui/UI_STYLE.md; ART_BIBLE §4): meadow mint on deep pine, badges leaning a
## little (lift); the face upright.
static var look := GameTheme.new(Color("2fd3b0"), Color("0b2620"), 0.08)

var logic: KeepyLogic
var world: KeepyWorld

var _view: SubViewport
var _status: KeepyStatus
var _shown: MeshInstance2D
var _hum: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _view_scale := RENDER_SCALE
var _message_left := 0.0
var _squeak_left := 0.0
var _rain_level := 0.0
var _rounds := 0
var governor := RenderScaleStep.new()


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "keepy_uppy"
	i.title = "Keepy Uppy"
	i.how_to = "Pedal to keep the balloon up"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 60
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points a minute (DESIGN.md "Bands and scoring"): steady mid at 1.0× is about 1200 (2 stars),
	# always high at 1.0× about 1800 (short of 3); 3 stars takes riding high with about 1.3×
	# effort (keepy_logic_test). The weight scales with difficulty, so the stars don't.
	i.star_thresholds = {
		"easy": [500, 1100, 2000],
		"standard": [500, 1100, 2000],
		"hard": [500, 1100, 2000],
	}
	i.options = [
		{"key": "steer", "label": "Steer", "choices": ["off", "on"], "labels": ["Off", "On"],
			"default": "off", "kind": "segmented"},
	]
	return i


## The camera runs only for Steer, which reads the lean.
func tracker_mode_for_segment(_segment: Dictionary) -> String:
	return "lean_x" if option("steer") == "on" else "off"


func how_to_text(_seg: Dictionary) -> String:
	if option("steer") == "on":
		return "Pedal to keep the balloon up; lean to slide the fan under it"
	return "Pedal to keep the balloon up: higher pays more"


func target_text(seg: Dictionary) -> String:
	var p: Dictionary = seg.get("params", {})
	var ftp := float(p.get("ftp_watts", p.get("ftp", KeepyLogic.DEFAULT_FTP)))
	var share: float = KeepyLogic.WEIGHT_SHARE.get(str(seg.get("difficulty", "standard")), 0.4)
	var w := float(p.get("weight_watts", ftp * share))
	return "About %d W floats it mid-air" % (roundi(KeepyLogic.power_for(0.5, w) / 5.0) * 5)


func ui_theme() -> GameTheme:
	return look


## The intro card's picture: the bands and their multipliers, and what to watch for.
func intro_visual() -> Control:
	return KeepyIntroVisual.new(look, option("steer") == "on")


func _ready() -> void:
	KeepyAudioScript.register()
	world = KeepyWorld.new()
	world.name = "World"
	_view = SubViewport.new()
	_view.name = "View3D"
	_set_render_scale(RENDER_SCALE)
	_view.msaa_3d = MSAA
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	_view.add_child(world)
	# The view scaled up to the screen: a grid with the vignette in its vertex colours, one draw.
	_shown = MeshInstance2D.new()
	_shown.name = "View3DImage"
	_shown.texture = _view.get_texture()
	_shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_shown)
	_fit_view()
	Stage.changed.connect(_fit_view)
	_hum = KeepyAudioScript.loop_player("keepy_fan_hum")
	add_child(_hum)
	_rain = KeepyAudioScript.loop_player("keepy_rain")
	add_child(_rain)


func _on_prepare(seg: Dictionary) -> void:
	logic = KeepyLogic.new(rng.seed, params, difficulty, option("steer") == "on")
	governor = RenderScaleStep.new()
	_set_render_scale(RENDER_SCALE)
	_rounds = 0
	if str(seg.get("end_mode", "timer")) == "game" and params.has("rounds"):
		_rounds = maxi(int(params.rounds), 1)
	hud.set_skin(look.hud_skin())
	_status = KeepyStatus.new(look)
	hud.add_widget(_status)
	AudioDirector.play_music(MUSIC_STYLE, MUSIC_BPM)
	AudioDirector.set_intensity(0.55)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, KeepyAudioScript.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, KeepyAudioScript.sfx_effects())
	AudioDirector.set_bus_effects(AudioDirector.MASTER_BUS, GameMix.master_effects())
	# One frame of the meadow at rest behind the intro card, and the effects warmed up.
	world.update_view(0.0, logic)
	world.prewarm()
	_update_status()


func _on_start() -> void:
	_hum.play()
	_rain.play()


func _on_pause() -> void:
	_hum.stream_paused = true
	_rain.stream_paused = true


func _on_resume() -> void:
	_hum.stream_paused = false
	_rain.stream_paused = false


func _on_option_changed(key: String, _value: String) -> void:
	if key == "steer":
		logic.steer = option("steer") == "on"
		# Switch the camera on or off at once; Kotlin calibrates on the first camera mode.
		Session.set_tracker_mode(tracker_mode_for_segment(segment))


func _on_frame(delta: float) -> void:
	if governor.sample(delta, logic.balloon == KeepyLogic.Balloon.FLYING):
		_set_render_scale(governor.render_scale(RENDER_SCALE))
		print("OPENRIDE_GAMES keepy_uppy quality tier=%d fps=%.1f scale=%.2f" % [
			governor.tier, governor.last_fps, governor.render_scale(RENDER_SCALE)])
	var tracking := InputBus.tracker_state == InputBus.TRACKER_TRACKING
	var events := logic.step(delta, InputBus.power, InputBus.lean_x, tracking, not InputBus.sensors_ok)
	if logic.last_points > 0.0:
		award(logic.last_points)
	for event in events:
		_handle(event)
	world.update_view(delta, logic, InputBus.cadence)
	_update_status()
	_update_sound(delta)
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	if _rounds > 0 and played_sec >= _rounds * ROUND_SEC:
		end_segment()


func _handle(event: Dictionary) -> void:
	match event.type:
		"telegraph":
			match event.force:
				"rain":
					AudioDirector.play_sfx("keepy_rain_warn", -2.0)
					_show_message("Rain cloud coming", GameTheme.WARN)
				"bird":
					AudioDirector.play_sfx("keepy_bird_flutter", -3.0)
					_show_message("Bird incoming", GameTheme.WARN)
				"downdraft":
					AudioDirector.play_sfx("keepy_downdraft_warn", -1.0)
					GameMix.duck_for_moment(2.4)
					_show_message("Downdraft! Push!", GameTheme.BAD)
		"bird_land":
			world.nudge(0.6)
		"birds_shaken":
			AudioDirector.play_sfx("keepy_birds_shaken")
			_show_message("Shook off %d!" % event.count if event.count > 1 else "Shook it off!", GameTheme.GOOD)
		"birds_leave":
			AudioDirector.play_sfx("keepy_bird_flutter", -8.0)
		"force_end":
			if event.force == "downdraft" and event.get("beaten", false):
				_show_message("Held it!", GameTheme.GOOD)
		"gust_warn":
			AudioDirector.play_sfx("keepy_gust", -4.0)
		"gust":
			world.nudge(1.0)
		"band":
			if event.band == KeepyLogic.Band.HIGH:
				AudioDirector.play_sfx("keepy_high_chime", -6.0)
		"pop":
			penalize(event.points)
			world.pop_at_balloon()
			AudioDirector.play_sfx("keepy_pop")
			GameMix.duck_for_sting(1.5)
			_show_message("POP! −%d" % roundi(event.points), GameTheme.BAD)
			GameTheme.pop(hud.score, 1.2)
		"dispatch":
			AudioDirector.play_sfx("keepy_new_balloon", -3.0)
		"arrive":
			_show_message("New balloon!", GameTheme.GOOD)


## The fan hums with the lift; the rain hisses while it rains; the balloon squeaks on the grille;
## the music fills out with height.
func _update_sound(delta: float) -> void:
	var lift := clampf(logic.smoothed / maxf(logic.weight(), 1.0), 0.0, 1.6)
	_hum.volume_db = lerpf(-40.0, HUM_DB, clampf(lift / 1.2, 0.0, 1.0)) if lift > 0.05 else -80.0
	_hum.pitch_scale = lerpf(0.7, 1.35, clampf(lift / 1.6, 0.0, 1.0))
	_rain_level = move_toward(_rain_level, 1.0 if logic.raining else 0.0, delta / 1.5)
	_rain.volume_db = lerpf(-50.0, RAIN_DB, _rain_level) if _rain_level > 0.01 else -80.0
	_squeak_left -= delta
	if logic.balloon == KeepyLogic.Balloon.FLYING and logic.h < SQUEAK_BELOW and logic.rate < 0.0 and _squeak_left <= 0.0:
		_squeak_left = 0.8
		AudioDirector.play_sfx("keepy_squeak", -4.0, randf_range(0.9, 1.1))
	var intensity := 0.3
	if logic.balloon != KeepyLogic.Balloon.FLYING:
		intensity = 0.3
	elif logic.band == KeepyLogic.Band.HIGH:
		intensity = 1.0
	elif logic.band == KeepyLogic.Band.MID:
		intensity = 0.6
	AudioDirector.set_intensity(intensity)


func _update_status() -> void:
	var warning := ""
	if logic.balloon == KeepyLogic.Balloon.ARRIVING:
		warning = "new"
	elif logic.weather == KeepyLogic.Weather.TELEGRAPH:
		warning = logic.force
	elif logic.weather == KeepyLogic.Weather.ACTIVE and logic.force == "downdraft":
		warning = "downdraft"
	elif logic.gust != "":
		warning = "gust"
	elif logic.raining:
		warning = "raining"
	var wind := logic.wind_target / KeepyLogic.WIND_MAX if logic.steer else 0.0
	_status.set_state(logic.band, warning, logic.birds, logic.shake_progress, logic.steer, wind)


## The result's stats, built once at the end.
func finish() -> Dictionary:
	if logic == null:
		return super.finish()
	stats = {
		"pops": logic.pops,
		"seconds_high": roundi(logic.seconds_high),
		"birds_shaken": logic.birds_shaken,
		"avg_power": roundi(logic.avg_power()),
		"downdrafts": logic.downdrafts,
		"downdrafts_beaten": logic.downdrafts_beaten,
		"best_air": roundi(logic.best_air),
		"steer": logic.steer,
	}
	return super.finish()


func _show_message(text: String, color := GameTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = MESSAGE_SEC


## The 3D view renders at `scale` of the screen's resolution (drawn scaled up under the HUD).
func _set_render_scale(scale: float) -> void:
	_view_scale = scale
	var size := Stage.view_size(scale)
	if _view.size != size:
		_view.size = size


## The view over the whole window, past the centred stage (#57), whenever the window changes.
func _fit_view() -> void:
	_shown.position = -Stage.pad
	_shown.mesh = KeepyMeshes.view_image(Stage.visible_size)
	_set_render_scale(_view_scale)
