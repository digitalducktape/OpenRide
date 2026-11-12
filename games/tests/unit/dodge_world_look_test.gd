extends GdUnitTestSuite
## Dodge Ball's look (ART_BIBLE.md, GFX_POLISH.md): one hand light on every world material,
## shared scenery materials (no new draw calls per chunk), the procedural horizon, fence and
## handlebars within their budgets, and the pooled FX written once per burst.

const SCENERY_SHADER := "res://games/dodge_ball/shaders/scenery.gdshader"


func _world() -> DodgeWorld:
	var world: DodgeWorld = auto_free(DodgeWorld.new())
	add_child(world)
	world.set_time_of_day(TimeOfDay.load_preset("day"))
	return world


func _triangles(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var idx = arrays[Mesh.ARRAY_INDEX]
		n += (idx.size() if idx != null else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
	return n


func test_scenery_is_hand_lit_and_shares_materials_across_chunks() -> void:
	var world := _world()
	var first: Mesh = (world._chunks[0].get_node("Trees0") as MultiMeshInstance3D).multimesh.mesh
	var second: Mesh = (world._chunks[1].get_node("Trees0") as MultiMeshInstance3D).multimesh.mesh
	for s in first.get_surface_count():
		var mat := first.surface_get_material(s) as ShaderMaterial
		assert_object(mat).is_not_null()
		assert_str(mat.shader.resource_path).is_equal(SCENERY_SHADER)
		assert_object(second.surface_get_material(s)).is_same(mat)
	# One material per look of surface, not per chunk or per model.
	assert_int(world._scenery_mats.size()).is_less_equal(14)


func test_tug_of_wars_helpers_keep_their_standard_materials() -> void:
	var tree := DodgeWorld._recolor(DodgeWorld._model_mesh("tree_oak.glb"), Color(0.26, 0.48, 0.17))
	var lamp := DodgeWorld._cheap(DodgeWorld._model_mesh("light-curved.glb"))
	assert_object(tree.surface_get_material(0)).is_instanceof(StandardMaterial3D)
	assert_object(lamp.surface_get_material(0)).is_instanceof(StandardMaterial3D)


func test_the_look_reaches_every_world_material() -> void:
	var world := _world()
	var night := TimeOfDay.load_preset("night")
	world.set_time_of_day(night)
	var sun := WorldLook.sun_dir(night.sun_elevation, night.sun_azimuth)
	var mats := world.look_materials()
	assert_int(mats.size()).is_greater(8)
	for mat in mats:
		var got: Vector3 = (mat as ShaderMaterial).get_shader_parameter("sun_dir")
		assert_bool(got.is_equal_approx(sun)).override_failure_message("%s missed the look" % mat.shader.resource_path).is_true()
		assert_float(float((mat as ShaderMaterial).get_shader_parameter("haze_density"))).is_equal_approx(night.fog_density, 0.0001)


func test_look_scales_energy_in_linear_light() -> void:
	var day := TimeOfDay.load_preset("day")
	var look := DodgeWorld.look_for(day)
	var sky: Color = (look.sky_color as Color).srgb_to_linear()
	var want := day.ambient.srgb_to_linear() * day.ambient_energy
	assert_bool(Vector3(sky.r, sky.g, sky.b).is_equal_approx(Vector3(want.r, want.g, want.b))).is_true()
	assert_float(DodgeWorld.look_for(day, false).haze_density).is_equal(0.0)


func test_only_night_has_stars_and_suns_are_small() -> void:
	for name in TimeOfDay.NAMES:
		var tod := TimeOfDay.load_preset(name)
		assert_float(tod.sun_size).is_less_equal(0.04)  # radians: a disc under 4.6° across
		if name != "night":
			assert_float(tod.stars).is_equal(0.0)


func test_horizon_closes_the_view_cheaply() -> void:
	var mesh := DodgeWorld.horizon_mesh()
	var aabb := mesh.get_aabb()
	assert_int(_triangles(mesh)).is_less_equal(2000)
	assert_float(aabb.position.y).is_less_equal(-7.9)  # reaches under the verges' far edges
	assert_float(aabb.end.y).is_between(10.0, 15.0)
	assert_float(-aabb.position.z).is_between(DodgeWorld.HORIZON_HILLS - 1.0, 170.0)  # inside the far plane


func test_fence_runs_on_its_line_and_scenery_keeps_clear() -> void:
	var mesh := DodgeWorld.fence_mesh()
	var line := DodgeBallLogic.ROAD_HALF + DodgeWorld.FENCE_OFFSET
	var aabb := mesh.get_aabb()
	assert_int(_triangles(mesh)).is_less_equal(1300)
	assert_float(aabb.end.x).is_equal_approx(line + 0.06, 0.01)
	# From behind the bike past the far plane, whatever the scroll (it wraps at a post spacing).
	assert_float(aabb.end.z).is_greater(DodgeWorld.FENCE_SPACING)
	assert_float(aabb.position.z + DodgeWorld.FENCE_SPACING).is_less(-170.0)
	assert_float(absf(DodgeWorld.clear_of_fence(line) - line)).is_greater_equal(1.2)
	assert_float(DodgeWorld.clear_of_fence(20.0)).is_equal(20.0)


func test_the_fence_scrolls_and_the_idle_fx_pool_is_hidden() -> void:
	var world := _world()
	var logic := DodgeBallLogic.new(1, "standard", {}, false, "dodge")
	assert_bool(world._fx_mmi.visible).is_false()
	world.distance = 10.0
	world.update_view(0.016, logic, 0.0, 0.0)
	assert_float(world._fence.position.z).is_equal_approx(fmod(10.0, DodgeWorld.FENCE_SPACING), 0.001)
	world.burst(Vector3.ZERO, Color.CYAN, 4, 1.0, 2.0, 0.0, 0.4, 0.04, false)
	assert_bool(world._fx_mmi.visible).is_true()
	world.update_view(0.5, logic, 0.0, 0.0)
	assert_bool(world._fx_mmi.visible).is_false()


func test_handlebars_are_one_mesh() -> void:
	var world := _world()
	var meshes := 0
	for node in world.camera.get_children():
		if node is MeshInstance3D:
			meshes += 1
	assert_int(meshes).is_equal(2)  # the bars and the shield
	var bars := world.camera.get_node("Bars") as MeshInstance3D
	assert_int(bars.mesh.get_surface_count()).is_equal(1)
	assert_int(bars.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_COLOR).is_not_equal(0)


func test_lamp_head_is_marked_self_lit() -> void:
	var lamp := DodgeWorld._glow_tip(DodgeWorld._model_mesh("light-curved.glb"))
	var colours: PackedColorArray = lamp.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lit := 0
	for c in colours:
		if c.a > 0.5:
			lit += 1
	assert_int(lit).is_greater(0)
	assert_int(lit).is_less(colours.size() / 4)


func test_fx_instances_pack_their_motion_and_never_fly_at_the_rider() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 50:
		var xf := DodgeWorld.fx_instance(rng, Vector3(1, 0.5, -3), 2.0, 4.0, -9.0, 0.6, 0.08, i % 2 == 0)
		assert_vector(xf.origin).is_equal(Vector3(1, 0.5, -3))
		assert_float(xf.basis.x.length()).is_between(1.999, 4.001)  # speed
		assert_float(xf.basis.x.y).is_greater(0.0)  # up and out
		assert_float(xf.basis.x.z / xf.basis.x.length()).is_less_equal(0.3001)  # never straight at the face
		assert_float(xf.basis.y.x).is_equal(-9.0)  # gravity
		assert_float(xf.basis.y.y).is_between(0.45, 0.6)  # life
		assert_float(xf.basis.z.x).is_equal(1.0 if i % 2 == 0 else 0.0)  # chunk or streak


func test_bursts_take_pool_slots_in_turn_and_wrap() -> void:
	var world := _world()
	world.burst(Vector3(1, 0.5, -3), Color.RED, 10, 2.0, 4.0, -9.0, 0.6, 0.08, true)
	assert_int(world._fx_next).is_equal(10)
	world.burst(Vector3.ZERO, Color.CYAN, DodgeWorld.FX_POOL, 1.0, 2.0, 0.0, 0.4, 0.04, false)
	assert_int(world._fx_next).is_equal(10)
	assert_int(world._fx_mm.instance_count).is_equal(DodgeWorld.FX_POOL)


func test_bouncing_balls_squash_on_landing_and_their_shadows_tighten() -> void:
	assert_float(DodgeWorld.squash_for(0.0)).is_equal_approx(0.14, 0.001)
	assert_float(DodgeWorld.squash_for(0.2)).is_equal(0.0)
	assert_float(DodgeWorld.shadow_scale(0.0)).is_less(DodgeWorld.shadow_scale(DodgeWorld.BOUNCE_HEIGHT))
