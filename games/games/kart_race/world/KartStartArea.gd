class_name KartStartArea
extends RefCounted
## Kart Race's start (#43): the grandstand and its crowd, the start gate with its lamps, and the
## flags along the straight, built once per track by KartWorld.build with the world's materials.
## Also the shared meshes and textures the dressers reuse (halo_quad, flag_cloth) and the crowd
## sprite. Builders only: what the world keeps (the crowd's MultiMesh, the gate's halos, the
## stand's frame) is handed back to it.

static var _halo_quad: QuadMesh
static var _cloth: ArrayMesh


## The grandstand on the outside of the start straight, full of fans, dressed in its theme:
## Meadow's striped canopy, Canyon's awning over red rock, Harbor's lamps, Frost's snow-laden
## roof over wooden benches. Accent banners hang from the roof; flags fly along its back.
## Sets world.stand_xf, appends the lit lamps to `stand_lamps`, and returns the crowd's MultiMesh.
static func build_grandstand(world: KartWorld, parent: Node3D, stand_lamps: Array[Vector3]) -> MultiMesh:
	var track := world.track
	var look := world.look
	var s_mid := track.wrap(-22.0)
	var hw := track.half_width(s_mid)
	var yaw := track.yaw_at(s_mid)
	var side := 1.0
	var origin := track.position_at(s_mid, side * (hw + track.verge + 3.2))
	origin.y = track.position_at(s_mid, 0.0).y
	var stand := Node3D.new()
	stand.name = "Grandstand"
	# Local frame: -z along the track (forward), +x away from the road.
	stand.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
	world.stand_xf = stand.transform
	parent.add_child(stand)
	var theme := KartLook.theme
	var length := KartWorld.STAND_LENGTH
	var rows := KartWorld.STAND_ROWS
	var depth := 0.95
	var rise := 0.6
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 6.0
	kit.ao_min = 0.6
	var concrete := Color(0.78, 0.77, 0.74, 0.0)
	var seat_a: Color = look.stand_a
	var seat_b: Color = look.stand_b
	var roof: Color = look.stand_roof
	var white := Color(0.97, 0.97, 0.97, 0.0)
	var snow := Color(0.95, 0.97, 1.0, 0.0)
	var wood := Color(0.56, 0.38, 0.24, 0.0)
	if theme == "canyon":
		concrete = Color(0.82, 0.66, 0.5, 0.0)  # adobe
	# Footings down to the land, so the stand never floats over a dip.
	kit.add(MeshKit3D.box(Vector3(back_x(rows, depth) + 0.6, 6.0, length)), MeshKit3D.xf(Vector3(back_x(rows, depth) * 0.5, -3.0, 0)), concrete.darkened(0.2))
	# Front wall with a coloured fascia.
	kit.add(MeshKit3D.box(Vector3(0.4, 1.4, length)), MeshKit3D.xf(Vector3(0.0, 0.7, 0)), concrete)
	kit.add(MeshKit3D.box(Vector3(0.45, 0.35, length)), MeshKit3D.xf(Vector3(-0.02, 1.25, 0)), Color(roof.r, roof.g, roof.b, 0.0))
	for r in rows:
		var x := 0.6 + r * depth
		var y := 1.2 + r * rise
		kit.add(MeshKit3D.box(Vector3(depth, y, length)), MeshKit3D.xf(Vector3(x + depth * 0.5, y * 0.5, 0)), concrete)
		if theme == "frost":
			# Wooden benches, a dusting of snow on each.
			var plank: Color = wood if r % 2 == 0 else wood.darkened(0.12)
			kit.add(MeshKit3D.box(Vector3(0.42, 0.12, length)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.3, 0)), plank)
			kit.add(MeshKit3D.box(Vector3(0.44, 0.04, length)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.38, 0)), snow)
			for z in range(-int(length * 0.5) + 2, int(length * 0.5), 6):
				kit.add(MeshKit3D.box(Vector3(0.08, 0.26, 0.08)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.13, z)), wood.darkened(0.3))
		else:
			var seat: Color = seat_a if r % 2 == 0 else seat_b
			kit.add(MeshKit3D.box(Vector3(0.35, 0.22, length)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.11, 0)), Color(seat.r, seat.g, seat.b, 0.0))
	var bx := back_x(rows, depth)
	var top_y := 1.2 + rows * rise
	kit.add(MeshKit3D.box(Vector3(0.4, top_y + 2.6, length)), MeshKit3D.xf(Vector3(bx + 0.2, (top_y + 2.6) * 0.5, 0)), Color(seat_a.r * 0.5, seat_a.g * 0.5, seat_a.b * 0.6, 0.0))
	kit.add(MeshKit3D.box(Vector3(0.1, 0.5, length)), MeshKit3D.xf(Vector3(bx - 0.02, top_y + 0.9, 0)), Color(seat_b.r, seat_b.g, seat_b.b, 0.0))
	# Roof on posts.
	for i in 8:
		var z := -length * 0.5 + 2.0 + i * (length - 4.0) / 7.0
		kit.add(MeshKit3D.cylinder(0.12, 0.12, 4.6, 6), MeshKit3D.xf(Vector3(0.3, top_y + 0.6 - 1.6, z)),
			wood if theme == "frost" else Color(0.9, 0.9, 0.92, 0.0))
	var roof_y := top_y + 2.75
	for i in 12:
		var z0 := -length * 0.5 + i * length / 12.0
		var stripe := white if i % 2 == 0 else Color(roof.r, roof.g, roof.b, 0.0)
		if theme == "frost":
			stripe = Color(roof.r, roof.g, roof.b, 0.0)  # dark timber under the snow
		kit.add(MeshKit3D.box(Vector3(bx + 1.4, 0.25, length / 12.0)),
			MeshKit3D.xf(Vector3(bx * 0.5 + 0.1, roof_y, z0 + length / 24.0), Vector3(0, 0, -7)), stripe)
	match theme:
		"frost":
			# A thick blanket of snow on the roof, rounded at the eave, and icicles under it.
			kit.add(MeshKit3D.box(Vector3(bx + 1.5, 0.45, length + 0.3)), MeshKit3D.xf(Vector3(bx * 0.5 + 0.1, roof_y + 0.3, 0), Vector3(0, 0, -7)), snow)
			kit.add(MeshKit3D.cylinder(0.32, 0.32, length + 0.3, 6), MeshKit3D.xf(Vector3(-0.6, roof_y + 0.08 + 0.1, 0), Vector3(90, 0, 0)), snow)
			var r2 := RandomNumberGenerator.new()
			r2.seed = 17
			var z := -length * 0.5 + 0.5
			while z < length * 0.5:
				var l := r2.randf_range(0.3, 0.8)
				kit.add(MeshKit3D.cylinder(0.06, 0.0, l, 4), MeshKit3D.xf(Vector3(-0.62, roof_y - 0.12 - l * 0.5, z), Vector3(180, 0, 0)), Color(0.8, 0.9, 1.0, 0.3))
				z += r2.randf_range(0.5, 1.4)
		"canyon":
			# The striped awning runs out over the front rows on poles; red rock piles at the ends.
			for i in 12:
				var z0 := -length * 0.5 + i * length / 12.0
				var c := white if i % 2 == 0 else Color(look.gate_band.r, look.gate_band.g, look.gate_band.b, 0.0)
				kit.add(MeshKit3D.box(Vector3(2.6, 0.12, length / 12.0)), MeshKit3D.xf(Vector3(-1.3, roof_y - 0.75, z0 + length / 24.0), Vector3(0, 0, 18)), c)
				var flap := MeshKit3D.prism(Vector3(length / 12.0, 0.5, 0.06))
				kit.add(flap, MeshKit3D.xf(Vector3(-2.55, roof_y - 1.4, z0 + length / 24.0), Vector3(180, 90, 0)), c)
			for z: float in [-length * 0.5 - 4.0, length * 0.5 + 4.0]:
				for k in 3:
					kit.add(KartDress.rock_mesh(Color(0.74, 0.34, 0.2), 40 + k), MeshKit3D.xf(Vector3(1.5 + k * 3.0, -0.5, z + (k - 1) * 1.5), Vector3(0, k * 50, 0), Vector3(3.2, 4.0 + k * 1.6, 3.2) * (1.2 - k * 0.15)), Color(0.74, 0.34, 0.2, 0.0))
		"harbor":
			# Iron lamp posts along the front, lanterns lit (props_mat: alpha is glow).
			var iron := Color(0.14, 0.16, 0.2, 0.0)
			var z := -length * 0.5 + 6.0
			while z < length * 0.5:
				kit.add(MeshKit3D.cylinder(0.08, 0.12, 4.6, 6), MeshKit3D.xf(Vector3(-0.5, 2.3, z)), iron)
				kit.add(MeshKit3D.box(Vector3(0.36, 0.5, 0.36)), MeshKit3D.xf(Vector3(-0.5, 4.75, z)), Color(1.0, 0.86, 0.55, 1.0))
				kit.add(MeshKit3D.prism(Vector3(0.55, 0.3, 0.55)), MeshKit3D.xf(Vector3(-0.5, 5.15, z)), iron)
				stand_lamps.append(stand.transform * Vector3(-0.5, 4.75, z))
				z += 12.0
	stand.add_child(MeshKit3D.mesh_node(kit.commit(), world.props_mat, "Stand"))
	if not stand_lamps.is_empty():
		var halos := []
		var colors := []
		for p: Vector3 in stand_lamps:
			halos.append(Transform3D(Basis().scaled(Vector3.ONE * 2.6), p))
			colors.append(Color(1.0, 0.75, 0.4, 0.55))
		var lamp_halos := MeshKit3D.multimesh_node(halo_quad(), halos, "StandHalos", [], colors)
		parent.add_child(lamp_halos)
	_build_stand_banners(world, stand, roof_y, length)
	return _build_crowd(world, stand, rows, depth, rise, length)


## Accent banners hanging from the stand's roof edge (the banner cloth sways).
static func _build_stand_banners(world: KartWorld, stand: Node3D, roof_y: float, length: float) -> void:
	var look := world.look
	var accents: Array = [look.gate_band, look.stand_roof, look.stand_b, look.stand_a]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 7
	for b in count:
		var z0 := -length * 0.5 + (b + 0.5) * length / count - 0.8
		var c: Color = accents[b % accents.size()]
		var w := 1.6
		var h := 2.3
		var nx := 2
		var ny := 5
		for i in nx:
			for j in ny:
				var u0 := float(i) / nx
				var u1 := float(i + 1) / nx
				var v0 := float(j) / ny
				var v1 := float(j + 1) / ny
				# A white band near the foot, and a pointed tail.
				var col := Color(0.97, 0.97, 0.97) if j == ny - 2 else Color(c.r, c.g, c.b)
				for uv in [[u0, v0], [u1, v0], [u1, v1], [u0, v0], [u1, v1], [u0, v1]]:
					var v: float = uv[1]
					var u: float = uv[0]
					var tail := 0.0
					if j == ny - 1 and v > v0:
						tail = 0.45 * (1.0 - absf(u - 0.5) * 2.0)
					st.set_color(col)
					st.set_uv(Vector2(u, v))
					st.set_normal(Vector3.LEFT)
					st.add_vertex(Vector3(-0.75, roof_y - 0.2 - (v + tail * 0.25) * h, z0 + u * w))
	var node := MeshKit3D.mesh_node(st.commit(), world.banner_mat, "StandBanners")
	stand.add_child(node)


## The crowd: one MultiMesh of fans (crowd.gdshader). Each row has its own mix of shirts (the
## home colours toward the front, a supporters' block in the theme's accent) and heights; some
## fans wave their arms, and a stadium wave runs along the stand.
## The crowd's instances: {transforms, custom (crowd.gdshader's INSTANCE_CUSTOM), colors (the
## shirts)}, for theme `theme_look` (KartLook's values) named `theme`.
static func crowd_data(theme_look: Dictionary, theme: String, rows: int, depth: float, rise: float, length: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var xfs := []
	var custom := []
	var colors := []
	var shirts := [Color(0.95, 0.25, 0.2), Color(1.0, 0.8, 0.2), Color(0.25, 0.55, 1.0), Color(0.3, 0.8, 0.4),
		Color(0.95, 0.5, 0.8), Color(0.98, 0.98, 0.98), Color(0.6, 0.35, 0.9), Color(1.0, 0.55, 0.15), Color(0.2, 0.75, 0.8)]
	var row_tints: Array = [theme_look.stand_a, theme_look.gate_band, theme_look.stand_b, Color(0.98, 0.98, 0.98)]
	if theme == "frost":
		# Winter coats: deeper colours.
		shirts = [Color(0.85, 0.15, 0.2), Color(0.15, 0.35, 0.75), Color(0.2, 0.55, 0.35), Color(0.95, 0.75, 0.2),
			Color(0.45, 0.25, 0.6), Color(0.9, 0.45, 0.15), Color(0.2, 0.2, 0.25)]
	for r in rows:
		var x := 0.6 + r * depth + 0.45
		var y := 1.2 + r * rise - 0.15
		var z := -length * 0.5 + 0.6
		var tint: Color = row_tints[r % row_tints.size()]
		var tint_share := 0.55 if r % 3 == 1 else 0.2
		var row_height := 0.94 + 0.05 * float((r * 7) % 3)
		while z < length * 0.5 - 0.5:
			# Not every seat is taken: the alpha-tested fans are the start's costliest pixels.
			if rng.randf() < 0.7:
				var sc := rng.randf_range(0.92, 1.1)
				xfs.append(Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(x + rng.randf_range(-0.1, 0.1), y, z)))
				var c: Color = shirts[rng.randi() % shirts.size()]
				colors.append(c.lerp(tint, tint_share))
				var tall := row_height * (0.78 if rng.randf() < 0.08 else rng.randf_range(0.92, 1.12))
				var waver := 2.0 if rng.randf() < 0.3 else 0.0
				custom.append(Color(tall, rng.randf(), rng.randf(), clampf((z + length * 0.5) / length, 0.0, 0.999) + waver))
			z += rng.randf_range(0.6, 0.8)
	# Shuffled, so the quality governor's share of the crowd thins every row evenly.
	for i in range(xfs.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		for arr: Array in [xfs, custom, colors]:
			var t: Variant = arr[i]
			arr[i] = arr[j]
			arr[j] = t
	return {"transforms": xfs, "custom": custom, "colors": colors}


static func _build_crowd(world: KartWorld, stand: Node3D, rows: int, depth: float, rise: float, length: float) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 1.0)
	quad.center_offset = Vector3(0, 0.5, 0)
	var data := crowd_data(world.look, KartLook.theme, rows, depth, rise, length)
	var xfs: Array = data.transforms
	var custom: Array = data.custom
	var colors: Array = data.colors
	var crowd := world.mm(quad, xfs, "Crowd", world.crowd_mat, custom, colors)
	stand.add_child(crowd)
	return crowd.multimesh


static func back_x(rows: int, depth: float) -> float:
	return 0.6 + rows * depth


## The start gate over the line: pillars, a beam with five lamps, chequered banners. Returns the
## lamps' additive halos (KartWorld.set_start_lights drives them).
static func build_gate(world: KartWorld, parent: Node3D) -> MultiMeshInstance3D:
	var track := world.track
	var look := world.look
	var s := 1.0
	var hw := track.half_width(s)
	var yaw := track.yaw_at(s)
	var gate := Node3D.new()
	gate.name = "StartGate"
	gate.transform = Transform3D(Basis(Vector3.UP, yaw), track.position_at(s, 0.0))
	parent.add_child(gate)
	var span := hw + KartTrackModel.KERB_WIDTH + 1.4
	var height := 6.4
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 4.0
	kit.ao_min = 0.65
	var navy: Color = look.gate
	navy.a = 0.0
	var band: Color = look.gate_band
	band.a = 0.0
	var white := Color(0.96, 0.96, 0.97, 0.0)
	for side: float in [-1.0, 1.0]:
		kit.add(MeshKit3D.box(Vector3(1.0, height + 1.2, 1.0)), MeshKit3D.xf(Vector3(side * span, (height + 1.2) * 0.5, 0)), white)
		for k in 4:
			kit.add(MeshKit3D.box(Vector3(1.04, 0.4, 1.04)), MeshKit3D.xf(Vector3(side * span, 0.8 + k * 1.5, 0)), band)
		kit.add(MeshKit3D.box(Vector3(1.6, 3.0, 1.6)), MeshKit3D.xf(Vector3(side * span, -1.0, 0)), navy)
	kit.add(MeshKit3D.box(Vector3(span * 2.0 + 1.0, 1.5, 1.1)), MeshKit3D.xf(Vector3(0, height, 0)), navy)
	# Chequered fascia on both faces of the beam.
	var cells := 24
	for face: float in [-1.0, 1.0]:
		for i in cells:
			for j in 2:
				var x0 := -span - 0.5 + (span * 2.0 + 1.0) * i / cells
				var x1 := -span - 0.5 + (span * 2.0 + 1.0) * (i + 1) / cells
				var y0 := height + 0.75 - 0.4 * (j + 1)
				var y1 := y0 + 0.4
				var c := Color(0.05, 0.05, 0.06, 0.0) if (i + j) % 2 == 0 else Color(0.97, 0.97, 0.97, 0.0)
				var z := face * 0.56
				if face > 0.0:
					kit.quad(Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x1, y1, z), Vector3(x1, y0, z), c)
				else:
					kit.quad(Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), Vector3(x0, y0, z), c)
	# Lamp housings on the grid side (+z: behind the line, where the karts wait).
	kit.add(MeshKit3D.box(Vector3(5.2, 1.0, 0.5)), MeshKit3D.xf(Vector3(0, height - 1.15, 0.5)), Color(0.08, 0.08, 0.1, 0.0))
	gate.add_child(MeshKit3D.mesh_node(kit.commit(), world.scenery_mat, "Gate"))
	var lamps := MeshKit3D.new()
	var halo_xfs := []
	for i in 5:
		var x := -2.0 + i * 1.0
		lamps.add(MeshKit3D.sphere(0.3, 10, 5), MeshKit3D.xf(Vector3(x, height - 1.15, 0.78)), Color(i / 5.0, 1.0, 0.0))
		halo_xfs.append(Transform3D(Basis().scaled(Vector3.ONE * 1.6), gate.transform * Vector3(x, height - 1.15, 0.95)))
	gate.add_child(MeshKit3D.mesh_node(lamps.commit(), world.lamps_mat, "Lamps"))
	# Fake glow: additive halos for the lit lamps (cheaper than Environment glow).
	var halos := MultiMeshInstance3D.new()
	halos.name = "LampHalos"
	halos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.use_colors = true
	mmesh.mesh = halo_quad()
	mmesh.instance_count = halo_xfs.size()
	for i in halo_xfs.size():
		mmesh.set_instance_transform(i, halo_xfs[i])
		mmesh.set_instance_color(i, Color(1, 0.3, 0.2, 0.9))
	halos.multimesh = mmesh
	parent.add_child(halos)
	# Chequered banners hanging from the beam on the road side.
	var banner := SurfaceTool.new()
	banner.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: float in [-1.0, 1.0]:
		var x0 := b * (span - 2.6) - 1.0
		var top := height - 0.75
		var w := 2.0
		var h := 1.6
		var nx := 6
		var ny := 5
		for i in nx:
			for j in ny:
				var c := Color(0.05, 0.05, 0.06) if (i + j) % 2 == 0 else Color(0.97, 0.97, 0.97)
				var u0 := float(i) / nx
				var u1 := float(i + 1) / nx
				var v0 := float(j) / ny
				var v1 := float(j + 1) / ny
				for uv in [[u0, v0], [u1, v0], [u1, v1], [u0, v0], [u1, v1], [u0, v1]]:
					banner.set_color(c)
					banner.set_uv(Vector2(uv[0], uv[1]))
					banner.set_normal(Vector3.BACK)
					banner.add_vertex(Vector3(x0 + uv[0] * w, top - uv[1] * h, 0.62))
	gate.add_child(MeshKit3D.mesh_node(banner.commit(), world.banner_mat, "Banners"))
	return halos


## A soft additive billboard (lamp halos; dressers use it for bulbs that should bloom).
static func halo_quad() -> QuadMesh:
	if _halo_quad == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = MeshKit3D.soft_disc(64)
		mat.disable_fog = true
		_halo_quad = QuadMesh.new()
		_halo_quad.size = Vector2(1.0, 1.0)
		_halo_quad.material = mat
	return _halo_quad


## Flags on tall poles along both sides of the start straight (not in front of the stand).
static func build_flags(world: KartWorld, parent: Node3D) -> void:
	var track := world.track
	var look := world.look
	var poles := MeshKit3D.new()
	var flag_xfs := []
	var custom := []
	var n := 0
	var s := -70.0
	while s < 40.0:
		var ss := track.wrap(s)
		var hw := track.half_width(ss)
		for side: float in [-1.0, 1.0]:
			if side > 0.0 and s > -66.0 and s < 22.0:
				continue  # the grandstand is there
			var p := track.position_at(ss, side * (hw + track.verge + 1.2))
			poles.add(MeshKit3D.cylinder(0.06, 0.08, 9.0, 5), MeshKit3D.xf(p + Vector3.UP * 2.5), Color(0.92, 0.92, 0.94, 0.0))
			var yaw := track.yaw_at(ss) + PI * 0.5
			flag_xfs.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 6.3))
			custom.append(KartWorld.FLAG_COLORS[n % KartWorld.FLAG_COLORS.size()])
			n += 1
		s += 7.0
	if world.has_grandstand():
		# Flags along the back of the stand's roof, in the theme's accents.
		var accents: Array = [look.gate_band, look.stand_roof, look.stand_b, Color(0.98, 0.98, 0.98)]
		var bx := back_x(KartWorld.STAND_ROWS, 0.95)
		var roof_top := 1.2 + KartWorld.STAND_ROWS * 0.6 + 2.75 + bx * 0.5 * tan(deg_to_rad(7.0))
		var k := 0
		var z := -KartWorld.STAND_LENGTH * 0.5 + 4.0
		while z < KartWorld.STAND_LENGTH * 0.5:
			var foot := world.stand_xf * Vector3(bx + 0.3, roof_top - 0.6, z)
			poles.add(MeshKit3D.cylinder(0.05, 0.07, 3.6, 5), MeshKit3D.xf(foot + Vector3.UP * 1.8), Color(0.92, 0.92, 0.94, 0.0))
			flag_xfs.append(Transform3D(Basis(Vector3.UP, track.yaw_at(track.wrap(-22.0)) + PI * 0.5).scaled(Vector3.ONE * 0.8), foot + Vector3.UP * 3.5))
			var c: Color = accents[k % accents.size()]
			custom.append(Color(c.r, c.g, c.b, 1.0))
			k += 1
			z += 10.5
	parent.add_child(MeshKit3D.mesh_node(poles.commit(), world.scenery_mat, "FlagPoles"))
	parent.add_child(world.mm(flag_cloth(), flag_xfs, "Flags", world.flag_mat, custom))


## A flag's cloth, 1.7 × 1.05 m from the pole along +x; UV.x runs along it (the wave grows).
static func flag_cloth() -> ArrayMesh:
	if _cloth == null:
		var cloth := PlaneMesh.new()
		cloth.size = Vector2(1.7, 1.05)
		cloth.subdivide_width = 8
		cloth.orientation = PlaneMesh.FACE_Z
		cloth.center_offset = Vector3(0.85, -0.5, 0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var arr := cloth.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			st.set_color(Color.WHITE if uvs[i].y > 0.25 else Color(0.85, 0.85, 0.85))
			st.set_uv(Vector2(verts[i].x / 1.7, uvs[i].y))
			st.set_normal(Vector3.BACK)
			st.add_vertex(verts[i])
		_cloth = st.commit()
	return _cloth


## The crowd sprite, two 32x48 frames side by side: a fan in a T-shirt (R), the head (G) and the
## arms (B): raised in the left frame, out to the sides in the right (crowd.gdshader flips them).
static func crowd_sprite() -> ImageTexture:
	var w := 32
	var h := 48
	var img := Image.create(w * 2, h, true, Image.FORMAT_RGBA8)
	for frame in 2:
		for y in h:
			for x in w:
				var p := Vector2(x + 0.5, y + 0.5)
				var head := p.distance_to(Vector2(16, 12)) < 7.0
				var body := Rect2(7, 19, 18, 29).has_point(p) and p.distance_to(Vector2(16, 26)) < 13.5
				var arms := false
				if frame == 0:
					arms = (absf(p.x - 5.0) < 2.2 or absf(p.x - 27.0) < 2.2) and p.y > 6.0 and p.y < 24.0
				else:
					# Out and a little down, hands at the frame's edges.
					var ax := absf(p.x - 16.0)
					arms = ax > 8.0 and ax < 15.0 and absf(p.y - (21.0 + (ax - 8.0) * 0.45)) < 2.3
				var c := Color(0, 0, 0, 0)
				if head:
					c = Color(0, 1, 0, 1)
				elif body:
					c = Color(1, 0, 0, 1)
				elif arms:
					c = Color(0, 0, 1, 1)
				img.set_pixel(frame * w + x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
