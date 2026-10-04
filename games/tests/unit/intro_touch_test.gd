extends GdUnitTestSuite
## Touches on the transitional screens (intro card and countdown, calibration, segment ending,
## the open-ride done panel, the summary) must never end a session: only End, then its
## confirmation, may. Real touches go through the viewport, as on the bike (#35, a rider's
## workout ended when they touched the countdown).

const LocalSession := preload("res://autoload/LocalSession.gd")

var director: SessionDirector
var local: Node
var finished: Array = []  # segment_finished results LocalSession received


func _plan(segments: Array, kind := "circuit") -> Dictionary:
	return {"kind": kind, "plan_id": "test", "difficulty": "standard", "total_sec": 0, "segments": segments}


func _seg(game_id := "demo", role := "work", duration := 60) -> Dictionary:
	return {"game_id": game_id, "role": role, "duration_sec": duration}


func before_test() -> void:
	director = Session.director
	local = Session._local
	director.process_mode = Node.PROCESS_MODE_DISABLED
	local.process_mode = Node.PROCESS_MODE_DISABLED
	finished = local._results
	director._last_recalibrate_msec = -1


func after_test() -> void:
	if Session.active:
		Session.request_end()
		_step(LocalSession.GRACE_SEC + 0.1)
	director.process_mode = Node.PROCESS_MODE_ALWAYS
	local.process_mode = Node.PROCESS_MODE_ALWAYS
	director.summary_screen.visible = false


## Advances both clocks by `seconds`, in small steps.
func _step(seconds: float) -> void:
	var left := seconds
	while left > 0.0:
		var dt := minf(left, 0.25)
		local._process(dt)
		director._process(dt)
		left -= dt


func _start(plan: Dictionary) -> void:
	local.start(plan)
	finished = local._results


## A finger on the screen at `at` (canvas coordinates), through the viewport like the bike: the
## touch and the mouse click Android emulates from it.
func _touch(at: Vector2) -> void:
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.position = at
		touch.pressed = pressed
		get_tree().root.push_input(touch, true)
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = at
		click.global_position = at
		click.pressed = pressed
		get_tree().root.push_input(click, true)


## The intro card's countdown, after the scripted calibration has finished, so nothing but the
## card is on top.
func _to_the_countdown() -> void:
	_step(local.calibration_left_sec() + LocalSession.INTRO_SEC - 1.0)
	assert_int(director.phase).is_equal(SessionDirector.Phase.INTRO)
	assert_int(local.tracker_state()).is_not_equal(InputBus.TRACKER_CALIBRATING)


func test_touching_the_countdown_never_ends_a_timed_just_ride() -> void:
	# The rider's bug: a 20-minute Just Ride is one segment, and a touch on its card ended it.
	_start(_plan([_seg("demo", "free", 1200)], "just_ride"))
	_to_the_countdown()
	for at in [Vector2(960, 540), Vector2(100, 100), Vector2(1800, 1000), Vector2(960, 900)]:
		_touch(at)
	assert_int(finished.size()).is_equal(0)
	assert_bool(Session.active).is_true()
	assert_int(director.phase).is_equal(SessionDirector.Phase.INTRO)
	_step(1.5)
	assert_int(director.phase).is_equal(SessionDirector.Phase.PLAYING)


func test_the_last_segment_of_a_circuit_cannot_be_skipped() -> void:
	_start(_plan([_seg("demo", "warmup"), _seg("demo", "cooldown")]))
	director.skip()
	assert_int(int(Session.segment.index)).is_equal(1)
	assert_bool(director.can_skip()).is_false()
	assert_bool(director.intro_card.skip_button.visible).is_false()
	director.skip()
	assert_int(finished.size()).is_equal(1)
	assert_bool(Session.active).is_true()


func test_a_touch_on_a_circuit_card_skips_nothing_but_the_skip_button_does() -> void:
	_start(_plan([_seg("demo", "warmup"), _seg("demo", "work")]))
	_to_the_countdown()
	_touch(Vector2(960, 540))
	_touch(Vector2(100, 100))
	assert_int(finished.size()).is_equal(0)
	assert_bool(director.intro_card.skip_button.visible).is_true()
	_touch(director.intro_card.skip_button.get_global_rect().get_center())
	assert_int(finished.size()).is_equal(1)
	assert_bool(finished[0].skipped).is_true()
	assert_int(int(Session.segment.index)).is_equal(1)


func test_touching_the_calibration_screen_never_ends_the_session() -> void:
	_start(_plan([_seg("demo", "free", 1200)], "just_ride"))
	_step(0.5)
	assert_int(local.tracker_state()).is_equal(InputBus.TRACKER_CALIBRATING)
	_touch(Vector2(960, 540))
	assert_int(finished.size()).is_equal(0)
	assert_bool(Session.active).is_true()


func test_touching_the_screen_while_a_segment_ends_never_ends_the_session() -> void:
	_start(_plan([_seg("demo", "warmup", 5), _seg("demo", "work")]))
	_step(LocalSession.INTRO_SEC + 5.0 + 0.05)  # segment_ending has been sent
	for at in [Vector2(960, 540), Vector2(100, 100)]:
		_touch(at)
	assert_bool(Session.active).is_true()
	assert_bool(director.pause_overlay.is_confirming()).is_false()


func test_the_open_ride_done_panel_asks_before_ending() -> void:
	_start(_plan([_seg("demo", "free", -1)], "just_ride"))
	_step(local.calibration_left_sec() + LocalSession.INTRO_SEC + 0.1)
	director.game.end_segment()
	assert_bool(director.done_panel.visible).is_true()
	_touch(Vector2(960, 540))  # anywhere but the button
	assert_bool(Session.active).is_true()
	director.end_from_done_panel()
	assert_bool(Session.active).is_true()
	assert_bool(director.pause_overlay.is_confirming()).is_true()
	director.pause_overlay.end_confirmed.emit()
	assert_bool(Session.active).is_false()


func test_touching_the_summary_doesnt_leave_it() -> void:
	_start(_plan([_seg("demo", "free", -1)], "just_ride"))
	Session.request_end()
	assert_int(director.phase).is_equal(SessionDirector.Phase.SUMMARY)
	_touch(Vector2(100, 100))
	_touch(Vector2(1800, 100))
	assert_int(director.phase).is_equal(SessionDirector.Phase.SUMMARY)
	assert_bool(director.summary_screen.visible).is_true()
