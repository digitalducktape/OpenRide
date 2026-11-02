extends Game
## The Pull (#79): a sled pull at a county fair, in first person from the bike. A chain runs back
## to a steel sled, and its weight box slides forward as it goes, so every metre needs more watts.
## Pull until you max out: distance is the score. DESIGN.md (this folder) has the rules and the
## tuning; ART_BIBLE.md the look.
##
## Rules: `PullLogic` (tested headless). View: `PullWorld` (3D). HUD widget: `PullStatus`. Audio:
## `PullAudio`. Bests: `PullBests`. This scene wires them to the framework: declarations, the
## widget and the ride metrics' power band, scoring through award(), the music and effects, and
## the result (its stars from the best single pull).
##
## Every number on screen comes from one place (DESIGN.md "HUD agreement"): the rider's watts
## only in the ride metrics; the sled's need from `PullLogic.shown_need()` in both the widget's
## chip and the metrics' power band; metres from `PullLogic.shown_m()` everywhere.

const PullMusic := preload("res://games/the_pull/PullMusic.gd")

## "Heavy Haul" (PullMusic, rendered by games/tools/music): the bed (drums, bass) always; the
## harmony (chugs, piano) once the sled rolls; the lead near the best flag or the Full Pull line.
const MUSIC_STYLE := {
	"name": "heavy_haul",
	"stem_files": PullMusic.STEM_FILES,
	"loop_from": PullMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
## The 3D view renders into a SubViewport at this share of the screen's resolution, drawn scaled
## up under the HUD (Dodge Ball's pattern: the tablet's GPU is fill-rate bound at 1080p).
const RENDER_SCALE := 0.62
const DIG_IN_TINT := Color(1.0, 0.62, 0.45)
const LOOK_TURN_SEC := 1.2  ## the look back turns to the track over the end of SET
const RESULT_END_DELAY := 2.0  ## after the last pull's result, the segment ends this much later
const NEAR_FULL_M := 20.0

## The look (framework/ui/UI_STYLE.md): tractor green on a dark field green, a slight lean.
static var look := GameTheme.new(PullMeshes.ACCENT, PullMeshes.INK, 0.08)

var logic: PullLogic
var world: PullWorld
var audio: PullAudio

var _view: SubViewport
var _shown: MeshInstance2D
var _status: PullStatus
var _mode := "open"
var _view_distance := 0.0
var _need_shown := -1
var _pull_points := 0.0  ## this pull's points as counted (multiplier included)
var _best_pull_points := 0.0
var _total_full := 0
var _peak_power := 0.0
var _start_best := 0.0
var _message_left := 0.0
var _tint := 0.0
## Steps the 3D view down to a lower render scale if the frame rate stays low in a pull.
var governor := RenderScaleStep.new()
var _view_scale := RENDER_SCALE
var _end_left := -1.0  ## counts down to end_segment after the last result (game time: a pause holds it)


func info() -> GameInfo:
	var i := GameInfo.new()
	i.id = "the_pull"
	i.title = "The Pull"
	i.how_to = "Pull the sled as far as you can: it gets heavier every metre"
	i.supports = ["rounds", "minutes", "open"]
	i.min_sec = 300
	i.max_sec = 3600
	i.min_rounds = 1
	i.max_rounds = 5
	i.roles = []  # Just Ride only; a custom circuit plays it as a free slot (DESIGN.md "Modes")
	i.tracker_mode = "off"
	i.effort_in_just_ride = true
	i.timed_end_mode = "game"  # a pull in progress finishes when the timer runs out
	# The best single pull's points (the game sets the result's stars itself, from the sled's
	# d_ref; these are the defaults for the declared d_ref). FTP held at 1.0x stays short of 3
	# stars and 1.3x reaches them (the_pull_logic_test).
	i.star_thresholds = {}
	for difficulty in PullLogic.D_REF:
		i.star_thresholds[difficulty] = PullLogic.star_thresholds_for(PullLogic.D_REF[difficulty])
	return i


func how_to_text(seg: Dictionary) -> String:
	match _mode_for(seg):
		"rounds":
			var n := int(seg.get("params", {}).get("rounds", 1))
			return "%d pulls: the sled gets heavier every metre. How far can you go?" % n if n > 1 else declared().how_to
		"timed":
			return "Pull after pull until the time is up: the sled gets heavier every metre"
	return declared().how_to


func target_text(seg: Dictionary) -> String:
	var best := PullBests.get_best(str(seg.get("difficulty", "standard")))
	if best > 0.5:
		return "Beat your best: %d m" % PullLogic.shown_m(best)
	var p: Dictionary = seg.get("params", {})
	var d_ref := float(p.get("d_ref_m", PullLogic.D_REF.get(str(seg.get("difficulty", "standard")), 300.0)))
	return "Full Pull at %d m" % PullLogic.shown_m(d_ref * float(p.get("full_factor", PullLogic.FULL_FACTOR)))


func ui_theme() -> GameTheme:
	return look


## rounds (a rounds Just Ride), timed (minutes, or a custom circuit's slot) or open.
static func _mode_for(seg: Dictionary) -> String:
	if float(seg.get("duration_sec", -1)) < 0.0:
		return "open"
	if str(seg.get("end_mode", "timer")) == "game" and seg.get("params", {}).has("rounds"):
		return "rounds"
	return "timed"


func _ready() -> void:
	PullAudio.register()
	world = PullWorld.new()
	world.name = "World"
	_view = SubViewport.new()
	_view.name = "View3D"
	_view.msaa_3d = Viewport.MSAA_DISABLED
	_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_view.audio_listener_enable_3d = false
	add_child(_view)
	_view.add_child(world)
	_shown = MeshInstance2D.new()
	_shown.name = "View3DImage"
	_shown.texture = _view.get_texture()
	_shown.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_shown)
	_fit_view()
	Stage.changed.connect(_fit_view)
	audio = PullAudio.new()
	audio.name = "Audio"
	add_child(audio)


func _on_prepare(seg: Dictionary) -> void:
	_mode = _mode_for(seg)
	_start_best = PullBests.get_best(difficulty)
	logic = PullLogic.new(params, difficulty, _mode, int(params.get("rounds", 1)), float(seg.get("duration_sec", -1)), _start_best)
	_view_distance = 0.0
	_need_shown = -1
	_pull_points = 0.0
	_best_pull_points = 0.0
	_total_full = 0
	_peak_power = 0.0
	_end_left = -1.0
	governor = RenderScaleStep.new()
	_set_render_scale(RENDER_SCALE)
	world.build(logic.full_m, _start_best)
	hud.set_skin(look.hud_skin())
	_status = PullStatus.new(look)
	hud.add_widget(_status)
	_status.set_track(logic.full_m, _start_best)
	_update_status()
	AudioDirector.play_music(MUSIC_STYLE, PullMusic.BPM)
	AudioDirector.set_intensity(0.4)
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, PullAudio.music_effects())
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, PullAudio.sfx_effects())
	AudioDirector.set_bus_effects(AudioDirector.MASTER_BUS, GameMix.master_effects())
	# The sled in the look back behind the intro card (the pull's SET turns to the track), and
	# the effects warmed up.
	world.update_view(0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0)
	world.prewarm()


func _on_start() -> void:
	audio.start_loops()
	_show_message("Get set", PullLogic.SET_SEC - 0.5, GameTheme.TARGET)


func _on_pause() -> void:
	audio.set_paused(true)


func _on_resume() -> void:
	audio.set_paused(false)


func _on_frame(delta: float) -> void:
	if governor.sample(delta, logic.phase == PullLogic.Phase.PULL):
		_set_render_scale(governor.render_scale(RENDER_SCALE))
		print("OPENRIDE_GAMES the_pull quality tier=%d fps=%.1f scale=%.2f" % [
			governor.tier, governor.last_fps, governor.render_scale(RENDER_SCALE)])
	var power := InputBus.power
	var events := logic.step(delta, power, _clock(), InputBus.sensors_ok)
	if logic.last_points > 0.0:
		_pull_points += award(logic.last_points)
	if logic.phase == PullLogic.Phase.PULL:
		_peak_power = maxf(_peak_power, power)
	for event in events:
		_handle(event)
	_update_view(delta, power)
	_update_status()
	if _message_left > 0.0:
		_message_left -= delta
		if _message_left <= 0.0:
			hud.hide_message()
	if _end_left >= 0.0:
		_end_left -= delta
		if _end_left < 0.0:
			end_segment()


## The segment's gameplay seconds so far: Kotlin's clock on the bike, ours on a desktop.
func _clock() -> float:
	var duration := float(segment.get("duration_sec", -1))
	if duration > 0.0 and not InputBus.is_simulated() and InputBus.segment_time_left > 0.0:
		return duration - InputBus.segment_time_left
	return played_sec


func _update_view(delta: float, power: float) -> void:
	var pulling := logic.phase == PullLogic.Phase.PULL
	var look_back := 0.0
	match logic.phase:
		PullLogic.Phase.SET:
			# Looking back at the sled since the intro card; facing the track for the horn.
			look_back = minf(logic.phase_left / LOOK_TURN_SEC, 1.0)
			_view_distance = 0.0
		PullLogic.Phase.PULL, PullLogic.Phase.RESULT:
			_view_distance = logic.distance
		PullLogic.Phase.RECOVERY:
			# The view drifts back to the start over the first part of the rest.
			_view_distance = move_toward(_view_distance, 0.0, maxf(_view_distance / 3.0, 20.0) * delta)
	var strain := 0.0
	if pulling and power > logic.ftp * 0.1:
		strain = clampf(1.0 - logic.speed / 1.0, 0.0, 1.0)
	var slack := 0.0 if pulling and logic.speed > 0.05 or (pulling and power > 20.0) else 1.0
	var near_best := _start_best > 0.0 and pulling and logic.distance >= _start_best - PullLogic.BEST_NEAR \
		and logic.distance <= _start_best + 5.0
	if near_best:
		world.excitement = maxf(world.excitement, 0.8)
	world.update_view(delta, _view_distance, logic.speed if pulling else 0.0, logic.box_t() if pulling or
		logic.phase == PullLogic.Phase.RESULT else 0.0, InputBus.cadence, strain, look_back, slack)
	audio.follow(delta, power / logic.ftp, strain, logic.speed / PullLogic.V_MAX, pulling)
	var intensity := 0.4
	if pulling:
		intensity = 0.6
		if near_best or logic.distance >= logic.full_m - NEAR_FULL_M:
			intensity = 1.0
	elif logic.phase == PullLogic.Phase.RECOVERY:
		intensity = 0.3
	AudioDirector.set_intensity(intensity)
	# Dig in!: the view's edges flush warm, breathing (its modulate; no overlay pass).
	var target_tint := 0.0
	if logic.warned:
		target_tint = 0.5 + 0.5 * sin(played_sec * TAU * 1.5)
	_tint = move_toward(_tint, target_tint, delta * 4.0)
	_shown.modulate = Color.WHITE.lerp(DIG_IN_TINT, _tint * 0.6)


## The widget and the ride metrics' power band, from the one logic.
func _update_status() -> void:
	_status.set_distance(PullLogic.shown_m(logic.distance))
	_status.set_pull(logic.pull_index, logic.rounds if _mode == "rounds" else 0)
	var need := logic.shown_need()
	var band := logic.phase in [PullLogic.Phase.SET, PullLogic.Phase.PULL]
	match logic.phase:
		PullLogic.Phase.SET:
			_status.set_chip("set", 0)
		PullLogic.Phase.PULL:
			if logic.warned:
				_status.set_chip("dig_in", ceili(PullLogic.STALL_SEC - logic.stall_sec))
			else:
				_status.set_chip("need", need)
		PullLogic.Phase.RESULT, PullLogic.Phase.DONE:
			_status.set_chip({"stall": "stalled", "full": "full", "time": "time"}.get(logic.last_end, "stalled"), 0)
		PullLogic.Phase.RECOVERY:
			_status.set_chip("rest", ceili(logic.phase_left))
	var shown := need if band else -1
	if shown != _need_shown:
		_need_shown = shown
		if band:
			hud.metrics.set_power_band(need)
		else:
			hud.metrics.clear_bands()


## The need the HUD shows now in both places (-1 between pulls), for tests.
func shown_need() -> int:
	return _need_shown


func _handle(event: Dictionary) -> void:
	match event.type:
		"go":
			AudioDirector.play_sfx("pull_horn", -2.0)
			GameMix.duck_for_moment(1.0)
			_show_message("PULL!", 1.2, look.accent)
		"set":
			world.excitement = 0.3
			AudioDirector.play_sfx("crowd_swell", -12.0)
			_show_message("Get set", PullLogic.SET_SEC - 0.5, GameTheme.TARGET)
		"board":
			AudioDirector.play_sfx("board_pass", -1.0)
			world.excitement = minf(world.excitement + 0.12, 1.0)
		"dig_in":
			AudioDirector.play_sfx("dig_in", -3.0)
			_show_message("Dig in!", 1.5, GameTheme.WARN)
		"dig_in_clear":
			hud.hide_message()
			_message_left = 0.0
		"best_near":
			AudioDirector.play_sfx("crowd_swell", -6.0)
		"best_passed":
			AudioDirector.play_sfx("best_pass", -3.0)
			GameMix.duck_for_sting(1.5)
			_show_message("New best!", 1.8, GameTheme.TARGET)
			world.excitement = 1.0
		"pull_end":
			_pull_ended(event)
		"done":
			_finish_soon()


func _pull_ended(event: Dictionary) -> void:
	var metres := PullLogic.shown_m(event.distance)
	match event.how:
		"full":
			_pull_points += award(event.points)
			_total_full += 1
			world.full_pull_burst()
			AudioDirector.play_sfx("full_pull")
			AudioDirector.play_sfx("crowd_swell", -2.0)
			GameMix.duck_for_sting(2.5)
			_show_message("FULL PULL! %d m" % metres, PullLogic.RESULT_SEC, GameTheme.GOOD)
			GameTheme.pop(hud.score, 1.2)
		"stall":
			world.stall_dip()
			AudioDirector.play_sfx("stall_horn", -3.0)
			GameMix.duck_for_moment(1.5)
			_show_message("Stalled at %d m" % metres, PullLogic.RESULT_SEC, GameTheme.INK)
		_:
			AudioDirector.play_sfx("stall_horn", -8.0)
			_show_message("Time! %d m" % metres, PullLogic.RESULT_SEC, GameTheme.WARN)
	_best_pull_points = maxf(_best_pull_points, _pull_points)
	_pull_points = 0.0
	if event.new_best:
		PullBests.offer(difficulty, event.distance)
		world.set_best(logic.best_distance)
		_status.set_track(logic.full_m, logic.best_distance)
	_start_best = logic.best_distance


## The timer ran out (end_mode timer) or the rider ended the session: the pull counts as it
## stands.
func _on_finish_requested() -> void:
	var event := logic.end_now()
	if not event.is_empty():
		_pull_ended(event)
	end_segment()


func _finish_soon() -> void:
	if _end_left < 0.0:
		_end_left = RESULT_END_DELAY


## The result's stats, and its stars from the best single pull (DESIGN.md "Scoring and stars").
func finish() -> Dictionary:
	if logic == null:
		return super.finish()
	_best_pull_points = maxf(_best_pull_points, _pull_points)
	stats = {
		"distance_m": PullLogic.shown_m(logic.best_pull_m),
		"best_distance_m": PullLogic.shown_m(logic.best_distance),
		"peak_power": roundi(_peak_power),
		"pull_sec": roundi(logic.best_pull_sec),
		"pulls": logic.pulls_done,
		"full_pulls": _total_full,
	}
	var result := super.finish()
	result["stars"] = Stars.count(_best_pull_points, PullLogic.star_thresholds_for(logic.d_ref))
	return result


func _fit_view() -> void:
	_shown.position = -Stage.pad
	_shown.mesh = PullMeshes.view_image(Stage.visible_size)
	_set_render_scale(_view_scale)


## The 3D view renders at `scale` of the screen's resolution (drawn scaled up under the HUD).
func _set_render_scale(scale: float) -> void:
	_view_scale = scale
	var size := Stage.view_size(scale)
	if _view.size != size:
		_view.size = size


func _show_message(text: String, seconds: float, color := GameTheme.INK) -> void:
	hud.show_message(text, color)
	_message_left = seconds
