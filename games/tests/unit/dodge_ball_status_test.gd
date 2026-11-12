extends GdUnitTestSuite
## Dodge Ball's status widget in its themed HUD (games/dodge_ball/UI_POLISH.md): with the
## longest texts it fits the top-centre budget (framework/ui/UI_STYLE.md: 850 x 120), its parts
## don't overlap, it keeps the road clear, nothing in it moves when the caption or the power
## bonus changes, the empty shield breathes without a redraw every frame, and no text is under
## 34 px.

const Layout := preload("res://tests/unit/hud_layout_test.gd")
const BUDGET := Vector2(850, 120)

var hud: Hud
var status: DodgeStatus


func before_test() -> void:
	hud = auto_free(Hud.new())
	add_child(hud)
	var info := GameInfo.new()
	info.title = "Dodge Ball"
	info.id = "dodge_ball"
	info.tracker_mode = "lean_x"
	hud.setup(info, {"role": "free"})
	hud.set_skin(DodgeStatus.look.hud_skin())
	status = DodgeStatus.new(85.0, true, false)
	hud.add_widget(status)
	hud.metrics.set_cadence_band(85.0)
	hud.metrics.set_power_band(210.0)
	hud.metrics.refresh(118, 1888, 100)
	hud.score.set_value("99999")


func _settle(frames := 4) -> void:
	for i in frames:
		await get_tree().process_frame


func _worst_case() -> void:
	status.set_state(0.0, true, true, 188, 3, 12)
	await _settle()
	# Let the slam and the pulse settle onto their resting scale for the geometry checks.
	GameTheme.pulse(status._caption_box, false)
	status.bonus_badge.scale = Vector2.ONE
	status.bonus_badge.modulate.a = 1.0
	await _settle(2)


func _leaves(root: Node, out: Array[Control]) -> void:
	for child in root.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is Control:
			var c := child as Control
			if c is Label and not (c as Label).text.is_empty() or (c.get_child_count() == 0 and c.size.x > 0.0):
				out.append(c)
				continue
		_leaves(child, out)


func _positions() -> Array:
	var out := []
	for c: Control in [status._mode, status._caption_box, status.bar, status.streak_label, status.lives_box,
			status._wave, status._bonus_slot]:
		# Layout positions: a pulse or a pop scales about the centre, which is visual only.
		out.append(Rect2((c.get_parent() as Control).get_global_rect().position + c.position, c.size))
	return out


func test_fits_the_budget_and_does_not_overlap() -> void:
	await _worst_case()
	assert_float(status.size.x).override_failure_message("width %.0f" % status.size.x).is_less_equal(BUDGET.x)
	assert_float(status.size.y).override_failure_message("height %.0f" % status.size.y).is_less_equal(BUDGET.y)
	var leaves: Array[Control] = []
	_leaves(status, leaves)
	assert_int(leaves.size()).is_greater_equal(7)
	for i in leaves.size():
		for j in range(i + 1, leaves.size()):
			var a := leaves[i].get_global_rect().grow(-0.5)
			var b := leaves[j].get_global_rect().grow(-0.5)
			if a.encloses(b) or b.encloses(a):
				continue  # a badge's label inside its slot
			assert_bool(a.intersects(b)).override_failure_message("%s %s overlaps %s %s" % [
				leaves[i].name, a, leaves[j].name, b]).is_false()


func test_keeps_the_road_clear_with_the_shield_empty_and_the_bonus_on() -> void:
	await _worst_case()
	var rect := status.get_global_rect().grow(Layout.KEEP_CLEAR_MARGIN)
	var y := rect.position.y
	while y <= rect.end.y:
		var x := rect.position.x
		while x <= rect.end.x:
			var p := Vector2(x, y)
			assert_bool(Layout.on_road(p, DodgeWorld.FOV_SLOW) or Layout.on_road(p, DodgeWorld.FOV_FAST)) \
				.override_failure_message("the status %s covers the road at %s" % [status.get_global_rect(), p]).is_false()
			x += Layout.SAMPLE_STEP
		y += Layout.SAMPLE_STEP


func test_nothing_moves_when_the_caption_or_the_bonus_changes() -> void:
	status.set_state(1.0, false, false, 5, 3, 2)
	await _settle()
	var before := _positions()
	var width := status.size.x
	status.set_state(0.6, true, true, 5, 3, 2)  # PEDAL UP!, ×2 POINTS
	await _settle()
	status.set_state(0.0, true, true, 5, 3, 2)  # empty
	await _settle()
	status.set_state(0.5, false, false, 5, 3, 2)  # NO SHIELD, recharging, bonus gone
	await await_millis(400)
	assert_float(status.size.x).is_equal_approx(width, 0.5)
	var after := _positions()
	for i in before.size():
		assert_vector((after[i] as Rect2).position).is_equal_approx((before[i] as Rect2).position, Vector2(0.5, 0.5))


func test_the_caption_says_what_to_do() -> void:
	status.set_state(1.0, false, false, 0, 3, 1)
	assert_str(status._caption.text).is_equal("SHIELD")
	status.set_state(0.5, true, false, 0, 3, 1)
	assert_str(status._caption.text).is_equal("PEDAL UP!")
	assert_bool(status.empty).is_false()
	status.set_state(0.0, true, false, 0, 3, 1)
	assert_bool(status.empty).is_true()
	assert_str(status._caption.text).is_equal("PEDAL UP!")
	status.set_state(0.4, false, false, 0, 3, 1)
	assert_str(status._caption.text).is_equal("NO SHIELD")
	status.set_state(1.0, false, false, 0, 3, 1)  # shield_ready
	assert_bool(status.empty).is_false()
	assert_str(status._caption.text).is_equal("SHIELD")


func test_the_bonus_badge_shows_only_while_the_bonus_is_on() -> void:
	status.set_state(1.0, false, false, 0, 3, 1)
	assert_bool(status.bonus_badge.visible).is_false()
	status.set_state(1.0, false, true, 0, 3, 1)
	assert_bool(status.bonus_badge.visible).is_true()
	status.set_state(1.0, false, false, 0, 3, 1)
	await await_millis(400)
	assert_bool(status.bonus_badge.visible).is_false()


func test_an_empty_shield_does_not_redraw_every_frame() -> void:
	status.set_state(0.0, true, false, 0, 3, 1)
	await _settle()
	var draws := status.draws + status.bar.draws
	for i in 20:
		status.set_state(0.0, true, false, 0, 3, 1)
		await get_tree().process_frame
	assert_int(status.draws + status.bar.draws - draws).is_less_equal(1)


func test_no_text_under_34_px() -> void:
	await _worst_case()
	for node in status.find_children("*", "Label", true, false):
		var l := node as Label
		assert_int(l.get_theme_font_size("font_size")).is_greater_equal(HudTheme.SMALL)
		var face := l.get_theme_font("font") as FontVariation
		assert_object(face).is_not_null()
		assert_str(face.base_font.resource_path).is_equal(GameTheme.FONT_PATH)  # one face, one glyph atlas
		assert_int(l.get_theme_constant("outline_size")).is_greater_equal(6)
