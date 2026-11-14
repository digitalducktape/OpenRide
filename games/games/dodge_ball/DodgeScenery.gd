class_name DodgeScenery
extends RefCounted
## Dodge Ball's roadside (#39): the CHUNKS scenery chunks that leapfrog past the bike (lamps both
## sides, trees, bushes, rocks, cones, contact discs) and the one fence that scrolls with them,
## built once by DodgeWorld. Builders only: what the world keeps is handed back to it.


## Each chunk: lamps both sides (staggered), trees, bushes and rocks, a few cones on the kerb, a
## post-and-rail fence each side, and a painted contact disc under everything that stands.
## Adds the fence and then the chunks (appended to `chunks`) to `world`; the scenery materials go
## in `cache`, the contact discs' material in `blob_mats`. Returns {fence, halo_mat}.
static func build(world: Node3D, cache: Dictionary, blob_mats: Array[ShaderMaterial], chunks: Array[Node3D]) -> Dictionary:
	var lamp := DodgeModels.hand_lit(DodgeModels.glow_tip(DodgeModels.model_mesh("light-curved.glb")), cache)
	var trees := [DodgeModels.hand_lit(DodgeModels.model_mesh("tree_default.glb"), cache, Color(0.32, 0.56, 0.2), DodgeWorld.BARK, DodgeWorld.TREE_SWAY),
		DodgeModels.hand_lit(DodgeModels.model_mesh("tree_oak.glb"), cache, Color(0.26, 0.48, 0.17), DodgeWorld.BARK, DodgeWorld.TREE_SWAY),
		DodgeModels.hand_lit(DodgeModels.model_mesh("tree_pineTallA.glb"), cache, Color(0.16, 0.36, 0.2), DodgeWorld.BARK, DodgeWorld.TREE_SWAY),
		DodgeModels.hand_lit(DodgeModels.model_mesh("tree_cone.glb"), cache, Color(0.38, 0.6, 0.22), DodgeWorld.BARK, DodgeWorld.TREE_SWAY)]
	var bush := DodgeModels.hand_lit(DodgeModels.model_mesh("plant_bushLarge.glb"), cache, Color(0.3, 0.52, 0.2), DodgeWorld.BARK, DodgeWorld.BUSH_SWAY)
	# Rocks: a lighter top over a darker foot (the painted AO over their whole height).
	var rock := DodgeModels.hand_lit(DodgeModels.model_mesh("rock_largeA.glb"), cache, Color(0.56, 0.56, 0.53),
		Color(0.46, 0.45, 0.43), 0.0, 0.9)
	var cone := DodgeModels.hand_lit(DodgeModels.model_mesh("construction-cone.glb"), cache)
	# One fence for the whole road (a draw call, not one a chunk): it scrolls like the chunks and
	# steps back a post spacing as it passes, which can't be seen.
	var fence := MeshInstance3D.new()
	fence.name = "Fence"
	fence.mesh = DodgeMeshes.fence_mesh()
	fence.material_override = DodgeModels.scenery_material(cache, Color(1, 1, 1), null, 0.0, 1.0, false, true)
	fence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(fence)
	var disc := QuadMesh.new()
	disc.size = Vector2.ONE
	disc.orientation = PlaneMesh.FACE_Y
	var disc_mat := ShaderMaterial.new()
	disc_mat.shader = load("res://games/dodge_ball/shaders/blob.gdshader")
	disc_mat.set_shader_parameter("core", 0.3)
	disc_mat.set_shader_parameter("darkness", 1.0)
	disc_mat.set_shader_parameter("strength", 0.42)
	disc.material = disc_mat
	blob_mats.append(disc_mat)
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.disable_fog = true
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.45))
	glow.gradient = g
	halo_mat.albedo_texture = glow
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(1.6, 1.6)
	halo_quad.material = halo_mat

	var lamp_height := 6.0
	var lamp_scale := lamp_height / maxf(0.01, lamp.get_aabb().size.y) if lamp else 1.0
	var lamp_aabb: AABB = lamp.get_aabb() if lamp else AABB()
	# The model's arm reaches along -z; each lamp is turned so it reaches over the road.
	var head_local := Vector3(lamp_aabb.get_center().x, lamp_aabb.end.y - 0.03, lamp_aabb.position.z + 0.02) * lamp_scale

	for c in DodgeWorld.CHUNKS:
		var chunk := Node3D.new()
		chunk.name = "Chunk%d" % c
		chunk.position.z = -c * DodgeWorld.CHUNK_LEN
		world.add_child(chunk)
		chunks.append(chunk)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (c + 1)
		var lamp_xf: Array[Transform3D] = []
		var halo_xf: Array[Transform3D] = []
		var discs: Array[Transform3D] = []
		var lamp_x := DodgeBallLogic.ROAD_HALF + 1.2
		for k in int(DodgeWorld.CHUNK_LEN / DodgeWorld.LAMP_SPACING):
			for side in [-1.0, 1.0]:
				var z := -k * DodgeWorld.LAMP_SPACING - (0.0 if side < 0.0 else DodgeWorld.LAMP_SPACING * 0.5)
				# Left lamps reach towards +x, right ones towards -x.
				var yaw := -PI / 2.0 if side < 0.0 else PI / 2.0
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * lamp_scale)
				lamp_xf.append(Transform3D(basis, Vector3(side * lamp_x, 0, z)))
				var head := Basis(Vector3.UP, yaw) * head_local
				halo_xf.append(Transform3D(Basis(), Vector3(side * lamp_x, -0.15, z) + head))
				discs.append(_disc(Vector3(side * lamp_x, 0, z), 0.7))
		if lamp:
			chunk.add_child(DodgeModels.multimesh(lamp, lamp_xf, "Lamps"))
		var halos := DodgeModels.multimesh(halo_quad, halo_xf, "Halos")
		chunk.add_child(halos)

		var per_tree: Array[Array] = []
		for t in 4:
			per_tree.append([] as Array[Transform3D])
		for i in 26:
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := side * clear_of_fence(rng.randf_range(DodgeBallLogic.ROAD_HALF + 3.5, 32.0))
			var z := -rng.randf_range(0.0, DodgeWorld.CHUNK_LEN)
			var which := rng.randi_range(0, 3)
			var mesh: Mesh = trees[which]
			if mesh == null:
				continue
			var h := rng.randf_range(5.0, 9.0) * (1.3 if which == 2 else 1.0)
			var s := h / maxf(0.01, mesh.get_aabb().size.y)
			per_tree[which].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, 0, z)))
			discs.append(_disc(Vector3(x, 0, z), maxf(mesh.get_aabb().size.x, mesh.get_aabb().size.z) * s * 0.75))
		for which in 4:
			if trees[which] and not per_tree[which].is_empty():
				var xfs: Array[Transform3D] = []
				xfs.assign(per_tree[which])
				chunk.add_child(DodgeModels.multimesh(trees[which], xfs, "Trees%d" % which))
		for pair in [[bush, 14, 1.2, 2.2, "Bushes"], [rock, 6, 0.8, 1.8, "Rocks"]]:
			var mesh: Mesh = pair[0]
			if mesh == null:
				continue
			var xfs: Array[Transform3D] = []
			for i in int(pair[1]):
				var side := -1.0 if i % 2 == 0 else 1.0
				var x := side * clear_of_fence(rng.randf_range(DodgeBallLogic.ROAD_HALF + 1.8, 20.0))
				var s: float = rng.randf_range(pair[2], pair[3]) / maxf(0.01, mesh.get_aabb().size.y)
				var at := Vector3(x, 0, -rng.randf_range(0.0, DodgeWorld.CHUNK_LEN))
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), at))
				discs.append(_disc(at, maxf(mesh.get_aabb().size.x, mesh.get_aabb().size.z) * s * 1.1))
			chunk.add_child(DodgeModels.multimesh(mesh, xfs, pair[4]))
		if cone and c == 1:
			var cones: Array[Transform3D] = []
			var cs := 0.7 / maxf(0.01, cone.get_aabb().size.y)
			for i in 4:
				cones.append(Transform3D(Basis().scaled(Vector3.ONE * cs), Vector3(-(DodgeBallLogic.ROAD_HALF + 0.6), 0, -10.0 - i * 2.5)))
			chunk.add_child(DodgeModels.multimesh(cone, cones, "Cones"))
		var disc_mmi := DodgeModels.multimesh(disc, discs, "Discs")
		chunk.add_child(disc_mmi)
	return {"fence": fence, "halo_mat": halo_mat}


## An |x| for scenery that keeps it at least 1.2 m off the fence line (pushed outwards).
static func clear_of_fence(ax: float) -> float:
	var line := DodgeBallLogic.ROAD_HALF + DodgeWorld.FENCE_OFFSET
	return ax + 2.4 if absf(ax - line) < 1.2 else ax


## A contact disc's transform: `diameter` m across, flat on the ground just above the verge.
static func _disc(at: Vector3, diameter: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(diameter, 1.0, diameter)), Vector3(at.x, 0.03, at.z))
