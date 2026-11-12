extends KartDress
## Frost Pass's dressing (#43): a snowy mountain pass. Deep snow and dark pines capped white,
## mountains with grey rock faces all round, an ice-blue frozen lake in the valley, log cabins
## with warm lit windows and smoking chimneys, snowmen by the road and lanterns on posts.

var _lakes: Array[Dictionary] = []
var _lakes_read := false


func base_height(x: float, z: float, _r_road: float) -> float:
	var g := road_level(x, z)
	var h := g + 1.5 * noise.get_noise_2d(x * 3.0, z * 3.0) + hills(x, z, 30.0, 120.0, 110.0)
	if not _lakes_read:
		_lakes_read = true
		_lakes = world.landmarks("lake")
		for lm in _lakes:
			var lp: Vector3 = lm.p
			lm.floor = road_level(lp.x, lp.z) - 3.4
	for lm in _lakes:
		var p: Vector3 = lm.p
		var d := Vector2(x - p.x, z - p.z).length()
		var r: float = lm.r
		h = lerpf(h, lm.floor, 1.0 - smoothstep(r * 0.7, r * 1.1, d))
	return h


func dress_hero(scenery: Node3D, _props: Dictionary) -> void:
	_ice(scenery)


func dress(scenery: Node3D, foliage: Dictionary, props: Dictionary, woods: Array) -> void:
	var trees := tree_meshes(Color(0.18, 0.4, 0.26), true)
	scatter(foliage, trees, 150, KartWorld.TREE_CLEARANCE, 70.0, Vector2(0.9, 1.6),
		func(r: RandomNumberGenerator) -> int: return 1 if r.randf() < 0.75 else (2 if r.randf() < 0.6 else 0))
	scatter_far(woods, trees, 150, -20.0, 260.0, Vector2(1.4, 2.4), func(_r: RandomNumberGenerator) -> int: return 3)
	var rocks := [_snowy_rock(4), _snowy_rock(5), _snowy_rock(6)]
	scatter(props, rocks, 60, 2.0, 40.0, Vector2(0.7, 2.2), func(r: RandomNumberGenerator) -> int: return r.randi() % 3, 1.5, true, 0.4)
	scatter(props, [_snowman()], 10, 2.5, 9.0, Vector2(0.9, 1.1), func(_r: RandomNumberGenerator) -> int: return 0, 2.0, true, 0.1)
	_cabins(props)
	_lanterns(props)
	_huts(props)


## Ice-fishing huts out on the big lake, each a bright colour under a snow roof, and a jetty on
## the start's tarn.
func _huts(props: Dictionary) -> void:
	var lm := world.landmark("huts")
	if not lm.is_empty():
		var colors := [Color(0.85, 0.2, 0.2, 0.0), Color(0.2, 0.45, 0.85, 0.0), Color(0.95, 0.75, 0.2, 0.0), Color(0.3, 0.65, 0.4, 0.0)]
		var p0: Vector3 = lm.p
		var ice_y := road_level(p0.x, p0.z) - 0.55
		for k in 5:
			var kit := MeshKit3D.new()
			kit.ao_y0 = 0.0
			kit.ao_y1 = 2.0
			kit.ao_min = 0.7
			kit.add(MeshKit3D.box(Vector3(2.2, 2.0, 2.6)), MeshKit3D.xf(Vector3(0, 1.0, 0)), colors[k % colors.size()])
			kit.add(MeshKit3D.prism(Vector3(2.8, 1.0, 3.0)), MeshKit3D.xf(Vector3(0, 2.5, 0)), Color(0.95, 0.97, 1.0, 0.1))
			kit.add(MeshKit3D.box(Vector3(0.7, 1.3, 0.06)), MeshKit3D.xf(Vector3(0, 0.65, 1.32)), Color(0.3, 0.2, 0.14, 0.0))
			kit.add(MeshKit3D.box(Vector3(0.5, 0.4, 0.06)), MeshKit3D.xf(Vector3(0.6, 1.35, 1.32)), Color(1.0, 0.8, 0.45, 1.0))
			var a := TAU * k / 5.0 + rng.randf_range(-0.3, 0.3)
			var r := rng.randf_range(12.0, 38.0)
			var at := Vector3(p0.x + cos(a) * r, ice_y, p0.z + sin(a) * r)
			world.cell(props, at).add_baked(kit.commit(), Transform3D(Basis(Vector3.UP, rng.randf() * TAU), at))
	# The tarn's jetty: planks on posts from the near shore out over the ice.
	for lake in world.landmarks("lake"):
		if not lake.get("hero", false):
			continue
		var c: Vector3 = lake.p
		var toward := Vector3(world.track.position_at(lake.s, 0.0) - c)
		toward.y = 0.0
		toward = toward.normalized()
		var r2: float = lake.r
		var kit := MeshKit3D.new()
		var wood := Color(0.5, 0.34, 0.22, 0.0)
		for k in 6:
			kit.add(MeshKit3D.box(Vector3(2.0, 0.15, 1.3)), MeshKit3D.xf(Vector3(0, 0.6, -k * 1.4)), wood if k % 2 == 0 else wood.darkened(0.1))
			kit.add(MeshKit3D.box(Vector3(0.2, 1.2, 0.2)), MeshKit3D.xf(Vector3(0.9, 0.1, -k * 1.4)), wood.darkened(0.3))
			kit.add(MeshKit3D.box(Vector3(0.2, 1.2, 0.2)), MeshKit3D.xf(Vector3(-0.9, 0.1, -k * 1.4)), wood.darkened(0.3))
		var at := c + toward * r2 * 0.95
		at.y = road_level(c.x, c.z) - 0.55
		world.cell(props, at).add_baked(kit.commit(), Transform3D(Basis.looking_at(-toward, Vector3.UP), at))


## A grey boulder with a cap of snow.
static func _snowy_rock(seed_value: int) -> ArrayMesh:
	return snow_cap(rock_mesh(Color(0.46, 0.48, 0.56), seed_value), 0.55)


## A snowman with a carrot nose, coal buttons and a red scarf, facing +z.
static func _snowman() -> ArrayMesh:
	var kit := MeshKit3D.new()
	var snow := Color(0.96, 0.97, 1.0, 0.1)
	kit.add(MeshKit3D.sphere(0.75, 10, 5), MeshKit3D.xf(Vector3(0, 0.6, 0)), snow)
	kit.add(MeshKit3D.sphere(0.55, 10, 5), MeshKit3D.xf(Vector3(0, 1.55, 0)), snow)
	kit.add(MeshKit3D.sphere(0.4, 10, 5), MeshKit3D.xf(Vector3(0, 2.25, 0)), snow)
	kit.add(MeshKit3D.cylinder(0.0, 0.07, 0.4, 6), MeshKit3D.xf(Vector3(0, 2.25, 0.5), Vector3(90, 0, 0)), Color(1.0, 0.5, 0.1, 0.0))
	for e: float in [-0.13, 0.13]:
		kit.add(MeshKit3D.sphere(0.05, 4, 2), MeshKit3D.xf(Vector3(e, 2.35, 0.36)), Color(0.05, 0.05, 0.06, 0.0))
	for y: float in [1.4, 1.65]:
		kit.add(MeshKit3D.sphere(0.06, 4, 2), MeshKit3D.xf(Vector3(0, y, 0.53)), Color(0.05, 0.05, 0.06, 0.0))
	kit.add(MeshKit3D.torus(0.38, 0.52, 10, 4), MeshKit3D.xf(Vector3(0, 1.95, 0)), Color(0.85, 0.15, 0.18, 0.0))
	kit.add(MeshKit3D.cylinder(0.28, 0.28, 0.4, 8), MeshKit3D.xf(Vector3(0, 2.75, 0)), Color(0.1, 0.1, 0.12, 0.0))
	kit.add(MeshKit3D.cylinder(0.42, 0.42, 0.05, 8), MeshKit3D.xf(Vector3(0, 2.57, 0)), Color(0.1, 0.1, 0.12, 0.0))
	return kit.commit()


## The frozen lakes: discs of ice in their basins. The one marked `hero` is the title shot's.
func _ice(parent: Node3D) -> void:
	var lakes := world.landmarks("lake")
	if lakes.is_empty():
		return
	world.water_mat.set_shader_parameter("ice", 1.0)
	KartLook.apply(world.water_mat, {"deep": Color(0.22, 0.56, 0.86), "shallow": Color(0.42, 0.76, 0.98),
		"reflect_color": Color(0.62, 0.82, 1.0), "snow": Color(0.92, 0.96, 1.0)})
	for lm in lakes:
		var disc := CylinderMesh.new()
		var r: float = lm.r * 1.15
		disc.top_radius = r
		disc.bottom_radius = r
		disc.height = 0.02
		disc.radial_segments = 40
		disc.rings = 1
		var node := MeshKit3D.mesh_node(disc, world.water_mat, "Ice")
		var p: Vector3 = lm.p
		node.position = Vector3(p.x, road_level(p.x, p.z) - 0.55, p.z)
		parent.add_child(node)
		if lm.get("hero", false) or hero.is_empty():
			hero = {"p": node.position + Vector3.UP * 0.5, "size": r * 1.4, "flat": true}


## Log cabins with snowy roofs, lit windows and chimneys, a little back from the road.
func _cabins(props: Dictionary) -> void:
	var track := world.track
	var meshes := [_cabin(false), _cabin(true)]
	var placed := 0
	var tries := 0
	while placed < 9 and tries < 300:
		tries += 1
		var s := rng.randf_range(0.0, track.length)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var spot = world.beyond(s, side, rng.randf_range(10.0, 24.0), 9.0)
		if spot == null or (side > 0.0 and world.in_stand(s)):
			continue
		var p: Vector3 = spot - Vector3.UP * 0.4
		var face := -track.sample(track.wrap(s)).right * side
		face = face.rotated(Vector3.UP, rng.randf_range(-0.4, 0.4))
		world.cell(props, p).add_baked(meshes[placed % 2], Transform3D(Basis(Vector3.UP.cross(face), Vector3.UP, face), p))
		placed += 1


## A log cabin facing +z; `big` adds a porch and a second window row.
static func _cabin(big: bool) -> ArrayMesh:
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 3.0
	kit.ao_min = 0.7
	var w := 7.0 if big else 5.5
	var d := 6.0
	var h := 3.2
	var log_color := Color(0.5, 0.32, 0.2, 0.0)
	kit.add(MeshKit3D.box(Vector3(w, h + 1.5, d)), MeshKit3D.xf(Vector3(0, (h - 1.5) * 0.5, -d * 0.5)), log_color)
	for k in 5:
		kit.add(MeshKit3D.box(Vector3(w + 0.1, 0.12, d + 0.1)), MeshKit3D.xf(Vector3(0, 0.4 + k * 0.62, -d * 0.5)), log_color.darkened(0.25))
	# Roof: dark eaves under a thick snow blanket.
	kit.add(MeshKit3D.prism(Vector3(w + 1.2, 2.6, d + 1.2)), MeshKit3D.xf(Vector3(0, h + 1.3, -d * 0.5)), Color(0.35, 0.22, 0.16, 0.0))
	kit.add(MeshKit3D.prism(Vector3(w + 1.4, 2.4, d + 1.4)), MeshKit3D.xf(Vector3(0, h + 1.55, -d * 0.5)), Color(0.96, 0.97, 1.0, 0.1))
	kit.add(MeshKit3D.box(Vector3(0.8, 2.2, 0.8)), MeshKit3D.xf(Vector3(w * 0.25, h + 2.6, -d * 0.6)), Color(0.45, 0.42, 0.42, 0.0))
	kit.add(MeshKit3D.box(Vector3(1.1, 2.0, 0.1)), MeshKit3D.xf(Vector3(0, 1.0, 0.03)), Color(0.32, 0.2, 0.12, 0.0))
	for x: float in [-w * 0.3, w * 0.3]:
		kit.add(MeshKit3D.box(Vector3(1.1, 0.9, 0.1)), MeshKit3D.xf(Vector3(x, 1.7, 0.03)), Color(1.0, 0.78, 0.4, 1.0))
		kit.add(MeshKit3D.box(Vector3(1.3, 0.14, 0.25)), MeshKit3D.xf(Vector3(x, 1.2, 0.08)), Color(0.96, 0.97, 1.0, 0.1))
	if big:
		kit.add(MeshKit3D.box(Vector3(w, 0.15, 2.0)), MeshKit3D.xf(Vector3(0, 0.1, 1.0)), log_color.darkened(0.1))
		for x: float in [-w * 0.45, w * 0.45]:
			kit.add(MeshKit3D.box(Vector3(0.2, 2.6, 0.2)), MeshKit3D.xf(Vector3(x, 1.3, 1.9)), log_color)
		kit.add(MeshKit3D.box(Vector3(w + 0.3, 0.5, 2.3)), MeshKit3D.xf(Vector3(0, 2.75, 1.0), Vector3(-12, 0, 0)), Color(0.96, 0.97, 1.0, 0.1))
	return kit.commit()


## Lanterns on wooden posts at the barrier, lighting the way round.
func _lanterns(props: Dictionary) -> void:
	var track := world.track
	var kit := MeshKit3D.new()
	kit.add(MeshKit3D.box(Vector3(0.16, 2.4, 0.16)), MeshKit3D.xf(Vector3(0, 1.2, 0)), Color(0.42, 0.28, 0.18, 0.0))
	kit.add(MeshKit3D.box(Vector3(0.36, 0.45, 0.36)), MeshKit3D.xf(Vector3(0, 2.55, 0)), Color(1.0, 0.8, 0.45, 1.0))
	kit.add(MeshKit3D.prism(Vector3(0.5, 0.25, 0.5)), MeshKit3D.xf(Vector3(0, 2.9, 0)), Color(0.96, 0.97, 1.0, 0.1))
	var mesh := kit.commit()
	var s := 30.0
	var side := 1.0
	while s < track.length - 60.0:
		var p := track.position_at(s, side * (track.half_width(s) + track.verge + 0.8))
		if world.clear_of_road(p, 0.3):
			world.cell(props, p).add_baked(mesh, Transform3D(Basis(), p))
		s += 36.0
		side = -side
