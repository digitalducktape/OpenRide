extends GdUnitTestSuite
## InputBus's controller fields (#68): frame indices 13-15, steering, and Use item presses.

var _items := 0


func before_test() -> void:
	_items = 0
	InputBus._item_presses = -1
	InputBus.controller_item.connect(_count_item)


func after_test() -> void:
	InputBus.controller_item.disconnect(_count_item)
	InputBus._item_presses = -1
	InputBus.controller_steering = false
	InputBus.controller_steer = 0.0
	InputBus.lean_x = 0.0


func _count_item() -> void:
	_items += 1


func _frame(steer: float, steering: bool, presses: int) -> PackedFloat64Array:
	var f := PackedFloat64Array()
	f.resize(InputBus.I_CONTROLLER_ITEM_PRESSES + 1)
	f[InputBus.I_CONTROLLER_STEER] = steer
	f[InputBus.I_CONTROLLER_STEERING] = 1.0 if steering else 0.0
	f[InputBus.I_CONTROLLER_ITEM_PRESSES] = presses
	return f


func test_indices_follow_the_contract() -> void:
	assert_int(InputBus.I_CONTROLLER_STEER).is_equal(13)
	assert_int(InputBus.I_CONTROLLER_STEERING).is_equal(14)
	assert_int(InputBus.I_CONTROLLER_ITEM_PRESSES).is_equal(15)


func test_a_steering_controller_steers_instead_of_lean() -> void:
	InputBus.lean_x = -0.4
	InputBus._read_controller(_frame(0.75, true, 0))
	assert_bool(InputBus.controller_steering).is_true()
	assert_float(InputBus.steer_x()).is_equal_approx(0.75, 0.0001)


func test_no_steering_controller_keeps_head_lean() -> void:
	InputBus.lean_x = -0.4
	InputBus._read_controller(_frame(0.75, false, 0))
	assert_bool(InputBus.controller_steering).is_false()
	assert_float(InputBus.steer_x()).is_equal_approx(-0.4, 0.0001)


func test_a_frame_without_the_fields_has_no_controller() -> void:
	var old := PackedFloat64Array()
	old.resize(InputBus.I_RIDER_MUSIC + 1)
	InputBus._read_controller(old)
	assert_bool(InputBus.controller_steering).is_false()


func test_item_presses_fire_once_per_press_after_the_first_frame() -> void:
	InputBus._item_presses = -1  # the simulator's own frames may have run since before_test
	InputBus._read_controller(_frame(0.0, false, 7))  # the baseline: earlier presses aren't replayed
	assert_int(_items).is_equal(0)
	InputBus._read_controller(_frame(0.0, false, 8))
	assert_int(_items).is_equal(1)
	InputBus._read_controller(_frame(0.0, false, 8))
	assert_int(_items).is_equal(1)
