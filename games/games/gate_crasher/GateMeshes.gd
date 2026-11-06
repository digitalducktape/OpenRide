class_name GateMeshes
extends RefCounted
## Every mesh of Gate Crasher's arena (#80), built in code from primitive shapes with KartMeshKit:
## vertex colours with painted AO, each object one draw call on the shared scenery shader. UV.x is
## free and UV.y is self-lit share; COLOR.a is 1 - sway (the mane, the bunting, the flags).
## ART_BIBLE.md has the palette and the layout. The course is `GateCourse`.

const ACCENT := Color("2fc4b2")  ## rosette teal
const INK := Color("0c2a2e")
const WHITE := Color("f4f1e8")
const SAND := Color("d9bd8c")
const POST := Color("e8e4dc")
const RAIL_SETS := [[Color("d8382e"), WHITE], [Color("2f5fc8"), WHITE], [Color("f2b71c"), Color("24303a")],
	[Color("2fa86a"), WHITE], [Color("e8702a"), WHITE], [Color("7a4ac8"), WHITE], [Color("d8382e"), Color("f2b71c")],
	[Color("2fc4b2"), Color("24303a")]]
const FLOWERS := [Color("e8405a"), Color("f2c230"), Color("f4f1e8"), Color("c84ad0"), Color("f28a30")]
const HEDGE := Color("3f7a3a")
const LEAF := [Color("4f8f3e"), Color("3f7f44"), Color("6a9c3a")]
const TRUNK := Color("5a4630")
const STAND_WOOD := Color("7a6650")
const ROOF := Color("c8382e")
const BUNTING := [Color("e04a3a"), Color("f2c230"), Color("3a7fd9"), Color("2fc4b2"), Color("f4f1e8")]

const COAT := Color("7a4526")  ## the horse: a bay
const COAT_DARK := Color("54301c")
const MANE := Color("1d1612")
const EAR_INSIDE := Color("3a2318")

const RAIL_WIDTH := 4.2  ## between the standards
const RAIL_HEIGHTS := [0.55, 0.9, 1.25]  ## the top one falls (`top_rail`)
const TRACK_HALF := 7.0  ## the worn track either side of the course
const RING_MARGIN := 9.0  ## the arena's fence, out from the course
const BEAT_STRIPES := 3


static func _kit() -> KartMeshKit:
	var kit := KartMeshKit.new()
	kit.flags = true
	kit.outline = 0.0
	kit.glow = 0.0
	return kit


static func _box(kit: KartMeshKit, size: Vector3, xf: Transform3D, color: Color) -> void:
	kit.add(KartMeshKit.box(size), xf, color)


## The arena's statics: the white ring fence, the fences' standards and flower boxes, the
## grandstand, the judges' box, hedges, trees and bunting. One mesh.
static func scenery(logic_fences: int, spacing: float, seed_value := 80) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _kit()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 1.0
	kit.ao_min = 0.65
	_ring(kit)
	for k in logic_fences:
		_fence_frame(kit, k, GateCourse.frame((k + 1) * spacing), rng)
	_stand(kit)
	_judges_box(kit)
	_hedges(kit, rng)
	_trees(kit, rng)
	_bunting(kit)
	return kit.commit()


## The ring: white posts and two rails, following the loop outside and inside.
static func _ring(kit: KartMeshKit) -> void:
	var s := 0.0
	while s < GateCourse.LENGTH:
		var f := GateCourse.frame(s)
		var f2 := GateCourse.frame(s + 4.0)
		for side: float in [-1.0, 1.0]:
			var off := f.basis.x * side * RING_MARGIN
			var off2 := f2.basis.x * side * RING_MARGIN
			var a := f.origin + off
			var b := f2.origin + off2
			_box(kit, Vector3(0.14, 1.15, 0.14), Transform3D(f.basis, a + Vector3.UP * 0.575), POST)
			for h: float in [0.6, 1.05]:
				var dir := b - a
				var basis := Basis.looking_at(dir.normalized(), Vector3.UP)
				_box(kit, Vector3(0.07, 0.11, dir.length()), Transform3D(basis, (a + b) / 2.0 + Vector3.UP * h), WHITE)
		s += 4.0


## A fence's fixed parts: two standards with painted bands, wings, and flower boxes under the rails.
static func _fence_frame(kit: KartMeshKit, k: int, f: Transform3D, rng: RandomNumberGenerator) -> void:
	var colours: Array = RAIL_SETS[k % RAIL_SETS.size()]
	for side: float in [-1.0, 1.0]:
		var x := side * (RAIL_WIDTH / 2.0 + 0.1)
		_box(kit, Vector3(0.2, 1.75, 0.2), f * KartMeshKit.xf(Vector3(x, 0.875, 0.0)), WHITE)
		_box(kit, Vector3(0.24, 0.3, 0.24), f * KartMeshKit.xf(Vector3(x, 1.6, 0.0)), colours[0])
		_box(kit, Vector3(0.7, 0.1, 1.0), f * KartMeshKit.xf(Vector3(x, 0.05, 0.0)), colours[0].darkened(0.2))
		# The wing: a slatted panel stepping down outward.
		for i in 4:
			var h := 1.5 - i * 0.28
			_box(kit, Vector3(0.3, h, 0.1), f * KartMeshKit.xf(Vector3(x + side * (0.3 + i * 0.3), h / 2.0, 0.0)),
				colours[i % 2])
	# The flower boxes along the foot of the fence, on the approach side.
	for i in 4:
		var x := -1.55 + i * 1.03
		_box(kit, Vector3(0.92, 0.26, 0.42), f * KartMeshKit.xf(Vector3(x, 0.13, 0.3)), Color("6b4a2c"))
		for j in 7:
			var fx := x + rng.randf_range(-0.4, 0.4)
			var fz := 0.3 + rng.randf_range(-0.14, 0.14)
			var bloom: Color = HEDGE if j % 2 == 0 else FLOWERS[rng.randi() % FLOWERS.size()]
			kit.add(KartMeshKit.sphere(0.13, 6, 3), f * KartMeshKit.xf(Vector3(fx, 0.32, fz)), bloom)


## A fence's lower rails, built at the fence's frame. Its own mesh so it draws with the top rail.
static func rails(k: int) -> ArrayMesh:
	var kit := _kit()
	for i in RAIL_HEIGHTS.size() - 1:
		_rail(kit, k, RAIL_HEIGHTS[i], Transform3D.IDENTITY)
	return kit.commit()


## A fence's top rail: its own node, for the knock.
static func top_rail(k: int) -> ArrayMesh:
	var kit := _kit()
	_rail(kit, k, 0.0, Transform3D.IDENTITY)
	return kit.commit()


## A pole in painted bands, across the course at height `y`.
static func _rail(kit: KartMeshKit, k: int, y: float, base: Transform3D) -> void:
	var colours: Array = RAIL_SETS[k % RAIL_SETS.size()]
	var bands := 6
	var band := RAIL_WIDTH / bands
	for i in bands:
		var x := -RAIL_WIDTH / 2.0 + band * (i + 0.5)
		kit.add(KartMeshKit.cylinder(0.075, 0.075, band, 8),
			base * KartMeshKit.xf(Vector3(x, y, 0.0), Vector3(0.0, 0.0, 90.0)), colours[i % 2])


## The take-off lines of every fence: one mesh, each piece tagged with its fence in UV.x and its
## beat in UV.y (0 the line, 1-3 the stripes leading to it; the marker shader lights them).
static func markers(fences: int, spacing: float, line_gap: float, stripe_m: float) -> ArrayMesh:
	var kit := _kit()
	for k in fences:
		kit.outline = float(k)
		var s := (k + 1) * spacing - line_gap
		kit.glow = 0.0
		var f := GateCourse.frame(s)
		_box(kit, Vector3(5.6, 0.02, 0.55), f * KartMeshKit.xf(Vector3(0.0, 0.04, 0.0)), WHITE)
		for side: float in [-1.0, 1.0]:
			_box(kit, Vector3(0.1, 1.5, 0.1), f * KartMeshKit.xf(Vector3(side * 3.0, 0.75, 0.0)), WHITE)
			kit.add(KartMeshKit.prism(Vector3(0.05, 0.42, 0.6)),
				f * KartMeshKit.xf(Vector3(side * 3.0, 1.32, -0.3), Vector3(90.0, 0.0, 0.0)), ACCENT)
		for b in BEAT_STRIPES:
			kit.glow = float(b + 1)
			var fs := GateCourse.frame(s - stripe_m * (b + 1))
			# A chevron pointing the way: two bars meeting on the course.
			for side: float in [-1.0, 1.0]:
				_box(kit, Vector3(2.6, 0.02, 0.4), fs * KartMeshKit.xf(Vector3(side * 1.2, 0.04, side * 0.0 + 0.4), Vector3(0.0, side * 18.0, 0.0)), WHITE)
	return kit.commit()


## The grandstand, outside the first straight (the rider's right), and its roof.
const STAND_X := GateCourse.RADIUS + RING_MARGIN + 5.0
const STAND_Z := Vector2(-55.0, 55.0)
const STAND_TIERS := 5
const TIER_DEPTH := 1.1
const TIER_RISE := 0.62


static func _stand(kit: KartMeshKit) -> void:
	var length := STAND_Z.y - STAND_Z.x
	var centre := (STAND_Z.x + STAND_Z.y) / 2.0
	for t in STAND_TIERS:
		var top := TIER_RISE * (t + 1)
		_box(kit, Vector3(TIER_DEPTH, top, length), KartMeshKit.xf(Vector3(STAND_X + TIER_DEPTH * (t + 0.5), top / 2.0, centre)),
			STAND_WOOD.lightened(0.05 * t))
	var back := STAND_X + TIER_DEPTH * STAND_TIERS + 0.2
	_box(kit, Vector3(0.3, 6.0, length), KartMeshKit.xf(Vector3(back, 3.0, centre)), STAND_WOOD.darkened(0.2))
	# The roof in striped canvas, on posts.
	var z := STAND_Z.x
	var i := 0
	while z < STAND_Z.y:
		_box(kit, Vector3(TIER_DEPTH * STAND_TIERS + 1.6, 0.12, 5.0),
			KartMeshKit.xf(Vector3(STAND_X + TIER_DEPTH * STAND_TIERS / 2.0, 6.15, z + 2.5), Vector3(0.0, 0.0, -6.0)),
			ROOF if i % 2 == 0 else WHITE)
		if i % 3 == 0:
			_box(kit, Vector3(0.16, 6.0, 0.16), KartMeshKit.xf(Vector3(STAND_X - 0.3, 3.0, z)), WHITE)
		z += 5.0
		i += 1


static func _judges_box(kit: KartMeshKit) -> void:
	var c := Vector3(-GateCourse.RADIUS - RING_MARGIN - 6.0, 0.0, 0.0)
	_box(kit, Vector3(4.0, 3.4, 7.0), KartMeshKit.xf(c + Vector3(0, 1.7, 0)), WHITE)
	_box(kit, Vector3(0.1, 1.0, 6.2), KartMeshKit.xf(c + Vector3(2.02, 2.4, 0)), Color("24303a"))
	_box(kit, Vector3(5.0, 0.2, 8.0), KartMeshKit.xf(c + Vector3(0, 3.5, 0)), ACCENT.darkened(0.25))
	_box(kit, Vector3(0.1, 2.2, 0.1), KartMeshKit.xf(c + Vector3(0, 4.7, 0)), WHITE)


## The hedge round the arena, and clipped hedge blocks with flowers in the infield.
static func _hedges(kit: KartMeshKit, rng: RandomNumberGenerator) -> void:
	var s := 0.0
	while s < GateCourse.LENGTH:
		var f := GateCourse.frame(s)
		var at := f.origin + f.basis.x * (RING_MARGIN + 2.4)
		if absf(at.z) > STAND_Z.y + 4.0 or at.x < GateCourse.RADIUS:
			_box(kit, Vector3(1.0, 1.5, 7.0), Transform3D(f.basis, at + Vector3.UP * 0.75), HEDGE.lightened(rng.randf_range(-0.05, 0.08)))
		s += 6.5
	var z := -50.0
	while z <= 50.0:
		_box(kit, Vector3(3.2, 0.7, 12.0), KartMeshKit.xf(Vector3(0.0, 0.35, z)), HEDGE)
		for j in 14:
			kit.add(KartMeshKit.sphere(0.2, 6, 3), KartMeshKit.xf(Vector3(rng.randf_range(-1.4, 1.4), 0.78, z + rng.randf_range(-5.6, 5.6))),
				FLOWERS[rng.randi() % FLOWERS.size()])
		z += 25.0


static func _trees(kit: KartMeshKit, rng: RandomNumberGenerator) -> void:
	kit.ao_y1 = 7.0
	kit.ao_min = 0.7
	for i in 46:
		var a := TAU * i / 46.0 + rng.randf_range(-0.04, 0.04)
		var r := Vector2(rng.randf_range(75.0, 110.0), rng.randf_range(130.0, 170.0))
		var p := Vector3(cos(a) * r.x, 0.0, sin(a) * r.y)
		var h := rng.randf_range(6.0, 10.0)
		_box(kit, Vector3(0.6, h * 0.6, 0.6), KartMeshKit.xf(p + Vector3.UP * h * 0.3), TRUNK)
		var leaf: Color = LEAF[rng.randi() % LEAF.size()]
		for j in 3:
			var o := Vector3(rng.randf_range(-1.8, 1.8), h * 0.75 + j * 1.2, rng.randf_range(-1.8, 1.8))
			kit.add(KartMeshKit.sphere(rng.randf_range(2.8, 4.2), 8, 4), KartMeshKit.xf(p + o), leaf.lightened(0.05 * j))
	kit.ao_y1 = 1.0
	kit.ao_min = 0.65


## Bunting along the stand's front.
static func _bunting(kit: KartMeshKit) -> void:
	var z := STAND_Z.x
	var i := 0
	while z < STAND_Z.y:
		var sag := 0.4 * sin(fmod(z - STAND_Z.x, 15.0) / 15.0 * PI)
		var c: Color = BUNTING[i % BUNTING.size()]
		c.a = 0.4
		kit.add(KartMeshKit.prism(Vector3(0.45, 0.6, 0.03)),
			KartMeshKit.xf(Vector3(STAND_X - 0.5, 5.2 - sag, z), Vector3(180.0, 90.0, 0.0)), c)
		z += 1.0
		i += 1


## The top of the neck, `t` from the withers to the poll, over its centre line at `y`.
static func _crest(y: float, t: float) -> float:
	return y + lerpf(0.72, 0.38, t) * 0.6


## What the rider sees of the horse, in the camera rig's space (metres; x right, -z ahead, y up
## from the rig's eye height). Broad and low on purpose: a wide crest of neck that fills the bottom
## of the frame, a flat poll with a browband, a thick black mane down the middle and two tall ears
## set far apart, so its silhouette is a wide trapezoid with two points and never a single tapering
## column (ART_BIBLE §10; the rider's silhouette rule).
static func horse() -> ArrayMesh:
	var kit := _kit()
	var neck_y := func(z: float) -> float: return lerpf(-1.32, -0.86, (z + 0.5) / -1.2)
	# The neck, flattened: wide at the withers and still wide at the poll.
	var points := PackedVector3Array()
	var radii := PackedFloat32Array()
	for i in 6:
		var z := lerpf(-0.5, -1.7, i / 5.0)
		points.append(Vector3(0.0, neck_y.call(z) / 0.6, z))
		radii.append(lerpf(0.72, 0.38, i / 5.0))
	kit.add(KartMeshKit.tube(points, radii, 14), Transform3D(Basis().scaled(Vector3(1.0, 0.6, 1.0)), Vector3.ZERO), COAT)
	# The poll: a flat-topped block across the head, wider than it is tall.
	kit.add(KartMeshKit.blob(Vector3(0.36, 0.13, 0.26), 0.45, 0.45), KartMeshKit.xf(Vector3(0, -0.74, -1.78)), COAT)
	# The face running away downhill, with a white star.
	kit.add(KartMeshKit.blob(Vector3(0.23, 0.12, 0.44), 0.7, 0.7), KartMeshKit.xf(Vector3(0, -0.86, -2.14), Vector3(-22.0, 0.0, 0.0)), COAT_DARK)
	kit.add(KartMeshKit.blob(Vector3(0.07, 0.03, 0.12), 1.0, 1.0), KartMeshKit.xf(Vector3(0, -0.745, -2.02), Vector3(-22.0, 0.0, 0.0)), WHITE)
	# The browband, in the game's teal.
	_box(kit, Vector3(0.66, 0.045, 0.05), KartMeshKit.xf(Vector3(0, -0.66, -1.93)), ACCENT)
	# The ears: two tall leaf shapes, wide apart and tilted out.
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 0.27, -0.5, -1.74)
		var tilt := Vector3(4.0, 0.0, -side * 13.0)
		kit.add(KartMeshKit.blob(Vector3(0.095, 0.24, 0.05), 1.3, 1.0), KartMeshKit.xf(at, tilt), COAT_DARK)
		kit.add(KartMeshKit.blob(Vector3(0.055, 0.18, 0.02), 1.3, 1.0), KartMeshKit.xf(at + Vector3(0, -0.01, 0.04), tilt), EAR_INSIDE)
	# The mane: locks draped over the right of the crest, a ragged band to one side. Never a
	# centred strip, and no forelock: a dark oval over a tapering stripe has the wrong silhouette.
	for i in 60:
		var t := i / 59.0
		var z := lerpf(-0.42, -1.5, t)
		var mane := MANE.lightened(0.1 * (i % 3))
		mane.a = 0.3
		var length := lerpf(0.2, 0.13, t) + 0.035 * ((i * 7) % 4)
		kit.add(KartMeshKit.blob(Vector3(length, 0.028, 0.034), 1.0, 1.0),
			KartMeshKit.xf(Vector3(length * 0.92, _crest(neck_y.call(z), t) + 0.012 - length * 0.1, z), Vector3(0, 10.0 * (i % 3 - 1), -10.0)), mane)
	return kit.commit()
