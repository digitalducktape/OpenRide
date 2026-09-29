extends GdUnitTestSuite
## SessionDirector against the desktop's LocalSession: scene loading, the intro card and skip,
## gameplay, pause, ending, end-session and the summary. Both clocks are stepped by hand.

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


func test_a_segment_loads_its_game_with_the_intro_card() -> void:
	_start(_plan([_seg()]))
	assert_int(director.phase).is_equal(SessionDirector.Phase.INTRO)
	assert_object(director.game).is_not_null()
	assert_str(director.game.game_id).is_equal("demo")
	assert_object(get_tree().current_scene).is_same(director.game)
	assert_bool(director.intro_card.visible).is_true()
	assert_bool(director.hud.visible).is_false()
	assert_bool(Effort.is_scoring()).is_false()
	assert_bool(Effort.enabled).is_true()  # a work segment
	assert_str(Session.tracker_mode).is_equal("lean_x")
	assert_int(local.tracker_state()).is_equal(InputBus.TRACKER_CALIBRATING)  # the camera mode calibrates


func test_gameplay_starts_when_the_intro_ends() -> void:
	_start(_plan([_seg()]))
	_step(LocalSession.INTRO_SEC + 0.1)
	assert_int(director.phase).is_equal(SessionDirector.Phase.PLAYING)
	assert_bool(director.intro_card.visible).is_false()
	assert_bool(director.hud.visible).is_true()
	assert_bool(director.game.playing).is_true()
	assert_bool(Effort.is_scoring()).is_true()


func test_the_timer_ends_the_segment_with_stars_in_the_result() -> void:
	_start(_plan([_seg("demo", "work", 5)]))
	_step(LocalSession.INTRO_SEC + 0.1)
	director.game.played_sec = 60.0
	Effort.award(2000.0)
	_step(5.1)  # segment_ending: the demo ends at once
	assert_int(finished.size()).is_equal(1)
	var result: Dictionary = finished[0]
	assert_str(result.game_id).is_equal("demo")
	assert_bool(result.skipped).is_false()
	assert_int(result.stars).is_between(1, 3)
	assert_bool(result.stats.has("effort_avg")).is_true()
	assert_bool(Session.active).is_false()  # the last timed segment: the session finished


func test_tapping_the_card_skips_to_the_next_segment() -> void:
	_start(_plan([_seg("demo", "warmup"), _seg("demo", "work")]))
	assert_bool(director.can_skip()).is_true()
	var first := director.game
	director.skip()
	assert_int(finished.size()).is_equal(1)
	assert_bool(finished[0].skipped).is_true()
	assert_int(finished[0].stars).is_equal(0)
	assert_int(int(Session.segment.index)).is_equal(1)
	assert_object(director.game).is_not_same(first)
	assert_int(director.phase).is_equal(SessionDirector.Phase.INTRO)
	# The previous (skipped) result shows on the new card; calibration was asked for only once.
	assert_bool(director.intro_card._previous.visible).is_true()


func test_skipping_during_gameplay_does_nothing() -> void:
	_start(_plan([_seg("demo", "warmup"), _seg("demo", "work")]))
	_step(LocalSession.INTRO_SEC + 0.1)
	director.skip()
	assert_int(finished.size()).is_equal(0)


func test_the_only_segment_of_an_open_ride_cannot_be_skipped() -> void:
	_start(_plan([_seg("demo", "free", -1)], "just_ride"))
	assert_bool(director.can_skip()).is_false()
	assert_bool(director.intro_card._skip_hint.visible).is_false()
	director.skip()
	assert_int(finished.size()).is_equal(0)


func test_pause_and_resume() -> void:
	_start(_plan([_seg()]))
	_step(LocalSession.INTRO_SEC + 0.1)
	director.hud.pause_pressed.emit()
	assert_bool(Session.paused).is_true()
	assert_bool(director.game.paused).is_true()
	assert_bool(director.pause_overlay.visible).is_true()
	assert_bool(Effort.is_scoring()).is_false()
	var played: float = director.game.played_sec
	_step(3.0)
	assert_float(director.game.played_sec).is_equal(played)
	director.pause_overlay.resume_pressed.emit()
	assert_bool(Session.paused).is_false()
	assert_bool(director.game.paused).is_false()
	assert_bool(director.pause_overlay.visible).is_false()


func test_pause_freezes_the_intro_countdown() -> void:
	_start(_plan([_seg()]))
	Session.request_pause()
	_step(LocalSession.INTRO_SEC + 1.0)
	assert_int(director.phase).is_equal(SessionDirector.Phase.INTRO)
	Session.request_resume()
	_step(LocalSession.INTRO_SEC + 0.1)
	assert_int(director.phase).is_equal(SessionDirector.Phase.PLAYING)


func test_end_asks_for_confirmation_then_shows_the_summary() -> void:
	_start(_plan([_seg("demo", "free", -1)], "just_ride"))
	_step(LocalSession.INTRO_SEC + 0.1)
	director.hud.end_pressed.emit()
	assert_bool(director.pause_overlay.is_confirming()).is_true()
	assert_bool(Session.active).is_true()
	director.pause_overlay.end_confirmed.emit()
	assert_bool(Session.active).is_false()
	assert_int(director.phase).is_equal(SessionDirector.Phase.SUMMARY)
	assert_bool(director.summary_screen.visible).is_true()
	assert_bool(director.hud.visible).is_false()
	assert_object(director.game).is_null()
	assert_str(Session.tracker_mode).is_equal("off")
	assert_int(Session.summary.results.size()).is_equal(1)
	assert_bool(Session.summary.results[0].skipped).is_false()


func test_ending_on_the_intro_card_records_the_game_as_skipped() -> void:
	_start(_plan([_seg("demo", "free", -1)], "just_ride"))
	Session.request_end()
	assert_bool(Session.active).is_false()
	assert_bool(Session.summary.results[0].skipped).is_true()


func test_summary_done_exits_and_the_desktop_starts_again() -> void:
	_start(_plan([_seg("demo", "free", -1)], "just_ride"))
	Session.request_end()
	assert_bool(director.summary_screen.visible).is_true()
	director.summary_screen.done_pressed.emit()
	assert_bool(Session.active).is_true()  # request_exit restarts the local plan
	assert_bool(director.summary_screen.visible).is_false()
	assert_int(director.phase).is_equal(SessionDirector.Phase.INTRO)


func test_an_open_ride_whose_game_ended_offers_to_end_the_session() -> void:
	_start(_plan([_seg("demo", "free", -1)], "just_ride"))
	_step(LocalSession.INTRO_SEC + 0.1)
	director.game.end_segment()  # an open-ended segment may end itself
	assert_int(finished.size()).is_equal(1)
	assert_bool(Session.active).is_true()
	assert_bool(director.done_panel.visible).is_true()


func test_one_calibration_per_session_start() -> void:
	# The session side (TrackerLink, or LocalSession here) calibrates on the first camera mode;
	# the director must not ask for a second, forced one.
	var before: int = local.calibrations_started
	_start(_plan([_seg("demo", "warmup"), _seg("demo", "work"), _seg("demo", "cooldown")]))
	assert_int(local.calibrations_started - before).is_equal(1)
	assert_str(director.calibrated_mode).is_equal("lean_x")
	director.skip()
	director.skip()
	assert_int(int(Session.segment.index)).is_equal(2)
	assert_int(local.calibrations_started - before).is_equal(1)


func test_the_centre_alone_is_retaken_once_extremes_exist() -> void:
	_start(_plan([_seg()]))
	_step(8.0)  # a full calibration, if this process had no extremes yet
	assert_bool(local.is_calibrating()).is_false()
	_start(_plan([_seg()]))
	assert_int(local.calibration_step_count()).is_equal(1)
	_step(3.5)
	assert_str(Session.calibration.step).is_equal("centre")
	assert_int(Session.calibration.step_count).is_equal(1)


func test_recalibrate_runs_every_step() -> void:
	_start(_plan([_seg()]))
	_step(8.0)
	InputBus.tracker_state = InputBus.TRACKER_TRACKING
	var before: int = local.calibrations_started
	director.hud.recalibrate_pressed.emit()
	assert_int(local.calibrations_started - before).is_equal(1)
	assert_int(local.calibration_step_count()).is_equal(3)


func test_recalibrate_is_debounced() -> void:
	_start(_plan([_seg()]))
	_step(8.0)
	InputBus.tracker_state = InputBus.TRACKER_TRACKING
	var before: int = local.calibrations_started
	director.hud.recalibrate_pressed.emit()
	InputBus.tracker_state = InputBus.TRACKER_TRACKING  # as if the new run hadn't shown yet
	director.hud.recalibrate_pressed.emit()  # a double tap
	assert_int(local.calibrations_started - before).is_equal(1)
	director._last_recalibrate_msec -= SessionDirector.RECALIBRATE_DEBOUNCE_MSEC + 1
	director.hud.recalibrate_pressed.emit()
	assert_int(local.calibrations_started - before).is_equal(2)


func test_recalibrate_never_restarts_a_running_calibration() -> void:
	_start(_plan([_seg()]))
	InputBus.tracker_state = InputBus.TRACKER_CALIBRATING
	var before: int = local.calibrations_started
	director.hud.recalibrate_pressed.emit()
	director.calibration.recalibrate_requested.emit()
	assert_int(local.calibrations_started - before).is_equal(0)


func test_overlay_taps_count_only_when_no_calibration_runs() -> void:
	_start(_plan([_seg()]))
	var overlay := director.calibration
	var taps := [0]
	var count := func(): taps[0] += 1
	overlay.recalibrate_requested.connect(count)
	var tap := InputEventMouseButton.new()
	tap.button_index = MOUSE_BUTTON_LEFT
	tap.pressed = true
	for shown in ["calibrating", "needs", "lost", "unavailable"]:
		overlay._show(shown)
		overlay._on_gui_input(tap)
	overlay.recalibrate_requested.disconnect(count)
	assert_int(taps[0]).is_equal(3)  # not while calibrating


func test_a_lean_2d_game_after_lean_x_asks_for_depth_once() -> void:
	_start(_plan([_seg()]))
	var depth := GameInfo.new()
	depth.tracker_mode = "lean_2d"
	var before: int = local.calibrations_started
	director._calibrate_for(depth)
	assert_int(local.calibrations_started - before).is_equal(1)
	assert_int(local.calibration_step_count()).is_equal(5)
	director._calibrate_for(depth)
	director._calibrate_for(GameRegistry.info("demo"))
	assert_int(local.calibrations_started - before).is_equal(1)
	assert_str(director.calibrated_mode).is_equal("lean_2d")


func test_the_overlay_draws_every_calibration_field() -> void:
	_start(_plan([_seg()]))
	var overlay := director.calibration
	Session._on_calibration_progress("left", 0.5, 1, 3, 2, "unstable")
	overlay._process(0.0)
	assert_str(overlay.mode).is_equal("calibrating")
	assert_str(overlay._prompt.text).is_equal("Lean comfortably left")
	assert_str(overlay._detail.text).is_equal("CALIBRATING  ·  STEP 2 OF 3  ·  TRY 2")
	assert_str(overlay._retry.text).is_equal("Hold still for a moment")
	assert_float(overlay._bar.size.x).is_equal(450.0)
	Session._on_calibration_progress("centre", 0.4, 0, 1, 1, "")
	overlay._process(0.0)
	assert_str(overlay._detail.text).is_equal("CALIBRATING")  # centre only: no step count
	assert_str(overlay._count.text).is_equal("2")
	assert_str(overlay._retry.text).is_empty()


func test_the_overlay_reports_an_unavailable_camera() -> void:
	_start(_plan([_seg()]))
	var overlay := director.calibration
	Session._on_calibration_progress("centre", 0.2, 0, 3, 2, "no_face")
	Session.calibration.at_msec = 0  # long ago
	InputBus.tracker_state = InputBus.TRACKER_OFF  # as Kotlin reports after two failed tries
	overlay._process(0.0)
	assert_str(overlay.mode).is_equal("unavailable")
	assert_bool(overlay._strip.visible).is_true()


func test_an_unknown_game_is_skipped() -> void:
	_start(_plan([_seg("no_such_game"), _seg("demo")]))
	assert_int(finished.size()).is_equal(1)
	assert_bool(finished[0].skipped).is_true()
	assert_str(finished[0].game_id).is_equal("no_such_game")
	assert_str(director.game.game_id).is_equal("demo")
