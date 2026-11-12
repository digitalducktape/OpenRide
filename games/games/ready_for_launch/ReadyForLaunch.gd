extends Game
## Ready for Launch (#82): each round is one rocket launch. Fuel it with a steady effort, count
## down, then an all-out push at liftoff drives the climb through the clouds, the edge of space,
## orbit and the Moon.
##
## Rules: `LaunchLogic` (tested headless; DESIGN.md). The picture is 2D, drawn in code like Safe
## Cracker's (ART_BIBLE.md): `LaunchSky` (everything above the ground), `LaunchBackdrop` (the place,
## baked), `LaunchPad` (the tower, clock, steam and smoke), `LaunchRocket` (the hero and its
## flame). HUD widget: `LaunchStatus`; callouts: `LaunchBanner`. Audio: `LaunchAudio` and the
## rendered theme (`LaunchMusic`). This scene wires them to the framework and is the camera: it
## scrolls the ground away by the climb (LaunchSky.ground_off) rather than moving a Camera2D, which
## would fight `Stage`'s canvas transform.

const LaunchAudioScript := preload("res://games/ready_for_launch/LaunchAudio.gd")
const LaunchMusic := preload("res://games/ready_for_launch/LaunchMusic.gd")

## The theme ("Moon Shot"): the bed always; the harmony, with the guitar riff, while the tank fills
## and from the count on; the theremin and horns on the push.
const MUSIC_STYLE := {
	"name": "moon_shot",
	"stem_files": LaunchMusic.STEM_FILES,
	"loop_from": LaunchMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
const MUSIC_BPM := LaunchMusic.BPM
const ROUND_SEC := 90.0
const HISS_DB := -15.0
const ENGINE_DB := -9.0
const MESSAGE_SEC := 2.4
const LOW_FUEL_WAIT := 5.0  ## seconds under the line before the callout, and between repeats
const VIEW_MAX_H := 500.0  ## the rocket's height on screen in flight
const VIEW_CENTRE_Y := 590.0  ## the stack's middle in flight
const CAPSULE_SCALE := 1.25
const VIEW_TAU := 0.5
const SHAKE_PX := 5.0
const SHUTTER_SEC := 0.4
const FUEL_COLOR := Color("ffb84a")
const CLIMB_COLOR := Color("2fd6c8")

## The look (framework/ui/UI_STYLE.md; ART_BIBLE §4): a bright mission teal on deep night navy,
## badges leaning a little. Clear of Dodge Ball's sky blue and the meaning colours.
static var look := GameTheme.new(Color("2fd6c8"), Color("0a1a2e"), 0.1)


var logic: LaunchLogic
var sky: LaunchSky
var ground: Node2D
var backdrop: LaunchBackdrop
var pad: LaunchPad
var plume: ColorRect
var rocket: LaunchRocket
var banner: LaunchBanner
var shutter: ColorRect

var _status: LaunchStatus
var _hiss: AudioStreamPlayer
var _engine: AudioStreamPlayer
var _place := 0
var _mark := 0
var _place_rng := RandomNumberGenerator.new()
var _t := 0.0
var _view_scale := 1.0
var _view_y := LaunchPlaces.PAD_Y
var _low_for := 0.0
var _plume_scroll := 0.0
var _landed := false
var _ticks: Array[float] = []


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "ready_for_launch"
	i.title = "Ready for Launch"
	i.how_to = "Fuel the rocket with a steady effort, then give it everything at liftoff"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 90
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 10
	i.roles = ["work"]
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.stars_per_minute = true
	# Points a minute (DESIGN.md "Scoring"): an empty tank and the target about 330 (1 star); a
	# full tank and the target reach orbit, about 1230 (2 stars); a perfect Moon launch at 1.0× is
	# 1640, short of 3; 3 stars takes that with about 1.3× effort (launch_logic_test). The watts
	# scale with difficulty, so the stars don't.
	i.star_thresholds = {
		"easy": [300, 950, 2000],
		"standard": [300, 950, 2000],
		"hard": [300, 950, 2000],
	}
	i.summary_stats = [
		{"key": "best_altitude", "label": "best altitude", "suffix": " km", "grouped": true},
		{"key": "fuel_pct_avg", "label": "average tank", "suffix": "%"},
		{"key": "launches", "label": "launches"},
	]
	var place_ids: Array = ["random"]
	var place_names: Array = ["Random"]
	for p in LaunchPlaces.PLACES:
		place_ids.append(p.id)
		place_names.append(p.name)
	i.options = [
		{"key": "place", "label": "Launch site", "choices": place_ids, "labels": place_names, "default": "random",
			"group": "More options"},
	]
	return i


## The watts the rider sees are the rules' own, whatever the segment.
func target_text(seg: Dictionary) -> String:
	var l := LaunchLogic.new(seg.get("params", {}), str(seg.get("difficulty", "standard")))
	return "Hold %d W, then push past %d W" % [roundi(l.fuel_full), roundi(l.target)]


func ui_theme() -> GameTheme:
	return look


func intro_visual() -> Control:
	return LaunchIntroVisual.new(look, logic)


func _ready() -> void:
	LaunchAudioScript.register()
	sky = LaunchSky.new()
	add_child(sky)
	ground = Node2D.new()
	ground.name = "Ground"
	add_child(ground)
	backdrop = LaunchBackdrop.new()
	ground.add_child(backdrop)
	pad = LaunchPad.new()
	ground.add_child(pad.back)
	plume = ColorRect.new()
	plume.name = "Plume"
	plume.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plume.size = Vector2(1100, 800)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://games/ready_for_launch/shaders/rfl_plume.gdshader")
	plume.material = mat
	plume.visible = false
	add_child(plume)
	rocket = LaunchRocket.new()
	add_child(rocket)
	add_child(pad)
	add_child(sky.front)
	banner = LaunchBanner.new(look)
	banner.name = "Banner"
	add_child(banner)
	shutter = ColorRect.new()
	shutter.name = "Shutter"
	shutter.color = Color(look.ink, 0.0)
	shutter.position = LaunchSky.RECT.position
	shutter.size = LaunchSky.RECT.size
	shutter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shutter.visible = false
	add_child(shutter)
	_hiss = LaunchAudioScript.loop_player("rfl_hiss")
	add_child(_hiss)
	_engine = LaunchAudioScript.loop_player("rfl_engine")
	add_child(_engine)


func _on_prepare(seg: Dictionary) -> void:
	var timed := str(seg.get("end_mode", "timer")) == "timer"
	var rounds := 0
	if not timed and params.has("rounds"):
		rounds = maxi(int(params.rounds), 1)
	var duration := float(seg.get("duration_sec", -1)) if timed else -1.0
	logic = LaunchLogic.new(params, difficulty, duration, rounds)
	_place_rng.seed = rng.seed + 23
	_place = _pick_place(-1)
	_mark = _mark_for(1)
	_stage_launch()
	_ticks.clear()
	for m: Dictionary in LaunchLogic.MILESTONES:
		_ticks.append(float(m.at) / float(LaunchLogic.MILESTONES[-1].at))
	_ticks.pop_back()
	hud.set_skin(look.hud_skin())
	_status = LaunchStatus.new(look)
	hud.add_widget(_status)
	banner.follow(hud, _status)
	hud.metrics.set_power_source(smoothed_power)
	_set_band()
	AudioDirector.play_music(MUSIC_STYLE, MUSIC_BPM)
	AudioDirector.set_intensity(0.55)
	GameAudio.apply_mix(LaunchAudioScript.music_effects(), LaunchAudioScript.sfx_effects())
	_draw_state(0.0)
	_update_status()



## The ride panel's W: the rules' smoothed power (one watts number on the whole HUD). A bound
## method, so the panel's Callable stops being valid if the game is freed before `clear_widgets`.
func smoothed_power() -> float:
	return logic.smoothed if logic else InputBus.power


func _on_start() -> void:
	_hiss.play()
	_engine.play()
	_show_message("Hold %d W to fill the tank" % roundi(logic.fuel_full), FUEL_COLOR, 3.5)


func _on_pause() -> void:
	_hiss.stream_paused = true
	_engine.stream_paused = true


func _on_resume() -> void:
	_hiss.stream_paused = false
	_engine.stream_paused = false


func _on_option_changed(key: String, _value: String) -> void:
	# A site change takes effect on the next pad: a rocket mid-flight stays where it is.
	if key == "place" and logic.phase == LaunchLogic.Phase.FUEL and not logic.lifted:
		var fixed := LaunchPlaces.index_of(option("place"))
		if fixed >= 0 and fixed != _place:
			_place = fixed
			_stage_launch()


func _pick_place(not_index: int) -> int:
	var fixed := LaunchPlaces.index_of(option("place"))
	if fixed >= 0:
		return fixed
	var pick := _place_rng.randi() % LaunchPlaces.count()
	if pick == not_index:
		pick = (pick + 1) % LaunchPlaces.count()
	return pick


## A slot with one launch gets any rocket; a longer ride starts small and builds up.
func _mark_for(launch: int) -> int:
	if logic.planned == 1:
		return _place_rng.randi() % LaunchRocket.MARKS.size()
	return (launch - 1) % LaunchRocket.MARKS.size()


## Everything back on the ground for a launch: `_place`'s pad and `_mark`'s rocket.
func _stage_launch() -> void:
	backdrop.set_place(_place)
	sky.set_place(_place)
	pad.set_stage(_mark, _place)
	rocket.setup(_mark)
	rocket.modulate = LaunchPlaces.place(_place).light
	rocket.rotation = 0.0
	_view_scale = 1.0
	_view_y = LaunchPlaces.PAD_Y
	_landed = false
	_low_for = 0.0
	var p := LaunchPlaces.place(_place)
	var mat := plume.material as ShaderMaterial
	mat.set_shader_parameter("lit", (p.cloud as Color).lightened(0.3))
	mat.set_shader_parameter("shade", p.cloud2)


func _on_frame(delta: float) -> void:
	var events := logic.step(delta, InputBus.power, not InputBus.sensors_ok)
	if logic.last_points > 0.0:
		award(logic.last_points)
	for event in events:
		_handle(event)
	_draw_state(delta)
	_update_status()
	_update_sound(delta)
	_nudge(delta)
	if logic.finished:
		end_segment()


## Moves everything that moves, from the logic alone.
func _draw_state(delta: float) -> void:
	_t += delta
	var c := logic.climb
	var off := LaunchSky.ground_off(c)
	var shake := _shake()
	var on_ground := off < LaunchPlaces.SIZE.y
	ground.visible = on_ground
	pad.visible = on_ground
	ground.position = Vector2(sin(_t * 47.0) * shake * 0.5, off + cos(_t * 53.0) * shake * 0.5)
	pad.position = ground.position
	if on_ground:
		backdrop.step(delta)
		pad.step(delta)
		pad.set_flow(1.0 if logic.flowing else 0.0)
		_update_clock()
	sky.update(c, logic.speed, delta)
	rocket.set_fuel(logic.fuel)
	rocket.thrust = _thrust()
	rocket.space = LaunchSky.space_at(c)
	rocket.step(delta)
	_frame_rocket(delta, shake)
	_update_plume(delta)
	if logic.phase == LaunchLogic.Phase.PUSH:
		pad.trench_glow.modulate.a = clampf(logic.push_share() * 1.3, 0.0, 1.0)
		for b in pad.smoke:
			b.emitting = on_ground and c < LaunchSky.GROUND_GONE * 0.8 and logic.push_share() > 0.1
	else:
		pad.trench_glow.modulate.a = 0.0
		for b in pad.smoke:
			b.emitting = false


## What the engines are doing, 0 off to 1.3.
func _thrust() -> float:
	match logic.phase:
		LaunchLogic.Phase.PUSH:
			return logic.push_share()
		LaunchLogic.Phase.COAST:
			# The capsule's small engine, slowing it down to the surface.
			return 0.4 if _at_moon() and not _landed else 0.0
	return 0.0


func _at_moon() -> bool:
	return logic.milestone == LaunchLogic.MILESTONES.size() - 1


func _shake() -> float:
	if logic.phase != LaunchLogic.Phase.PUSH:
		return 0.0
	var near_ground := 1.0 - clampf(logic.climb / LaunchSky.GROUND_GONE, 0.0, 1.0)
	return SHAKE_PX * logic.push_share() * (0.3 + 0.7 * near_ground)


## The camera on the rocket: on the pad at first, then the stack centred, smaller while it's tall,
## and re-centred as each stage goes; the capsule ends with its feet on the Moon.
func _frame_rocket(delta: float, shake: float) -> void:
	var fly := smoothstep(0.0, 1.6, logic.climb)
	var h := rocket.stack_height()
	var s := minf(VIEW_MAX_H / h, CAPSULE_SCALE)
	var base := VIEW_CENTRE_Y + h * s * 0.5 - rocket.lowest_y() * s
	if _at_moon():
		# Rocket origin so the capsule's feet (legs below its section origin) rest on the surface.
		base = LaunchSky.SURFACE_Y - LaunchRocket.LEG_FOOT * s + rocket.offsets[rocket.bottom] * s
	var want_s := lerpf(1.0, s, fly)
	var want_y := lerpf(LaunchPlaces.PAD_Y, base, fly)
	var k := 1.0 - exp(-delta / VIEW_TAU) if delta > 0.0 else 1.0
	_view_scale = lerpf(_view_scale, want_s, k)
	_view_y = lerpf(_view_y, want_y, k)
	if _at_moon() and not _landed and absf(_view_y - base) < 12.0:
		_landed = true
		_handle({"type": "landed"})
	rocket.scale = Vector2(_view_scale, _view_scale)
	var sway := sin(_t * 1.3) * 5.0 * fly * (0.0 if _landed else 1.0)
	rocket.position = Vector2(LaunchPlaces.PAD_X + sway + sin(_t * 61.0) * shake, _view_y)
	rocket.rotation = deg_to_rad(sin(_t * 0.9) * 0.9) * fly * (0.0 if _landed else 1.0)


## The smoke column under the flame, in the air only.
func _update_plume(delta: float) -> void:
	var air := 1.0 - LaunchSky.space_at(logic.climb)
	var burn := clampf(rocket.thrust * 1.5, 0.0, 1.0)
	var amount := air * burn * smoothstep(0.02, 0.4, logic.climb)
	plume.visible = amount > 0.01
	if not plume.visible:
		return
	_plume_scroll += delta * (1.0 + logic.speed * 2.6)
	var top := rocket.position.y + rocket.lowest_y() * rocket.scale.y + rocket.flame.size.y * rocket.scale.y * 0.4
	plume.position = Vector2(LaunchPlaces.PAD_X - plume.size.x * 0.5, top)
	plume.size.y = maxf(LaunchPlaces.SIZE.y - top, 20.0)
	var mat := plume.material as ShaderMaterial
	mat.set_shader_parameter("amount", amount)
	mat.set_shader_parameter("scroll", _plume_scroll)


func _update_clock() -> void:
	match logic.phase:
		LaunchLogic.Phase.FUEL, LaunchLogic.Phase.COUNT:
			pad.set_clock(ceili(logic.t_minus()), logic.phase)
		_:
			pad.set_clock(0, LaunchLogic.Phase.PUSH)


func _handle(event: Dictionary) -> void:
	match event.type:
		"fuel_on":
			_low_for = 0.0
		"tank_full":
			AudioDirector.play_sfx("rfl_tank_full", -2.0)
			GameMix.duck_for_moment(1.2)
			_show_message("Tank full! Ease off, save your legs", GameTheme.GOOD, 3.5)
		"count_start":
			AudioDirector.play_sfx("rfl_count_start", -1.0)
			GameMix.duck_for_moment(1.5)
			_show_message("Fuel %d%%: push past %d W at zero" % [event.fuel, roundi(logic.target)], GameTheme.TARGET, 5.0)
			_set_band()
		"count":
			_on_count(event.n)
		"ignition":
			AudioDirector.play_sfx("rfl_ignition", -2.5)
			GameMix.duck_for_sting(1.2)
			pad.ignite(1.0)
			_show_message("PUSH past %d W!" % roundi(logic.target), GameTheme.TARGET, 3.0)
			_set_band()
			GameTheme.pop(_status, 1.08)
		"liftoff":
			AudioDirector.play_sfx("rfl_liftoff", -3.0)
		"push_ending":
			_show_message("3 seconds, then spin easy", GameTheme.WARN, 2.8)
		"coast":
			_set_band()
			if event.get("arrived", false):
				_show_message("You made it! Spin to touch down", GameTheme.GOOD, 3.5)
			else:
				AudioDirector.play_sfx("rfl_cutoff", -2.0)
				_show_message("Engines off: spin easy to climb on", GameTheme.GOOD, 3.5)
		"scrub":
			_set_band()
			AudioDirector.play_sfx("rfl_scrub", 0.0)
			GameMix.duck_for_sting(1.5)
			_show_message("Scrubbed: push past %d W next time" % _lift_watts(), GameTheme.BAD, 4.0)
		"milestone":
			_on_milestone(event)
		"result":
			if not event.scrubbed:
				_on_result(event)
		"next_launch":
			_next_launch(event.launch)
		"landed":
			rocket.deploy_legs()
			AudioDirector.play_sfx("rfl_touchdown", 0.0)


func _on_count(n: int) -> void:
	pad.on_count(n)
	# The tone "voice": rising a semitone a second, the last three brighter.
	var pitch := pow(2.0, (10 - n) / 12.0)
	AudioDirector.play_sfx("rfl_count_final" if n <= 3 else "rfl_count", -2.0 if n <= 3 else -3.0, pitch)
	GameMix.duck_for_moment(1.0)
	if n == 5:
		_show_message("Arms back. Get ready to push", GameTheme.TARGET, 2.2)


func _on_milestone(event: Dictionary) -> void:
	var id: String = event.id
	var dropped := rocket.drops_at(id) and rocket.drop_stage()
	if dropped:
		AudioDirector.play_sfx("rfl_stage", 1.0)
	AudioDirector.play_sfx("rfl_moon" if id == "moon" else "rfl_milestone", -1.0 if id == "moon" else -3.0)
	GameMix.duck_for_moment(1.2)
	var km := int(LaunchLogic.MILESTONES[event.index].km)
	var text := "%s! %s km" % [event.name, _grouped(km)]
	if event.index + 1 < LaunchLogic.MILESTONES.size():
		text = "%s! Next stop %s km" % [event.name, _grouped(int(LaunchLogic.MILESTONES[event.index + 1].km))]
	_show_message(text, GameTheme.GOOD, MESSAGE_SEC)
	GameTheme.pop(hud.score, 1.15)


func _on_result(event: Dictionary) -> void:
	var where: String = event.reached
	var text := "%s km! Next launch" % _grouped(roundi(event.km)) if where == "" else "%s: %s km" % [where, _grouped(roundi(event.km))]
	AudioDirector.play_sfx("rfl_result", -3.0)
	_show_message(text, GameTheme.TARGET, 2.2)


func _next_launch(launch: int) -> void:
	_place = _pick_place(_place)
	_mark = _mark_for(launch)
	shutter.visible = true
	var t := create_tween()
	t.tween_property(shutter, "color:a", 1.0, SHUTTER_SEC)
	t.tween_callback(_stage_launch)
	t.tween_callback(func() -> void:
		_set_band()
		_show_message("Launch %d: hold %d W to fill up" % [launch, roundi(logic.fuel_full)], FUEL_COLOR, 3.5))
	t.tween_property(shutter, "color:a", 0.0, SHUTTER_SEC)
	t.tween_callback(func() -> void: shutter.visible = false)


## The ride panel's gold mark: what fills the tank on the ground, the target on the push, none after.
func _set_band() -> void:
	match logic.phase:
		LaunchLogic.Phase.FUEL, LaunchLogic.Phase.COUNT:
			hud.metrics.set_power_band(roundf(logic.fuel_full))
		LaunchLogic.Phase.PUSH:
			hud.metrics.set_power_band(roundf(logic.target))
		_:
			hud.metrics.set_power_band(-INF)


func _lift_watts() -> int:
	return ceili(logic.target * LaunchLogic.LIFT_SHARE)


## Nudges a rider who has dropped under the line or hasn't started the climb.
func _nudge(delta: float) -> void:
	var low := false
	var text := ""
	match logic.phase:
		LaunchLogic.Phase.FUEL:
			low = not logic.flowing and not logic.tank_full
			text = "Pedal past %d W to fill the tank" % roundi(logic.fuel_line)
		LaunchLogic.Phase.PUSH:
			low = not logic.lifted
			text = "Push past %d W to lift off!" % _lift_watts()
	_low_for = _low_for + delta if low else 0.0
	if _low_for >= (LOW_FUEL_WAIT if logic.phase == LaunchLogic.Phase.FUEL else 1.0):
		_low_for = -LOW_FUEL_WAIT
		_show_message(text, GameTheme.WARN, 3.0)


func _update_status() -> void:
	match logic.phase:
		LaunchLogic.Phase.FUEL:
			_status.show_state("FUEL", FUEL_COLOR, logic.fuel, FUEL_COLOR, "%d%%" % logic.fuel_pct())
		LaunchLogic.Phase.COUNT:
			_status.show_state("COUNT", GameTheme.TARGET, logic.fuel, FUEL_COLOR, "%d%%" % logic.fuel_pct())
		_:
			var word := "PUSH" if logic.phase == LaunchLogic.Phase.PUSH else "COAST"
			if logic.phase == LaunchLogic.Phase.RESULT:
				word = "DONE"
			var top: float = LaunchLogic.MILESTONES[-1].at
			_status.show_state(word, CLIMB_COLOR, logic.climb / top, CLIMB_COLOR, "%s km" % _grouped(roundi(logic.km())), _ticks)


## The hiss follows the fuel, the engine the thrust; the music fills out toward the push.
func _update_sound(delta: float) -> void:
	var hiss_want := HISS_DB if logic.flowing else -60.0
	_hiss.volume_db = move_toward(_hiss.volume_db, hiss_want, delta * 60.0)
	_hiss.pitch_scale = lerpf(0.9, 1.2, logic.fuel)
	var thrust := rocket.thrust
	var near_air := 1.0 - 0.75 * LaunchSky.space_at(logic.climb)
	var engine_want := -70.0 if thrust < 0.02 else lerpf(-20.0, ENGINE_DB, clampf(thrust, 0.0, 1.0)) + 20.0 * log(near_air) / log(10.0)
	_engine.volume_db = move_toward(_engine.volume_db, engine_want, delta * 70.0)
	_engine.pitch_scale = lerpf(0.75, 1.25, clampf(thrust / 1.3, 0.0, 1.0))
	var intensity := 0.3
	match logic.phase:
		LaunchLogic.Phase.FUEL:
			intensity = 0.6 if logic.flowing or logic.tank_full else 0.3
		LaunchLogic.Phase.COUNT:
			intensity = 0.6
		LaunchLogic.Phase.PUSH:
			intensity = 1.0 if logic.lifted else 0.6
		LaunchLogic.Phase.COAST, LaunchLogic.Phase.RESULT:
			intensity = 0.6
	AudioDirector.set_intensity(intensity)


## The result's stats, built once at the end.
func finish() -> Dictionary:
	if logic == null:
		return super.finish()
	stats = {
		"launches": logic.launches,
		"best_altitude": roundi(logic.best_km()),
		"fuel_pct_avg": logic.fuel_pct_avg(),
		"peak_power": roundi(logic.peak_power),
		"moons": logic.moons,
	}
	return super.finish()


## A callout in the banner's lane (never the HUD's centre message, which would sit on the rocket).
func _show_message(text: String, color := GameTheme.INK, seconds := MESSAGE_SEC) -> void:
	banner.show_callout(text, color, seconds)


## 384400 as "384,400".
static func _grouped(n: int) -> String:
	return HudTheme.grouped(n)
