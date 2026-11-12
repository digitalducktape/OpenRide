class_name MeshKit3D
extends RefCounted
## Procedural mesh helpers for the 3D games (from Kart Race's look, #43; The Pull and Gate Crasher
## build their worlds with it too). Every model in a game is
## built here from primitive shapes merged into one vertex-coloured ArrayMesh per object, so a
## kart is a couple of draw calls and a whole forest is one MultiMesh. Colours carry the look:
## painted ambient occlusion (darker low down and underneath) is baked into them, and the alpha
## channel is a per-vertex mask the shaders read (gloss on karts, sway weight on foliage).
##
## The shaders light everything by hand (see shaders/): the tablet's GPU is fill-rate bound and
## the engine's per-pixel lights cost about a third of its frame (docs/GAMES.md, Dodge Ball).

## Painted AO for the next `add` calls: colours darken towards `ao_min` below `ao_y0` (metres,
## in the merged mesh's space), reaching full brightness at `ao_y1`. ao_min = 1 turns it off.
var ao_y0 := 0.0
var ao_y1 := 1.0
var ao_min := 1.0

## Rigid rigging (the karts' rig): when `skinned`, every vertex of the next `add` calls carries
## bone `bone` in UV2.x (the kart shaders move it by that bone's matrix), and `commit` indexes
## the mesh. Set it before the first add.
var skinned := false
var bone := 0
## Per-vertex flags for the kart shader, in UV (when `flags`; set it before the first add):
## x = the outline's width scale (0 = none), y = self-lit share (eye glints, lamps).
var flags := false
var outline := 1.0
var glow := 0.0
## An optional painter for the next `add` calls: func(local_pos, local_normal, color) -> Color,
## in the added shape's own space (stripes, masks, bellies).
var paint := Callable()
## A transform applied after each `add`'s own (a whole group scaled about a point: the racers'
## heads are built at portrait size, then shrunk onto the kart).
var pre := Transform3D.IDENTITY

var _st := SurfaceTool.new()
var _empty := true


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## Appends `mesh` (a PrimitiveMesh or any one-surface ArrayMesh), transformed by `xf`, in `color`
## (alpha = the shader mask). A mesh with vertex colours (lathe, tube) is tinted by `color`.
func add(mesh: Mesh, xf: Transform3D, color: Color) -> void:
	var arrays: Array = mesh.get_mesh_arrays() if mesh is PrimitiveMesh else mesh.surface_get_arrays(0)
	xf = pre * xf
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	var nb := xf.basis.inverse().transposed()
	var count := indices.size() if not indices.is_empty() else verts.size()
	var painted := paint.is_valid()
	# PrimitiveMesh winding is clockwise front faces; keep it (Godot's convention).
	for i in count:
		var vi := indices[i] if not indices.is_empty() else i
		var p := xf * verts[vi]
		var n := (nb * normals[vi]).normalized() if normals.size() > vi else Vector3.UP
		var c := color
		if colors.size() > vi:
			c = color * colors[vi]
		if painted:
			c = paint.call(verts[vi], normals[vi] if normals.size() > vi else Vector3.UP, c)
		if ao_min < 1.0:
			var k := clampf((p.y - ao_y0) / maxf(ao_y1 - ao_y0, 0.001), 0.0, 1.0)
			var f := lerpf(ao_min, 1.0, k * k * (3.0 - 2.0 * k))
			# Faces pointing down get a little darker still.
			f *= lerpf(0.82, 1.0, clampf(n.y + 1.0, 0.0, 1.0))
			c = Color(c.r * f, c.g * f, c.b * f, c.a)
		_st.set_color(c)
		_st.set_normal(n)
		_vertex_extras()
		_st.add_vertex(p)
	_empty = false


func _vertex_extras() -> void:
	if flags:
		_st.set_uv(Vector2(outline, glow))
	if skinned:
		_st.set_uv2(Vector2(bone, 0.0))


## Appends a vertex-coloured mesh built by a kit (its colours times `tint`), transformed by `xf`.
## Used to bake many instances into one static mesh per sector of the world.
func add_baked(mesh: ArrayMesh, xf: Transform3D, tint := Color.WHITE) -> void:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var b := xf.basis
	for i in verts.size():
		_st.set_color(colors[i] * tint)
		_st.set_normal((b * normals[i]).normalized())
		_vertex_extras()
		_st.add_vertex(xf * verts[i])
	_empty = false


## A quad a-b-c-d (clockwise seen from the front) with a flat normal.
func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	var n := (c - a).cross(b - a).normalized()
	for p in [a, b, c, a, c, d]:
		_st.set_color(color)
		_st.set_normal(n)
		_vertex_extras()
		_st.add_vertex(p)
	_empty = false


func is_empty() -> bool:
	return _empty


func commit() -> ArrayMesh:
	if skinned:
		_st.index()
	return _st.commit()


# --- Primitive shortcuts (low segment counts: the tablet) ---

static func sphere(radius: float, segments := 10, rings := 5, hemisphere := false) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * (1.0 if hemisphere else 2.0)
	m.radial_segments = segments
	m.rings = rings
	m.is_hemisphere = hemisphere
	return m


static func box(size: Vector3) -> BoxMesh:
	var m := BoxMesh.new()
	m.size = size
	return m


static func cylinder(top: float, bottom: float, height: float, segments := 10) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = top
	m.bottom_radius = bottom
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return m


static func capsule(radius: float, height: float, segments := 10, rings := 2) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = maxf(height, radius * 2.0)
	m.radial_segments = segments
	m.rings = rings
	return m


static func torus(inner: float, outer: float, rings := 14, ring_segments := 6) -> TorusMesh:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = rings
	m.ring_segments = ring_segments
	return m


static func prism(size: Vector3) -> PrismMesh:
	var m := PrismMesh.new()
	m.size = size
	return m


# --- Smooth shapes (the racers): analytic normals, so a low count still shades round ---

## A superellipsoid with `radii`: e1 shapes it top to bottom, e2 around (1, 1 = an ellipsoid;
## 0.3 = a pillowy rounded box). `v_max` < PI cuts it open below (a helmet dome). Indexed.
static func blob(radii: Vector3, e1 := 1.0, e2 := 1.0, segments := 12, rings := 8, v_max := PI) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	for r in rings + 1:
		var v := v_max * r / rings
		var sv := sin(v)
		var cv := cos(v)
		for s in segments + 1:
			var u := TAU * s / segments
			var cu := cos(u)
			var su := sin(u)
			verts.append(Vector3(radii.x * _spow(sv, e1) * _spow(cu, e2), radii.y * _spow(cv, e1),
				radii.z * _spow(sv, e1) * _spow(su, e2)))
			var n := Vector3(_spow(sv, 2.0 - e1) * _spow(cu, 2.0 - e2) / radii.x, _spow(cv, 2.0 - e1) / radii.y,
				_spow(sv, 2.0 - e1) * _spow(su, 2.0 - e2) / radii.z)
			normals.append(n.normalized() if n.length_squared() > 1e-12 else Vector3(0, signf(cv), 0))
	return _grid_mesh(verts, normals, PackedColorArray(), rings, segments)


## `profile` (x = radius, y = height, bottom to top) revolved around Y. A repeated point makes a
## crease. `colors`, one per profile point, paint bands (ear tips, tyre walls, iris rings).
static func lathe(profile: PackedVector2Array, segments := 12, colors := PackedColorArray()) -> ArrayMesh:
	var n2 := PackedVector2Array()
	var count := profile.size()
	for i in count:
		# Average the two neighbouring segments' normals; a zero-length one (a crease) is skipped.
		var acc := Vector2.ZERO
		if i > 0 and not profile[i].is_equal_approx(profile[i - 1]):
			acc += _perp(profile[i] - profile[i - 1])
		if i < count - 1 and not profile[i].is_equal_approx(profile[i + 1]):
			acc += _perp(profile[i + 1] - profile[i])
		n2.append(acc.normalized() if acc.length_squared() > 1e-12 else Vector2(0, 1))
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	for r in count:
		for s in segments + 1:
			var u := TAU * s / segments
			var dir := Vector3(cos(u), 0.0, sin(u))
			verts.append(dir * profile[r].x + Vector3.UP * profile[r].y)
			normals.append((dir * n2[r].x + Vector3.UP * n2[r].y).normalized())
			if not colors.is_empty():
				cols.append(colors[mini(r, colors.size() - 1)])
	return _grid_mesh(verts, normals, cols, count - 1, segments)


## A stack of `count` tyres (`radius` out, `hole` in, each `height` tall), revolved in one piece:
## each tyre's outer wall is bevelled into a dark groove where it meets the next, painted darker
## toward the grooves (AO), and the top tyre's rim rolls over into a dark hole. `colors` per tyre
## (white = take the tint), alpha kept.
static func tyre_stack(count: int, colors: Array, radius := 0.42, hole := 0.2, height := 0.3, segments := 7) -> ArrayMesh:
	var prof := PackedVector2Array()
	var cols := PackedColorArray()
	var bevel := 0.05
	for k in count:
		var c: Color = colors[k % colors.size()]
		var y0 := k * height
		var y1 := y0 + height
		var groove := Color(c.r * 0.35, c.g * 0.35, c.b * 0.35, c.a)
		var shade := Color(c.r * 0.72, c.g * 0.72, c.b * 0.72, c.a)
		for pc: Array in [[Vector2(radius - bevel, y0), groove], [Vector2(radius, y0 + bevel), c],
				[Vector2(radius, y1 - bevel), shade], [Vector2(radius - bevel, y1), groove]]:
			prof.append(pc[0])
			cols.append(pc[1])
	var top: Color = colors[(count - 1) % colors.size()]
	var h := count * height
	var dark := Color(0.05, 0.05, 0.06, top.a)
	for pc: Array in [[Vector2(radius - bevel * 2.0, h + 0.02), Color(top.r * 0.9, top.g * 0.9, top.b * 0.9, top.a)],
			[Vector2(hole + bevel, h + 0.02), Color(top.r * 0.6, top.g * 0.6, top.b * 0.6, top.a)],
			[Vector2(hole, h - 0.03), dark], [Vector2(hole, h - height * 0.9), dark], [Vector2(0.0, h - height * 0.9), dark]]:
		prof.append(pc[0])
		cols.append(pc[1])
	return lathe(prof, segments, cols)


## A barrel `height` tall: a slight bulge, two dark hoops, a bevelled rim and a recessed lid.
static func barrel(color: Color, radius := 0.35, height := 0.95, segments := 10) -> ArrayMesh:
	var hoop := Color(color.r * 0.45, color.g * 0.45, color.b * 0.5, color.a)
	var rim := Color(color.r * 0.7, color.g * 0.7, color.b * 0.7, color.a)
	var lid := Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, color.a)
	var pts := [[Vector2(radius - 0.03, 0.0), rim], [Vector2(radius, 0.04), rim], [Vector2(radius, 0.13), hoop],
		[Vector2(radius + 0.01, 0.19), color], [Vector2(radius + 0.03, height * 0.5), color],
		[Vector2(radius + 0.01, height - 0.19), color], [Vector2(radius, height - 0.13), hoop],
		[Vector2(radius, height - 0.04), rim], [Vector2(radius - 0.03, height), color.lightened(0.1)],
		[Vector2(radius - 0.06, height - 0.03), rim], [Vector2(0.0, height - 0.03), lid]]
	var prof := PackedVector2Array()
	var cols := PackedColorArray()
	for pc: Array in pts:
		prof.append(pc[0])
		cols.append(pc[1])
	return lathe(prof, segments, cols)


## A round tube through `points`, `radii` per point (or one), rounded ends; `colors` per point.
static func tube(points: PackedVector3Array, radii: PackedFloat32Array, segments := 6, colors := PackedColorArray()) -> ArrayMesh:
	var count := points.size()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var cols := PackedColorArray()
	var t0 := (points[1] - points[0]).normalized()
	var side := t0.cross(Vector3.UP if absf(t0.y) < 0.9 else Vector3.RIGHT).normalized()
	# Rings: an end cap point, the points, an end cap point (rounded ends).
	var rings := count + 2
	for r in rings:
		var i := clampi(r - 1, 0, count - 1)
		var t := (points[mini(i + 1, count - 1)] - points[maxi(i - 1, 0)]).normalized()
		side = (side - t * side.dot(t)).normalized()  # parallel transport
		var up := t.cross(side)
		var rad: float = radii[mini(i, radii.size() - 1)]
		var centre := points[i]
		var shrink := 1.0
		var push := Vector3.ZERO
		if r == 0:
			shrink = 0.0
			push = -t * rad * 0.7
		elif r == rings - 1:
			shrink = 0.0
			push = t * rad * 0.7
		for s in segments + 1:
			var a := TAU * s / segments
			var d := side * cos(a) + up * sin(a)
			verts.append(centre + push + d * rad * shrink)
			var nrm := d
			if r == 0:
				nrm = -t
			elif r == rings - 1:
				nrm = t
			normals.append(nrm)
			if not colors.is_empty():
				cols.append(colors[clampi(i, 0, colors.size() - 1)])
	return _grid_mesh(verts, normals, cols, rings - 1, segments)


## A transform onto an ellipsoid's surface (centre at the origin, `radii`), at the front (-Z)
## point with these x, y: local +Y along the outward normal, +Z up the surface, +X right. Lathes
## and domes placed with it stand out of the surface. `sink` pushes it in along the normal.
static func on_surface(radii: Vector3, x: float, y: float, sink := 0.0, back := false) -> Transform3D:
	var q := 1.0 - pow(x / radii.x, 2.0) - pow(y / radii.y, 2.0)
	var z := radii.z * sqrt(maxf(q, 0.0)) * (1.0 if back else -1.0)
	var p := Vector3(x, y, z)
	var n := Vector3(x / (radii.x * radii.x), y / (radii.y * radii.y), z / (radii.z * radii.z)).normalized()
	var up := (Vector3.UP - n * n.dot(Vector3.UP))
	up = up.normalized() if up.length_squared() > 1e-6 else Vector3.BACK
	var right := n.cross(up).normalized()
	return Transform3D(Basis(right, n, up), p - n * sink)


## The transform that takes a Y-axis shape of unit length centred at the origin onto a-b.
static func between(a: Vector3, b: Vector3, thickness := Vector3.ONE) -> Transform3D:
	var y := b - a
	var len := y.length()
	y /= len
	var x := y.cross(Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y)
	return Transform3D(Basis(x * thickness.x, y * len * thickness.y, z * thickness.z), (a + b) * 0.5)


static func tri_count(mesh: Mesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		n += (a[Mesh.ARRAY_INDEX].size() if a[Mesh.ARRAY_INDEX] != null else a[Mesh.ARRAY_VERTEX].size()) / 3
	return n


static func _spow(x: float, e: float) -> float:
	return signf(x) * pow(absf(x), e)


static func _perp(t: Vector2) -> Vector2:
	return Vector2(t.y, -t.x).normalized()


## A (rows + 1) x (cols + 1) vertex grid into an indexed mesh; degenerate triangles (poles) are
## dropped, and each triangle is wound to face along its normals (Godot's front faces).
static func _grid_mesh(verts: PackedVector3Array, normals: PackedVector3Array, cols: PackedColorArray, rows: int, columns: int) -> ArrayMesh:
	var idx := PackedInt32Array()
	var w := columns + 1
	for r in rows:
		for s in columns:
			var a := r * w + s
			var b := a + 1
			var c := a + w
			var d := c + 1
			_tri(idx, verts, normals, a, b, c)
			_tri(idx, verts, normals, b, d, c)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	if not cols.is_empty():
		arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _tri(idx: PackedInt32Array, v: PackedVector3Array, n: PackedVector3Array, a: int, b: int, c: int) -> void:
	var cr := (v[b] - v[a]).cross(v[c] - v[a])
	if cr.length_squared() < 1e-14:
		return
	if cr.dot(n[a] + n[b] + n[c]) > 0.0:
		idx.append_array([a, c, b])
	else:
		idx.append_array([a, b, c])


## Transform helper: translate, then rotate (degrees, YXZ), then scale.
static func xf(pos: Vector3, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	var b := Basis.from_euler(Vector3(deg_to_rad(rot_deg.x), deg_to_rad(rot_deg.y), deg_to_rad(rot_deg.z)))
	return Transform3D(b.scaled_local(scale), pos)


## 64x64 random values; with linear filtering and repeat, sampling it is value noise for the
## shaders (cheaper on the tablet's PowerVR than hashing per pixel). Dodge Ball's pattern.
static func noise_texture(seed_value := 1337) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var data := PackedByteArray()
	data.resize(64 * 64)
	for i in data.size():
		data[i] = rng.randi_range(0, 255)
	var img := Image.create_from_data(64, 64, false, Image.FORMAT_L8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## A soft round sprite (white, alpha falls off), for puffs, halos and shadows.
static func soft_disc(size := 64, hardness := 0.0) -> ImageTexture:
	var img := Image.create(size, size, true, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var r := Vector2(x - c, y - c).length() / c
			var a := clampf(1.0 - r, 0.0, 1.0)
			a = lerpf(a * a * (3.0 - 2.0 * a), 1.0 if r < 0.85 else 0.0, hardness)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func multimesh_node(mesh: Mesh, transforms: Array, node_name: String, custom: Array = [],
		colors: Array = []) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = not custom.is_empty()
	# In the Compatibility renderer, custom data without instance colours multiplies COLOR by zero:
	# carry white instance colours along with it (or the given `colors`).
	mm.use_colors = not custom.is_empty() or not colors.is_empty()
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
		if not custom.is_empty():
			mm.set_instance_custom_data(i, custom[i])
		if mm.use_colors:
			mm.set_instance_color(i, colors[i] if not colors.is_empty() else Color.WHITE)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


static func mesh_node(mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## A flat grid in the xz plane, `width` across and from z = `z0` to `z0 - length`, with `cols`
## and `rows` cells (per-vertex light and haze need the vertices).
static func ground_grid(width: float, length: float, cols: int, rows: int, z0: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in rows + 1:
		for i in cols + 1:
			verts.append(Vector3(-width / 2.0 + width * i / cols, 0.0, z0 - length * j / rows))
			normals.append(Vector3.UP)
	for j in rows:
		for i in cols:
			var a := j * (cols + 1) + i
			var c := a + cols + 1
			# Seen from above (front faces clockwise in Godot).
			idx.append_array([a, c, a + 1, a + 1, c, c + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The shared low-poly models (`games/assets/models/`, sources in `games/assets/SOURCES.md`): the
## trees, bushes and rocks more than one world plants.
const MODELS := "res://assets/models/"


## The first mesh in the model scene `file` under `MODELS` (a .glb), or null.
static func model_mesh(file: String) -> Mesh:
	var scene := load(MODELS + file) as PackedScene
	if scene == null:
		push_warning("MeshKit3D: can't load %s" % file)
		return null
	var root := scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty() and found == null:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			found = (node as MeshInstance3D).mesh
		stack.append_array(node.get_children())
	root.free()
	return found
