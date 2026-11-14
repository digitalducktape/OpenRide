class_name DodgeModels
extends RefCounted
## Dodge Ball's model-kit adapters (#39): copies of the imported models restyled for this road
## (recoloured, cheap per-vertex lighting, or on the hand-lit scenery shader with one shared
## material per surface look), the street lamp's self-lit head, and the static MultiMesh helper
## the scenery chunks are made of. Pure builders: the only state is the caller's material cache.


static func model_mesh(file: String) -> Mesh:
	return MeshKit3D.model_mesh(file)


## A copy of a nature-kit mesh in this road's palette: leaves (the greener surfaces) in
## `leaf`, the rest (trunks) in `bark`. The kit's materials are fully metallic, which renders
## near-black without reflections, so they become plain matte ones lit per vertex.
static func recolor(mesh: Mesh, leaf: Color, bark := Color(0.42, 0.29, 0.19)) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s) as StandardMaterial3D
		if mat == null:
			continue
		var m := mat.duplicate() as StandardMaterial3D
		var c := mat.albedo_color
		m.albedo_color = leaf if c.g > c.r else bark
		m.metallic = 0.0
		m.roughness = 0.95
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		copy.surface_set_material(s, m)
	return copy


## A copy of a model mesh lit per vertex, without specular: flat-shaded low-poly models look
## the same, and the tablet's GPU does a fraction of the work.
static func cheap(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s) as BaseMaterial3D
		if mat == null:
			continue
		var m := mat.duplicate() as BaseMaterial3D
		m.metallic = 0.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		copy.surface_set_material(s, m)
	return copy


## A copy of a model mesh on the hand-lit scenery shader (shaders/scenery.gdshader), one
## material per surface colour from `cache`, so every chunk shares them. With `leaf`, the greener
## surfaces take `leaf` and sway by `sway`, the rest `bark` (as `recolor` picks them); without,
## each surface keeps its colour and texture (the city kit's palette map). A mesh carrying vertex
## colours marks its self-lit part in their alpha (`glow_tip`). `recolor` and `cheap` stay as
## they were for Tug of War, which builds its own look.
static func hand_lit(mesh: Mesh, cache: Dictionary, leaf: Variant = null, bark := DodgeWorld.BARK, sway := 0.0,
		ao_height := 1.5) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var src := copy.surface_get_material(s) as BaseMaterial3D
		var c := src.albedo_color if src else Color.WHITE
		var tex: Texture2D = src.albedo_texture if src else null
		var is_leaf := leaf != null and c.g > c.r
		var colour: Color = (leaf if is_leaf else bark) if leaf != null else c
		var glow: bool = (copy.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
		copy.surface_set_material(s, scenery_material(cache, colour, tex, sway if is_leaf else 0.0,
			ao_height, glow, false))
	return copy


## The shared scenery material for one look of surface, made once per `cache`.
static func scenery_material(cache: Dictionary, colour: Color, tex: Texture2D, sway: float,
		ao_height: float, glow: bool, vertex_color: bool) -> ShaderMaterial:
	var key := "%s|%s|%.4f|%.2f|%s|%s" % [colour.to_html(), tex.resource_path if tex else "",
		sway, ao_height, glow, vertex_color]
	if cache.has(key):
		return cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/dodge_ball/shaders/scenery.gdshader")
	mat.set_shader_parameter("albedo", colour)
	if tex:
		mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("sway", sway)
	mat.set_shader_parameter("ao_height", ao_height)
	mat.set_shader_parameter("glow_mask", glow)
	mat.set_shader_parameter("use_vertex_color", vertex_color)
	cache[key] = mat
	return mat


## The street lamp with its head marked self-lit: vertex alpha 1 on the lamp at the arm's tip
## (the top 7 cm of the model, its last 6 cm along the arm), 0 elsewhere.
static func glow_tip(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var aabb := mesh.get_aabb()
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours := PackedColorArray()
		colours.resize(verts.size())
		for i in verts.size():
			var v := verts[i]
			var tip := v.y > aabb.end.y - 0.07 and v.z < aabb.position.z + 0.06
			colours[i] = Color(1, 1, 1, 1.0 if tip else 0.0)
		arrays[Mesh.ARRAY_COLOR] = colours
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


static func multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi
