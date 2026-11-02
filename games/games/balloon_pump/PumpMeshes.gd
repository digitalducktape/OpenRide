class_name PumpMeshes
extends RefCounted
## Balloon Pump's procedural meshes (ART_BIBLE.md). Everything is built from primitive shapes
## merged into vertex-coloured meshes with `KartMeshKit` (read only: Kart owns it), so the whole
## fairground is one draw call, the brass one, the wheel one and the plunger one. Colours are the
## bible's palette (sRGB), turned linear for the vertex colours (`lin`): the shaders light and
## grade in linear space like the engine's own materials.
##
## Vertex data the shaders read (KartMeshKit flags):
##   scenery.gdshader: COLOR.a = 1 - sway weight (bunting), UV.x = ground grain, UV.y = self-lit.
##   balloon.gdshader / bunch.gdshader: COLOR.r < 1 on the knot and neck; bunch: UV.x along the
##     string (0 on the balloon).

# The palette (ART_BIBLE §4), sRGB.
const LAWN := Color("6cb24f")
const LAWN_DARK := Color("5da845")
const PINK := Color("ff5fa2")
const CREAM := Color("fff4de")
const MINT := Color("7fe0c4")
const BRASS := Color("e2b04a")
const BRASS_DARK := Color("8c6420")
const RED := Color("d83a34")
const PLUM := Color("2b0f2a")
const WOOD := Color("b07a4a")
const HOSE := Color("c8352f")
const TREE_GREENS := [Color("4fa34a"), Color("3d8f45"), Color("67b84e")]
const HILL_GREENS := [Color("8cc77a"), Color("76b46c"), Color("9dcf87")]
const TENT_STRIPES := [[Color("ff5fa2"), Color("fff4de")], [Color("6e7cff"), Color("fff4de")],
	[Color("3fd0a8"), Color("fff4de")], [Color("ffc530"), Color("fff4de")], [Color("ff8a4c"), Color("fff4de")]]
const BUNTING := [Color("ff5fa2"), Color("ffc530"), Color("3fd0a8"), Color("6e7cff"), Color("fff4de")]

## Each balloon kind's colour (ART_BIBLE §4) and full radius in metres.
const BALLOON_COLORS := {"small": Color("3fd0a8"), "medium": Color("ff4f96"), "large": Color("8a7dff"),
	"gold": Color("ffc530")}
const BALLOON_RADIUS := {"small": 0.3, "medium": 0.36, "large": 0.43, "gold": 0.36}

## Layout (metres; the camera is at the origin, 1.5 m up, looking down -z).
const PUMP_POS := Vector3(-0.95, 0.0, -2.5)
const PUMP_RADIUS := 0.3
const PUMP_TOP := 1.32  ## the body's top (the dome sits on it)
const GAUGE_Y := 0.9
const PLUNGER_HANDLE := 0.55  ## the T handle's height above the plunger's foot
const GAUGE_RADIUS := 0.17
const NOZZLE_POS := Vector3(0.35, 1.05, -3.1)  ## where the balloon's knot sits
const RACK_POS := Vector3(1.55, 1.12, -4.75)  ## where the next balloon's knot sits
const TETHER := Vector3(0.45, 1.0, -4.45)  ## where the bunch's strings meet
const COUNTER_Z := -5.0
const BACK_Z := -5.8
const WHEEL_POS := Vector3(-16.0, 11.0, -38.0)
const WHEEL_RADIUS := 9.0
## The balloon profile's knot is at y = 0 and its widest point near y = 1 (units of the radius).
const BUNCH_KNOT := -1.0  ## the bunch mesh is shifted so its centre is at 0 (bunch.gdshader)

const VIGNETTE := 0.22
const VIGNETTE_TINT := Color(1.0, 0.9, 1.0)
const VIEW_COLS := 16
const VIEW_ROWS := 9


static func lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, c.a)


static func _kit(grain := 0.0, glow := 0.0) -> KartMeshKit:
	var kit := KartMeshKit.new()
	kit.flags = true
	kit.outline = grain
	kit.glow = glow
	return kit


static func _k(kit: KartMeshKit, mesh: Mesh, xf: Transform3D, color: Color) -> void:
	kit.add(mesh, xf, lin(color))


static func _xf(pos: Vector3, rot := Vector3.ZERO, scale := Vector3.ONE) -> Transform3D:
	return KartMeshKit.xf(pos, rot, scale)


# --- Balloons ---

## The balloon's profile (radius, height) from the knot up, in units of its radius, and each
## point's shade (the knot and neck darker).
static func _profile() -> Array:
	var pts := PackedVector2Array([Vector2(0.0, 0.0), Vector2(0.08, 0.0), Vector2(0.08, 0.07),
		Vector2(0.045, 0.11), Vector2(0.11, 0.2), Vector2(0.36, 0.36), Vector2(0.68, 0.6),
		Vector2(0.92, 0.9), Vector2(1.0, 1.2), Vector2(0.95, 1.5), Vector2(0.78, 1.78),
		Vector2(0.48, 1.98), Vector2(0.18, 2.07), Vector2(0.0, 2.09)])
	var shades := PackedColorArray()
	for i in pts.size():
		var s := 0.55 if i < 4 else (0.8 if i == 4 else 1.0)
		shades.append(Color(s, s, s))
	return [pts, shades]


## One balloon, knot at the origin, growing up +y, radius 1 (scale it to the kind's radius).
static func balloon() -> ArrayMesh:
	var prof := _profile()
	var kit := KartMeshKit.new()
	kit.add(KartMeshKit.lathe(prof[0], 18, prof[1]), Transform3D.IDENTITY, Color.WHITE)
	return kit.commit()


## A balloon of the bunch on its string: the balloon's centre at the origin, the knot at
## BUNCH_KNOT, and a string from the knot down (UV.x 0-1 along it; bunch.gdshader sets its length).
static func bunch_balloon() -> ArrayMesh:
	var prof := _profile()
	var lathe := KartMeshKit.lathe(prof[0], 12, prof[1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var arrays := lathe.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for i in indices:
		st.set_color(colors[i])
		st.set_normal(normals[i])
		st.set_uv(Vector2.ZERO)
		st.add_vertex(verts[i] + Vector3(0.0, BUNCH_KNOT, 0.0))
	# The string: a thin square tube, its top at the knot (UV.x just over 0) and its foot at UV.x 1.
	var w := 0.025
	var corners := [Vector2(-w, -w), Vector2(w, -w), Vector2(w, w), Vector2(-w, w)]
	for k in 4:
		var a: Vector2 = corners[k]
		var b: Vector2 = corners[(k + 1) % 4]
		var n := Vector3(a.x + b.x, 0.0, a.y + b.y).normalized()
		var quad := [[a, 0.001], [b, 0.001], [b, 1.0], [a, 0.001], [b, 1.0], [a, 1.0]]
		var ordered := [quad[0], quad[2], quad[1], quad[3], quad[5], quad[4]]
		for q in ordered:
			var c: Vector2 = q[0]
			st.set_color(Color.WHITE)
			st.set_normal(n)
			st.set_uv(Vector2(q[1], 0.0))
			st.add_vertex(Vector3(c.x, BUNCH_KNOT - float(q[1]), c.y))
	return st.commit()


# --- The pump, the nozzle stand, the hose and the tether (one mesh, the brass material) ---

static func brass() -> ArrayMesh:
	var kit := _kit()
	var p := PUMP_POS
	# The plinth: red-painted, with a brass trim.
	_k(kit, KartMeshKit.box(Vector3(0.86, 0.3, 0.86)), _xf(p + Vector3(0, 0.15, 0)), RED)
	_k(kit, KartMeshKit.box(Vector3(0.9, 0.04, 0.9)), _xf(p + Vector3(0, 0.32, 0)), BRASS_DARK)
	# The barrel, its bands and the dome.
	_k(kit, KartMeshKit.cylinder(PUMP_RADIUS, PUMP_RADIUS, PUMP_TOP - 0.34, 20),
		_xf(p + Vector3(0, (PUMP_TOP + 0.34) * 0.5, 0)), BRASS)
	for y in [0.42, 0.78, PUMP_TOP - 0.05]:
		_k(kit, KartMeshKit.torus(PUMP_RADIUS - 0.01, PUMP_RADIUS + 0.03, 20, 6), _xf(p + Vector3(0, y, 0)), BRASS_DARK)
	_k(kit, KartMeshKit.sphere(PUMP_RADIUS, 20, 6, true), _xf(p + Vector3(0, PUMP_TOP, 0), Vector3.ZERO, Vector3(1, 0.6, 1)), BRASS)
	_k(kit, KartMeshKit.cylinder(0.07, 0.09, 0.12, 12), _xf(p + Vector3(0, PUMP_TOP + 0.2, 0)), BRASS_DARK)
	# The gauge's bezel on the barrel's front, facing the rider, and its little neck.
	var g := gauge_center()
	_k(kit, KartMeshKit.torus(GAUGE_RADIUS, GAUGE_RADIUS + 0.04, 22, 6), _xf(g + Vector3(0, 0, -0.005), Vector3(90, 0, 0)), BRASS_DARK)
	_k(kit, KartMeshKit.cylinder(GAUGE_RADIUS + 0.02, GAUGE_RADIUS + 0.02, 0.06, 22), _xf(g + Vector3(0, 0, -0.04), Vector3(90, 0, 0)), BRASS)
	# The outlet at the barrel's foot and the hose to the nozzle stand, lying on the rug.
	_k(kit, KartMeshKit.cylinder(0.05, 0.05, 0.22, 10), _xf(p + Vector3(0.3, 0.42, 0.0), Vector3(0, 0, 90)), BRASS_DARK)
	var hose := PackedVector3Array([p + Vector3(0.42, 0.42, 0.0), p + Vector3(0.55, 0.2, -0.05),
		p + Vector3(0.7, 0.07, -0.2), Vector3(-0.05, 0.07, -2.9), Vector3(0.25, 0.07, -3.08),
		NOZZLE_POS * Vector3(1, 0, 1) + Vector3(-0.06, 0.12, 0.0)])
	_k(kit, KartMeshKit.tube(hose, PackedFloat32Array([0.045]), 8), Transform3D.IDENTITY, HOSE)
	# The nozzle stand: a weighted foot, a pole and the nozzle cone the balloon sits on.
	var n := NOZZLE_POS * Vector3(1, 0, 1)
	_k(kit, KartMeshKit.cylinder(0.2, 0.24, 0.08, 18), _xf(n + Vector3(0, 0.04, 0)), BRASS_DARK)
	_k(kit, KartMeshKit.cylinder(0.035, 0.035, NOZZLE_POS.y - 0.12, 10), _xf(n + Vector3(0, (NOZZLE_POS.y - 0.12) * 0.5 + 0.06, 0)), BRASS)
	_k(kit, KartMeshKit.cylinder(0.025, 0.06, 0.1, 12), _xf(Vector3(n.x, NOZZLE_POS.y - 0.05, n.z)), BRASS)
	_k(kit, KartMeshKit.torus(0.05, 0.075, 12, 5), _xf(Vector3(n.x, NOZZLE_POS.y - 0.12, n.z)), BRASS_DARK)
	# The bunch's tether: a weight on the lawn and a short post.
	var t := TETHER * Vector3(1, 0, 1)
	_k(kit, KartMeshKit.cylinder(0.12, 0.15, 0.16, 14), _xf(t + Vector3(0, 0.08, 0)), BRASS_DARK)
	_k(kit, KartMeshKit.cylinder(0.025, 0.025, TETHER.y - 0.12, 8), _xf(t + Vector3(0, TETHER.y * 0.5 + 0.06, 0)), BRASS)
	_k(kit, KartMeshKit.sphere(0.05, 10, 5), _xf(TETHER), BRASS)
	return kit.commit()


## Where the gauge's face sits (on the barrel's front, toward the rider).
static func gauge_center() -> Vector3:
	return PUMP_POS + Vector3(0.0, GAUGE_Y, PUMP_RADIUS + 0.05)


## The plunger: a rod and a T handle with red grips, its foot at the origin (the world moves it
## with each pedal stroke).
static func plunger() -> ArrayMesh:
	var kit := _kit()
	_k(kit, KartMeshKit.cylinder(0.032, 0.032, PLUNGER_HANDLE, 10), _xf(Vector3(0, PLUNGER_HANDLE * 0.5, 0)), Color("f0d9a0"))
	_k(kit, KartMeshKit.cylinder(0.04, 0.04, 0.62, 10), _xf(Vector3(0, PLUNGER_HANDLE, 0), Vector3(0, 0, 90)), BRASS)
	for side in [-1.0, 1.0]:
		_k(kit, KartMeshKit.cylinder(0.055, 0.055, 0.17, 12), _xf(Vector3(side * 0.24, PLUNGER_HANDLE, 0), Vector3(0, 0, 90)), RED)
	_k(kit, KartMeshKit.sphere(0.06, 10, 5), _xf(Vector3(0, PLUNGER_HANDLE, 0)), BRASS_DARK)
	return kit.commit()


## The Ferris wheel's turning part (its stand is in the scenery): a rim, spokes and gondolas,
## centred on the origin in the xy plane.
static func wheel() -> ArrayMesh:
	var kit := _kit()
	var r := WHEEL_RADIUS
	_k(kit, KartMeshKit.torus(r - 0.2, r + 0.1, 36, 4), _xf(Vector3.ZERO, Vector3(90, 0, 0)), CREAM)
	_k(kit, KartMeshKit.torus(r * 0.55 - 0.12, r * 0.55 + 0.08, 28, 4), _xf(Vector3.ZERO, Vector3(90, 0, 0)), PINK)
	_k(kit, KartMeshKit.cylinder(0.6, 0.6, 0.8, 12), _xf(Vector3.ZERO, Vector3(90, 0, 0)), PINK)
	var count := 12
	for i in count:
		var a := TAU * i / count
		var d := Vector3(cos(a), sin(a), 0.0)
		_k(kit, KartMeshKit.box(Vector3(0.12, 1.0, 0.12)), KartMeshKit.between(d * 0.5, d * (r - 0.1), Vector3(1, 1, 1)), CREAM)
		var stripes: Array = TENT_STRIPES[i % TENT_STRIPES.size()]
		_k(kit, KartMeshKit.box(Vector3(1.2, 1.0, 1.0)), _xf(d * r + Vector3(0, -0.8, 0)), stripes[0])
		_k(kit, KartMeshKit.box(Vector3(1.35, 0.12, 1.15)), _xf(d * r + Vector3(0, -0.25, 0)), stripes[1])
	return kit.commit()


# --- The fairground (one baked mesh) ---

static func scenery() -> ArrayMesh:
	var kit := _kit(1.0)
	# The lawn: a big grid (haze per vertex needs vertices), with grain.
	var lawn := PlaneMesh.new()
	lawn.size = Vector2(300.0, 300.0)
	lawn.subdivide_width = 29
	lawn.subdivide_depth = 29
	_k(kit, lawn, _xf(Vector3(0, 0, -100)), LAWN)
	kit.outline = 0.0
	# The rug under the pump and the stand: a round mat in pink and cream, with a red rim.
	_k(kit, KartMeshKit.cylinder(1.62, 1.66, 0.04, 32), _xf(Vector3(-0.3, 0.02, -2.95)), RED)
	_striped(kit, KartMeshKit.cylinder(1.5, 1.5, 0.02, 32), _xf(Vector3(-0.3, 0.05, -2.95)), PINK, CREAM, 16)
	_stall(kit)
	_tents(kit)
	_wheel_stand(kit)
	_trees(kit)
	_hills(kit)
	_bunting(kit)
	return kit.commit()


static func _stall(kit: KartMeshKit) -> void:
	kit.ao_y0 = 0.0
	kit.ao_y1 = 0.9
	kit.ao_min = 0.7
	var stripe := 0.4
	# The counter: mint and cream stripes, a pink top.
	for i in 11:
		var x := -2.0 + i * stripe
		_k(kit, KartMeshKit.box(Vector3(stripe, 1.0, 0.6)), _xf(Vector3(x, 0.5, COUNTER_Z)), MINT if i % 2 == 0 else CREAM)
	_k(kit, KartMeshKit.box(Vector3(4.6, 0.08, 0.78)), _xf(Vector3(0, 1.04, COUNTER_Z + 0.05)), PINK)
	# The back wall: pink and cream stripes.
	for i in 12:
		var x := -2.2 + i * stripe
		_k(kit, KartMeshKit.box(Vector3(stripe, 2.9, 0.12)), _xf(Vector3(x, 1.45, BACK_Z)), PINK if i % 2 == 0 else CREAM)
	# The side walls.
	for side in [-1.0, 1.0]:
		_k(kit, KartMeshKit.box(Vector3(0.1, 2.9, 0.8)), _xf(Vector3(side * 2.4, 1.45, (COUNTER_Z + BACK_Z) * 0.5)), CREAM)
	kit.ao_min = 1.0
	# The posts, with brass caps.
	for side in [-1.0, 1.0]:
		_k(kit, KartMeshKit.cylinder(0.08, 0.08, 3.15, 10), _xf(Vector3(side * 2.38, 1.575, COUNTER_Z + 0.3)), CREAM)
		_k(kit, KartMeshKit.sphere(0.12, 10, 5), _xf(Vector3(side * 2.38, 3.2, COUNTER_Z + 0.3)), BRASS)
		for y in [0.6, 1.4, 2.2]:
			_k(kit, KartMeshKit.torus(0.07, 0.1, 10, 4), _xf(Vector3(side * 2.38, y, COUNTER_Z + 0.3)), PINK)
	# The awning: stripes sloping up to the back, scallops along the front.
	var front := Vector3(0, 3.1, COUNTER_Z + 0.4)
	var back := Vector3(0, 3.45, BACK_Z - 0.05)
	var depth := Vector2(front.z - back.z, back.y - front.y).length()
	var tilt := rad_to_deg(atan2(back.y - front.y, front.z - back.z))
	for i in 13:
		var x := -2.4 + i * stripe
		var mid := (front + back) * 0.5 + Vector3(x, 0, 0)
		_k(kit, KartMeshKit.box(Vector3(stripe, 0.05, depth)), _xf(mid, Vector3(tilt, 0, 0)), PINK if i % 2 == 0 else CREAM)
	kit.ao_min = 1.0
	for i in 13:
		var x := -2.4 + i * stripe
		_k(kit, KartMeshKit.sphere(0.2, 10, 4, true), _xf(Vector3(x, front.y + 0.01, front.z), Vector3(180, 0, 0), Vector3(1, 0.85, 0.35)),
			PINK if i % 2 == 0 else CREAM)
	# Bulbs under the awning's front, self-lit.
	kit.glow = 1.0
	for i in 12:
		_k(kit, KartMeshKit.sphere(0.045, 8, 4), _xf(Vector3(-2.2 + i * stripe, 2.9, front.z - 0.05)), Color("fff2c0"))
	kit.glow = 0.0
	# The rack on the counter's right: a wooden block and a peg for the next balloon.
	var r := RACK_POS
	_k(kit, KartMeshKit.box(Vector3(0.5, 0.06, 0.34)), _xf(Vector3(r.x, 1.11, r.z)), WOOD)
	_k(kit, KartMeshKit.cylinder(0.02, 0.03, 0.06, 8), _xf(Vector3(r.x, r.y - 0.02, r.z)), BRASS_DARK)
	kit.ao_min = 1.0


## A striped cylinder (a tent's wall or roof): `paint` colours by the angle round it.
static func _striped(kit: KartMeshKit, mesh: Mesh, xf: Transform3D, a: Color, b: Color, count := 12) -> void:
	var la := lin(a)
	var lb := lin(b)
	kit.paint = func(p: Vector3, _n: Vector3, c: Color) -> Color:
		var ang := atan2(p.z, p.x) / TAU + 0.5
		var pick := la if int(floor(ang * count)) % 2 == 0 else lb
		return Color(pick.r * c.r, pick.g * c.g, pick.b * c.b, c.a)
	kit.add(mesh, xf, Color.WHITE)
	kit.paint = Callable()


static func _tents(kit: KartMeshKit) -> void:
	var spots := [Vector3(-9.0, 0, -15.0), Vector3(9.5, 0, -17.0), Vector3(-20.0, 0, -24.0),
		Vector3(19.0, 0, -27.0), Vector3(4.0, 0, -33.0), Vector3(-6.0, 0, -42.0), Vector3(28.0, 0, -40.0)]
	for i in spots.size():
		var p: Vector3 = spots[i]
		var r := 2.4 + (i % 3) * 0.6
		var h := 2.2 + (i % 2) * 0.6
		var s: Array = TENT_STRIPES[i % TENT_STRIPES.size()]
		kit.ao_y0 = p.y
		kit.ao_y1 = p.y + h
		kit.ao_min = 0.75
		_striped(kit, KartMeshKit.cylinder(r, r, h, 20), _xf(p + Vector3(0, h * 0.5, 0)), s[0], s[1], 16)
		kit.ao_min = 1.0
		_striped(kit, KartMeshKit.cylinder(0.05, r + 0.35, h * 0.85, 20), _xf(p + Vector3(0, h + h * 0.425, 0)), s[1], s[0], 16)
		var top := p + Vector3(0, h * 1.85, 0)
		_k(kit, KartMeshKit.cylinder(0.04, 0.04, 0.8, 6), _xf(top + Vector3(0, 0.4, 0)), CREAM)
		var pennant := Color(s[0].r, s[0].g, s[0].b, 0.3)
		_k(kit, KartMeshKit.prism(Vector3(0.7, 0.4, 0.04)), _xf(top + Vector3(0.35, 0.65, 0), Vector3(0, 0, -90)), pennant)


static func _wheel_stand(kit: KartMeshKit) -> void:
	var c := WHEEL_POS
	for side in [-1.0, 1.0]:
		for lean in [-1.0, 1.0]:
			var foot := Vector3(c.x + lean * 4.5, 0.0, c.z + side * 1.2)
			_k(kit, KartMeshKit.box(Vector3(0.35, 1.0, 0.35)), KartMeshKit.between(foot, c + Vector3(0, 0, side * 0.6)), CREAM)
	_k(kit, KartMeshKit.box(Vector3(10.0, 0.6, 3.0)), _xf(Vector3(c.x, 0.3, c.z)), PINK)


static func _trees(kit: KartMeshKit) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7613
	var spots := [Vector3(-6.0, 0, -10.0), Vector3(6.5, 0, -11.0), Vector3(-13.0, 0, -12.0), Vector3(14.0, 0, -10.0),
		Vector3(-26.0, 0, -18.0), Vector3(25.0, 0, -16.0), Vector3(-3.0, 0, -25.0), Vector3(12.0, 0, -30.0),
		Vector3(-30.0, 0, -36.0), Vector3(36.0, 0, -32.0), Vector3(-22.0, 0, -50.0), Vector3(20.0, 0, -55.0),
		Vector3(0.0, 0, -60.0), Vector3(-40.0, 0, -45.0), Vector3(42.0, 0, -50.0)]
	for p: Vector3 in spots:
		var h := rng.randf_range(2.2, 3.4)
		var r := rng.randf_range(1.4, 2.2)
		var green: Color = TREE_GREENS[rng.randi() % TREE_GREENS.size()]
		kit.ao_y0 = 0.0
		kit.ao_y1 = h
		kit.ao_min = 0.7
		_k(kit, KartMeshKit.cylinder(0.16, 0.22, h, 8), _xf(p + Vector3(0, h * 0.5, 0)), WOOD.darkened(0.25))
		kit.ao_y0 = h - r * 0.6
		kit.ao_y1 = h + r
		_k(kit, KartMeshKit.blob(Vector3(r, r * 1.05, r), 1.0, 1.0, 12, 7), _xf(p + Vector3(0, h + r * 0.6, 0)), green)
		_k(kit, KartMeshKit.blob(Vector3(r * 0.6, r * 0.6, r * 0.6), 1.0, 1.0, 10, 5),
			_xf(p + Vector3(r * 0.55, h + r * 0.2, r * 0.3)), green.lightened(0.08))
	kit.ao_min = 1.0


static func _hills(kit: KartMeshKit) -> void:
	var hills := [[Vector3(-70, -14, -130), 60.0], [Vector3(20, -18, -150), 75.0], [Vector3(95, -12, -120), 55.0],
		[Vector3(-130, -10, -90), 50.0], [Vector3(140, -16, -70), 55.0]]
	for i in hills.size():
		var h: Array = hills[i]
		_k(kit, KartMeshKit.blob(Vector3(h[1], h[1] * 0.45, h[1]), 1.0, 1.0, 16, 8), _xf(h[0]), HILL_GREENS[i % HILL_GREENS.size()])


## Bunting: two runs of little flags from the stall's posts out to the tents, sagging.
static func _bunting(kit: KartMeshKit) -> void:
	var runs := [[Vector3(-2.38, 3.2, COUNTER_Z + 0.3), Vector3(-9.0, 4.4, -15.0)],
		[Vector3(2.38, 3.2, COUNTER_Z + 0.3), Vector3(9.5, 4.4, -17.0)],
		[Vector3(-2.38, 3.2, COUNTER_Z + 0.3), Vector3(2.38, 3.2, COUNTER_Z + 0.3)]]
	for run in runs:
		var a: Vector3 = run[0]
		var b: Vector3 = run[1]
		var count := int(a.distance_to(b) / 0.45)
		var sag := 0.5 if a.distance_to(b) > 6.0 else 0.3
		var prev := a
		for i in count + 1:
			var t := float(i) / count
			var p := a.lerp(b, t) - Vector3(0, sag * 4.0 * t * (1.0 - t), 0)
			if i > 0:
				_k(kit, KartMeshKit.box(Vector3(0.012, 1.0, 0.012)), KartMeshKit.between(prev, p), CREAM)
			prev = p
			if i == 0 or i == count:
				continue
			var c: Color = BUNTING[i % BUNTING.size()]
			var yaw := rad_to_deg(atan2(b.x - a.x, b.z - a.z)) + 90.0
			_k(kit, KartMeshKit.prism(Vector3(0.26, 0.3, 0.02)), _xf(p - Vector3(0, 0.16, 0), Vector3(180, yaw, 0)),
				Color(c.r, c.g, c.b, 0.35))


# --- The view on screen ---

## The darkening (as a colour multiplier) at a screen position `suv` (0-1 each way): the shared
## include's vignette, in linear light (Tug's recipe, TugMeshes.vignette_at).
static func vignette_at(suv: Vector2) -> Color:
	var p := suv * 2.0 - Vector2.ONE
	p.x *= 1.35
	var v := smoothstep(0.7, 1.75, p.length())
	var m := 1.0 - v * VIGNETTE
	var tint := Color.WHITE.lerp(VIGNETTE_TINT, v * 0.5)
	return Color(m * tint.r, m * tint.g, m * tint.b)


## The grid that draws the 3D view's image at `size` on screen: UVs across the image and the
## vignette in the vertex colours (display values, so the linear multiplier goes to 1/2.2).
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
