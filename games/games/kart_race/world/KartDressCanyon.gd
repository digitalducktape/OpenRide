extends KartDress
## Canyon Dash's dressing (#43): red layered rock. Terraced canyon walls rise beside the road
## where the land closes in, mesas stand on the horizon, a pale dry riverbed winds through the
## infield, and a natural rock arch spans the road at the narrows. Saguaro cacti, boulders, dry
## scrub and a farm windpump turning in the hot wind.

var _river := {}
var _mask := FastNoiseLite.new()


func _init() -> void:
	super()
	_mask.seed = 77
	_mask.frequency = 0.004


func base_height(x: float, z: float, r_road: float) -> float:
	var g := road_level(x, z)
	var n := noise.get_noise_2d(x, z) * 0.5 + 0.5
	var dunes := 0.7 * noise.get_noise_2d(x * 5.0, z * 5.0)
	# Canyon walls where the mask says so, rising 16-34 m beyond the barrier.
	var wall := smoothstep(14.0, 34.0, r_road) * smoothstep(0.0, 0.25, _mask.get_noise_2d(x, z)) * (12.0 + 24.0 * n)
	# Mesas and the far rim.
	var rc := Vector2(x - world.centre.x, z - world.centre.z).length()
	var far := smoothstep(world.reach + 60.0, world.reach + 200.0, rc) * (24.0 + 46.0 * n) * smoothstep(-0.25, 0.15, _mask.get_noise_2d(x * 1.7, z * 1.7))
	far += smoothstep(world.reach + 350.0, world.reach + 700.0, rc) * 50.0
	var h := terrace(maxf(wall, far), 5.0)
	return g + dunes + h - 1.2 * _in_river(x, z)


## The riverbed's pale sand and pebbles.
func ground_tint(x: float, z: float, _h: float) -> Color:
	var k := _in_river(x, z)
	return Color(1.0, 1.0, 1.0).lerp(Color(1.12, 1.12, 1.18), k)


## 0..1: how far into the dry riverbed (x, z) is.
func _in_river(x: float, z: float) -> float:
	if _river.is_empty():
		_river = world.landmark("river")
		if _river.is_empty():
			_river = {"none": true}
	if _river.has("none"):
		return 0.0
	var p: Vector3 = _river.p
	var rel := Vector3(x - p.x, 0.0, z - p.z)
	var u := rel.dot(_river.dir as Vector3)
	var v := rel.dot(_river.out as Vector3)
	if absf(u) > 260.0:
		return 0.0
	var centre := 16.0 * sin(u / 38.0) + 8.0 * sin(u / 17.0)
	return smoothstep(10.0, 5.0, absf(v - centre)) * smoothstep(260.0, 200.0, absf(u))


func dress_hero(_scenery: Node3D, props: Dictionary) -> void:
	_arch(props)


func dress(scenery: Node3D, foliage: Dictionary, props: Dictionary, woods: Array) -> void:
	var rocks := [rock_mesh(Color(0.72, 0.34, 0.2), 1), rock_mesh(Color(0.8, 0.46, 0.28), 2, 0.55),
		rock_mesh(Color(0.6, 0.28, 0.18), 3, 0.85)]
	var cacti := [_cactus(2), _cactus(1), _cactus(0)]
	var scrub := _scrub()
	scatter(props, cacti, 70, 3.0, 45.0, Vector2(0.8, 1.3), func(r: RandomNumberGenerator) -> int: return r.randi() % 3, 3.0)
	scatter(props, rocks, 90, 1.5, 40.0, Vector2(0.6, 2.4), func(r: RandomNumberGenerator) -> int: return r.randi() % 3, 1.5, true, 0.4)
	scatter(foliage, [scrub], 160, 1.0, 30.0, Vector2(0.7, 1.4), func(_r: RandomNumberGenerator) -> int: return 0, 1.0, false, 0.1)
	scatter_far(woods, [cacti[0], rocks[0], rocks[2]], 120, 10.0, 220.0, Vector2(1.2, 3.0),
		func(r: RandomNumberGenerator) -> int: return 0 if r.randf() < 0.4 else 1 + r.randi() % 2)
	_spire(props)
	_windpump(scenery)
	_tyres(props)


## A saguaro: a ribbed trunk and up to two arms, `arms` of them.
static func _cactus(arms: int) -> ArrayMesh:
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 4.0
	kit.ao_min = 0.6
	var green := Color(0.32, 0.56, 0.3, 0.0)
	var h := 4.2 if arms > 0 else 2.6
	kit.add(MeshKit3D.cylinder(0.34, 0.42, h, 8), MeshKit3D.xf(Vector3(0, h * 0.5, 0)), green)
	kit.add(MeshKit3D.sphere(0.34, 8, 3, true), MeshKit3D.xf(Vector3(0, h, 0)), green.lightened(0.1))
	for a in arms:
		var side := 1.0 if a == 0 else -1.0
		var y := 1.6 + a * 0.6
		kit.add(MeshKit3D.cylinder(0.22, 0.22, 0.9, 6), MeshKit3D.xf(Vector3(side * 0.6, y, 0), Vector3(0, 0, 90)), green)
		kit.add(MeshKit3D.cylinder(0.22, 0.24, 1.4, 6), MeshKit3D.xf(Vector3(side * 1.0, y + 0.65, 0)), green)
		kit.add(MeshKit3D.sphere(0.22, 6, 2, true), MeshKit3D.xf(Vector3(side * 1.0, y + 1.35, 0)), green.lightened(0.1))
	# A pink bloom on top.
	kit.add(MeshKit3D.sphere(0.12, 5, 2), MeshKit3D.xf(Vector3(0.1, h + 0.3, 0)), Color(1.0, 0.45, 0.6, 0.0))
	return kit.commit()


## Dry scrub: olive and straw clumps (they sway a little).
static func _scrub() -> ArrayMesh:
	var kit := MeshKit3D.new()
	kit.add(MeshKit3D.sphere(0.55, 6, 3), MeshKit3D.xf(Vector3(0, 0.35, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), Color(0.55, 0.55, 0.28, 0.5))
	kit.add(MeshKit3D.sphere(0.4, 6, 3), MeshKit3D.xf(Vector3(0.5, 0.3, 0.2), Vector3.ZERO, Vector3(1.0, 0.7, 1.0)), Color(0.72, 0.62, 0.36, 0.5))
	return kit.commit()


## The rock arches over the road at the landmarks: half rings of layered red rock. The one
## marked `hero` is the title shot's.
func _arch(props: Dictionary) -> void:
	var track := world.track
	for lm in world.landmarks("arch"):
		var span := track.half_width(lm.s) + track.verge + 4.0
		var kit := MeshKit3D.new()
		kit.ao_y0 = 0.0
		kit.ao_y1 = span + 4.0
		kit.ao_min = 0.55
		var reds := [Color(0.78, 0.36, 0.2, 0.0), Color(0.66, 0.28, 0.16, 0.0), Color(0.9, 0.55, 0.34, 0.0)]
		# Built from chunky segments round the half ring, each band its own shade (strata).
		var segs := 14
		for i in segs:
			var a := PI * (i + 0.5) / segs
			var p := Vector3(cos(a) * (span + 2.2), sin(a) * (span + 2.2) - 2.0, 0.0)
			var c: Color = reds[i % 3]
			kit.add(MeshKit3D.box(Vector3(5.2, PI * (span + 2.2) / segs + 0.6, 5.0)),
				Transform3D(Basis(Vector3.BACK, a), p), c)
		# Feet: rock piles where the arch meets the ground.
		for side: float in [-1.0, 1.0]:
			kit.add(rock_mesh(Color(0.7, 0.32, 0.19), 9), MeshKit3D.xf(Vector3(side * (span + 2.5), -1.0, 0), Vector3.ZERO, Vector3(4.5, 6.0, 4.5)), Color(0.7, 0.32, 0.19, 0.0))
		var at := track.position_at(lm.s, 0.0)
		world.cell(props, at).add_baked(kit.commit(), Transform3D(Basis(Vector3.UP, track.yaw_at(lm.s)), at))
		if lm.get("hero", false) or hero.is_empty():
			hero = {"p": at + Vector3.UP * (span * 0.75), "size": span * 2.0 + 6.0, "lift": 1.0}


## A lone sandstone spire: stacked, tapering strata with a balanced cap rock.
func _spire(props: Dictionary) -> void:
	var lm := world.landmark("spire")
	if lm.is_empty() or not world.clear_of_road(lm.p, 6.0):
		return
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 20.0
	kit.ao_min = 0.6
	var reds := [Color(0.8, 0.38, 0.22, 0.0), Color(0.68, 0.3, 0.18, 0.0), Color(0.92, 0.58, 0.36, 0.0)]
	var y := -2.0
	var r := 6.5
	for k in 7:
		var h := rng.randf_range(2.6, 4.2)
		kit.add(MeshKit3D.cylinder(r * 0.86, r, h, 7), MeshKit3D.xf(Vector3(rng.randf_range(-0.4, 0.4), y + h * 0.5, rng.randf_range(-0.4, 0.4)), Vector3(0, k * 23.0, 0)), reds[k % 3])
		y += h
		r *= 0.8 if k < 4 else 0.9
	kit.add(rock_mesh(Color(0.86, 0.5, 0.3), 12), MeshKit3D.xf(Vector3(0.0, y - 0.6, 0.0), Vector3.ZERO, Vector3(3.6, 2.4, 3.2)), Color(0.86, 0.5, 0.3, 0.0))
	var at: Vector3 = lm.p
	world.cell(props, at).add_baked(kit.commit(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at))


## A farm windpump in the infield, its many-bladed wheel turning.
func _windpump(parent: Node3D) -> void:
	var track := world.track
	for attempt: Array in [[60.0, 40.0], [120.0, 38.0], [60.0, -40.0]]:
		var s: float = track.wrap(attempt[0])
		var p := track.position_at(s, attempt[1])
		if not world.clear_of_road(p, 16.0):
			continue
		p.y = world.ground_at(p.x, p.z) - 0.2
		var pump := Node3D.new()
		pump.name = "Windpump"
		var face := track.position_at(track.wrap(-30.0), 0.0) - p
		pump.transform = Transform3D(Basis(Vector3.UP, atan2(-face.x, -face.z)), p)
		parent.add_child(pump)
		var kit := MeshKit3D.new()
		var steel := Color(0.62, 0.62, 0.66, 0.0)
		for corner: Vector2 in [Vector2(-1.4, -1.4), Vector2(1.4, -1.4), Vector2(-1.4, 1.4), Vector2(1.4, 1.4)]:
			var foot := Vector3(corner.x, 0.0, corner.y)
			var top := Vector3(corner.x * 0.2, 11.0, corner.y * 0.2)
			var mid := (foot + top) * 0.5
			var len := foot.distance_to(top)
			kit.add(MeshKit3D.box(Vector3(0.14, len, 0.14)), Transform3D(along(top - foot), mid), steel)
		for y: float in [3.0, 6.0, 9.0]:
			var w := lerpf(2.8, 0.6, y / 11.0)
			kit.add(MeshKit3D.box(Vector3(w, 0.1, 0.1)), MeshKit3D.xf(Vector3(0, y, w * 0.5)), steel)
			kit.add(MeshKit3D.box(Vector3(w, 0.1, 0.1)), MeshKit3D.xf(Vector3(0, y, -w * 0.5)), steel)
		kit.add(MeshKit3D.box(Vector3(0.5, 0.5, 2.6)), MeshKit3D.xf(Vector3(0, 11.3, 0.6)), Color(0.85, 0.2, 0.15, 0.0))
		kit.add(MeshKit3D.box(Vector3(0.06, 1.6, 2.0)), MeshKit3D.xf(Vector3(0, 11.6, 2.4)), Color(0.95, 0.95, 0.92, 0.0))
		kit.add(MeshKit3D.cylinder(1.6, 1.6, 1.4, 10), MeshKit3D.xf(Vector3(3.0, 1.0, 0)), Color(0.55, 0.58, 0.62, 0.0))
		pump.add_child(MeshKit3D.mesh_node(kit.commit(), world.scenery_mat, "Tower"))
		var wheel := MeshKit3D.new()
		for i in 14:
			var rot := Basis(Vector3.FORWARD, TAU * i / 14.0)
			wheel.add(MeshKit3D.box(Vector3(0.5, 1.6, 0.04)), Transform3D(rot * Basis(Vector3.UP, 0.4), rot * Vector3(0, 1.4, 0)), Color(0.92, 0.92, 0.9, 0.0))
		wheel.add(MeshKit3D.torus(2.1, 2.25, 16, 4), MeshKit3D.xf(Vector3.ZERO, Vector3(90, 0, 0)), Color(0.85, 0.2, 0.15, 0.0))
		var hub := Node3D.new()
		hub.name = "Wheel"
		hub.position = Vector3(0, 11.3, -0.9)
		pump.add_child(hub)
		hub.add_child(MeshKit3D.mesh_node(wheel.commit(), world.scenery_mat, "WheelMesh"))
		world.spin(hub, Vector3.FORWARD, 1.6)
		return


## Tyre walls in the theme's colours on the outside of the corners.
func _tyres(cells: Dictionary) -> void:
	var track := world.track
	var mesh := MeshKit3D.tyre_stack(3, [Color(0.15, 0.15, 0.16, 0.0), Color(1, 1, 1, 0.0), Color(0.15, 0.15, 0.16, 0.0)])
	var tints := [Color(0.95, 0.45, 0.12), Color(0.98, 0.98, 0.98), Color(0.1, 0.62, 0.66)]
	var s := 0.0
	var n := 0
	while s < track.length:
		var k := track.curvature(s)
		if absf(k) > 0.011 and not world.in_stand(s):
			var side := signf(k)  # the outside
			var p := track.position_at(s, side * (track.half_width(s) + track.verge - 0.5))
			world.cell(cells, p).add_baked(mesh, Transform3D(Basis(Vector3.UP, track.yaw_at(s)), p), tints[n % tints.size()])
			n += 1
			s += 1.6
		else:
			s += 4.0
