class_name TugMeshes
extends RefCounted
## Tug of War's procedural meshes (graphics pass, 2026-10-19; ART_BIBLE.md). Everything is built
## here from primitive shapes merged into vertex-coloured meshes with `MeshKit3D` (read only:
## Kart owns it), so the whole riverside is one draw call, the bot two and the rider's gloves one.
## Colours are the bible's palette (sRGB), turned linear for the vertex colours (`lin`): the
## shaders light and grade in linear space like the engine's own materials.
##
## Vertex data the Tug shaders read:
##   scenery.gdshader: COLOR.a = 1 - sway weight (reeds, bunting, the flag's cloth),
##     UV.x = ground grain (1 on the banks), UV.y = glow (the string lights' bulbs).
##   bot.gdshader: UV.x = 1 takes the bot's body colour, UV.y = 1 is the wind-up key (it spins).

const BANK_RUN := 0.9  ## metres from a bank's top edge to its foot under the water
const BANK_FOOT := -0.45
const WATERLINE_OUT := 0.55  ## where the bank's slope meets the water, out from its top edge

# The palette (ART_BIBLE §3), sRGB.
const DECK := Color("8c6138")
const GAP := Color("2e1f14")
const PILING := Color("4d331f")
const GRASS := Color("4d8033")
const EARTH := Color("6b5233")
const ROPE_LIGHT := Color("c7a86b")
const ROPE_DARK := Color("8c6b42")
const FLAG := Color("ff401f")
const GLOVE := Color("5980d9")
const IRON := Color(0.2, 0.2, 0.23)
const BRASS := Color(0.86, 0.68, 0.3)
const REED := Color(0.42, 0.52, 0.22)
const REED_TIP := Color(0.68, 0.62, 0.36)
## The bunting's and the tent's colours: saturated toys, never the flag's red.
const BUNTING := [Color(0.95, 0.75, 0.25), Color(0.3, 0.6, 0.9), Color(0.95, 0.95, 0.9),
	Color(0.4, 0.75, 0.4), Color(0.95, 0.55, 0.2), Color(0.85, 0.5, 0.8)]

## The bot's local points the world animates (bot space, feet at the origin, facing +z).
const BOT_KEY_PIVOT := Vector2(0.0, 1.12)  ## the key turns about z through this x, y
const BOT_CHIMNEY_TOP := Vector3(0.14, 2.74, -0.1)
const BOT_EYES := [Vector3(-0.13, 2.05, 0.4), Vector3(0.13, 2.05, 0.4)]


static func lin(c: Color) -> Color:
	var l := c.srgb_to_linear()
	return Color(l.r, l.g, l.b, c.a)


static func _k(kit: MeshKit3D, mesh: Mesh, xf: Transform3D, color: Color) -> void:
	kit.add(mesh, xf, lin(color))


static func _new_kit() -> MeshKit3D:
	var kit := MeshKit3D.new()
	kit.flags = true
	kit.outline = 0.0
	kit.glow = 0.0
	return kit


## Where each bank's slope meets the water (z), for the water shader's foam.
static func waterlines() -> Vector2:
	return Vector2(TugWorld.NEAR_BANK_Z - WATERLINE_OUT, TugWorld.FAR_BANK_Z + WATERLINE_OUT)


# --- A small triangle list, wound like the kit (front faces along the normals) ---

class Tris:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	func tri(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		if (b - a).cross(c - a).dot(n) > 0.0:
			verts.append_array([a, c, b])
			colors.append_array([ca, cc, cb])
		else:
			verts.append_array([a, b, c])
			colors.append_array([ca, cb, cc])
		normals.append_array([n, n, n])

	## Both sides of a thin card, each with its own normal (cards are lit from either side).
	func card(a: Vector3, b: Vector3, c: Vector3, n: Vector3, ca: Color, cb: Color, cc: Color) -> void:
		tri(a, b, c, n, ca, cb, cc)
		tri(a, b, c, -n, ca, cb, cc)

	func mesh() -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_COLOR] = colors
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		return m


## A nature-kit model as one vertex-coloured surface: leaves (the greener materials) in `leaf`,
## the rest in `bark`, so a tree can be baked into the scenery and lit by hand.
static func model(mesh: Mesh, leaf: Color, bark: Color) -> ArrayMesh:
	if mesh == null:
		return null
	var t := Tris.new()
	for s in mesh.get_surface_count():
		var a := mesh.surface_get_arrays(s)
		var m := mesh.surface_get_material(s) as StandardMaterial3D
		var c := lin(bark)
		if m != null and m.albedo_color.g > m.albedo_color.r:
			c = lin(leaf)
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX] if a[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var count := idx.size() if not idx.is_empty() else v.size()
		for i in count:
			var vi := idx[i] if not idx.is_empty() else i
			t.verts.append(v[vi])
			t.normals.append(n[vi])
			t.colors.append(c)
	return t.mesh()


## The points of a rope hung from `a` to `b`, sagging `sag` metres at the middle.
static func catenary(a: Vector3, b: Vector3, sag: float, count: int) -> PackedVector3Array:
	var pts := PackedVector3Array()
	for i in count + 1:
		var t := float(i) / count
		var p := a.lerp(b, t)
		p.y -= sag * 4.0 * t * (1.0 - t)
		pts.append(p)
	return pts


# --- The riverside: one static mesh (scenery.gdshader) ---

## Banks, hills, trees, bushes and rocks, pier frames and pilings, torch posts, masts, bunting,
## string lights, reeds, shore rocks, the tent and the hay bales. `models` holds the converted
## nature-kit meshes: "trees" (an Array of four), "bush" and "rock".
static func scenery(models: Dictionary) -> ArrayMesh:
	var kit := _new_kit()
	_banks(kit)
	_hills(kit)
	_piers(kit)
	_masts_and_strings(kit)
	_reeds_and_shore(kit, models.get("rock"))
	_plants(kit, models)
	_fairground(kit)
	return kit.commit()


static func _bank(kit: MeshKit3D, edge_z: float, toward_water: float, inland: float) -> void:
	# A cross-section from far inland to under the water (out = metres past the top edge, toward
	# the water), revolved along x as a strip of columns with jittered tints.
	var top := TugWorld.BANK_TOP
	var rows := [[-inland, top, GRASS], [-6.0, top, GRASS], [-1.2, top, GRASS.darkened(0.08)],
		[-0.3, top, GRASS.darkened(0.2)], [0.0, top - 0.03, EARTH.lightened(0.05)],
		[0.22, top - 0.14, EARTH], [WATERLINE_OUT, 0.0, EARTH.darkened(0.35)],
		[BANK_RUN, BANK_FOOT, EARTH.darkened(0.6)]]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(absf(edge_z) * 100.0)
	var xs: Array[float] = []
	var x := -90.0
	while x <= 90.0:
		xs.append(x)
		x += 6.0
	var jitter: Array[float] = []
	for i in xs.size():
		jitter.append(rng.randf_range(0.9, 1.08))
	for r in rows.size() - 1:
		var t := Tris.new()
		var o0: float = rows[r][0]
		var o1: float = rows[r + 1][0]
		var y0: float = rows[r][1]
		var y1: float = rows[r + 1][1]
		var z0 := edge_z + o0 * toward_water
		var z1 := edge_z + o1 * toward_water
		var slope := Vector2(o1 - o0, y1 - y0).normalized()
		var n := Vector3(0.0, slope.x, -slope.y * toward_water).normalized()
		for i in xs.size() - 1:
			var c00 := lin(rows[r][2]) * jitter[i]
			var c10 := lin(rows[r][2]) * jitter[i + 1]
			var c01 := lin(rows[r + 1][2]) * jitter[i]
			var c11 := lin(rows[r + 1][2]) * jitter[i + 1]
			for c in [c00, c10, c01, c11]:
				c.a = 1.0
			var a := Vector3(xs[i], y0, z0)
			var b := Vector3(xs[i + 1], y0, z0)
			var c := Vector3(xs[i], y1, z1)
			var d := Vector3(xs[i + 1], y1, z1)
			t.tri(a, b, c, n, c00, c10, c01)
			t.tri(b, d, c, n, c10, c11, c01)
		kit.outline = 1.0 if r < 4 else 0.6
		kit.add(t.mesh(), Transform3D.IDENTITY, Color.WHITE)
	kit.outline = 0.0


static func _banks(kit: MeshKit3D) -> void:
	# The near bank's water lies toward -z, the far bank's toward +z.
	_bank(kit, TugWorld.NEAR_BANK_Z, -1.0, 40.0)
	_bank(kit, TugWorld.FAR_BANK_Z, 1.0, 100.0)


static func _hills(kit: MeshKit3D) -> void:
	# Far hills, flattened spheres in two tints, behind everything (the old layout's seed).
	var hill := MeshKit3D.sphere(1.0, 12, 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	for i in 9:
		var tint := Color(0.22, 0.38, 0.28).lerp(Color(0.3, 0.45, 0.35), rng.randf())
		var pos := Vector3(-90.0 + i * 22.0 + rng.randf_range(-6.0, 6.0), 0.0, rng.randf_range(-95.0, -70.0))
		var s := Vector3(rng.randf_range(24.0, 36.0), rng.randf_range(9.0, 18.0), rng.randf_range(14.0, 20.0))
		_k(kit, hill, Transform3D(Basis.from_scale(s), pos), tint)


static func _piers(kit: MeshKit3D) -> void:
	var top := TugWorld.DECK_TOP
	# Painted AO: the timber darkens toward the water.
	kit.ao_y0 = -0.3
	kit.ao_y1 = top
	kit.ao_min = 0.45
	var beam := PILING.lightened(0.12)
	for pier in [[TugWorld.NEAR_EDGE_Z, TugWorld.NEAR_EDGE_Z + 9.0], [TugWorld.FAR_EDGE_Z - 7.0, TugWorld.FAR_EDGE_Z]]:
		var z0: float = pier[0]
		var z1: float = pier[1]
		var mid := (z0 + z1) * 0.5
		var length := z1 - z0
		for x: float in [-2.47, 2.47]:  # the side beams frame the deck
			_k(kit, MeshKit3D.box(Vector3(0.1, 0.3, length)), MeshKit3D.xf(Vector3(x, top - 0.13, mid)), beam)
		# The end beam over the water, and the pilings under it.
		var end_z: float = z0 if z0 == TugWorld.NEAR_EDGE_Z else z1
		var out := -1.0 if end_z == TugWorld.NEAR_EDGE_Z else 1.0
		_k(kit, MeshKit3D.box(Vector3(5.04, 0.3, 0.1)), MeshKit3D.xf(Vector3(0.0, top - 0.13, end_z + out * 0.03)), beam)
		for x: float in [-2.3, -0.8, 0.8, 2.3]:
			var r := 0.12 if absf(x) > 2.0 else 0.09
			var h := top + 1.0
			_k(kit, MeshKit3D.cylinder(r, r * 1.08, h, 8), MeshKit3D.xf(Vector3(x, top - h * 0.5 - 0.03, end_z - out * 0.16)), PILING)
	kit.ao_min = 1.0
	# The far pier's torch posts: a post, a bracket and an iron cup for the flame card.
	var post_z := TugWorld.FAR_EDGE_Z - 0.15
	for x: float in [-2.35, 2.35]:
		_k(kit, MeshKit3D.box(Vector3(0.16, 1.28, 0.16)), MeshKit3D.xf(Vector3(x, top + 0.64, post_z)), PILING)
		_k(kit, MeshKit3D.box(Vector3(0.24, 0.06, 0.24)), MeshKit3D.xf(Vector3(x, top + 1.27, post_z)), IRON)
		var cup := MeshKit3D.lathe(PackedVector2Array([Vector2(0.05, 0.0), Vector2(0.13, 0.12), Vector2(0.15, 0.2),
			Vector2(0.11, 0.2), Vector2(0.0, 0.12)]), 8)
		_k(kit, cup, MeshKit3D.xf(Vector3(x, top + 1.3, post_z)), IRON)


static func _mast(kit: MeshKit3D, x: float, z: float, height: float) -> Vector3:
	var on_deck := absf(x) < 2.5 and (z > TugWorld.NEAR_EDGE_Z or z < TugWorld.FAR_EDGE_Z)
	var base := TugWorld.DECK_TOP if on_deck else TugWorld.BANK_TOP
	_k(kit, MeshKit3D.cylinder(0.05, 0.07, height, 6), MeshKit3D.xf(Vector3(x, base + height * 0.5, z)), PILING.lightened(0.2))
	_k(kit, MeshKit3D.sphere(0.08, 6, 3), MeshKit3D.xf(Vector3(x, base + height, z)), BRASS)
	return Vector3(x, base + height - 0.05, z)


## The bunting and the string lights hang from masts beside the far torches: the bunting back to
## masts on the near bank (wide of the camera), the lights out over the far bank. Both stay wide
## of the rope's line from the fists to the bot.
static func _masts_and_strings(kit: MeshKit3D) -> void:
	var wire := Color(0.25, 0.2, 0.16)
	for side: float in [-1.0, 1.0]:
		var far := _mast(kit, side * 2.4, TugWorld.FAR_EDGE_Z - 0.45, 2.7)
		var near := _mast(kit, side * 6.8, TugWorld.NEAR_BANK_Z + 0.9, 4.2)
		var out := _mast(kit, side * 9.6, TugWorld.FAR_BANK_Z - 0.6, 2.9)
		# Bunting: triangles under a sagging line, alternating colours, fluttering at the tips.
		var line := catenary(far, near, 0.7, 26)
		_k(kit, MeshKit3D.tube(line, PackedFloat32Array([0.016]), 4), Transform3D.IDENTITY, wire)
		var flags := Tris.new()
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			var tip := (a + b) * 0.5 + Vector3(0.0, -0.3, 0.0)
			var n := (b - a).cross(Vector3.DOWN).normalized()
			var c := lin(BUNTING[i % BUNTING.size()])
			var still := Color(c.r, c.g, c.b, 1.0)
			var loose := Color(c.r * 0.9, c.g * 0.9, c.b * 0.9, 0.0)
			flags.card(a, b, tip, n, still, still, loose)
		kit.add(flags.mesh(), Transform3D.IDENTITY, Color.WHITE)
		# String lights: bulbs along a sagging wire; they glow with the lamps (UV.y).
		var lights := catenary(far + Vector3(0.0, -0.15, 0.0), out, 0.45, 14)
		_k(kit, MeshKit3D.tube(lights, PackedFloat32Array([0.014]), 4), Transform3D.IDENTITY, wire)
		var bulb := MeshKit3D.sphere(0.065, 6, 3)
		kit.glow = 1.0
		for i in range(1, lights.size() - 1):
			var c := Color(1.0, 0.86, 0.55) if i % 2 == 0 else Color(1.0, 0.62, 0.32)
			_k(kit, bulb, MeshKit3D.xf(lights[i] + Vector3(0.0, -0.07, 0.0)), c)
		kit.glow = 0.0


static func _reed_clump(t: Tris, base: Vector3, rng: RandomNumberGenerator) -> void:
	for b in rng.randi_range(4, 7):
		var h := rng.randf_range(0.45, 0.95)
		var ang := rng.randf() * TAU
		var dir := Vector3(cos(ang), 0.0, sin(ang))
		var lean := Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
		var p := base + dir * rng.randf_range(0.0, 0.18)
		var w := rng.randf_range(0.025, 0.04)
		var side := dir.cross(Vector3.UP) * w
		var mid := p + Vector3.UP * h * 0.55 + lean * 0.5
		var tip := p + Vector3.UP * h + lean
		# Lit like the ground, so the blades never flip dark against the light.
		var n := Vector3(0.0, 0.8, 0.6).normalized()
		var root := lin(REED.darkened(0.25))
		root.a = 1.0
		var middle := lin(REED)
		middle.a = 0.55
		var top := lin(REED_TIP)
		top.a = 0.0
		t.card(p - side, p + side, mid + side * 0.6, n, root, root, middle)
		t.card(p - side, mid + side * 0.6, mid - side * 0.6, n, root, middle, middle)
		t.card(mid - side * 0.6, mid + side * 0.6, tip, n, middle, middle, top)


static func _reeds_and_shore(kit: MeshKit3D, rock: Mesh) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 6113
	var reeds := Tris.new()
	var lines := waterlines()
	for bank in [[lines.x, -1.0, 40], [lines.y, 1.0, 54]]:
		var wl: float = bank[0]
		var toward: float = bank[1]
		for i in int(bank[2]):
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := side * rng.randf_range(3.4, 34.0)
			var z := wl + toward * rng.randf_range(-0.25, 0.05)
			_reed_clump(reeds, Vector3(x, -0.05, z), rng)
	kit.add(reeds.mesh(), Transform3D.IDENTITY, Color.WHITE)
	if rock != null:
		for bank in [[lines.x, -1.0], [lines.y, 1.0]]:
			for i in 12:
				var side := -1.0 if i % 2 == 0 else 1.0
				var x := side * rng.randf_range(3.2, 26.0)
				var z: float = bank[0] + bank[1] * rng.randf_range(-0.2, 0.15)
				var s := rng.randf_range(0.5, 1.1)
				kit.add(rock, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, -0.12, z)),
					Color(rng.randf_range(0.85, 1.05), rng.randf_range(0.85, 1.05), rng.randf_range(0.85, 1.0)))


## The trees, bushes and rocks (the old layout's seed and counts, kept off the water).
static func _plants(kit: MeshKit3D, models: Dictionary) -> void:
	var trees: Array = models.get("trees", [])
	var bush: Mesh = models.get("bush")
	var rock: Mesh = models.get("rock")
	var rng := RandomNumberGenerator.new()
	rng.seed = 9981
	kit.ao_y0 = TugWorld.BANK_TOP
	kit.ao_y1 = TugWorld.BANK_TOP + 2.4
	kit.ao_min = 0.55
	var y := TugWorld.BANK_TOP - 0.05
	for i in 70:
		var far := rng.randf() < 0.75
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(7.0, 38.0)
		var z := rng.randf_range(TugWorld.FAR_BANK_Z - 40.0, TugWorld.FAR_BANK_Z - 1.0) if far \
			else rng.randf_range(TugWorld.NEAR_BANK_Z + 1.0, TugWorld.NEAR_BANK_Z + 13.0)
		var s := rng.randf_range(2.6, 4.4)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, y, z))
		var which := rng.randi() % 4
		if which < trees.size() and trees[which] != null:
			var v := rng.randf_range(0.88, 1.08)
			kit.add(trees[which], xf, Color(v, v, v * 0.96))
	for i in 36:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var far := rng.randf() < 0.6
		var x := side * rng.randf_range(4.0, 26.0)
		var z := rng.randf_range(TugWorld.FAR_BANK_Z - 22.0, TugWorld.FAR_BANK_Z - 0.6) if far \
			else rng.randf_range(TugWorld.NEAR_BANK_Z + 0.6, TugWorld.NEAR_BANK_Z + 9.0)
		var xf := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.6, 2.6)), Vector3(x, y, z))
		var m: Mesh = rock if rng.randf() < 0.3 else bush
		if m != null:
			kit.add(m, xf, Color.WHITE)
	kit.ao_min = 1.0


## Behind the far crowd: a striped tent (mustard and cream, a blue pennant) and hay bales.
static func _fairground(kit: MeshKit3D) -> void:
	var y := TugWorld.BANK_TOP - 0.02
	var tent_at := Vector3(-11.5, y, TugWorld.FAR_BANK_Z - 9.0)
	var stripes := Callable(func(p: Vector3, _n: Vector3, c: Color) -> Color:
		var a := atan2(p.z, p.x)
		var cream := fmod(a / TAU * 12.0 + 12.0, 2.0) < 1.0
		var col := lin(Color(0.95, 0.92, 0.82)) if cream else lin(Color(0.93, 0.7, 0.2))
		return Color(col.r * c.r, col.g * c.g, col.b * c.b, 1.0))
	kit.paint = stripes
	var walls := MeshKit3D.lathe(PackedVector2Array([Vector2(2.3, 0.0), Vector2(2.3, 1.5), Vector2(2.45, 1.6),
		Vector2(1.2, 2.5), Vector2(0.15, 3.35), Vector2(0.0, 3.4)]), 12)
	kit.add(walls, MeshKit3D.xf(tent_at), Color.WHITE)
	kit.paint = Callable()
	_k(kit, MeshKit3D.box(Vector3(1.0, 1.3, 0.05)), MeshKit3D.xf(tent_at + Vector3(0.4, 0.65, 2.29)), Color(0.12, 0.08, 0.06))
	_k(kit, MeshKit3D.cylinder(0.03, 0.03, 0.8, 4), MeshKit3D.xf(tent_at + Vector3(0.0, 3.7, 0.0)), PILING)
	var pennant := Tris.new()
	var blue := lin(Color(0.3, 0.6, 0.9))
	pennant.card(tent_at + Vector3(0.0, 4.05, 0.0), tent_at + Vector3(0.0, 3.8, 0.0), tent_at + Vector3(0.55, 3.93, 0.0),
		Vector3.BACK, Color(blue, 1.0), Color(blue, 1.0), Color(blue, 0.0))
	kit.add(pennant.mesh(), Transform3D.IDENTITY, Color.WHITE)
	var bale := MeshKit3D.blob(Vector3(0.55, 0.32, 0.38), 0.3, 0.3, 8, 6)
	kit.ao_y0 = y
	kit.ao_y1 = y + 0.7
	kit.ao_min = 0.7
	for b in [[Vector3(7.6, 0.3, -7.8), 8.0], [Vector3(8.8, 0.3, -7.4), -14.0], [Vector3(8.2, 0.92, -7.6), 3.0],
			[Vector3(-7.4, 0.3, -6.6), 30.0]]:
		_k(kit, bale, MeshKit3D.xf(Vector3(0.0, y, TugWorld.FAR_BANK_Z) + b[0], Vector3(0.0, b[1], 0.0)), Color(0.85, 0.7, 0.36))
	kit.ao_min = 1.0


# --- The deck tops (deck.gdshader draws the planks) ---

static func decks() -> ArrayMesh:
	var t := Tris.new()
	var y := TugWorld.DECK_TOP
	var w := Color.WHITE
	for pier in [[TugWorld.NEAR_EDGE_Z, TugWorld.NEAR_EDGE_Z + 9.0], [TugWorld.FAR_EDGE_Z - 7.0, TugWorld.FAR_EDGE_Z]]:
		var a := Vector3(-2.52, y, pier[0])
		var b := Vector3(2.52, y, pier[0])
		var c := Vector3(-2.52, y, pier[1])
		var d := Vector3(2.52, y, pier[1])
		t.tri(a, b, c, Vector3.UP, w, w, w)
		t.tri(b, d, c, Vector3.UP, w, w, w)
	return t.mesh()


# --- The bot: a wind-up tin robot (bot.gdshader) ---

## The bot's body (one mesh): barrel body, dome head with a visor slot, mitten hands on the rope,
## a chimney, a gauge, rivets, and the wind-up key on its back (UV.y = 1). Body-coloured parts
## carry UV.x = 1 and white-ish paint (the shader multiplies in the body colour).
static func bot_body() -> ArrayMesh:
	var kit := _new_kit()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 1.0
	kit.ao_min = 0.55
	var dark := IRON
	# Feet and legs.
	for x: float in [-0.24, 0.24]:
		_k(kit, MeshKit3D.blob(Vector3(0.19, 0.12, 0.28), 0.5, 0.5, 8, 5), MeshKit3D.xf(Vector3(x, 0.12, 0.06)), dark)
		var leg := PackedVector3Array()
		var cols := PackedColorArray()
		for i in 5:
			leg.append(Vector3(x * 0.92, 0.2 + i * 0.09, 0.0))
			cols.append(lin(Color(0.55, 0.55, 0.58) if i % 2 == 0 else Color(0.3, 0.3, 0.33)))
		kit.add(MeshKit3D.tube(leg, PackedFloat32Array([0.085]), 6, cols), Transform3D.IDENTITY, Color.WHITE)
	_k(kit, MeshKit3D.lathe(PackedVector2Array([Vector2(0.3, 0.52), Vector2(0.42, 0.56), Vector2(0.42, 0.62),
		Vector2(0.3, 0.64)]), 12), Transform3D.IDENTITY, dark)
	# The barrel body, in the body colour with darker hoops.
	kit.outline = 1.0
	var shade := Color(0.62, 0.62, 0.62)
	var paint := Color(1.0, 1.0, 1.0)
	var body := MeshKit3D.lathe(PackedVector2Array([Vector2(0.34, 0.58), Vector2(0.44, 0.62), Vector2(0.46, 0.68),
		Vector2(0.52, 0.78), Vector2(0.55, 1.05), Vector2(0.53, 1.32), Vector2(0.47, 1.46), Vector2(0.45, 1.52),
		Vector2(0.36, 1.6), Vector2(0.0, 1.62)]), 14,
		PackedColorArray([shade, shade, paint, paint, paint, paint, paint, shade, shade, shade]))
	kit.add(body, Transform3D.IDENTITY, Color.WHITE)
	# The head: a short drum and a dome.
	var head := MeshKit3D.lathe(PackedVector2Array([Vector2(0.0, 1.7), Vector2(0.3, 1.7), Vector2(0.39, 1.75),
		Vector2(0.41, 1.9), Vector2(0.41, 2.16), Vector2(0.37, 2.3), Vector2(0.27, 2.42), Vector2(0.13, 2.49),
		Vector2(0.0, 2.51)]), 14, PackedColorArray([shade, shade, paint, paint, paint, paint, paint, paint, paint]))
	kit.add(head, Transform3D.IDENTITY, Color.WHITE)
	# Shoulders and mitten hands on the rope (the rope meets them at (0, 1.3, 0.97)).
	for x: float in [-0.56, 0.56]:
		kit.add(MeshKit3D.sphere(0.14, 8, 4), MeshKit3D.xf(Vector3(x, 1.38, 0.0)), Color(0.92, 0.92, 0.92))
	for x: float in [-0.12, 0.12]:
		kit.add(MeshKit3D.blob(Vector3(0.1, 0.11, 0.13), 0.7, 0.7, 8, 5), MeshKit3D.xf(Vector3(x, 1.3, 0.9)), Color.WHITE)
		kit.add(MeshKit3D.blob(Vector3(0.04, 0.05, 0.06), 0.8, 0.8, 6, 4), MeshKit3D.xf(Vector3(x * 0.55, 1.4, 0.93), Vector3(0.0, 0.0, 0.0)), Color(0.9, 0.9, 0.9))
	kit.outline = 0.0
	# The arms: springy hoses from the shoulders to the mittens.
	for side: float in [-1.0, 1.0]:
		var arm := PackedVector3Array()
		var cols := PackedColorArray()
		var a := Vector3(side * 0.58, 1.34, 0.05)
		var b := Vector3(side * 0.52, 1.16, 0.5)
		var c := Vector3(side * 0.2, 1.28, 0.82)
		for i in 9:
			var t := i / 8.0
			arm.append(a.lerp(b, t).lerp(b.lerp(c, t), t))
			cols.append(lin(Color(0.6, 0.6, 0.62) if i % 2 == 0 else Color(0.32, 0.32, 0.35)))
		kit.add(MeshKit3D.tube(arm, PackedFloat32Array([0.07]), 6, cols), Transform3D.IDENTITY, Color.WHITE)
	# The visor slot (the eyes glow inside it) and the mouth grille.
	_k(kit, MeshKit3D.blob(Vector3(0.3, 0.085, 0.08), 0.25, 0.25, 10, 5), MeshKit3D.xf(Vector3(0.0, 2.05, 0.345)), Color(0.06, 0.06, 0.08))
	for i in 3:
		_k(kit, MeshKit3D.box(Vector3(0.24, 0.025, 0.04)), MeshKit3D.xf(Vector3(0.0, 1.82 + i * 0.045, 0.395)), Color(0.08, 0.08, 0.1))
	# The chest gauge: a brass rim, a cream face and a needle.
	_k(kit, MeshKit3D.cylinder(0.17, 0.17, 0.05, 14), MeshKit3D.xf(Vector3(0.0, 1.12, 0.53), Vector3(90.0, 0.0, 0.0)), BRASS)
	_k(kit, MeshKit3D.cylinder(0.135, 0.135, 0.02, 14), MeshKit3D.xf(Vector3(0.0, 1.12, 0.56), Vector3(90.0, 0.0, 0.0)), Color(0.95, 0.92, 0.8))
	_k(kit, MeshKit3D.box(Vector3(0.018, 0.11, 0.012)), MeshKit3D.xf(Vector3(0.03, 1.15, 0.575), Vector3(0.0, 0.0, -35.0)), Color(0.12, 0.1, 0.1))
	# Rivets in rings around the body and head.
	var rivet := MeshKit3D.sphere(0.024, 4, 2, true)
	for ring in [[0.79, 0.52], [1.3, 0.535], [1.76, 0.39]]:
		for i in 8:
			var a: float = TAU * (i + 0.5) / 8.0
			var n := Vector3(sin(a), 0.0, cos(a))
			var xf := Transform3D(Basis(n.cross(Vector3.UP), n, Vector3.UP), n * ring[1] + Vector3.UP * ring[0])
			_k(kit, rivet, xf, Color(0.8, 0.8, 0.76))
	# The chimney (it puffs steam in a surge).
	_k(kit, MeshKit3D.cylinder(0.075, 0.09, 0.3, 10), MeshKit3D.xf(Vector3(0.14, 2.56, -0.1)), dark)
	_k(kit, MeshKit3D.cylinder(0.11, 0.11, 0.05, 10), MeshKit3D.xf(Vector3(0.14, 2.71, -0.1)), Color(0.32, 0.32, 0.35))
	# The wind-up key on its back: a shaft and a two-lobed bow; it spins about z (UV.y = 1).
	kit.glow = 1.0
	var p := Vector3(BOT_KEY_PIVOT.x, BOT_KEY_PIVOT.y, 0.0)
	_k(kit, MeshKit3D.cylinder(0.04, 0.04, 0.32, 8), MeshKit3D.xf(p + Vector3(0.0, 0.0, -0.66), Vector3(90.0, 0.0, 0.0)), BRASS)
	_k(kit, MeshKit3D.sphere(0.07, 8, 4), MeshKit3D.xf(p + Vector3(0.0, 0.0, -0.83)), BRASS)
	for side: float in [-1.0, 1.0]:
		_k(kit, MeshKit3D.blob(Vector3(0.17, 0.11, 0.035), 0.9, 0.9, 8, 4), MeshKit3D.xf(p + Vector3(side * 0.17, 0.0, -0.83)), BRASS)
	kit.glow = 0.0
	return kit.commit()


## Ears (even rungs): round discs on the head's sides, in the body colour.
static func bot_ears() -> ArrayMesh:
	var kit := _new_kit()
	kit.outline = 1.0
	for side: float in [-1.0, 1.0]:
		kit.add(MeshKit3D.cylinder(0.14, 0.14, 0.08, 12), MeshKit3D.xf(Vector3(side * 0.43, 2.12, 0.0), Vector3(0.0, 0.0, 90.0)), Color(0.72, 0.72, 0.72))
		kit.add(MeshKit3D.cylinder(0.08, 0.08, 0.04, 10), MeshKit3D.xf(Vector3(side * 0.48, 2.12, 0.0), Vector3(0.0, 0.0, 90.0)), Color(0.45, 0.45, 0.45))
	return kit.commit()


## Horns (odd rungs): ivory cones from the dome, as on the intro card's portrait.
static func bot_horns() -> ArrayMesh:
	var kit := _new_kit()
	for side: float in [-1.0, 1.0]:
		_k(kit, MeshKit3D.cylinder(0.0, 0.075, 0.42, 8), MeshKit3D.xf(Vector3(side * 0.3, 2.52, 0.0), Vector3(0.0, 0.0, -32.0 * side)), Color(0.9, 0.86, 0.74))
	return kit.commit()


## The two eyes (eyes.gdshader animates their colour): little lenses in the visor slot.
static func bot_eyes() -> ArrayMesh:
	var kit := _new_kit()
	for p in BOT_EYES:
		kit.add(MeshKit3D.blob(Vector3(0.07, 0.05, 0.03), 1.0, 1.0, 10, 5), MeshKit3D.xf(p), Color.WHITE)
	return kit.commit()


# --- The rider's gloves on the rope (hands.gdshader) ---

## Chunky work gloves in the UI blue on the rope, cream knit cuffs, blue sleeves going back under
## the camera, and the rope's end just behind them. Camera space: the rope runs along -z
## from between the fists.
static func gloves() -> ArrayMesh:
	var kit := _new_kit()
	var glove := GLOVE
	var seam := GLOVE.darkened(0.35)
	for side: float in [-1.0, 1.0]:
		var c := Vector3(side * 0.064, 0.0, 0.0)
		# The palm and back of the hand, a pillowy block around the rope.
		_k(kit, MeshKit3D.blob(Vector3(0.05, 0.047, 0.062), 0.55, 0.6, 12, 8), MeshKit3D.xf(c + Vector3(0.0, 0.004, 0.006)), glove)
		# Curled fingers: four rolls across the top front, knuckles readable from above.
		for f in 4:
			var at := Vector3(c.x - 0.033 + f * 0.022, 0.03 - absf(f - 1.5) * 0.004, -0.028)
			_k(kit, MeshKit3D.blob(Vector3(0.0125, 0.02, 0.026), 0.8, 0.8, 8, 5), MeshKit3D.xf(at, Vector3(20.0, 0.0, 0.0)), glove.lightened(0.06))
			_k(kit, MeshKit3D.blob(Vector3(0.012, 0.012, 0.012), 1.0, 1.0, 6, 4), MeshKit3D.xf(at + Vector3(0.0, 0.016, 0.012)), glove.lightened(0.14))
		# The seam across the back, and the thumb wrapping the rope on the inside.
		_k(kit, MeshKit3D.box(Vector3(0.07, 0.004, 0.006)), MeshKit3D.xf(c + Vector3(0.0, 0.048, 0.012)), seam)
		_k(kit, MeshKit3D.blob(Vector3(0.016, 0.018, 0.034), 0.8, 0.8, 8, 5), MeshKit3D.xf(Vector3(side * 0.03, 0.012, -0.03), Vector3(0.0, side * 25.0, 0.0)), glove)
		# The cuff and the sleeve going back and down under the camera.
		_k(kit, MeshKit3D.lathe(PackedVector2Array([Vector2(0.044, 0.0), Vector2(0.058, 0.005), Vector2(0.06, 0.04),
			Vector2(0.056, 0.05), Vector2(0.0, 0.052)]), 10), MeshKit3D.xf(c + Vector3(side * 0.006, -0.012, 0.05), Vector3(-80.0, 0.0, 0.0)),
			Color(0.92, 0.88, 0.78))
		var sleeve := PackedVector3Array([c + Vector3(side * 0.008, -0.018, 0.09), c + Vector3(side * 0.016, -0.04, 0.15)])
		_k(kit, MeshKit3D.tube(sleeve, PackedFloat32Array([0.044, 0.047]), 10), Transform3D.IDENTITY, GLOVE.darkened(0.45))
	# The rope through the fists, its end showing just behind them.
	var tail := PackedVector3Array([Vector3(0.0, 0.0, -0.03), Vector3(0.0, -0.002, 0.03), Vector3(0.006, -0.012, 0.06)])
	var tc := PackedColorArray()
	for i in tail.size():
		tc.append(lin(ROPE_LIGHT if i % 2 == 0 else ROPE_DARK))
	kit.add(MeshKit3D.tube(tail, PackedFloat32Array([0.026, 0.026, 0.024]), 8, tc), Transform3D.IDENTITY, Color.WHITE)
	return kit.commit()


# --- The flag on the rope (scenery.gdshader, self-lit, its cloth fluttering) ---

## A short white pole and a red swallowtail pennant flying broadside to the rider, so its place on
## the rope reads at a glance (the world leans it to the right, clear of the bot); COLOR.a = 1 -
## flutter weight along the cloth.
static func flag() -> ArrayMesh:
	var kit := _new_kit()
	_k(kit, MeshKit3D.cylinder(0.022, 0.022, 0.95, 6), MeshKit3D.xf(Vector3(0.0, 0.475, 0.0)), Color(0.92, 0.92, 0.88))
	_k(kit, MeshKit3D.sphere(0.04, 6, 3), MeshKit3D.xf(Vector3(0.0, 0.97, 0.0)), BRASS)
	var t := Tris.new()
	var red := lin(FLAG)
	var cols := 6
	var length := 0.8
	var top := 0.93
	var bottom := 0.47
	for i in cols:
		var u0 := float(i) / cols
		var u1 := float(i + 1) / cols
		# The swallowtail: the fly end's middle cuts back.
		var notch0 := smoothstep(0.7, 1.0, u0) * 0.22
		var notch1 := smoothstep(0.7, 1.0, u1) * 0.22
		var mid := (top + bottom) * 0.5
		var c0 := Color(red.r, red.g, red.b, 1.0 - u0)
		var c1 := Color(red.r, red.g, red.b, 1.0 - u1)
		var a := Vector3(u0 * length, top, 0.0)
		var b := Vector3(u1 * length, top, 0.0)
		var m0 := Vector3(u0 * length - notch0, mid, 0.0)
		var m1 := Vector3(u1 * length - notch1, mid, 0.0)
		var d0 := Vector3(u0 * length, bottom, 0.0)
		var d1 := Vector3(u1 * length, bottom, 0.0)
		t.card(a, b, m0, Vector3.BACK, c0, c1, c0)
		t.card(b, m1, m0, Vector3.BACK, c1, c1, c0)
		t.card(m0, m1, d0, Vector3.BACK, c0, c1, c0)
		t.card(m1, d1, d0, Vector3.BACK, c1, c1, c0)
	kit.add(t.mesh(), Transform3D.IDENTITY, Color.WHITE)
	return kit.commit()


# --- Effects ---

## A lily pad (lily.gdshader): a flat disc with a notch, a paler rim, a raised centre; some carry a
## pink-white flower bud.
static func lily_pad(flower: bool) -> ArrayMesh:
	var t := Tris.new()
	var seg := 10
	var pad := lin(Color(0.27, 0.48, 0.2))
	var rim := lin(Color(0.38, 0.58, 0.26))
	var centre := Vector3(0.0, 0.02, 0.0)
	for i in seg:
		var a0 := (i + 0.5) / seg * TAU
		var a1 := (i + 1.5) / seg * TAU
		if i == 0:
			continue  # the notch
		var p0 := Vector3(cos(a0), 0.0, sin(a0))
		var p1 := Vector3(cos(a1), 0.0, sin(a1))
		t.tri(centre, p0, p1, Vector3.UP, pad, rim, rim)
	var kit := _new_kit()
	kit.add(t.mesh(), Transform3D.IDENTITY, Color.WHITE)
	if flower:
		_k(kit, MeshKit3D.blob(Vector3(0.14, 0.12, 0.14), 1.0, 1.0, 6, 4, PI * 0.55), MeshKit3D.xf(Vector3(0.25, 0.02, 0.1)), Color(0.98, 0.85, 0.9))
	return kit.commit()


## The two torch flames: a card each (flame.gdshader, additive), facing the rider; COLOR.a is
## each flame's flicker phase.
static func flames() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var normals := PackedVector3Array()
	var w := 0.46
	var h := 0.78
	var i := 0
	for x: float in [-2.35, 2.35]:
		var c := Vector3(x, TugWorld.DECK_TOP + 1.47, TugWorld.FAR_EDGE_Z - 0.13)
		var ph := Color(1.0, 1.0, 1.0, 0.3 + 0.4 * i)
		var a := c + Vector3(-w * 0.5, 0.0, 0.0)
		var b := c + Vector3(w * 0.5, 0.0, 0.0)
		var d := c + Vector3(-w * 0.5, h, 0.0)
		var e := c + Vector3(w * 0.5, h, 0.0)
		# Clockwise seen from +z (Godot's front faces).
		for v in [[a, Vector2(0, 1)], [d, Vector2(0, 0)], [b, Vector2(1, 1)], [b, Vector2(1, 1)], [d, Vector2(0, 0)], [e, Vector2(1, 0)]]:
			verts.append(v[0])
			uvs.append(v[1])
			cols.append(ph)
			normals.append(Vector3.BACK)
		i += 1
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = cols
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## A fan of the crowd (crowd.gdshader): an upright quad (the sprite, billboarded in the shader)
## and a flat quad on the ground under it (the blob shadow, NORMAL.y = 1).
static func crowd_fan() -> ArrayMesh:
	var verts := PackedVector3Array()
	var uvs := PackedVector2Array()
	var normals := PackedVector3Array()
	var w := 0.62
	var h := 1.0  # the shader scales it by the fan's height
	for v in [[Vector3(-w * 0.5, 0.0, 0.0), Vector2(0, 1)], [Vector3(-w * 0.5, h, 0.0), Vector2(0, 0)], [Vector3(w * 0.5, 0.0, 0.0), Vector2(1, 1)],
			[Vector3(w * 0.5, 0.0, 0.0), Vector2(1, 1)], [Vector3(-w * 0.5, h, 0.0), Vector2(0, 0)], [Vector3(w * 0.5, h, 0.0), Vector2(1, 0)]]:
		verts.append(v[0])
		uvs.append(v[1])
		normals.append(Vector3.BACK)
	var r := Vector2(0.42, 0.3)
	for v in [[Vector3(-r.x, 0.02, -r.y), Vector2(0, 0)], [Vector3(r.x, 0.02, -r.y), Vector2(1, 0)], [Vector3(-r.x, 0.02, r.y), Vector2(0, 1)],
			[Vector3(r.x, 0.02, -r.y), Vector2(1, 0)], [Vector3(r.x, 0.02, r.y), Vector2(1, 1)], [Vector3(-r.x, 0.02, r.y), Vector2(0, 1)]]:
		verts.append(v[0])
		uvs.append(v[1])
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## The crowd's sprite, two frames side by side (32 x 48 each): arms down, then arms up and
## cheering. R = shirt (and sleeves), G = skin (head, hands), B = trousers, black = hair.
static func crowd_sprite() -> ImageTexture:
	var w := 32
	var h := 48
	var img := Image.create(w * 2, h, false, Image.FORMAT_RGBA8)
	for frame in 2:
		for y in h:
			for x in w:
				var p := Vector2(x + 0.5, y + 0.5)
				var c := Color(0, 0, 0, 0)
				var head := p.distance_to(Vector2(16, 10.5)) < 6.2
				var hair := p.distance_to(Vector2(16, 8.6)) < 6.0 and p.y < 8.6
				var torso := Rect2(9.5, 17, 13, 16).has_point(p) and p.distance_to(Vector2(16, 26)) < 11.0
				var neck := Rect2(14, 15, 4, 3).has_point(p)
				var legs := (Rect2(10.5, 32, 4.6, 16).has_point(p) or Rect2(16.9, 32, 4.6, 16).has_point(p))
				var arm := false
				var hand := false
				for side: float in [-1.0, 1.0]:
					var shoulder := Vector2(16.0 + side * 6.0, 19.0)
					var tip := Vector2(16.0 + side * 9.5, 33.0) if frame == 0 else Vector2(16.0 + side * 12.0, 4.5)
					var seg := tip - shoulder
					var t := clampf((p - shoulder).dot(seg) / seg.length_squared(), 0.0, 1.0)
					var d := p.distance_to(shoulder + seg * t)
					if d < 2.3:
						arm = true
					if p.distance_to(tip) < 2.6:
						hand = true
				if hair:
					c = Color(0, 0, 0, 1)
				elif head or neck or hand:
					c = Color(0, 1, 0, 1)
				elif torso or arm:
					c = Color(1, 0, 0, 1)
				elif legs:
					c = Color(0, 0, 1, 1)
				img.set_pixel(frame * w + x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Tug's vignette (ART_BIBLE §4: 0.3 toward a warm tint), painted into the vertex colours of the
## grid that draws the 3D view scaled up on screen (`StageView3D.view_image`), so it costs nothing a pixel.
## It was LOOK_VIGNETTE in every world shader: about 20 ALU on every pixel of the view.
const VIGNETTE := 0.3
const VIGNETTE_TINT := Color(1.0, 0.9, 0.8)
