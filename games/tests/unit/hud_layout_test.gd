extends GdUnitTestSuite
## The HUD lays out at 1920x1080 without any two elements overlapping, in every state a game
## puts it in: playing, the power bonus, the camera-off strip, calibrating and game over. Each
## element is a leaf on screen (a label, a button, a drawn gauge); two leaves may only overlap
## when one contains the other.
##
## It also keeps the road clear: no persistent HUD element may cover the road surface from the
## horizon down to the bike. The road is derived from Dodge Ball's camera (DodgeWorld: eye height,
## pitch, field of view) and its road edges, with the bike anywhere across its range, so a
## screen point is "road" when its ray meets the ground within ROAD_HALF + RIDER_RANGE of the
## road's centre. Both ends of the field of view are checked (it widens with speed), and each
## rect is grown by KEEP_CLEAR_MARGIN for the camera's few degrees of roll. Exempt by design:
## Recalibrate (bottom right, by the rider's choice), the camera strip (its own row, only while
## steering is off) and brief translucent messages.

const SCREEN := Rect2(0, 0, 1920, 1080)
const KEEP_CLEAR_MARGIN := 12.0
const SAMPLE_STEP := 12.0

var hud: Hud
var overlay: CalibrationOverlay
var status: DodgeStatus


func before_test() -> void:
	hud = auto_free(Hud.new())
	add_child(hud)
	overlay = auto_free(CalibrationOverlay.new())
	overlay.strip_host = hud.status_slot
	add_child(overlay)
	var info := GameInfo.new()
	info.title = "Dodge Ball"
	info.id = "dodge_ball"
	info.tracker_mode = "lean_x"
	hud.setup(info, {"role": "work", "index": 3, "count": 9})
	status = DodgeStatus.new(85.0, true, false)
	hud.add_widget(status)
	hud.metrics.set_cadence_band(85.0)
	hud.metrics.set_power_band(210.0)
	# Worst-case contents: the longest texts and numbers each element can show.
	hud.metrics.refresh(118, 1888, 100)
	hud.score.set_value("99999")
	status.set_state(0.0, true, true, 188, 3, 12)
	Effort.begin_segment(true)  # the effort badge shows


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _leaves(root: Node, out: Array[Control]) -> void:
	for child in root.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var c := child as Control
			var is_leaf := c is Label or c is Button or (c.get_child_count() == 0 and c.size.x > 0.0 and c.size.y > 0.0)
			if is_leaf and c is Label and (c as Label).text.is_empty():
				is_leaf = false
			if is_leaf:
				out.append(c)
				continue
		_leaves(child, out)


func _assert_no_overlaps(state: String, roots: Array, at_least := 6) -> void:
	var leaves: Array[Control] = []
	for r in roots:
		_leaves(r, leaves)
	assert_int(leaves.size()).override_failure_message("%s: nothing laid out" % state).is_greater_equal(at_least)
	for c in leaves:
		var rect := c.get_global_rect()
		assert_bool(SCREEN.encloses(rect.grow(-0.5))).override_failure_message(
			"%s: %s %s is off screen" % [state, _name(c), rect]).is_true()
	for i in leaves.size():
		for j in range(i + 1, leaves.size()):
			var a := leaves[i].get_global_rect().grow(-0.5)
			var b := leaves[j].get_global_rect().grow(-0.5)
			assert_bool(a.intersects(b)).override_failure_message("%s: %s %s overlaps %s %s" % [
				state, _name(leaves[i]), a, _name(leaves[j]), b]).is_false()


## Whether screen point `p` (1920x1080) shows road, for a vertical field of view `fov_deg`.
static func on_road(p: Vector2, fov_deg: float) -> bool:
	var t := tan(deg_to_rad(fov_deg) / 2.0)
	var x := (p.x - SCREEN.size.x / 2.0) / (SCREEN.size.y / 2.0) * t
	var y := -(p.y - SCREEN.size.y / 2.0) / (SCREEN.size.y / 2.0) * t
	var pitch := deg_to_rad(DodgeWorld.CAMERA_PITCH)
	var down := y * cos(pitch) + sin(pitch)  # the ray's world y, with z = -1 in camera space
	var forward := y * sin(pitch) - cos(pitch)
	if down >= 0.0:
		return false  # at or above the horizon
	var distance := DodgeWorld.EYE_HEIGHT / -down
	var lateral := x * distance
	return -forward * distance > 0.0 and absf(lateral) <= DodgeBallLogic.ROAD_HALF + DodgeBallLogic.RIDER_RANGE


## The keep-clear check for every persistent leaf under `roots`.
func _assert_road_clear(state: String, roots: Array) -> void:
	var leaves: Array[Control] = []
	for r in roots:
		_leaves(r, leaves)
	for c in leaves:
		if _exempt(c):
			continue
		var rect := c.get_global_rect().grow(KEEP_CLEAR_MARGIN)
		var hit := Vector2(-1, -1)
		var y := rect.position.y
		while y <= rect.end.y and hit.x < 0:
			var x := rect.position.x
			while x <= rect.end.x:
				var p := Vector2(x, y)
				if on_road(p, DodgeWorld.FOV_SLOW) or on_road(p, DodgeWorld.FOV_FAST):
					hit = p
					break
				x += SAMPLE_STEP
			y += SAMPLE_STEP
		assert_bool(hit.x < 0).override_failure_message("%s: %s %s covers the road at %s" % [
			state, _name(c), c.get_global_rect(), hit]).is_true()


func _exempt(c: Control) -> bool:
	return c == hud.recalibrate_button or hud.status_slot.is_ancestor_of(c) or c == hud._message


func test_the_road_keep_clear_area_is_sane() -> void:
	# Sky and the top of the screen are never road; the middle bottom always is.
	assert_bool(on_road(Vector2(960, 100), 62.0)).is_false()
	assert_bool(on_road(Vector2(960, 900), 62.0)).is_true()
	assert_bool(on_road(Vector2(960, 520), 62.0)).is_true()  # just under the horizon (about y 430)
	assert_bool(on_road(Vector2(40, 470), 62.0)).is_false()  # the verge near the horizon


func _name(c: Control) -> String:
	var text: String = c.text if c is Label or c is Button else ""
	return "%s('%s')" % [c.get_path().get_concatenated_names().get_slice("Rows/", 1), text]


func test_playing() -> void:
	await _settle()
	_assert_no_overlaps("playing", [hud])
	_assert_road_clear("playing", [hud])


func test_power_bonus() -> void:
	status.set_state(1.0, false, true, 5, 2, 1)
	hud.metrics.refresh(102, 260, 64)
	await _settle()
	_assert_no_overlaps("power bonus", [hud])
	_assert_road_clear("power bonus", [hud])


func test_camera_off_strip() -> void:
	overlay._show("unavailable")
	overlay._place_strip()
	overlay._strip_text.text = "Camera steering is off: no face found. Is the room bright enough?  ·  tap to try again"
	await _settle()
	assert_object(overlay.strip().get_parent()).is_same(hud.status_slot)
	_assert_no_overlaps("camera off", [hud])
	_assert_road_clear("camera off", [hud])


func test_game_over() -> void:
	hud.show_message("Game over! Next run in 5", HudTheme.WARN)
	await _settle()
	_assert_no_overlaps("game over", [hud])
	_assert_road_clear("game over", [hud])


func test_calibrating_is_a_full_screen_card() -> void:
	overlay._show("calibrating")
	overlay._update_progress({"step": "left", "fraction": 0.4, "step_index": 1, "step_count": 3,
		"attempt": 2, "retry_reason": "too_small", "at_msec": Time.get_ticks_msec()})
	await _settle()
	# The calibration card covers the whole screen (it is modal), and its own parts don't overlap.
	assert_bool(overlay._full.get_global_rect().encloses(SCREEN)).is_true()
	_assert_no_overlaps("calibrating", [overlay._full], 3)
	# Under the calibration card (the game is paused), the HUD keeps the road clear too.
	_assert_road_clear("calibrating", [hud])


func test_ride_metrics_are_uniform_columns() -> void:
	await _settle()
	var m := hud.metrics
	assert_int(m.values.size()).is_equal(3)
	var size: int = m.values[0].get_theme_font_size("font_size")
	var width: float = m.values[0].get_parent().size.x
	for i in 3:
		assert_int(m.values[i].get_theme_font_size("font_size")).is_equal(size)
		assert_int(m.units[i].get_theme_font_size("font_size")).is_equal(m.units[0].get_theme_font_size("font_size"))
		assert_float(m.values[i].get_parent().size.x).is_equal_approx(width, 0.5)
	assert_array(m.units.map(func(u): return u.text)).is_equal(["rpm", "W", "%"])

