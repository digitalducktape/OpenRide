extends GdUnitTestSuite
## Keepy Uppy's scene wiring and frame (#77, the 2D rework): the camera only with Steer on, the
## intro copy computed from the segment, scoring and the pop's penalty through the framework, the
## stats at finish, the HUD widget's budget, and the frame check the rider asked for: the balloon
## (birds and all), the fan and the height pole are never clipped by the frame, the ground line
## or a HUD panel, at any height and any rail offset.

const STAGE := Rect2(0, 0, 1920, 1080)

var game: Node


func _make(steer := "off", seg_extra := {}) -> Node:
	GameOptions.set_value(GameRegistry.info("keepy_uppy"), "steer", steer)
	var g: Node = load("res://games/keepy_uppy/KeepyUppy.tscn").instantiate()
	g.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(g.hud)
	add_child(g)
	var seg := {"game_id": "keepy_uppy", "role": "free", "difficulty": "standard", "duration_sec": -1,
		"end_mode": "game", "seed": 7, "params": {"ftp_watts": 200.0}}
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
	GameOptions.set_value(GameRegistry.info("keepy_uppy"), "steer", "off")


func test_the_camera_runs_only_with_steer_on() -> void:
	assert_str(game.tracker_mode_for_segment({})).is_equal("off")
	game.free()
	game = _make("on")
	assert_str(game.tracker_mode_for_segment({})).is_equal("lean_x")
	assert_bool(game.logic.steer).is_true()
	assert_str(game.how_to_text({})).is_equal("Pedal to keep the balloon up. Lean to slide the fan under it")


func test_the_declarations_match_the_issue() -> void:
	var i: GameInfo = game.info()
	assert_array(i.validate()).is_empty()
	assert_array(i.roles).is_equal(["work"])
	assert_str(i.tracker_mode).is_equal("off")
	assert_bool(i.effort_in_just_ride).is_true()
	assert_bool(i.stars_per_minute).is_true()
	assert_array(i.supports).contains_exactly_in_any_order(["rounds", "minutes", "open"])
	assert_str(game.how_to_text({})).is_equal("Pedal to keep the balloon in the air. The higher it flies, the more you score")


func test_the_target_line_is_computed_from_the_segment() -> void:
	# Just inside the mid band (30% of a full height): 16 + 0.3 × 150 = 61 W → 60.
	assert_str(game.target_text({"params": {"ftp_watts": 200.0, "weight_watts": 16.0, "height_watts": 150.0}})) \
		.is_equal("About 60 W holds it in the middle band")
	# From FTP and difficulty: hard is 10% + 0.3 × 85% of 300 W = 106.5 → 105.
	assert_str(game.target_text({"difficulty": "hard", "params": {"ftp_watts": 300.0}})).is_equal("About 105 W holds it in the middle band")
	# The rider's bike (FTP 140, standard): 11.2 + 0.3 × 105 = 42.7 → 45, the comfortable effort.
	assert_str(game.target_text({"params": {"ftp_watts": 140.0}})).is_equal("About 45 W holds it in the middle band")


func test_a_pop_takes_fifty_points_off_through_the_framework() -> void:
	Effort.begin_segment(false)
	Effort.set_live(true)
	game.award(500.0)
	var before := Effort.score
	assert_float(before).is_greater(0.0)
	game._handle({"type": "pop", "points": 50.0})
	assert_float(Effort.score).is_equal_approx(before - 50.0, 0.01)
	Effort.set_live(false)


func test_stats_are_built_at_finish() -> void:
	for i in 30:
		game._on_frame(1.0 / 60.0)
	assert_dict(game.stats).is_empty()
	var result: Dictionary = game.finish()
	for key in ["pops", "seconds_high", "birds_shaken", "avg_power", "downdrafts", "downdrafts_beaten", "best_air"]:
		assert_bool(result.stats.has(key)).override_failure_message("stats lacks %s" % key).is_true()
	assert_str(result.variant).is_equal("")


func test_the_balloon_follows_the_logic_height() -> void:
	game.logic.h = 0.9
	game._draw_state(1.0 / 60.0)
	var high: Vector2 = game.balloon.body.position
	game.logic.h = 0.1
	game._draw_state(1.0 / 60.0)
	assert_float(game.balloon.body.position.y - high.y).is_greater(250.0)


func test_a_rounds_ride_ends_after_its_minutes() -> void:
	game.free()
	game = _make("off", {"params": {"ftp_watts": 200.0, "rounds": 1}})
	game.start()
	game.set_process(false)
	var ended := [false]
	game.ended.connect(func(): ended[0] = true)
	game.played_sec = 59.0
	game._on_frame(1.0 / 60.0)
	assert_bool(ended[0]).is_false()
	game.played_sec = 60.0
	game._on_frame(1.0 / 60.0)
	assert_bool(ended[0]).is_true()


func test_the_status_widget_is_one_short_centred_row() -> void:
	var s: KeepyStatus = game._status
	s.set_state(KeepyLogic.Band.HIGH, 3, 0.5, true, -1.0)
	s.reset_size()
	await get_tree().process_frame
	assert_float(s.get_combined_minimum_size().x).is_less_equal(800.0)
	assert_float(s.get_combined_minimum_size().y).is_less_equal(90.0)
	for l: Label in s.find_children("*", "Label", true, false):
		assert_int(l.get_theme_font_size("font_size")).is_greater_equal(HudTheme.SMALL)
		# No second multiplier beside the ride panel's.
		assert_str(l.text).not_contains("×")
	# The chips sit in the middle of the panel, both ways (layout rects: the band's pop scales one).
	var row: Control = s.chips[0].get_parent()
	var left: float = s.chips[0].position.x
	var right: float = row.size.x - s.chips[2].position.x - s.chips[2].size.x
	assert_float(absf(left - right)).is_less_equal(2.0)
	assert_float(absf(row.position.y * 2.0 + row.size.y - s.size.y)).is_less_equal(2.0)


## The HUD's persistent panels and buttons as laid out (stage coordinates).
func _hud_rects() -> Array[Rect2]:
	var hud: Hud = game.hud
	var out: Array[Rect2] = []
	for c: Control in [hud.ride_panel, hud.clock_panel, hud.pause_button, hud.end_button, hud.recalibrate_button, game._status]:
		if c != null and c.is_visible_in_tree():
			out.append(c.get_global_rect())
	return out


## Lays the HUD out as in play: the effort badge's row showing (the ride panel's tallest).
func _settle() -> void:
	Effort.begin_segment(true)
	game.hud.metrics.refresh(118, 1888, 100)
	game.hud.score.set_value("99999")
	for i in 4:
		await get_tree().process_frame


func test_the_balloon_is_never_clipped_by_the_frame_the_ground_or_the_hud() -> void:
	game._status.set_state(KeepyLogic.Band.HIGH, 3, 0.5, true, -1.0)
	await _settle()
	var panels := _hud_rects()
	assert_int(panels.size()).is_greater_equal(4)
	# The ride panel as tall as in play (effort, its gauge, the caption and the metrics).
	assert_float(game.hud.ride_panel.get_global_rect().end.y).is_greater(280.0)
	var grille_bottom := KeepyPlaces.FAN_AT.y + KeepyPlaces.GRILLE.y
	for h in [0.0, 0.2, KeepyLogic.MID_FROM, 0.5, KeepyLogic.HIGH_FROM, 0.85, 1.0]:
		for x in [-KeepyLogic.X_LIMIT, -1.0, 0.0, 1.0, KeepyLogic.X_LIMIT]:
			for squash in [-0.3, 0.0, 0.3]:
				var at := KeepyPlaces.balloon_at(h, x) + Vector2(0, -game.BOB_PX)
				game.balloon.show_at(at, squash, 16.0, 3)
				var r: Rect2 = game.balloon.drawn_bounds()
				var label := "balloon at h=%.2f x=%.1f squash=%.1f: %s" % [h, x, squash, r]
				assert_bool(STAGE.encloses(r)).override_failure_message(label + " leaves the frame").is_true()
				assert_float(r.end.y).override_failure_message(label + " sinks past the grille").is_less_equal(grille_bottom + 24.0)
				for p in panels:
					assert_bool(r.intersects(p)).override_failure_message("%s under the HUD panel %s" % [label, p]).is_false()


## The height pole, streamers and pointer included.
func _pole_rect() -> Rect2:
	return Rect2(KeepyPlaces.POLE_X - 40.0, KeepyPlaces.POLE_TOP - 22.0, 160.0, KeepyPlaces.FAN_AT.y - KeepyPlaces.POLE_TOP + 40.0)


func _assert_rig_clear(panels: Array[Rect2]) -> void:
	for x in [-KeepyLogic.X_LIMIT, 0.0, KeepyLogic.X_LIMIT]:
		var r := KeepyRig.bounds(x)
		assert_bool(STAGE.encloses(r)).override_failure_message("fan at x=%.1f: %s" % [x, r]).is_true()
		# The whole base and its ground shadow show, with a margin under them.
		assert_float(r.end.y).override_failure_message("fan base %s" % r).is_less_equal(STAGE.end.y - 30.0)
		for p in panels:
			assert_bool(r.intersects(p)).override_failure_message("fan %s under %s" % [r, p]).is_false()
	var pole := _pole_rect()
	assert_bool(STAGE.encloses(pole)).override_failure_message("the pole %s leaves the frame" % pole).is_true()
	for p in panels:
		assert_bool(pole.intersects(p)).override_failure_message("the pole %s under %s" % [pole, p]).is_false()


func test_the_fan_and_the_pole_stay_in_frame_and_clear_of_the_hud() -> void:
	await _settle()
	_assert_rig_clear(_hud_rects())
	# The pole's band lines are the logic's.
	assert_float(KeepyPlaces.band_y(KeepyLogic.MID_FROM)).is_greater(KeepyPlaces.band_y(KeepyLogic.HIGH_FROM))


func test_with_steer_on_the_recalibrate_button_clears_the_rig() -> void:
	game.free()
	game = _make("on")
	game.start()
	game.set_process(false)
	await _settle()
	game.hud.recalibrate_button.visible = true
	await get_tree().process_frame
	_assert_rig_clear(_hud_rects())


func test_callouts_sit_in_their_lane_clear_of_the_balloon_and_the_hud() -> void:
	await _settle()
	game._handle({"type": "pop", "points": 50.0})
	game._show_message("Raining: 195 W holds it up", GameTheme.WARN)
	await _settle()
	assert_bool(game.banner.is_showing()).is_true()
	var lane: Rect2 = game.banner.lane_rect()
	var text: Rect2 = game.banner.label.get_global_rect()
	assert_bool(lane.encloses(text)).override_failure_message("callout %s leaves its lane %s" % [text, lane]).is_true()
	for p in _hud_rects():
		assert_bool(lane.intersects(p)).override_failure_message("lane %s under %s" % [lane, p]).is_false()
	# Centred on the stage's panels, and above the balloon at its highest, birds perched.
	game.balloon.show_at(KeepyPlaces.balloon_at(1.0, 0.0) + Vector2(0, -game.BOB_PX), 0.3, 16.0, 3)
	assert_float(game.balloon.drawn_bounds().position.y).is_greater(lane.end.y)
	# Nothing goes to the HUD's centre message, which would cover the balloon.
	assert_bool(game.hud.is_showing_message()).is_false()


func test_the_rain_warning_says_what_the_rain_costs() -> void:
	# The callout's figure is the watts that hold the mid band in the rain.
	var w: float = game.logic.weight() + game.logic.rain_watts
	var span: float = game.logic.height_watts
	game._handle({"type": "telegraph", "force": "rain"})
	assert_str(game.banner.label.text).is_equal("Rain: %d W holds it up" % game._holds_watts(w, span))
	assert_int(game._holds_watts(w, span)).is_greater(game._holds_watts(game.logic.weight(), span))


func test_the_rooftop_has_no_grass() -> void:
	var seen := {}
	for i in KeepyPlaces.count():
		game._set_place(i, false)
		var m := MeshBatch2D.new()
		game._grass(m)
		seen[KeepyPlaces.place(i).id] = m.vertex_count()
	assert_int(seen.rooftop).is_equal(0)
	assert_int(seen.meadow).is_greater(0)


func test_the_summary_shows_the_game_s_own_tiles() -> void:
	var keys: Array = game.info().summary_stats.map(func(d: Dictionary) -> String: return d.key)
	assert_array(keys).is_equal(["seconds_high", "pops", "birds_shaken"])
	var result: Dictionary = game.finish()
	for key in keys:
		assert_bool(result.stats.has(key)).is_true()


func test_the_whole_scene_redraws_nothing_while_playing() -> void:
	# The backdrop is baked once per place: frames only move nodes and set uniforms.
	var bakes: int = game.backdrop.bakes
	for i in 120:
		game._on_frame(1.0 / 60.0)
	assert_int(game.backdrop.bakes).is_equal(bakes)


func test_a_new_place_cross_fades_and_bakes_once() -> void:
	var bakes: int = game.backdrop.bakes
	game._set_place((game._place + 1) % KeepyPlaces.count(), true)
	assert_int(game.backdrop.bakes).is_equal(bakes + 1)
