extends GdUnitTestSuite
## The circuit builder (plan phase D, spec §8.3): CircuitBuilder's rules (lengths, caps, roles,
## the request and plan id, as Kotlin's SessionPlans.custom), HubPrefs' saved circuits, and the
## builder and My circuits screens in the hub (save, replace, delete, leave, start).

const RIDER := "builder-test"

var local: Node
var hub: Node
var catalog: Array


func before() -> void:
	HubPrefs.path = "user://hub_prefs_builder_test.cfg"
	HubPrefs.reload()


func after() -> void:
	HubPrefs.forget_rider(RIDER)
	HubPrefs.forget_rider("1")
	HubPrefs.path = HubPrefs.DEFAULT_PATH
	HubPrefs.reload()


func before_test() -> void:
	local = Session._local
	catalog = HubState.normalized({"catalog": local.hub.catalog()}).catalog
	HubPrefs.forget_rider(RIDER)
	HubPrefs.forget_rider("1")


func after_test() -> void:
	if hub:
		local.hub.phase = ""
		Session.visit_id = ""
		Session.hub = {}
		Session.director.phase = SessionDirector.Phase.IDLE
		local.process_mode = Node.PROCESS_MODE_ALWAYS
		local.hub.permission = "granted"
		local.hub.settings.camera_games = true
		Engine.max_fps = 0
		hub = null


func _entry(id: String) -> Dictionary:
	for e in catalog:
		if e.id == id:
			return e
	return {}


# --- CircuitBuilder ---

func test_a_new_slot_takes_the_games_minimum_or_one_and_a_half_minutes() -> void:
	var b := CircuitBuilder.new(catalog)
	assert_bool(b.add("kart_race")).is_true()
	assert_bool(b.add("dodge_ball")).is_true()
	assert_int(int(b.slots[0].duration_sec)).is_equal(300)
	assert_int(int(b.slots[1].duration_sec)).is_equal(90)


func test_steps_are_30_s_up_to_5_min_then_whole_minutes() -> void:
	var steps := CircuitBuilder.steps_for(_entry("dodge_ball"))
	assert_array(steps.slice(0, 10)).is_equal([60, 90, 120, 150, 180, 210, 240, 270, 300, 360])
	assert_int(int(steps.back())).is_equal(3600)
	assert_int(int(CircuitBuilder.steps_for(_entry("kart_race"))[0])).is_equal(300)
	assert_int(int(CircuitBuilder.steps_for(_entry("kart_race"))[1])).is_equal(360)


func test_lengths_never_go_under_a_games_minimum() -> void:
	var b := CircuitBuilder.new(catalog, [{"game_id": "kart_race", "duration_sec": 60}, {"game_id": "safe_cracker", "duration_sec": 10}])
	assert_int(int(b.slots[0].duration_sec)).is_equal(300)
	assert_int(int(b.slots[1].duration_sec)).is_equal(60)
	b.set_length(0, 120)
	assert_int(int(b.slots[0].duration_sec)).is_equal(300)
	assert_int(int(b.lengths(0)[0])).is_equal(300)


func test_seconds_round_to_30_then_clamp_as_kotlin() -> void:
	var e := _entry("tug_of_war")
	assert_int(CircuitBuilder.seconds_for(e, 100)).is_equal(90)
	assert_int(CircuitBuilder.seconds_for(e, 105)).is_equal(120)
	assert_int(CircuitBuilder.seconds_for(e, 20)).is_equal(60)
	assert_int(CircuitBuilder.seconds_for(e, 99999)).is_equal(3600)


func test_twelve_slots_at_most() -> void:
	var b := CircuitBuilder.new(catalog)
	for i in 12:
		assert_bool(b.add("safe_cracker")).is_true()
	assert_str(b.add_problem("safe_cracker")).is_equal("full")
	assert_bool(b.add("safe_cracker")).is_false()
	assert_int(b.size()).is_equal(12)


func test_ninety_minutes_at_most() -> void:
	var b := CircuitBuilder.new(catalog, [{"game_id": "kart_race", "duration_sec": 3600}, {"game_id": "kart_race", "duration_sec": 1740}])
	assert_int(b.gameplay_sec()).is_equal(5340)
	assert_str(b.add_problem("dodge_ball")).is_equal("too_long")  # 90 s would pass 90 min
	assert_int(int(b.lengths(1).back())).is_equal(1800)  # + stops at the cap
	b.set_length(1, 1860)
	assert_int(int(b.slots[1].duration_sec)).is_equal(1740)
	b.set_length(1, 1800)
	assert_int(b.gameplay_sec()).is_equal(CircuitBuilder.MAX_SEC)


func test_roles_follow_kotlins_rule() -> void:
	var b := CircuitBuilder.new(catalog, [{"game_id": "cadence_karaoke", "duration_sec": 180},
		{"game_id": "dodge_ball", "duration_sec": 90}, {"game_id": "safe_cracker", "duration_sec": 90},
		{"game_id": "kart_race", "duration_sec": 300}, {"game_id": "cadence_karaoke", "duration_sec": 180}])
	var roles: Array = []
	for i in b.size():
		roles.append(b.role(i))
	assert_array(roles).is_equal(["warmup", "work", "recovery", "free", "cooldown"])
	# A lone Cadence slot is its warm-up (first wins); Cadence in the middle plays recovery.
	assert_str(CircuitBuilder.new(catalog, [{"game_id": "cadence_karaoke", "duration_sec": 60}]).role(0)).is_equal("warmup")
	b.move(0, 1)
	assert_str(b.role(1)).is_equal("recovery")
	assert_str(b.role(0)).is_equal("work")


func test_the_request_and_plan_id() -> void:
	var b := CircuitBuilder.new(catalog, [{"game_id": "cadence_karaoke", "duration_sec": 180},
		{"game_id": "kart_race", "duration_sec": 600}, {"game_id": "safe_cracker", "duration_sec": 120}], "hard")
	assert_dict(b.request()).is_equal({"kind": "custom", "difficulty": "hard", "slots": [
		{"game_id": "cadence_karaoke", "duration_sec": 180}, {"game_id": "kart_race", "duration_sec": 600},
		{"game_id": "safe_cracker", "duration_sec": 120}]})
	assert_str(b.plan_id()).is_equal("custom:cadence_karaoke.180,kart_race.600,safe_cracker.120")
	assert_int(b.total_sec()).is_equal(900 + 30)
	var planned: Dictionary = local.hub.build_plan(b.request())
	assert_str(str(planned.plan.plan_id)).is_equal(b.plan_id())
	var planned_roles: Array = planned.plan.segments.map(func(s): return s.role)
	assert_array(planned_roles).is_equal([b.role(0), b.role(1), b.role(2)])


func test_move_and_remove() -> void:
	var b := CircuitBuilder.new(catalog, [{"game_id": "dodge_ball", "duration_sec": 90}, {"game_id": "safe_cracker", "duration_sec": 90}])
	assert_bool(b.move(0, -1)).is_false()
	assert_bool(b.move(0, 1)).is_true()
	assert_str(str(b.slots[0].game_id)).is_equal("safe_cracker")
	b.remove(0)
	assert_int(b.size()).is_equal(1)
	assert_str(str(b.slots[0].game_id)).is_equal("dodge_ball")


func test_without_the_camera() -> void:
	var b := CircuitBuilder.new(catalog, [{"game_id": "dodge_ball", "duration_sec": 90}])
	assert_str(b.stand_in("dodge_ball")).is_equal("tug_of_war")
	assert_str(b.start_problem(false)).is_equal("")
	b.add("kart_race")
	assert_str(b.stand_in("kart_race")).is_equal("")
	# The Pull (#79) is free and camera-free too, but no stand-in for a race; it plays itself.
	assert_str(b.stand_in("the_pull")).is_equal("the_pull")
	assert_str(b.start_problem(false)).is_equal("camera:kart_race")
	assert_str(b.start_problem(true)).is_equal("")
	assert_str(CircuitBuilder.new(catalog).start_problem(true)).is_equal("empty")


# --- HubPrefs ---

func test_saved_circuits_save_replace_and_delete() -> void:
	assert_array(HubPrefs.custom_circuits(RIDER)).is_equal([null, null, null])
	assert_int(HubPrefs.free_custom(RIDER)).is_equal(0)
	var b := CircuitBuilder.new(catalog, [{"game_id": "dodge_ball", "duration_sec": 120}], "easy")
	for i in 3:
		HubPrefs.save_custom(RIDER, i, b.to_saved())
	assert_int(HubPrefs.free_custom(RIDER)).is_equal(-1)
	HubPrefs.reload()  # from disk
	var saved: Dictionary = HubPrefs.custom_circuit(RIDER, 1)
	assert_str(str(saved.difficulty)).is_equal("easy")
	assert_int(int(saved.v)).is_equal(1)
	assert_str(CircuitBuilder.new(catalog, saved.slots).plan_id()).is_equal("custom:dodge_ball.120")
	var other := CircuitBuilder.new(catalog, [{"game_id": "safe_cracker", "duration_sec": 60}])
	HubPrefs.save_custom(RIDER, 1, other.to_saved())
	assert_str(CircuitBuilder.new(catalog, HubPrefs.custom_circuit(RIDER, 1).slots).plan_id()).is_equal("custom:safe_cracker.60")
	HubPrefs.delete_custom(RIDER, 0)
	assert_int(HubPrefs.free_custom(RIDER)).is_equal(0)
	assert_object(HubPrefs.custom_circuit(RIDER, 0)).is_null()
	assert_str(HubPrefs.custom_name(2)).is_equal("My circuit 3")


func test_saved_circuits_are_per_rider() -> void:
	HubPrefs.save_custom(RIDER, 0, CircuitBuilder.new(catalog, [{"game_id": "dodge_ball", "duration_sec": 90}]).to_saved())
	assert_object(HubPrefs.custom_circuit("guest", 0)).is_null()


# --- The screens ---

func _open_hub() -> void:
	local.process_mode = Node.PROCESS_MODE_DISABLED
	Session.director.phase = SessionDirector.Phase.IDLE
	local.hub.begin_visit()
	hub = get_tree().current_scene
	await _settle()


func _settle(frames := 8) -> void:
	for i in frames:
		await get_tree().process_frame


func test_home_has_my_circuits_and_build() -> void:
	await _open_hub()
	var home: HomeScreen = hub.screen
	assert_bool(home.circuit_cards.has("mine") and home.circuit_cards.has("build")).is_true()
	home.circuit_cards["build"].hit.pressed.emit()
	await _settle(3)
	assert_str(hub.nav.top_id()).is_equal(HubNav.BUILDER)
	assert_object(hub.screen).is_instanceof(BuilderScreen)


func test_build_save_and_start() -> void:
	await _open_hub()
	hub.nav.push(HubNav.BUILDER, {"index": -1})
	await _settle()
	var s: BuilderScreen = hub.screen
	assert_bool(s.save_button.disabled).is_true()
	assert_bool(s.start_button.disabled).is_true()
	s.tiles.cards["cadence_karaoke"].hit.pressed.emit()
	s.tiles.cards["dodge_ball"].hit.pressed.emit()
	await _settle(2)
	assert_int(s.rows.size()).is_equal(2)
	assert_str(s.tiles.value).is_equal("")  # tiles add; nothing stays picked
	assert_str(s.rows[0].role_label.text).is_equal("1 · Warm-up")
	s.rows[1].stepper.step(1)  # 1:30 → 2:00
	assert_int(int(s.builder.slots[1].duration_sec)).is_equal(120)
	assert_bool(s.save_button.disabled).is_false()
	s.save()
	await _settle(2)
	assert_int(s.index).is_equal(0)
	assert_str(s._title.text).is_equal("MY CIRCUIT 1")
	assert_bool(s.save_button.disabled).is_true()
	assert_bool(s.delete_button.visible).is_true()
	assert_str(CircuitBuilder.new(catalog, HubPrefs.custom_circuit("1", 0).slots).plan_id()).is_equal("custom:cadence_karaoke.90,dodge_ball.120")
	s.start.disconnect(hub._start)  # the request only: no plan swaps the scene here
	var sent: Array = []
	s.start.connect(func(r: Dictionary): sent.append(r))
	s.start_button.pressed.emit()
	assert_array(sent).is_equal([{"kind": "custom", "difficulty": "standard",
		"slots": [{"game_id": "cadence_karaoke", "duration_sec": 90}, {"game_id": "dodge_ball", "duration_sec": 120}]}])
	assert_bool(s.start_button.disabled).is_true()  # until session_started or plan_rejected
	s.start_answered()
	assert_bool(s.start_button.disabled).is_false()


func test_a_fourth_save_asks_which_to_replace() -> void:
	for i in 3:
		HubPrefs.save_custom("1", i, CircuitBuilder.new(catalog, [{"game_id": "safe_cracker", "duration_sec": 60 + 30 * i}]).to_saved())
	await _open_hub()
	hub.nav.push(HubNav.BUILDER, {"index": -1})
	await _settle()
	var s: BuilderScreen = hub.screen
	s.add_game("tug_of_war")
	s.save()
	await _settle(2)
	assert_object(s.replace_panel).is_not_null()
	(s.replace_panel.find_child("Replace_1", true, false) as Button).pressed.emit()
	await _settle(2)
	assert_bool(hub.dialog.visible).is_true()
	hub.dialog.act_button.pressed.emit()
	await _settle(2)
	assert_int(s.index).is_equal(1)
	assert_str(CircuitBuilder.new(catalog, HubPrefs.custom_circuit("1", 1).slots).plan_id()).is_equal("custom:tug_of_war.90")
	assert_str(CircuitBuilder.new(catalog, HubPrefs.custom_circuit("1", 0).slots).plan_id()).is_equal("custom:safe_cracker.60")


func test_delete_is_confirmed() -> void:
	HubPrefs.save_custom("1", 0, CircuitBuilder.new(catalog, [{"game_id": "safe_cracker", "duration_sec": 60}]).to_saved())
	await _open_hub()
	hub.nav.push(HubNav.MY_CIRCUITS)
	await _settle()
	hub.screen.cards[0].hit.pressed.emit()
	await _settle(3)
	var s: BuilderScreen = hub.screen
	assert_int(s.index).is_equal(0)
	s.delete_button.pressed.emit()
	assert_bool(hub.dialog.visible).is_true()
	hub.dialog.keep_button.pressed.emit()
	assert_object(HubPrefs.custom_circuit("1", 0)).is_not_null()
	s.delete_button.pressed.emit()
	hub.dialog.act_button.pressed.emit()
	await _settle(3)
	assert_object(HubPrefs.custom_circuit("1", 0)).is_null()
	assert_str(hub.nav.top_id()).is_equal(HubNav.MY_CIRCUITS)


func test_leaving_unsaved_asks_first() -> void:
	await _open_hub()
	hub.nav.push(HubNav.BUILDER, {"index": -1})
	await _settle()
	var s: BuilderScreen = hub.screen
	s.add_game("dodge_ball")
	Session.back()
	assert_bool(hub.dialog.visible).is_true()
	assert_str(hub.nav.top_id()).is_equal(HubNav.BUILDER)
	hub.dialog.act_button.pressed.emit()
	await _settle(3)
	assert_str(hub.nav.top_id()).is_equal(HubNav.HOME)


func test_the_draft_survives_a_rebuild() -> void:
	await _open_hub()
	hub.nav.push(HubNav.BUILDER, {"index": -1})
	await _settle()
	hub.screen.add_game("safe_cracker")
	hub.screen.add_game("dodge_ball")
	var stack: Array = hub.nav.snapshot()
	hub.nav.restore(stack)
	hub._show_top()  # as when the hub comes back after a plan
	await _settle(3)
	assert_int(hub.screen.builder.size()).is_equal(2)


func test_camera_off_greys_start_for_kart_race() -> void:
	local.hub.permission = "ask"
	await _open_hub()
	hub.nav.push(HubNav.BUILDER, {"index": -1})
	await _settle()
	var s: BuilderScreen = hub.screen
	s.add_game("dodge_ball")
	assert_bool(s.start_button.disabled).is_false()  # Dodge Ball plays as Tug of War
	s.add_game("kart_race")
	assert_bool(s.start_button.disabled).is_true()
	assert_str(s.problem_label.text).is_equal("Kart Race needs the camera")


func test_a_finished_custom_circuit_shows_its_best_on_its_card() -> void:
	var b := CircuitBuilder.new(catalog, [{"game_id": "safe_cracker", "duration_sec": 60}])
	HubPrefs.save_custom("1", 0, b.to_saved())
	local.hub.plan_bests[b.plan_id() + "|standard"] = {"score": 4321, "stars": 2}
	await _open_hub()
	hub.nav.push(HubNav.MY_CIRCUITS)
	await _settle()
	assert_str(hub.screen.best_text(0)).is_equal("Best 4321")
	assert_str(hub.screen.best_text(1)).is_equal("")
	local.hub.plan_bests.erase(b.plan_id() + "|standard")


func test_opening_a_circuit_with_a_retired_game_doesnt_offer_to_overwrite_it() -> void:
	# Review of PR #58: the unknown game was dropped on load, which read as an edit, and one
	# Save rewrote the circuit (its plan id and bests) without it.
	await _open_hub()
	var rider := HubPrefs.rider(hub.state)
	var saved := {"v": 1, "difficulty": "standard", "slots": [
		{"game_id": "dodge_ball", "duration_sec": 120}, {"game_id": "retired_game", "duration_sec": 120},
		{"game_id": "cadence_karaoke", "duration_sec": 120}]}
	HubPrefs.save_custom(rider, 0, saved)
	hub.nav.push(HubNav.BUILDER, {"index": 0})
	await _settle()
	var s: BuilderScreen = hub.screen
	assert_int(s.builder.slots.size()).is_equal(2)
	assert_int(s.builder.dropped).is_equal(1)
	assert_bool(s.dirty()).is_false()
	assert_bool(s.save_button.disabled).is_true()
	s.save()
	assert_array(HubPrefs.custom_circuit(rider, 0).slots).has_size(3)
	HubPrefs.delete_custom(rider, 0)
