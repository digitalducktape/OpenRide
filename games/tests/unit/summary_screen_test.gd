extends GdUnitTestSuite
## The session summary (#35, #37): a circuit ended early lists every planned game, the heading
## says whether it finished, and the best line says what the rider is up against.

const PLAN := {"kind": "circuit", "segments": [
	{"game_id": "cadence_karaoke", "role": "warmup", "duration_sec": 180},
	{"game_id": "tug_of_war", "role": "work", "duration_sec": 60},
	{"game_id": "safe_cracker", "role": "recovery", "duration_sec": 90},
]}


func _summary(results: Array, bests := {}) -> Dictionary:
	return {"results": results, "totals": {"score": 130, "stars": 1, "elapsed_sec": 51}, "bests": bests}


func test_a_circuit_ended_early_lists_every_planned_game() -> void:
	var screen: SummaryScreen = auto_free(SummaryScreen.new())
	add_child(screen)
	screen.show_summary(_summary([{"game_id": "cadence_karaoke", "score": 130, "stars": 1, "skipped": false}]), PLAN)
	assert_int(screen._rows.get_child_count()).is_equal(3)
	assert_str(screen._title.text).is_equal("Session ended early")
	# The last two say they weren't played.
	var pending := 0
	for row in screen._rows.get_children():
		for label in row.find_children("*", "Label", true, false):
			if (label as Label).text == "not played":
				pending += 1
	assert_int(pending).is_equal(2)


func test_a_finished_circuit_says_complete_with_a_row_each() -> void:
	var screen: SummaryScreen = auto_free(SummaryScreen.new())
	add_child(screen)
	var results := []
	for seg in PLAN.segments:
		results.append({"game_id": seg.game_id, "score": 100, "stars": 1, "skipped": false})
	screen.show_summary(_summary(results), PLAN)
	assert_int(screen._rows.get_child_count()).is_equal(3)
	assert_str(screen._title.text).is_equal("Circuit complete")


func test_a_just_ride_has_one_row_and_its_own_heading() -> void:
	var screen: SummaryScreen = auto_free(SummaryScreen.new())
	add_child(screen)
	var plan := {"kind": "just_ride", "segments": [{"game_id": "dodge_ball", "role": "free", "duration_sec": -1}]}
	screen.show_summary(_summary([{"game_id": "dodge_ball", "score": 500, "stars": 2, "skipped": false}]), plan)
	assert_int(screen._rows.get_child_count()).is_equal(1)
	assert_str(screen._title.text).is_equal("Ride complete")


func test_the_best_line_says_what_the_rider_is_up_against() -> void:
	assert_str(SummaryScreen.bests_text({})).is_equal("")
	assert_str(SummaryScreen.bests_text({"score": true})).is_equal("New personal best!")
	assert_str(SummaryScreen.bests_text({"score": true, "stars": true, "previous_score": 900, "previous_stars": 1})) \
		.is_equal("New personal best! (before: 900 points, 1 star)")
	assert_str(SummaryScreen.bests_text({"previous_score": 5400, "previous_stars": 2})).is_equal("Your best: 5400 points, 2 stars")


# --- Look and layout (framework/ui/UI_STYLE.md) ---

const SCREEN := Rect2(0, 0, 1920, 1080)
const GAMES := ["cadence_karaoke", "dodge_ball", "tug_of_war", "safe_cracker", "kart_race"]


func _shown(summary: Dictionary, plan: Dictionary, looks := {}) -> SummaryScreen:
	var screen: SummaryScreen = auto_free(SummaryScreen.new())
	add_child(screen)
	screen.show_summary(summary, plan, looks)
	return screen


## Laid out, and the entrance motion (scale and fade) has landed.
func _settle(screen: SummaryScreen = null) -> void:
	for i in 4:
		await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 3000
	while screen and not screen.is_settled() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


## The visible leaves (labels, buttons, drawn shapes) under `root`, as screen rects.
func _leaves(root: Node, out: Array[Control]) -> void:
	for child in root.get_children():
		if child is CanvasItem and not (child as CanvasItem).visible:
			continue
		if child is ScrollBar:
			continue
		if child is Control:
			var c := child as Control
			var leaf := c is Label or c is Button or (c.get_child_count() == 0 and c.size.x > 0.0 and c.size.y > 0.0)
			if c is Label and (c as Label).text.is_empty():
				leaf = false
			if leaf and c.mouse_filter != Control.MOUSE_FILTER_STOP or c is Button:
				out.append(c)
				continue
		_leaves(child, out)


func _assert_tidy(screen: SummaryScreen, what: String) -> void:
	var leaves: Array[Control] = []
	_leaves(screen._column, leaves)
	var clip := screen._scroll.get_global_rect()
	for i in leaves.size():
		var a := leaves[i].get_global_rect()
		var in_list := screen._scroll.is_ancestor_of(leaves[i])
		if not in_list:
			assert_bool(SCREEN.encloses(a)).override_failure_message("%s: %s %s is off screen" % [what, leaves[i], a]).is_true()
		for j in range(i + 1, leaves.size()):
			var b := leaves[j].get_global_rect()
			if in_list and not (a.intersects(clip) and b.intersects(clip)):
				continue
			assert_bool(a.grow(-1).intersects(b.grow(-1))).override_failure_message(
				"%s: %s %s overlaps %s %s" % [what, leaves[i], a, leaves[j], b]).is_false()


func _assert_done_button(screen: SummaryScreen) -> void:
	var done := screen.done_button.get_global_rect()
	assert_float(done.size.y).is_greater_equal(HudTheme.BUTTON_HEIGHT)
	assert_float(done.size.x).is_greater_equal(220.0)
	assert_bool(SCREEN.encloses(done)).is_true()
	assert_float(done.end.y).is_greater(SCREEN.size.y * 0.8)  # at the bottom, where a thumb rests
	assert_int(screen.done_button.focus_mode).is_equal(Control.FOCUS_NONE)


func _circuit(count: int) -> Array:
	var segments := []
	var results := []
	for i in count:
		segments.append({"game_id": GAMES[i % GAMES.size()], "role": ["warmup", "work", "recovery", "cooldown"][i % 4]})
		results.append({"game_id": GAMES[i % GAMES.size()], "score": 99999, "stars": i % 4, "skipped": i == 3})
	return [{"kind": "circuit", "segments": segments}, results]


func test_one_game_wears_its_look_and_lays_out_tidily() -> void:
	var look := GameTheme.new(Color("e8b04a"), Color("14110d"))
	var screen := _shown({"results": [{"game_id": "safe_cracker", "score": 4820, "stars": 3}],
		"totals": {"score": 4820, "stars": 3, "elapsed_sec": 1265},
		"bests": {"score": true, "previous_score": 3900, "previous_stars": 2}},
		{"kind": "just_ride", "segments": [{"game_id": "safe_cracker", "role": "free"}]}, {"safe_cracker": look})
	await _settle(screen)
	assert_str(screen.shape).is_equal("single")
	assert_object(screen.theme).is_same(look)
	assert_str(screen._chip_label.text).is_equal("SAFE CRACKER")
	assert_bool(screen._list.visible).is_false()
	assert_bool(screen._hero_stars.visible).is_true()
	assert_int(screen._hero_star_nodes.filter(func(s): return s.lit).size()).is_equal(3)
	assert_bool(screen._best.visible).is_true()
	assert_str(screen._best_head.text).is_equal("NEW PERSONAL BEST!")
	assert_str(screen._best_detail.text).is_equal("before: 3900 points, 2 stars")
	_assert_tidy(screen, "one game")
	_assert_done_button(screen)


func test_a_game_without_a_look_gets_the_house_look_and_no_stars_says_so() -> void:
	var screen := _shown({"results": [{"game_id": "kart_race", "score": 40, "stars": 0}],
		"totals": {"score": 40, "stars": 0, "elapsed_sec": 300}, "bests": {"previous_score": 5400, "previous_stars": 2}},
		{"kind": "just_ride", "segments": [{"game_id": "kart_race", "role": "free"}]})
	await _settle(screen)
	assert_object(screen.theme).is_same(GameTheme.house())
	assert_int(screen._hero_star_nodes.filter(func(s): return s.lit).size()).is_equal(0)
	assert_bool(screen._stars_note.visible).is_true()
	assert_str(screen._best_head.text).is_equal("YOUR BEST")
	assert_str(screen._best_detail.text).is_equal("5400 points, 2 stars")
	_assert_tidy(screen, "no stars")
	_assert_done_button(screen)


## The tallest one-game summary: no stars (the note shows), every stat tile the game declares and
## a best with its detail line. Done must stay on screen (it was clipped on the bike).
func test_every_game_stat_tiles_keep_done_on_screen_with_no_stars_and_a_best() -> void:
	var seen := 0
	for id in GameRegistry.ids():
		var info := GameRegistry.info(id)
		if info == null or info.summary_stats.is_empty():
			continue
		seen += 1
		var stats := {}
		for spec in info.summary_stats:
			stats[spec.key] = 888
			if spec.has("of"):
				stats[spec.of] = 888
		var screen := _shown({"results": [{"game_id": id, "score": 574, "stars": 0, "stats": stats}],
			"totals": {"score": 574, "stars": 0, "elapsed_sec": 3163},
			"bests": {"score": true, "previous_score": 3900, "previous_stars": 2}},
			{"kind": "just_ride", "segments": [{"game_id": id, "role": "free"}]})
		await _settle(screen)
		assert_bool(screen._stars_note.visible).is_true()
		assert_int(screen._tiles.get_child_count()).is_equal(2 + mini(info.summary_stats.size(), 3))
		_assert_tidy(screen, "%s, no stars" % id)
		_assert_done_button(screen)
		screen.free()
	assert_int(seen).is_greater_equal(4)  # Watt Lane, Balloon Pump, Keepy Uppy, The Pull


func test_a_circuit_tints_each_row_by_its_game() -> void:
	var dodge := GameTheme.new(Color("38b6ff"), Color("0e1b3d"))
	var parts := _circuit(3)
	var screen := _shown({"results": parts[1], "totals": {"score": 3000, "stars": 3, "elapsed_sec": 900}, "bests": {}},
		parts[0], {"dodge_ball": dodge})
	await _settle(screen)
	assert_str(screen.shape).is_equal("circuit")
	assert_object(screen.theme).is_same(GameTheme.house())  # a circuit spans games
	var edges := screen._rows.get_children().map(func(r): return (r.get_theme_stylebox("panel") as StyleBoxFlat).border_color)
	assert_that(Color(edges[1], 1.0)).is_equal(Color(dodge.accent, 1.0))
	assert_that(Color(edges[0], 1.0)).is_equal(Color(GameTheme.house().accent, 1.0))  # no look: the house accent
	assert_bool(screen._best.visible).is_false()
	_assert_tidy(screen, "circuit")
	_assert_done_button(screen)


func test_many_rows_with_long_names_fit_or_scroll() -> void:
	var parts := _circuit(12)
	parts[0].segments[0].game_id = "a_game_with_a_very_long_name_that_would_never_fit_on_one_card_row"
	parts[1][0].game_id = parts[0].segments[0].game_id
	var screen := _shown({"results": parts[1], "totals": {"score": 999999, "stars": 36, "elapsed_sec": 9999},
		"bests": {"score": true, "stars": true, "previous_score": 999999, "previous_stars": 35}}, parts[0])
	await _settle(screen)
	assert_int(screen._rows.get_child_count()).is_equal(12)
	var list := screen._scroll.get_global_rect()
	assert_float(screen._rows.size.y).is_greater(list.size.y)  # they don't all fit, so…
	assert_bool(screen._scroll.get_v_scroll_bar().visible).is_true()  # …the list scrolls
	for row in screen._rows.get_children():
		var r := (row as Control).get_global_rect()
		assert_float(r.position.x).is_greater_equal(list.position.x - 0.5)
		assert_float(r.end.x).is_less_equal(list.end.x + 0.5)  # long names give way, rows never widen
	_assert_tidy(screen, "long circuit")
	_assert_done_button(screen)


func test_the_backdrop_is_opaque_and_takes_every_touch() -> void:
	var screen := _shown(_summary([]), PLAN)
	await _settle()
	assert_bool(screen._backdrop.get_global_rect().encloses(SCREEN)).is_true()
	for c in screen._gradient.colors:
		assert_float(c.a).is_equal(1.0)  # the idle scene never shows through
	assert_int(screen._backdrop.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_the_entrance_lands_and_a_second_summary_starts_clean() -> void:
	var parts := _circuit(4)
	var screen := _shown({"results": parts[1], "totals": {"score": 10, "stars": 1, "elapsed_sec": 60},
		"bests": {"score": true}}, parts[0])
	assert_float(screen._best.modulate.a).is_equal(0.0)  # waits for its turn
	await get_tree().create_timer(1.8).timeout
	assert_bool(screen.is_settled()).is_true()
	for c in [screen._title, screen._best] + screen._rows.get_children() + screen._tiles.get_children():
		assert_float((c as Control).modulate.a).is_equal_approx(1.0, 0.01)
		assert_that((c as Control).scale).is_equal(Vector2.ONE)
	screen.show_summary(_summary([{"game_id": "dodge_ball", "score": 5, "stars": 1}]),
		{"kind": "just_ride", "segments": [{"game_id": "dodge_ball", "role": "free"}]})
	assert_int(screen._rows.get_child_count()).is_equal(1)
	assert_int(screen._tiles.get_child_count()).is_equal(2)
	assert_bool(screen.done_button.visible).is_true()  # Done works from the first frame
