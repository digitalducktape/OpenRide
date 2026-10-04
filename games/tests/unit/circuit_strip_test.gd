extends GdUnitTestSuite
## The circuit progress strip (#37): which segments it shows, what it says, and that it fits.

const PLAN := {"kind": "circuit", "total_sec": 1120, "segments": [
	{"game_id": "cadence_karaoke", "role": "warmup", "duration_sec": 180},
	{"game_id": "tug_of_war", "role": "work", "duration_sec": 60},
	{"game_id": "safe_cracker", "role": "recovery", "duration_sec": 90},
	{"game_id": "dodge_ball", "role": "work", "duration_sec": 90},
	{"game_id": "cadence_karaoke", "role": "cooldown", "duration_sec": 180},
]}


func test_a_circuit_shows_the_strip_and_a_just_ride_hides_it() -> void:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	hud.set_plan(PLAN)
	assert_bool(hud.circuit_strip.visible).is_true()
	assert_int(hud.circuit_strip.segments.size()).is_equal(5)
	hud.set_plan({"kind": "just_ride", "segments": [{"game_id": "dodge_ball", "role": "free", "duration_sec": -1}]})
	assert_bool(hud.circuit_strip.visible).is_false()


func test_the_remaining_time_counts_the_rest_of_the_segment_and_every_card() -> void:
	var strip: CircuitStrip = auto_free(CircuitStrip.new())
	add_child(strip)
	strip.set_plan(PLAN)
	strip.set_segment(1, 60.0)
	# 20 s left of the Tug of War, then Safe Cracker, Dodge Ball and the cool-down, each after a 10 s card.
	assert_float(strip.remaining_sec(20.0)).is_equal(20.0 + (90 + 10) + (90 + 10) + (180 + 10))
	strip.set_segment(4, 180.0)
	assert_float(strip.remaining_sec(45.0)).is_equal(45.0)


func test_the_label_says_where_you_are_and_how_long_is_left() -> void:
	var strip: CircuitStrip = auto_free(CircuitStrip.new())
	add_child(strip)
	strip.set_plan(PLAN)
	strip.set_segment(2, 90.0)
	assert_str(strip._label.text).starts_with("3 of 5")
	assert_str(strip._label.text).ends_with("left")


func test_the_strip_fits_above_the_games_widgets_without_overlap() -> void:
	var hud: Hud = auto_free(Hud.new())
	add_child(hud)
	var info := GameInfo.new()
	info.id = "tug_of_war"
	hud.set_plan(PLAN)
	hud.setup(info, {"role": "work", "index": 1, "count": 5, "duration_sec": 60})
	var widget := TugStatus.new()
	hud.add_widget(widget)
	widget.set_state(120.0, 120.0, 0.0, "", "Round 1 · 0-0 · Rust Mule", "Keep pedaling")
	await await_idle_frame()
	await await_idle_frame()
	var strip_rect := hud.circuit_strip.get_global_rect()
	var widget_rect := widget.get_global_rect()
	assert_bool(strip_rect.intersects(widget_rect)).is_false()
	# And it stays clear of the side panels and inside the screen.
	assert_bool(strip_rect.intersects(hud.ride_panel.get_global_rect())).is_false()
	assert_bool(strip_rect.intersects(hud.clock_panel.get_global_rect())).is_false()
	assert_bool(Rect2(0, 0, 1920, 1080).encloses(strip_rect)).is_true()
