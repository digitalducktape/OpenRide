extends GdUnitTestSuite
## The Game base class: lifecycle, ending rules and the result it builds.


class ProbeGame extends Game:
	var calls: Array[String] = []

	func info() -> GameInfo:
		var i := GameInfo.new()
		i.id = "probe"
		i.title = "Probe"
		i.how_to = "Test"
		i.star_thresholds = {"easy": [1, 2, 3], "standard": [10, 20, 30], "hard": [100, 200, 300]}
		return i

	func _on_prepare(_segment: Dictionary) -> void:
		calls.append("prepare")

	func _on_start() -> void:
		calls.append("start")

	func _on_frame(_delta: float) -> void:
		calls.append("frame")

	func _on_pause() -> void:
		calls.append("pause")

	func _on_resume() -> void:
		calls.append("resume")


func _segment(end_mode := "timer", duration := 60.0) -> Dictionary:
	return {"index": 0.0, "count": 1.0, "game_id": "probe", "duration_sec": duration, "intro_sec": 10.0,
		"end_mode": end_mode, "role": "work", "difficulty": "standard", "effort": true, "seed": 1234.0,
		"audio": {"music": true, "music_volume": 0.8, "sfx_volume": 1.0}, "params": {"target_watts": 200.0}}


func before_test() -> void:
	Effort.begin_segment(true)
	InputBus.sensors_ok = true
	Session.paused = false


func after_test() -> void:
	Effort.set_live(false)
	Effort.begin_segment(false)


func test_prepare_sets_segment_state() -> void:
	var game: ProbeGame = auto_free(ProbeGame.new())
	game.prepare(_segment())
	assert_array(game.calls).is_equal(["prepare"])
	assert_str(game.difficulty).is_equal("standard")
	assert_float(game.params.target_watts).is_equal(200.0)
	assert_int(game.rng.seed).is_equal(1234)
	assert_bool(game.was_prepared()).is_true()
	assert_bool(game.playing).is_false()


func test_frames_run_only_while_playing_and_not_paused() -> void:
	var game: ProbeGame = auto_free(ProbeGame.new())
	game.prepare(_segment())
	game._process(0.5)
	game.start()
	game._process(0.5)
	game.set_paused(true)
	game._process(0.5)
	game.set_paused(false)
	game._process(0.5)
	assert_array(game.calls).is_equal(["prepare", "start", "frame", "pause", "resume", "frame"])
	assert_float(game.played_sec).is_equal(1.0)


func test_award_counts_only_while_playing() -> void:
	var game: ProbeGame = auto_free(ProbeGame.new())
	game.prepare(_segment())
	Effort.set_live(true)
	assert_float(game.award(5.0)).is_equal(0.0)
	game.start()
	assert_float(game.award(5.0)).is_greater(0.0)


func test_a_timed_game_cannot_end_itself_early() -> void:
	var game: ProbeGame = auto_free(ProbeGame.new())
	var ended := [0]
	game.ended.connect(func(): ended[0] += 1)
	game.prepare(_segment("timer", 60.0))
	game.start()
	game.end_segment()
	assert_int(ended[0]).is_equal(0)
	assert_bool(game.playing).is_true()
	game.request_finish()  # the default hook ends at once
	assert_int(ended[0]).is_equal(1)
	game.end_segment()
	assert_int(ended[0]).is_equal(1)


func test_a_game_mode_or_open_segment_ends_when_the_game_says() -> void:
	for seg in [_segment("game", 600.0), _segment("game", -1.0)]:
		var game: ProbeGame = auto_free(ProbeGame.new())
		var ended := [0]
		game.ended.connect(func(): ended[0] += 1)
		game.prepare(seg)
		game.start()
		game.end_segment()
		assert_int(ended[0]).is_equal(1)
		assert_bool(game.playing).is_false()


func test_finish_builds_the_contract_result() -> void:
	var game: ProbeGame = auto_free(ProbeGame.new())
	game.prepare(_segment())
	Effort.set_live(true)
	game.start()
	game.played_sec = 30.0
	game.award(12.0)
	game.won = true
	game.stats = {"laps": 3}
	var result := game.finish()
	assert_str(result.game_id).is_equal("probe")
	assert_int(result.score).is_equal(roundi(Effort.score))
	assert_int(result.stars).is_equal(Stars.for_score(Effort.score, game.declared(), "standard"))
	assert_bool(result.won).is_true()
	assert_bool(result.skipped).is_false()
	assert_int(result.stats.laps).is_equal(3)
	assert_float(result.stats.effort_avg).is_equal(snappedf(Effort.average(), 0.01))
	assert_int(result.stats.played_sec).is_equal(30)
	# The wire format round-trips through JSON as the bridge sends it.
	assert_bool(JSON.parse_string(JSON.stringify(result)) is Dictionary).is_true()


func test_won_is_null_by_default() -> void:
	var game: ProbeGame = auto_free(ProbeGame.new())
	game.prepare(_segment())
	assert_that(game.finish().won).is_null()
