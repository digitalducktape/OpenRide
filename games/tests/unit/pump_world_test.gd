extends GdUnitTestSuite
## Balloon Pump's 3D view (games/balloon_pump/ART_BIBLE.md): every shader compiles on the shared
## look, the world is a handful of draws, the nozzle's balloon grows with the fill, a tied
## balloon flies into the bunch, and the bunch caps its instances.

const SHADERS := "res://games/balloon_pump/shaders/"
const LOOK_SHADERS := ["scenery", "balloon", "bunch", "gauge"]

var world: PumpWorld


func before_test() -> void:
	world = auto_free(PumpWorld.new())
	add_child(world)


func _uniforms(file: String) -> Array:
	var shader: Shader = load(SHADERS + file + ".gdshader")
	return shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return str(u.name))


func test_every_world_shader_compiles_on_the_shared_look() -> void:
	for file in LOOK_SHADERS:
		var names := _uniforms(file)
		for p in WorldLook.PARAMS:
			assert_array(names).override_failure_message("%s lacks %s" % [file, p]).contains([String(p)])
	assert_array(_uniforms("gauge")).contains(["needle", "line", "filling"])
	assert_array(_uniforms("balloon")).contains(["body_color", "taut", "wobble", "gold"])
	assert_array(_uniforms("sky")).contains(["top_color", "horizon_color"])


func test_every_hand_lit_material_gets_the_noon_light() -> void:
	var look := PumpWorld.look()
	for mat in world._lit:
		assert_object(mat.get_shader_parameter("haze_color")).is_equal(look[&"haze_color"])
		assert_object(mat.get_shader_parameter("sun_dir")).is_equal(look[&"sun_dir"])
	# The sun is behind the rider, so the stall faces it.
	assert_float(look[&"sun_dir"].z).is_greater(0.0)


func test_the_world_is_a_handful_of_draws() -> void:
	var meshes := world.find_children("*", "GeometryInstance3D", true, false)
	assert_int(meshes.size()).is_less_equal(12)
	var scenery: ArrayMesh = world.get_node("Scenery").mesh
	assert_int(scenery.get_surface_count()).is_equal(1)
	var tris := 0
	for g in meshes:
		if g is MeshInstance3D and g.mesh:
			tris += KartMeshKit.tri_count(g.mesh)
	assert_int(tris).is_less(60000)


func test_the_nozzle_balloon_grows_with_the_fill() -> void:
	world.set_balloons("large", "small")
	world.update_view(1.0, 0.0, false, 0.0, 0.0, 0.3, 80.0)
	var empty: float = world._nozzle.scale.x
	for i in 120:
		world.update_view(1.0 / 30.0, 1.0, false, 1.0, 0.6, 0.6, 80.0)
	var full: float = world._nozzle.scale.x
	assert_float(full).is_equal_approx(PumpMeshes.BALLOON_RADIUS.large, 0.01)
	assert_float(empty).is_less(full * 0.35)
	# The rack shows the next kind, part-blown.
	assert_float(world._rack.scale.x).is_equal_approx(PumpMeshes.BALLOON_RADIUS.small * PumpWorld.RACK_SCALE, 0.001)


func test_the_plunger_pumps_with_the_cadence() -> void:
	var ys := []
	for i in 30:
		world.update_view(1.0 / 30.0, 0.5, false, 1.0, 0.5, 0.4, 60.0)
		ys.append(world._plunger.position.y)
	assert_float(ys.max() - ys.min()).is_greater(PumpWorld.STROKE * 0.8)
	var still := []
	for i in 30:
		world.update_view(1.0 / 30.0, 0.5, false, 1.0, 0.5, 0.4, 0.0)
		still.append(world._plunger.position.y)
	assert_float(still.max() - still.min()).is_less(0.001)


func test_a_tied_balloon_flies_into_the_bunch() -> void:
	world.set_balloons("medium", "small")
	world.tie_off("medium")
	assert_bool(world._flyer.visible).is_true()
	assert_int(world.bunch_count()).is_equal(0)
	for i in roundi(PumpWorld.FLIGHT_SEC * 30.0) + 2:
		world.update_view(1.0 / 30.0, 0.0, false, 0.0, 0.0, 0.3, 80.0, false)
	assert_bool(world._flyer.visible).is_false()
	assert_int(world.bunch_count()).is_equal(1)
	assert_int(world._bunch_mm.visible_instance_count).is_equal(1)
	# It lands in the first slot, in its own kind (the headless renderer keeps no instance data).
	assert_str(world._slot_kinds[0]).is_equal("medium")


func test_a_second_tie_lands_the_first_at_once() -> void:
	world.tie_off("small")
	world.update_view(0.1, 0.0, false, 0.0, 0.0, 0.3, 80.0, false)
	world.tie_off("gold")
	assert_int(world.bunch_count()).is_equal(1)


func test_the_bunch_caps_its_instances() -> void:
	for i in PumpWorld.BUNCH_MAX + 5:
		world.tie_off("small")
	world.tie_off("small")
	assert_int(world.bunch_count()).is_equal(PumpWorld.BUNCH_MAX + 5)
	assert_int(world._bunch_mm.visible_instance_count).is_equal(PumpWorld.BUNCH_MAX)


func test_every_slot_sits_over_the_counter_under_the_hud() -> void:
	for i in PumpWorld.BUNCH_MAX:
		var slot: Array = world._slot(i, "large")
		var p: Vector3 = slot[0].origin
		assert_float(p.y).is_between(2.2, 3.6)
		assert_float(absf(p.x - PumpMeshes.TETHER.x)).is_less(1.6)
		assert_float(slot[1]).is_greater(1.0)
