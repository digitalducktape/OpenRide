extends GdUnitTestSuite
## Every registered game loads, extends Game, and declares itself validly. A new game gets
## these checks by adding its registry line.


func test_every_registered_game_is_valid() -> void:
	assert_array(GameRegistry.ids()).is_not_empty()
	for game_id in GameRegistry.ids():
		var game := GameRegistry.instantiate(game_id)
		assert_object(game).override_failure_message("%s doesn't load as a Game" % game_id).is_not_null()
		var info := game.declared()
		assert_str(info.id).override_failure_message("%s's info().id is '%s'" % [game_id, info.id]).is_equal(game_id)
		assert_array(Array(info.validate())).override_failure_message("%s: %s" % [game_id, info.validate()]).is_empty()
		assert_str(game.target_text({"difficulty": "standard", "params": {}})).is_not_empty()
		game.free()


func test_the_demo_is_registered() -> void:
	assert_bool(GameRegistry.has("demo")).is_true()
	var info := GameRegistry.info("demo")
	assert_str(info.title).is_equal("Demo")
	assert_str(info.tracker_mode).is_equal("lean_x")
	assert_bool(info.effort_in_just_ride).is_true()


func test_info_is_cached() -> void:
	assert_object(GameRegistry.info("demo")).is_same(GameRegistry.info("demo"))


func test_unknown_game_is_null() -> void:
	assert_bool(GameRegistry.has("nope")).is_false()
	assert_object(GameRegistry.instantiate("nope")).is_null()
	assert_object(GameRegistry.info("nope")).is_null()


func test_validate_reports_problems() -> void:
	var info := GameInfo.new()
	info.supports = ["weeks"]
	info.roles = ["sprint"]
	info.tracker_mode = "eyes"
	info.star_thresholds = {"easy": [3, 2, 1], "standard": [1, 2]}
	var problems := "\n".join(info.validate())
	for expected in ["id is empty", "title is empty", "how_to is empty", "unknown supports mode 'weeks'",
			"unknown role 'sprint'", "unknown tracker_mode 'eyes'", "star_thresholds.easy must be positive and rising",
			"star_thresholds.standard needs three scores", "star_thresholds.hard needs three scores"]:
		assert_str(problems).contains(expected)


func test_calibration_mode_follows_tracker_mode() -> void:
	var info := GameInfo.new()
	for pair in [["off", "lean_x"], ["lean_x", "lean_x"], ["lean_stand", "lean_x"], ["lean_2d", "lean_2d"]]:
		info.tracker_mode = pair[0]
		assert_str(info.calibration_mode()).is_equal(pair[1])
	info.tracker_mode = "off"
	assert_bool(info.uses_camera()).is_false()
