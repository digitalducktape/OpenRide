class_name PumpPlaces
extends RefCounted
## The places Balloon Pump's pump stands in (#76, the 2D rework; ART_BIBLE.md §3 and §6): a fair
## at dusk, backstage in a big top, and a pier at night. Each is a palette, one key light and a
## few shapes drawn in code into one `SafeMesh` batch (Safe Cracker's batcher, read only), baked
## once per place with the pump, its hose and stand (`PumpStage`). The slow ambient life (twinkling
## bulbs, the turning wheel, the sea, dust in the spotlight) is `PumpStage`'s, in shaders and
## tweens. Names are plain descriptions; nothing here refers to any existing fair, circus or pier.

const SIZE := Vector2(1920, 1080)
## The room is painted this far past each side of the stage (#57: the bike shows 68 px more each
## side). Props stay on the 1920 stage.
const BLEED := 160.0
const WIDE := Vector2(SIZE.x + 2.0 * BLEED, SIZE.y)
const FLOOR_Y := 880.0
const VP := Vector2(960, 600)  ## the floor's vanishing point

## The hero's layout (canvas pixels).
const PUMP_X := 800.0  ## the barrel's centre line
const BARREL := Rect2(715, 410, 170, 360)  ## the brass barrel
const PLINTH := Rect2(670, 790, 260, 92)  ## the painted base, its top face above it
const GAUGE_AT := Vector2(800, 585)
const GAUGE_R := 100.0
const COLLAR := Rect2(778, 338, 44, 34)  ## the plunger's collar on the dome
const NOZZLE := Vector2(1225, 772)  ## where the balloon's knot sits
const STAND_FOOT := Vector2(1225, 884)
const TETHER := Vector2(1600, 868)  ## the bunch's weight on the floor
const BASKET := Rect2(470, 820, 170, 80)  ## spare balloons, limp, at the pump's foot

const PLACES := [
	{"id": "fair", "name": "Fair at dusk",
		"sky_top": Color(0.07, 0.08, 0.2), "sky_mid": Color(0.2, 0.15, 0.32), "horizon": Color(0.78, 0.4, 0.34),
		"floor": Color(0.15, 0.17, 0.12), "accent": Color(1.0, 0.78, 0.36),
		"light": {"at": Vector2(1015, 360), "color": Color(1.0, 0.8, 0.52), "radius": Vector2(860, 720), "strength": 0.3}},
	{"id": "bigtop", "name": "Big top, backstage",
		"sky_top": Color(0.2, 0.03, 0.05), "sky_mid": Color(0.36, 0.06, 0.08), "horizon": Color(0.44, 0.1, 0.1),
		"floor": Color(0.42, 0.32, 0.22), "accent": Color(0.98, 0.78, 0.32),
		"light": {"at": Vector2(930, 0), "color": Color(1.0, 0.94, 0.8), "radius": Vector2(860, 1040), "strength": 0.3}},
	{"id": "pier", "name": "Pier at night",
		"sky_top": Color(0.02, 0.04, 0.1), "sky_mid": Color(0.05, 0.09, 0.18), "horizon": Color(0.18, 0.24, 0.36),
		"floor": Color(0.22, 0.16, 0.12), "accent": Color(1.0, 0.72, 0.36),
		"light": {"at": Vector2(1005, 420), "color": Color(1.0, 0.74, 0.44), "radius": Vector2(820, 640), "strength": 0.32}},
]

const SEA := Rect2(-160, 610, 2240, 140)  ## the pier's sea, a shader rect under the baked room
const MOON := Vector2(250, 330)
const FAIR_HORIZON := 700.0
## The Ferris wheel stands on the fair's horizon, far off: its lowest car clears the ground line,
## its top clears the ride panel (pump_layout_test).
const WHEEL_AT := Vector2(290, 514)
const WHEEL_R := 148.0
const WHEEL_CAR := Vector2(26, 20)  ## a car's size; it hangs this far below the rim, plus 4


static func count() -> int:
	return PLACES.size()


static func place(index: int) -> Dictionary:
	return PLACES[posmod(index, PLACES.size())]


static func light(index: int) -> Dictionary:
	return place(index).light


## A unit vector from `at` toward the place's key light.
static func to_light(index: int, at: Vector2) -> Vector2:
	return ((light(index).at as Vector2) - at).normalized()


## x on the floor at height y for a line through the vanishing point and (x0, FLOOR_Y).
static func floor_x(x0: float, y: float) -> float:
	return VP.x + (x0 - VP.x) * (y - VP.y) / (FLOOR_Y - VP.y)


## The whole room for place `index`, the pump and stand included, into `m` (stage coordinates;
## the bake shifts it by BLEED). Static: drawn once per place.
static func paint(m: SafeMesh, index: int) -> void:
	var p := place(index)
	match str(p.id):
		"fair":
			_fair(m, p)
		"bigtop":
			_bigtop(m, p)
		"pier":
			_pier(m, p)
	var l: Dictionary = p.light
	# The key light: a pool on the wall and a brighter one on the floor under it.
	m.glow(l.at, l.radius, Color(l.color, l.strength), 16, 0.05)
	var floor_at := Vector2((l.at as Vector2).x, FLOOR_Y + 60.0)
	m.glow(floor_at, Vector2(720, 150), Color(l.color, l.strength * 0.9), 12, 0.1)
	PumpArt.paint_machine(m, index)
	vignette(m)


## The soot vignette: the corners pulled in toward the hero.
static func vignette(m: SafeMesh) -> void:
	var c := Vector2(930, 600)
	var inner := SafeMesh._ellipse(c, Vector2(980, 600), 48)
	var outer := SafeMesh._ellipse(c, Vector2(1700, 1150), 48)
	m.band(inner, outer, Color(0.04, 0.02, 0.05, 0.0), Color(0.04, 0.02, 0.05, 0.75))


# --- The places ---

static func _sky(m: SafeMesh, p: Dictionary, horizon_y: float) -> void:
	m.rect_v(Rect2(-BLEED, 0, WIDE.x, horizon_y * 0.6), p.sky_top, p.sky_mid)
	m.rect_v(Rect2(-BLEED, horizon_y * 0.6, WIDE.x, horizon_y * 0.4 + 1.0), p.sky_mid, p.horizon)


static func _stars(m: SafeMesh, seed: int, count: int, max_y: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in count:
		var at := Vector2(rng.randf_range(-BLEED, SIZE.x + BLEED), rng.randf_range(10, max_y))
		m.circle(at, rng.randf_range(1.0, 2.2), Color(1, 0.96, 0.9, rng.randf_range(0.35, 0.8)))


static func _fair(m: SafeMesh, p: Dictionary) -> void:
	var horizon := FAIR_HORIZON
	_sky(m, p, horizon)
	_stars(m, 76, 40, 380)
	# The afterglow low on the horizon, and the far hills and tree line in silhouette.
	m.glow(Vector2(1300, horizon), Vector2(1400, 260), Color(1.0, 0.55, 0.38, 0.35), 12)
	var hills := PackedVector2Array()
	for k in 25:
		var x := -BLEED + k * WIDE.x / 24.0
		hills.append(Vector2(x, horizon - 40.0 - 26.0 * sin(k * 0.9) - 14.0 * sin(k * 2.3)))
	_ridge(m, hills, horizon + 20.0, Color(0.12, 0.09, 0.2))
	# Tents on the far side of the field: striped cones, their doorways lit.
	var tents := [[Vector2(1020, 705), 120.0, Color(0.5, 0.16, 0.28)], [Vector2(1560, 712), 150.0, Color(0.2, 0.22, 0.42)],
		[Vector2(1890, 700), 110.0, Color(0.46, 0.2, 0.18)], [Vector2(-60, 708), 120.0, Color(0.25, 0.18, 0.4)]]
	for t in tents:
		_tent(m, t[0], t[1], t[2], p.accent)
	# The wheel's stand (the wheel turns in its own layer).
	var hub := WHEEL_AT
	for side in [-1.0, 1.0]:
		m.line(hub, Vector2(hub.x + side * 110.0, horizon + 4.0), 10.0, Color(0.16, 0.12, 0.2))
	m.rect_v(Rect2(hub.x - 140, horizon - 2.0, 280, 12), Color(0.22, 0.16, 0.26), Color(0.1, 0.07, 0.12))
	# The field: dusky grass, a trodden patch where the pump stands, tufts.
	m.rect_v(Rect2(-BLEED, horizon, WIDE.x, SIZE.y - horizon), Color(0.13, 0.15, 0.13), (p.floor as Color).darkened(0.35))
	m.glow(Vector2(900, 930), Vector2(860, 120), Color(0.32, 0.26, 0.18, 0.55), 10)
	# A trodden path from the near field back between the tents, and straw scattered on it.
	var path := Color(0.3, 0.24, 0.17)
	m.quad4(Vector2(floor_x(760, horizon + 4), horizon + 4), Vector2(floor_x(1160, horizon + 4), horizon + 4),
		Vector2(floor_x(1160, SIZE.y), SIZE.y), Vector2(floor_x(760, SIZE.y), SIZE.y),
		Color(path, 0.0), Color(path, 0.0), Color(path, 0.75), Color(path, 0.75))
	var straw := RandomNumberGenerator.new()
	straw.seed = 17
	for i in 90:
		var y := straw.randf_range(horizon + 60, SIZE.y)
		var x := straw.randf_range(floor_x(760, y), floor_x(1160, y))
		var a := straw.randf_range(0.0, PI)
		var l := lerpf(3.0, 12.0, (y - horizon) / (SIZE.y - horizon))
		m.line(Vector2(x, y), Vector2(x, y) + Vector2(cos(a), sin(a) * 0.3) * l, 1.5, Color(0.78, 0.66, 0.38, 0.55))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	for i in 70:
		var at := Vector2(rng.randf_range(-BLEED, SIZE.x + BLEED), rng.randf_range(horizon + 20, SIZE.y))
		var h := lerpf(4.0, 16.0, (at.y - horizon) / (SIZE.y - horizon))
		m.line(at, at + Vector2(rng.randf_range(-3, 3), -h), 2.0, Color(0.2, 0.26, 0.16, 0.7))
	# The string lights' wires (their bulbs twinkle in their own layer).
	for wire in string_wires(0):
		_wire(m, wire, Color(0.05, 0.04, 0.06, 0.9))
	# A lamp pole carries the lantern that lights the pump.
	m.rect_h(Rect2(1009, 340, 12, FLOOR_Y - 340), Color(0.12, 0.1, 0.12), Color(0.26, 0.22, 0.24))
	_lantern(m, Vector2(1015, 330), p.accent)


static func _bigtop(m: SafeMesh, p: Dictionary) -> void:
	# Red velvet curtains in folds, a gold-fringed valance, a spotlight from the rigging.
	var red: Color = p.sky_mid
	m.rect_v(Rect2(-BLEED, 0, WIDE.x, FLOOR_Y), p.sky_top, p.horizon)
	var x := -BLEED
	var w := 70.0
	var k := 0
	while x < SIZE.x + BLEED:
		var lit := 0.55 + 0.45 * absf(sin(k * 1.7))
		m.rect_h(Rect2(x, 0, w * 0.5, FLOOR_Y), red.darkened(0.5), red.lightened(0.18 * lit))
		m.rect_h(Rect2(x + w * 0.5, 0, w * 0.5, FLOOR_Y), red.lightened(0.18 * lit), red.darkened(0.55))
		x += w
		k += 1
	m.rect_v(Rect2(-BLEED, 0, WIDE.x, 300), Color(0.08, 0.0, 0.02, 0.65), Color(0.08, 0.0, 0.02, 0.0))
	# The valance: scallops along a gold rail, with a fringe.
	var acc: Color = p.accent
	m.rect_v(Rect2(-BLEED, 250, WIDE.x, 22), acc.lightened(0.2), acc.darkened(0.4))
	var sx := -BLEED
	var s := 0
	while sx < SIZE.x + BLEED:
		var arc := PackedVector2Array([Vector2(sx, 272)])
		for i in 9:
			var a := PI * i / 8.0
			arc.append(Vector2(sx + 60.0 - cos(a) * 60.0, 272.0 + sin(a) * 42.0))
		m.fill(arc, red.lightened(0.05) if s % 2 == 0 else red.darkened(0.1))
		for i in 7:
			m.line(Vector2(sx + 15 + i * 15, 272 + sin(PI * (i + 1) / 8.0) * 42.0),
				Vector2(sx + 15 + i * 15, 290 + sin(PI * (i + 1) / 8.0) * 42.0), 3.0, acc.darkened(0.2))
		sx += 120.0
		s += 1
	# The sawdust floor and the ring's curb sweeping past in front.
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, SIZE.y - FLOOR_Y), (p.floor as Color).lightened(0.05), (p.floor as Color).darkened(0.4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	for i in 220:
		var at := Vector2(rng.randf_range(-BLEED, SIZE.x + BLEED), rng.randf_range(FLOOR_Y + 4, SIZE.y))
		m.rect(Rect2(at, Vector2(rng.randf_range(2, 5), 1.5)), Color(0.75, 0.6, 0.4, 0.25))
	var curb_out := PackedVector2Array()
	var curb_in := PackedVector2Array()
	for i in 33:
		var t := float(i) / 32.0
		var cx := lerpf(-BLEED, SIZE.x + BLEED, t)
		var cy := 1040.0 - 70.0 * sin(t * PI)
		curb_out.append(Vector2(cx, cy + 34.0))
		curb_in.append(Vector2(cx, cy))
	for i in 32:
		var col := Color(0.78, 0.16, 0.16) if i % 2 == 0 else Color(0.95, 0.9, 0.82)
		m.quad4(curb_in[i], curb_in[i + 1], curb_out[i + 1], curb_out[i], col.lightened(0.1), col.lightened(0.1), col.darkened(0.3), col.darkened(0.3))
	# A painted trunk and a drum stool in the wings.
	var trunk := Rect2(-40, 760, 230, 130)
	m.soft_shadow(trunk, 8.0, 20.0, Color(0, 0, 0, 0.45))
	m.round_rect(trunk, 8.0, Color(0.36, 0.18, 0.12), Color(0.2, 0.1, 0.07))
	for bx in [-20.0, 160.0]:
		m.rect_v(Rect2(bx, 760, 14, 130), acc.lightened(0.1), acc.darkened(0.45))
	m.rect_v(Rect2(-40, 806, 230, 10), acc.darkened(0.1), acc.darkened(0.5))
	# The spotlight's beam from the rigging (the floor pool is the key light's).
	var top := Vector2(930, -20)
	m.quad4(top + Vector2(-60, 0), top + Vector2(60, 0), Vector2(1520, FLOOR_Y + 60), Vector2(340, FLOOR_Y + 60),
		Color(1, 0.95, 0.82, 0.16), Color(1, 0.95, 0.82, 0.16), Color(1, 0.95, 0.82, 0.03), Color(1, 0.95, 0.82, 0.03))
	# Hanging ropes.
	for rx in [120.0, 1810.0]:
		m.line(Vector2(rx, 0), Vector2(rx + 10, 700), 5.0, Color(0.55, 0.45, 0.3, 0.8))


static func _pier(m: SafeMesh, p: Dictionary) -> void:
	var horizon := SEA.position.y
	_sky(m, p, horizon)
	_stars(m, 11, 90, 520)
	# The moon and its halo (the glitter on the sea is the sea shader's).
	m.glow(MOON, Vector2(260, 260), Color(0.7, 0.8, 1.0, 0.25), 12)
	m.circle(MOON, 48.0, Color(0.95, 0.95, 0.88))
	m.circle(MOON + Vector2(-12, -10), 10.0, Color(0.85, 0.85, 0.8))
	m.circle(MOON + Vector2(16, 12), 7.0, Color(0.86, 0.86, 0.8))
	# The far shore: a low dark line with a few lit windows.
	var shore := PackedVector2Array()
	for k in 25:
		shore.append(Vector2(-BLEED + k * WIDE.x / 24.0, horizon - 14.0 - 10.0 * absf(sin(k * 1.3))))
	_ridge(m, shore, horizon + 2.0, Color(0.04, 0.05, 0.1))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 26:
		m.circle(Vector2(rng.randf_range(600, 2000), horizon - rng.randf_range(4, 16)), 2.0, Color(1.0, 0.8, 0.5, 0.8))
	# The sea rect is left clear: the sea shader draws under the baked room there.
	# The pier's deck: planks running to the vanishing point.
	var deck := (p.floor as Color)
	m.rect_v(Rect2(-BLEED, 740, WIDE.x, FLOOR_Y - 740), deck.darkened(0.45), deck.darkened(0.1))
	m.rect_v(Rect2(-BLEED, FLOOR_Y, WIDE.x, SIZE.y - FLOOR_Y), deck.lightened(0.06), deck.darkened(0.45))
	var x := -BLEED - 120.0
	var i := 0
	while x < SIZE.x + BLEED + 120.0:
		var a := Vector2(floor_x(x, 740.0), 740.0)
		var d := Vector2(floor_x(x, SIZE.y), SIZE.y)
		m.line(a, d, 2.5, Color(0, 0, 0, 0.35))
		x += 120.0
		i += 1
	# The railing in front of the sea: posts, a top rail and two ropes.
	for k in 17:
		var px := -BLEED + k * 150.0
		m.rect_h(Rect2(px, 660, 18, 100), deck.darkened(0.2), deck.lightened(0.1))
	m.rect_v(Rect2(-BLEED, 650, WIDE.x, 14), deck.lightened(0.15), deck.darkened(0.3))
	for ry in [690.0, 722.0]:
		var rope := PackedVector2Array()
		for k in 33:
			var t := float(k) / 32.0
			rope.append(Vector2(lerpf(-BLEED, SIZE.x + BLEED, t), ry + 6.0 * absf(sin(t * PI * 16.0))))
		for k in 32:
			m.line(rope[k], rope[k + 1], 3.0, Color(0.6, 0.5, 0.36, 0.85))
	# A lantern on a post between the pump and the balloon.
	m.rect_h(Rect2(998, 420, 14, FLOOR_Y - 420), Color(0.12, 0.09, 0.08), Color(0.28, 0.2, 0.15))
	_lantern(m, Vector2(1005, 410), p.accent)
	# Bunting of little lamps along the railing (they twinkle in their own layer).


## A silhouette from a ridge line down to `bottom`.
static func _ridge(m: SafeMesh, ridge: PackedVector2Array, bottom: float, col: Color) -> void:
	for k in ridge.size() - 1:
		m.quad(ridge[k], ridge[k + 1], Vector2(ridge[k + 1].x, bottom), Vector2(ridge[k].x, bottom), col)


## A striped tent: a cone roof over a short drum, its doorway lit.
static func _tent(m: SafeMesh, foot: Vector2, w: float, col: Color, accent: Color) -> void:
	var h := w * 0.55
	var roof := w * 0.7
	for k in 6:
		var x0 := foot.x - w + k * (2.0 * w / 6.0)
		var x1 := x0 + 2.0 * w / 6.0
		var c := col if k % 2 == 0 else Color(0.85, 0.8, 0.72).darkened(0.45)
		m.quad(Vector2(x0, foot.y - h), Vector2(x1, foot.y - h), Vector2(x1, foot.y), Vector2(x0, foot.y), c.darkened(0.2))
		m.quad4(Vector2(foot.x, foot.y - h - roof), Vector2(foot.x, foot.y - h - roof), Vector2(x1, foot.y - h), Vector2(x0, foot.y - h),
			c, c, c.darkened(0.15), c.darkened(0.15))
	m.quad(Vector2(foot.x - w * 0.16, foot.y), Vector2(foot.x - w * 0.05, foot.y - h * 0.8), Vector2(foot.x + w * 0.05, foot.y - h * 0.8),
		Vector2(foot.x + w * 0.16, foot.y), Color(accent, 0.75))
	m.glow(Vector2(foot.x, foot.y - h * 0.3), Vector2(w * 0.5, h * 0.6), Color(accent, 0.25), 8)
	m.line(Vector2(foot.x, foot.y - h - roof), Vector2(foot.x, foot.y - h - roof - 26), 3.0, col.darkened(0.3))
	m.fill(PackedVector2Array([Vector2(foot.x, foot.y - h - roof - 26), Vector2(foot.x + 22, foot.y - h - roof - 20),
		Vector2(foot.x, foot.y - h - roof - 14)]), accent.darkened(0.2))


## A hanging lantern: a cap, a glass box glowing warm, a bracket.
static func _lantern(m: SafeMesh, at: Vector2, accent: Color) -> void:
	m.glow(at + Vector2(0, 30), Vector2(150, 150), Color(1.0, 0.85, 0.55, 0.45), 10, 0.2)
	m.rect_v(Rect2(at.x - 22, at.y + 10, 44, 46), Color(1.0, 0.95, 0.75), Color(1.0, 0.75, 0.4))
	m.rect(Rect2(at.x - 26, at.y + 6, 52, 6), Color(0.15, 0.12, 0.12))
	m.rect(Rect2(at.x - 26, at.y + 56, 52, 6), Color(0.15, 0.12, 0.12))
	m.fill(PackedVector2Array([at + Vector2(-28, 6), at + Vector2(0, -14), at + Vector2(28, 6)]), Color(0.18, 0.14, 0.14))
	for dx in [-22.0, 20.0]:
		m.rect(Rect2(at.x + dx, at.y + 10, 3, 46), Color(0.15, 0.12, 0.12))


## Whether a bulb at `at` would sit in front of the pump or a lamp (the bulbs draw above the bake,
## so these are left off: the wire runs behind).
static func behind_hero(at: Vector2) -> bool:
	if BARREL.grow_individual(14, 70, 14, 0).has_point(at):
		return true
	if at.distance_to(GAUGE_AT) < GAUGE_R + 30.0:
		return true
	return absf(at.x - 1010.0) < 34.0 and at.y > 300.0


## The string lights' wires for place `index`: polylines across the top of the view (their
## bulbs are `PumpStage`'s, on the same points). Empty where a place has none.
static func string_wires(index: int) -> Array:
	var id := str(place(index).id)
	var out := []
	if id == "fair":
		for run in [[Vector2(-BLEED, 330), Vector2(1015, 380), 60.0], [Vector2(1015, 380), Vector2(SIZE.x + BLEED, 320), 70.0],
				[Vector2(-BLEED, 470), Vector2(560, 610), 26.0]]:
			out.append(_catenary(run[0], run[1], run[2], 22))
	elif id == "bigtop":
		out.append(_catenary(Vector2(-BLEED, 320), Vector2(SIZE.x + BLEED, 320), 50.0, 40))
	elif id == "pier":
		out.append(_catenary(Vector2(-BLEED, 600), Vector2(SIZE.x + BLEED, 600), 18.0, 40))
	return out


static func _catenary(a: Vector2, b: Vector2, sag: float, n: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for k in n + 1:
		var t := float(k) / n
		pts.append(a.lerp(b, t) + Vector2(0, sag * 4.0 * t * (1.0 - t)))
	return pts


static func _wire(m: SafeMesh, pts: PackedVector2Array, col: Color) -> void:
	for k in pts.size() - 1:
		m.line(pts[k], pts[k + 1], 2.5, col)
