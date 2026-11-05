extends GdUnitTestSuite
## The Pull's 3D view (#79): its shaders compile, the statics are built once per sled, the
## per-frame parts follow the logic (the rig, the sled, the weight box, the chain, the sky), the
## best flag, and the warm-up idles afterwards.

const SHADERS := ["track", "scenery", "sky", "crowd", "mirror", "glow"]

var world: PullWorld


func before_test() -> void:
	world = PullWorld.new()
	add_child(world)


func after_test() -> void:
	world.free()


func test_every_shader_compiles() -> void:
	for name in SHADERS:
		var shader := load("res://games/the_pull/shaders/%s.gdshader" % name) as Shader
		assert_object(shader).override_failure_message(name).is_not_null()
		var mat := ShaderMaterial.new()
		mat.shader = shader
		# A shader that failed to compile exposes no uniforms.
		assert_bool(shader.get_shader_uniform_list().size() > 0 or name == "mirror").override_failure_message(name).is_true()


func test_the_statics_are_one_mesh_and_the_full_pull_line_moves_with_the_sled() -> void:
	assert_int(world.find_children("Scenery", "MeshInstance3D", true, false).size()).is_equal(1)
	world.build(300.0, 0.0)
	await await_idle_frame()
	assert_int(world.find_children("Scenery", "MeshInstance3D", true, false).size()).is_equal(1)
	var banner: Label3D = world.find_children("*", "Label3D", true, false).filter(
		func(l: Label3D) -> bool: return l.text == "FULL PULL")[0]
	assert_float(banner.position.z).is_equal_approx(-300.0, 0.2)


func test_the_rig_sled_box_and_sky_follow_the_pull() -> void:
	world.update_view(1.0 / 60.0, 120.0, 2.0, 0.0, 80.0, 0.0, 0.0, 0.0)
	var rig: Node3D = world.get_node("Rig")
	var sled: Node3D = world.get_node("Sled")
	var box: Node3D = sled.get_node("WeightBox")
	assert_float(rig.position.z).is_equal_approx(-120.0, 0.05)
	assert_float(sled.position.z).is_equal_approx(-120.0 + PullWorld.SLED_GAP, 0.05)
	assert_float(box.position.z).is_equal_approx(PullWorld.BOX_REAR, 0.001)
	world.update_view(1.0 / 60.0, 120.0, 2.0, 1.0, 80.0, 0.0, 0.0, 0.0)
	assert_float(box.position.z).is_equal_approx(PullWorld.BOX_FRONT, 0.001)
	assert_float(world.get_node("Sky").position.z).is_equal_approx(rig.position.z, 0.001)
	# The chain's links (their transforms live in the RenderingServer, which a headless run
	# doesn't keep, so only the count is checked here; the captures show them).
	var chain: MultiMesh = (world.get_node("Chain") as MultiMeshInstance3D).multimesh
	assert_int(chain.instance_count).is_equal(PullWorld.CHAIN_LINKS)


func test_the_look_back_turns_the_camera_to_the_sled() -> void:
	world.update_view(1.0 / 60.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0)
	assert_float(world.camera.rotation_degrees.y).is_equal_approx(-PullWorld.LOOK_BACK_YAW, 0.01)
	world.update_view(1.0 / 60.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0)
	assert_float(world.camera.rotation_degrees.y).is_equal_approx(0.0, 0.01)


func test_the_best_flag_hides_without_a_best() -> void:
	var flag: Node3D = world.get_node("BestFlag")
	world.set_best(0.0)
	assert_bool(flag.visible).is_false()
	world.set_best(212.5)
	assert_bool(flag.visible).is_true()
	assert_float(flag.position.z).is_equal(-212.5)


func test_the_warm_up_draws_the_effects_then_idles() -> void:
	world.prewarm()
	assert_bool(world.is_processing()).is_true()
	for i in 5:
		await await_idle_frame()
	assert_bool(world.is_processing()).is_false()
	assert_bool((world.get_node("Confetti") as CPUParticles3D).visible).is_false()
