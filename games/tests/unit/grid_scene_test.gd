extends GdUnitTestSuite
## Power Grid's scene: the declarations, the intro card's numbers, one watts reading, the result's
## stats, and that playing redraws nothing.

const GridGame := preload("res://games/power_grid/PowerGrid.gd")
const FTP := 200.0

var game: Node
var hud: Hud
var _cadence := 0.0


func _segment(role := "work", duration := 180, params := {}) -> Dictionary:
	var p := {"ftp_watts": FTP}
	p.merge(params)
	return {"game_id": "power_grid", "role": role, "duration_sec": duration, "seed": 3, "difficulty": "standard",
		"effort": role == "work", "params": p}


func _start(seg: Dictionary) -> void:
	game = auto_free(GridGame.new())
	add_child(game)
	hud = auto_free(Hud.new())
	add_child(hud)
	var info: GameInfo = game.declared()
	hud.setup(info, seg)
	game.hud = hud
	game.prepare(seg)
	game.start(seg)


func before_test() -> void:
	_cadence = InputBus._sim_cadence


func after_test() -> void:
	InputBus._sim_cadence = _cadence
	if hud:
		hud.clear_widgets()
		hud.clear_skin()


func test_declarations() -> void:
	var g = auto_free(GridGame.new())
	var i: GameInfo = g.info()
	assert_array(i.validate()).is_empty()
	assert_str(i.id).is_equal("power_grid")
	assert_array(i.roles).contains_exactly_in_any_order(["warmup", "work", "recovery", "cooldown"])
	assert_array(i.supports).contains_exactly_in_any_order(["minutes", "open"])
	assert_str(i.tracker_mode).is_equal("off")
	assert_int(i.summary_stats.size()).is_equal(3)


func test_the_intro_numbers_come_from_the_params() -> void:
	var g = auto_free(GridGame.new())
	var seg := _segment("work", 180, {"demand_lo_watts": 100, "demand_hi_watts": 200})
	assert_str(g.target_text(seg)).contains("90 W").contains("180 W")
	var easy := _segment("recovery", 90, {"demand_lo_watts": 50, "demand_hi_watts": 70, "power_cap_watts": 111})
	assert_str(g.target_text(easy)).contains("45").contains("63").contains("111")


func test_the_intro_picture_lists_each_district_at_its_watts() -> void:
	var l := GridLogic.new(1, {"ftp_watts": FTP, "demand_lo_watts": 100, "demand_hi_watts": 200}, "work", 180.0)
	var v: GridIntroVisual = auto_free(GridIntroVisual.new(GridGame.look, l))
	var labels := v.find_children("Watts*", "Label", true, false)
	assert_int(labels.size()).is_equal(4)
	assert_str((labels[0] as Label).text).is_equal("90 W")
	assert_str((labels[3] as Label).text).is_equal("171 W")
	var storm: Label = v.find_child("StormLine", true, false)
	assert_str(storm.text).contains("30 W").contains("10 s")
	for label: Label in labels:
		assert_int(label.get_theme_font_size("font_size")).is_greater_equal(40)


func test_every_role_has_its_own_how_to() -> void:
	var g = auto_free(GridGame.new())
	var seen := {}
	for role in ["warmup", "cooldown", "recovery", "work"]:
		seen[g.how_to_text({"role": role})] = true
	assert_int(seen.size()).is_equal(4)


func test_the_ride_panel_shows_the_rules_smoothed_supply() -> void:
	_start(_segment())
	game.logic.supply = 123.0
	assert_float(hud.metrics.shown_power()).is_equal(123.0)


func test_no_score_while_the_pedals_are_still() -> void:
	_start(_segment())
	Effort.begin_segment(true)
	InputBus._sim_cadence = 0.0
	await await_millis(200)
	assert_float(game.logic.earned).is_equal(0.0)
	assert_float(game.score()).is_equal(0.0)


func test_easy_roles_have_no_storm_tile_and_work_does() -> void:
	_start(_segment("recovery", 90))
	var result: Dictionary = game.finish()
	assert_bool(result.stats.has("storms")).is_false()
	assert_bool(result.stats.has("lit_pct")).is_true()
	hud.clear_widgets()
	_start(_segment("work", 180))
	result = game.finish()
	assert_bool(result.stats.has("storms_restored")).is_true()
	assert_int(result.stats.districts_total).is_equal(4)


func test_the_status_states_follow_the_logic() -> void:
	_start(_segment())
	var l: GridLogic = game.logic
	l.pedalling = false
	assert_str(game._state_name()).is_equal("pedal")
	l.pedalling = true
	l.meeting = false
	assert_str(game._state_name()).is_equal("short")
	l.meeting = true
	assert_str(game._state_name()).is_equal("powered")
	l.storm = GridLogic.Storm.DOWN
	assert_str(game._state_name()).is_equal("repair")


func test_district_states() -> void:
	_start(_segment())
	var l: GridLogic = game.logic
	l.online = 3
	l.powered = 2
	l.dim = 0.4
	assert_int(game._district_state(0)).is_equal(1)
	assert_int(game._district_state(1)).is_equal(2)
	assert_int(game._district_state(2)).is_equal(3)
	assert_int(game._district_state(3)).is_equal(0)
	l.down_index = 0
	assert_int(game._district_state(0)).is_equal(4)


func test_playing_redraws_nothing_in_the_world() -> void:
	_start(_segment())
	var world: GridStage = game.world
	var calls := [0]
	SafeMesh.probe = func(_ci, _p, _i): calls[0] += 1
	for i in 5:
		await get_tree().process_frame
	calls[0] = 0
	for i in 30:
		world.update_view(0.016, Vector4(1, 1, 0.5, 0), 0.5, 0.6, 0.5, 85.0, true)
		await get_tree().process_frame
	SafeMesh.probe = Callable()
	assert_int(calls[0]).is_equal(0)


func test_the_valley_bakes_once_in_each_palette() -> void:
	_start(_segment())
	assert_int(game.world.bakes).is_equal(2)
	assert_bool(SafeMesh.is_built("grid_valley_0")).is_true()
	assert_bool(SafeMesh.is_built("grid_valley_1")).is_true()


func test_storm_events_show_and_clear() -> void:
	_start(_segment())
	var world: GridStage = game.world
	world.storm_warning(3.0)
	for i in 120:
		world.update_view(0.03, Vector4.ONE, 0.5, 0.6, 0.5, 85.0, true)
	assert_bool(world.find_child("Rain", false, false).visible).is_true()
	world.storm_over()
	for i in 120:
		world.update_view(0.03, Vector4.ONE, 0.5, 0.6, 0.5, 85.0, true)
	assert_bool(world.find_child("Rain", false, false).visible).is_false()
