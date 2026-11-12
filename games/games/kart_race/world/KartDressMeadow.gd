extends KartDress
## Meadow Ring's dressing (#43): rolling green hills, trees that sway, wildflowers, white
## fences, tyre stacks on the corners, hay bales, a red barn and a windmill turning on a rise.


func dress_hero(scenery: Node3D, _props: Dictionary) -> void:
	_windmill(scenery)


func dress(scenery: Node3D, foliage: Dictionary, props: Dictionary, woods: Array) -> void:
	var trees := tree_meshes()
	scatter(foliage, trees, 150, KartWorld.TREE_CLEARANCE, 60.0, Vector2(0.8, 1.35),
		func(r: RandomNumberGenerator) -> int: return 2 if r.randf() < 0.22 else (1 if r.randf() < 0.35 else 0))
	scatter_far(woods, trees, 110, -10.0, 170.0, Vector2(1.3, 2.1),
		func(r: RandomNumberGenerator) -> int: return 3 if r.randf() < 0.7 else 0)
	_flowers(foliage)
	_tyres(props)
	_fences(props)
	_hay(props)
	_barn(props)
	_balloon(props)


## A hot-air balloon tethered high over the fields: striped gores, a wicker basket on ropes.
func _balloon(cells: Dictionary) -> void:
	var lm := world.landmark("balloon")
	if lm.is_empty():
		return
	var kit := MeshKit3D.new()
	var stripes := [Color(0.95, 0.25, 0.2, 0.0), Color(1.0, 0.82, 0.2, 0.0), Color(0.2, 0.55, 0.95, 0.0), Color(0.98, 0.97, 0.94, 0.0)]
	kit.paint = func(p: Vector3, _n: Vector3, _c: Color) -> Color:
		var gore := posmod(int(floor((atan2(p.z, p.x) + PI) / TAU * 12.0)), 12)
		var c: Color = stripes[gore % stripes.size()]
		var shade := lerpf(0.7, 1.05, clampf(p.y * 0.5 + 0.5, 0.0, 1.0))
		return Color(c.r * shade, c.g * shade, c.b * shade, 0.0)
	kit.add(MeshKit3D.sphere(1.0, 12, 7), MeshKit3D.xf(Vector3(0, 9.0, 0), Vector3.ZERO, Vector3(6.0, 7.0, 6.0)), Color.WHITE)
	kit.add(MeshKit3D.cylinder(3.4, 1.4, 3.0, 12), MeshKit3D.xf(Vector3(0, 2.2, 0)), Color.WHITE)
	kit.paint = Callable()
	for a in 4:
		var u := TAU * (a + 0.5) / 4.0
		var top := Vector3(cos(u) * 1.3, 0.7, sin(u) * 1.3)
		var foot := Vector3(cos(u) * 0.6, -2.4, sin(u) * 0.6)
		kit.add(MeshKit3D.box(Vector3(0.06, (top - foot).length(), 0.06)), Transform3D(along(top - foot), (top + foot) * 0.5), Color(0.3, 0.24, 0.18, 0.0))
	kit.add(MeshKit3D.box(Vector3(1.4, 1.0, 1.4)), MeshKit3D.xf(Vector3(0, -2.9, 0)), Color(0.62, 0.42, 0.22, 0.0))
	var at: Vector3 = lm.p + Vector3.UP * 26.0
	world.cell(cells, lm.p).add_baked(kit.commit(), Transform3D(Basis(Vector3.UP, 0.4), at))


## Clumps of wildflowers on the embankments.
func _flowers(cells: Dictionary) -> void:
	var kit := MeshKit3D.new()
	var colors := [Color(1.0, 0.9, 0.25), Color(1, 1, 1), Color(0.95, 0.45, 0.75), Color(0.7, 0.5, 1.0), Color(1.0, 0.55, 0.2)]
	kit.add(MeshKit3D.sphere(0.32, 5, 1, true), MeshKit3D.xf(Vector3.ZERO, Vector3.ZERO, Vector3(1.4, 0.6, 1.4)), Color(0.3, 0.55, 0.18, 0.4))
	for i in 6:
		var p := Vector3(rng.randf_range(-0.55, 0.55), rng.randf_range(0.18, 0.42), rng.randf_range(-0.55, 0.55))
		var c: Color = colors[rng.randi() % colors.size()]
		c.a = 1.0
		kit.add(MeshKit3D.sphere(0.085, 4, 1), MeshKit3D.xf(p), c)
	scatter(cells, [kit.commit()], 360, 1.0, 22.0, Vector2(0.8, 1.6), func(_r: RandomNumberGenerator) -> int: return 0, 0.8, false, 0.0)


## Tyre stacks in front of the barrier on the outside of the corners.
func _tyres(cells: Dictionary) -> void:
	var track := world.track
	var mesh := MeshKit3D.tyre_stack(3, [Color(0.15, 0.15, 0.16, 0.0), Color(1, 1, 1, 0.0), Color(0.15, 0.15, 0.16, 0.0)])
	var tints := [Color(0.95, 0.2, 0.16), Color(0.98, 0.98, 0.98), Color(0.2, 0.55, 1.0), Color(1.0, 0.8, 0.15)]
	var s := 0.0
	var n := 0
	while s < track.length:
		var k := track.curvature(s)
		if absf(k) > 0.011 and not world.in_stand(s):
			var side := signf(k)  # the outside
			var p := track.position_at(s, side * (track.half_width(s) + track.verge - 0.5))
			var tint: Color = tints[n % tints.size()]
			world.cell(cells, p).add_baked(mesh, Transform3D(Basis(Vector3.UP, track.yaw_at(s)), p),
				Color(lerpf(1.0, tint.r, 0.8), lerpf(1.0, tint.g, 0.8), lerpf(1.0, tint.b, 0.8)) if n % 2 == 0 else tint)
			n += 1
			s += 1.6
		else:
			s += 4.0


## White post-and-rail fences along the meadows.
func _fences(cells: Dictionary) -> void:
	var track := world.track
	var kit := MeshKit3D.new()
	var white := Color(0.97, 0.96, 0.92, 0.0)
	kit.ao_y0 = 0.0
	kit.ao_y1 = 1.1
	kit.ao_min = 0.7
	kit.add(MeshKit3D.box(Vector3(0.14, 1.6, 0.14)), MeshKit3D.xf(Vector3(0, 0.35, 0)), white)
	for y: float in [0.45, 0.9]:
		kit.add(MeshKit3D.box(Vector3(0.07, 0.11, 3.0)), MeshKit3D.xf(Vector3(0, y, -1.5)), white)
	var mesh := kit.commit()
	for side: float in [-1.0, 1.0]:
		var s := 0.0
		while s < track.length:
			var spot = world.beyond(s, side, 14.0, 6.0)
			var spot2 = world.beyond(s + 4.0, side, 14.0, 6.0)
			if spot != null and spot2 != null:
				var dir: Vector3 = spot2 - spot
				var flat := Vector3(dir.x, 0.0, dir.z)
				if flat.length() > 2.0 and flat.length() < 6.5:
					var basis := Basis.looking_at(flat.normalized(), Vector3.UP).scaled(Vector3(1, 1, flat.length() / 3.0))
					# Shear the rails to follow the slope.
					basis.z.y = -dir.y / 3.0
					world.cell(cells, spot).add_baked(mesh, Transform3D(basis, spot))
			s += 4.0


## Round hay bales in the fields, alone and in little stacks.
func _hay(cells: Dictionary) -> void:
	var kit := MeshKit3D.new()
	kit.add(MeshKit3D.cylinder(0.75, 0.75, 1.2, 10), MeshKit3D.xf(Vector3(0, 0.72, 0), Vector3(90, 0, 0)), Color(0.93, 0.76, 0.36, 0.0))
	kit.add(MeshKit3D.cylinder(0.5, 0.5, 1.22, 10), MeshKit3D.xf(Vector3(0, 0.72, 0), Vector3(90, 0, 0)), Color(0.8, 0.62, 0.26, 0.0))
	var bale := kit.commit()
	kit = MeshKit3D.new()
	for p: Vector3 in [Vector3(-0.8, 0.72, 0), Vector3(0.8, 0.72, 0), Vector3(0, 1.95, 0)]:
		kit.add(MeshKit3D.cylinder(0.75, 0.75, 1.2, 10), MeshKit3D.xf(p, Vector3(90, 0, 0)), Color(0.93, 0.76, 0.36, 0.0))
		kit.add(MeshKit3D.cylinder(0.5, 0.5, 1.22, 10), MeshKit3D.xf(p, Vector3(90, 0, 0)), Color(0.8, 0.62, 0.26, 0.0))
	var stack := kit.commit()
	scatter(cells, [bale, stack], 26, 10.0, 45.0, Vector2(0.9, 1.1),
		func(r: RandomNumberGenerator) -> int: return 1 if r.randf() < 0.3 else 0, 8.0, true, 0.1)


## A red barn with a white-trimmed roof and a silo, out in the infield.
func _barn(cells: Dictionary) -> void:
	var track := world.track
	var attempts: Array = [[420.0, 40.0], [380.0, -40.0], [820.0, 42.0], [300.0, 45.0]]
	var lm := world.landmark("barn")
	if not lm.is_empty():
		attempts.push_front([lm.s, lm.d])
		attempts.push_front([lm.s, lm.d * 1.4])
	for attempt: Array in attempts:
		var s: float = track.wrap(attempt[0])
		var p := track.position_at(s, attempt[1])
		if not world.clear_of_road(p, 14.0):
			continue
		p.y = world.ground_at(p.x, p.z) - 0.2
		var kit := MeshKit3D.new()
		kit.ao_y0 = 0.0
		kit.ao_y1 = 6.0
		kit.ao_min = 0.65
		var red := Color(0.72, 0.16, 0.12, 0.0)
		var white := Color(0.97, 0.95, 0.9, 0.0)
		kit.add(MeshKit3D.box(Vector3(9.0, 5.0, 12.0)), MeshKit3D.xf(Vector3(0, 2.5, 0)), red)
		kit.add(MeshKit3D.prism(Vector3(10.0, 3.6, 12.6)), MeshKit3D.xf(Vector3(0, 6.8, 0)), Color(0.32, 0.3, 0.32, 0.0))
		kit.add(MeshKit3D.box(Vector3(3.4, 3.6, 0.2)), MeshKit3D.xf(Vector3(0, 1.8, 6.05)), white)
		kit.add(MeshKit3D.box(Vector3(2.8, 3.1, 0.22)), MeshKit3D.xf(Vector3(0, 1.6, 6.06)), Color(0.55, 0.12, 0.1, 0.0))
		kit.add(MeshKit3D.box(Vector3(1.2, 1.0, 0.2)), MeshKit3D.xf(Vector3(0, 5.6, 6.1)), white)
		kit.add(MeshKit3D.cylinder(2.0, 2.0, 11.0, 10), MeshKit3D.xf(Vector3(7.2, 5.5, -2.0)), Color(0.82, 0.84, 0.86, 0.0))
		kit.add(MeshKit3D.sphere(2.0, 10, 4, true), MeshKit3D.xf(Vector3(7.2, 11.0, -2.0)), Color(0.36, 0.5, 0.62, 0.0))
		var face := track.position_at(s, 0.0) - p
		world.cell(cells, p).add_baked(kit.commit(), Transform3D(Basis(Vector3.UP, atan2(face.x, face.z)), p))
		return


## A windmill on a rise in the infield, its sails turning.
func _windmill(parent: Node3D) -> void:
	var track := world.track
	var spot := Vector3.ZERO
	var found := false
	var attempts: Array = [[70.0, -48.0], [40.0, -55.0], [110.0, -50.0], [70.0, 48.0]]
	var lm := world.landmark("windmill")
	if not lm.is_empty():
		attempts.push_front([lm.s, lm.d])
	for attempt: Array in attempts:
		var s: float = track.wrap(attempt[0])
		var p := track.position_at(s, attempt[1])
		if world.clear_of_road(p, 18.0):
			spot = p
			spot.y = world.ground_at(p.x, p.z) - 0.3
			found = true
			break
	if not found:
		return
	hero = {"p": spot + Vector3.UP * 11.0, "size": 18.0}
	var mill := Node3D.new()
	mill.name = "Windmill"
	var look_at := track.position_at(track.wrap(-20.0), 0.0)
	look_at.y = spot.y
	mill.transform = Transform3D(Basis.looking_at((look_at - spot).normalized(), Vector3.UP), spot)
	parent.add_child(mill)
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 10.0
	kit.ao_min = 0.65
	kit.add(MeshKit3D.cylinder(2.3, 3.6, 13.0, 8), MeshKit3D.xf(Vector3(0, 6.5, 0)), Color(0.96, 0.93, 0.86, 0.0))
	kit.add(MeshKit3D.cylinder(0.0, 2.8, 3.4, 8), MeshKit3D.xf(Vector3(0, 14.6, 0)), Color(0.55, 0.25, 0.18, 0.0))
	kit.add(MeshKit3D.box(Vector3(1.2, 2.2, 0.3)), MeshKit3D.xf(Vector3(0, 1.1, -3.4)), Color(0.4, 0.26, 0.16, 0.0))
	for y: float in [5.5, 9.5]:
		kit.add(MeshKit3D.box(Vector3(0.9, 0.9, 0.2)), MeshKit3D.xf(Vector3(0, y, -3.0 + (y - 5.5) * 0.14)), Color(0.25, 0.35, 0.5, 0.0))
	kit.add(MeshKit3D.cylinder(0.35, 0.35, 1.2, 8), MeshKit3D.xf(Vector3(0, 13.2, -2.6), Vector3(90, 0, 0)), Color(0.3, 0.2, 0.15, 0.0))
	mill.add_child(MeshKit3D.mesh_node(kit.commit(), world.scenery_mat, "Tower"))
	var blades := MeshKit3D.new()
	for i in 4:
		var rot := Basis(Vector3.FORWARD, i * PI * 0.5)
		blades.add(MeshKit3D.box(Vector3(0.3, 7.5, 0.2)), Transform3D(rot, rot * Vector3(0, 4.0, 0)), Color(0.45, 0.32, 0.22, 0.0))
		blades.add(MeshKit3D.box(Vector3(1.5, 6.0, 0.08)), Transform3D(rot, rot * Vector3(0.85, 4.6, 0.05)), Color(0.97, 0.95, 0.9, 0.0))
	var sails := Node3D.new()
	sails.name = "Sails"
	sails.position = Vector3(0, 13.2, -3.3)
	mill.add_child(sails)
	sails.add_child(MeshKit3D.mesh_node(blades.commit(), world.scenery_mat, "SailMesh"))
	world.spin(sails, Vector3.FORWARD, 0.7)
