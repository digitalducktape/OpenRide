extends GdUnitTestSuite
## Balloon Pump's layout against the frame, the ground and the HUD (the rider, 2026-11-02: "the
## Ferris wheel sits in the ground; the pump handle is cut off"). Like safe_scene_test: the key
## elements' boxes at their extremes (the handle at both ends of its stroke, the largest balloon
## full, every bunch slot at both ends of the sway, the wheel turning) stay inside the 1920 x 1080
## stage, clear of every HUD panel with its widest contents, and backdrop props stand on or above
## their horizon.

const STAGE := Rect2(0, 0, 1920, 1080)
const PumpGame := preload("res://games/balloon_pump/BalloonPump.gd")

var hud: Hud
var stage: PumpStage


func before_test() -> void:
	hud = auto_free(Hud.new())
	add_child(hud)
	var info := GameInfo.new()
	info.title = "Balloon Pump"
	info.id = "balloon_pump"
	info.tracker_mode = "off"
	hud.setup(info, {"role": "work", "index": 3, "count": 9})
	hud.set_skin(PumpGame.look.hud_skin())
	var status := PumpStatus.new(PumpGame.look)
	hud.add_widget(status)
	status.set_state(1.0, 0.7, "filling")
	status.set_count(999)
	status.set_race(10, 10, 119.0)
	hud.metrics.refresh(118, 1888, 100)
	hud.score.set_value("99999")
	Effort.begin_segment(true)  # the effort badge: the ride panel at its widest
	stage = auto_free(PumpStage.new())
	add_child(stage)


func after_test() -> void:
	hud.clear_skin()


func _panels() -> Array[Rect2]:
	await get_tree().process_frame
	await get_tree().process_frame
	var out: Array[Rect2] = []
	for c: Control in hud.find_children("*", "PanelContainer", true, false):
		if c.is_visible_in_tree() and c.size.x > 0.0:
			out.append(c.get_global_rect())
	for c: Control in hud.find_children("*", "Button", true, false):
		if c.is_visible_in_tree():
			out.append(c.get_global_rect())
	return out


func _clear_of(name: String, r: Rect2, panels: Array[Rect2]) -> void:
	assert_bool(STAGE.encloses(r)).override_failure_message("%s %s leaves the stage" % [name, r]).is_true()
	for p in panels:
		assert_bool(r.intersects(p)).override_failure_message("%s %s is under a HUD panel %s" % [name, r, p]).is_false()


func test_the_pump_handle_is_never_cut_off() -> void:
	var panels := await _panels()
	assert_int(panels.size()).is_greater_equal(4)
	for down in [0.0, 0.5, 1.0]:
		var h := PumpStage.handle_rect(down)
		_clear_of("handle at %.1f" % down, h, panels)
		# Its grips stay above the collar, where the rod is clipped.
		assert_float(h.end.y).is_less_equal(PumpPlaces.COLLAR.position.y)


func test_the_largest_balloon_full_is_never_cut_off() -> void:
	var panels := await _panels()
	for kind in PumpArt.BALLOON_RADIUS:
		_clear_of("%s balloon" % kind, PumpStage.balloon_rect(kind), panels)


func test_the_bunch_is_never_cut_off() -> void:
	var panels := await _panels()
	var rects := stage.bunch_rects()
	for i in rects.size():
		_clear_of("bunch slot %d" % (i / 2), rects[i], panels)


func test_the_pump_its_gauge_and_its_stand_stay_on_the_stage() -> void:
	var panels := await _panels()
	var gauge := Rect2(PumpPlaces.GAUGE_AT - Vector2.ONE * (PumpPlaces.GAUGE_R + 22.0), Vector2.ONE * (PumpPlaces.GAUGE_R + 22.0) * 2.0)
	_clear_of("gauge", gauge, panels)
	_clear_of("barrel", PumpPlaces.BARREL.grow_individual(10, 70, 10, 0), panels)
	_clear_of("plinth", PumpPlaces.PLINTH.grow_individual(0, 20, 0, 8), panels)
	_clear_of("basket", PumpPlaces.BASKET.grow(30), panels)


func test_the_ferris_wheel_stands_on_its_horizon_and_clears_the_hud() -> void:
	var panels := await _panels()
	var w := PumpStage.wheel_rect()
	_clear_of("wheel", w, panels)
	# Its lowest car clears the ground line (it stands on the horizon, far off).
	assert_float(w.end.y).override_failure_message("the wheel reaches y %.0f" % w.end.y).is_less_equal(PumpPlaces.FAIR_HORIZON + 8.0)
	# And it never reaches the pump.
	assert_bool(w.intersects(PumpPlaces.BARREL.grow(20))).is_false()


func test_a_tied_balloon_flies_under_the_hud() -> void:
	var panels := await _panels()
	var from := Transform2D(0.0, Vector2.ONE * PumpArt.BALLOON_RADIUS.large, 0.0, PumpPlaces.NOZZLE)
	for slot in PumpStage.BUNCH_MAX:
		for step in 11:
			var x := stage.flight_at(from, slot, "large", step / 10.0)
			var r := x.get_scale().x
			# The balloon's quad, upright (the flight's slight turn only narrows it).
			var box := Rect2(x.origin - Vector2(r, r * PumpArt.BALLOON_TALL), Vector2(r * 2.0, r * PumpArt.BALLOON_TALL))
			_clear_of("slot %d flight %.1f" % [slot, step / 10.0], box, panels)


func test_confetti_stays_under_the_hud() -> void:
	var panels := await _panels()
	var lowest_panel := 0.0
	for p in panels:
		lowest_panel = maxf(lowest_panel, p.end.y)
	for at in [PumpStage.TIE_BURST, PumpStage.WIN_BURST]:
		for big in [false, true]:
			var top := PumpStage.burst_top(at, big)
			assert_float(top).override_failure_message("a burst at %s reaches %.0f" % [at, top]).is_greater(lowest_panel)


func test_the_big_top_valance_clears_the_handle() -> void:
	# The rail, its scallops and fringe end above the handle at the top of its stroke.
	assert_float(PumpStage.handle_rect(0.0).position.y).is_greater(PumpPlaces.VALANCE_Y + 56.0)
	# The rigging ropes stand clear of the pump.
	for rx in PumpPlaces.BIGTOP_ROPES:
		assert_bool(PumpPlaces.BARREL.grow(150).has_point(Vector2(rx, 600))).is_false()


func test_the_pier_moon_clears_the_hud() -> void:
	var panels := await _panels()
	_clear_of("moon", Rect2(PumpPlaces.MOON - Vector2(60, 60), Vector2(120, 120)), panels)
