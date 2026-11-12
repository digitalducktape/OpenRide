extends GdUnitTestSuite
## Tug of War's 3D view after the graphics pass (games/tug_of_war/GFX_POLISH.md): every Tug
## shader compiles on the shared look, one look table lights the world for each time of day, the
## baked meshes carry the vertex data their shaders read, the bot stays in its triangle budget
## with its key marked behind it, and the world stays a handful of draws with no per-frame crowd
## or torch script.

const SHADERS := "res://games/tug_of_war/shaders/"
## The world shaders on tug_look.gdshaderinc (the eyes are a self-lit light, not on the look).
const LOOK_SHADERS := ["scenery", "deck", "water", "bot", "crowd", "rope", "hands", "flame", "foam",
	"steam", "lily"]

var world: TugWorld


func before_test() -> void:
	world = auto_free(TugWorld.new())
	add_child(world)


func _uniforms(file: String) -> Array:
	var shader: Shader = load(SHADERS + file + ".gdshader")
	return shader.get_shader_uniform_list().map(func(u: Dictionary) -> String: return str(u.name))


func test_every_world_shader_compiles_on_the_shared_look() -> void:
	for file in LOOK_SHADERS:
		var names := _uniforms(file)
		for p in WorldLook.PARAMS:
			assert_array(names).override_failure_message("%s lacks %s" % [file, p]).contains([String(p)])
	assert_array(_uniforms("eyes")).contains(["eye_color", "glow"])
	assert_array(_uniforms("sky")).contains(["top_color", "disc_color", "star_tex"])


func test_the_look_table_lights_each_time_of_day() -> void:
	for id in ["dawn", "day", "dusk", "night"]:
		var tod := TimeOfDay.load_preset(id)
		var look := TugWorld.look_for(tod)
		for p in WorldLook.PARAMS:
			if p != &"noise_tex":
				assert_bool(look.has(p)).override_failure_message("%s lacks %s" % [id, p]).is_true()
		assert_vector(look.sun_dir).is_equal(WorldLook.sun_dir(tod.sun_elevation, tod.sun_azimuth))
	var day := TugWorld.look_for(TimeOfDay.load_preset("day"))
	var night := TugWorld.look_for(TimeOfDay.load_preset("night"))
	assert_float(night.lamp).is_greater(day.lamp)
	assert_float(night.lamp).is_equal_approx(1.0, 0.001)


func test_set_time_of_day_reaches_every_hand_lit_material() -> void:
	var night := TimeOfDay.load_preset("night")
	world.set_time_of_day(night)
	var haze: Color = night.fog_color
	for mat in world._lit:
		assert_object(mat.get_shader_parameter("haze_color")).is_equal(haze)


func test_the_scenery_is_one_vertex_coloured_mesh_with_sway_and_glow() -> void:
	var mesh: ArrayMesh = world.get_node("Scenery").mesh
	assert_int(mesh.get_surface_count()).is_equal(1)
	var a := mesh.surface_get_arrays(0)
	var colors: PackedColorArray = a[Mesh.ARRAY_COLOR]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	assert_int(colors.size()).is_equal(a[Mesh.ARRAY_VERTEX].size())
	var swaying := 0
	var glowing := 0
	var grained := 0
	for i in colors.size():
		if colors[i].a < 0.5:
			swaying += 1
		if uvs[i].y > 0.5:
			glowing += 1
		if uvs[i].x > 0.5:
			grained += 1
	assert_int(swaying).is_greater(100)  # reed tips, bunting tips
	assert_int(glowing).is_greater(50)  # the string lights' bulbs
	assert_int(grained).is_greater(50)  # the banks
	assert_int(MeshKit3D.tri_count(mesh)).is_less(40000)


func test_the_bot_is_in_budget_with_its_key_behind_it() -> void:
	var body := TugMeshes.bot_body()
	var tris := MeshKit3D.tri_count(body) + MeshKit3D.tri_count(TugMeshes.bot_ears()) \
		+ MeshKit3D.tri_count(TugMeshes.bot_eyes())
	assert_int(tris).is_less(3000)
	var a := body.surface_get_arrays(0)
	var verts: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var key := 0
	var tinted := 0
	for i in verts.size():
		if uvs[i].y > 0.5:
			key += 1
			assert_float(verts[i].z).is_less(-0.45)  # on its back, never over the rope's grip
		if uvs[i].x > 0.5:
			tinted += 1
	assert_int(key).is_greater(20)
	assert_int(tinted).is_greater(200)


func test_set_bot_recolours_by_uniform_and_swaps_ears_for_horns() -> void:
	var mat: ShaderMaterial = world._bot_mat
	var name0 := world.set_bot(0)
	assert_object(mat.get_shader_parameter("body_color")).is_equal(TugWorld.BOT_COLORS[0])
	assert_bool(world.bot_has_horns()).is_false()
	world.set_bot(3)
	assert_object(mat.get_shader_parameter("body_color")).is_equal(TugWorld.BOT_COLORS[3])
	assert_object(world.bot_color()).is_equal(TugWorld.BOT_COLORS[3])
	assert_bool(world.bot_has_horns()).is_true()
	assert_object(world._bot_mat).is_same(mat)  # no new material per rung
	assert_str(name0).is_not_equal(world.bot_name())


func test_the_key_winds_faster_on_a_telegraph_and_steam_shows_only_then() -> void:
	world.update_view(0.0, 0.0, 0.5, "", 80.0)
	var a0 := world._key_angle
	world.update_view(0.1, 0.0, 0.5, "", 80.0)
	var rest := world._key_angle - a0
	assert_bool(world._steam.visible).is_false()
	a0 = world._key_angle
	world.update_view(0.1, 0.0, 0.5, "telegraph", 80.0)
	assert_float(world._key_angle - a0).is_greater(rest * 4.0)
	assert_bool(world._steam.visible).is_true()


func test_the_world_is_a_handful_of_draws() -> void:
	world.update_view(0.016, 0.2, 0.7, "", 80.0)
	var shown := 0
	for node in world.find_children("*", "GeometryInstance3D", true, false):
		var g := node as GeometryInstance3D
		if g.is_visible_in_tree() and not g is CPUParticles3D:
			shown += 1
	# Water, scenery, lilies, decks, flames, crowd, rope, flag, bot body, ears or horns, eyes,
	# gloves: ART_BIBLE §9 allows 70 for the world.
	assert_int(shown).is_less_equal(14)


func test_the_crowd_moves_in_its_shader_not_in_script() -> void:
	var mm: MultiMesh = (world.get_node("Crowd") as MultiMeshInstance3D).multimesh
	var before := mm.get_instance_transform(5)
	world.excitement = 1.0
	for i in 10:
		world.update_view(0.05, 0.4, 0.8, "", 80.0)
	assert_object(mm.get_instance_transform(5)).is_equal(before)
	assert_float(world._crowd_mat.get_shader_parameter("excite")).is_equal_approx(1.0, 0.001)


func test_the_crowd_sprite_has_two_frames_arms_up_in_the_second() -> void:
	var img := TugMeshes.crowd_sprite().get_image()
	assert_int(img.get_width()).is_equal(64)
	assert_int(img.get_height()).is_equal(48)
	# Arms up: the second frame has opaque pixels at the sides above the head; the first doesn't.
	var up := [0, 0]
	for frame in 2:
		for y in 3:
			for x in [4, 5, 26, 27]:
				if img.get_pixel(frame * 32 + x, y + 3).a > 0.5:
					up[frame] += 1
	assert_int(up[0]).is_equal(0)
	assert_int(up[1]).is_greater(0)


func test_the_sky_is_drawn_once_into_its_cubemap_and_sampled() -> void:
	var env: Environment = world._env.environment
	# The cubemap is only kept up to date while the sky is a reflection source.
	assert_int(env.reflected_light_source).is_equal(Environment.REFLECTION_SOURCE_SKY)
	assert_int(env.sky.radiance_size).is_greater_equal(Sky.RADIANCE_SIZE_256)
	var code: String = (load(SHADERS + "sky.gdshader") as Shader).code
	assert_str(code).contains("AT_CUBEMAP_PASS").contains("texture(RADIANCE, EYEDIR)")
	assert_str(code).not_contains("TIME *").not_contains("TIME)")  # TIME would rebuild it every frame


func test_the_vignette_is_in_the_view_grid_not_per_pixel() -> void:
	var inc: String = FileAccess.get_file_as_string(SHADERS + "tug_look.gdshaderinc")
	assert_str(inc).not_contains("#define LOOK_VIGNETTE")
	var mesh := StageView3D.view_image(Vector2(1920, 1080), TugMeshes.VIGNETTE, TugMeshes.VIGNETTE_TINT)
	var a := mesh.surface_get_arrays(0)
	var verts: PackedVector2Array = a[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = a[Mesh.ARRAY_COLOR]
	assert_int(verts.size()).is_equal((StageView3D.COLS + 1) * (StageView3D.ROWS + 1))
	assert_vector(verts[verts.size() - 1]).is_equal(Vector2(1920, 1080))
	var centre := cols[(StageView3D.ROWS / 2) * (StageView3D.COLS + 1) + StageView3D.COLS / 2]
	assert_float(centre.r).is_greater(0.99)
	# The corners are darker and warmer (less blue than red).
	assert_float(cols[0].r).is_less(0.95)
	assert_float(cols[0].b).is_less(cols[0].r)


func test_prewarm_draws_the_hidden_effects_then_hides_them() -> void:
	world.update_view(0.0, 0.0, 0.5, "", 80.0)
	world.prewarm()
	# Drawn (so their shaders compile behind the intro card), but invisible to the rider.
	assert_bool(world._steam.visible).is_true()
	assert_bool(world._ring.visible).is_true()
	assert_float(world._steam_mat.get_shader_parameter("steam")).is_equal(0.0)
	assert_float(world._foam_mat.get_shader_parameter("progress")).is_equal(1.0)
	assert_float(world._splash.global_position.y).is_less(0.0)  # under the river
	for i in TugWorld.WARM_FRAMES + 2:
		await get_tree().process_frame
	assert_bool(world._steam.visible).is_false()
	assert_bool(world._ring.visible).is_false()
	assert_bool(world._splash.emitting).is_false()
