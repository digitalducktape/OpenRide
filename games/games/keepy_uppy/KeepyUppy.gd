extends Game
## Keepy Uppy (#77): keep a balloon in the air over a fan your pedalling drives, while the
## weather tries to push it down. Ride higher for more points; touch the ground and it pops, and
## a new balloon is on its way.
##
## Rules: `KeepyLogic` (tested headless; DESIGN.md). The picture is 2D, drawn in code like Safe
## Cracker's (ART_BIBLE.md): `KeepyBackdrop` (the place, baked, and its ambient life),
## `KeepyRig` (the pedal fan, its column of air, the height pole), `KeepyBalloon` (the balloon,
## its birds and the pop), `KeepyWeather` (the rain cloud, the bird coming in, the downdraft's
## curtain, a gust) and the swaying foreground grass. HUD widget: `KeepyStatus`. Audio:
## `KeepyAudio` and the rendered theme (`KeepyMusic`). This scene wires them to the framework.
##
## Camera: off unless the rider turned Steer on (Tug of War's brace-lean precedent):
## `tracker_mode_for_segment` returns `lean_x` only then, so the camera runs only for riders who
## use it.

const KeepyAudioScript := preload("res://games/keepy_uppy/KeepyAudio.gd")
const KeepyMusic := preload("res://games/keepy_uppy/KeepyMusic.gd")

## The theme (KeepyMusic): the bed always; the harmony once the balloon is off the ground (the
## mid band), the lead in the high band.
const MUSIC_STYLE := {
	"name": "updraft",
	"stem_files": KeepyMusic.STEM_FILES,
	"loop_from": KeepyMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
const MUSIC_BPM := KeepyMusic.BPM
const ROUND_SEC := 60.0  ## a "round" of a rounds Just Ride: a minute of air time
const HUM_DB := -14.0  ## the fan's hum at full lift
const RAIN_DB := -10.0
const SQUEAK_BELOW := 0.1  ## the balloon squeaks on the grille below this height, sinking
const MESSAGE_SEC := 1.6
## With the Place option on "random", the place changes every PLACE_SEC of play (a cross-fade).
const PLACE_SEC := 180.0
const BOB_PX := 6.0
const GUST_SHAKE_PX := 10.0

## The look (framework/ui/UI_STYLE.md; ART_BIBLE §4): a warm sunset coral on deep sky navy, badges
## leaning a little (lift); the face upright. Clear of Balloon Pump's mint and candy pink.
static var look := GameTheme.new(Color("ff7a59"), Color("12233a"), 0.08)

var logic: KeepyLogic
var backdrop: KeepyBackdrop
var rig: KeepyRig
var balloon: KeepyBalloon
var weather: KeepyWeather
var foreground: Node2D

var _status: KeepyStatus
var banner: KeepyBanner
## The rider's Place option is "random": read once and on change, not from the file every frame.
var _random_place := true
var _hum: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _squeak_left := 0.0
var _rain_level := 0.0
var _rounds := 0
var _place := 0
var _place_left := PLACE_SEC
var _place_rng := RandomNumberGenerator.new()
var _t := 0.0
var _flash := 0.0
var _balloon_at := Vector2(KeepyPlaces.FAN_AT.x, KeepyPlaces.BALLOON_LOW)


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "keepy_uppy"
	i.title = "Keepy Uppy"
	i.how_to = "Pedal to keep the balloon in the air. The higher it flies, the more you score"
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
	var place_ids: Array = ["random"]
	var place_names: Array = ["Random"]
	for p in KeepyPlaces.PLACES:
		place_ids.append(p.id)
		place_names.append(p.name)
	i.summary_stats = [
		{"key": "seconds_high", "label": "seconds high"},
		{"key": "pops", "label": "pops"},
		{"key": "birds_shaken", "label": "birds shaken"},
	]
	i.options = [
		{"key": "steer", "label": "Steer", "choices": ["off", "on"], "labels": ["Off", "On"],
			"default": "off", "kind": "segmented"},
		{"key": "place", "label": "Place", "choices": place_ids, "labels": place_names, "default": "random",
			"group": "More options"},
	]
	return i


## The camera runs only for Steer, which reads the lean.
func tracker_mode_for_segment(_segment: Dictionary) -> String:
	return "lean_x" if option("steer") == "on" else "off"


func how_to_text(_seg: Dictionary) -> String:
	if option("steer") == "on":
		return "Pedal to keep the balloon up. Lean to slide the fan under it"
	return declared().how_to


func target_text(seg: Dictionary) -> String:
	var w := KeepyLogic.weights_for(seg.get("params", {}), str(seg.get("difficulty", "standard")))
	return "About %d W holds it in the middle band" % _holds_watts(w.x, w.y)


func ui_theme() -> GameTheme:
	return look


## The intro card's picture: the bands and their multipliers, and what to watch for.
func intro_visual() -> Control:
	return KeepyIntroVisual.new(look, option("steer") == "on")


func _ready() -> void:
	KeepyAudioScript.register()
	backdrop = KeepyBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	weather = KeepyWeather.new()
	weather.name = "Weather"
	add_child(weather.back)
	rig = KeepyRig.new()
	rig.name = "Rig"
	add_child(rig)
	balloon = KeepyBalloon.new()
	balloon.name = "Balloon"
	add_child(balloon)
	foreground = PaintLayer.new()
	foreground.name = "Foreground"
	foreground.paint = _paint_foreground
	var sway := ShaderMaterial.new()
	sway.shader = preload("res://games/keepy_uppy/shaders/keepy_sway.gdshader")
	sway.set_shader_parameter("amount", 7.0)
	foreground.material = sway
	add_child(foreground)
	add_child(weather.front)
	add_child(weather)  # its own node (it drives the two layers above)
	banner = KeepyBanner.new(look)
	banner.name = "Banner"
	add_child(banner)
	_hum = KeepyAudioScript.loop_player("keepy_fan_hum")
	add_child(_hum)
	_rain = KeepyAudioScript.loop_player("keepy_rain")
	add_child(_rain)


func _on_prepare(seg: Dictionary) -> void:
	logic = KeepyLogic.new(rng.seed, params, difficulty, option("steer") == "on")
	_rounds = 0
	if str(seg.get("end_mode", "timer")) == "game" and params.has("rounds"):
		_rounds = maxi(int(params.rounds), 1)
	_place_rng.seed = rng.seed + 17
	_place = _pick_place(-1)
	_place_left = PLACE_SEC
	_set_place(_place, false)
	hud.set_skin(look.hud_skin())
	_status = KeepyStatus.new(look)
	hud.add_widget(_status)
	banner.follow(hud, _status)
	hud.metrics.set_power_source(smoothed_power)
	_random_place = option("place") == "random"
	AudioDirector.play_music(MUSIC_STYLE, MUSIC_BPM)
	AudioDirector.set_intensity(0.55)
	GameAudio.apply_mix(KeepyAudioScript.music_effects(), KeepyAudioScript.sfx_effects())
	# The scene at rest behind the intro card, and the effects drawn once so they compile now.
	_draw_state(0.0)
	balloon.prewarm()
	weather.prewarm()
	_update_status()


func _pick_place(not_index: int) -> int:
	var fixed := KeepyPlaces.index_of(option("place"))
	if fixed >= 0:
		return fixed
	return KeepyPlaces.random_index(_place_rng, not_index)


func _set_place(index: int, fade: bool) -> void:
	_place = index
	backdrop.set_place(index, fade)
	rig.set_place(index)
	balloon.set_place(index)
	foreground.queue_redraw()


## The ride panel's W: the rules' smoothed power (one watts number on the whole HUD). A bound
## method, so the panel's Callable stops being valid if the game is freed before `clear_widgets`.
func smoothed_power() -> float:
	return logic.smoothed if logic else InputBus.power


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
	match key:
		"steer":
			logic.steer = option("steer") == "on"
			# Switch the camera on or off at once; Kotlin calibrates on the first camera mode.
			Session.set_tracker_mode(tracker_mode_for_segment(segment))
		"place":
			_random_place = option("place") == "random"
			var fixed := KeepyPlaces.index_of(option("place"))
			if fixed >= 0 and fixed != _place:
				_set_place(fixed, true)
			_place_left = PLACE_SEC


func _on_frame(delta: float) -> void:
	var tracking := InputBus.tracker_state == InputBus.TRACKER_TRACKING
	var events := logic.step(delta, InputBus.power, InputBus.lean_x, tracking, not InputBus.sensors_ok)
	if logic.last_points > 0.0:
		award(logic.last_points)
	for event in events:
		_handle(event)
	_draw_state(delta)
	_update_status()
	_update_sound(delta)
	if _random_place:
		_place_left -= delta
		if _place_left <= 0.0 and logic.balloon == KeepyLogic.Balloon.FLYING and logic.weather == KeepyLogic.Weather.CALM:
			_place_left = PLACE_SEC
			_set_place(_pick_place(_place), true)
	if _rounds > 0 and played_sec >= _rounds * ROUND_SEC:
		end_segment()


## Moves everything that moves: the balloon, the fan, the column, the weather, the clouds.
func _draw_state(delta: float) -> void:
	_t += delta
	backdrop.step(delta)
	var power_share := logic.smoothed / maxf(logic.ftp, 1.0)
	var strength := clampf(logic.smoothed / maxf(logic.need(logic.h), 1.0) * 0.8, 0.0, 1.0) * logic.efficiency
	var climb := lerpf(0.25, 1.3, strength)
	if logic.weather == KeepyLogic.Weather.ACTIVE and logic.force == "downdraft":
		climb = -0.9
	var gusting := 1.0 if logic.gust != "" or (logic.force == "downdraft" and logic.weather != KeepyLogic.Weather.CALM) else 0.0
	var wind := 0.3
	if logic.steer:
		wind = logic.wind_target / KeepyLogic.WIND_MAX
	rig.update(delta, logic.fan_x, power_share, strength, climb, gusting, wind)
	var fm := foreground.material as ShaderMaterial
	fm.set_shader_parameter("gust", gusting)
	fm.set_shader_parameter("wind", wind)
	match logic.balloon:
		KeepyLogic.Balloon.FLYING:
			var at := KeepyPlaces.balloon_at(logic.h, logic.x)
			at.y += sin(_t * 1.7) * BOB_PX
			at.x += sin(_t * 1.1) * 3.0
			if logic.gust == "gust":
				at.x += sin(_t * 19.0) * GUST_SHAKE_PX
			_balloon_at = at
			var tilt := sin(_t * 1.3) * 4.0 + clampf((logic.x - logic.fan_x) * 12.0, -16.0, 16.0)
			balloon.show_at(at, clampf(logic.rate, -0.3, 0.3), tilt, logic.birds)
			rig.set_shadow(logic.h, at.x - rig.fan.position.x)
			rig.marker.position.y = at.y
		KeepyLogic.Balloon.POPPED:
			balloon.hide_balloon()
			rig.set_shadow(-1.0, 0.0)
		KeepyLogic.Balloon.ARRIVING:
			var p := clampf(1.0 - logic.state_left / KeepyLogic.ARRIVE_SEC, 0.0, 1.0)
			var e := ease(p, -2.0)
			var from := Vector2(-140.0, 470.0)
			var to := KeepyPlaces.balloon_at(KeepyLogic.START_HEIGHT, logic.fan_x)
			_balloon_at = from.lerp(to, e) + Vector2(0.0, -sin(p * PI) * 40.0)
			balloon.show_at(_balloon_at, 0.0, (1.0 - e) * 20.0, 0)
			rig.set_shadow(-1.0, 0.0)
	weather.update(delta, logic, _balloon_at)


func _handle(event: Dictionary) -> void:
	match event.type:
		"telegraph":
			match event.force:
				"rain":
					AudioDirector.play_sfx("keepy_rain_warn", 1.0)
					GameMix.duck_for_moment(2.0)
					_show_message("Rain: %d W holds it up" % _holds_watts(logic.weight() + logic.rain_watts, logic.height_watts), GameTheme.WARN, 3.0)
				"bird":
					AudioDirector.play_sfx("keepy_bird_flutter", 0.0)
					GameMix.duck_for_moment(1.2)
					_show_message("Bird incoming", GameTheme.WARN, 2.5)
				"downdraft":
					AudioDirector.play_sfx("keepy_downdraft_warn", 1.0)
					GameMix.duck_for_moment(2.4)
					_show_message("Downdraft! Push!", GameTheme.BAD, 2.5)
		"bird_land":
			GameTheme.pop(_status, 1.06)
		"force_start":
			if event.force == "rain":
				_show_message("Raining: %d W holds it up" % _holds_watts(logic.weight(), logic.height_watts), GameTheme.WARN, 4.0)
		"birds_shaken":
			AudioDirector.play_sfx("keepy_birds_shaken")
			_show_message("Shook off %d!" % event.count if event.count > 1 else "Shook it off!", GameTheme.GOOD)
		"birds_leave":
			AudioDirector.play_sfx("keepy_bird_flutter", -8.0)
		"force_end":
			if event.force == "downdraft" and event.get("beaten", false):
				_show_message("Held it!", GameTheme.GOOD)
		"gust_warn":
			AudioDirector.play_sfx("keepy_gust", 0.0)
			_show_message("Gust!", GameTheme.WARN, 2.0)
			GameMix.duck_for_moment(2.0)
		"band":
			if event.band == KeepyLogic.Band.HIGH:
				AudioDirector.play_sfx("keepy_high_chime", -6.0)
		"pop":
			penalize(event.points)
			balloon.pop()
			AudioDirector.play_sfx("keepy_pop", 1.0)
			GameMix.duck_for_sting(1.5)
			_show_message("POP! −%d" % roundi(event.points), GameTheme.BAD)
			GameTheme.pop(hud.score, 1.2)
		"dispatch":
			AudioDirector.play_sfx("keepy_new_balloon", -3.0)
		"arrive":
			_show_message("New balloon!", GameTheme.GOOD)
		"sinking":
			_show_message("Sinking! Pedal a little harder", GameTheme.WARN, 3.0)


## The fan hums with the lift; the rain hisses while it rains; the balloon squeaks on the grille;
## the music fills out with height.
func _update_sound(delta: float) -> void:
	var lift := clampf(logic.smoothed / maxf(logic.need(logic.h), 1.0), 0.0, 1.6)
	_hum.volume_db = lerpf(-40.0, HUM_DB, clampf(lift / 1.2, 0.0, 1.0)) if lift > 0.05 else -80.0
	_hum.pitch_scale = lerpf(0.7, 1.35, clampf(lift / 1.6, 0.0, 1.0))
	_rain_level = move_toward(_rain_level, 1.0 if logic.raining else 0.0, delta / 1.5)
	_rain.volume_db = lerpf(-50.0, RAIN_DB, _rain_level) if _rain_level > 0.01 else -80.0
	_squeak_left -= delta
	if logic.balloon == KeepyLogic.Balloon.FLYING and logic.h < SQUEAK_BELOW and logic.rate < 0.0 and _squeak_left <= 0.0:
		_squeak_left = 0.8
		AudioDirector.play_sfx("keepy_squeak", -4.0, randf_range(0.9, 1.1))
	var intensity := 0.3
	if logic.balloon == KeepyLogic.Balloon.FLYING:
		if logic.band == KeepyLogic.Band.HIGH:
			intensity = 1.0
		elif logic.band == KeepyLogic.Band.MID:
			intensity = 0.6
	AudioDirector.set_intensity(intensity)


func _update_status() -> void:
	var wind := logic.wind_target / KeepyLogic.WIND_MAX if logic.steer else 0.0
	_status.set_state(logic.band, logic.birds, logic.shake_progress, logic.steer, wind)


## The watts, to the nearest 5, that hold the balloon just inside the mid band against a weight
## `w` and height watts `span`: the same figure as the intro's target line.
static func _holds_watts(w: float, span: float) -> int:
	return roundi(KeepyLogic.power_for(KeepyLogic.TARGET_HEIGHT, w, span) / 5.0) * 5


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


## A callout in the banner's lane under the status widget (never the HUD's centre message, which
## would sit on the balloon).
func _show_message(text: String, color := GameTheme.INK, seconds := MESSAGE_SEC) -> void:
	banner.show_callout(text, color, seconds)


## Grass tufts along the bottom edge, in front of the fan's feet, swaying (UV.x = sway weight).
func _paint_foreground(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	_grass(m)
	m.flush(ci)


func _grass(m: MeshBatch2D) -> void:
	var pl := KeepyPlaces.place(_place)
	if pl.id == "rooftop":
		return  # a deck has no grass
	var base: Color = pl.near2
	var tip: Color = (pl.near as Color).lightened(0.15)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31 + _place
	var x := -KeepyPlaces.BLEED
	while x < KeepyPlaces.SIZE.x + KeepyPlaces.BLEED:
		var h := rng.randf_range(26.0, 54.0)
		var y := KeepyPlaces.SIZE.y + 4.0
		for blade in 3:
			var lean := rng.randf_range(-14.0, 14.0)
			var bx := x + blade * 7.0
			m.depth = 0.0
			var i := m.vert(Vector2(bx - 5.0, y), base)
			m.vert(Vector2(bx + 5.0, y), base)
			m.depth = 1.0
			m.vert(Vector2(bx + lean, y - h * rng.randf_range(0.7, 1.0)), tip)
			m.tri(i, i + 1, i + 2)
		x += rng.randf_range(16.0, 30.0)
	m.depth = 0.0
