class_name KeepyPlaces
extends RefCounted
## The places Keepy Uppy's balloon flies in (#77, the 2D rework; ART_BIBLE.md §3 and §6): a
## summer meadow, seaside cliffs, a city rooftop at dusk and an autumn park. Each is a palette, a
## sun (its key light) and a few layers of shapes drawn in code into one `SafeMesh` batch, baked
## once per place by `KeepyBackdrop`; the slow ambient life (clouds, the sea's glitter, gulls,
## butterflies, lit windows, falling leaves) lives in `KeepyBackdrop` as shaders, particles and
## moving nodes. Names are plain descriptions. Layout constants here are shared by every layer.

const SIZE := Vector2(1920, 1080)
## The scene is painted this far past each side of the stage (#57: the bike's window shows 68 px
## more each side), as Safe Cracker's rooms are. Props stay on the 1920 stage.
const BLEED := 160.0
const WIDE := Vector2(SIZE.x + 2.0 * BLEED, SIZE.y)
const HORIZON_Y := 640.0  ## where the far land meets the sky
const GROUND_Y := 900.0  ## the near ground the fan stands on (its feet)
## The fan: its grille's centre (the top of the crate, seen from a little above) and size.
const FAN_AT := Vector2(960, 858)
const GRILLE := Vector2(150, 36)  ## the grille's half axes (an ellipse)
const CRATE_W := 340.0
const CRATE_H := 150.0
## The balloon's centre: BALLOON_LOW at h = 0 (resting on the grille), BALLOON_HIGH at h = 1.
const BALLOON_R := Vector2(80, 94)
const BALLOON_LOW := FAN_AT.y - BALLOON_R.y - 8.0
const BALLOON_HIGH := 340.0
## Steer: screen pixels a metre of the fan's rail (KeepyLogic's metres). The balloon is drawn
## no further than X_SHOWN metres either side, so it never reaches a HUD panel.
const PX_PER_M := 140.0
const X_SHOWN := 1.6
## The height pole beside the column, painted in the three bands.
const POLE_X := 1300.0
const POLE_TOP := 236.0

const PLACES := [
	{"id": "meadow", "name": "Summer meadow",
		"sky_top": Color("3f8fdc"), "sky_low": Color("c9e6f6"), "sun": Vector2(380, 150), "sun_col": Color(1.0, 0.95, 0.78),
		"far": Color("8fbf86"), "mid": Color("6aa859"), "near": Color("5d9e3f"), "near2": Color("3f7f2e"),
		"haze": Color("d6ebf2"), "accent": Color("f5d547"), "dark": Color("2c4f22")},
	{"id": "seaside", "name": "Seaside cliffs",
		"sky_top": Color("3c78c4"), "sky_low": Color("f7d7a6"), "sun": Vector2(1540, 330), "sun_col": Color(1.0, 0.86, 0.6),
		"far": Color("5f8fb4"), "mid": Color("8a9f6a"), "near": Color("7aa04c"), "near2": Color("546f34"),
		"haze": Color("f3dfc0"), "accent": Color("f2efe6"), "dark": Color("3b4a3a")},
	{"id": "rooftop", "name": "City rooftop at dusk",
		"sky_top": Color("2a2c66"), "sky_low": Color("f29b6b"), "sun": Vector2(560, 560), "sun_col": Color(1.0, 0.7, 0.45),
		"far": Color("4a4a7a"), "mid": Color("35355e"), "near": Color("5a4a48"), "near2": Color("3a302f"),
		"haze": Color("d9889a"), "accent": Color("ffcf7a"), "dark": Color("1c1a30")},
	{"id": "park", "name": "Autumn park",
		"sky_top": Color("5e9ad0"), "sky_low": Color("f4e2c4"), "sun": Vector2(1500, 190), "sun_col": Color(1.0, 0.88, 0.62),
		"far": Color("b9a173"), "mid": Color("9c7a3c"), "near": Color("7f8f3c"), "near2": Color("586a2a"),
		"haze": Color("efdcbc"), "accent": Color("e8833a"), "dark": Color("3a2e1c")},
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


## A random place that isn't `not_index`.
static func random_index(rng: RandomNumberGenerator, not_index := -1) -> int:
	var pick := rng.randi() % PLACES.size()
	if pick == not_index:
		pick = (pick + 1 + rng.randi() % (PLACES.size() - 1)) % PLACES.size()
	return pick


## The unit direction from the fan toward the place's sun (the fan and balloon are shaded by it).
static func to_sun(index: int) -> Vector2:
	return ((place(index).sun as Vector2) - FAN_AT).normalized()


## The balloon's centre on screen for a height `h` (0-1) and a rail offset `x_m` (metres).
static func balloon_at(h: float, x_m: float) -> Vector2:
	return Vector2(FAN_AT.x + clampf(x_m, -X_SHOWN, X_SHOWN) * PX_PER_M, lerpf(BALLOON_LOW, BALLOON_HIGH, clampf(h, 0.0, 1.0)))


## The pole's y for a band boundary at height `h`.
static func band_y(h: float) -> float:
	return lerpf(BALLOON_LOW, BALLOON_HIGH, h)


# --- Painting the place (baked once per place) ---

## Adds the whole scene behind the fan to `m`, in screen coordinates from x = -BLEED.
static func build_scene(m: SafeMesh, index: int) -> void:
	var p := place(index)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9100 + index
	var x0 := -BLEED
	var x1 := SIZE.x + BLEED
	# The sky: a three-stop gradient, and the sun with a wide, soft halo.
	var sky_mid: Color = (p.sky_top as Color).lerp(p.sky_low, 0.55)
	m.rect_v(Rect2(x0, 0, x1 - x0, HORIZON_Y * 0.55), p.sky_top, sky_mid)
	m.rect_v(Rect2(x0, HORIZON_Y * 0.55, x1 - x0, HORIZON_Y * 0.45 + 40), sky_mid, p.sky_low)
	var sun: Vector2 = p.sun
	var sc: Color = p.sun_col
	m.glow(sun, Vector2(760, 560), Color(sc, 0.38), 20)
	m.glow(sun, Vector2(220, 220), Color(sc, 0.55), 12)
	if p.id != "rooftop":
		m.circle(sun, 46.0, sc.lightened(0.3))
	else:
		# A low dusk sun, half behind the far towers.
		m.circle(sun, 62.0, sc)
	_high_clouds(m, p, rng)
	# The land under everything, so no ridge's dip ever shows the clear colour.
	m.rect_v(Rect2(x0, HORIZON_Y - 40, x1 - x0, SIZE.y - HORIZON_Y + 40), (p.far as Color).lerp(p.near, 0.6), p.near2)
	match p.id:
		"meadow":
			_meadow(m, p, rng)
		"seaside":
			_seaside(m, p, rng)
		"rooftop":
			_rooftop(m, p, rng)
		"park":
			_park(m, p, rng)
	# Mown stripes on the grass, in perspective toward the fan (GFX_POLISH item 4).
	if p.id != "rooftop":
		_stripes(m, HORIZON_Y + 170.0, Color((p.near as Color).lightened(0.25), 0.07))
	# Light falling on the ground round the fan, toward the sun (item 2).
	m.glow(FAN_AT + Vector2(((p.sun as Vector2).x - FAN_AT.x) * 0.15, 40), Vector2(640, 150), Color(sc, 0.2), 12)
	# Haze along the horizon, so the far land sits back (item 3).
	m.glow(Vector2(960, HORIZON_Y - 10), Vector2(1400, 70), Color(p.haze, 0.25), 8)


## Thin, wind-combed streaks of high cloud.
static func _high_clouds(m: SafeMesh, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var col := Color((p.sky_low as Color).lightened(0.4), 0.35)
	for i in 5:
		var y := rng.randf_range(70.0, 260.0)
		var x := rng.randf_range(-100.0, 1800.0)
		var w := rng.randf_range(280.0, 520.0)
		m.glow(Vector2(x + w * 0.5, y), Vector2(w * 0.5, 9.0), col, 6)


## A ridge across the scene: a smooth wavy top (sum of sines) filled down to `bottom`, shading
## from `top_col` to `low_col`, its top edge feathered.
static func ridge(m: SafeMesh, base_y: float, amp: float, freq: float, phase: float, top_col: Color, low_col: Color, bottom: float, step := 24.0) -> void:
	var prev := Vector2.ZERO
	var x := -BLEED
	var first := true
	while x <= SIZE.x + BLEED + step:
		var y := base_y - amp * (0.6 * sin(x * freq + phase) + 0.3 * sin(x * freq * 2.3 + phase * 1.7) + 0.1 * sin(x * freq * 5.1))
		var cur := Vector2(x, y)
		if not first:
			m.quad4(prev, cur, Vector2(cur.x, bottom), Vector2(prev.x, bottom), top_col, top_col, low_col, low_col)
			m.quad4(prev - Vector2(0, SafeMesh.FEATHER), cur - Vector2(0, SafeMesh.FEATHER), cur, prev,
				Color(top_col, 0.0), Color(top_col, 0.0), top_col, top_col)
		prev = cur
		first = false
		x += step


## A round-crowned tree: a trunk and three overlapping crowns, lit from the sun's side.
static func tree(m: SafeMesh, at: Vector2, size: float, leaf: Color, trunk: Color, sun_dir: Vector2) -> void:
	m.rect_v(Rect2(at.x - size * 0.07, at.y - size * 0.55, size * 0.14, size * 0.55), trunk, trunk.darkened(0.3))
	var crowns := [Vector2(0, -size * 0.85), Vector2(-size * 0.3, -size * 0.62), Vector2(size * 0.3, -size * 0.64)]
	for c in crowns:
		m.circle(at + c, size * 0.38, leaf.darkened(0.18))
	for c in crowns:
		m.circle(at + c + sun_dir * size * 0.06, size * 0.3, leaf)
	m.circle(at + crowns[0] + sun_dir * size * 0.14, size * 0.16, leaf.lightened(0.18))


## A soft, round cumulus (also drawn by the ambient clouds).
static func cumulus(m: SafeMesh, at: Vector2, w: float, top: Color, shade: Color) -> void:
	var puffs := [Vector2(-0.38, 0.1), Vector2(-0.14, -0.18), Vector2(0.12, -0.28), Vector2(0.36, -0.06), Vector2(0.0, 0.08)]
	var radii := [0.24, 0.3, 0.34, 0.26, 0.3]
	for i in puffs.size():
		m.circle(at + (puffs[i] as Vector2) * w + Vector2(0, w * 0.06), radii[i] * w, shade)
	for i in puffs.size():
		m.circle(at + (puffs[i] as Vector2) * w, radii[i] * w * 0.92, top)


## Foreground flowers and tufts along the bottom edge (in front of nothing: the fan's crate and
## the grass layer cover the middle).
static func _flowers(m: SafeMesh, rng: RandomNumberGenerator, from_y: float, colors: Array, n: int) -> void:
	for i in n:
		var at := Vector2(rng.randf_range(-BLEED, SIZE.x + BLEED), rng.randf_range(from_y, SIZE.y - 10.0))
		var c: Color = colors[rng.randi() % colors.size()]
		var r := lerpf(3.0, 7.0, (at.y - from_y) / (SIZE.y - from_y))
		m.circle(at, r, c)
		m.circle(at, r * 0.4, Color(1.0, 0.9, 0.4))


## Alternate lighter stripes from `from_y` to the bottom edge, converging on a point above the
## horizon (one-point perspective, as Safe Cracker's floors converge on the safe).
static func _stripes(m: SafeMesh, from_y: float, col: Color) -> void:
	var vp := Vector2(960, HORIZON_Y - 260)
	var w := 260.0
	for k in range(-9, 9):
		var b0 := Vector2(960 + k * w, SIZE.y)
		var b1 := Vector2(960 + (k + 0.5) * w, SIZE.y)
		var t := (from_y - vp.y) / (SIZE.y - vp.y)
		m.quad4(vp.lerp(b0, t), vp.lerp(b1, t), b1, b0, Color(col, 0.0), Color(col, 0.0), col, col)


static func _ground(m: SafeMesh, p: Dictionary, from_y: float) -> void:
	m.rect_v(Rect2(-BLEED, from_y, WIDE.x, SIZE.y - from_y), p.near, p.near2)


static func _meadow(m: SafeMesh, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var haze: Color = p.haze
	ridge(m, HORIZON_Y - 40, 46, 0.004, 1.2, (p.far as Color).lerp(haze, 0.45), (p.far as Color).lerp(haze, 0.25), HORIZON_Y + 60)
	ridge(m, HORIZON_Y + 10, 34, 0.006, 3.1, p.far, (p.mid as Color).lerp(p.far, 0.4), HORIZON_Y + 120)
	# Hedgerows and trees on the far hill, wide of the column.
	var hedge := (p.dark as Color).lightened(0.25)
	for row in [[HORIZON_Y + 40, -BLEED, 760.0], [HORIZON_Y + 52, 1160.0, SIZE.x + BLEED]]:
		var x: float = row[1]
		while x < row[2]:
			m.circle(Vector2(x, row[0]), rng.randf_range(16, 24), hedge)
			x += rng.randf_range(18, 30)
	var sun_dir := ((p.sun as Vector2) - Vector2(960, 600)).normalized()
	for t in [[Vector2(180, HORIZON_Y + 60), 150.0], [Vector2(320, HORIZON_Y + 70), 110.0], [Vector2(1620, HORIZON_Y + 64), 170.0],
			[Vector2(1770, HORIZON_Y + 76), 120.0], [Vector2(-60, HORIZON_Y + 80), 130.0]]:
		tree(m, t[0], t[1], (p.mid as Color).darkened(0.12), Color("5a4030"), sun_dir)
	ridge(m, HORIZON_Y + 120, 26, 0.0035, 0.4, p.mid, p.near, GROUND_Y + 20)
	_ground(m, p, GROUND_Y - 30)
	# A mown path curving toward the fan.
	m.quad4(Vector2(880, HORIZON_Y + 150), Vector2(1040, HORIZON_Y + 150), Vector2(1260, SIZE.y), Vector2(660, SIZE.y),
		Color((p.near as Color).lightened(0.12), 0.0), Color((p.near as Color).lightened(0.12), 0.0),
		Color((p.near as Color).lightened(0.16), 0.5), Color((p.near as Color).lightened(0.16), 0.5))
	_flowers(m, rng, HORIZON_Y + 140, [Color("f7f4e8"), Color("f5d547"), Color("b8a1e3"), Color("f2a5c0")], 150)


static func _seaside(m: SafeMesh, p: Dictionary, rng: RandomNumberGenerator) -> void:
	# The sea to the horizon (its glitter is KeepyBackdrop's shader), an island far out.
	var sea_top := Color("4f86b8")
	m.rect_v(Rect2(-BLEED, HORIZON_Y - 60, WIDE.x, 200), sea_top.lerp(p.haze, 0.35), Color("2f6a99"))
	m.glow(Vector2((p.sun as Vector2).x, HORIZON_Y - 50), Vector2(520, 40), Color(p.sun_col, 0.35), 8)
	m.glow(Vector2(420, HORIZON_Y - 62), Vector2(140, 22), Color(0.35, 0.5, 0.55, 0.9), 6)
	# The cliffs on the left with a lighthouse, the headland running in from the right.
	var cliff := Color("a58a6a")
	var outline := PackedVector2Array([Vector2(-BLEED, HORIZON_Y - 150), Vector2(120, HORIZON_Y - 170), Vector2(320, HORIZON_Y - 120),
		Vector2(470, HORIZON_Y + 40), Vector2(420, HORIZON_Y + 160), Vector2(-BLEED, HORIZON_Y + 160)])
	m.fill(outline, cliff)
	m.fill(PackedVector2Array([Vector2(-BLEED, HORIZON_Y - 150), Vector2(120, HORIZON_Y - 170), Vector2(320, HORIZON_Y - 120),
		Vector2(250, HORIZON_Y - 108), Vector2(-BLEED, HORIZON_Y - 128)]), Color("6f8f47"))
	for k in 6:
		var y := HORIZON_Y - 100 + k * 40.0
		m.line(Vector2(-BLEED, y), Vector2(360 - k * 10.0, y + 8), 3.0, cliff.darkened(0.2))
	# The lighthouse: a white tower with one dark band, a lamp room and a warm light.
	var lh := Vector2(140, HORIZON_Y - 168)
	m.quad(lh + Vector2(-26, 0), lh + Vector2(26, 0), lh + Vector2(18, -150), lh + Vector2(-18, -150), Color("f2efe6"))
	m.quad(lh + Vector2(-23, -50), lh + Vector2(23, -50), lh + Vector2(21, -80), lh + Vector2(-21, -80), Color("39506a"))
	m.rect(Rect2(lh.x - 22, lh.y - 172, 44, 22), Color("39506a"))
	m.glow(lh + Vector2(0, -160), Vector2(60, 40), Color(1.0, 0.9, 0.6, 0.6), 6)
	m.quad(lh + Vector2(-14, -172), lh + Vector2(14, -172), lh + Vector2(0, -192), lh + Vector2(0, -192), Color("39506a"))
	ridge(m, HORIZON_Y + 140, 40, 0.004, 2.2, p.near, p.near2, GROUND_Y + 10, 20)
	_ground(m, p, GROUND_Y - 20)
	# A wooden fence along the headland, posts and two rails.
	var wood := Color("8a6a48")
	for k in 9:
		var x := 1180.0 + k * 110.0
		m.rect_v(Rect2(x, HORIZON_Y + 110, 12, 70), wood.lightened(0.1), wood.darkened(0.3))
	m.line(Vector2(1160, HORIZON_Y + 128), Vector2(SIZE.x + BLEED, HORIZON_Y + 122), 6.0, wood)
	m.line(Vector2(1160, HORIZON_Y + 156), Vector2(SIZE.x + BLEED, HORIZON_Y + 150), 6.0, wood.darkened(0.1))
	_flowers(m, rng, HORIZON_Y + 170, [Color("f7f4e8"), Color("f2a5c0"), Color("f5d547")], 110)


static func _rooftop(m: SafeMesh, p: Dictionary, rng: RandomNumberGenerator) -> void:
	# Two rows of towers against the dusk; lit windows in the near row (they twinkle in a shader).
	var far: Color = p.far
	var x := -BLEED
	while x < SIZE.x + BLEED:
		var w := rng.randf_range(70, 150)
		var h := rng.randf_range(120, 300)
		m.rect_v(Rect2(x, HORIZON_Y - h, w - 6, h + 40), far.lerp(p.haze, 0.25), far)
		x += w
	x = -BLEED - 40
	var mid: Color = p.mid
	while x < SIZE.x + BLEED:
		var w := rng.randf_range(110, 210)
		var h := rng.randf_range(80, 230)
		var r := Rect2(x, HORIZON_Y + 20 - h, w - 10, h + 80)
		m.rect_v(r, mid, mid.darkened(0.25))
		var col := 0
		var wy := r.position.y + 18
		while wy < HORIZON_Y + 60:
			var wx := r.position.x + 12
			while wx < r.end.x - 20:
				if rng.randf() < 0.42:
					m.rect(Rect2(wx, wy, 12, 16), Color(p.accent, rng.randf_range(0.5, 0.95)))
				wx += 24
				col += 1
			wy += 30
		# A rooftop water tower now and then.
		if rng.randf() < 0.25:
			var t := Vector2(r.get_center().x, r.position.y)
			m.rect(Rect2(t.x - 22, t.y - 50, 44, 40), mid.darkened(0.35))
			m.quad(t + Vector2(-28, -50), t + Vector2(28, -50), t + Vector2(0, -74), t + Vector2(0, -74), mid.darkened(0.45))
			m.line(t + Vector2(-16, -10), t + Vector2(-20, 0), 4.0, mid.darkened(0.45))
			m.line(t + Vector2(16, -10), t + Vector2(20, 0), 4.0, mid.darkened(0.45))
		x += w
	# Our roof: a low parapet, then the deck in perspective, potted plants and a chimney.
	var deck: Color = p.near
	m.rect_v(Rect2(-BLEED, HORIZON_Y + 90, WIDE.x, 60), Color("6a5048"), Color("4a3834"))
	m.rect(Rect2(-BLEED, HORIZON_Y + 86, WIDE.x, 8), Color("8a6a5e"))
	m.rect_v(Rect2(-BLEED, HORIZON_Y + 150, WIDE.x, SIZE.y - HORIZON_Y - 150), deck, p.near2)
	var vp := Vector2(960, HORIZON_Y - 60)
	for k in range(-12, 13):
		var bx := 960.0 + k * 150.0
		var top := vp.lerp(Vector2(bx, SIZE.y), (HORIZON_Y + 150 - vp.y) / (SIZE.y - vp.y))
		m.line(top, Vector2(bx, SIZE.y), 2.0, Color(0, 0, 0, 0.18))
	var pot := Color("b0603a")
	for at in [Vector2(260, 1000), Vector2(420, 960), Vector2(1580, 980), Vector2(1730, 1020)]:
		m.quad(at + Vector2(-38, -50), at + Vector2(38, -50), at + Vector2(28, 0), at + Vector2(-28, 0), pot)
		m.rect(Rect2(at.x - 42, at.y - 58, 84, 10), pot.lightened(0.15))
		for k in 3:
			m.circle(at + Vector2(-22 + k * 22, -78 - (k % 2) * 16), 30.0, Color("4f7f3a").lightened(k * 0.06))
	var ch := Vector2(1490, HORIZON_Y + 92)
	m.rect_v(Rect2(ch.x, ch.y - 120, 70, 120), Color("8a5040"), Color("5e3428"))
	m.rect(Rect2(ch.x - 6, ch.y - 128, 82, 12), Color("6e3e30"))
	# A short string of warm bulbs from the chimney to a post.
	var a := ch + Vector2(35, -100)
	var b := Vector2(1880, HORIZON_Y + 60)
	var prev := a
	for k in range(1, 13):
		var t := k / 12.0
		var q := a.lerp(b, t) + Vector2(0, 40.0 * 4.0 * t * (1.0 - t))
		m.line(prev, q, 2.0, Color(0.1, 0.08, 0.1))
		m.glow(q + Vector2(0, 6), Vector2(16, 16), Color(1.0, 0.8, 0.45, 0.6), 4)
		m.circle(q + Vector2(0, 6), 4.5, Color(1.0, 0.9, 0.6))
		prev = q
	m.rect_v(Rect2(1876, HORIZON_Y + 50, 10, 110), Color("4a3834"), Color("2a201e"))


static func _park(m: SafeMesh, p: Dictionary, rng: RandomNumberGenerator) -> void:
	var haze: Color = p.haze
	ridge(m, HORIZON_Y - 10, 30, 0.005, 0.7, (p.far as Color).lerp(haze, 0.4), p.far, HORIZON_Y + 80)
	# Autumn trees in two rows, warm crowns in three colours.
	var leaves := [Color("d9792f"), Color("c9502c"), Color("e3a83a"), Color("9a7a2c")]
	var sun_dir := ((p.sun as Vector2) - Vector2(960, 600)).normalized()
	for row in 2:
		var y := HORIZON_Y + 40 + row * 60
		var x := -BLEED + rng.randf_range(0, 60)
		while x < SIZE.x + BLEED:
			if absf(x - 960) > 300 + row * 120:
				tree(m, Vector2(x, y), rng.randf_range(130, 190) + row * 50, leaves[rng.randi() % leaves.size()], Color("4a3424"), sun_dir)
			x += rng.randf_range(120, 200)
	ridge(m, HORIZON_Y + 150, 12, 0.003, 1.9, p.mid, p.near, GROUND_Y + 20)
	_ground(m, p, GROUND_Y - 40)
	# A gravel path, a lamp post and a bench.
	m.quad4(Vector2(-BLEED, HORIZON_Y + 210), Vector2(SIZE.x + BLEED, HORIZON_Y + 190), Vector2(SIZE.x + BLEED, HORIZON_Y + 240),
		Vector2(-BLEED, HORIZON_Y + 262), Color("d8c39a"), Color("d8c39a"), Color("b9a47a"), Color("b9a47a"))
	var iron := Color("2e2a26")
	var lamp := Vector2(1640, HORIZON_Y + 228)
	m.rect_v(Rect2(lamp.x - 6, lamp.y - 240, 12, 240), iron.lightened(0.15), iron)
	m.rect(Rect2(lamp.x - 20, lamp.y - 270, 40, 34), iron)
	m.rect(Rect2(lamp.x - 14, lamp.y - 264, 28, 24), Color(1.0, 0.9, 0.6))
	m.glow(lamp + Vector2(0, -252), Vector2(70, 60), Color(1.0, 0.85, 0.5, 0.35), 6)
	var bench := Vector2(330, HORIZON_Y + 228)
	m.rect_v(Rect2(bench.x - 90, bench.y - 46, 180, 12), Color("8a5a36"), Color("6e4628"))
	m.rect_v(Rect2(bench.x - 90, bench.y - 24, 180, 12), Color("8a5a36"), Color("6e4628"))
	for dx in [-80.0, 70.0]:
		m.rect(Rect2(bench.x + dx, bench.y - 46, 10, 50), iron)
	# Fallen leaves scattered on the grass.
	for i in 140:
		var at := Vector2(rng.randf_range(-BLEED, SIZE.x + BLEED), rng.randf_range(HORIZON_Y + 270, SIZE.y))
		var c: Color = leaves[rng.randi() % leaves.size()]
		var s := lerpf(3.0, 8.0, (at.y - HORIZON_Y) / (SIZE.y - HORIZON_Y))
		var ang := rng.randf() * TAU
		var d := Vector2(cos(ang), sin(ang)) * s
		m.quad(at - d, at + d.orthogonal() * 0.5, at + d, at - d.orthogonal() * 0.5, c)
