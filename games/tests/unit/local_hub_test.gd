extends GdUnitTestSuite
## LocalHub, the desktop's stand-in for Kotlin's hub visit: the hub_state it sends, plans it
## accepts and rejects, a plan's visit keys and bests, settings, exit and the idle save.

const LocalSession := preload("res://autoload/LocalSession.gd")
const LocalHub := preload("res://autoload/LocalHub.gd")

var local: Node
var hub: Node
var states: Array = []
var rejected: Array = []
var ended: Array = []
var _on_state := func(s: Dictionary): states.append(s)
var _on_rejected := func(r: Dictionary): rejected.append(r)
var _on_ended := func(r: Dictionary): ended.append(r)


func before_test() -> void:
	local = Session._local
	hub = local.hub
	local.process_mode = Node.PROCESS_MODE_DISABLED
	Session.director.process_mode = Node.PROCESS_MODE_DISABLED
	states.clear()
	rejected.clear()
	ended.clear()
	Session.hub_state_changed.connect(_on_state)
	Session.plan_rejected.connect(_on_rejected)
	Session.visit_ended.connect(_on_ended)
	hub.settings = {"camera_games": true, "music": "auto", "music_volume": 0.8, "sfx_volume": 1.0}
	hub.permission = "granted"
	hub.begin_visit()


func after_test() -> void:
	Session.hub_state_changed.disconnect(_on_state)
	Session.plan_rejected.disconnect(_on_rejected)
	Session.visit_ended.disconnect(_on_ended)
	if Session.active:
		Session.request_end()
		for i in 30:
			local._process(0.25)
	hub.phase = ""
	Session.visit_id = ""
	Session.hub = {}
	Session.director.summary_screen.visible = false
	local.process_mode = Node.PROCESS_MODE_ALWAYS
	Session.director.process_mode = Node.PROCESS_MODE_ALWAYS
	Engine.max_fps = 0


func test_a_visit_starts_with_a_full_hub_state() -> void:
	var s: Dictionary = states.back()
	assert_str(s.phase).is_equal("hub")
	assert_str(s.visit_id).is_equal(Session.visit_id)
	var ids: Array = s.catalog.map(func(g): return g.id)
	assert_array(ids).is_equal(["kart_race", "dodge_ball", "tug_of_war", "safe_cracker", "cadence_karaoke", "watt_lane", "the_pull", "balloon_pump",
		"keepy_uppy", "power_grid"])
	var kart: Dictionary = s.catalog[0]
	assert_array(kart.minute_steps).is_equal([5.0, 10.0, 15.0, 20.0, 30.0, 45.0, 60.0])
	assert_str(kart.circuit_role).is_equal("free")
	assert_bool(kart.uses_camera).is_true()
	assert_int(s.circuits.size()).is_equal(3)
	assert_int(int(s.circuits[0].total_sec)).is_equal(1120)  # 18:40, as CircuitPresets


func test_a_just_ride_plays_with_the_visit_keys() -> void:
	Session.start_plan({"kind": "just_ride", "game_id": "safe_cracker", "mode": "minutes", "length": 5, "difficulty": "easy"})
	assert_bool(Session.active).is_true()
	assert_str(Session.plan.plan_id).is_equal("just-ride:safe_cracker:minutes:5")
	assert_str(Session.plan.visit_id).is_equal(hub.visit_id)
	assert_int(int(Session.plan.plan_index)).is_equal(0)
	assert_str(hub.phase).is_equal("plan")
	# Busy until it ends.
	Session.start_plan({"kind": "circuit", "preset_id": "circuit-20"})
	assert_str(rejected.back().reason).is_equal("busy")


func test_a_finished_plan_reports_its_visit_and_comes_back_in_hub_state() -> void:
	Session.start_plan({"kind": "just_ride", "game_id": "safe_cracker", "mode": "open", "difficulty": "standard"})
	Session.request_end()
	assert_str(Session.summary.visit_id).is_equal(hub.visit_id)
	assert_str(Session.summary.plan_id).is_equal("just-ride:safe_cracker:open")
	assert_object(Session.summary.ride_id).is_null()
	assert_str(hub.phase).is_equal("hub")
	var s: Dictionary = states.back()
	assert_int(s.visit.plans.size()).is_equal(1)
	assert_str(s.visit.plans[0].plan_id).is_equal("just-ride:safe_cracker:open")


func test_rejections() -> void:
	Session.start_plan({"kind": "just_ride", "game_id": "nope", "mode": "minutes", "length": 5})
	Session.start_plan({"kind": "just_ride", "game_id": "cadence_karaoke", "mode": "rounds", "length": 3})
	Session.start_plan({"kind": "custom", "slots": []})
	hub.settings.camera_games = false
	Session.start_plan({"kind": "just_ride", "game_id": "kart_race", "mode": "minutes", "length": 5})
	var reasons: Array = rejected.map(func(r): return r.reason)
	assert_array(reasons).is_equal(["unknown_game", "unsupported_mode", "empty_circuit", "camera_unavailable"])
	assert_bool(Session.active).is_false()


func test_rounds_and_presets_plan_as_kotlin_does() -> void:
	var plan: Dictionary = hub.build_plan({"kind": "just_ride", "game_id": "tug_of_war", "mode": "rounds", "length": 3}).plan
	assert_int(plan.segments[0].duration_sec).is_equal(360)
	assert_str(plan.segments[0].end_mode).is_equal("game")
	hub.settings.camera_games = false
	var circuit: Dictionary = hub.build_plan({"kind": "circuit", "preset_id": "circuit-20"}).plan
	var games: Array = circuit.segments.map(func(s): return s.game_id)
	assert_bool("dodge_ball" in games).is_false()  # the camera-off substitution
	hub.settings.camera_games = true
	var custom: Dictionary = hub.build_plan({"kind": "custom", "slots": [
		{"game_id": "cadence_karaoke", "duration_sec": 170}, {"game_id": "kart_race", "duration_sec": 100}]}).plan
	assert_str(custom.plan_id).is_equal("custom:cadence_karaoke.180,kart_race.300")
	assert_str(custom.segments[0].role).is_equal("warmup")
	assert_str(custom.segments[1].role).is_equal("free")


## Eleven catalog entries as the hub_state sends them (min_sec, max_sec, roles, uses_camera).
static func _eleven() -> Array:
	var games := [
		["kart_race", [], 300, true], ["dodge_ball", ["work"], 60, true], ["tug_of_war", ["work"], 60, false],
		["safe_cracker", ["recovery"], 60, false], ["cadence_karaoke", ["warmup", "recovery", "cooldown"], 60, false],
		["power_grid", ["warmup", "work", "cooldown"], 60, false], ["watt_lane", ["warmup", "recovery", "cooldown"], 60, false],
		["gate_crasher", ["work"], 60, true], ["ready_for_launch", ["work"], 90, false],
		["keepy_uppy", ["recovery"], 60, false], ["the_pull", [], 300, false],
	]
	return games.map(func(g): return {"id": g[0], "roles": g[1], "min_sec": g[2], "max_sec": 3600, "uses_camera": g[3]})


func _shape_45() -> Array:
	var shape: Array = [LocalHub.WARMUP]
	for i in 6:
		shape.append_array(LocalHub.BLOCK)
	shape.append(LocalHub.COOLDOWN)
	return shape


func test_circuits_draw_from_role_pools_like_kotlin() -> void:
	var shape := _shape_45()
	for entries in [hub.catalog(), _eleven()]:
		for camera in [true, false]:
			for seed_value in 40:
				var slots: Array = LocalHub.draw_slots(shape, entries, camera, seed_value)
				# Deterministic per seed.
				assert_array(LocalHub.draw_slots(shape, entries, camera, seed_value)).is_equal(slots)
				var by_id := {}
				for e in entries:
					by_id[e.id] = e
				var played := {}  # role → ids this pass
				var before := ""
				for slot in slots:
					var e: Dictionary = by_id[slot.game_id]
					assert_bool(slot.role in e.roles).is_true()
					assert_bool(int(slot.duration_sec) >= int(e.min_sec)).override_failure_message("%s in %ds" % [e.id, slot.duration_sec]).is_true()
					assert_bool(camera or not e.uses_camera).is_true()
					var seen: Dictionary = played.get_or_add(slot.role, {})
					if seen.has(slot.game_id):
						# A repeat only once every game that fits the slot has played this pass, but
						# for the one that played the slot before (not twice running wins).
						for f in LocalHub.circuit_pool(entries, slot.role, camera):
							if int(slot.duration_sec) >= int(f.min_sec) and f.id != before:
								assert_bool(seen.has(f.id)).override_failure_message("%s repeats before %s" % [slot.game_id, f.id]).is_true()
						seen.clear()
					seen[slot.game_id] = true
					before = slot.game_id
				# 12 work and 12 recovery slots cover those pools.
				for role in ["work", "recovery"]:
					var ids := {}
					for slot in slots.filter(func(s): return s.role == role):
						ids[slot.game_id] = true
					assert_int(ids.size()).is_equal(LocalHub.circuit_pool(entries, role, camera).size())
	# Different seeds, different mixes.
	var mixes := {}
	for seed_value in 20:
		mixes[str(LocalHub.draw_slots(shape, _eleven(), true, seed_value).map(func(s): return s.game_id))] = true
	assert_int(mixes.size()).is_greater(1)


func test_the_hub_shows_the_lineup_that_plays() -> void:
	var shown: Array = states.back().circuits[2].slots.map(func(s): return s.game_id)
	var plan: Dictionary = hub.build_plan({"kind": "circuit", "preset_id": "circuit-45"}).plan
	assert_array(plan.segments.map(func(s): return s.game_id)).is_equal(shown)
	assert_str(plan.plan_id).is_equal("circuit-45")


func test_settings_resend_the_state() -> void:
	Session.update_setting("game_music", false)
	Session.update_setting("music_volume", 1.5)
	var s: Dictionary = states.back()
	assert_bool(s.settings.game_music).is_false()
	assert_bool(s.audio.music).is_false()
	assert_float(s.settings.music_volume).is_equal(1.0)
	assert_float(s.audio.music_volume).is_equal(1.0)


func test_exit_ends_the_visit_then_a_new_one_starts() -> void:
	var first: String = hub.visit_id
	Session.exit_hub("app")
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0].next).is_equal("app")
	assert_bool(ended[0].saved).is_false()  # no gameplay yet
	assert_str(ended[0].discarded_reason).is_equal("too_short")
	hub._process(LocalHub.RESTART_SEC + 0.1)
	assert_str(hub.visit_id).is_not_equal(first)
	assert_str(hub.phase).is_equal("hub")


func test_the_idle_guard_saves_and_a_tap_starts_a_new_visit() -> void:
	var first: String = hub.visit_id
	hub._process(LocalHub.IDLE_SAVE_SEC - 1.0)
	Session.hub_activity()  # a touch resets it
	hub._process(LocalHub.IDLE_SAVE_SEC - 1.0)
	assert_int(ended.size()).is_equal(0)
	hub._process(2.0)
	assert_int(ended.size()).is_equal(1)
	assert_str(ended[0].next).is_equal("hub")
	assert_str(ended[0].reason).is_equal("idle")
	Session.hub_activity()
	assert_str(hub.visit_id).is_not_equal(first)


func test_request_exit_in_the_hub_exits_it() -> void:
	Session.request_exit()
	assert_str(ended.back().reason).is_equal("exit")
