extends GdUnitTestSuite
## Dodge Ball's scene with the framework: pause freezes the field, the rider's options apply
## and are remembered per rider, and the result carries the issue's stats.

const SEGMENT := {"game_id": "dodge_ball", "role": "free", "difficulty": "standard", "duration_sec": -1,
	"end_mode": "game", "seed": 7, "effort": true, "params": {"cadence_floor": 85, "target_watts": 200}}

var _rider := ""
var _saved_plan := {}


func before_test() -> void:
	# A rider of its own, so the test neither sees nor leaves real riders' options.
	_rider = "test%d" % Time.get_ticks_usec()
	_saved_plan = Session.plan
	Session.plan = {"rider_id": _rider}


func after_test() -> void:
	GameOptions.forget_rider(_rider)
	GameOptions.forget_rider(_rider + "b")
	Session.plan = _saved_plan


func _game() -> Game:
	var game: Game = auto_free(load("res://games/dodge_ball/DodgeBall.tscn").instantiate())
	game.hud = auto_free(Hud.new())
	add_child(game)
	game.prepare(SEGMENT)
	game.start()
	return game


func test_pause_freezes_the_field() -> void:
	var game := _game()
	await await_millis(300)
	var logic: DodgeBallLogic = game.get("logic")
	assert_float(logic.time_total).is_greater(0.0)
	game.set_paused(true)
	var frozen := logic.time_total
	var distance: float = game.get("world").distance
	await await_millis(300)
	assert_float(logic.time_total).is_equal(frozen)
	assert_float(game.get("world").distance).is_equal(distance)
	game.set_paused(false)
	await await_millis(200)
	assert_float(logic.time_total).is_greater(frozen)


func test_options_apply_and_are_remembered_per_rider() -> void:
	var game := _game()
	assert_str(game.option("scene")).is_equal("auto")
	assert_str(game.option("camera_roll")).is_equal("on")
	game.change_option("camera_roll", "off")
	assert_bool(game.get("world").roll_enabled).is_false()
	game.change_option("scene", "night")
	assert_str(game.option("scene")).is_equal("night")
	# Unknown values are ignored.
	game.change_option("scene", "noon")
	assert_str(game.option("scene")).is_equal("night")
	# Stored on disk for this rider only.
	GameOptions.reload()
	var info := game.declared()
	var other := _rider + "b"
	assert_str(GameOptions.rider()).is_equal(_rider)
	assert_str(GameOptions.get_value(info, "scene", _rider)).is_equal("night")
	assert_str(GameOptions.get_value(info, "scene", other)).is_equal("auto")
	GameOptions.set_value(info, "scene", "dawn", other)
	assert_str(GameOptions.get_value(info, "scene", other)).is_equal("dawn")
	assert_str(GameOptions.get_value(info, "scene", _rider)).is_equal("night")


func test_options_cycle_in_order() -> void:
	var spec := {"key": "k", "label": "K", "choices": ["a", "b", "c"], "labels": ["A", "B", "C"], "default": "a"}
	assert_str(GameOptions.next_choice(spec, "a")).is_equal("b")
	assert_str(GameOptions.next_choice(spec, "c")).is_equal("a")
	assert_str(GameOptions.label_for(spec, "b")).is_equal("B")


func test_result_has_the_issue_stats() -> void:
	var game := _game()
	await await_millis(300)
	var result := game.finish()
	for key in ["dodges", "hits", "pct_time_above_floor", "avg_power", "longest_streak", "runs", "effort_avg"]:
		assert_bool(result.stats.has(key)).override_failure_message("missing stats.%s" % key).is_true()
	assert_that(result.won).is_null()
