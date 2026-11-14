extends GdUnitTestSuite
## HubState: an old or partial hub_state gets its documented defaults, and the helpers the
## screens read (games, bests, the ride line, what's playable).


func test_an_empty_payload_gets_every_default() -> void:
	var s := HubState.normalized({})
	assert_int(s.hub_version).is_equal(1)
	assert_str(s.phase).is_equal("hub")
	assert_object(s.rider.id).is_null()
	assert_bool(s.settings.camera_games).is_true()
	assert_str(s.camera.permission).is_equal("granted")
	assert_array(s.catalog).is_empty()
	assert_array(s.bests.games).is_empty()
	assert_bool(s.visit.recording).is_true()


func test_a_partial_payload_keeps_its_values_and_fills_the_rest() -> void:
	var s := HubState.normalized({"rider": {"id": 3.0, "name": "Ed"}, "camera": {"available": false},
		"settings": "not a dictionary", "extra": 7})
	assert_str(s.rider.name).is_equal("Ed")
	assert_str(s.rider.avatar_color).is_equal("#7A7CFF")
	assert_bool(s.camera.available).is_false()
	assert_str(s.camera.permission).is_equal("granted")
	assert_bool(s.settings.game_music).is_true()  # the Game music switch, on by default
	assert_str(s.settings.lean_sensitivity).is_equal("normal")  # an app before #71 doesn't send it
	assert_int(s.extra).is_equal(7)  # unknown keys pass through


func test_catalog_entries_get_defaults_and_entries_without_an_id_go() -> void:
	var s := HubState.normalized({"catalog": [{"id": "dodge_ball", "supports": ["rounds"]}, {"title": "no id"}, "junk"]})
	assert_int(s.catalog.size()).is_equal(1)
	var e: Dictionary = s.catalog[0]
	assert_array(e.supports).is_equal(["rounds"])
	assert_int(e.max_rounds).is_equal(10)
	assert_str(e.title).is_equal("Dodge Ball")
	assert_str(e.circuit_role).is_equal("free")


func test_games_keep_only_registered_ones_in_catalog_order() -> void:
	var s := HubState.normalized({"catalog": [{"id": "tug_of_war"}, {"id": "not_a_game"}, {"id": "kart_race"}]})
	var ids: Array = HubState.games(s).map(func(e): return e.id)
	assert_array(ids).is_equal(["tug_of_war", "kart_race"])


func test_a_camera_game_is_playable_only_with_the_camera() -> void:
	var s := HubState.normalized({"camera": {"available": false}})
	assert_bool(HubState.playable(s, {"uses_camera": true})).is_false()
	assert_bool(HubState.playable(s, {"uses_camera": false})).is_true()


func test_bests_read_floats() -> void:
	var s := HubState.normalized({"bests": {
		"games": [{"game_id": "dodge_ball", "plan_id": "just-ride:dodge_ball:minutes:20", "difficulty": "standard", "score": 5400.0, "stars": 2.0},
			{"game_id": "dodge_ball", "plan_id": "just-ride:dodge_ball:minutes:20", "difficulty": "standard", "variant": "catch", "score": 6100.0, "stars": 3.0},
			{"game_id": "dodge_ball", "plan_id": "circuit-20", "difficulty": "standard", "score": 9999.0, "stars": 3.0}],
		"plans": [{"plan_id": "circuit-20", "difficulty": "hard", "score": 9100.0, "stars": 21.0}]}})
	assert_dict(HubState.game_best(s, "dodge_ball")).is_equal({"score": 6100, "stars": 3})  # Just Rides only
	assert_dict(HubState.just_ride_best(s, "dodge_ball", "just-ride:dodge_ball:minutes:20", "standard")).is_equal({"score": 6100, "stars": 3})
	assert_dict(HubState.just_ride_best(s, "dodge_ball", "just-ride:dodge_ball:minutes:20", "easy")).is_empty()
	assert_dict(HubState.plan_best(s, "circuit-20", "hard")).is_equal({"score": 9100, "stars": 21})
	assert_dict(HubState.circuit_best(s, "circuit-20")).is_equal({"score": 9100, "stars": 21})


func test_the_ride_line() -> void:
	assert_str(HubState.ride_line(HubState.normalized({}))).is_equal("Ride starts with a game")
	var s := HubState.normalized({"rider": {"id": 1}, "visit": {"ride_sec": 754.0, "plans": [{"game_ids": ["a"]}, {"game_ids": ["b", "c"]}]}})
	assert_str(HubState.ride_line(s)).is_equal("Ride so far 12:34 · 3 games")
	assert_str(HubState.ride_line(HubState.normalized({"visit": {"recording": false}}))).is_equal("Not recording: pick a rider in the app")
	assert_str(HubState.ride_line(HubState.normalized({"rider": {"id": 2}, "visit": {"recording": false}}))).is_equal("Not recording: another ride is running")


func test_hub_prefs_default_and_remember_a_game_pick() -> void:
	HubPrefs.path = "user://hub_prefs_test.cfg"
	HubPrefs.reload()
	HubPrefs.forget_rider("t")
	var entry: Dictionary = HubState.normalized({"catalog": [{"id": "kart_race", "supports": ["minutes", "open"], "minute_steps": [5.0, 10.0, 15.0]}]}).catalog[0]
	assert_dict(HubPrefs.game_pick("t", entry)).is_equal({"mode": "minutes", "length": 10, "difficulty": "standard"})
	HubPrefs.set_game_pick("t", "kart_race", {"mode": "minutes", "length": 15, "difficulty": "hard"})
	HubPrefs.reload()
	assert_dict(HubPrefs.game_pick("t", entry)).is_equal({"mode": "minutes", "length": 15, "difficulty": "hard"})
	# A pick the catalog no longer offers falls back to a valid one.
	HubPrefs.set_pick("t", "kart_race.mode", "rounds")
	assert_str(HubPrefs.game_pick("t", entry).mode).is_equal("minutes")
	HubPrefs.forget_rider("t")
	HubPrefs.path = HubPrefs.DEFAULT_PATH
	HubPrefs.reload()
