class_name KartTrackside
extends RefCounted
## Kart Race's track furniture (#43): item-row pylons, climb signs and corner chevrons, baked
## into the trackside props cells (KartWorld.cell) once per KartWorld.build. Pure builders: no
## nodes, no state.


## Item-row pylons, climb signs and corner chevrons, baked into the trackside props.
static func build(world: KartWorld, props: Dictionary) -> void:
	var track := world.track
	var pylon := _pylon_mesh()
	var sign := _climb_sign_mesh()
	for z in track.zones:
		if z.type == "items":
			var mid := track.wrap(float(z.s0) + track.delta(z.s0, z.s1) * 0.5)
			for side: float in [-1.0, 1.0]:
				var p := track.position_at(mid, side * (track.half_width(mid) + KartTrackModel.KERB_WIDTH + 1.2))
				world.cell(props, p).add_baked(pylon, Transform3D(Basis(Vector3.UP, track.yaw_at(mid)), p))
		elif z.type == "climb":
			var s := track.wrap(float(z.s0) - 12.0)
			for side: float in [-1.0, 1.0]:
				var p := track.position_at(s, side * (track.half_width(s) + track.verge - 0.6))
				# Facing the oncoming karts.
				world.cell(props, p).add_baked(sign, Transform3D(Basis(Vector3.UP, track.yaw_at(s)), p))
	_build_chevrons(world, props)


## Chevron boards on the barrier round the outside of tight corners, pointing the way.
static func _build_chevrons(world: KartWorld, props: Dictionary) -> void:
	var track := world.track
	var left := _chevron_mesh(1.0)
	var right := _chevron_mesh(-1.0)
	var s := 0.0
	while s < track.length:
		var k := track.curvature(s)
		if absf(k) > 1.0 / 32.0 and not world.in_stand(s):
			var side := signf(k)  # the outside (+ curvature turns left: the right edge)
			var p := track.position_at(s, side * (track.half_width(s) + track.verge - 0.05))
			# The board's front (+z) faces the road.
			var face := -track.sample(s).right * side
			var basis := Basis(Vector3.UP.cross(face), Vector3.UP, face)
			world.cell(props, p).add_baked(left if k > 0.0 else right, Transform3D(basis, p))
			s += 5.0
		else:
			s += 2.0


## A board facing +z (from the outside wall toward the road), its arrow pointing along -x for
## `dir` = 1 (the board's left as seen from the road).
static func _chevron_mesh(dir: float) -> ArrayMesh:
	var kit := MeshKit3D.new()
	var back := Color(0.08, 0.08, 0.1, 0.0)
	var yellow := Color(1.0, 0.8, 0.1, 0.35)
	kit.add(MeshKit3D.box(Vector3(1.9, 1.1, 0.08)), MeshKit3D.xf(Vector3(0, 1.75, 0)), back)
	kit.add(MeshKit3D.box(Vector3(0.1, 1.3, 0.1)), MeshKit3D.xf(Vector3(-0.6, 0.65, -0.05)), Color(0.5, 0.5, 0.52, 0.0))
	kit.add(MeshKit3D.box(Vector3(0.1, 1.3, 0.1)), MeshKit3D.xf(Vector3(0.6, 0.65, -0.05)), Color(0.5, 0.5, 0.52, 0.0))
	for k in 2:
		var x := (-0.35 + k * 0.6) * dir
		for half: float in [-1.0, 1.0]:
			# Each chevron: two slanted bars meeting at the point.
			kit.add(MeshKit3D.box(Vector3(0.5, 0.16, 0.04)),
				MeshKit3D.xf(Vector3(x + 0.12 * dir, 1.75 + half * 0.2, 0.05), Vector3(0, 0, half * 42.0 * dir)), yellow)
	return kit.commit()


## An item-row pylon: a striped post with a glowing orb.
static func _pylon_mesh() -> ArrayMesh:
	var kit := MeshKit3D.new()
	kit.add(MeshKit3D.cylinder(0.16, 0.22, 1.6, 8), MeshKit3D.xf(Vector3(0, 0.8, 0)), Color(0.96, 0.96, 0.98, 0.0))
	for k in 3:
		kit.add(MeshKit3D.cylinder(0.2, 0.21, 0.18, 8), MeshKit3D.xf(Vector3(0, 0.35 + k * 0.45, 0)), Color(0.55, 0.3, 0.95, 0.0))
	kit.add(MeshKit3D.sphere(0.32, 10, 5), MeshKit3D.xf(Vector3(0, 1.85, 0)), Color(0.75, 0.55, 1.0, 1.0))
	kit.add(MeshKit3D.cylinder(0.32, 0.36, 0.14, 8), MeshKit3D.xf(Vector3(0, 0.07, 0)), Color(0.2, 0.2, 0.24, 0.0))
	return kit.commit()


## The climb sign: a yellow board on two posts with a mountain and an up-arrow, facing the
## oncoming karts (+z).
static func _climb_sign_mesh() -> ArrayMesh:
	var kit := MeshKit3D.new()
	var post := Color(0.55, 0.55, 0.58, 0.0)
	var board := Color(1.0, 0.78, 0.1, 0.25)
	var ink := Color(0.1, 0.1, 0.12, 0.0)
	for x: float in [-0.75, 0.75]:
		kit.add(MeshKit3D.box(Vector3(0.12, 2.4, 0.12)), MeshKit3D.xf(Vector3(x, 1.2, -0.05)), post)
	kit.add(MeshKit3D.box(Vector3(2.2, 1.5, 0.08)), MeshKit3D.xf(Vector3(0, 2.4, 0)), board)
	kit.add(MeshKit3D.box(Vector3(2.3, 1.6, 0.06)), MeshKit3D.xf(Vector3(0, 2.4, -0.02)), ink)
	# The mountain: a slope up to the right.
	kit.quad(Vector3(-0.9, 1.85, 0.05), Vector3(0.9, 2.55, 0.05), Vector3(0.9, 1.85, 0.05), Vector3(-0.9, 1.85, 0.05), ink)
	# The arrow: a shaft and a head, pointing up.
	kit.add(MeshKit3D.box(Vector3(0.16, 0.6, 0.04)), MeshKit3D.xf(Vector3(-0.45, 2.5, 0.06)), ink)
	kit.quad(Vector3(-0.75, 2.75, 0.06), Vector3(-0.45, 3.05, 0.06), Vector3(-0.15, 2.75, 0.06), Vector3(-0.75, 2.75, 0.06), ink)
	return kit.commit()
