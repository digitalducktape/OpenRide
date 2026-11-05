extends GdUnitTestSuite
## The hub's bike-first rules (spec §8.2) on every screen at 1920x1080, with the longest
## strings: every touch target at least 120 px on its shorter side (cards 180), at least 24 px
## between targets, no text under 34 px (baked text included), everything on screen, and Exit
## games and Start never on one screen. Also: the hub's bakes stop rendering once settled (no
## viewport renders on an idle frame).

const LONG_NAME := "Bartholomew Montgomery-Smythe"

var local: Node
var hub: Node


func before() -> void:
	HubPrefs.path = "user://hub_prefs_layout_test.cfg"
	HubPrefs.reload()


func after() -> void:
	HubPrefs.path = HubPrefs.DEFAULT_PATH
	HubPrefs.reload()


func before_test() -> void:
	local = Session._local
	local.process_mode = Node.PROCESS_MODE_DISABLED
	local.hub.rider.name = LONG_NAME
	local.hub.rider.ftp_is_default = true
	local.hub.settings.camera_games = true
	Session.director.phase = SessionDirector.Phase.IDLE
	local.hub.begin_visit()
	hub = get_tree().current_scene
	await _settle()


func after_test() -> void:
	Session._on_now_playing({})
	local.hub.rider.name = local.hub.RIDER_NAME
	local.hub.phase = ""
	Session.visit_id = ""
	Session.hub = {}
	Session.director.phase = SessionDirector.Phase.IDLE
	local.process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 0


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout
	await get_tree().process_frame


func _settle(frames := 12) -> void:
	for i in frames:
		await get_tree().process_frame


func test_the_hub_is_the_current_scene() -> void:
	assert_str(hub.scene_file_path).is_equal(SessionDirector.IDLE_SCENE)
	assert_object(hub.screen).is_instanceof(HomeScreen)


func test_home() -> void:
	_check_screen("home")
	var home: HomeScreen = hub.screen
	for card in home.game_cards.values() + home.circuit_cards.values():
		var r: Rect2 = card.target_rect()
		assert_float(minf(r.size.x, r.size.y)).override_failure_message("a card under 180 px").is_greater_equal(HubTheme.CARD_TARGET)


func test_home_with_the_riders_music() -> void:
	Session._on_now_playing({"title": "Nothin' on You (feat. Bruno Mars) - Extended Version", "artist": "B.o.B, Bruno Mars",
		"art": "", "playing": true, "can_previous": true, "can_next": false})
	await _settle()
	var home: HomeScreen = hub.screen
	assert_bool(home.header.music_button.visible).is_true()
	_check_screen("home with the rider's music")
	# The music panel over the hub: its targets keep the hub's sizes and gaps, and its text fits.
	home.header.music_button.pressed.emit()
	await _settle()
	var panel: MusicPanel = Session.director.music_panel
	assert_bool(panel.is_open()).is_true()
	_check_targets("the music panel", panel.targets())
	_check_text("the music panel", panel.card)
	assert_float(panel.card.get_combined_minimum_size().y).override_failure_message("the panel's content outgrows its card") \
		.is_less_equal(MusicPanel.CARD_SIZE.y + 0.5)
	panel.close()
	Session._on_now_playing({})
	await _settle()
	assert_bool(home.header.music_button.visible).is_false()
	_check_screen("home after the music")


func test_home_with_bests_and_without_the_camera() -> void:
	local.hub.rider.ftp_is_default = false
	local.hub.settings.camera_games = false
	local.hub.plan_bests = {"circuit-20|standard": {"score": 123456, "stars": 30}}
	local.hub.send_state()
	await _settle()
	_check_screen("home without camera")
	local.hub.plan_bests = {}
	local.hub.settings.camera_games = true


func test_every_game_screen() -> void:
	for e in HubState.games(hub.state):
		hub.nav.push(HubNav.GAME, {"game_id": e.id})
		await _settle()
		_check_screen("game " + str(e.id))
		for mode in hub.screen.length_picker.modes.choices:
			hub.screen.length_picker.modes.pick(mode)
			await _wait(0.4)  # the pick's pop (a scale) settles
			_check_screen("game %s %s" % [e.id, mode])
		if hub.screen.more_button:  # "More options" over the left column
			hub.screen.open_more()
			await _wait(0.4)
			_check_screen("game %s more options" % e.id)
			hub.screen.close_more()
		hub.nav.pop()
		await _settle(2)


func test_every_circuit_screen() -> void:
	for c in hub.state.circuits:
		hub.nav.push(HubNav.CIRCUIT, {"circuit_id": c.id})
		await _settle()
		_check_screen("circuit " + str(c.id))
		hub.nav.pop()
		await _settle(2)


func test_the_builder_with_twelve_slots_scrolls() -> void:
	hub.nav.push(HubNav.BUILDER, {"index": -1})
	await _settle()
	_check_screen("builder empty")
	var s: BuilderScreen = hub.screen
	for i in 12:
		s.add_game(["cadence_karaoke", "dodge_ball", "tug_of_war", "safe_cracker"][i % 4])
	await _wait(0.4)
	assert_int(s.rows.size()).is_equal(12)
	assert_float(s.scroll.get_v_scroll_bar().max_value).is_greater(s.scroll.size.y)  # it scrolls
	_check_screen("builder 12 slots, scrolled to the end")
	s.scroll.scroll_vertical = 0
	await _settle(3)
	_check_screen("builder 12 slots, top")
	var visible_rows := 0
	for r in s.rows:
		if s.scroll.get_global_rect().encloses(r.remove.get_global_rect()):
			visible_rows += 1
	# More than six games wrap the tiles to a second row (#75), which leaves the list two full rows.
	assert_int(visible_rows).is_greater_equal(2)
	for i in 3:
		HubPrefs.save_custom(HubPrefs.rider(hub.state), i, s.builder.to_saved())
	s.builder.set_length(0, 120)
	s.save()  # all three places taken: which to replace
	await _wait(0.4)
	assert_object(s.replace_panel).is_not_null()
	_check_screen("builder replace")
	s.close_replace()
	HubPrefs.forget_rider(HubPrefs.rider(hub.state))


## Stand-ins for the wave 2 games not registered yet, with their roles (#75): the full 12 with the
## real ones. A real one is skipped.
const FAKE_GAMES := {"power_grid": ["warmup", "work", "cooldown"], "gate_crasher": ["work"], "ready_for_launch": ["work"]}


## How many games _send_eleven_games sent: the registry's real games plus the fakes not yet real
## (12 when the wave 2 games are all registered).
var _game_total := 0


## A hub_state with eleven games, its circuits drawn from all of them.
func _send_eleven_games() -> void:
	HubState.test_ids = FAKE_GAMES.keys()
	var s: Dictionary = local.hub.state()
	var real: Array = s.catalog.map(func(g): return g.id)
	for id in FAKE_GAMES:
		if id in real:
			continue
		var e: Dictionary = s.catalog[1].duplicate(true)
		e.id = id
		e.title = id.capitalize()
		e.roles = FAKE_GAMES[id]
		e.uses_camera = id == "gate_crasher"
		e.circuit_role = local.hub.circuit_role(e.roles)
		s.catalog.append(e)
	_game_total = s.catalog.size()
	for c in s.circuits:
		var shape: Array = c.slots.map(func(slot): return {"role": slot.role, "duration_sec": slot.duration_sec})
		c.slots = local.hub.draw_slots(shape, s.catalog, true, 7)
	Session._on_hub_state(JSON.parse_string(JSON.stringify(s)))
	await _settle()


func test_circuit_screens_with_eleven_games() -> void:
	await _send_eleven_games()
	for c in hub.state.circuits:
		hub.nav.push(HubNav.CIRCUIT, {"circuit_id": c.id})
		await _settle()
		_check_screen("circuit %s, 11 games" % c.id)
		hub.nav.pop()
		await _settle(2)
	HubState.test_ids = []


func test_home_pages_through_eleven_games() -> void:
	await _send_eleven_games()
	var home: HomeScreen = hub.screen
	assert_int(home.game_cards.size()).is_equal(_game_total)
	assert_int(home.page_count()).is_equal(ceili(_game_total / 4.0))
	assert_object(home.page_left).is_not_null()
	var seen := {}
	for page in home.page_count():
		home.show_page(page)
		await _settle(3)
		_check_screen("home, 11 games, page %d" % page)
		assert_bool(home.page_left.disabled).is_equal(page == 0)
		assert_bool(home.page_right.disabled).is_equal(page == home.page_count() - 1)
		for id in home.game_cards:
			var card: HubCard = home.game_cards[id]
			if card.is_visible_in_tree():
				seen[id] = true
				assert_float(minf(card.target_rect().size.x, card.target_rect().size.y)).is_greater_equal(HubTheme.CARD_TARGET)
	assert_int(seen.size()).override_failure_message("every game shows on some page").is_equal(_game_total)
	# The right button turns the page.
	home.show_page(0)
	home.page_right.pressed.emit()
	assert_int(home.game_page).is_equal(1)
	HubState.test_ids = []


func test_the_builder_tiles_wrap_eleven_games() -> void:
	await _send_eleven_games()
	hub.nav.push(HubNav.BUILDER, {"index": -1})
	await _settle()
	var s: BuilderScreen = hub.screen
	assert_int(s.tiles.grid.columns).is_equal(BuilderScreen.TILE_COLUMNS_MAX)
	_check_screen("builder, 11 games")
	assert_float(s.scroll.size.y).override_failure_message("room for the slot list").is_greater_equal(2 * HubTheme.TARGET)
	HubState.test_ids = []


func test_my_circuits() -> void:
	var rider := HubPrefs.rider(hub.state)
	HubPrefs.save_custom(rider, 1, CircuitBuilder.new(hub.state.catalog, [{"game_id": "cadence_karaoke", "duration_sec": 180},
		{"game_id": "kart_race", "duration_sec": 600}, {"game_id": "dodge_ball", "duration_sec": 90}]).to_saved())
	hub.nav.push(HubNav.MY_CIRCUITS)
	await _settle()
	_check_screen("my circuits")
	HubPrefs.forget_rider(rider)


func test_settings() -> void:
	hub.nav.push(HubNav.SETTINGS)
	await _settle()
	_check_screen("settings")


func test_the_exit_dialog() -> void:
	hub.ask_exit()
	await _wait(0.5)  # the card's slam settles
	var d: ConfirmDialog = hub.dialog
	_check_targets("exit dialog", [d.keep_button, d.act_button])
	assert_str(d.act_button.text).is_equal("Exit")
	assert_bool(d.act_button.get_global_rect().position.x > d.keep_button.get_global_rect().end.x + 120).is_true()  # UI_STYLE §6: 120 px from the safe button
	d.close()


func test_back_steps_back_then_asks_to_exit() -> void:
	hub.nav.push(HubNav.SETTINGS)
	await _settle(2)
	Session.back()
	assert_str(hub.nav.top_id()).is_equal(HubNav.HOME)
	Session.back()
	assert_bool(hub.dialog.visible).is_true()
	Session.back()  # back closes the dialog: never exits by itself
	assert_bool(hub.dialog.visible).is_false()
	assert_array(local.hub_calls.filter(func(c): return c[0] == "exit_hub")).is_empty()


func test_bakes_go_quiet_when_settled() -> void:
	await _settle(30)
	# Only what shows: with six games the home row pages (#75), and a hidden page's cards bake
	# when it is shown.
	var bakes := _bakes(hub).filter(func(b): return b.is_visible_in_tree())
	assert_int(bakes.size()).is_greater(8)
	var before := _renders(bakes)
	await _settle(20)
	assert_int(_renders(bakes)).override_failure_message("a bake rendered on an idle frame").is_equal(before)
	for b in bakes:
		# A bake on a hidden page (more than five games page on home, #75) waits until it shows.
		if b.is_visible_in_tree():
			assert_bool(b.is_pending()).is_false()


func test_the_frame_cap_in_the_hub() -> void:
	assert_int(Engine.max_fps).is_equal(SessionDirector.HUB_MAX_FPS)


# --- Checks ---

func _check_screen(what: String) -> void:
	var screen: HubScreen = hub.screen
	var targets: Array = screen.targets()
	assert_bool(targets.is_empty()).is_false()
	_check_targets(what, targets)
	var names := targets.map(func(t): return str(t.name))
	assert_bool("Exit" in names and "Start" in names).override_failure_message("%s: Exit and Start on one screen" % what).is_false()
	_check_text(what, screen)
	for row in screen.find_children("*", "Control", true, false).filter(func(n): return n is OptionRow and n.is_visible_in_tree()):
		var r: Rect2 = (row as Control).get_global_rect()
		var parent_r: Rect2 = (row.get_parent() as Control).get_global_rect()
		assert_float(r.end.x).override_failure_message("%s: %s is %.0f px wide, past its column" % [what, row.name, r.size.x]) \
			.is_less_equal(parent_r.end.x + 0.5)
	for card in screen.find_children("*", "Control", true, false).filter(func(n): return n is HubCard):
		var c: HubCard = card
		assert_bool(c.content.size.x <= c.size.x + 0.5 and c.content.size.y <= c.size.y + 0.5) \
			.override_failure_message("%s: %s's content %s overflows its bake %s" % [what, c.name, c.content.size, c.size]).is_true()


func _check_targets(what: String, targets: Array) -> void:
	var screen_rect := Rect2(0, 0, HubTheme.W, HubTheme.H)
	var rects: Array[Rect2] = []
	for t in targets:
		var r: Rect2 = (t as Control).get_global_rect()
		assert_float(minf(r.size.x, r.size.y)).override_failure_message("%s: %s is %s, under 120 px" % [what, t.name, r.size]).is_greater_equal(HubTheme.TARGET)
		assert_bool(screen_rect.encloses(r)).override_failure_message("%s: %s %s is off screen" % [what, t.name, r]).is_true()
		rects.append(r)
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			var gap := _gap(rects[i], rects[j])
			assert_float(gap).override_failure_message("%s: %s and %s are %.0f px apart" % [what, targets[i].name, targets[j].name, gap]).is_greater_equal(HubTheme.GAP)


## The space between two rects (negative when they overlap).
static func _gap(a: Rect2, b: Rect2) -> float:
	return maxf(maxf(b.position.x - a.end.x, a.position.x - b.end.x), maxf(b.position.y - a.end.y, a.position.y - b.end.y))


## Every label and button, baked ones too, at 34 px or more, and inside the screen.
func _check_text(what: String, root: Node) -> void:
	for n in root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree():
			continue
		if c is Label and not (c as Label).text.is_empty():
			var fs := c.get_theme_font_size("font_size")
			assert_int(fs).override_failure_message("%s: '%s' at %d px" % [what, (c as Label).text, fs]).is_greater_equal(HudTheme.SMALL)
		elif c is Button and not (c as Button).text.is_empty():
			var bs := c.get_theme_font_size("font_size")
			assert_int(bs).override_failure_message("%s: button '%s' at %d px" % [what, (c as Button).text, bs]).is_greater_equal(HudTheme.SMALL)


func _bakes(root: Node) -> Array:
	return root.find_children("*", "TextureRect", true, false).filter(func(n): return n is BakedView)


func _renders(bakes: Array) -> int:
	var total := 0
	for b in bakes:
		total += (b as BakedView).renders
	return total


## The bike's window (#57: about 2057x1080 of canvas): the backdrop fills it and the home screen
## sits in the middle, every target still on the 1920x1080 stage.
func test_on_the_bike_window_the_backdrop_fills_it_and_home_is_centred() -> void:
	var bike := Vector2(2057, 1080)
	Stage.fit(bike)
	await _settle(2)
	var on_window := func(c: Control) -> Rect2: return c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, c.size)
	var backdrop: Control = hub.get_node("Backdrop")
	assert_object(on_window.call(backdrop)).is_equal(Rect2(Vector2.ZERO, bike))
	var stage := Rect2(Stage.pad, Vector2(HubTheme.W, HubTheme.H))
	var targets: Array = hub.screen.find_children("*", "Control", true, false).filter(func(n): return (n is BaseButton or n is HubCard) and n.is_visible_in_tree())
	assert_bool(targets.is_empty()).is_false()
	var bounds: Rect2 = on_window.call(targets[0])
	for t in targets:
		var r: Rect2 = on_window.call(t)
		assert_bool(stage.encloses(r)).override_failure_message("%s %s is off the stage %s" % [t.name, r, stage]).is_true()
		bounds = bounds.merge(r)
	Stage.fit(Vector2(HubTheme.W, HubTheme.H))
	assert_float(bounds.get_center().x).is_equal_approx(bike.x / 2.0, 2.0)
