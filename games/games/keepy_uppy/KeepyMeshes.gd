class_name KeepyMeshes
extends RefCounted
## Keepy Uppy's procedural meshes (ART_BIBLE.md). Everything is built from primitive shapes merged
## into vertex-coloured meshes with `KartMeshKit` (read only: Kart owns it), so the whole meadow is
## one draw call. Colours are the bible's palette (sRGB), turned linear for the vertex colours
## (`lin`): the shaders light and grade in linear space.
##
## Vertex data the shaders read (meadow.gdshader):
##   COLOR.a  1 - sway weight (leaves, streamers, the windsock).
##   UV.x     ground grain: one noise read breaks up the hills' grass.
##   UV.y     self-lit share (the balloon's knot ribbon, nothing big).

# The palette (ART_BIBLE §4), sRGB.
const BALLOON := Color("ff5e5b")
const BALLOON_HI := Color("ffd6c9")
const GRASS_NEAR := Color("6fbf4a")
const GRASS_FAR := Color("9ccb6b")
const HILL := Color("7fb86a")
const HILL_FAR := Color("b5d3a0")
const PINE := Color("c9a577")
const PINE_DARK := Color("6b4e2e")
const BAND_LOW := Color("f2efe6")
const BAND_MID := Color("7fd3c4")
const BAND_HIGH := Color("f5c04a")
const FLOWERS := [Color("f7f4e8"), Color("f5d547"), Color("b8a1e3")]
const BIRD := Color("465466")
const BIRD_BELLY := Color("ede6d6")
const BEAK := Color("f5a623")
const CLOUD := Color("ffffff")
const CLOUD_SHADE := Color("c9d6e3")
const RAIN_CLOUD := Color("7d8a9c")
const RAIN_SHADE := Color("5a6677")
const IRON := Color(0.22, 0.23, 0.26)
const GRIP := Color("2fd3b0")

## The world's layout (metres; the camera at the origin looking down -z).
const FAN_Z := -7.0
const FAN_TOP := 0.55  ## the grille's height above the grass
const POLE_X := 2.3
const POLE_HEIGHT := 7.2
## The balloon's centre height: GROUND_Y at h = 0 (resting on the grille), TOP_Y at h = 1.
const GROUND_Y := 1.1
const TOP_Y := 6.6
const BALLOON_RADIUS := 0.46
const VIEW_COLS := 8
const VIEW_ROWS := 6
const VIGNETTE := 0.18
const VIGNETTE_TINT := Color(0.9, 1.0, 1.0)


static func lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, c.a)


## The balloon's centre height for a logic height `h` (0-1).
static func height_y(h: float) -> float:
	return lerpf(GROUND_Y, TOP_Y, h)


static func _kit() -> KartMeshKit:
	var kit := KartMeshKit.new()
	kit.flags = true
	kit.outline = 0.0
	kit.glow = 0.0
	return kit


static func _k(kit: KartMeshKit, mesh: Mesh, xf: Transform3D, color: Color) -> void:
	kit.add(mesh, xf, lin(color))


## A nature-kit model as one vertex-coloured mesh: leaves (the greener materials) in `leaf`, the
## rest in `bark`; leaves sway (alpha 1 - weight).
static func model(mesh: Mesh, leaf: Color, bark: Color) -> ArrayMesh:
	if mesh == null:
		return null
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var m := mesh.surface_get_material(s) as StandardMaterial3D
		var c := lin(bark)
		if m != null and m.albedo_color.g > m.albedo_color.r:
			c = lin(leaf)
			c.a = 0.75
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if not idx.is_empty() else v.size()
		for i in count:
			var vi := idx[i] if not idx.is_empty() else i
			st.set_color(c)
			st.set_normal(n[vi])
			st.add_vertex(v[vi])
	return st.commit()


# --- The meadow: one static mesh (meadow.gdshader) ---

## Hills, hedgerows, trees and bushes, the fan's rails. `models` holds the converted nature-kit
## meshes: "trees" (an Array) and "bush".
static func meadow(models: Dictionary) -> ArrayMesh:
	var kit := _kit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7707
	# Rolling hills in rings: flattened spheres sunk into the ground, paler far away.
	kit.outline = 1.0
	for ring in 3:
		var dist := 70.0 + ring * 45.0
		var count := 9 + ring * 3
		for i in count:
			var a := lerpf(-PI * 0.95, PI * 0.95, (i + rng.randf() * 0.6) / count)
			var pos := Vector3(sin(a) * dist, 0.0, -cos(a) * dist)
			var r := rng.randf_range(22.0, 38.0) + ring * 8.0
			var h := rng.randf_range(5.0, 11.0) + ring * 3.0
			var col := HILL.lerp(HILL_FAR, ring / 2.0).darkened(rng.randf() * 0.08)
			_k(kit, KartMeshKit.sphere(1.0, 14, 7, true), KartMeshKit.xf(pos + Vector3(0, -1.0, 0), Vector3.ZERO, Vector3(r, h, r * 0.8)), col)
	kit.outline = 0.0
	# Hedgerows: lines of round bushes across the middle distance, never behind the column.
	for row in [[-38.0, -14.0, 1.0], [-46.0, 10.0, -1.0], [-30.0, 26.0, 1.0]]:
		var z: float = row[0]
		var x0: float = row[1]
		for i in 9:
			var x: float = x0 + row[2] * i * 2.2
			if absf(x) < 5.0:
				continue
			var s := rng.randf_range(1.0, 1.5)
			_k(kit, KartMeshKit.sphere(1.0, 8, 5), KartMeshKit.xf(Vector3(x, s * 0.6, z + rng.randf_range(-0.6, 0.6)), Vector3.ZERO, Vector3(s * 1.3, s, s)), Color("4f8f3a").darkened(rng.randf() * 0.15))
	# Trees, wide of the column.
	var trees: Array = models.get("trees", [])
	var spots := [Vector3(-9.0, 0, -16.0), Vector3(-15.0, 0, -24.0), Vector3(11.0, 0, -19.0),
		Vector3(17.0, 0, -30.0), Vector3(-24.0, 0, -40.0), Vector3(26.0, 0, -44.0), Vector3(-6.5, 0, -55.0),
		Vector3(8.0, 0, -60.0), Vector3(-13.0, 0, -8.0), Vector3(14.0, 0, -9.0)]
	for i in spots.size():
		if trees.is_empty() or trees[i % trees.size()] == null:
			break
		var s := rng.randf_range(2.4, 3.4)
		kit.add_baked(trees[i % trees.size()], Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), spots[i]))
	var bush = models.get("bush")
	if bush:
		for p in [Vector3(-4.5, 0, -10.0), Vector3(5.0, 0, -12.0), Vector3(-7.5, 0, -20.0), Vector3(9.0, 0, -26.0), Vector3(-3.5, 0, -30.0)]:
			kit.add_baked(bush, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.2, 1.8)), p))
	# The fan's rails: two pale timber runners across the grass.
	for z in [FAN_Z - 0.42, FAN_Z + 0.42]:
		_k(kit, KartMeshKit.box(Vector3(4.6, 0.08, 0.12)), KartMeshKit.xf(Vector3(0, 0.04, z)), PINE_DARK)
	for x in [-2.2, -1.1, 0.0, 1.1, 2.2]:
		_k(kit, KartMeshKit.box(Vector3(0.16, 0.06, 1.1)), KartMeshKit.xf(Vector3(x, 0.03, FAN_Z)), PINE_DARK.darkened(0.2))
	return kit.commit()


## The height pole: a pine post in three painted bands, a peg at each band line. Its streamers and
## the windsock are `streamers()` (they sway on their own material).
static func pole() -> ArrayMesh:
	var kit := _kit()
	var y_mid := height_y(KeepyLogic.MID_FROM)
	var y_high := height_y(KeepyLogic.HIGH_FROM)
	var w := 0.16
	_k(kit, KartMeshKit.box(Vector3(w, GROUND_Y, w)), KartMeshKit.xf(Vector3(0, GROUND_Y * 0.5, 0)), PINE_DARK)
	_k(kit, KartMeshKit.box(Vector3(w, y_mid - GROUND_Y, w)), KartMeshKit.xf(Vector3(0, (GROUND_Y + y_mid) * 0.5, 0)), BAND_LOW)
	_k(kit, KartMeshKit.box(Vector3(w, y_high - y_mid, w)), KartMeshKit.xf(Vector3(0, (y_mid + y_high) * 0.5, 0)), BAND_MID)
	_k(kit, KartMeshKit.box(Vector3(w, POLE_HEIGHT - y_high, w)), KartMeshKit.xf(Vector3(0, (y_high + POLE_HEIGHT) * 0.5, 0)), BAND_HIGH)
	for y in [y_mid, y_high, POLE_HEIGHT]:
		_k(kit, KartMeshKit.box(Vector3(w * 1.6, 0.06, w * 1.6)), KartMeshKit.xf(Vector3(0, y, 0)), PINE_DARK)
	# A cap and a stake foot.
	_k(kit, KartMeshKit.sphere(0.11, 8, 4), KartMeshKit.xf(Vector3(0, POLE_HEIGHT + 0.06, 0)), PINE)
	_k(kit, KartMeshKit.cylinder(0.22, 0.3, 0.1, 8), KartMeshKit.xf(Vector3(0, 0.05, 0)), PINE_DARK)
	return kit.commit()


## The pole's streamers: a ribbon at each band line, in the band's colour, flying to the left, and
## a windsock at the top. Alpha 1 - sway weight along the ribbon.
static func streamers() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var lines := [[height_y(KeepyLogic.MID_FROM), BAND_MID], [height_y(KeepyLogic.HIGH_FROM), BAND_HIGH],
		[POLE_HEIGHT - 0.12, Color("ff8c42")]]
	for line in lines:
		var y: float = line[0]
		var c := lin(line[1])
		var segs := 6
		var length := 1.1 if y < POLE_HEIGHT - 1.0 else 1.4
		var half := 0.07 if y < POLE_HEIGHT - 1.0 else 0.16
		for i in segs:
			var t0 := float(i) / segs
			var t1 := float(i + 1) / segs
			var x0 := -t0 * length
			var x1 := -t1 * length
			var h0 := half * (1.0 - t0 * 0.5)
			var h1 := half * (1.0 - t1 * 0.5)
			var quad := [Vector3(x0, y + h0, 0), Vector3(x1, y + h1, 0), Vector3(x1, y - h1, 0), Vector3(x0, y - h0, 0)]
			var w := [t0, t1, t1, t0]
			for f in 4:
				var face: Array = [[0, 1, 2], [0, 2, 3], [0, 2, 1], [0, 3, 2]][f]
				var n := Vector3(0, 0, 1) if f < 2 else Vector3(0, 0, -1)
				for k in face:
					var cc := c
					cc.a = 1.0 - w[k]
					st.set_color(cc)
					st.set_normal(n)
					st.add_vertex(quad[k])
	return st.commit()


## The pedal fan: a pale pine crate with a dark round grille facing up, corner posts and a belt
## wheel on the near side. Built around its own origin (the grille's centre at FAN_TOP). The
## blades are `fan_blades()`, turned by the world.
static func fan_box() -> ArrayMesh:
	var kit := _kit()
	kit.ao_min = 0.65
	kit.ao_y0 = 0.0
	kit.ao_y1 = FAN_TOP
	_k(kit, KartMeshKit.box(Vector3(1.3, FAN_TOP - 0.04, 1.3)), KartMeshKit.xf(Vector3(0, (FAN_TOP - 0.04) * 0.5, 0)), PINE)
	for x in [-0.62, 0.62]:
		for z in [-0.62, 0.62]:
			_k(kit, KartMeshKit.box(Vector3(0.12, FAN_TOP + 0.06, 0.12)), KartMeshKit.xf(Vector3(x, (FAN_TOP + 0.06) * 0.5, z)), PINE_DARK)
	# Plank lines on the sides.
	for y in [0.16, 0.32]:
		_k(kit, KartMeshKit.box(Vector3(1.32, 0.025, 1.32)), KartMeshKit.xf(Vector3(0, y, 0)), PINE_DARK)
	kit.ao_min = 1.0
	_k(kit, KartMeshKit.cylinder(0.56, 0.56, 0.05, 20), KartMeshKit.xf(Vector3(0, FAN_TOP - 0.02, 0)), IRON)
	_k(kit, KartMeshKit.torus(0.5, 0.58, 20, 6), KartMeshKit.xf(Vector3(0, FAN_TOP + 0.01, 0)), PINE_DARK)
	_k(kit, KartMeshKit.torus(0.28, 0.32, 16, 4), KartMeshKit.xf(Vector3(0, FAN_TOP + 0.02, 0)), Color(0.5, 0.5, 0.5))
	# The drive wheel facing the rider, and a hub.
	_k(kit, KartMeshKit.cylinder(0.24, 0.24, 0.06, 16), KartMeshKit.xf(Vector3(0, 0.28, 0.68), Vector3(90, 0, 0)), IRON)
	_k(kit, KartMeshKit.cylinder(0.06, 0.06, 0.1, 8), KartMeshKit.xf(Vector3(0, 0.28, 0.72), Vector3(90, 0, 0)), BAND_HIGH)
	return kit.commit()


## Four broad blades round a hub, lying flat under the grille (the world spins them about y).
static func fan_blades() -> ArrayMesh:
	var kit := _kit()
	for i in 4:
		var a := i * 90.0
		var dir := Vector3(sin(deg_to_rad(a)), 0, cos(deg_to_rad(a)))
		_k(kit, KartMeshKit.box(Vector3(0.18, 0.02, 0.42)), KartMeshKit.xf(dir * 0.26, Vector3(0, a, 18)), Color(0.88, 0.88, 0.84))
	_k(kit, KartMeshKit.sphere(0.07, 8, 4), Transform3D.IDENTITY, BAND_HIGH)
	return kit.commit()


## The balloon: a sphere stretched a little tall, a knot and a short ribbon. Lit per pixel by
## balloon.gdshader, which reads COLOR (the knot and ribbon are darker).
static func balloon() -> ArrayMesh:
	var kit := KartMeshKit.new()
	var r := BALLOON_RADIUS
	_k(kit, KartMeshKit.blob(Vector3(r, r * 1.15, r), 1.0, 1.0, 20, 14), Transform3D.IDENTITY, BALLOON)
	# A slight point toward the knot.
	_k(kit, KartMeshKit.cylinder(0.12, 0.03, 0.14, 10), KartMeshKit.xf(Vector3(0, -r * 1.1, 0)), BALLOON)
	_k(kit, KartMeshKit.torus(0.02, 0.05, 10, 4), KartMeshKit.xf(Vector3(0, -r * 1.18 - 0.03, 0)), BALLOON.darkened(0.25))
	var pts := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 7:
		var t := float(i) / 6.0
		pts.append(Vector3(sin(t * 7.0) * 0.06, -r * 1.22 - t * 0.55, cos(t * 5.0) * 0.03))
		radii.append(0.012)
	_k(kit, KartMeshKit.tube(pts, radii, 4), Transform3D.IDENTITY, Color("f7f4e8"))
	return kit.commit()


## A round slate bird facing +z (the camera): body, head, beak and two wings. UV.x = 1 on the
## wings (bird.gdshader flaps them).
static func bird() -> ArrayMesh:
	var kit := _kit()
	_k(kit, KartMeshKit.blob(Vector3(0.11, 0.1, 0.13), 1.0, 1.0, 10, 6), KartMeshKit.xf(Vector3(0, 0.1, 0)), BIRD)
	_k(kit, KartMeshKit.blob(Vector3(0.08, 0.07, 0.06), 1.0, 1.0, 8, 5), KartMeshKit.xf(Vector3(0, 0.08, 0.07)), BIRD_BELLY)
	_k(kit, KartMeshKit.sphere(0.075, 8, 5), KartMeshKit.xf(Vector3(0, 0.22, 0.06)), BIRD)
	_k(kit, KartMeshKit.prism(Vector3(0.04, 0.07, 0.04)), KartMeshKit.xf(Vector3(0, 0.215, 0.15), Vector3(90, 0, 0)), BEAK)
	for side in [-1.0, 1.0]:
		_k(kit, KartMeshKit.sphere(0.014, 6, 3), KartMeshKit.xf(Vector3(side * 0.035, 0.24, 0.125)), Color(0.05, 0.05, 0.06))
	kit.outline = 1.0
	for side in [-1.0, 1.0]:
		_k(kit, KartMeshKit.box(Vector3(0.2, 0.02, 0.12)), KartMeshKit.xf(Vector3(side * 0.18, 0.13, -0.01), Vector3(0, 0, side * -12.0)), BIRD.darkened(0.15))
	kit.outline = 0.0
	_k(kit, KartMeshKit.prism(Vector3(0.1, 0.12, 0.02)), KartMeshKit.xf(Vector3(0, 0.08, -0.14), Vector3(-70, 0, 0)), BIRD)
	return kit.commit()


## A fair-weather cumulus: clustered spheres, shaded underneath (alpha 1: no sway).
static func cloud(rng: RandomNumberGenerator, top: Color, shade: Color, puffs := 7) -> ArrayMesh:
	var kit := _kit()
	# Shaded underneath: the puffs' lower halves darken toward 0.7.
	kit.ao_min = 0.7
	kit.ao_y0 = -0.6
	kit.ao_y1 = 0.6
	for i in puffs:
		var x := (float(i) / maxf(puffs - 1, 1) - 0.5) * 2.0
		var s := rng.randf_range(0.55, 1.0) * (1.0 - absf(x) * 0.4)
		var pos := Vector3(x * 1.8, s * 0.35, rng.randf_range(-0.4, 0.4))
		var col := shade.lerp(top, 0.6)
		_k(kit, KartMeshKit.sphere(s, 10, 6), KartMeshKit.xf(pos), col)
	return kit.commit()


## Background clouds in one mesh, far out along the horizon.
static func sky_clouds() -> ArrayMesh:
	var kit := _kit()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	for i in 7:
		var a := lerpf(-1.1, 1.1, (i + rng.randf() * 0.7) / 7.0)
		var dist := rng.randf_range(110.0, 160.0)
		var s := rng.randf_range(7.0, 12.0)
		var xf := Transform3D(Basis.from_scale(Vector3(s, s * 0.7, s)), Vector3(sin(a) * dist, rng.randf_range(28.0, 46.0), -cos(a) * dist))
		kit.add_baked(cloud(rng, CLOUD, CLOUD_SHADE), xf)
	return kit.commit()


## The rain cloud: a darker, flatter cumulus.
static func rain_cloud() -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	return cloud(rng, RAIN_CLOUD, RAIN_SHADE, 9)


## Grass tufts: three crossed blade cards, rooted at the origin (alpha 1 - sway weight up the
## blade). One flower head when `flower`.
static func tuft(flower: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := i * PI / 3.0
		var d := Vector3(cos(a), 0, sin(a)) * 0.09
		var top := Vector3(d.x * 0.6, 0.32, d.z * 0.6)
		var n := Vector3(-sin(a), 0.35, cos(a)).normalized()
		var base := lin(GRASS_NEAR.darkened(0.3))
		var tip := lin(GRASS_NEAR.lightened(0.1))
		tip.a = 0.0
		for face in [[-d, d, top], [d, -d, top]]:
			var cols := [base, base, tip]
			for k in 3:
				st.set_color(cols[k])
				st.set_normal(n if face[0] == -d else -n)
				st.add_vertex(face[k])
	if flower:
		var arrays := KartMeshKit.sphere(0.045, 6, 3).get_mesh_arrays()
		var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var nn: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for k in idx:
			var c := Color(1, 1, 1, 0.0)  # tinted per instance; sways with the tip
			st.set_color(c)
			st.set_normal(nn[k])
			st.add_vertex(v[k] + Vector3(0, 0.34, 0))
	return st.commit()


## An open cone of air from the grille up (the column), UV.y up its height, UV.x around.
static func column() -> ArrayMesh:
	var segs := 20
	var rows := 6
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var idx := PackedInt32Array()
	var height := TOP_Y + 1.6 - FAN_TOP
	for j in rows + 1:
		var t := float(j) / rows
		var r := lerpf(0.5, 1.05, t)
		for i in segs + 1:
			var a := TAU * i / segs
			verts.append(Vector3(cos(a) * r, FAN_TOP + t * height, sin(a) * r))
			normals.append(Vector3(cos(a), 0, sin(a)))
			uvs.append(Vector2(float(i) / segs, t))
	for j in rows:
		for i in segs:
			var a := j * (segs + 1) + i
			var c := a + segs + 1
			idx.append_array([a, c, a + 1, a + 1, c, c + 1])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The rider's handlebars in the camera's space: a dark bar, mint grips and a stem, low in view.
static func handlebars() -> ArrayMesh:
	var kit := _kit()
	var bar := PackedVector3Array([Vector3(-0.42, -0.02, 0.06), Vector3(-0.25, 0.0, 0.0), Vector3(0.25, 0.0, 0.0), Vector3(0.42, -0.02, 0.06)])
	_k(kit, KartMeshKit.tube(bar, PackedFloat32Array([0.016, 0.016, 0.016, 0.016]), 8), Transform3D.IDENTITY, IRON)
	for side in [-1.0, 1.0]:
		_k(kit, KartMeshKit.cylinder(0.022, 0.022, 0.12, 8), KartMeshKit.xf(Vector3(side * 0.4, -0.015, 0.05), Vector3(0, 0, 90)), GRIP)
	_k(kit, KartMeshKit.box(Vector3(0.05, 0.05, 0.14)), KartMeshKit.xf(Vector3(0, -0.02, 0.07)), IRON)
	_k(kit, KartMeshKit.cylinder(0.03, 0.03, 0.3, 8), KartMeshKit.xf(Vector3(0, -0.17, 0.12)), IRON)
	return kit.commit()


## The darkening at a screen position `suv` (0-1 each way), as Tug's view grid does: the shared
## include's vignette formula, painted into the vertex colours of the grid that draws the view.
static func vignette_at(suv: Vector2) -> Color:
	var p := suv * 2.0 - Vector2.ONE
	p.x *= 1.35
	var v := smoothstep(0.7, 1.75, p.length())
	var m := 1.0 - v * VIGNETTE
	var tint := Color.WHITE.lerp(VIGNETTE_TINT, v * 0.5)
	return Color(m * tint.r, m * tint.g, m * tint.b)


## The grid that draws the 3D view's image at `size` on screen, with the vignette in its colours.
static func view_image(size: Vector2) -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for j in VIEW_ROWS + 1:
		for i in VIEW_COLS + 1:
			var uv := Vector2(float(i) / VIEW_COLS, float(j) / VIEW_ROWS)
			verts.append(uv * size)
			uvs.append(uv)
			var m := vignette_at(uv)
			cols.append(Color(pow(m.r, 1.0 / 2.2), pow(m.g, 1.0 / 2.2), pow(m.b, 1.0 / 2.2)))
	for j in VIEW_ROWS:
		for i in VIEW_COLS:
			var a := j * (VIEW_COLS + 1) + i
			var c := a + VIEW_COLS + 1
			idx.append_array([a, a + 1, c, a + 1, c + 1, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
