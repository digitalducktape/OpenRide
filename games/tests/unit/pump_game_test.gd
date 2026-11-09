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


func test_the_intro_copy_comes_from_the_segments_params() -> void:
	_set_mode("race")
	_make({"params": {"ftp_watts": 200.0, "push_lo_watts": 16, "push_hi_watts": 52, "race_balloons": 7, "race_sec": 90}})
	# The biggest balloon's top line: 16 + 36 × 1.12.
	assert_str(game.target_text(game.segment)).is_equal("Get above 56 W to finish each balloon")
	assert_str(game.race_line(game.segment)).is_equal("Race: fill 7 balloons in 1:30")
	assert_str(game.how_to_text(game.segment).replace("\n", " ")).is_equal(
		"Pedal to pump up balloons. Each one gets harder to fill near the end")
	# FTP alone sets the line when the params leave it out, by role.
	var fallback := {"role": "recovery", "params": {"ftp_watts": 300.0}}
	assert_str(game.target_text(fallback)).is_equal("Get above 65 W to finish each balloon")
	# Circuits play Max: no race line.
	assert_str(game.race_line({"role": "work", "params": {}})).is_equal("")


func test_the_intro_picture_labels_gold_and_the_race() -> void:
	_set_mode("race")
	_make({"params": {"ftp_watts": 200.0, "race_balloons": 4, "race_sec": 120}})
	var picture: Control = auto_free(game.intro_visual())
	var texts: Array = picture.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_array(texts).contains(["Race: fill 4 balloons in 2:00", "Gold ×3", "100 pts"])


func test_the_ride_panel_shows_the_smoothed_watts_the_rules_use() -> void:
	_make({})
	game.logic.smoothed = 123.0
	assert_float(game.hud.metrics.shown_power()).is_equal(123.0)


func test_the_summary_tiles_show_balloons_and_the_race_only_in_race() -> void:
	_set_mode("max")
	_make({})
	var result: Dictionary = game.finish()
	assert_bool(result.stats.has("balloons")).is_true()
	assert_bool(result.stats.has("heats_won")).is_false()
	var keys: Array = game.declared().summary_stats.map(func(t): return t.key)
	assert_array(keys).contains(["balloons", "gold", "heats_won"])
