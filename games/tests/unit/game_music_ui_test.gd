extends GdUnitTestSuite
## The rider's music mini player over every wave 2 game (the rider: "the UIs for the games should
## also test for the user's audio mini player"). Each game plays through the real SessionDirector,
## HUD and AudioDirector with a track set (`Session.now_playing`):
##
##   - the Music button shows, on screen, clear of the game's status widget, its callouts or
##     banners, its key art, Pause, End and Recalibrate, in a Just Ride and in a circuit (whose
##     strip moves the status widget down), the HUD at its widest (the effort badge, the longest
##     texts), with a heart strap's column and without (the End and Pause checks are strap-off,
##     as in the games' own layout tests: a strap and a five-digit score crowd them with no track);
##   - the music panel opens and closes over the game, which stays paused and unchanged meanwhile
##     and takes the rider's input again after;
##   - `rider_music` stops the game's music and keeps its effects and loops, and the music comes
##     back when it goes off, whether the rider's music started before the game or during it.
##
## A new game is one row in `_games()`:
##   name    the row's name in failure messages
##   id      the game's id; role and params for its segment
##   options optional: the game's options, set for this row and put back after
##   camera  optional: true when Recalibrate shows (the row checks it either way)
##   lean    optional: true when a lean must reach the rules after the panel (they move `fan_x`)
##   widest  func(game): fills the status widget with its longest contents
##   callout the longest callout or centre message
##   art     func(game) -> {name: Rect2}: the game's key art at its extremes, in stage coordinates
##           (a name starting "round " is the oval inside the box: a balloon has no corners)
##   effect  func(game): makes the game play one effect

const LocalSession := preload("res://autoload/LocalSession.gd")

const STAGE := Rect2(0, 0, 1920, 1080)
const TRACK := {"title": "Die With A Smile", "artist": "Lady Gaga, Bruno Mars", "art": "",
	"playing": true, "can_previous": true, "can_next": true}
const PANEL_STEP_SEC := 0.5
const WAIT_MSEC := 8000

var director: SessionDirector
var local: Node
var hud: Hud
var _option_undo: Array = []  ## [info, key, value] per option a row set


func _games() -> Array[Dictionary]:
	return [
		{"name": "Balloon Pump", "id": "balloon_pump", "role": "work", "params": {"ftp_watts": 200.0},
			"widest": func(g: Node) -> void:
				g._status.set_state(1.0, 0.7, "filling")
				g._status.set_count(999)
				g._status.set_race(10, 10, 119.0),
			"callout": "Race won! +1888",
			"art": _pump_art,
			"effect": func(g: Node) -> void: g._audio.on_event({"type": "filled", "kind": "large", "points": 100.0, "gold": true})},
		{"name": "Keepy Uppy, Steer off", "id": "keepy_uppy", "role": "free", "options": {"steer": "off"},
			"params": {"ftp_watts": 200.0, "weight_watts": 80.0},
			"widest": func(g: Node) -> void: g._status.set_state(KeepyLogic.Band.HIGH, 3, 0.5, false, -1.0),
			"callout": "Raining: 1888 W holds it up",
			"art": _keepy_art,
			"effect": func(g: Node) -> void: g._handle({"type": "pop", "points": 50.0})},
		{"name": "Keepy Uppy, Steer on", "id": "keepy_uppy", "role": "free", "options": {"steer": "on"},
			"camera": true, "lean": true, "params": {"ftp_watts": 200.0, "weight_watts": 80.0},
			"widest": func(g: Node) -> void: g._status.set_state(KeepyLogic.Band.HIGH, 3, 0.5, true, -1.0),
			"callout": "Raining: 1888 W holds it up",
			"art": _keepy_art,
			"effect": func(g: Node) -> void: g._handle({"type": "pop", "points": 50.0})},
		{"name": "Watt Lane", "id": "watt_lane", "role": "work", "params": {"ftp_watts": 200.0},
			"widest": func(g: Node) -> void:
				g._status.set_lane(880, 960)
				g._status.set_info(true, 1.75)
				g._status.set_alert("ease", 880),
			"callout": "Caught it!",
			"art": func(_g: Node) -> Dictionary:
				return {"the lane's reach": Rect2(0.0, WattLaneTrack.TOP_Y, STAGE.size.x, WattLaneTrack.BOTTOM_Y - WattLaneTrack.TOP_Y)},
			"effect": func(g: Node) -> void: g._handle({"type": "jump"})},
		{"name": "The Pull", "id": "the_pull", "role": "free", "params": {"ftp_watts": 200.0},
			"widest": func(g: Node) -> void:
				g._status.set_distance(1888)
				g._status.set_chip("need", 1888),
			"callout": "Stalled at 1888 m",
			"art": _pull_art,
			"effect": func(g: Node) -> void: g._handle({"type": "board"})},
		{"name": "Power Grid", "id": "power_grid", "role": "work", "params": {"ftp_watts": 200.0},
			"widest": func(g: Node) -> void:
				g._status.set_state(1.0, 0.7, "powered")
				g._status.set_districts(PackedInt32Array([1, 2, 3, 4]))
				g._status.set_note("NEXT: STREET LAMPS"),
			"callout": "Pedal to 1888 W: street lamps fading",
			"art": _grid_art,
			"effect": func(g: Node) -> void: g._audio.on_event({"type": "strike"})},
		{"name": "Ready for Launch", "id": "ready_for_launch", "role": "work",
			"params": {"ftp_watts": 200.0, "fuel_line_watts": 100.0, "fuel_full_watts": 120.0, "target_watts": 210.0},
			"widest": func(g: Node) -> void:
				g._status.show_state("COUNT", GameTheme.TARGET, 1.0, GameTheme.TARGET, "384,400 km"),
			"callout": "Fuel 100%: push past 2100 W at zero",
			"art": _launch_art,
			"effect": func(g: Node) -> void: g._handle({"type": "tank_full"})},
	]


# --- Each game's key art ---

func _pump_art(g: Node) -> Dictionary:
	var out := {"gauge": Rect2(PumpPlaces.GAUGE_AT - Vector2.ONE * (PumpPlaces.GAUGE_R + 22.0), Vector2.ONE * (PumpPlaces.GAUGE_R + 22.0) * 2.0),
		"barrel": PumpPlaces.BARREL.grow_individual(10, 70, 10, 0), "wheel": PumpStage.wheel_rect(),
		"moon": Rect2(PumpPlaces.MOON - Vector2(60, 60), Vector2(120, 120))}
	for down in [0.0, 1.0]:
		out["handle at %.0f" % down] = PumpStage.handle_rect(down)
	for kind in PumpArt.BALLOON_RADIUS:
		out["round %s balloon" % kind] = PumpStage.balloon_rect(kind)
	var bunch: Array = g.world.bunch_rects()
	for i in bunch.size():
		out["bunch %d" % i] = bunch[i]
	return out


func _keepy_art(g: Node) -> Dictionary:
	var out := {"pole": Rect2(KeepyPlaces.POLE_X - 40.0, KeepyPlaces.POLE_TOP - 22.0, 160.0, KeepyPlaces.FAN_AT.y - KeepyPlaces.POLE_TOP + 40.0)}
	for x in [-KeepyLogic.X_LIMIT, 0.0, KeepyLogic.X_LIMIT]:
		out["fan at %.1f" % x] = KeepyRig.bounds(x)
		g.balloon.show_at(KeepyPlaces.balloon_at(1.0, x) + Vector2(0, -g.BOB_PX), 0.3, 16.0, 3)
		out["balloon at the top, x %.1f" % x] = g.balloon.drawn_bounds()
	return out


func _pull_art(g: Node) -> Dictionary:
	var world: PullWorld = g.world
	var rig: Node3D = world.get_node("Rig")
	var view: SubViewport = g.get_node("View3D")
	var on_stage := func(p: Vector3) -> Vector2:
		return world.camera.unproject_position(rig.to_global(p)) / Vector2(view.size) * Stage.visible_size - Stage.pad
	var box := func(centre: Vector3, half: Vector3) -> Rect2:
		var r := Rect2(on_stage.call(centre), Vector2.ZERO)
		for x in [-1.0, 1.0]:
			for y in [-1.0, 1.0]:
				for z in [-1.0, 1.0]:
					r = r.expand(on_stage.call(centre + half * Vector3(x, y, z)))
		return r
	return {"mirror": box.call(PullWorld.MIRROR, Vector3(PullWorld.MIRROR_SIZE.x / 2.0 + 0.012, PullWorld.MIRROR_SIZE.y / 2.0 + 0.012, 0.01)),
		"handlebars": box.call(PullWorld.BARS, Vector3(PullMeshes.BAR_HALF, 0.03, 0.03))}


func _grid_art(_g: Node) -> Dictionary:
	var out := GridStage.prop_rects()
	var moons := GridStage.moon_rects()
	for i in moons.size():
		out["moon %d" % i] = moons[i]
	out["storm"] = GridStage.STORM_RECT
	return out


func _launch_art(g: Node) -> Dictionary:
	var out := {"clock": LaunchPad.CLOCK_RECT}
	for mark in LaunchRocket.MARKS.size():
		out["mark %d's tower" % mark] = LaunchPad.tower_rect(mark)
		g._mark = mark
		g._stage_launch()
		for i in 3:
			g._draw_state(0.1)
		var r: LaunchRocket = g.rocket
		var s: float = r.scale.x
		var top: float = r.position.y - LaunchRocket.height_of(r.mark) * s
		var half: float = LaunchRocket.half_width_of(r.mark) * s
		out["mark %d's rocket" % mark] = Rect2(r.position.x - half, top, half * 2.0, r.position.y + r.lowest_y() * s - top)
	g.sky.update(LaunchSky.MOON_FROM + 3.0, 1.0, 0.0)
	out["moon"] = g.sky.moon_rect()
	return out


# --- Playing a row ---

func before_test() -> void:
	director = Session.director
	local = Session._local
	hud = director.hud
	director.process_mode = Node.PROCESS_MODE_DISABLED
	local.process_mode = Node.PROCESS_MODE_DISABLED
	director._last_recalibrate_msec = -1
	InputBus._sim_rider_music = false
	InputBus._sim_resistance = 30.0
	InputBus._sim_cadence = 80.0


func after_test() -> void:
	_leave()
	director.process_mode = Node.PROCESS_MODE_ALWAYS
	local.process_mode = Node.PROCESS_MODE_ALWAYS
	Session._on_now_playing({})
	InputBus._sim_rider_music = false
	InputBus._sim_heart_rate = -1.0
	AudioDirector.set_rider_music(false)
	Engine.max_fps = 0


## Advances both clocks by `seconds`, in small steps.
func _step(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(left, 0.25)
		local._process(dt)
		director.calibration._process(dt)
		director._process(dt)
		left -= dt


func _segment(row: Dictionary) -> Dictionary:
	return {"game_id": row.id, "role": row.role, "difficulty": "standard", "duration_sec": 600, "end_mode": "timer",
		"seed": 7, "effort": true, "params": row.params}


## Plays the row's game up to gameplay.
func _play(row: Dictionary, kind := "just_ride") -> Node:
	var options: Dictionary = row.get("options", {})
	var info := GameRegistry.info(row.id)
	for key in options:
		_option_undo.append([info, key, GameOptions.get_value(info, key)])
		GameOptions.set_value(info, key, options[key])
	var segments := [_segment(row)]
	if kind == "circuit":
		segments.append(_segment(row))
	local.start({"kind": kind, "plan_id": "music-ui", "difficulty": "standard", "total_sec": 0, "segments": segments})
	_step(local.calibration_left_sec() + LocalSession.INTRO_SEC + 0.1)
	assert_int(director.phase).override_failure_message("%s never started" % row.name).is_equal(SessionDirector.Phase.PLAYING)
	return director.game


## Ends the ride and puts everything the row changed back.
func _leave() -> void:
	if director.music_panel.is_open():
		director.music_panel.close()
	if Session.active:
		Session.request_end()
		_step(LocalSession.GRACE_SEC + 0.1)
	director.summary_screen.visible = false
	Session.visit_id = ""
	for undo: Array in _option_undo:
		GameOptions.set_value(undo[0], undo[1], undo[2])
	_option_undo.clear()
	AudioDirector.end_session()
	AudioDirector._process(AudioDirector.CROSSFADE_SEC)


func _frames(count := 4) -> void:
	for i in count:
		await get_tree().process_frame


func _until(what: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + WAIT_MSEC
	while not what.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	return what.call()


# --- The Music button's place ---

## The text's box, for a label that spans its row.
func _text_rect(label: Label) -> Rect2:
	var box := label.get_global_rect()
	var w := label.get_theme_font("font").get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1,
		label.get_theme_font_size("font_size")).x
	return Rect2(box.get_center().x - w / 2.0, box.position.y, w, box.size.y)


func _clear_of_music(state: String, thing: String, rect: Rect2) -> void:
	var music := hud.music_button.get_global_rect()
	assert_bool(music.intersects(rect)).override_failure_message("%s: the Music button %s overlaps %s %s" % [
		state, music, thing, rect]).is_false()


func _check_layout(row: Dictionary, kind: String) -> void:
	var state := "%s (%s)" % [row.name, kind]
	Session._on_now_playing(TRACK)
	InputBus._sim_heart_rate = 199.0
	InputBus._sim_cadence = 118.0
	InputBus._sim_resistance = 100.0
	var game := _play(row, kind)
	game.set_process(false)  # the widest contents stay put
	row.widest.call(game)
	hud.metrics.refresh(118, 1888, 100)
	hud.score.set_value("99999")
	Effort.begin_segment(true)
	if "banner" in game:
		game.banner.show_callout(row.callout, GameTheme.WARN, 30.0)
	else:
		hud.show_message(row.callout, GameTheme.WARN)
	await _frames()

	assert_bool(hud.recalibrate_button.is_visible_in_tree()).override_failure_message(
		"%s: Recalibrate" % state).is_equal(bool(row.get("camera", false)))
	var art: Dictionary = row.art.call(game)
	assert_bool(art.is_empty()).override_failure_message("%s: no key art" % state).is_false()
	for strap in [-1.0, 199.0]:
		InputBus._sim_heart_rate = strap
		await _frames()
		_check_music_clear("%s, strap %d" % [state, strap], game, art)
		if strap < 0.0:
			for b: Button in [hud.pause_button, hud.end_button]:
				assert_bool(STAGE.encloses(b.get_global_rect())).override_failure_message(
					"%s: %s %s leaves the stage" % [state, b.text, b.get_global_rect()]).is_true()
	_leave()
	Session._on_now_playing({})


## Whether the oval filling `box` reaches `rect`.
func _oval_touches(box: Rect2, rect: Rect2) -> bool:
	var centre := box.get_center()
	var nearest := centre.clamp(rect.position, rect.end)
	return ((nearest - centre) / (box.size / 2.0)).length_squared() <= 1.0


func _check_music_clear(state: String, game: Node, art: Dictionary) -> void:
	assert_bool(hud.music_button.is_visible_in_tree()).override_failure_message("%s: no Music button" % state).is_true()
	assert_bool(STAGE.encloses(hud.music_button.get_global_rect())).override_failure_message(
		"%s: the Music button %s leaves the stage" % [state, hud.music_button.get_global_rect()]).is_true()
	assert_float(hud.music_button.size.y).is_greater_equal(HudTheme.BUTTON_HEIGHT * 0.8)
	for c: Control in [game._status, hud.ride_panel, hud.clock_panel, hud.pause_button, hud.end_button, hud.recalibrate_button, hud.circuit_strip]:
		if c.is_visible_in_tree():
			_clear_of_music(state, c.name, c.get_global_rect())
	if "banner" in game:
		var lane: Rect2 = game.banner.lane_rect()
		_clear_of_music(state, "the callout lane", lane)
		assert_bool(lane.encloses(_text_rect(game.banner.label))).override_failure_message(
			"%s: the callout %s leaves its lane %s" % [state, _text_rect(game.banner.label), lane]).is_true()
	else:
		_clear_of_music(state, "the centre message", _text_rect(hud._message))
	for name: String in art:
		if name.begins_with("round "):
			assert_bool(_oval_touches(art[name], hud.music_button.get_global_rect())).override_failure_message(
				"%s: the Music button %s overlaps %s %s" % [state, hud.music_button.get_global_rect(), name, art[name]]).is_false()
		else:
			_clear_of_music(state, name, art[name])


func test_the_music_button_clears_every_game_in_a_just_ride() -> void:
	for row in _games():
		await _check_layout(row, "just_ride")


func test_the_music_button_clears_every_game_in_a_circuit() -> void:
	for row in _games():
		await _check_layout(row, "circuit")


# --- The music panel ---

## Everything in the game's rules that can be compared: what a pause must leave alone.
func _rules(game: Node) -> Dictionary:
	var out := {"played_sec": game.played_sec, "score": Effort.score}
	for p in game.logic.get_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE and p.type in [TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING]:
			out[p.name] = game.logic.get(p.name)
	return out


func _assert_same(state: String, before: Dictionary, after: Dictionary) -> void:
	for key in before:
		assert_bool(before[key] == after[key]).override_failure_message("%s: %s went from %s to %s" % [
			state, key, before[key], after[key]]).is_true()


func _loops(game: Node) -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	for p in game.find_children("*", "AudioStreamPlayer", true, false):
		out.append(p as AudioStreamPlayer)
	return out


func _check_panel(row: Dictionary) -> void:
	var state: String = row.name
	var panel := director.music_panel
	Session._on_now_playing(TRACK)
	var game := _play(row)
	var tracker := Session.tracker_mode
	await _frames()
	assert_bool(game.paused).is_false()

	hud.music_button.pressed.emit()
	assert_bool(panel.is_open()).override_failure_message("%s: the panel didn't open" % state).is_true()
	assert_int(panel.layer).is_greater(hud.layer)
	assert_bool(STAGE.encloses(panel.card.get_global_rect())).is_true()
	assert_str(panel.title_label.text).is_equal(TRACK.title)
	assert_bool(Session.paused).override_failure_message("%s: the ride kept going" % state).is_true()
	assert_bool(game.paused).is_true()
	assert_bool(director.pause_overlay.visible).override_failure_message("%s: the pause card came up too" % state).is_false()

	# Open, nothing moves: not the rules, the clock or the score.
	var before := _rules(game)
	var time_left: float = Session.local_time_left()
	await _frames()
	_step(PANEL_STEP_SEC)
	await _frames()
	_assert_same(state, before, _rules(game))
	assert_float(Session.local_time_left()).is_equal(time_left)
	assert_int(director.phase).is_equal(SessionDirector.Phase.PLAYING)
	assert_object(director.game).is_same(game)

	panel.done_button.pressed.emit()
	assert_bool(panel.is_open()).is_false()
	assert_bool(Session.paused).override_failure_message("%s: Done didn't resume the ride" % state).is_false()
	assert_bool(game.paused).is_false()
	assert_str(Session.tracker_mode).is_equal(tracker)
	assert_object(director.game).is_same(game)
	for p in _loops(game):
		assert_bool(p.stream_paused).override_failure_message("%s: %s stayed paused" % [state, p.name]).is_false()

	# The rider's pedalling reaches the rules again, and a lean when the game steers.
	var resumed := _rules(game)
	InputBus._sim_cadence = 110.0
	InputBus._sim_resistance = 60.0
	var moved := func() -> bool:
		InputBus._sim_lean_x = 1.0
		var now := _rules(game)
		return now.played_sec > resumed.played_sec and (not row.get("lean", false) or absf(float(now.fan_x)) > 0.01)
	assert_bool(await _until(moved)).override_failure_message("%s: the input stopped reaching the game" % state).is_true()
	InputBus._sim_lean_x = 0.0

	# A tap outside the card closes it too; a ride the rider had paused stays paused.
	hud.music_button.pressed.emit()
	(panel.get_node("Shade") as Button).pressed.emit()
	assert_bool(panel.is_open()).is_false()
	assert_bool(Session.paused).is_false()
	hud.pause_pressed.emit()
	hud.music_button.pressed.emit()
	panel.done_button.pressed.emit()
	assert_bool(Session.paused).override_failure_message("%s: the panel resumed the rider's pause" % state).is_true()
	assert_bool(director.pause_overlay.visible).is_true()
	Session.request_resume()
	director._sync_pause_screen()
	_leave()
	Session._on_now_playing({})


func test_the_music_panel_opens_and_closes_over_every_game() -> void:
	for row in _games():
		await _check_panel(row)


# --- rider_music ---

## Game music is off, the decks silent, and the game's effects and loops still play.
func _assert_music_off_effects_on(state: String, row: Dictionary, game: Node) -> void:
	AudioDirector._process(AudioDirector.CROSSFADE_SEC)
	assert_bool(AudioDirector._decks[0].playing or AudioDirector._decks[1].playing).override_failure_message(
		"%s: game music kept playing" % state).is_false()
	var sounds: Array = []
	var heard := func(sound: String, bus: String) -> void: sounds.append([sound, bus])
	AudioDirector.sound_played.connect(heard)
	row.effect.call(game)
	AudioDirector.sound_played.disconnect(heard)
	assert_bool(sounds.is_empty()).override_failure_message("%s: the effect stayed silent" % state).is_false()
	for s: Array in sounds:
		assert_str(s[1]).override_failure_message("%s: %s plays on the music's bus" % [state, s[0]]).is_not_equal(AudioDirector.MUSIC_BUS)
	for p in _loops(game):
		assert_str(p.bus).override_failure_message("%s: the loop %s dies with the music" % [state, p.name]).is_equal(AudioDirector.SFX_BUS)
		assert_bool(p.playing).override_failure_message("%s: the loop %s stopped" % [state, p.name]).is_true()


func _check_rider_music(row: Dictionary) -> void:
	var state: String = row.name
	Session._on_now_playing(TRACK)
	# The rider's music starts mid-game.
	var game := _play(row)
	assert_bool(await _until(func(): return AudioDirector.is_music_playing())).override_failure_message(
		"%s: no game music to begin with" % state).is_true()
	var key := AudioDirector.current_music_key()
	InputBus._sim_rider_music = true
	assert_bool(await _until(func(): return AudioDirector.rider_music)).is_true()
	_assert_music_off_effects_on(state, row, game)
	InputBus._sim_rider_music = false
	assert_bool(await _until(func(): return AudioDirector.is_music_playing())).override_failure_message(
		"%s: game music didn't come back" % state).is_true()
	assert_str(AudioDirector.current_music_key()).is_equal(key)
	_leave()

	# The rider's music was on before the game: it never starts, and comes in when it goes.
	InputBus._sim_rider_music = true
	assert_bool(await _until(func(): return AudioDirector.rider_music)).is_true()
	game = _play(row)
	await _frames()
	_assert_music_off_effects_on(state + " (music first)", row, game)
	InputBus._sim_rider_music = false
	assert_bool(await _until(func(): return AudioDirector.is_music_playing())).override_failure_message(
		"%s: game music never came in" % state).is_true()
	assert_str(AudioDirector.current_music_key()).is_equal(key)
	_leave()
	Session._on_now_playing({})


func test_rider_music_stops_game_music_and_keeps_effects_in_every_game() -> void:
	for row in _games():
		await _check_rider_music(row)
