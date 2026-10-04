extends GdUnitTestSuite
## The effort multiplier's maths (EffortMeter): the curve, the grinding guard, `effort: false`
## and effort_avg.


func test_curve_is_flat_up_to_30_percent() -> void:
	for resistance in [0.0, 10.0, 29.9, 30.0]:
		assert_float(EffortMeter.multiplier_for(resistance, 90.0, true)).is_equal(1.0)


func test_curve_rises_linearly_from_30_to_60_percent() -> void:
	assert_float(EffortMeter.multiplier_for(36.0, 90.0, true)).is_equal_approx(1.1, 0.0001)
	assert_float(EffortMeter.multiplier_for(45.0, 90.0, true)).is_equal_approx(1.25, 0.0001)
	assert_float(EffortMeter.multiplier_for(48.0, 90.0, true)).is_equal_approx(1.3, 0.0001)
	assert_float(EffortMeter.multiplier_for(54.0, 90.0, true)).is_equal_approx(1.4, 0.0001)


func test_curve_caps_at_1_5_from_60_percent() -> void:
	for resistance in [60.0, 75.0, 100.0]:
		assert_float(EffortMeter.multiplier_for(resistance, 90.0, true)).is_equal(1.5)


func test_grinding_guard_59_vs_60_rpm() -> void:
	assert_float(EffortMeter.multiplier_for(60.0, 59.0, true)).is_equal(1.0)
	assert_float(EffortMeter.multiplier_for(60.0, 59.99, true)).is_equal(1.0)
	assert_float(EffortMeter.multiplier_for(60.0, 60.0, true)).is_equal(1.5)
	assert_float(EffortMeter.multiplier_for(45.0, 60.0, true)).is_equal_approx(1.25, 0.0001)


func test_always_1_when_effort_is_false() -> void:
	for resistance in [0.0, 45.0, 60.0, 100.0]:
		for cadence in [0.0, 59.0, 60.0, 120.0]:
			assert_float(EffortMeter.multiplier_for(resistance, cadence, false)).is_equal(1.0)


func test_award_multiplies_by_the_latest_sample() -> void:
	var meter := EffortMeter.new()
	meter.reset(true)
	meter.sample(0.1, 60.0, 90.0)
	assert_float(meter.award(10.0)).is_equal(15.0)
	meter.sample(0.1, 30.0, 90.0)
	assert_float(meter.award(10.0)).is_equal(10.0)
	assert_float(meter.score).is_equal(25.0)


func test_award_is_plain_when_effort_is_false() -> void:
	var meter := EffortMeter.new()
	meter.reset(false)
	meter.sample(0.1, 80.0, 100.0)
	assert_float(meter.award(10.0)).is_equal(10.0)
	assert_float(meter.average()).is_equal(1.0)


func test_effort_avg_is_time_weighted() -> void:
	var meter := EffortMeter.new()
	meter.reset(true)
	meter.sample(3.0, 60.0, 90.0)  # 1.5× for 3 s
	meter.sample(1.0, 20.0, 90.0)  # 1.0× for 1 s
	assert_float(meter.average()).is_equal_approx(1.375, 0.0001)


func test_effort_avg_counts_grinding_as_1() -> void:
	var meter := EffortMeter.new()
	meter.reset(true)
	meter.sample(1.0, 60.0, 59.0)
	meter.sample(1.0, 60.0, 60.0)
	assert_float(meter.average()).is_equal_approx(1.25, 0.0001)


func test_effort_avg_is_1_before_any_sample_and_resets() -> void:
	var meter := EffortMeter.new()
	meter.reset(true)
	assert_float(meter.average()).is_equal(1.0)
	meter.sample(2.0, 60.0, 90.0)
	meter.award(4.0)
	meter.reset(true)
	assert_float(meter.average()).is_equal(1.0)
	assert_float(meter.score).is_equal(0.0)
	assert_float(meter.multiplier).is_equal(1.0)
