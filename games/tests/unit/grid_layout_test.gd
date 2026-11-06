extends GdUnitTestSuite
## Power Grid against the frame, the ground and the HUD (the wave A reviews: nothing clipped by the
## frame, the ground line or a HUD panel; scenery kept out from under the panels). The HUD is laid
## out at its widest: the effort badge, a heart strap's column off, a circuit's strip and the
## longest status texts.

const STAGE := Rect2(0, 0, 1920, 1080)
const GridGame := preload("res://games/power_grid/PowerGrid.gd")

var hud: Hud
var status: GridStatus


func before_test() -> void:
	hud = auto_free(Hud.new())
	add_child(hud)
	var info := GameInfo.new()
	info.title = "Power Grid"
	info.id = "power_grid"
	info.tracker_mode = "off"
	hud.setup(info, {"role": "work", "index": 3, "count": 9})
	hud.set_skin(GridGame.look.hud_skin())
	status = GridStatus.new(GridGame.look)
	hud.add_widget(status)
	status.set_state(1.0, 0.7, "powered")
	status.set_districts(PackedInt32Array([1, 2, 3, 4]))
	status.set_note("NEXT: STREET LAMPS")
	hud.metrics.refresh(118, 1888, 100)
	hud.score.set_value("99999")
	Effort.begin_segment(true)


func after_test() -> void:
	hud.clear_skin()


func _panels() -> Array[Rect2]:
	await get_tree().process_frame
	await get_tree().process_frame
	var out: Array[Rect2] = []
	for c: Control in hud.find_children("*", "PanelContainer", true, false):
		if c.is_visible_in_tree() and c.size.x > 0.0:
			out.append(c.get_global_rect())
	for c: Control in hud.find_children("*", "Button", true, false):
		if c.is_visible_in_tree():
			out.append(c.get_global_rect())
	return out


func _clear_of(name: String, r: Rect2, panels: Array[Rect2]) -> void:
	assert_bool(STAGE.encloses(r)).override_failure_message("%s %s leaves the stage" % [name, r]).is_true()
	for p in panels:
		assert_bool(r.intersects(p)).override_failure_message("%s %s is under a HUD panel %s" % [name, r, p]).is_false()


func test_every_prop_stands_inside_the_frame_and_clear_of_the_hud() -> void:
	var panels := await _panels()
	assert_int(panels.size()).is_greater_equal(4)
	var props := GridStage.prop_rects()
	for name in props:
		_clear_of(name, props[name], panels)


func test_the_moon_stays_clear_of_the_hud_and_the_callout_lane() -> void:
	var panels := await _panels()
	var banner: GridBanner = auto_free(GridBanner.new(GridGame.look))
	add_child(banner)
	for r in GridStage.moon_rects():
		_clear_of("moon", r, panels)
		assert_bool(r.intersects(GridBanner.LANE)).is_false()


func test_the_callout_lane_clears_every_panel() -> void:
	var panels := await _panels()
	var lane := GridBanner.LANE
	for p in panels:
		# The status widget's bottom sets the lane's top: it's checked at play, below.
		if p.position.x > 640.0 and p.end.x < 1490.0:
			continue
		assert_bool(lane.intersects(p)).override_failure_message("the lane is under %s" % p).is_false()


func test_a_circuits_status_area_pushes_the_lane_down_clear_of_it() -> void:
	var panels := await _panels()
	var bottom := 0.0
	for p in panels:
		if p.position.x > 640.0 and p.end.x < 1490.0:
			bottom = maxf(bottom, p.end.y)
	var game = auto_free(GridGame.new())
	assert_float(game.lane_top(bottom)).is_greater_equal(bottom)


func test_the_status_widget_fits_its_budget() -> void:
	await _panels()
	status.set_note("REPAIR: 10 s TO GO")
	await get_tree().process_frame
	assert_float(status.size.x).is_less_equal(850.0)
	assert_float(status.size.y).is_less_equal(120.0)


func test_every_label_on_the_widget_is_40_px_or_the_shared_34() -> void:
	assert_int(status.note.get_theme_font_size("font_size")).is_greater_equal(40)
	assert_int(status.badge_label.get_theme_font_size("font_size")).is_greater_equal(HudTheme.SMALL)


func test_the_longest_callouts_fit_the_lane_on_one_line() -> void:
	var banner: GridBanner = auto_free(GridBanner.new(GridGame.look))
	add_child(banner)
	var longest := ["Storm coming: get ready for 1888 W", "Pedal to 1888 W: street lamps fading",
		"1888 W brings the street lamps back", "Street lamps next: hold 1888 W", "Street lamps off for the night",
		"Line down! Hold 1888 W for 10 s"]
	var font := banner.label.get_theme_font("font")
	for text in longest:
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, GridBanner.SIZE).x
		assert_float(w).override_failure_message("'%s' is %.0f px" % [text, w]).is_less_equal(GridBanner.LANE.size.x)
	assert_int(GridBanner.SIZE).is_greater_equal(40)


func test_the_wheel_stands_on_its_yard_not_in_the_ground() -> void:
	var foot := GridValley.WHEEL_AT.y + GridValley.WHEEL_R + 22.0
	assert_float(GridValley.WHEEL_AT.y + GridValley.WHEEL_R).is_less(foot)
	assert_float(foot).is_less(GridValley.road_y(GridValley.WHEEL_AT.x))


func test_pylons_stand_on_the_land_and_get_smaller_down_the_valley() -> void:
	var last := INF
	for i in GridValley.PYLONS.size():
		var foot: Vector2 = GridValley.PYLONS[i][0]
		var h := float(GridValley.PYLONS[i][1])
		assert_float(foot.y).is_greater_equal(GridValley.FLOOR_Y)
		assert_float(h).is_less(last)
		last = h


func test_the_cars_and_lamps_stay_on_the_road() -> void:
	for at: Vector2 in GridValley.lamps():
		assert_float(at.y).is_equal_approx(GridValley.road_y(at.x), 0.01)
		assert_bool(STAGE.has_point(GridValley.lamp_head(at))).is_true()


func test_sky_scenery_stays_under_the_panels() -> void:
	var panels := await _panels()
	var lowest := 0.0
	for p in panels:
		if p.position.x < 640.0 or p.end.x > 1490.0:
			lowest = maxf(lowest, p.end.y)
	assert_float(GridStage.SKY_BAND.x).is_greater_equal(lowest)
	for c in GridStage.CLOUDS:
		assert_float((c[0] as Vector2).y - 30.0).is_greater_equal(lowest)
	assert_float(GridStage.BIRDS_TO.y - 20.0).is_greater_equal(lowest)
	assert_float(GridStage.STORM_RECT.position.y).is_greater_equal(lowest)
	assert_float(GridStage.firework_top()).is_greater_equal(GridBanner.LANE.end.y)


func test_the_shed_stands_on_its_hill() -> void:
	var shed := GridShed.bounds()
	assert_float(GridShed.FLOOR).is_greater_equal(GridValley.near_y(GridShed.POST_L) - 12.0)
	assert_bool(shed.intersects(Rect2(0, 0, 640, 320))).is_false()
	# The machine sits inside the bay, its crank's whole sweep above the floor and under the lintel.
	var reach := GridShed.CRANK_ARM + GridShed.PEDAL.y + 8.0
	assert_float(GridShed.CRANK.y + reach).is_less_equal(GridShed.FLOOR)
	assert_float(GridShed.CRANK.y - reach).is_greater_equal(GridShed.EAVE + 8.0)
	assert_float(GridShed.FLYWHEEL.y - GridShed.FLYWHEEL_R).is_greater_equal(GridShed.EAVE + 8.0)
	assert_float(GridShed.METER.y - GridShed.METER_R - 8.0).is_greater_equal(GridShed.EAVE + 8.0)
