extends GdUnitTestSuite
## The HUD lays out at 1920x1080 without any two elements overlapping, in every state a game
## puts it in: playing, the power bonus, the camera-off strip, calibrating and game over. Each
## element is a leaf on screen (a label, a button, a drawn gauge); two leaves may only overlap
## when one contains the other.

const SCREEN := Rect2(0, 0, 1920, 1080)

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


func _name(c: Control) -> String:
	var text: String = c.text if c is Label or c is Button else ""
	return "%s('%s')" % [c.get_path().get_concatenated_names().get_slice("Rows/", 1), text]


func test_playing() -> void:
	await _settle()
	_assert_no_overlaps("playing", [hud])


func test_power_bonus() -> void:
	status.set_state(1.0, false, true, 5, 2, 1)
	hud.metrics.refresh(102, 260, 64)
	await _settle()
	_assert_no_overlaps("power bonus", [hud])


func test_camera_off_strip() -> void:
	overlay._show("unavailable")
	overlay._place_strip()
	overlay._strip_text.text = "Camera steering is off: no face found. Is the room bright enough?  ·  tap to try again"
	await _settle()
	assert_object(overlay.strip().get_parent()).is_same(hud.status_slot)
	_assert_no_overlaps("camera off", [hud])


func test_game_over() -> void:
	hud.show_message("Game over! Next run in 5", HudTheme.WARN)
	await _settle()
	_assert_no_overlaps("game over", [hud])


func test_calibrating_is_a_full_screen_card() -> void:
	overlay._show("calibrating")
	overlay._update_progress({"step": "left", "fraction": 0.4, "step_index": 1, "step_count": 3,
		"attempt": 2, "retry_reason": "too_small", "at_msec": Time.get_ticks_msec()})
	await _settle()
	# The calibration card covers the whole screen (it is modal), and its own parts don't overlap.
	assert_bool(overlay._full.get_global_rect().encloses(SCREEN)).is_true()
	_assert_no_overlaps("calibrating", [overlay._full], 3)
