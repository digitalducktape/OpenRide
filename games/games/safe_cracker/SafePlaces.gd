class_name SafePlaces
extends RefCounted
## The places Safe Cracker's safes are found in (#41). Each is a palette, one key light and a few
## shapes drawn in code into one `MeshBatch2D` batch (one draw call), so there are no assets and the
## picture redraws only when the safe changes. The slow ambient life (rain, the sea, the lantern,
## the flasks, dust in the light) is `SafeBackdrop`'s, in shaders and tweens. Names are plain
## descriptions; nothing here refers to any existing game or film. ART_BIBLE.md §3 and §6.

const SIZE := Vector2(1920, 1080)
## The room is painted this far past each side of the stage, so a wider window (#57: the bike's
## shows 68 px more each side) sees more room, not bars. Props stay on the 1920 stage.
const BLEED := 160.0
const WIDE := Vector2(SIZE.x + 2.0 * BLEED, SIZE.y)  ## the painted room, from x = -BLEED
const FLOOR_Y := 905.0
const SAFE_AT := Vector2(960, 645)  ## the safe's centre (SafeCracker.BODY_HOME)
## The floor's vanishing point: boards and tiles converge on the safe.
const VP := Vector2(960, 560)

const PLACES := [
	{"id": "office", "name": "Night office", "wall": Color(0.1, 0.17, 0.22), "wall2": Color(0.06, 0.1, 0.14),
		"floor": Color(0.1, 0.08, 0.07), "safe": Color(0.34, 0.37, 0.4), "accent": Color(0.95, 0.75, 0.35),
		"light": {"at": Vector2(1665, 655), "color": Color(1.0, 0.78, 0.45), "radius": Vector2(640, 560), "strength": 0.3}},
	{"id": "bank", "name": "Bank vault", "wall": Color(0.36, 0.38, 0.41), "wall2": Color(0.24, 0.26, 0.29),
		"floor": Color(0.16, 0.16, 0.18), "safe": Color(0.5, 0.52, 0.55), "accent": Color(0.85, 0.65, 0.25),
		"light": {"at": Vector2(960, 26), "color": Color(0.82, 0.9, 1.0), "radius": Vector2(1150, 640), "strength": 0.22}},
	{"id": "museum", "name": "Museum hall", "wall": Color(0.62, 0.56, 0.46), "wall2": Color(0.5, 0.44, 0.36),
		"floor": Color(0.33, 0.25, 0.2), "safe": Color(0.25, 0.3, 0.36), "accent": Color(0.9, 0.8, 0.5),
		"light": {"at": Vector2(960, 0), "color": Color(1.0, 0.88, 0.66), "radius": Vector2(1000, 620), "strength": 0.2}},
	{"id": "cabin", "name": "Ship's cabin", "wall": Color(0.38, 0.25, 0.15), "wall2": Color(0.28, 0.18, 0.11),
		"floor": Color(0.2, 0.13, 0.09), "safe": Color(0.22, 0.3, 0.28), "accent": Color(0.9, 0.7, 0.3),
		"light": {"at": Vector2(1700, 420), "color": Color(1.0, 0.72, 0.38), "radius": Vector2(640, 580), "strength": 0.3}},
	# The lab's accent is a brass-teal, clear of the reading's on-target green (GameTheme.GOOD).
	{"id": "lab", "name": "Laboratory", "wall": Color(0.62, 0.74, 0.7), "wall2": Color(0.5, 0.62, 0.58),
		"floor": Color(0.3, 0.36, 0.36), "safe": Color(0.7, 0.72, 0.74), "accent": Color("4fb4c8"),
		"light": {"at": Vector2(960, 28), "color": Color(0.86, 1.0, 0.97), "radius": Vector2(1200, 640), "strength": 0.2}},
	{"id": "library", "name": "Old library", "wall": Color(0.3, 0.19, 0.14), "wall2": Color(0.2, 0.12, 0.09),
		"floor": Color(0.14, 0.09, 0.07), "safe": Color(0.28, 0.24, 0.3), "accent": Color(0.9, 0.72, 0.3),
		"light": {"at": Vector2(1520, 690), "color": Color(1.0, 0.74, 0.4), "radius": Vector2(600, 520), "strength": 0.32}},
]



static func count() -> int:
	return PLACES.size()


static func place(index: int) -> Dictionary:
	return PLACES[posmod(index, PLACES.size())]


## The index of a place by id, or -1.
static func index_of(id: String) -> int:
	for i in PLACES.size():
		if PLACES[i].id == id:
			return i
	return -1


## A random place that isn't `not_index` (so two safes in a row are never in the same place).
static func random_index(rng: RandomNumberGenerator, not_index := -1) -> int:
	var pick := rng.randi() % PLACES.size()
	if pick == not_index:
		pick = (pick + 1 + rng.randi() % (PLACES.size() - 1)) % PLACES.size()
	return pick


## The place's key light: {at, color, radius, strength}.
static func light(index: int) -> Dictionary:
	return place(index).light


## The unit direction from the safe toward the place's key light (the safe is shaded by it).
static func to_light(index: int) -> Vector2:
	return ((light(index).at as Vector2) - SAFE_AT).normalized()


## Steel lit from above and from the key light's side: an affine relight (exact on fans and
## bands), for `MeshBatch2D.shade`. `half` is the shape's half size, centred on the origin.
static func steel_shade(dir: Vector2, half: Vector2, light_col: Color) -> Callable:
	return func(p: Vector2, c: Color) -> Color:
		var n := Vector2(p.x / half.x, p.y / half.y)
		var top := -n.y
		var side := n.dot(dir)
		var f := 0.06 * top + 0.05 * side
		var warm := 0.05 * side
		return Color(c.r + f + light_col.r * warm, c.g + f + light_col.g * warm, c.b + f + light_col.b * warm, c.a)


## Adds the room to `m`: the wall, the key light's pool, the props, the floor in perspective.
## The safe covers the middle (x 470-1450), so the props sit to either side and behind it.
static func build_room(m: MeshBatch2D, index: int) -> void:
	var p := place(index)
	var wall: Color = p.wall
	var wall2: Color = p.wall2
	var l: Dictionary = p.light
	m.rect_v(Rect2(-BLEED, 0, WIDE.x, FLOOR_Y), wall, wall2)
	match str(p.id):
		"office":
			_office(m, p)
		"bank":
			_bank(m, p)
		"museum":
			_museum(m, p)
		"cabin":
			_cabin(m, p)
		"lab":
			_lab(m, p)
		"library":
			_library(m, p)
	# The baseboard, then the key light's pool over the wall and the props.
	m.rect_v(Rect2(-BLEED, FLOOR_Y - 22, WIDE.x, 22), wall2.darkened(0.35), wall2.darkened(0.5))
	m.rect(Rect2(-BLEED, FLOOR_Y - 22, WIDE.x, 2), Color(wall2.lightened(0.3), 0.6))
	var lc: Color = l.color
	m.glow(l.at, l.radius, Color(lc, l.strength), 16)
	m.glow(l.at, l.radius * 0.35, Color(lc, l.strength * 0.6), 10)
	match str(p.id):
		"office":
			_office_front(m, p)
		"library":
			_library_front(m, p)
	# The floor's own key-light pool, under the light.
	m.glow(Vector2((l.at as Vector2).x, FLOOR_Y + 70.0), Vector2((l.radius as Vector2).x * 0.9, 110.0), Color(lc, l.strength * 0.5), 10)
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, 10), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0.0))


## Where a floor line through `x` at the floor's back edge is at height `y` (one-point
## perspective toward VP).
static func floor_x(x: float, y: float) -> float:
	return VP.x + (x - VP.x) * (y - VP.y) / (FLOOR_Y - VP.y)


## Boards running toward the safe, `step` wide at the back edge, in tones of `base`.
static func _boards(m: MeshBatch2D, base: Color, step: float, vary: float, seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var x := -BLEED - step
	while x < SIZE.x + BLEED + step:
		var tone := base.lightened(rng.randf_range(0.0, vary)) if rng.randf() < 0.5 else base.darkened(rng.randf_range(0.0, vary))
		var a := Vector2(x, FLOOR_Y)
		var b := Vector2(x + step, FLOOR_Y)
		var c := Vector2(floor_x(x + step, SIZE.y), SIZE.y)
		var d := Vector2(floor_x(x, SIZE.y), SIZE.y)
		m.quad4(a, b, c, d, tone.lightened(0.08), tone.lightened(0.08), tone.darkened(0.25), tone.darkened(0.25))
		m.line(a, d, 2.0, Color(0, 0, 0, 0.35))
		x += step


## Checker tiles toward the safe: rows deeper in perspective, `step` wide at the back edge.
static func _tiles(m: MeshBatch2D, a_col: Color, b_col: Color, step: float) -> void:
	var rows := [FLOOR_Y]
	var k := 1
	while rows[-1] < SIZE.y:
		rows.append(VP.y + (FLOOR_Y - VP.y) / (1.0 - k * 0.13))
		k += 1
	for i in rows.size() - 1:
		var y0: float = rows[i]
		var y1: float = rows[i + 1]
		var j := 0
		var x := -BLEED - step * 2.0
		while x < SIZE.x + BLEED + step * 2.0:
			var col: Color = a_col if (i + j) % 2 == 0 else b_col
			m.quad4(Vector2(floor_x(x, y0), y0), Vector2(floor_x(x + step, y0), y0),
				Vector2(floor_x(x + step, y1), y1), Vector2(floor_x(x, y1), y1),
				col.lightened(0.05), col.lightened(0.05), col.darkened(0.15), col.darkened(0.15))
			x += step
			j += 1


## A picture frame: a moulding with a lit top and left, a dark inner lip.
static func _frame(m: MeshBatch2D, r: Rect2, wood: Color, w: float) -> void:
	m.soft_shadow(Rect2(r.position + Vector2(10, 14), r.size), 4.0, 18.0, Color(0, 0, 0, 0.35))
	m.rect(r, wood)
	m.bevel(r, 2.0, w * 0.45, Vector2(-0.4, -0.9).normalized(), wood.lightened(0.4), wood.darkened(0.5))
	m.rect(r.grow(-w), wood.darkened(0.6))


static func _office(m: MeshBatch2D, p: Dictionary) -> void:
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, SIZE.y - FLOOR_Y), (p.floor as Color).lightened(0.05), (p.floor as Color).darkened(0.3))
	_boards(m, p.floor, 70.0, 0.12, 3)
	# Moonlight through the blinds: soft slanted stripes from the window across the wall.
	for i in 7:
		var y := 318.0 + i * 46.0
		var a := Color(0.6, 0.72, 0.9, 0.07)
		m.quad4(Vector2(390, y), Vector2(1080, y + 190), Vector2(1080, y + 210), Vector2(390, y + 18), a, Color(a, 0.0), Color(a, 0.0), a)
	# The window (its glass and rain are SafeBackdrop's shader rect, inset 14).
	var win := Rect2(50, 300, 340, 420)
	m.soft_shadow(Rect2(win.position + Vector2(8, 12), win.size), 4.0, 16.0, Color(0, 0, 0, 0.4))
	m.rect(win, Color(0.33, 0.37, 0.42))
	m.bevel(win, 3.0, 6.0, Vector2(-0.5, -0.85), Color(0.55, 0.6, 0.66), Color(0.15, 0.17, 0.2))
	m.rect(win.grow(-14), Color(0.05, 0.08, 0.14))
	m.rect_v(Rect2(32, 718, 376, 18), Color(0.45, 0.48, 0.52), Color(0.22, 0.24, 0.27))
	# A framed certificate where the lamp catches it.
	_frame(m, Rect2(1525, 245, 170, 130), Color(0.32, 0.22, 0.14), 12.0)
	m.rect_v(Rect2(1537, 257, 146, 106), Color(0.86, 0.82, 0.7), Color(0.72, 0.68, 0.56))
	for k in 4:
		m.rect(Rect2(1560, 285 + k * 18, 100 - (k % 2) * 30, 4), Color(0.3, 0.27, 0.22, 0.6))


## The desk and its lamp, in front of the light's pool.
static func _office_front(m: MeshBatch2D, p: Dictionary) -> void:
	var wood := Color(0.24, 0.15, 0.1)
	m.quad4(Vector2(1490, 768), Vector2(SIZE.x + BLEED, 768), Vector2(SIZE.x + BLEED, 802), Vector2(1460, 802), wood.lightened(0.35), wood.lightened(0.2), wood.lightened(0.05), wood.lightened(0.1))
	m.rect_v(Rect2(1460, 802, 460 + BLEED, 103), wood, wood.darkened(0.45))
	m.rect(Rect2(1500, 830, 380, 2), Color(0, 0, 0, 0.4))
	m.circle(Vector2(1690, 852), 7.0, p.accent)
	var metal := Color(0.16, 0.16, 0.18)
	m.fill(MeshBatch2D._ellipse(Vector2(1640, 770), Vector2(46, 11), 24), metal.lightened(0.15))
	m.line(Vector2(1640, 765), Vector2(1600, 668), 8.0, metal)
	m.line(Vector2(1600, 668), Vector2(1652, 618), 8.0, metal)
	m.circle(Vector2(1600, 668), 7.0, metal.lightened(0.2))
	# The shade (the room's brass prop) and its hot mouth.
	var acc: Color = p.accent
	m.quad4(Vector2(1632, 594), Vector2(1688, 604), Vector2(1712, 660), Vector2(1608, 646), acc.lightened(0.25), acc, acc.darkened(0.35), acc.darkened(0.1))
	m.glow(Vector2(1662, 655), Vector2(70, 26), Color(1.0, 0.95, 0.75, 0.9), 8, 0.3)


static func _bank(m: MeshBatch2D, p: Dictionary) -> void:
	var wall: Color = p.wall
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, SIZE.y - FLOOR_Y), (p.floor as Color).lightened(0.08), (p.floor as Color).darkened(0.25))
	_tiles(m, (p.floor as Color).lightened(0.1), (p.floor as Color).darkened(0.1), 150.0)
	# Steel panels: seams, a lit lip under each, rivets along them.
	var dir := Vector2(0, -1)
	for x in range(-160, 2081, 160):
		m.line(Vector2(x, 0), Vector2(x, FLOOR_Y), 4.0, Color(0, 0, 0, 0.28))
		m.line(Vector2(x + 3, 0), Vector2(x + 3, FLOOR_Y), 1.5, Color(1, 1, 1, 0.08))
	m.line(Vector2(-BLEED, 450), Vector2(SIZE.x + BLEED, 450), 4.0, Color(0, 0, 0, 0.25))
	m.line(Vector2(-BLEED, 453), Vector2(SIZE.x + BLEED, 453), 1.5, Color(1, 1, 1, 0.08))
	for x in range(-160, 2081, 160):
		for y in [70.0, 380.0, 520.0, 830.0]:
			for dx in [14.0, -14.0]:
				if x + dx > -BLEED and x + dx < SIZE.x + BLEED:
					MeshBatch2D.rivet(m, Vector2(x + dx, y), 6.0, wall.lightened(0.15), dir)
	# The round vault door's rim on the wall behind the safe.
	var c := Vector2(960, 560)
	m.glow(c, Vector2(600, 600), Color(0, 0, 0, 0.3), 10, 0.75)
	MeshBatch2D.lit_ring(m, c, 470.0, 530.0, wall.lightened(0.3), wall.darkened(0.5), dir)
	MeshBatch2D.lit_ring(m, c, 455.0, 470.0, wall.darkened(0.6), wall.lightened(0.1), dir)
	for k in 20:
		var a := TAU * k / 20.0
		MeshBatch2D.rivet(m, c + Vector2(cos(a), sin(a)) * 500.0, 9.0, wall.lightened(0.1), dir)
	# Brass bars on the left: lit cylinders between two rails.
	var acc: Color = p.accent
	for i in 7:
		var x := 60.0 + i * 52.0
		m.rect_h(Rect2(x, 340, 11, 500), acc.darkened(0.55), acc.lightened(0.15))
		m.rect_h(Rect2(x + 11, 340, 11, 500), acc.lightened(0.15), acc.darkened(0.45))
	for y in [330.0, 828.0]:
		m.rect_v(Rect2(40, y, 380, 22), acc.lightened(0.3), acc.darkened(0.35))
	# Deposit boxes on the right.
	for row in 6:
		for col in 3:
			var r := Rect2(1530 + col * 120, 300 + row * 92, 112, 84)
			m.rect_v(r, wall.lightened(0.18), wall.darkened(0.1))
			m.bevel(r, 2.0, 3.0, dir, wall.lightened(0.45), wall.darkened(0.55))
			m.rect(Rect2(r.position.x + 36, r.position.y + 14, 40, 14), acc.darkened(0.2))
			m.circle(r.get_center() + Vector2(0, 14), 7.0, wall.darkened(0.45))
	# The overhead strip light.
	m.rect_v(Rect2(720, 10, 480, 26), Color(0.3, 0.32, 0.35), Color(0.18, 0.19, 0.21))
	m.rect_v(Rect2(740, 34, 440, 8), Color(0.95, 0.98, 1.0), Color(0.8, 0.88, 1.0))


static func _museum(m: MeshBatch2D, p: Dictionary) -> void:
	var wall2: Color = p.wall2
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, SIZE.y - FLOOR_Y), (p.floor as Color).lightened(0.05), (p.floor as Color).darkened(0.3))
	_boards(m, p.floor, 48.0, 0.1, 17)
	# Wainscot panels under a rail.
	m.rect_v(Rect2(-BLEED, 700, WIDE.x, FLOOR_Y - 700), wall2, wall2.darkened(0.2))
	m.rect_v(Rect2(-BLEED, 692, WIDE.x, 14), wall2.lightened(0.25), wall2.darkened(0.25))
	for x in range(-210, 2160, 240):
		m.bevel(Rect2(x, 730, 200, 145), 2.0, 3.0, Vector2(0, -1), wall2.darkened(0.3), wall2.lightened(0.2))
	# Two pictures under spotlights: a cone of light down each.
	var frames := [Rect2(70, 330, 300, 380), Rect2(1550, 330, 300, 380)]
	for i in 2:
		var r: Rect2 = frames[i]
		var fx := r.get_center().x
		var warm := Color(1.0, 0.9, 0.7, 0.16)
		m.quad4(Vector2(fx - 20, 250), Vector2(fx + 20, 250), Vector2(r.end.x + 40, r.end.y + 20), Vector2(r.position.x - 40, r.end.y + 20), warm, warm, Color(warm, 0.0), Color(warm, 0.0))
		_frame(m, r.grow(18), (p.accent as Color).darkened(0.3), 18.0)
		if i == 0:
			_landscape(m, r)
		else:
			_abstract(m, r)
		m.glow(Vector2(fx, r.position.y + 60), Vector2(260, 220), Color(1.0, 0.92, 0.75, 0.16), 10)
		# The fixture on its arm.
		m.line(Vector2(fx, 200), Vector2(fx, 236), 6.0, Color(0.15, 0.13, 0.12))
		m.quad4(Vector2(fx - 16, 232), Vector2(fx + 16, 232), Vector2(fx + 24, 258), Vector2(fx - 24, 258), Color(0.3, 0.27, 0.24), Color(0.3, 0.27, 0.24), Color(0.12, 0.1, 0.09), Color(0.12, 0.1, 0.09))
		m.glow(Vector2(fx, 258), Vector2(26, 9), Color(1, 0.96, 0.85, 0.9), 6, 0.3)
	# A vase on a marble pedestal, behind the right rope.
	m.rect_h(Rect2(1600, 770, 140, 135), Color(0.86, 0.84, 0.8), Color(0.62, 0.6, 0.56))
	m.rect_v(Rect2(1588, 758, 164, 16), Color(0.92, 0.9, 0.86), Color(0.7, 0.68, 0.64))
	m.fill(MeshBatch2D._ellipse(Vector2(1670, 706), Vector2(42, 52), 28), Color(0.5, 0.27, 0.18))
	m.rect_h(Rect2(1652, 638, 36, 22), Color(0.45, 0.24, 0.16), Color(0.6, 0.34, 0.22))
	m.fill(MeshBatch2D._ellipse(Vector2(1656, 690), Vector2(12, 26), 16), Color(1, 0.85, 0.7, 0.25))
	# Rope barriers on brass posts.
	_rope(m, Vector2(110, 790), Vector2(430, 790), p.accent)
	_rope(m, Vector2(1490, 790), Vector2(1830, 790), p.accent)


static func _landscape(m: MeshBatch2D, r: Rect2) -> void:
	m.rect_v(r, Color(0.55, 0.62, 0.7), Color(0.85, 0.72, 0.55))
	m.circle(Vector2(r.position.x + 200, r.position.y + 120), 34.0, Color(1.0, 0.88, 0.6))
	m.fill(PackedVector2Array([Vector2(r.position.x, r.position.y + 250), Vector2(r.position.x + 120, r.position.y + 190),
		Vector2(r.position.x + 230, r.position.y + 240), Vector2(r.end.x, r.position.y + 210), r.end, Vector2(r.position.x, r.end.y)]), Color(0.32, 0.4, 0.3), false)
	m.fill(PackedVector2Array([Vector2(r.position.x, r.position.y + 300), Vector2(r.end.x, r.position.y + 280), r.end, Vector2(r.position.x, r.end.y)]), Color(0.24, 0.3, 0.22), false)


static func _abstract(m: MeshBatch2D, r: Rect2) -> void:
	m.rect_v(r, Color(0.2, 0.3, 0.42), Color(0.12, 0.18, 0.28))
	m.circle(Vector2(r.position.x + 110, r.position.y + 140), 70.0, Color(0.85, 0.55, 0.3))
	m.rect(Rect2(r.position.x + 150, r.position.y + 180, 110, 150), Color(0.9, 0.85, 0.7))
	m.fill(PackedVector2Array([Vector2(r.position.x + 40, r.end.y - 30), Vector2(r.position.x + 150, r.position.y + 230), Vector2(r.position.x + 200, r.end.y - 30)]), Color(0.75, 0.3, 0.3))


## Two brass posts and a sagging red rope between them.
static func _rope(m: MeshBatch2D, a: Vector2, b: Vector2, brass: Color) -> void:
	var red := Color(0.55, 0.1, 0.12)
	var prev := a
	for k in range(1, 13):
		var t := k / 12.0
		var at := a.lerp(b, t) + Vector2(0, 46.0 * 4.0 * t * (1.0 - t))
		m.line(prev, at, 10.0, red)
		m.line(prev + Vector2(0, -3), at + Vector2(0, -3), 3.0, red.lightened(0.3))
		prev = at
	for x in [a.x, b.x]:
		m.glow(Vector2(x, FLOOR_Y + 8), Vector2(40, 9), Color(0, 0, 0, 0.5), 6)
		m.rect_h(Rect2(x - 6, a.y, 12, FLOOR_Y - a.y), brass.darkened(0.4), brass.lightened(0.2))
		m.fill(MeshBatch2D._ellipse(Vector2(x, FLOOR_Y - 2), Vector2(24, 7), 18), brass.darkened(0.3))
		m.circle(Vector2(x, a.y - 4), 12.0, brass)
		m.circle(Vector2(x - 3, a.y - 7), 4.0, brass.lightened(0.5))


static func _cabin(m: MeshBatch2D, p: Dictionary) -> void:
	var wall: Color = p.wall
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, SIZE.y - FLOOR_Y), (p.floor as Color).lightened(0.06), (p.floor as Color).darkened(0.3))
	_boards(m, p.floor, 90.0, 0.1, 29)
	# Timber planks, each its own tone, with a dark seam and a lit lip.
	var rng := RandomNumberGenerator.new()
	rng.seed = 23
	var y := 0.0
	while y < FLOOR_Y:
		var tone := Color(1, 1, 1, rng.randf_range(0.0, 0.05)) if rng.randf() < 0.5 else Color(0, 0, 0, rng.randf_range(0.0, 0.08))
		m.rect(Rect2(-BLEED, y, WIDE.x, 70), tone)
		m.rect(Rect2(-BLEED, y + 67, WIDE.x, 3), Color(0, 0, 0, 0.3))
		m.rect(Rect2(-BLEED, y + 70, WIDE.x, 1.5), Color(1, 1, 1, 0.06))
		y += 70.0
	# Ribs and the deck beam overhead.
	for x in [420.0, 1480.0]:
		m.rect_h(Rect2(x, 0, 60, FLOOR_Y), wall.darkened(0.35), wall.darkened(0.6))
		m.rect(Rect2(x, 0, 4, FLOOR_Y), Color(1, 1, 1, 0.06))
	m.rect_v(Rect2(-BLEED, 0, WIDE.x, 46), wall.darkened(0.45), wall.darkened(0.65))
	# The porthole: a brass ring with bolts (the sea is SafeBackdrop's shader).
	var c := Vector2(230, 520)
	var acc: Color = p.accent
	m.glow(c, Vector2(260, 260), Color(0.45, 0.65, 0.85, 0.12), 10)
	m.circle(c + Vector2(8, 12), 152.0, Color(0, 0, 0, 0.35))
	MeshBatch2D.lit_ring(m, c, 122.0, 152.0, acc.lightened(0.2), acc.darkened(0.55), Vector2(-0.5, -0.85))
	for k in 10:
		var a := TAU * k / 10.0 + 0.3
		MeshBatch2D.rivet(m, c + Vector2(cos(a), sin(a)) * 138.0, 6.0, acc.darkened(0.2), Vector2(-0.5, -0.85))
	# The lantern's wall bracket (the lantern swings, SafeBackdrop).
	var iron := Color(0.12, 0.1, 0.08)
	m.rect_v(Rect2(1688, 92, 24, 50), iron.lightened(0.15), iron)
	m.line(Vector2(1700, 120), Vector2(1700, 92), 6.0, iron)


static func _lab(m: MeshBatch2D, p: Dictionary) -> void:
	var wall: Color = p.wall
	var wall2: Color = p.wall2
	_tiles(m, Color(0.82, 0.86, 0.84), Color(0.3, 0.36, 0.36), 110.0)
	# Wall tiles under a band.
	m.rect_v(Rect2(-BLEED, 560, WIDE.x, FLOOR_Y - 560), wall2.lightened(0.15), wall2)
	for x in range(-180, 2101, 60):
		m.rect(Rect2(x, 560, 2, FLOOR_Y - 560), Color(1, 1, 1, 0.22))
	for yy in range(560, int(FLOOR_Y), 60):
		m.rect(Rect2(-BLEED, yy, WIDE.x, 2), Color(1, 1, 1, 0.22))
	m.rect_v(Rect2(-BLEED, 548, WIDE.x, 14), wall.darkened(0.2), wall.darkened(0.35))
	# Shelves on the left (the flasks' liquid is SafeBackdrop's shimmer layer).
	for shelf in 3:
		var y := 420.0 + shelf * 150.0
		m.rect_v(Rect2(60, y + 100, 340, 12), Color(0.5, 0.55, 0.55), Color(0.25, 0.3, 0.3))
		m.rect_v(Rect2(60, y + 112, 340, 10), Color(0, 0, 0, 0.25), Color(0, 0, 0, 0))
		for k in 4:
			var cx := 110.0 + k * 80.0
			m.circle(Vector2(cx, y + 72), 30.0, Color(0.9, 0.95, 0.95, 0.35))
			m.rect_h(Rect2(cx - 9, y + 22, 18, 30), Color(0.95, 1, 1, 0.5), Color(0.7, 0.8, 0.8, 0.4))
			m.rect(Rect2(cx - 12, y + 18, 24, 5), Color(0.85, 0.9, 0.9, 0.7))
	# A fume hood on the right: cabinet, a tinted sash with a reflection, a duct.
	var hood := Rect2(1500, 230, 390, 675)
	m.rect_v(Rect2(1660, 0, 90, 230), Color(0.78, 0.82, 0.82), Color(0.6, 0.65, 0.65))
	m.rect_h(hood, Color(0.86, 0.9, 0.9), Color(0.66, 0.7, 0.7))
	m.bevel(hood, 4.0, 5.0, Vector2(0, -1), Color(0.95, 1, 1), Color(0.4, 0.45, 0.45))
	var sash := Rect2(1530, 290, 330, 300)
	m.rect_v(sash, Color(0.2, 0.3, 0.32), Color(0.12, 0.18, 0.2))
	m.circle(Vector2(1650, 540), 34.0, Color(0.4, 0.75, 0.6, 0.7))
	m.rect(Rect2(1640, 470, 20, 40), Color(0.6, 0.75, 0.75, 0.6))
	m.line(Vector2(1720, 590), Vector2(1720, 450), 4.0, Color(0.5, 0.55, 0.55))
	m.quad(Vector2(1560, 290), Vector2(1620, 290), Vector2(1560, 410), Vector2(1530, 410), Color(1, 1, 1, 0.08))
	m.bevel(sash, 2.0, 6.0, Vector2(0, -1), Color(0.95, 1, 1), Color(0.45, 0.5, 0.5))
	m.rect_v(Rect2(1500, 600, 390, 16), Color(0.5, 0.55, 0.55), Color(0.35, 0.4, 0.4))
	for k in 2:
		m.bevel(Rect2(1525 + k * 175, 640, 165, 240), 3.0, 3.0, Vector2(0, -1), Color(0.95, 1, 1), Color(0.45, 0.5, 0.5))
	# The fluorescent fixture.
	m.rect_v(Rect2(700, 8, 520, 30), Color(0.78, 0.8, 0.8), Color(0.6, 0.62, 0.62))
	m.rect(Rect2(720, 36, 480, 7), Color(0.95, 1.0, 0.98))


static func _library(m: MeshBatch2D, p: Dictionary) -> void:
	var fl: Color = p.floor
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, SIZE.y - FLOOR_Y), fl.lightened(0.06), fl.darkened(0.3))
	_boards(m, fl, 60.0, 0.12, 41)
	# A rug under the safe.
	var rug := Color(0.4, 0.1, 0.1)
	var y0 := FLOOR_Y + 30.0
	m.quad(Vector2(floor_x(450, y0), y0), Vector2(floor_x(1470, y0), y0), Vector2(floor_x(1470, SIZE.y), SIZE.y), Vector2(floor_x(450, SIZE.y), SIZE.y), Color(0.75, 0.55, 0.3))
	m.quad(Vector2(floor_x(470, y0 + 8), y0 + 8), Vector2(floor_x(1450, y0 + 8), y0 + 8), Vector2(floor_x(1450, SIZE.y), SIZE.y), Vector2(floor_x(470, SIZE.y), SIZE.y), rug)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for side in [0, 1]:
		var x0 := 40.0 if side == 0 else 1580.0
		var w := 380.0 if side == 0 else 310.0
		m.soft_shadow(Rect2(x0 + 12, 268, w, 645), 4.0, 20.0, Color(0, 0, 0, 0.4))
		m.rect_h(Rect2(x0 - 14, 240, w + 28, 665), Color(0.24, 0.15, 0.1), Color(0.16, 0.1, 0.07))
		m.rect(Rect2(x0, 260, w, 645), Color(0.1, 0.06, 0.05))
		for shelf in 4:
			var y := 280.0 + shelf * 155.0
			var x := x0 + 12.0
			while x < x0 + w - 24.0:
				var bw := rng.randf_range(16, 30)
				var h := rng.randf_range(90, 130)
				var tone := rng.randf()
				var col := Color.from_hsv(rng.randf_range(0.0, 0.12) + (0.55 if tone > 0.7 else 0.0), 0.6, 0.35 + tone * 0.3)
				var lean := 0.0 if rng.randf() < 0.9 else 6.0
				m.quad4(Vector2(x + lean, y + 135 - h), Vector2(x + bw + lean, y + 135 - h), Vector2(x + bw, y + 135), Vector2(x, y + 135), col.lightened(0.1), col, col.darkened(0.3), col.darkened(0.2))
				m.rect(Rect2(x + 2, y + 150 - h, bw - 4, 3), Color(0.9, 0.75, 0.4, 0.35))
				x += bw + 2.0
			m.rect_v(Rect2(x0 - 6, y + 135, w + 12, 12), Color(0.36, 0.24, 0.14), Color(0.2, 0.13, 0.08))
		m.rect_v(Rect2(x0 - 22, 228, w + 44, 20), Color(0.34, 0.22, 0.14), Color(0.18, 0.11, 0.07))
	# The rolling ladder against the left shelves, on its rail.
	var wood := Color(0.42, 0.28, 0.16)
	m.rect_v(Rect2(30, 222, 400, 8), Color(0.75, 0.6, 0.3), Color(0.45, 0.32, 0.15))
	var a := Vector2(250, 226)
	var b := Vector2(330, 226)
	var c := Vector2(150, FLOOR_Y + 30)
	var d := Vector2(230, FLOOR_Y + 30)
	for k in range(1, 12):
		var t := k / 12.0
		m.line(a.lerp(c, t), b.lerp(d, t), 7.0, wood.darkened(0.15))
	m.line(a, c, 12.0, wood)
	m.line(b, d, 12.0, wood.darkened(0.1))
	m.line(a + Vector2(-3, 0), c + Vector2(-3, 0), 3.0, wood.lightened(0.3))


## The reading lamp's table and the lamp, in front of the light's pool.
static func _library_front(m: MeshBatch2D, p: Dictionary) -> void:
	var wood := Color(0.3, 0.18, 0.1)
	m.glow(Vector2(1520, FLOOR_Y + 6), Vector2(120, 14), Color(0, 0, 0, 0.5), 6)
	m.quad4(Vector2(1440, 780), Vector2(1600, 780), Vector2(1612, 800), Vector2(1428, 800), wood.lightened(0.4), wood.lightened(0.3), wood.lightened(0.1), wood.lightened(0.15))
	m.rect_v(Rect2(1428, 800, 184, 14), wood, wood.darkened(0.3))
	for x in [1440.0, 1590.0]:
		m.rect_h(Rect2(x, 814, 12, FLOOR_Y - 814), wood.darkened(0.2), wood.darkened(0.5))
	var brass: Color = p.accent
	m.fill(MeshBatch2D._ellipse(Vector2(1520, 778), Vector2(34, 8), 20), brass.darkened(0.3))
	m.rect_h(Rect2(1516, 696, 8, 82), brass.darkened(0.2), brass.lightened(0.2))
	# The shade (the room's brass prop): a dome with its warm mouth.
	var dome := MeshBatch2D.arc_points(Vector2(1520, 700), 60.0, PI, TAU, 16)
	dome.append(Vector2(1580, 700))
	m.fill(_squash(dome, Vector2(1520, 700), 0.6), brass, false)
	m.glow(Vector2(1520, 702), Vector2(62, 14), Color(1.0, 0.92, 0.7, 0.95), 8, 0.4)


static func _squash(points_in: PackedVector2Array, about: Vector2, sy: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for q in points_in:
		out.append(Vector2(q.x, about.y + (q.y - about.y) * sy))
	return out
