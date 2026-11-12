extends GdUnitTestSuite
## The calibration screen and strips (framework/ui/CalibrationOverlay.gd): every step draws its
## pose, its dots and its countdown without its parts overlapping, inside the card; the look
## follows the game (the house look without one); taps only ask for a calibration when none
## runs. The session-level behaviour (modes from tracker_state, the debounce) is in
## session_director_test.

const SCREEN := Rect2(0, 0, 1920, 1080)
const STEPS := ["centre", "left", "right", "in", "back"]

var overlay: CalibrationOverlay
var requests := 0


func before_test() -> void:
	overlay = auto_free(CalibrationOverlay.new())
	add_child(overlay)
	overlay.set_process(false)  # no session here: its _process would hide everything
	requests = 0
	overlay.recalibrate_requested.connect(func(): requests += 1)


func _progress(step: String, fraction: float, index: int, count := 5, attempt := 1, reason := "") -> void:
	overlay._show("calibrating")
	overlay._update_progress({"step": step, "fraction": fraction, "step_index": index, "step_count": count,
		"attempt": attempt, "retry_reason": reason, "at_msec": Time.get_ticks_msec()})


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame
	await get_tree().create_timer(GameTheme.POP_SEC + 0.1).timeout  # a step's slam has landed


func _leaves(root: Node, out: Array[Control]) -> void:
	for child in root.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var c := child as Control
			if c is Label and (c as Label).text.is_empty():
				continue
			if c is Label or c.get_child_count() == 0 or c == overlay._tap_pill:
				out.append(c)
				continue
		_leaves(child, out)


func _assert_tidy(what: String) -> void:
	var card := overlay._card.get_global_rect()
	assert_bool(SCREEN.encloses(card)).is_true()
	var leaves: Array[Control] = []
	_leaves(overlay._card, leaves)
	for i in leaves.size():
		var a := leaves[i].get_global_rect()
		assert_bool(card.encloses(a)).override_failure_message("%s: %s %s leaves the card %s" % [what, leaves[i], a, card]).is_true()
		for j in range(i + 1, leaves.size()):
			var b := leaves[j].get_global_rect()
			assert_bool(a.grow(-1).intersects(b.grow(-1))).override_failure_message(
				"%s: %s %s overlaps %s %s" % [what, leaves[i], a, leaves[j], b]).is_false()


func _tap(at: Vector2) -> void:
	for pressed in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		get_tree().root.push_input(click, true)


func test_every_step_draws_its_pose_and_dots_without_overlaps() -> void:
	for i in STEPS.size():
		_progress(STEPS[i], 0.5, i, 5, 2, "too_small")
		await _settle()
		assert_str(overlay._prompt.text).is_equal(CalibrationOverlay.PROMPTS[STEPS[i]])
		assert_str(overlay.figure().step).is_equal(STEPS[i])
		assert_float(overlay.figure().fraction).is_equal(0.5)
		assert_bool(overlay._dots.visible).is_true()
		assert_int(overlay._dots.count).is_equal(5)
		assert_int(overlay._dots.current).is_equal(i)
		# The centre counts 3-2-1 beside the figure; the leans don't.
		assert_bool(overlay._count.visible).is_equal(STEPS[i] == "centre")
		_assert_tidy(STEPS[i])


func test_a_centre_only_run_has_no_dots_and_counts_down() -> void:
	_progress("centre", 0.1, 0, 1)
	assert_bool(overlay._dots.visible).is_false()
	assert_str(overlay._count.text).is_equal("3")
	_progress("centre", 0.7, 0, 1)
	assert_str(overlay._count.text).is_equal("1")
	assert_bool(overlay._count.has_meta(&"_ui_pop")).is_true()  # each new digit slams in


func test_a_finished_step_gets_its_tick() -> void:
	_progress("right", 1.0, 2, 3)
	assert_bool(overlay.figure().done).is_true()
	assert_bool(overlay._dots.current_done).is_true()
	assert_str(overlay._retry.text).is_equal("Got it!")
	_progress("centre", 1.0, 0, 3, 3, "used_default")
	assert_bool(overlay.figure().done).is_false()  # a fallback isn't a success
	assert_str(overlay._retry.text).is_equal(CalibrationOverlay.RETRY_REASONS.used_default)


func test_tap_to_calibrate_is_tidy_and_asks_on_a_tap() -> void:
	overlay._show("needs")
	await _settle()
	assert_bool(overlay._tap_pill.visible).is_true()
	assert_float(overlay._tap_pill.size.y).is_greater_equal(HudTheme.BUTTON_HEIGHT)
	_assert_tidy("needs")
	_tap(Vector2(300, 200))  # anywhere on the screen
	assert_int(requests).is_equal(1)


func test_a_tap_during_a_calibration_is_taken_but_ignored() -> void:
	_progress("left", 0.3, 1, 3)
	await _settle()
	_tap(SCREEN.get_center())
	_tap(Vector2(40, 40))
	assert_int(requests).is_equal(0)
	assert_bool(overlay._full.visible).is_true()


func test_the_strips_say_what_to_do_and_take_a_tap() -> void:
	for strip_mode in ["lost", "unavailable"]:
		overlay._show(strip_mode)
		await _settle()
		assert_bool(overlay.strip().visible).is_true()
		assert_bool(overlay._full.visible).is_false()
		assert_str(overlay._strip_text.text).is_equal(CalibrationOverlay.STRIP_TEXTS[strip_mode][0])
		assert_str(overlay._strip_action.text).contains("TAP")
		assert_bool(overlay._strip_icon.crossed).is_equal(strip_mode == "unavailable")
		var r := overlay.strip().get_global_rect()
		assert_bool(SCREEN.encloses(r)).is_true()
		assert_float(r.size.y).is_greater_equal(CalibrationOverlay.STRIP_HEIGHT)
		_tap(r.get_center())
	assert_int(requests).is_equal(2)


func test_the_look_follows_the_game_and_falls_back_to_the_house() -> void:
	assert_object(overlay.theme).is_same(GameTheme.house())
	var look := GameTheme.new(Color("38b6ff"), Color("0e1b3d"), 0.18, true)
	overlay.apply_theme(look)
	assert_object(overlay.theme).is_same(look)
	var card := overlay._card.get_theme_stylebox("panel") as StyleBoxFlat
	assert_that(card.border_color).is_equal(look.card_style().border_color)
	assert_that(overlay.figure().accent).is_equal(look.accent)
	assert_object(overlay._prompt.get_theme_font("font")).is_same(look.font(true))
	overlay.apply_theme(null)
	assert_object(overlay.theme).is_same(GameTheme.house())


var _restyles := 0


## Review of PR #58: _update_progress runs every frame of a calibration and set the hint's colour
## override each time; an unchanged colour must not re-shape the label.
func test_progress_frames_dont_restyle_the_hint() -> void:
	_progress("centre", 0.1, 0, 1)
	_restyles = 0
	overlay._retry.theme_changed.connect(func(): _restyles += 1)
	for i in 20:
		_progress("centre", 0.1 + i * 0.01, 0, 1)
	assert_int(_restyles).is_equal(0)


func test_a_stand_game_never_talks_about_steering() -> void:
	assert_str(CalibrationOverlay.strip_text("unavailable", "lean_stand")).contains("stand")
	assert_str(CalibrationOverlay.strip_text("unavailable", "lean_stand")).not_contains("steering")
	assert_str(CalibrationOverlay.strip_text("unavailable", "lean_x")).contains("steering")
	assert_str(CalibrationOverlay.strip_text("lost", "lean_stand")).not_contains("steering")
