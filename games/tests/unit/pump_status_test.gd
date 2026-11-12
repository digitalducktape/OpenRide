extends GdUnitTestSuite
## Balloon Pump's status widget (`PumpStatus`) in the HUD's top-centre slot, with the longest
## texts it shows and a five-digit score: no two HUD leaves overlap, the widget stays within
## 800 x 120 (the style guide's budget is 850 x 120), every text is at least 34 px, the badge's
## word follows the state, and nothing redraws every frame.

const SCREEN := Rect2(0, 0, 1920, 1080)
const MAX_SIZE := Vector2(800, 120)

var hud: Hud
var status: PumpStatus
var look := GameTheme.new(Color("ff5fa2"), Color("2b0f2a"), 0.1)


func before_test() -> void:
	hud = auto_free(Hud.new())
	add_child(hud)
	var info := GameInfo.new()
	info.title = "Balloon Pump"
	info.id = "balloon_pump"
	info.tracker_mode = "off"
	hud.setup(info, {"role": "work", "index": 3, "count": 9})
	hud.set_skin(look.hud_skin())
	status = PumpStatus.new(look)
	hud.add_widget(status)
	hud.metrics.refresh(118, 1888, 100)
	hud.score.set_value("99999")
	Effort.begin_segment(true)


func after_test() -> void:
	hud.clear_skin()


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


func _assert_layout(state: String) -> void:
	await _settle()
	await get_tree().create_timer(GameTheme.POP_SEC + 0.05).timeout
	var leaves: Array[Control] = []
	_leaves(hud, leaves)
	for i in leaves.size():
		var a := leaves[i].get_global_rect().grow(-0.5)
		assert_bool(SCREEN.encloses(a)).override_failure_message("%s: %s %s is off screen" % [
			state, leaves[i].name, a]).is_true()
		for j in range(i + 1, leaves.size()):
			var b := leaves[j].get_global_rect().grow(-0.5)
			assert_bool(a.intersects(b)).override_failure_message("%s: %s %s overlaps %s %s" % [
				state, leaves[i].name, a, leaves[j].name, b]).is_false()
	assert_float(status.size.x).override_failure_message("%s: %d px wide" % [state, status.size.x]).is_less_equal(MAX_SIZE.x)
	assert_float(status.size.y).override_failure_message("%s: %d px tall" % [state, status.size.y]).is_less_equal(MAX_SIZE.y)
	var labels: Array[Control] = []
	_leaves(status, labels)
	for c in labels:
		if c is Label:
			assert_int(c.get_theme_font_size("font_size")).is_greater_equal(HudTheme.SMALL)


func test_race_with_the_longest_texts() -> void:
	status.set_state(1.0, 0.7, "filling")
	status.set_count(999)
	status.set_race(10, 10, 119.0)
	status.set_next("large")
	await _assert_layout("race")
	assert_str(status.race_label.text).is_equal("10/10 · HEAT 1:59")
	assert_str(status.badge_label.text).is_equal("FILLING")


func test_max_hides_the_race_and_every_badge_fits() -> void:
	status.set_count(1)
	status.set_race(0, 0, -1.0)
	assert_str(status.race_label.text).is_equal("")
	assert_str(status.count_label.text).is_equal("×1")
	for state in ["filling", "push", "full", "pedal", "rest"]:
		status.set_state(0.4, 0.7, state)
		await _assert_layout(state)
	assert_str(status.badge_label.text).is_equal("REST")


func test_push_breathes_and_stops() -> void:
	status.set_state(0.3, 0.6, "push")
	await _settle()
	assert_str(status.badge_label.text).is_equal("PUSH!")
	assert_bool(status.badge.has_meta(&"_ui_pulse")).is_true()
	status.set_state(0.8, 0.6, "filling")
	await _settle()
	assert_bool(status.badge.has_meta(&"_ui_pulse")).is_false()


func test_the_race_clock_turns_amber_in_its_last_seconds() -> void:
	status.set_race(2, 5, 30.0)
	assert_object(status.race_label.get_theme_color("font_color")).is_equal(GameTheme.TARGET)
	status.set_race(3, 5, 9.2)
	assert_str(status.race_label.text).is_equal("3/5 · HEAT 0:10")
	assert_object(status.race_label.get_theme_color("font_color")).is_equal(GameTheme.WARN)


func test_the_widget_shows_no_watts_of_its_own() -> void:
	# One watts reading on screen: the ride panel's (reviewer, 2026-11-02).
	var texts: Array = status.find_children("*", "Label", true, false).map(func(l): return l.text)
	for t in texts:
		assert_bool(str(t).ends_with("W")).is_false()


func test_full_reads_as_full_not_a_tied_score() -> void:
	status.set_state(0.9, 0.7, "full")
	assert_str(status.badge_label.text).is_equal("FULL!")


func test_row_two_is_readable_from_the_saddle() -> void:
	for l: Label in [status.count_label, status.race_label, status.next_caption]:
		assert_int(l.get_theme_font_size("font_size")).is_greater_equal(40)
	assert_float(status.next_icon.custom_minimum_size.y).is_greater_equal(56.0)


func test_no_per_frame_code() -> void:
	var methods: Array = status.get_script().get_script_method_list().map(func(m): return m.name)
	assert_bool(methods.has("_process")).is_false()
