class_name LaunchPlaces
extends RefCounted
## The launch sites (#82, 2D like Safe Cracker; ART_BIBLE.md §4 and §6): a coastal pad at first
## light, desert flats at dusk and a polar shelf at night. Each is a palette and a few layers of
## shapes drawn in code into one `SafeMesh` batch, baked once per place by `LaunchBackdrop`. Layout
## constants here are shared by every layer. Props stay out from under the HUD's panels: nothing
## tall left of x 640 or right of x 1400 above y 310.

const SIZE := Vector2(1920, 1080)
## Painted this far past each side of the stage (#57: the bike's window shows 68 px more each side).
const BLEED := 160.0
const WIDE := Vector2(SIZE.x + 2.0 * BLEED, SIZE.y)
const HORIZON_Y := 700.0
const PAD_X := 960.0
const PAD_Y := 930.0  ## the launch table's deck: the rocket's engines stand on it
const TABLE_W := 560.0
const TOWER_X := 684.0  ## the service tower's centre

const PLACES := [
	{"id": "coast", "name": "Coast at first light",
		"sky_top": Color("24406f"), "sky_mid": Color("7f7fb4"), "sky_low": Color("f2ad8f"), "sky_edge": Color("ffdca6"),
		"flood": 0.1, "sun": Vector2(1490, 640), "sun_col": Color(1.0, 0.86, 0.62),
		"far": Color("6d6f9c"), "mid": Color("4f5a7c"), "near": Color("b39a84"), "near2": Color("5f5560"),
		"concrete": Color("9b93a0"), "concrete2": Color("5d5866"), "dark": Color("2a2a40"), "lit": Color("ffd08a"),
		"light": Color(1.0, 0.93, 0.86), "cloud": Color(1.0, 0.86, 0.8), "cloud2": Color("9a8fb8")},
	{"id": "desert", "name": "Desert flats at dusk",
		"sky_top": Color("231f52"), "sky_mid": Color("6d3372"), "sky_low": Color("e0653f"), "sky_edge": Color("ffb257"),
		"flood": 0.16, "sun": Vector2(1400, 655), "sun_col": Color(1.0, 0.7, 0.42),
		"far": Color("8a4a6a"), "mid": Color("6f3550"), "near": Color("a85f3e"), "near2": Color("55303a"),
		"concrete": Color("a2806f"), "concrete2": Color("5f4048"), "dark": Color("2a1730"), "lit": Color("ffc27a"),
		"light": Color(1.0, 0.83, 0.72), "cloud": Color(1.0, 0.72, 0.62), "cloud2": Color("8a4f7c")},
	{"id": "polar", "name": "Polar shelf at night",
		"sky_top": Color("050b22"), "sky_mid": Color("0c2748"), "sky_low": Color("1b5a70"), "sky_edge": Color("56a8a6"),
		"flood": 0.3, "sun": Vector2(1560, 720), "sun_col": Color(0.65, 0.95, 0.9),
		"far": Color("2a5a7a"), "mid": Color("1f4563"), "near": Color("a9c6dc"), "near2": Color("3f6488"),
		"concrete": Color("7f93a8"), "concrete2": Color("3f5168"), "dark": Color("0e1a30"), "lit": Color("ffe2a8"),
		"light": Color(0.82, 0.92, 1.0), "cloud": Color(0.72, 0.86, 0.95), "cloud2": Color("35587c")},
]


static func count() -> int:
	return PLACES.size()


static func place(index: int) -> Dictionary:
	return PLACES[posmod(index, PLACES.size())]


static func index_of(id: String) -> int:
	for i in PLACES.size():
		if PLACES[i].id == id:
			return i
	return -1


## The whole place, in stage coordinates (the bake shifts it by BLEED).
static func build_scene(m: SafeMesh, index: int) -> void:
	var p := place(index)
	_sky(m, p)
	match str(p.id):
		"coast":
			_coast(m, p)
		"desert":
			_desert(m, p)
		"polar":
			_polar(m, p)
	_apron(m, p)
	_pipes(m, p)
	_table(m, p)


static func _sky(m: SafeMesh, p: Dictionary) -> void:
	var l := -BLEED
	var w := WIDE.x
	m.rect_v(Rect2(l, 0, w, 300), p.sky_top, p.sky_mid)
	m.rect_v(Rect2(l, 300, w, 260), p.sky_mid, p.sky_low)
	m.rect_v(Rect2(l, 560, w, HORIZON_Y - 560.0 + 2.0), p.sky_low, p.sky_edge)
	# Thin high cloud, lit from under by the low sun (long flat bars, never a puff).
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 + str(p.id).length()
	for i in 12:
		var y := rng.randf_range(350.0, 600.0)
		var x := rng.randf_range(-100.0, 2000.0)
		var half := rng.randf_range(130.0, 340.0)
		var c: Color = (p.sun_col as Color).lerp(p.sky_low, 0.3)
		m.glow(Vector2(x, y), Vector2(half, rng.randf_range(5.0, 12.0)), Color(c, 0.34), 5)
	var sun: Vector2 = p.sun
	m.glow(sun, Vector2(620, 260), Color(p.sun_col, 0.5), 18)
	m.glow(sun, Vector2(190, 150), Color(p.sun_col, 0.6), 12)


## A rolling crest: a strip of quads down to `bottom`, shaded top to bottom.
static func _ridge(m: SafeMesh, y: float, swell: float, wave: float, phase: float, top: Color, under: Color, bottom: float) -> void:
	var x := -BLEED
	while x < SIZE.x + BLEED:
		var x2 := x + 24.0
		var y1 := y + sin(x * wave + phase) * swell + sin(x * wave * 2.7 + phase) * swell * 0.3
		var y2 := y + sin(x2 * wave + phase) * swell + sin(x2 * wave * 2.7 + phase) * swell * 0.3
		m.quad4(Vector2(x, y1), Vector2(x2, y2), Vector2(x2, bottom), Vector2(x, bottom), top, top, under, under)
		x = x2


static func _coast(m: SafeMesh, p: Dictionary) -> void:
	# The sea under the dawn, and a low headland far off at the left.
	m.rect_v(Rect2(-BLEED, HORIZON_Y - 18.0, WIDE.x, 110.0), Color("c9a0a6"), Color("4f6a8f"))
	m.glow(Vector2(p.sun.x, HORIZON_Y), Vector2(420, 34), Color(p.sun_col, 0.5), 8)
	_ridge(m, HORIZON_Y - 26.0, 8.0, 0.006, 1.0, p.far, (p.far as Color).lerp(p.sky_edge, 0.3), HORIZON_Y - 8.0)
	_buildings(m, 700.0, p)
	# The dunes and the shore's sand, in front of the sea.
	_ridge(m, 782.0, 10.0, 0.0052, 0.4, (p.near as Color).darkened(0.08), p.near, 1080.0)
	_ridge(m, 868.0, 14.0, 0.0034, 2.2, p.near, p.near2, 1080.0)


static func _desert(m: SafeMesh, p: Dictionary) -> void:
	# Mesas: flat-topped blocks with stepped shoulders, far then near.
	_mesa(m, -60.0, 420.0, 610.0, p.far, p)
	_mesa(m, 300.0, 240.0, 650.0, (p.far as Color).lerp(p.sky_low, 0.25), p)
	_mesa(m, 1500.0, 500.0, 590.0, p.far, p)
	_ridge(m, HORIZON_Y, 5.0, 0.008, 0.5, p.mid, (p.mid as Color).darkened(0.1), 800.0)
	_buildings(m, 720.0, p)
	_ridge(m, 780.0, 7.0, 0.0047, 3.0, (p.near as Color).lightened(0.06), p.near, 1080.0)
	_ridge(m, 880.0, 10.0, 0.003, 1.1, p.near, p.near2, 1080.0)
	# Long dusk shadows raking away from the sun.
	var rng := RandomNumberGenerator.new()
	rng.seed = 40
	for i in 26:
		var x := rng.randf_range(-100.0, 2000.0)
		var y := rng.randf_range(800.0, 1060.0)
		var r := rng.randf_range(10.0, 26.0)
		var rock: Color = (p.near2 as Color).darkened(0.25)
		m.quad(Vector2(x - r * 7.0, y + r * 0.5), Vector2(x - r, y), Vector2(x + r * 0.2, y + r * 0.45), Vector2(x - r * 6.0, y + r * 0.9), Color(p.dark, 0.32))
		m.fill(PackedVector2Array([Vector2(x - r, y + r * 0.3), Vector2(x - r * 0.5, y - r * 0.6), Vector2(x + r * 0.5, y - r * 0.5), Vector2(x + r, y + r * 0.3)]), rock)
		m.line(Vector2(x + r * 0.5, y - r * 0.5), Vector2(x + r, y + r * 0.3), 3.0, Color(p.lit, 0.5))


static func _polar(m: SafeMesh, p: Dictionary) -> void:
	# Ice cliffs on the horizon: faceted, pale at the top, floodlit from the pad's side.
	m.rect_v(Rect2(-BLEED, HORIZON_Y - 10.0, WIDE.x, 120.0), p.mid, (p.near2 as Color).lerp(p.mid, 0.5))
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	var x := -BLEED
	while x < SIZE.x + BLEED:
		var w := rng.randf_range(70.0, 170.0)
		var h := rng.randf_range(30.0, 130.0)
		var top: Color = (p.far as Color).lightened(rng.randf_range(0.0, 0.25))
		m.quad4(Vector2(x, HORIZON_Y + 20.0), Vector2(x + w * 0.2, HORIZON_Y - h), Vector2(x + w * 0.8, HORIZON_Y - h * 0.8),
			Vector2(x + w, HORIZON_Y + 20.0), p.mid, top, top, p.mid)
		x += w * 0.72
	_buildings(m, 720.0, p)
	_ridge(m, 776.0, 8.0, 0.006, 0.9, (p.near as Color).lightened(0.1), p.near, 1080.0)
	_ridge(m, 872.0, 12.0, 0.0031, 2.6, p.near, p.near2, 1080.0)
	m.glow(Vector2(PAD_X, 900.0), Vector2(860, 200), Color(p.lit, 0.26), 12)


## The site's far buildings, wide of the mission clock and the HUD: the assembly hall and water
## tower right of the rocket, a low control bunker left of it, the tracking dish at the far right.
static func _buildings(m: SafeMesh, base: float, p: Dictionary) -> void:
	_hangar(m, 1160.0, 250.0, 180.0, p)
	_tower_tank(m, 1490.0, base, p)
	_dish(m, 1700.0, base, p)
	_bunker(m, 210.0, base + 34.0, p)


## A low control bunker: a flat slab with a slit of lit windows.
static func _bunker(m: SafeMesh, x: float, base: float, p: Dictionary) -> void:
	var wall: Color = (p.mid as Color).lerp(p.dark, 0.2)
	m.quad(Vector2(x, base), Vector2(x + 36.0, base - 62.0), Vector2(x + 300.0, base - 62.0), Vector2(x + 336.0, base), wall)
	m.rect(Rect2(x + 30.0, base - 70.0, 276.0, 10.0), wall.lightened(0.2))
	for k in 6:
		m.rect(Rect2(x + 56.0 + k * 40.0, base - 46.0, 28.0, 10.0), Color(p.lit, 0.85))


## A flat-topped rock with one step in its shoulder, its sunward face lit.
static func _mesa(m: SafeMesh, x: float, w: float, top: float, col: Color, p: Dictionary) -> void:
	var base := HORIZON_Y + 10.0
	var shoulder := lerpf(top, base, 0.45)
	m.quad(Vector2(x, base), Vector2(x + w * 0.08, shoulder), Vector2(x + w * 0.92, shoulder), Vector2(x + w, base), col)
	m.quad(Vector2(x + w * 0.1, shoulder + 1.0), Vector2(x + w * 0.2, top), Vector2(x + w * 0.76, top), Vector2(x + w * 0.88, shoulder + 1.0), col)
	var lit: Color = (p.sun_col as Color).lerp(col, 0.45)
	m.quad(Vector2(x + w * 0.76, top), Vector2(x + w * 0.8, top), Vector2(x + w * 0.9, shoulder), Vector2(x + w * 0.88, shoulder), Color(lit, 0.7))
	m.quad(Vector2(x + w * 0.92, shoulder), Vector2(x + w * 0.96, shoulder), Vector2(x + w * 1.03, base), Vector2(x + w, base), Color(lit, 0.6))


## The assembly hall on the far side of the site: a big box with a tall door and lit windows.
static func _hangar(m: SafeMesh, x: float, w: float, h: float, p: Dictionary) -> void:
	var base := HORIZON_Y + 40.0
	var wall: Color = (p.mid as Color).lerp(p.dark, 0.25)
	var r := Rect2(x, base - h, w, h)
	m.rect_h(r, wall.darkened(0.2), wall.lightened(0.12))
	m.rect(Rect2(x - 6.0, base - h - 8.0, w + 12.0, 10.0), wall.lightened(0.2))
	m.rect_v(Rect2(x + w * 0.34, base - h + 24.0, w * 0.3, h - 24.0), (p.dark as Color).lightened(0.05), p.dark)
	for k in 5:
		m.line(Vector2(x + w * 0.34 + (k + 1) * w * 0.05, base - h + 24.0), Vector2(x + w * 0.34 + (k + 1) * w * 0.05, base), 2.0, Color(p.lit, 0.12))
	for row in 3:
		for col in 2:
			var wx := x + (18.0 if col == 0 else w - 54.0)
			m.rect(Rect2(wx, base - h + 36.0 + row * 42.0, 34.0, 18.0), Color(p.lit, 0.82))


## A water tower on four legs, its round tank capped by a cone.
static func _tower_tank(m: SafeMesh, x: float, base: float, p: Dictionary) -> void:
	var steel: Color = (p.mid as Color).lerp(p.dark, 0.4)
	for k in [-34.0, 34.0]:
		m.line(Vector2(x + k * 0.6, base - 110.0), Vector2(x + k, base + 16.0), 6.0, steel)
	m.line(Vector2(x - 28.0, base - 40.0), Vector2(x + 28.0, base - 40.0), 3.0, steel)
	m.line(Vector2(x - 24.0, base - 76.0), Vector2(x + 24.0, base - 76.0), 3.0, steel)
	var r := Rect2(x - 46.0, base - 168.0, 92.0, 60.0)
	m.round_rect(r, 10.0, steel.lightened(0.28), steel)
	m.fill(PackedVector2Array([Vector2(x - 50.0, base - 166.0), Vector2(x, base - 196.0), Vector2(x + 50.0, base - 166.0)]), steel.lightened(0.15))
	m.rect(Rect2(x - 46.0, base - 142.0, 92.0, 7.0), Color(p.lit, 0.42))


## A tracking dish on a pylon, tipped toward the rocket: a shallow fan of arcs, not a ball.
static func _dish(m: SafeMesh, x: float, base: float, p: Dictionary) -> void:
	var steel: Color = (p.mid as Color).lerp(p.dark, 0.3)
	m.fill(PackedVector2Array([Vector2(x - 44.0, base + 24.0), Vector2(x - 12.0, base - 80.0), Vector2(x + 12.0, base - 80.0), Vector2(x + 44.0, base + 24.0)]), steel)
	var at := Vector2(x, base - 110.0)
	var dish := SafeMesh.arc_points(at, 92.0, deg_to_rad(120.0), deg_to_rad(280.0), 14)
	var rim := SafeMesh.arc_points(at, 66.0, deg_to_rad(120.0), deg_to_rad(280.0), 14)
	m.band(dish, rim, steel.lightened(0.34), steel.lightened(0.08), false)
	m.line(dish[0], dish[14], 6.0, steel.lightened(0.42))
	var aim: Vector2 = (dish[0] + dish[14]) * 0.5
	m.line(aim, aim + Vector2(-58.0, -22.0), 4.0, steel.lightened(0.3))
	m.circle(aim + Vector2(-60.0, -23.0), 5.0, Color(p.lit, 0.9))


## The concrete apron: a trapezoid in one-point perspective toward the pad, its joints converging.
static func _apron(m: SafeMesh, p: Dictionary) -> void:
	var top := 846.0
	var bottom := 1080.0
	var a := Vector2(PAD_X - 460.0, top)
	var b := Vector2(PAD_X + 460.0, top)
	var c := Vector2(PAD_X + 980.0, bottom)
	var d := Vector2(PAD_X - 980.0, bottom)
	m.quad4(a, b, c, d, (p.concrete as Color), (p.concrete as Color).lightened(0.05), p.concrete2, p.concrete2)
	for k in range(-4, 5):
		var t := float(k) / 4.0
		m.line(Vector2(PAD_X + t * 460.0, top), Vector2(PAD_X + t * 980.0, bottom), 2.5, Color(p.dark, 0.25))
	for k in 5:
		var y := lerpf(top, bottom, pow(float(k + 1) / 5.5, 1.5))
		var half := lerpf(460.0, 980.0, (y - top) / (bottom - top))
		m.line(Vector2(PAD_X - half, y), Vector2(PAD_X + half, y), 2.5, Color(p.dark, 0.22))
	# Yellow safety lines and scorch round the table.
	var edge := Color("e8b84a")
	m.line(a + Vector2(10.0, 4.0), d + Vector2(40.0, -2.0), 6.0, Color(edge, 0.75))
	m.line(b + Vector2(-10.0, 4.0), c + Vector2(-40.0, -2.0), 6.0, Color(edge, 0.75))
	m.glow(Vector2(PAD_X, 985.0), Vector2(520, 76), Color(p.dark, 0.5), 10)
	# The key light across the concrete, from the sun's side.
	m.glow(Vector2(PAD_X + 240.0, 900.0), Vector2(620, 100), Color(p.sun_col, 0.2), 10)


## The fuel line along the ground from the tank farm at the right to the table.
static func _pipes(m: SafeMesh, p: Dictionary) -> void:
	var steel: Color = (p.concrete2 as Color).darkened(0.1)
	var y := 872.0
	# Two horizontal storage tanks, flat-ended, their ends lit.
	for k in 2:
		var r := Rect2(1486.0 + k * 40.0, 756.0 + k * 44.0, 300.0, 74.0)
		m.soft_shadow(Rect2(r.position + Vector2(-12.0, 54.0), Vector2(r.size.x + 20.0, 26.0)), 12.0, 16.0, Color(p.dark, 0.3))
		# Square-ended on saddles: a rounded pill lying down isn't a shape to leave to chance.
		for sx in [r.position.x + 40.0, r.end.x - 70.0]:
			m.rect(Rect2(sx, r.end.y - 4.0, 30.0, 14.0), steel.darkened(0.3))
		m.round_rect(r, 5.0, steel.lightened(0.42), steel.darkened(0.12))
		m.rect(Rect2(r.position.x, r.position.y, 10.0, r.size.y), Color(p.dark, 0.34))
		m.rect(Rect2(r.end.x - 10.0, r.position.y, 10.0, r.size.y), Color(p.dark, 0.34))
		m.rect(Rect2(r.position.x + 70.0, r.position.y + 28.0, 150.0, 12.0), Color("e8b84a"))
	m.rect_v(Rect2(1234.0, y, 300.0, 16.0), steel.lightened(0.34), steel.darkened(0.2))
	for k in 6:
		m.rect(Rect2(1250.0 + k * 50.0, y - 2.0, 8.0, 20.0), Color(p.dark, 0.6))


## The launch table: a steel deck on two piers, the flame trench dark between them, on the apron.
static func _table(m: SafeMesh, p: Dictionary) -> void:
	var w := TABLE_W
	var l := PAD_X - w * 0.5
	var steel := Color("565b6c").lerp(p.concrete2, 0.35)
	m.soft_shadow(Rect2(l - 40.0, PAD_Y + 90.0, w + 80.0, 40.0), 16.0, 30.0, Color(p.dark, 0.5))
	# The trench, then the piers either side of it.
	m.rect_v(Rect2(PAD_X - 170.0, PAD_Y + 30.0, 340.0, 100.0), Color("0c0c14"), Color("231a1a"))
	for s in [-1.0, 1.0]:
		var x: float = PAD_X + s * 225.0
		var r := Rect2(x - 56.0, PAD_Y + 28.0, 112.0, 104.0)
		m.rect_h(r, steel.darkened(0.25) if s < 0.0 else steel, steel.lightened(0.1) if s < 0.0 else steel.lightened(0.32))
		m.line(Vector2(r.position.x, r.position.y + 58.0), Vector2(r.end.x, r.position.y + 58.0), 3.0, Color(p.dark, 0.5))
		for k in 3:
			m.circle(Vector2(r.position.x + 22.0 + k * 34.0, r.position.y + 76.0), 4.0, Color(p.dark, 0.6))
	# The deck: bevelled plate with a hazard band along its front.
	var deck := Rect2(l, PAD_Y, w, 34.0)
	m.round_rect(deck, 6.0, steel.lightened(0.42), steel)
	m.bevel(deck, 6.0, 4.0, Vector2(0.6, -0.8), Color(1, 1, 1, 0.34), Color(0, 0, 0, 0.3))
	var stripe := 0.0
	var band_y := PAD_Y + 20.0
	while stripe < w - 8.0:
		var col := Color("e8b84a") if int(stripe / 28.0) % 2 == 0 else Color("23242e")
		m.quad(Vector2(l + stripe + 6.0, band_y + 10.0), Vector2(l + stripe + 12.0, band_y), Vector2(l + stripe + 40.0, band_y),
			Vector2(l + stripe + 34.0, band_y + 10.0), col)
		stripe += 28.0
	for k in 9:
		m.circle(Vector2(l + 30.0 + k * 62.5, PAD_Y + 9.0), 4.0, Color(p.dark, 0.7))
