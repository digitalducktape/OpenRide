extends GdUnitTestSuite
## The Effort autoload: awards count only while live, not paused and with sensors ok.


func before_test() -> void:
	Effort.begin_segment(true)
	Effort.set_live(true)
	InputBus.sensors_ok = true
	Session.paused = false


func after_test() -> void:
	Effort.set_live(false)
	Effort.begin_segment(false)
	Session.paused = false


func test_award_counts_while_live() -> void:
	assert_bool(Effort.is_scoring()).is_true()
	assert_float(Effort.award(10.0)).is_greater(0.0)
	assert_float(Effort.score).is_greater(0.0)


func test_award_is_frozen_when_not_live() -> void:
	Effort.set_live(false)
	assert_float(Effort.award(10.0)).is_equal(0.0)
	assert_float(Effort.score).is_equal(0.0)


func test_award_is_frozen_on_sensor_loss() -> void:
	InputBus.sensors_ok = false
	assert_float(Effort.award(10.0)).is_equal(0.0)
	assert_float(Effort.score).is_equal(0.0)


func test_award_is_frozen_while_paused() -> void:
	Session.paused = true
	assert_float(Effort.award(10.0)).is_equal(0.0)


func test_begin_segment_resets_score_and_flag() -> void:
	Effort.award(10.0)
	Effort.begin_segment(false)
	assert_float(Effort.score).is_equal(0.0)
	assert_bool(Effort.enabled).is_false()
	assert_bool(Effort.is_scoring()).is_false()
	assert_float(Effort.average()).is_equal(1.0)


func test_awarded_signal_reports_the_multiplied_points() -> void:
	var got := []
	var record := func(points: float): got.append(points)
	Effort.awarded.connect(record)
	Effort.award(4.0)
	Effort.set_live(false)
	Effort.award(4.0)
	Effort.awarded.disconnect(record)
	assert_int(got.size()).is_equal(1)
	assert_float(got[0]).is_equal(4.0 * Effort.multiplier)
