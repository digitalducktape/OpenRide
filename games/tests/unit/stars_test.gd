extends GdUnitTestSuite
## Score → stars against per-difficulty thresholds.


func _info(per_minute := false) -> GameInfo:
	var info := GameInfo.new()
	info.star_thresholds = {"easy": [10, 20, 30], "standard": [100, 200, 300], "hard": [1000, 2000, 3000]}
	info.stars_per_minute = per_minute
	return info


func test_counts_thresholds_reached() -> void:
	var info := _info()
	assert_int(Stars.for_score(0, info, "standard")).is_equal(0)
	assert_int(Stars.for_score(99, info, "standard")).is_equal(0)
	assert_int(Stars.for_score(100, info, "standard")).is_equal(1)
	assert_int(Stars.for_score(250, info, "standard")).is_equal(2)
	assert_int(Stars.for_score(300, info, "standard")).is_equal(3)
	assert_int(Stars.for_score(99999, info, "standard")).is_equal(3)


func test_uses_the_segment_difficulty() -> void:
	var info := _info()
	assert_int(Stars.for_score(30, info, "easy")).is_equal(3)
	assert_int(Stars.for_score(300, info, "hard")).is_equal(0)


func test_unknown_difficulty_falls_back_to_standard() -> void:
	assert_int(Stars.for_score(200, _info(), "brutal")).is_equal(2)


func test_per_minute_thresholds_scale_with_played_time() -> void:
	var info := _info(true)
	# 400 points over 2 minutes = 200 per minute.
	assert_int(Stars.for_score(400, info, "standard", 120.0)).is_equal(2)
	# The same score in 30 s = 800 per minute.
	assert_int(Stars.for_score(400, info, "standard", 30.0)).is_equal(3)
	assert_int(Stars.for_score(400, info, "standard", 0.0)).is_equal(0)


func test_count_caps_at_three() -> void:
	assert_int(Stars.count(10, [1, 2, 3, 4])).is_equal(3)
