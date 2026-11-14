class_name DodgeMeshes
extends RefCounted
## Dodge Ball's procedural meshes and textures (#39), built once by DodgeWorld: the horizon's
## hills and tree line, the fence, the handlebars and the value-noise texture. Pure builders:
## no nodes, no state.


## The horizon's mesh: an arc ahead (±85° of straight ahead) of hills 6-14 m high at
## HORIZON_HILLS, and chunky tree crowns 4-9 m high at HORIZON_TREES. Both reach 8 m below the
## ground, so no gap shows under them past the verges' far edges.
static func horizon_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	_arc(st, DodgeWorld.HORIZON_HILLS, 96, func(a: float) -> float:
		return 10.0 + 2.6 * sin(a * 3.1 + 0.6) + 1.4 * sin(a * 7.3 + 2.0),
		Color(0.36, 0.52, 0.3), Color(0.24, 0.36, 0.22))
	_arc(st, DodgeWorld.HORIZON_TREES, 220, func(a: float) -> float:
		var lump := absf(sin(a * 37.0)) * 0.6 + absf(sin(a * 91.0 + 1.3)) * 0.4
		return 4.5 + 3.5 * lump + 1.0 * sin(a * 5.0),
		Color(0.2, 0.36, 0.2), Color(0.14, 0.26, 0.15))
	return st.commit()


static func _arc(st: SurfaceTool, radius: float, segments: int, height: Callable, top: Color, foot: Color) -> void:
	var span := deg_to_rad(85.0)
	for i in segments:
		var a0 := lerpf(-span, span, float(i) / segments)
		var a1 := lerpf(-span, span, float(i + 1) / segments)
		var p0 := Vector3(sin(a0), 0, -cos(a0)) * radius
		var p1 := Vector3(sin(a1), 0, -cos(a1)) * radius
		var corners := [p0 + Vector3(0, -8, 0), p1 + Vector3(0, -8, 0),
			p1 + Vector3(0, float(height.call(a1)), 0), p0 + Vector3(0, float(height.call(a0)), 0)]
		var colours := [foot, foot, top, top]
		# Clockwise seen from the rider (Godot's front faces).
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(colours[k])
			st.add_vertex(corners[k])


## The fence (both sides, from just behind the bike to FENCE_LEN ahead): weathered posts every
## FENCE_SPACING and two rails, vertex-coloured, about 1.2k triangles.
static func fence_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := Color(0.62, 0.53, 0.41)
	var rail := Color(0.78, 0.7, 0.57)
	var x := DodgeBallLogic.ROAD_HALF + DodgeWorld.FENCE_OFFSET
	var posts := int(DodgeWorld.FENCE_LEN / DodgeWorld.FENCE_SPACING) + 2
	var start := DodgeWorld.FENCE_SPACING * 2.0
	for side in [-1.0, 1.0]:
		for i in posts:
			_box(st, Vector3(side * x, 0.45, start - i * DodgeWorld.FENCE_SPACING), Vector3(0.12, 0.9, 0.12), post)
		for y in [0.42, 0.78]:
			var length := posts * DodgeWorld.FENCE_SPACING
			_box(st, Vector3(side * (x - 0.07), y, start - length * 0.5), Vector3(0.05, 0.1, length), rail)
	return st.commit()


## A box without its bottom face (10 triangles) into `st`.
static func _box(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var faces := [[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP], [Vector3.BACK, Vector3.LEFT, Vector3.UP],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := centre + n * h
		var du := u * h
		var dv := v * h
		var quad := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		# Wind each face to face out along n (counter-clockwise seen from outside, Godot's front).
		var order := [0, 2, 1, 0, 3, 2] if u.cross(v).dot(n) > 0.0 else [0, 1, 2, 0, 2, 3]
		st.set_color(color)
		st.set_normal(n)
		for k in order:
			st.add_vertex(quad[k])


## The handlebars as one mesh: the parts the bars were built from (7 draw calls before), each
## vertex-coloured. Metal is a cool grey with sheen (alpha 1), the grips matte rubber, the stem
## and head the accent #F26626.
static func handlebar_mesh() -> ArrayMesh:
	var metal := Color(0.42, 0.44, 0.49, 1.0)
	var rubber := Color(0.06, 0.06, 0.07, 0.0)
	var accent := Color("f26626", 0.35)
	var parts := []
	parts.append([_cylinder(0.016, 0.016, 0.56, 10), metal, Vector3.ZERO, Vector3(0, 0, 90)])
	for side in [-1.0, 1.0]:
		parts.append([_cylinder(0.021, 0.021, 0.13, 10), rubber, Vector3(side * 0.33, 0, 0), Vector3(0, 0, 90)])
		parts.append([_cylinder(0.014, 0.014, 0.12, 8), metal, Vector3(side * 0.27, -0.05, -0.02), Vector3(25, 0, 0)])
	var stem := BoxMesh.new()
	stem.size = Vector3(0.05, 0.05, 0.16)
	parts.append([stem, accent, Vector3(0, -0.02, 0.07), Vector3(-12, 0, 0)])
	parts.append([_cylinder(0.03, 0.034, 0.3, 10), accent, Vector3(0, -0.16, 0.14), Vector3(-15, 0, 0)])
	return _merged(parts)


static func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


## Bakes `parts` ([mesh, colour, position, rotation in degrees], placed as a child node would
## be) into one vertex-coloured ArrayMesh.
static func _merged(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var mesh: Mesh = part[0]
		var xf := Transform3D(Basis.from_euler((part[3] as Vector3) * (PI / 180.0)), part[2])
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in indices:
			st.set_color(part[1])
			st.set_normal((xf.basis * normals[i]).normalized())
			st.add_vertex(xf * verts[i])
	st.index()
	return st.commit()


## 64x64 random values; with linear filtering and repeat, sampling it is value noise for the
## road, verge and sky shaders (cheaper on the tablet than hashing per pixel).
static func noise_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var data := PackedByteArray()
	data.resize(64 * 64)
	for i in data.size():
		data[i] = rng.randi_range(0, 255)
	var img := Image.create_from_data(64, 64, false, Image.FORMAT_L8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
