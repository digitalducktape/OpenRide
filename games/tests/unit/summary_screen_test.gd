extends GdUnitTestSuite
## The session summary (#35, #37): a circuit ended early lists every planned game, the heading
## says whether it finished, and the best line says what the rider is up against.

const PLAN := {"kind": "circuit", "segments": [
	{"game_id": "cadence_karaoke", "role": "warmup", "duration_sec": 180},
	{"game_id": "tug_of_war", "role": "work", "duration_sec": 60},
	{"game_id": "safe_cracker", "role": "recovery", "duration_sec": 90},
]}


func _summary(results: Array, bests := {}) -> Dictionary:
	return {"results": results, "totals": {"score": 130, "stars": 1, "elapsed_sec": 51}, "bests": bests}


func test_a_circuit_ended_early_lists_every_planned_game() -> void:
	var screen: SummaryScreen = auto_free(SummaryScreen.new())
	add_child(screen)
	screen.show_summary(_summary([{"game_id": "cadence_karaoke", "score": 130, "stars": 1, "skipped": false}]), PLAN)
	assert_int(screen._rows.get_child_count()).is_equal(3)
	assert_str(screen._title.text).is_equal("Session ended early")
	# The last two say they weren't played.
	var pending := 0
	for row in screen._rows.get_children():
		for label in row.find_children("*", "Label", true, false):
			if (label as Label).text == "not played":
				pending += 1
	assert_int(pending).is_equal(2)


func test_a_finished_circuit_says_complete_with_a_row_each() -> void:
	var screen: SummaryScreen = auto_free(SummaryScreen.new())
	add_child(screen)
	var results := []
	for seg in PLAN.segments:
		results.append({"game_id": seg.game_id, "score": 100, "stars": 1, "skipped": false})
	screen.show_summary(_summary(results), PLAN)
	assert_int(screen._rows.get_child_count()).is_equal(3)
	assert_str(screen._title.text).is_equal("Circuit complete")


func test_a_just_ride_has_one_row_and_its_own_heading() -> void:
	var screen: SummaryScreen = auto_free(SummaryScreen.new())
	add_child(screen)
	var plan := {"kind": "just_ride", "segments": [{"game_id": "dodge_ball", "role": "free", "duration_sec": -1}]}
	screen.show_summary(_summary([{"game_id": "dodge_ball", "score": 500, "stars": 2, "skipped": false}]), plan)
	assert_int(screen._rows.get_child_count()).is_equal(1)
	assert_str(screen._title.text).is_equal("Ride complete")


func test_the_best_line_says_what_the_rider_is_up_against() -> void:
	assert_str(SummaryScreen.bests_text({})).is_equal("")
	assert_str(SummaryScreen.bests_text({"score": true})).is_equal("New personal best!")
	assert_str(SummaryScreen.bests_text({"score": true, "stars": true, "previous_score": 900, "previous_stars": 1})) \
		.is_equal("New personal best! (before: 900 points, 1 star)")
	assert_str(SummaryScreen.bests_text({"previous_score": 5400, "previous_stars": 2})).is_equal("Your best: 5400 points, 2 stars")
