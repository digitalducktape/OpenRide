extends GdUnitTestSuite
## Tug of War's scene wiring after the tablet performance pass: the result's stats are built at
## finish (not every frame), the lost-round flash tints the view's image, and the quality step
## shrinks the 3D view.

var game: Node


func before_test() -> void:
	game = load("res://games/tug_of_war/TugOfWar.tscn").instantiate()
	game.hud = auto_free(load("res://framework/hud/Hud.gd").new())
	add_child(game.hud)
	add_child(game)
	game.prepare({"game_id": "tug_of_war", "role": "free", "difficulty": "standard", "duration_sec": -1,
		"end_mode": "game", "seed": 7, "params": {"ftp": 200.0}})
	game.start()
	game.set_process(false)


func after_test() -> void:
	game.free()


func test_stats_are_built_at_finish() -> void:
	for i in 30:
		game._on_frame(1.0 / 60.0)
	assert_dict(game.stats).is_empty()
	var result: Dictionary = game.finish()
	for key in ["mode", "rounds_won", "rounds_lost", "best_rung", "avg_power", "surges", "surges_answered"]:
		assert_bool(result.stats.has(key)).override_failure_message("stats lacks %s" % key).is_true()
	assert_array(["match", "ladder"]).contains([str(result.stats.mode)])


func test_the_lost_round_flash_tints_the_view_and_fades() -> void:
	game._handle({"type": "round_end", "won": false, "points": 0.0})
	var shown: CanvasItem = game.get_node("View3DImage")
	assert_float(shown.modulate.b).is_less(1.0)
	for i in 60:
		game._on_frame(1.0 / 60.0)
	assert_object(shown.modulate).is_equal(Color.WHITE)


func test_the_quality_step_shrinks_the_view() -> void:
	var view: SubViewport = game.get_node("View3D")
	var full := view.size
	game.view.governor.tier = 1
	game.view.set_render_scale(game.view.governor.render_scale(game.RENDER_SCALE))
	assert_int(view.size.x).is_less(full.x)
	assert_int(view.size.x).is_equal(roundi(HudTheme.W * RenderScaleStep.LOW_SCALE))
