extends KartDress
## Harbor Lights' dressing (#43): a seaside town at sunset. The start straight runs along a
## stone quay with the sea glittering into the low sun; piers reach out with boats moored
## alongside and a striped lighthouse at the end of the breakwater. Pastel houses with lit
## windows line the streets, festoons of coloured bulbs swing over the start, and lamp posts
## glow along the way.

const WATER_Y := 0.15  ## above the land's floor (world.centre.y)
const QUAY_HALF := 320.0  ## the quay runs this far either way along the shore

var _shore := {}
var _barrels := [MeshKit3D.barrel(Color(0.2, 0.4, 0.75, 0.0)), MeshKit3D.barrel(Color(0.8, 0.22, 0.2, 0.0)),
	MeshKit3D.barrel(Color(0.25, 0.6, 0.4, 0.0))]
var _bulbs := []  ## halo transforms
var _bulb_colors := []


## Metres from the shore line toward the sea (negative inland).
func sea_dist(x: float, z: float) -> float:
	if _shore.is_empty():
		_shore = world.landmark("shore")
	if _shore.is_empty():
		return -1000.0
	var p: Vector3 = _shore.p
	return Vector3(x - p.x, 0.0, z - p.z).dot(_shore.out as Vector3)


func base_height(x: float, z: float, _r_road: float) -> float:
	var g := world.centre.y
	var sd := sea_dist(x, z)
	if sd > 0.0:
		return g - 1.6 - 7.0 * smoothstep(0.0, 40.0, sd) + 0.6 * noise.get_noise_2d(x * 3.0, z * 3.0)
	var inland := smoothstep(-60.0, -220.0, sd)
	return g + 0.4 * noise.get_noise_2d(x * 3.0, z * 3.0) + inland * hills(x, z, 6.0, 38.0, 35.0)


## The town is paved (the theme's ground colours); green on the hills and in the parks.
func ground_tint(x: float, z: float, h: float) -> Color:
	var green := smoothstep(world.centre.y + 1.5, world.centre.y + 6.0, h)
	green = maxf(green, smoothstep(0.55, 0.75, noise.get_noise_2d(x * 2.0, z * 2.0) * 0.5 + 0.5) * 0.8)
	if sea_dist(x, z) > -4.0:
		# The beach and the shallows: sand.
		return Color(1.25, 1.15, 0.95)
	return Color(1.0, 1.0, 1.0).lerp(Color(0.68, 1.0, 0.55), green)


func dress_hero(scenery: Node3D, props: Dictionary) -> void:
	_lighthouse(scenery, props)


func dress(scenery: Node3D, foliage: Dictionary, props: Dictionary, woods: Array) -> void:
	world.water_mat.set_shader_parameter("ice", 0.0)
	KartLook.apply(world.water_mat, {"deep": Color(0.12, 0.16, 0.36), "shallow": Color(0.22, 0.34, 0.56),
		"reflect_color": Color(1.0, 0.6, 0.45)})
	_sea(scenery)
	_quay(props)
	_piers(props)
	_clocktower(props)
	_houses(props)
	_lights(props)
	_lamp_posts(props)
	var trees := tree_meshes(Color(0.26, 0.5, 0.2))
	scatter(foliage, trees, 60, 4.0, 40.0, Vector2(0.7, 1.1), func(r: RandomNumberGenerator) -> int: return 0 if r.randf() < 0.7 else 2)
	scatter_far(woods, trees, 90, 40.0, 220.0, Vector2(1.3, 2.0), func(r: RandomNumberGenerator) -> int: return 3 if r.randf() < 0.6 else 0)
	_halos(scenery)


func _sea(parent: Node3D) -> void:
	if _shore.is_empty():
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2(2600.0, 1400.0)
	var node := MeshKit3D.mesh_node(plane, world.water_mat, "Sea")
	var dir: Vector3 = _shore.dir
	var out: Vector3 = _shore.out
	var p: Vector3 = _shore.p
	# PlaneMesh lies in x/z: x along the shore, z out to sea (it's two-sided).
	node.transform = Transform3D(Basis(dir, Vector3.UP, dir.cross(Vector3.UP)).orthonormalized(),
		Vector3(p.x, world.centre.y + WATER_Y, p.z) + out * 700.0)
	parent.add_child(node)


## The quay: a stone deck along the shore with a sheer face into the water and a kerb of
## bollards.
func _quay(props: Dictionary) -> void:
	if _shore.is_empty():
		return
	var dir: Vector3 = _shore.dir
	var out: Vector3 = _shore.out
	var p0: Vector3 = _shore.p
	var top := world.track.sample(_shore.s).position.y - 0.04
	var low := world.centre.y - 3.0
	var stone := Color(0.66, 0.6, 0.56, 0.0)
	var face := Color(0.46, 0.42, 0.42, 0.0)
	var step := 20.0
	var u := -QUAY_HALF
	while u < QUAY_HALF:
		var a := p0 + dir * u
		var b := p0 + dir * (u + step)
		var kit := world.cell(props, a)
		var ia := a - out * 10.0
		var ib := b - out * 10.0
		a.y = top
		b.y = top
		ia.y = top
		ib.y = top
		kit.quad(ia, a, b, ib, stone)
		kit.quad(a, a + Vector3.DOWN * (top - low), b + Vector3.DOWN * (top - low), b, face)
		kit.quad(ib, ib + Vector3.DOWN * 2.0, ia + Vector3.DOWN * 2.0, ia, face)
		# A bollard every 20 m, and crates or barrels now and then.
		var bp := a + dir * 4.0 - out * 0.6
		kit.add(MeshKit3D.cylinder(0.2, 0.26, 0.6, 8), MeshKit3D.xf(bp + Vector3.UP * 0.3), Color(0.15, 0.16, 0.2, 0.0))
		if rng.randf() < 0.45:
			var cp := a + dir * 11.0 - out * rng.randf_range(2.5, 6.0)
			if rng.randf() < 0.5:
				kit.add(MeshKit3D.box(Vector3(1.1, 1.0, 1.1)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), cp + Vector3.UP * 0.5), Color(0.62, 0.42, 0.24, 0.0))
				kit.add(MeshKit3D.box(Vector3(0.9, 0.8, 0.9)), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), cp + Vector3.UP * 1.4), Color(0.7, 0.5, 0.3, 0.0))
			else:
				for k in 3:
					kit.add(_barrels[k], MeshKit3D.xf(cp + dir * (k * 0.8)), Color.WHITE)
		u += step


## Wooden piers on posts with boats moored alongside.
func _piers(props: Dictionary) -> void:
	if _shore.is_empty():
		return
	var dir: Vector3 = _shore.dir
	var out: Vector3 = _shore.out
	var p0: Vector3 = _shore.p
	var deck_y := world.track.sample(_shore.s).position.y - 0.25
	var water := world.centre.y + WATER_Y
	var wood := Color(0.55, 0.4, 0.26, 0.0)
	var boats := [_boat(Color(0.9, 0.25, 0.2)), _boat(Color(0.2, 0.45, 0.85)), _boat(Color(0.98, 0.95, 0.9)), _boat(Color(0.2, 0.62, 0.5))]
	for u: float in [-200.0, -90.0, 60.0, 170.0]:
		var base := p0 + dir * u
		var length := 38.0
		var kit := world.cell(props, base + out * 20.0)
		var mid := base + out * (length * 0.5)
		mid.y = deck_y
		kit.add(MeshKit3D.box(Vector3(4.0, 0.3, length)), Transform3D(Basis(dir, Vector3.UP, out), mid), wood)
		var v := 3.0
		while v < length:
			for side: float in [-1.8, 1.8]:
				var post := base + out * v + dir * side
				post.y = (deck_y + water - 2.0) * 0.5
				kit.add(MeshKit3D.cylinder(0.16, 0.16, deck_y - water + 2.0, 6), MeshKit3D.xf(post), Color(0.35, 0.26, 0.18, 0.0))
			v += 6.0
		# Boats either side.
		for k in 2:
			var side := -1.0 if k == 0 else 1.0
			var bp := base + out * rng.randf_range(12.0, 30.0) + dir * side * 5.2
			bp.y = water
			var yaw := Basis(Vector3.UP, atan2(-out.x, -out.z) + rng.randf_range(-0.1, 0.1))
			world.cell(props, bp).add_baked(boats[rng.randi() % boats.size()], Transform3D(yaw, bp))


## A small boat facing -z: a coloured hull with a pointed bow, a white cabin, a mast and sail.
static func _boat(hull: Color) -> ArrayMesh:
	var kit := MeshKit3D.new()
	var h := Color(hull.r, hull.g, hull.b, 0.0)
	kit.add(MeshKit3D.box(Vector3(2.4, 1.1, 5.0)), MeshKit3D.xf(Vector3(0, 0.25, 0.4)), h)
	kit.add(MeshKit3D.prism(Vector3(2.4, 2.0, 1.1)), MeshKit3D.xf(Vector3(0, 0.25, -2.6), Vector3(90, 0, 0)), h)
	kit.add(MeshKit3D.box(Vector3(2.5, 0.16, 5.1)), MeshKit3D.xf(Vector3(0, 0.82, 0.4)), Color(0.96, 0.96, 0.94, 0.0))
	kit.add(MeshKit3D.box(Vector3(1.6, 1.0, 1.8)), MeshKit3D.xf(Vector3(0, 1.35, 1.2)), Color(0.97, 0.97, 0.97, 0.0))
	kit.add(MeshKit3D.box(Vector3(1.62, 0.3, 1.4)), MeshKit3D.xf(Vector3(0, 1.55, 1.2)), Color(0.3, 0.45, 0.6, 0.25))
	kit.add(MeshKit3D.cylinder(0.07, 0.09, 6.5, 5), MeshKit3D.xf(Vector3(0, 4.0, -0.4)), Color(0.85, 0.85, 0.85, 0.0))
	kit.add(MeshKit3D.prism(Vector3(2.4, 5.0, 0.05)), MeshKit3D.xf(Vector3(0, 4.0, 0.6), Vector3(0, 90, 0)), Color(1.0, 0.97, 0.92, 0.15))
	return kit.commit()


## A striped lighthouse at the end of a rock breakwater, its lamp glowing.
func _lighthouse(parent: Node3D, props: Dictionary) -> void:
	if _shore.is_empty():
		return
	var dir: Vector3 = _shore.dir
	var out: Vector3 = _shore.out
	var p0: Vector3 = _shore.p
	var water := world.centre.y + WATER_Y
	var base := p0 + dir * 260.0
	var reach := 64.0
	var lm := world.landmark("lighthouse")
	if not lm.is_empty():
		# On the point: from the shore line nearest the landmark, out until it stands in the sea.
		var lp: Vector3 = lm.p
		base = lp - out * sea_dist(lp.x, lp.z)
		reach = 34.0
	# The breakwater: boulders in a line out to sea.
	var rock := rock_mesh(Color(0.5, 0.48, 0.5), 21)
	for k in int(reach / 4.5) - 1:
		var bp := base + out * (k * 4.5) + dir * rng.randf_range(-1.0, 1.0)
		bp.y = water - 0.6
		world.cell(props, bp).add_baked(rock, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(2.0, 2.8)), bp))
	var at := base + out * reach
	at.y = water + 0.6
	hero = {"p": at + Vector3.UP * 14.0, "size": 28.0}
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 12.0
	kit.ao_min = 0.7
	kit.add(MeshKit3D.cylinder(3.4, 3.8, 2.0, 12), MeshKit3D.xf(Vector3(0, 0.0, 0)), Color(0.5, 0.48, 0.5, 0.0))
	for k in 6:
		var r0 := lerpf(2.2, 1.5, k / 6.0)
		var r1 := lerpf(2.2, 1.5, (k + 1) / 6.0)
		kit.add(MeshKit3D.cylinder(r1, r0, 2.6, 12), MeshKit3D.xf(Vector3(0, 1.3 + k * 2.6, 0)),
			Color(0.95, 0.95, 0.95, 0.05) if k % 2 == 0 else Color(0.88, 0.16, 0.16, 0.05))
	kit.add(MeshKit3D.cylinder(2.0, 2.0, 0.3, 12), MeshKit3D.xf(Vector3(0, 16.9, 0)), Color(0.15, 0.15, 0.18, 0.0))
	kit.add(MeshKit3D.cylinder(1.0, 1.0, 1.6, 10), MeshKit3D.xf(Vector3(0, 17.9, 0)), Color(1.0, 0.92, 0.6, 1.0))
	kit.add(MeshKit3D.cylinder(0.0, 1.3, 1.2, 10), MeshKit3D.xf(Vector3(0, 19.3, 0)), Color(0.88, 0.16, 0.16, 0.0))
	# A third bigger than life: it's the town's landmark from the grid.
	world.cell(props, at).add_baked(kit.commit(), Transform3D(Basis().scaled(Vector3.ONE * 1.3), at))
	_bulbs.append(Transform3D(Basis().scaled(Vector3.ONE * 9.0), at + Vector3.UP * 17.9 * 1.3))
	_bulb_colors.append(Color(1.0, 0.85, 0.5, 0.9))


## The old town's clock tower: a stone shaft, a lit clock face on each side, an open belfry
## and a copper spire.
func _clocktower(props: Dictionary) -> void:
	var lm := world.landmark("clocktower")
	if lm.is_empty() or not world.clear_of_road(lm.p, 3.0):
		return
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 8.0
	kit.ao_min = 0.7
	var stone := Color(0.86, 0.8, 0.7, 0.1)
	var trim := Color(0.96, 0.95, 0.92, 0.1)
	kit.add(MeshKit3D.box(Vector3(5.0, 22.0, 5.0)), MeshKit3D.xf(Vector3(0, 9.0, 0)), stone)
	for y: float in [6.0, 13.0, 20.2]:
		kit.add(MeshKit3D.box(Vector3(5.4, 0.4, 5.4)), MeshKit3D.xf(Vector3(0, y, 0)), trim)
	for k in 4:
		var rot := Basis(Vector3.UP, k * PI * 0.5)
		# The clock: a glowing face, a dark rim, two hands.
		kit.add(MeshKit3D.cylinder(1.5, 1.5, 0.12, 14), Transform3D(rot * Basis(Vector3.RIGHT, PI * 0.5), rot * Vector3(0, 16.5, 2.52)), Color(1.0, 0.94, 0.78, 1.0))
		kit.add(MeshKit3D.torus(1.45, 1.7, 14, 4), Transform3D(rot * Basis(Vector3.RIGHT, PI * 0.5), rot * Vector3(0, 16.5, 2.55)), Color(0.2, 0.18, 0.2, 0.0))
		kit.add(MeshKit3D.box(Vector3(0.12, 1.0, 0.06)), Transform3D(rot, rot * Vector3(0, 16.9, 2.62)), Color(0.12, 0.1, 0.12, 0.0))
		kit.add(MeshKit3D.box(Vector3(0.7, 0.12, 0.06)), Transform3D(rot, rot * Vector3(0.3, 16.5, 2.62)), Color(0.12, 0.1, 0.12, 0.0))
		# The belfry's arch: a dark opening.
		kit.add(MeshKit3D.box(Vector3(2.0, 2.4, 0.1)), Transform3D(rot, rot * Vector3(0, 21.8, 2.52)), Color(0.12, 0.1, 0.14, 0.0))
	kit.add(MeshKit3D.box(Vector3(5.2, 3.2, 5.2)), MeshKit3D.xf(Vector3(0, 21.8, 0)), Color(0.8, 0.74, 0.64, 0.1))
	kit.add(MeshKit3D.cylinder(0.0, 3.9, 6.0, 4), MeshKit3D.xf(Vector3(0, 26.4, 0), Vector3(0, 45, 0)), Color(0.36, 0.62, 0.55, 0.0))
	kit.add(MeshKit3D.sphere(0.3, 6, 3), MeshKit3D.xf(Vector3(0, 29.6, 0)), Color(1.0, 0.82, 0.3, 0.3))
	var at: Vector3 = lm.p - Vector3.UP * 0.3
	var face: Vector3 = -(lm.out as Vector3)
	world.cell(props, at).add_baked(kit.commit(), Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), at))


## Pastel houses with lit windows along the streets (not on the quay side).
func _houses(props: Dictionary) -> void:
	var track := world.track
	var facades := [Color(0.98, 0.8, 0.62), Color(0.62, 0.82, 0.92), Color(0.98, 0.94, 0.78), Color(0.95, 0.62, 0.62),
		Color(0.72, 0.9, 0.72), Color(0.86, 0.74, 0.94), Color(0.98, 0.98, 0.96)]
	var roofs := [Color(0.62, 0.24, 0.18), Color(0.3, 0.32, 0.4), Color(0.42, 0.26, 0.22)]
	var meshes := []
	var widths := []
	for i in 9:
		var bays := 2 + (i * 5) % 3
		meshes.append(_house(facades[i % facades.size()], roofs[i % roofs.size()], 2 + i % 3, bays))
		widths.append(2.4 * bays + 1.2)
	for side: float in [-1.0, 1.0]:
		var s := 0.0
		while s < track.length:
			var pick := rng.randi() % meshes.size()
			var w: float = widths[pick] + rng.randf_range(1.5, 4.0)
			var out := rng.randf_range(4.5, 7.0)
			# On the inside of a bend the frontage is shorter: leave more room.
			w *= 1.0 + clampf(-track.curvature(track.wrap(s)) * side * 25.0, 0.0, 1.0)
			var spot = world.beyond(s, side, out + 4.0, 3.5)
			if spot != null and not (side > 0.0 and world.in_stand(s)) and sea_dist(spot.x, spot.z) < -14.0:
				var p: Vector3 = spot
				var face := -track.sample(track.wrap(s)).right * side
				p.y = minf(p.y, world.ground_at(p.x + face.x * 4.0, p.z + face.z * 4.0)) - 0.3
				var basis := Basis(Vector3.UP.cross(face), Vector3.UP, face)
				world.cell(props, p).add_baked(meshes[pick], Transform3D(basis, p))
			s += w


## A house facing +z, `floors` storeys of `bays` windows, with a pitched roof and a door.
static func _house(facade: Color, roof: Color, floors: int, bays: int) -> ArrayMesh:
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 3.0
	kit.ao_min = 0.75
	var w := 2.4 * bays + 1.2
	var h := 3.0 * floors + 0.6
	var d := 7.0
	var f := Color(facade.r, facade.g, facade.b, 0.12)
	kit.add(MeshKit3D.box(Vector3(w, h + 2.0, d)), MeshKit3D.xf(Vector3(0, (h - 2.0) * 0.5, -d * 0.5)), f)
	kit.add(MeshKit3D.prism(Vector3(w + 0.6, 2.6, d + 0.6)), MeshKit3D.xf(Vector3(0, h + 1.3, -d * 0.5)), Color(roof.r, roof.g, roof.b, 0.0))
	kit.add(MeshKit3D.box(Vector3(w + 0.1, 0.25, 0.3)), MeshKit3D.xf(Vector3(0, h, 0.05)), Color(0.96, 0.96, 0.94, 0.1))
	for fl in floors:
		for b in bays:
			var x := -w * 0.5 + 1.8 + b * 2.4
			var y := 1.6 + fl * 3.0
			if fl == 0 and b == bays / 2:
				kit.add(MeshKit3D.box(Vector3(1.2, 2.2, 0.1)), MeshKit3D.xf(Vector3(x, 1.1, 0.02)), Color(0.35, 0.22, 0.16, 0.0))
				continue
			var lit := (fl * 7 + b * 3 + bays) % 3 != 0
			kit.add(MeshKit3D.box(Vector3(1.0, 1.3, 0.1)), MeshKit3D.xf(Vector3(x, y, 0.02)),
				Color(1.0, 0.82, 0.45, 1.0) if lit else Color(0.2, 0.26, 0.4, 0.2))
			kit.add(MeshKit3D.box(Vector3(1.3, 0.12, 0.2)), MeshKit3D.xf(Vector3(x, y - 0.72, 0.06)), Color(0.96, 0.96, 0.94, 0.1))
	return kit.commit()


## Festoons of coloured bulbs: across the start straight between tall poles, and along it.
func _lights(props: Dictionary) -> void:
	var track := world.track
	var bulb_colors := [Color(1.0, 0.85, 0.35), Color(1.0, 0.4, 0.35), Color(0.45, 0.85, 1.0), Color(0.6, 1.0, 0.5), Color(1.0, 0.55, 0.85)]
	var pole := MeshKit3D.new()
	pole.add(MeshKit3D.cylinder(0.1, 0.14, 8.0, 6), MeshKit3D.xf(Vector3(0, 4.0, 0)), Color(0.2, 0.22, 0.28, 0.0))
	pole.add(MeshKit3D.sphere(0.18, 6, 3), MeshKit3D.xf(Vector3(0, 8.0, 0)), Color(0.2, 0.22, 0.28, 0.0))
	var pole_mesh := pole.commit()
	var tops := {-1.0: [], 1.0: []}
	var s := -60.0
	while s <= 110.0:
		var ss := track.wrap(s)
		var edge := track.half_width(ss) + track.verge + 0.9
		for side: float in [-1.0, 1.0]:
			if side > 0.0 and world.in_stand(ss) and s < 22.0:
				tops[side].append(null)
				continue
			var p := track.position_at(ss, side * edge)
			world.cell(props, p).add_baked(pole_mesh, Transform3D(Basis(), p))
			tops[side].append(p + Vector3.UP * 7.9)
		s += 24.0
	var count: int = tops[-1.0].size()
	for i in count:
		var l = tops[-1.0][i]
		var r = tops[1.0][i]
		if l != null and r != null:
			_festoon(props, l, r, 14, 1.4, bulb_colors)
		for side: float in [-1.0, 1.0]:
			if i + 1 < count and tops[side][i] != null and tops[side][i + 1] != null:
				_festoon(props, tops[side][i], tops[side][i + 1], 9, 1.0, bulb_colors)


## A sagging cable from a to b with `n` bulbs.
func _festoon(props: Dictionary, a: Vector3, b: Vector3, n: int, sag: float, colors: Array) -> void:
	var kit := world.cell(props, (a + b) * 0.5)
	var prev := a
	for k in range(1, n + 2):
		var t := float(k) / (n + 1)
		var p := a.lerp(b, t) + Vector3.DOWN * sag * 4.0 * t * (1.0 - t)
		var seg := p - prev
		kit.add(MeshKit3D.box(Vector3(0.03, seg.length(), 0.03)), Transform3D(along(seg), (p + prev) * 0.5), Color(0.1, 0.1, 0.12, 0.0))
		if k <= n:
			var c: Color = colors[(k + int(a.x)) % colors.size()]
			kit.add(MeshKit3D.sphere(0.13, 6, 3), MeshKit3D.xf(p + Vector3.DOWN * 0.15), Color(c.r, c.g, c.b, 1.0))
			if k % 2 == 0:
				_bulbs.append(Transform3D(Basis().scaled(Vector3.ONE * 0.9), p + Vector3.DOWN * 0.15))
				_bulb_colors.append(Color(c.r, c.g, c.b, 0.55))
		prev = p


## Old iron lamp posts with glowing lanterns along the streets.
func _lamp_posts(props: Dictionary) -> void:
	var track := world.track
	var kit := MeshKit3D.new()
	var iron := Color(0.14, 0.16, 0.2, 0.0)
	kit.add(MeshKit3D.cylinder(0.09, 0.14, 4.2, 6), MeshKit3D.xf(Vector3(0, 2.1, 0)), iron)
	kit.add(MeshKit3D.box(Vector3(0.1, 0.1, 0.9)), MeshKit3D.xf(Vector3(0, 4.15, 0.45)), iron)
	kit.add(MeshKit3D.box(Vector3(0.42, 0.55, 0.42)), MeshKit3D.xf(Vector3(0, 3.85, 0.9)), Color(1.0, 0.86, 0.55, 1.0))
	kit.add(MeshKit3D.prism(Vector3(0.6, 0.3, 0.6)), MeshKit3D.xf(Vector3(0, 4.25, 0.9)), iron)
	var mesh := kit.commit()
	var s := 150.0
	var side := 1.0
	while s < track.length - 80.0:
		var edge := track.half_width(s) + track.verge + 0.8
		var p := track.position_at(s, side * edge)
		if world.clear_of_road(p, 0.3):
			var face := -track.sample(s).right * side
			world.cell(props, p).add_baked(mesh, Transform3D(Basis(Vector3.UP.cross(face), Vector3.UP, face), p))
			_bulbs.append(Transform3D(Basis().scaled(Vector3.ONE * 2.2), p + face * 0.9 + Vector3.UP * 3.85))
			_bulb_colors.append(Color(1.0, 0.75, 0.4, 0.5))
		s += 28.0
		side = -side


## Soft additive halos round the bulbs and lanterns (one MultiMesh).
func _halos(parent: Node3D) -> void:
	if _bulbs.is_empty():
		return
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.use_colors = true
	mmesh.mesh = KartWorld.halo_quad()
	mmesh.instance_count = _bulbs.size()
	for i in _bulbs.size():
		mmesh.set_instance_transform(i, _bulbs[i])
		mmesh.set_instance_color(i, _bulb_colors[i])
	var node := MultiMeshInstance3D.new()
	node.name = "BulbHalos"
	node.multimesh = mmesh
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.visibility_range_end = 260.0
	parent.add_child(node)
