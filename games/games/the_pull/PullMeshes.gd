class_name PullMeshes
extends RefCounted
## Every mesh of The Pull's world (#79), built in code from primitive shapes with KartMeshKit:
## vertex colours with painted AO, so each object is one draw call on the shared scenery shader.
## UV.x says how much the floodlight pools reach a vertex (0 on the far horizon), UV.y is the
## self-lit glow (lamps, fair lights, the boards' faces, the Full Pull line); COLOR.a is 1 - sway.
## ART_BIBLE.md has the palette and the layout.
##
## The track runs from the start line at z = 0 down -z. Its centre is x = 0.

const HALF_WIDTH := 6.2  ## the barriers' x
const LENGTH := 460.0  ## the track's length past the start
const BOARD_X := -7.2
const TOWER_X := 8.5
const TOWER_SPACING := 40.0
const STAND_X := 10.0  ## the stands' first tier
const STAND_TIERS := 3
const TIER_DEPTH := 1.3
const TIER_RISE := 0.55
const SECTION := 34.0  ## a stand section's length (gaps at the towers)
const FAIR_Z := -540.0
## The view grid (as Tug's): the vignette in its vertex colours.
const VIEW_COLS := 12
const VIEW_ROWS := 8
const VIGNETTE := 0.32
const VIGNETTE_TINT := Color(0.75, 0.8, 1.05)

const CLAY := Color("c27a4a")
const CHALK := Color("ede6d6")
const BARRIER_WHITE := Color("e8e4dc")
const BARRIER_RED := Color("c8382e")
const BOARD_FACE := Color("f2e6c8")
const POST := Color("5a4630")
const STEEL := Color("262626")
const SLED_YELLOW := Color("f2b71c")
const WEIGHT := Color("6a7480")
const FLOOD := Color("ffd9a0")
const ACCENT := Color("5fd068")
const INK := Color("10200f")
const STAND_WOOD := Color("6b5844")
const FAIR_LIGHTS := [Color("ffb347"), Color("ff5d73"), Color("6fd3ff"), Color("fff1a8")]


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


static func _kit() -> KartMeshKit:
	var kit := KartMeshKit.new()
	kit.flags = true
	kit.outline = 1.0  # UV.x: the pools reach it
	kit.glow = 0.0
	return kit


static func _box(kit: KartMeshKit, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	kit.add(KartMeshKit.box(size), KartMeshKit.xf(pos, rot), color)


## The track's statics: barriers, stands, floodlight towers, distance boards, the Full Pull line
## and arch at `full_m`, and the far fair. One mesh.
static func scenery(full_m: float, seed_value := 79) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var kit := _kit()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 1.2
	kit.ao_min = 0.6
	_barriers(kit)
	_stands(kit)
	_boards(kit)
	_towers(kit)
	_full_line(kit, full_m)
	kit.ao_min = 1.0
	_fair(kit, rng)
	return kit.commit()


static func _barriers(kit: KartMeshKit) -> void:
	# A low rail each side in red and white blocks of 2 m, on dark feet.
	for side: float in [-1.0, 1.0]:
		var z := 6.0
		var k := 0
		while z > -LENGTH:
			_box(kit, Vector3(0.18, 0.5, 1.96), Vector3(side * HALF_WIDTH, 0.45, z - 1.0),
				BARRIER_RED if k % 2 == 0 else BARRIER_WHITE)
			_box(kit, Vector3(0.3, 0.2, 0.3), Vector3(side * HALF_WIDTH, 0.1, z - 1.0), STEEL)
			z -= 2.0
			k += 1


static func _stands(kit: KartMeshKit) -> void:
	var z := 14.0
	while z > -LENGTH + 20.0:
		var length := SECTION
		var centre := z - length / 2.0
		for side: float in [-1.0, 1.0]:
			for t in STAND_TIERS:
				var x := side * (STAND_X + TIER_DEPTH * (t + 0.5))
				var top := TIER_RISE * (t + 1)
				_box(kit, Vector3(TIER_DEPTH, top, length), Vector3(x, top / 2.0, centre),
					STAND_WOOD.lightened(0.06 * t))
			# The back wall and a roof on posts.
			var back := side * (STAND_X + TIER_DEPTH * STAND_TIERS + 0.2)
			_box(kit, Vector3(0.3, 3.6, length), Vector3(back, 1.8, centre), STAND_WOOD.darkened(0.25))
			_box(kit, Vector3(TIER_DEPTH * STAND_TIERS + 1.0, 0.15, length), Vector3(side * (STAND_X + 1.9), 4.1, centre),
				Color("3c4a5a"), Vector3(0, 0, -side * 8.0))
		z -= TOWER_SPACING


static func _boards(kit: KartMeshKit) -> void:
	var m := 25.0
	while m < LENGTH - 10.0:
		var z := -m
		_box(kit, Vector3(0.12, 2.3, 0.12), Vector3(BOARD_X - 0.65, 1.15, z), POST)
		_box(kit, Vector3(0.12, 2.3, 0.12), Vector3(BOARD_X + 0.65, 1.15, z), POST)
		kit.glow = 0.45
		_box(kit, Vector3(1.7, 1.05, 0.1), Vector3(BOARD_X, 1.85, z), BOARD_FACE)
		kit.glow = 0.0
		_box(kit, Vector3(1.8, 0.08, 0.14), Vector3(BOARD_X, 2.4, z), INK)
		# A tick across the track at each board: a short chalk mark by the barrier.
		_box(kit, Vector3(0.8, 0.02, 0.12), Vector3(-HALF_WIDTH + 0.6, 0.01, z), CHALK)
		_box(kit, Vector3(0.8, 0.02, 0.12), Vector3(HALF_WIDTH - 0.6, 0.01, z), CHALK)
		m += 25.0


static func _towers(kit: KartMeshKit) -> void:
	var z := 0.0
	while z > -LENGTH - 20.0:
		for side: float in [-1.0, 1.0]:
			var x := side * TOWER_X
			kit.add(KartMeshKit.cylinder(0.14, 0.2, 16.0, 6), KartMeshKit.xf(Vector3(x, 8.0, z)), Color("4a4f57"))
			_box(kit, Vector3(2.6, 1.1, 0.25), Vector3(x - side * 0.6, 16.2, z), Color("2c3036"), Vector3(0, 0, side * 12.0))
			kit.glow = 1.0
			for i in 4:
				var lx := x - side * 0.6 + (i - 1.5) * 0.6
				_box(kit, Vector3(0.45, 0.4, 0.08), Vector3(lx, 16.2, z + 0.15), FLOOD, Vector3(0, 0, side * 12.0))
			kit.glow = 0.0
		z -= TOWER_SPACING


static func _full_line(kit: KartMeshKit, full_m: float) -> void:
	var z := -full_m
	kit.glow = 0.55
	var squares := 24
	var size := HALF_WIDTH * 2.0 / squares
	for row in 2:
		for i in squares:
			var dark := (i + row) % 2 == 0
			_box(kit, Vector3(size, 0.02, 0.5), Vector3(-HALF_WIDTH + size * (i + 0.5), 0.012, z + 0.25 - row * 0.5),
				Color("1a1a1a") if dark else Color("f2c230"))
	kit.glow = 0.0
	# The arch: two posts and a beam with a green banner (its words are a Label3D).
	for side: float in [-1.0, 1.0]:
		_box(kit, Vector3(0.35, 5.6, 0.35), Vector3(side * (HALF_WIDTH + 0.5), 2.8, z), Color("2c3036"))
	_box(kit, Vector3(HALF_WIDTH * 2.0 + 1.4, 0.3, 0.35), Vector3(0, 5.6, z), Color("2c3036"))
	kit.glow = 0.5
	_box(kit, Vector3(7.0, 1.2, 0.12), Vector3(0, 4.7, z), ACCENT.darkened(0.15))
	kit.glow = 0.0


static func _fair(kit: KartMeshKit, rng: RandomNumberGenerator) -> void:
	kit.outline = 0.0  # beyond the pools
	# A tree line around everything.
	var tree := Color("17241e")
	var z := 40.0
	while z > FAIR_Z - 40.0:
		for side: float in [-1.0, 1.0]:
			var h := rng.randf_range(7.0, 13.0)
			kit.add(KartMeshKit.cylinder(0.0, rng.randf_range(2.5, 4.0), h, 6),
				KartMeshKit.xf(Vector3(side * rng.randf_range(40.0, 48.0), h / 2.0, z)), tree)
		z -= rng.randf_range(5.0, 8.0)
	var x := -60.0
	while x < 60.0:
		var h := rng.randf_range(8.0, 14.0)
		kit.add(KartMeshKit.cylinder(0.0, 3.5, h, 6), KartMeshKit.xf(Vector3(x, h / 2.0, FAIR_Z - 30.0)), tree)
		x += rng.randf_range(5.0, 8.0)
	# Tents on the left, striped.
	var stripes := [Color("d94a3a"), Color("f2e6c8"), Color("3a7fd9"), Color("f2c230")]
	for i in 5:
		var pos := Vector3(-34.0 + i * 7.5, 0.0, FAIR_Z + 10.0 - (i % 2) * 8.0)
		var c: Color = stripes[i % stripes.size()]
		kit.add(KartMeshKit.cylinder(2.6, 2.6, 2.4, 8), KartMeshKit.xf(pos + Vector3(0, 1.2, 0)), c)
		kit.add(KartMeshKit.cylinder(0.0, 3.2, 2.6, 8), KartMeshKit.xf(pos + Vector3(0, 3.7, 0)), c.lightened(0.15))
		kit.glow = 1.0
		_box(kit, Vector3(0.3, 0.3, 0.3), pos + Vector3(0, 5.1, 0), FAIR_LIGHTS[i % 4])
		kit.glow = 0.0
	# A lit wheel on the right horizon.
	var hub := Vector3(36.0, 18.0, FAIR_Z)
	kit.add(KartMeshKit.torus(13.4, 14.0, 28, 4), KartMeshKit.xf(hub, Vector3(90, 0, 0)), Color("6a6f7a"))
	for i in 12:
		var a := TAU * i / 12.0
		var tip := hub + Vector3(cos(a), sin(a), 0.0) * 13.7
		kit.add(KartMeshKit.box(Vector3(0.15, 1.0, 0.15)), KartMeshKit.between(hub, tip, Vector3(1, 1, 1)), Color("6a6f7a"))
	kit.glow = 1.0
	for i in 24:
		var a := TAU * i / 24.0
		_box(kit, Vector3(0.6, 0.6, 0.3), hub + Vector3(cos(a), sin(a), 0.0) * 13.7, FAIR_LIGHTS[i % 4])
	kit.glow = 0.0
	for leg: float in [-1.0, 1.0]:
		kit.add(KartMeshKit.box(Vector3(0.4, 1.0, 0.4)), KartMeshKit.between(hub, Vector3(36.0 + leg * 9.0, 0.0, FAIR_Z), Vector3(1, 1, 1)),
			Color("4a4f57"))
	# String lights across the far end.
	kit.glow = 1.0
	for i in 40:
		var t := float(i) / 39.0
		var px := lerpf(-28.0, 20.0, t)
		var py := 6.0 - sin(t * PI * 4.0) * 0.0 - 1.4 * sin(fmod(t * 4.0, 1.0) * PI)
		_box(kit, Vector3(0.22, 0.22, 0.22), Vector3(px, py, FAIR_Z + 18.0), FAIR_LIGHTS[i % 4])
	kit.glow = 0.0
	kit.outline = 1.0


## The sled: its pan, runners, yellow frame, box rails and the hitch tower. The hitch is at the
## origin and the sled runs back along +z (behind the rider).
static func sled() -> ArrayMesh:
	var kit := _kit()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 0.8
	kit.ao_min = 0.55
	_box(kit, Vector3(1.9, 0.12, 4.0), Vector3(0, 0.16, 2.6), STEEL.lightened(0.12))
	for side: float in [-1.0, 1.0]:
		_box(kit, Vector3(0.14, 0.24, 4.4), Vector3(side * 0.9, 0.12, 2.5), STEEL)
		_box(kit, Vector3(0.14, 0.24, 0.6), Vector3(side * 0.9, 0.3, 0.35), STEEL, Vector3(-30, 0, 0))
		# The frame: corner posts and a top rail.
		for z: float in [0.7, 4.5]:
			_box(kit, Vector3(0.12, 1.0, 0.12), Vector3(side * 0.88, 0.7, z), SLED_YELLOW)
		_box(kit, Vector3(0.12, 0.12, 3.9), Vector3(side * 0.88, 1.2, 2.6), SLED_YELLOW)
		# The rails the weight box slides on.
		_box(kit, Vector3(0.1, 0.1, 3.8), Vector3(side * 0.45, 0.27, 2.6), Color("9aa0a8"))
	_box(kit, Vector3(1.88, 0.12, 0.12), Vector3(0, 1.2, 4.5), SLED_YELLOW)
	_box(kit, Vector3(1.88, 0.25, 0.2), Vector3(0, 0.35, 4.6), SLED_YELLOW.darkened(0.2))
	# The hitch tower: an A-frame up to the chain's ring.
	for side: float in [-1.0, 1.0]:
		kit.add(KartMeshKit.box(Vector3(0.12, 1.0, 0.12)),
			KartMeshKit.between(Vector3(side * 0.7, 0.25, 0.9), Vector3(0, 0.62, 0.05), Vector3.ONE), SLED_YELLOW)
	kit.add(KartMeshKit.torus(0.06, 0.11, 10, 4), KartMeshKit.xf(Vector3(0, 0.6, 0.0), Vector3(0, 0, 90)), STEEL.lightened(0.3))
	return kit.commit()


## The weight box: a yellow cage of slate blocks, its base at the origin, 1.1 m long in z.
static func weight_box() -> ArrayMesh:
	var kit := _kit()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 1.0
	kit.ao_min = 0.6
	for layer in 3:
		for col in 2:
			for row in 2:
				var tone := WEIGHT.lightened(0.04 * ((layer + col + row) % 3))
				_box(kit, Vector3(0.6, 0.28, 0.52), Vector3((col - 0.5) * 0.62, 0.17 + layer * 0.3, (row - 0.5) * 0.54), tone)
	for x: float in [-0.66, 0.66]:
		for z: float in [-0.58, 0.58]:
			_box(kit, Vector3(0.08, 1.05, 0.08), Vector3(x, 0.52, z), SLED_YELLOW)
	for z: float in [-0.58, 0.58]:
		_box(kit, Vector3(1.4, 0.08, 0.08), Vector3(0, 1.02, z), SLED_YELLOW)
	_box(kit, Vector3(1.4, 0.06, 1.24), Vector3(0, 0.03, 0), STEEL)
	return kit.commit()


## The rider's bike up front, in the rig's space: the bars, the grips and gloves, the stem, the
## top of the front tyre and the mirror's stalk and rim (the glass is its own quad).
static func bike(bars: Vector3, mirror: Vector3) -> ArrayMesh:
	var kit := _kit()
	kit.outline = 0.4
	var bar := Color("2a2e33")
	kit.add(KartMeshKit.cylinder(0.022, 0.022, 0.66, 8), KartMeshKit.xf(bars, Vector3(0, 0, 90)), bar)
	for side: float in [-1.0, 1.0]:
		var grip := bars + Vector3(side * 0.3, 0, 0)
		kit.add(KartMeshKit.cylinder(0.03, 0.03, 0.14, 8), KartMeshKit.xf(grip, Vector3(0, 0, 90)), Color("111111"))
		# A glove over the grip: a rounded fist in the accent, knuckles forward.
		kit.add(KartMeshKit.sphere(0.07, 8, 5), KartMeshKit.xf(grip + Vector3(0, 0.03, 0.01), Vector3.ZERO, Vector3(1.0, 0.85, 1.25)),
			ACCENT.darkened(0.35))
		kit.add(KartMeshKit.sphere(0.05, 8, 4), KartMeshKit.xf(grip + Vector3(0, 0.0, 0.1), Vector3.ZERO, Vector3(0.9, 0.8, 1.4)),
			Color("23332a"))
	kit.add(KartMeshKit.cylinder(0.03, 0.035, 0.5, 8), KartMeshKit.xf(bars + Vector3(0, -0.24, -0.05), Vector3(10, 0, 0)), bar)
	kit.add(KartMeshKit.torus(0.3, 0.36, 18, 5), KartMeshKit.xf(bars + Vector3(0, -0.75, -0.3), Vector3(0, 90, 0)), Color("161616"))
	# The mirror: a stalk from the right bar end to a rim around the glass.
	var bar_end := bars + Vector3(0.33, 0, 0)
	kit.add(KartMeshKit.box(Vector3(0.018, 1.0, 0.018)), KartMeshKit.between(bar_end, mirror + Vector3(0, -0.07, 0.01), Vector3.ONE), bar)
	kit.add(KartMeshKit.cylinder(0.105, 0.105, 0.03, 16), KartMeshKit.xf(mirror + Vector3(0, 0, -0.02), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.68)),
		Color("1a1c1f"))
	return kit.commit()


## One chain link (a flattened ring).
static func chain_link() -> ArrayMesh:
	var kit := _kit()
	kit.add(KartMeshKit.torus(0.022, 0.045, 8, 4), KartMeshKit.xf(Vector3.ZERO, Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.6)),
		Color("8a9098"))
	return kit.commit()


## The best flag: a pole and a cloth in the accent (the cloth sways: COLOR.a 0).
static func flag() -> ArrayMesh:
	var kit := _kit()
	kit.add(KartMeshKit.cylinder(0.04, 0.05, 3.4, 6), KartMeshKit.xf(Vector3(0, 1.7, 0)), Color("d8d8d8"))
	kit.glow = 0.45
	var segs := 8
	for i in segs:
		var x0 := -0.04 - 1.2 * i / segs
		var x1 := -0.04 - 1.2 * (i + 1) / segs
		var c := ACCENT
		c.a = 1.0 - float(i + 1) / segs  # sways more toward the free end
		kit.quad(Vector3(x0, 3.3, 0), Vector3(x1, 3.3, 0), Vector3(x1, 2.55, 0), Vector3(x0, 2.55, 0), c)
		kit.quad(Vector3(x1, 3.3, 0), Vector3(x0, 3.3, 0), Vector3(x0, 2.55, 0), Vector3(x1, 2.55, 0), c)
	return kit.commit()


static func vignette_at(suv: Vector2) -> Color:
	var p := suv * 2.0 - Vector2.ONE
	p.x *= 1.35
	var v := smoothstep(0.7, 1.75, p.length())
	var m := 1.0 - v * VIGNETTE
	var tint := Color.WHITE.lerp(VIGNETTE_TINT, v * 0.5)
	return Color(m * tint.r, m * tint.g, m * tint.b)


## The grid that draws the 3D view's image at `size` on screen, the vignette in its vertex
## colours (display values, so the linear multiplier goes to the power 1/2.2).
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
