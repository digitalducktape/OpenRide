extends GdUnitTestSuite
## Balloon Pump's 2D picture (games/balloon_pump/ART_BIBLE.md, GFX_POLISH.md): the shaders compile,
## the room bakes once per place, the nozzle's balloon grows with the fill, the plunger pumps with
## the cadence and its handle stays above the collar, a tied balloon flies into the bunch, the bunch
## caps its instances and stays clear of the HUD, and no bulb draws over the pump.

const SHADERS := "res://games/balloon_pump/shaders/"

var stage: PumpStage


func before_test() -> void:
	stage = auto_free(PumpStage.new())
	add_child(stage)


func _uniforms(file: String) -> Array:
	var shader: Shader = load(SHADERS + file + ".gdshader")
	return shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return str(u.name))


func test_the_shaders_compile_with_their_uniforms() -> void:
	assert_array(_uniforms("pump_balloon")).contains(["taut", "wobble", "gold", "light_dir", "light_color"])
	assert_array(_uniforms("pump_wedge")).contains(["line", "filling"])
	assert_array(_uniforms("pump_twinkle")).contains(["speed", "depth"])
	assert_array(_uniforms("pump_sea")).contains(["moon_u"])


func test_the_wedge_takes_no_derivative_of_the_wrapping_scale() -> void:
	# t jumps at the scale's start: fwidth(t) drew a stray line on the gauge's face along that ray.
	var shader: Shader = load(SHADERS + "pump_wedge.gdshader")
	assert_bool(shader.code.contains("= fwidth(t)")).is_false()


func test_each_place_bakes_once_and_switches_its_ambient_life() -> void:
	var before := stage.bakes
	stage.set_place(1)
	assert_int(stage.bakes).is_equal(before + 1)
	stage.set_place(1)
	assert_int(stage.bakes).is_equal(before + 1)
	assert_bool(stage._dust.visible).is_true()
	assert_bool(stage._wheel.visible).is_false()
	stage.set_place(2)
	assert_bool(stage._sea.visible).is_true()
	assert_bool(stage._bake.transparent_bg).is_true()
	stage.set_place(0)
	assert_bool(stage._wheel.visible).is_true()
	assert_bool(stage._sea.visible).is_false()
	assert_bool(stage._bake.transparent_bg).is_false()


func test_every_place_has_a_key_light_and_builds() -> void:
	PumpStage.prebuild()
	for i in PumpPlaces.count():
		var l := PumpPlaces.light(i)
		assert_float(l.strength).is_greater(0.0)
		assert_bool(MeshBatch2D.is_built("pump_room_%d" % i)).is_true()


func test_the_nozzle_balloon_grows_with_the_fill() -> void:
	stage.set_balloons("large", "small")
	stage.update_view(1.0, 0.0, false, 0.0, 0.0, 0.3, 80.0)
	var empty: float = stage._nozzle.scale.x
	for i in 120:
		stage.update_view(1.0 / 30.0, 1.0, false, 1.0, 0.6, 0.6, 80.0)
	var full: float = stage._nozzle.scale.x
	assert_float(full).is_equal_approx(PumpArt.BALLOON_RADIUS.large, 0.5)
	assert_float(empty).is_less(full * 0.35)
	# Its top stays under the HUD's status widget (about 160 px down).
	var top: float = PumpPlaces.NOZZLE.y - full * PumpArt.BALLOON_TALL
	assert_float(top).is_greater(160.0)


func test_the_plunger_pumps_with_the_cadence_and_stays_above_the_collar() -> void:
	var ys := []
	for i in 30:
		stage.update_view(1.0 / 30.0, 0.5, false, 1.0, 0.5, 0.4, 60.0)
		ys.append(stage._plunger.global_position.y)
	assert_float(ys.max() - ys.min()).is_greater(PumpStage.STROKE * 0.8)
	# The handle (34 px tall) never sinks into the collar, where it would be clipped.
	assert_float(ys.max() + 17.0).is_less_equal(PumpPlaces.COLLAR.position.y)
	var still := []
	for i in 30:
		stage.update_view(1.0 / 30.0, 0.5, false, 1.0, 0.5, 0.4, 0.0)
		still.append(stage._plunger.position.y)
	assert_float(still.max() - still.min()).is_less(0.001)


func test_the_gauge_needle_turns_with_the_reading() -> void:
	for i in 120:
		stage.update_view(1.0 / 30.0, 0.5, false, 1.0, 0.8, 0.4, 80.0)
	assert_float(stage._needle.rotation).is_equal_approx(PumpArt.gauge_angle(0.8), 0.01)
	assert_float(stage._wedge_mat.get_shader_parameter("line")).is_equal_approx(0.4, 0.001)


func test_a_tied_balloon_flies_into_the_bunch() -> void:
	stage.set_balloons("medium", "small")
	stage.tie_off("medium")
	assert_bool(stage._flyer.visible).is_true()
	assert_int(stage.bunch_count()).is_equal(0)
	for i in roundi(PumpStage.FLIGHT_SEC * 30.0) + 2:
		stage.update_view(1.0 / 30.0, 0.0, false, 0.0, 0.0, 0.3, 80.0, false)
	assert_bool(stage._flyer.visible).is_false()
	assert_int(stage.bunch_count()).is_equal(1)
	assert_int(stage._bunch_mm.visible_instance_count).is_equal(1)
	assert_str(stage._slot_kinds[0]).is_equal("medium")


func test_a_second_tie_lands_the_first_at_once() -> void:
	stage.tie_off("small")
	stage.update_view(0.1, 0.0, false, 0.0, 0.0, 0.3, 80.0, false)
	stage.tie_off("gold")
	assert_int(stage.bunch_count()).is_equal(1)


func test_the_bunch_caps_its_instances() -> void:
	for i in PumpStage.BUNCH_MAX + 5:
		stage.tie_off("small")
	stage.tie_off("small")
	assert_int(stage.bunch_count()).is_equal(PumpStage.BUNCH_MAX + 5)
	assert_int(stage._bunch_mm.visible_instance_count).is_equal(PumpStage.BUNCH_MAX)


func test_every_bunch_balloon_stays_clear_of_the_hud_and_the_screen_edge() -> void:
	for kind in ["small", "large"]:
		for i in PumpStage.BUNCH_MAX:
			var centre: Vector2 = PumpPlaces.TETHER + (stage._slot(i, kind)[1] as Vector2)
			var r: float = PumpArt.BALLOON_RADIUS[kind] * PumpStage.BUNCH_SCALE
			# Under the clock and Pause | End (to about y 310), on the 1920 stage's right part.
			assert_float(centre.y - r * 1.05).override_failure_message("slot %d top %.0f" % [i, centre.y - r]).is_greater(310.0)
			assert_float(centre.x + r).is_less(1920.0 + PumpPlaces.BLEED)
			assert_float(centre.x - r).is_greater(1300.0)


func test_no_bulb_draws_over_the_pump() -> void:
	for i in PumpPlaces.count():
		for wire in PumpPlaces.string_wires(i):
			for p in wire:
				var at: Vector2 = p + Vector2(0, 9)
				if PumpPlaces.BARREL.has_point(at) or at.distance_to(PumpPlaces.GAUGE_AT) < PumpPlaces.GAUGE_R:
					assert_bool(PumpPlaces.behind_hero(at)).is_true()


func test_no_per_frame_redraw() -> void:
	var methods: Array = stage.get_script().get_script_method_list().map(func(m): return m.name)
	assert_bool(methods.has("_process")).is_false()
