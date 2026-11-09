extends GdUnitTestSuite
## Ready for Launch's scene wiring and frame (#82): the declarations, the intro copy computed from
## the segment, watts once only and agreeing with the rules, no scoring without pedalling, the
## callouts' lane, and the frame check the rider asked for: the rocket, the tower and the clock are
## never clipped by the frame or a HUD panel, on the pad or at any stage of a flight.

const STAGE := Rect2(0, 0, 1920, 1080)
const PARAMS := {"ftp_watts": 200.0, "fuel_line_watts": 20.0, "fuel_full_watts": 60.0, "push_watts": 120.0}

var game: Node


func _make(seg_extra := {}) -> Node:
	var g: Node = load("res://games/ready_for_launch/ReadyForLaunch.tscn").instantiate()
	g.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(g.hud)
	add_child(g)
	var seg := {"game_id": "ready_for_launch", "role": "work", "difficulty": "standard", "duration_sec": 90,
		"end_mode": "timer", "seed": 7, "params": PARAMS}
	seg.merge(seg_extra, true)
	g.prepare(seg)
	return g


func before_test() -> void:
	game = _make()
	game.start()
	game.set_process(false)


func after_test() -> void:
	if is_instance_valid(game):
		game.free()


func test_the_declarations_match_the_issue() -> void:
	var i: GameInfo = game.info()
	assert_array(i.validate()).is_empty()
	assert_array(i.roles).is_equal(["work"])
	assert_str(i.tracker_mode).is_equal("off")
	assert_int(i.min_sec).is_equal(90)
	assert_bool(i.effort_in_just_ride).is_true()
	assert_bool(i.stars_per_minute).is_true()
	assert_array(i.supports).contains_exactly_in_any_order(["rounds", "minutes", "open"])


func test_the_target_line_is_computed_from_the_segment() -> void:
	assert_str(game.target_text({"params": PARAMS})).is_equal("Hold 60 W, then push past 120 W")
	assert_str(game.target_text({"difficulty": "hard", "params": {"ftp_watts": 300.0}})).is_equal("Hold 105 W, then push past 210 W")
	assert_str(game.target_text({"difficulty": "easy", "params": {"ftp_watts": 100.0}})).is_equal("Hold 28 W, then push past 50 W")


func test_the_intro_card_picture_takes_every_number_from_the_segment() -> void:
	var visual: Control = auto_free(game.intro_visual())
	var words := ""
	for l: Label in visual.find_children("*", "Label", true, false):
		words += l.text + "\n"
		assert_int(l.get_theme_font_size("font_size")).is_greater_equal(40)
	assert_str(words).contains("45 s at 60 W")
	assert_str(words).contains("10 s, keep spinning")
	assert_str(words).contains("18 s past 120 W")
	game.free()
	game = _make({"duration_sec": 120, "params": {"ftp_watts": 300.0, "fuel_full_watts": 180.0, "push_watts": 315.0}})
	var longer: Control = auto_free(game.intro_visual())
	words = ""
	for l: Label in longer.find_children("*", "Label", true, false):
		words += l.text + "\n"
	assert_str(words).contains("63 s at 180 W")
	assert_str(words).contains("18 s past 315 W")


func test_the_ride_panel_shows_the_rules_watts_and_nothing_else_does() -> void:
	game.logic.smoothed = 137.0
	assert_float(game.hud.metrics.shown_power()).is_equal(137.0)
	for phase in [LaunchLogic.Phase.FUEL, LaunchLogic.Phase.COUNT, LaunchLogic.Phase.PUSH, LaunchLogic.Phase.COAST]:
		game.logic.phase = phase
		game._update_status()
		for l: Label in game._status.find_children("*", "Label", true, false):
			assert_str(l.text).not_contains(" W")
			assert_str(l.text).not_contains("×")


func test_the_gold_mark_is_what_the_phase_asks_for() -> void:
	assert_float(game.hud.metrics.power_low).is_equal(60.0)
	game.logic.phase = LaunchLogic.Phase.PUSH
	game._set_band()
	assert_float(game.hud.metrics.power_low).is_equal(120.0)
	game.logic.phase = LaunchLogic.Phase.COAST
	game._set_band()
	assert_float(game.hud.metrics.power_low).is_equal(-INF)


func test_a_rider_who_never_pedals_never_scores() -> void:
	Effort.begin_segment(false)
	Effort.set_live(true)
	var was: float = InputBus.power
	InputBus.power = 0.0
	for i in 90 * 10:
		game._on_frame(0.1)
		InputBus.power = 0.0
	InputBus.power = was
	assert_float(Effort.score).is_equal(0.0)
	assert_int(game.logic.launches).is_equal(0)
	Effort.set_live(false)


func test_stats_are_built_at_finish_and_the_summary_finds_them() -> void:
	game.logic.best_climb = 22.0
	game.logic.launches = 1
	var result: Dictionary = game.finish()
	for key in ["launches", "best_altitude", "fuel_pct_avg", "peak_power"]:
		assert_bool(result.stats.has(key)).override_failure_message("stats lacks %s" % key).is_true()
	assert_int(result.stats.best_altitude).is_equal(400)
	for spec in game.info().summary_stats:
		assert_bool(result.stats.has(spec.key)).is_true()


func test_a_rounds_ride_ends_on_its_last_launch() -> void:
	game.free()
	game = _make({"end_mode": "game", "duration_sec": 90, "params": PARAMS.merged({"rounds": 1})})
	game.start()
	game.set_process(false)
	var ended := [false]
	game.ended.connect(func(): ended[0] = true)
	var was: float = InputBus.power
	for i in 910:
		InputBus.power = 130.0
		game._on_frame(0.1)
	InputBus.power = was
	assert_bool(ended[0]).is_true()


func test_a_timed_slot_of_several_launches_moves_to_a_bigger_rocket_on_a_new_pad() -> void:
	game.free()
	GameOptions.set_value(GameRegistry.info("ready_for_launch"), "place", "random")
	game = _make({"duration_sec": 180})
	game.start()
	game.set_process(false)
	var first_place: int = game._place
	assert_int(game._mark).is_equal(0)
	game._handle({"type": "next_launch", "launch": 2})
	assert_int(game._place).is_not_equal(first_place)
	assert_int(game._mark).is_equal(1)


## The HUD's persistent panels and buttons as laid out in play, at their tallest.
func _settle() -> void:
	Effort.begin_segment(true)
	game.hud.metrics.refresh(118, 1888, 100)
	game.hud.score.set_value("99999")
	for i in 4:
		await get_tree().process_frame


func _hud_rects() -> Array[Rect2]:
	var hud: Hud = game.hud
	var out: Array[Rect2] = []
	for c: Control in [hud.ride_panel, hud.clock_panel, hud.pause_button, hud.end_button, game._status]:
		if c != null and c.is_visible_in_tree():
			out.append(c.get_global_rect())
	return out


func _assert_clear(r: Rect2, label: String, panels: Array[Rect2]) -> void:
	assert_bool(STAGE.encloses(r)).override_failure_message("%s %s leaves the frame" % [label, r]).is_true()
	for p in panels:
		assert_bool(r.intersects(p)).override_failure_message("%s %s under the HUD panel %s" % [label, r, p]).is_false()


func _rocket_rect() -> Rect2:
	var r: LaunchRocket = game.rocket
	var s: float = r.scale.x
	var top: float = r.position.y - LaunchRocket.height_of(r.mark) * s
	var bottom: float = r.position.y + r.lowest_y() * s
	var half: float = LaunchRocket.half_width_of(r.mark) * s
	return Rect2(r.position.x - half, top, half * 2.0, bottom - top)


func test_every_rocket_and_tower_stands_clear_of_the_frame_and_the_hud() -> void:
	await _settle()
	var panels := _hud_rects()
	assert_int(panels.size()).is_equal(5)
	for mark in LaunchRocket.MARKS.size():
		game._mark = mark
		game._stage_launch()
		for i in 3:
			game._draw_state(0.1)
		_assert_clear(_rocket_rect(), "mark %d on the pad" % mark, panels)
		_assert_clear(LaunchPad.tower_rect(mark), "mark %d's tower" % mark, panels)
	_assert_clear(LaunchPad.CLOCK_RECT, "the clock", panels)


func test_the_rocket_stays_framed_through_every_stage_of_a_flight() -> void:
	await _settle()
	var panels := _hud_rects()
	for mark in LaunchRocket.MARKS.size():
		game._mark = mark
		game.logic.climb = 0.0
		game.logic.milestone = -1
		game._stage_launch()
		game.logic.phase = LaunchLogic.Phase.PUSH
		game.logic.phase_left = 60.0
		game.logic.lifted = true
		for climb in [0.6, 1.5, 3.0, 5.0, 8.0, 12.0, 18.0, 22.0, 28.0]:
			var events: Array[Dictionary] = []
			game.logic._rise(climb - game.logic.climb, events)
			for e in events:
				game._handle(e)
			for i in 60:
				game._draw_state(0.1)
			_assert_clear(_rocket_rect(), "mark %d at climb %.1f" % [mark, climb], panels)
			var lane: Rect2 = game.banner.lane_rect()
			assert_float(_rocket_rect().position.y).is_greater_equal(lane.end.y)


func test_the_capsule_lands_with_its_feet_on_the_moon() -> void:
	await _settle()
	var events: Array[Dictionary] = []
	game.logic.phase = LaunchLogic.Phase.PUSH
	game.logic.phase_left = 60.0
	game.logic.lifted = true
	game.logic._rise(34.0, events)
	for e in events:
		game._handle(e)
	for i in 120:
		game._draw_state(0.1)
	assert_bool(game._landed).is_true()
	var r: LaunchRocket = game.rocket
	var feet: float = r.position.y + (-r.offsets[r.bottom] + LaunchRocket.LEG_FOOT) * r.scale.x
	assert_float(feet).is_equal_approx(LaunchSky.SURFACE_Y, 2.0)


func test_the_moon_rises_clear_of_the_hud() -> void:
	await _settle()
	game.sky.update(LaunchSky.MOON_FROM + 3.0, 1.0, 0.0)
	var rect: Rect2 = game.sky.moon_rect()
	for p in _hud_rects():
		assert_bool(rect.intersects(p)).override_failure_message("the Moon %s under %s" % [rect, p]).is_false()


func test_every_callout_fits_its_lane_clear_of_the_hud() -> void:
	await _settle()
	var lane: Rect2 = game.banner.lane_rect()
	for p in _hud_rects():
		if p != game._status.get_global_rect():
			assert_bool(lane.intersects(p)).override_failure_message("the lane %s under %s" % [lane, p]).is_false()
	var font: Font = game.banner.label.get_theme_font("font")
	var longest := ["Fuel 100%: push past 2100 W at zero", "Engines off: spin easy to climb on", "Edge of space! Next stop 400 km", "Tank full! Ease off, save your legs",
		"Scrubbed: push past 525 W next time", "Launch 40: hold 1200 W to fill up", "Pedal past 1000 W to fill the tank",
		"The Moon! 384,400 km", "You made it! Spin to touch down", "Edge of space: 100 km"]
	for text in longest:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LaunchBanner.SIZE).x
		assert_float(w).override_failure_message("'%s' is %d px" % [text, w]).is_less_equal(lane.size.x)


func test_the_status_widget_is_one_short_row_with_big_text() -> void:
	var s: LaunchStatus = game._status
	s.show_state("COAST", Color.WHITE, 1.0, Color.WHITE, "384,400 km")
	s.reset_size()
	await get_tree().process_frame
	assert_float(s.get_combined_minimum_size().x).is_less_equal(800.0)
	assert_float(s.get_combined_minimum_size().y).is_less_equal(90.0)
	for l: Label in s.find_children("*", "Label", true, false):
		assert_int(l.get_theme_font_size("font_size")).is_greater_equal(40)


func test_the_exhaust_in_vacuum_is_a_short_wide_fan_never_a_tail() -> void:
	# ART_BIBLE §3: the longest flame in space is no longer than it is wide, at any stage.
	for mark in LaunchRocket.MARKS.size():
		game.rocket.setup(mark)
		while true:
			var length := LaunchRocket.FLAME_MAX * LaunchRocket.FLAME_IN_SPACE
			assert_float(length).is_less_equal(game.rocket.flame.size.x * 1.05)
			if not game.rocket.drop_stage():
				break


func test_nothing_redraws_while_fuelling() -> void:
	await get_tree().process_frame
	var flushes := [0]
	SafeMesh.probe = func(_ci, _points, _indices) -> void: flushes[0] += 1
	var was: float = InputBus.power
	for i in 5:
		InputBus.power = 130.0
		game._on_frame(1.0 / 60.0)
		await get_tree().process_frame
	InputBus.power = was
	SafeMesh.probe = Callable()
	assert_int(flushes[0]).is_equal(0)
