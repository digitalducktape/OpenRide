class_name PullMeshes
extends RefCounted
## Every mesh of The Pull's world (#79), built in code from primitive shapes with MeshKit3D:
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
const BANNERS := [Color("c8382e"), Color("2f5fa8"), Color("e8e4dc"), Color("3e8a4a"), Color("d9a227")]
const BUNTING := [Color("e04a3a"), Color("f2c230"), Color("3a7fd9"), Color("5fd068"), Color("f2e6c8")]
const ROOF := Color("4a5868")
## The wheel on the far right horizon (its own mesh: it turns, PullWorld).
const WHEEL_HUB := Vector3(36.0, 18.0, -540.0)
const WHEEL_RADIUS := 13.7
const BAR_HALF := 0.42  ## the handlebar's half width, grips included


static func _kit() -> MeshKit3D:
	var kit := MeshKit3D.new()
	kit.flags = true
	kit.outline = 1.0  # UV.x: the pools reach it
	kit.glow = 0.0
	return kit


static func _box(kit: MeshKit3D, size: Vector3, pos: Vector3, color: Color, rot := Vector3.ZERO) -> void:
	kit.add(MeshKit3D.box(size), MeshKit3D.xf(pos, rot), color)


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


static func _barriers(kit: MeshKit3D) -> void:
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


static func _stands(kit: MeshKit3D) -> void:
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
			_stand_front(kit, side, z, length)
			_stand_roof(kit, side, z, length)
		z -= TOWER_SPACING


## The stand's front: a low wall of painted panels facing the track (plain colour blocks and
## stripes, no words or logos).
static func _stand_front(kit: MeshKit3D, side: float, z: float, length: float) -> void:
	var x := side * (STAND_X - 0.08)
	var panels := int(length / 2.0)
	for i in panels:
		var c: Color = BANNERS[(i + int(absf(z))) % BANNERS.size()]
		var pz := z - (i + 0.5) * length / panels
		kit.glow = 0.12
		_box(kit, Vector3(0.08, 0.7, length / panels - 0.08), Vector3(x, 0.55, pz), c)
		kit.glow = 0.0
		_box(kit, Vector3(0.09, 0.08, length / panels - 0.08), Vector3(x, 0.78, pz), c.lightened(0.35))
	_box(kit, Vector3(0.1, 0.12, length), Vector3(x, 0.96, z - length / 2.0), STAND_WOOD.darkened(0.4))


## The roof: posts at the front, a corrugated sheet (alternating tones) sloping back, pennant
## bunting along its front edge (it sways: COLOR.a < 1) and a string of warm bulbs under it.
static func _stand_roof(kit: MeshKit3D, side: float, z: float, length: float) -> void:
	var front_x := side * (STAND_X + 0.15)
	var eave := 4.3
	var depth := TIER_DEPTH * STAND_TIERS + 1.0
	for i in 4:
		var pz := z - 1.0 - i * (length - 2.0) / 3.0
		_box(kit, Vector3(0.14, eave, 0.14), Vector3(front_x, eave / 2.0, pz), Color("3a3f46"))
	var ribs := int(length / 0.8)
	for i in ribs:
		var tone := ROOF if i % 2 == 0 else ROOF.lightened(0.12)
		_box(kit, Vector3(depth, 0.12, length / ribs), Vector3(side * (STAND_X + depth / 2.0 - 0.3), eave + 0.25, z - (i + 0.5) * length / ribs),
			tone, Vector3(0, 0, -side * 8.0))
	_box(kit, Vector3(0.12, 0.3, length), Vector3(front_x, eave - 0.05, z - length / 2.0), ROOF.darkened(0.3))
	# Bunting: pennants on a sagging line, alternating colours.
	var flags := int(length / 1.1)
	for i in flags:
		var t0 := float(i) / flags
		var t1 := float(i + 1) / flags
		var a := Vector3(front_x - side * 0.05, eave - 0.2 - 0.35 * sin(t0 * PI), z - t0 * length)
		var b := Vector3(front_x - side * 0.05, eave - 0.2 - 0.35 * sin(t1 * PI), z - t1 * length)
		var tip := (a + b) / 2.0 + Vector3(0, -0.42, 0)
		var c: Color = BUNTING[i % BUNTING.size()]
		c.a = 0.4  # sways
		kit.quad(a, b, tip, tip, c)
		kit.quad(b, a, tip, tip, c)
	# Bulbs under the eave.
	kit.glow = 1.0
	var bulbs := int(length / 1.6)
	for i in bulbs:
		var t := (i + 0.5) / bulbs
		var pos := Vector3(front_x - side * 0.1, eave - 0.75 - 0.25 * sin(t * PI), z - t * length)
		_box(kit, Vector3(0.12, 0.12, 0.12), pos, FLOOD.lightened(0.2))
	kit.glow = 0.0


static func _boards(kit: MeshKit3D) -> void:
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


static func _towers(kit: MeshKit3D) -> void:
	var z := 0.0
	while z > -LENGTH - 20.0:
		for side: float in [-1.0, 1.0]:
			var x := side * TOWER_X
			kit.add(MeshKit3D.cylinder(0.14, 0.2, 16.0, 6), MeshKit3D.xf(Vector3(x, 8.0, z)), Color("4a4f57"))
			_box(kit, Vector3(2.6, 1.1, 0.25), Vector3(x - side * 0.6, 16.2, z), Color("2c3036"), Vector3(0, 0, side * 12.0))
			kit.glow = 1.0
			for i in 4:
				var lx := x - side * 0.6 + (i - 1.5) * 0.6
				_box(kit, Vector3(0.45, 0.4, 0.08), Vector3(lx, 16.2, z + 0.15), FLOOD, Vector3(0, 0, side * 12.0))
			kit.glow = 0.0
		z -= TOWER_SPACING


static func _full_line(kit: MeshKit3D, full_m: float) -> void:
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


static func _fair(kit: MeshKit3D, rng: RandomNumberGenerator) -> void:
	kit.outline = 0.0  # beyond the pools
	# A tree line around everything.
	var tree := Color("17241e")
	var z := 40.0
	while z > FAIR_Z - 40.0:
		for side: float in [-1.0, 1.0]:
			var h := rng.randf_range(7.0, 13.0)
			kit.add(MeshKit3D.cylinder(0.0, rng.randf_range(2.5, 4.0), h, 6),
				MeshKit3D.xf(Vector3(side * rng.randf_range(40.0, 48.0), h / 2.0, z)), tree)
		z -= rng.randf_range(5.0, 8.0)
	var x := -60.0
	while x < 60.0:
		var h := rng.randf_range(8.0, 14.0)
		kit.add(MeshKit3D.cylinder(0.0, 3.5, h, 6), MeshKit3D.xf(Vector3(x, h / 2.0, FAIR_Z - 30.0)), tree)
		x += rng.randf_range(5.0, 8.0)
	# Tents on the left, striped.
	var stripes := [Color("d94a3a"), Color("f2e6c8"), Color("3a7fd9"), Color("f2c230")]
	for i in 5:
		var pos := Vector3(-34.0 + i * 7.5, 0.0, FAIR_Z + 10.0 - (i % 2) * 8.0)
		var c: Color = stripes[i % stripes.size()]
		kit.add(MeshKit3D.cylinder(2.6, 2.6, 2.4, 8), MeshKit3D.xf(pos + Vector3(0, 1.2, 0)), c)
		kit.add(MeshKit3D.cylinder(0.0, 3.2, 2.6, 8), MeshKit3D.xf(pos + Vector3(0, 3.7, 0)), c.lightened(0.15))
		kit.glow = 1.0
		_box(kit, Vector3(0.3, 0.3, 0.3), pos + Vector3(0, 5.1, 0), FAIR_LIGHTS[i % 4])
		kit.glow = 0.0
	# The wheel's legs (the wheel itself turns: `wheel()`).
	var hub := WHEEL_HUB
	for leg: float in [-1.0, 1.0]:
		kit.add(MeshKit3D.box(Vector3(0.4, 1.0, 0.4)), MeshKit3D.between(hub, Vector3(36.0 + leg * 9.0, 0.0, FAIR_Z), Vector3(1, 1, 1)),
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
		kit.add(MeshKit3D.box(Vector3(0.12, 1.0, 0.12)),
			MeshKit3D.between(Vector3(side * 0.7, 0.25, 0.9), Vector3(0, 0.62, 0.05), Vector3.ONE), SLED_YELLOW)
	kit.add(MeshKit3D.torus(0.06, 0.11, 10, 4), MeshKit3D.xf(Vector3(0, 0.6, 0.0), Vector3(0, 0, 90)), STEEL.lightened(0.3))
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


## The bike's handlebars, in the rig's space, as the other first-person games show them (Dodge
## Ball's bars; rider, 2026-11-02: no arms or hands): a thin bar low in the frame, rubber grips,
## short drops and a short, squared stem in the accent. The mirror stands on a straight jointed
## stalk off the right end (its glass is its own quad). ART_BIBLE §10 has the silhouette check.
static func bike(bars: Vector3, mirror: Vector3, mirror_size: Vector2) -> ArrayMesh:
	var kit := _kit()
	kit.outline = 0.4
	var steel := Color("7a818c")
	var rubber := Color("17181b")
	kit.add(MeshKit3D.cylinder(0.017, 0.017, BAR_HALF * 2.0 - 0.1, 10), MeshKit3D.xf(bars, Vector3(0, 0, 90)), steel)
	for side: float in [-1.0, 1.0]:
		kit.add(MeshKit3D.cylinder(0.023, 0.023, 0.15, 10), MeshKit3D.xf(bars + Vector3(side * (BAR_HALF - 0.075), 0, 0), Vector3(0, 0, 90)), rubber)
		kit.add(MeshKit3D.cylinder(0.015, 0.015, 0.12, 8), MeshKit3D.xf(bars + Vector3(side * (BAR_HALF - 0.16), -0.05, -0.02), Vector3(25, 0, 0)), steel)
	_box(kit, Vector3(0.06, 0.05, 0.16), bars + Vector3(0, -0.02, 0.07), ACCENT.darkened(0.15))
	_box(kit, Vector3(0.07, 0.3, 0.06), bars + Vector3(0, -0.17, 0.14), ACCENT.darkened(0.25))
	# The mirror's straight stalk, a chrome rim and a dark back.
	var bar_end := bars + Vector3(BAR_HALF, 0.0, 0.0)
	var joint := bar_end + Vector3(0.07, 0.05, -0.02)
	var foot := mirror + Vector3(-0.05, -mirror_size.y / 2.0 + 0.006, -0.01)
	kit.add(MeshKit3D.box(Vector3(0.016, 1.0, 0.016)), MeshKit3D.between(bar_end, joint), steel)
	kit.add(MeshKit3D.box(Vector3(0.03, 0.03, 0.03)), MeshKit3D.xf(joint), Color("8a9098"))
	kit.add(MeshKit3D.box(Vector3(0.014, 1.0, 0.014)), MeshKit3D.between(joint, foot), steel)
	var half := mirror_size.x / 2.0
	kit.glow = 0.3
	kit.add(MeshKit3D.torus(half - 0.002, half + 0.012, 28, 4), MeshKit3D.xf(mirror + Vector3(0, 0, -0.002), Vector3(90, 0, 0),
		Vector3(1.0, 1.0, mirror_size.y / mirror_size.x)), Color("d4d9e0"))
	kit.glow = 0.0
	kit.add(MeshKit3D.blob(Vector3(half, mirror_size.y / 2.0, 0.03), 1.0, 1.0, 16, 8), MeshKit3D.xf(mirror + Vector3(0, 0, -0.034)), Color("1a1c1f"))
	return kit.commit()


## The lit wheel on the horizon, around its hub at the origin (PullWorld turns it slowly).
static func wheel() -> ArrayMesh:
	var kit := _kit()
	kit.outline = 0.0
	kit.add(MeshKit3D.torus(13.4, 14.0, 28, 4), MeshKit3D.xf(Vector3.ZERO, Vector3(90, 0, 0)), Color("6a6f7a"))
	for i in 12:
		var a := TAU * i / 12.0
		var tip := Vector3(cos(a), sin(a), 0.0) * WHEEL_RADIUS
		kit.add(MeshKit3D.box(Vector3(0.15, 1.0, 0.15)), MeshKit3D.between(Vector3.ZERO, tip, Vector3.ONE), Color("6a6f7a"))
	kit.glow = 1.0
	for i in 24:
		var a := TAU * i / 24.0
		_box(kit, Vector3(0.6, 0.6, 0.3), Vector3(cos(a), sin(a), 0.0) * WHEEL_RADIUS, FAIR_LIGHTS[i % 4])
		# The gondolas hang under every other light.
		if i % 2 == 0:
			kit.glow = 0.0
			_box(kit, Vector3(1.2, 1.0, 0.9), Vector3(cos(a), sin(a), 0.0) * WHEEL_RADIUS + Vector3(0, -0.9, 0), FAIR_LIGHTS[(i / 2) % 4].darkened(0.4))
			kit.glow = 1.0
	kit.glow = 0.0
	return kit.commit()


## Every floodlight lamp head's centre, for the glow halos (PullWorld).
static func lamp_heads() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var z := 0.0
	while z > -LENGTH - 20.0:
		for side: float in [-1.0, 1.0]:
			out.append(Vector3(side * TOWER_X - side * 0.6, 16.2, z + 0.4))
		z -= TOWER_SPACING
	return out


## One chain link (a flattened ring).
static func chain_link() -> ArrayMesh:
	var kit := _kit()
	kit.add(MeshKit3D.torus(0.022, 0.045, 8, 4), MeshKit3D.xf(Vector3.ZERO, Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.6)),
		Color("8a9098"))
	return kit.commit()


## The best flag: a pole and a cloth in the accent (the cloth sways: COLOR.a 0).
static func flag() -> ArrayMesh:
	var kit := _kit()
	kit.add(MeshKit3D.cylinder(0.04, 0.05, 3.4, 6), MeshKit3D.xf(Vector3(0, 1.7, 0)), Color("d8d8d8"))
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
