extends GdUnitTestSuite
## Balloon Pump's scene wiring (#76): the mode per segment (circuits always Max), the result's
## variant and stats, scoring through award() with the tie-off and the Race bonus, and a rounds
## Just Ride ending itself after its heats.

var game: Node


func _make(seg: Dictionary) -> void:
	game = load("res://games/balloon_pump/BalloonPump.tscn").instantiate()
	game.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(game.hud)
	add_child(game)
	var full := {"game_id": "balloon_pump", "role": "free", "difficulty": "standard", "duration_sec": -1,
		"end_mode": "game", "seed": 7, "params": {"ftp_watts": 200.0}}
	full.merge(seg, true)
	Effort.begin_segment(false)
	game.prepare(full)
	game.start()
	game.set_process(false)


func after_test() -> void:
	if is_instance_valid(game):
		game.free()
	Effort.set_live(false)
	_set_mode("race")  # the declared default, for the desktop's guest rider


func _set_mode(mode: String) -> void:
	var g: Game = load("res://games/balloon_pump/BalloonPump.gd").new()
	GameOptions.set_value(g.declared(), "mode", mode)
	g.free()


func test_a_circuit_slot_always_plays_max() -> void:
	_set_mode("race")
	_make({"role": "work", "duration_sec": 90, "end_mode": "timer"})
	assert_str(game.logic.mode).is_equal("max")
	assert_str(game.variant).is_equal("")
	assert_bool(game.logic.heats).is_false()


func test_a_race_just_ride_reports_its_variant() -> void:
	_set_mode("race")
	_make({})
	assert_str(game.logic.mode).is_equal("race")
	assert_str(game.variant).is_equal("race")


func test_stats_are_built_at_finish() -> void:
	_make({})
	for i in 30:
		game._on_frame(1.0 / 30.0)
	assert_dict(game.stats).is_empty()
	var result: Dictionary = game.finish()
	for key in ["balloons", "gold", "avg_power", "peak_power", "heats", "heats_won", "fastest_balloon_sec"]:
		assert_bool(result.stats.has(key)).override_failure_message("stats lacks %s" % key).is_true()


func test_a_tie_off_flies_to_the_bunch() -> void:
	_make({})
	game._handle({"type": "filled", "kind": "large", "points": 200.0, "gold": false, "sec": 9.0})
	assert_bool(game.world._flyer.visible).is_true()


func test_a_rounds_ride_ends_after_its_heats() -> void:
	_set_mode("max")
	_make({"params": {"ftp_watts": 200.0, "rounds": 1, "race_sec": 20}})
	var ended := [false]
	game.ended.connect(func(): ended[0] = true)
	for i in 30 * 30:
		game.logic.step(1.0 / 30.0, 150.0, 85.0)
		for e in game.logic.step(0.0, 150.0, 85.0):
			game._handle(e)
		if game.logic.is_over():
			break
	game._handle({"type": "over"})
	assert_bool(ended[0]).is_true()
