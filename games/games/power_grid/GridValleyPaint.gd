class_name GridValleyPaint
extends RefCounted
## Power Grid's valley painter (#81; ART_BIBLE.md): everything that doesn't move, drawn into a
## `MeshBatch2D` for either palette, back to front (sky, far mountains, forested hills, the valley
## floor and the river, the stadium, the funfair, the houses, the road and its lamps, the pylons,
## the near hillside), plus the corner vignette and the big wheel's frame. The layout it paints
## (the road, the houses, the pylons and wires, every constant) is GridValley's; GridValley.paint,
## vignette and paint_wheel call in here.


## Everything that doesn't move, in the palette `night` (0 dusk, 1 night), stage coordinates.
static func paint(m: MeshBatch2D, night: int) -> void:
	var p := GridValley.palette(night)
	_sky(m, p)
	_mountains(m, p)
	_hills(m, p)
	_floor(m, p)
	_river(m, p)
	_stadium(m, p)
	_funfair(m, p)
	_town(m, p)
	_road(m, p)
	_pylons(m, p)
	_near(m, p)
	_river(m, p, 884.0)  # the lower river runs over the near land's edge


## The corners pulled in toward the town. Painted last, over the shed too.
static func vignette(m: MeshBatch2D, night: int) -> void:
	var col: Color = GridValley.PALETTE.vignette[night]
	var c := Vector2(1040, 640)
	var inner := MeshBatch2D._ellipse(c, Vector2(1050, 500), 48)
	var outer := MeshBatch2D._ellipse(c, Vector2(1900, 1160), 48)
	m.band(inner, outer, Color(col, 0.0), col)


# --- The sky ---


static func _sky(m: MeshBatch2D, p: Dictionary) -> void:
	m.rect_v(Rect2(GridValley.LEFT, 0, GridValley.WIDE.x, 230), p.sky_top, p.sky_mid)
	m.rect_v(Rect2(GridValley.LEFT, 230, GridValley.WIDE.x, 170), p.sky_mid, p.sky_low)
	m.rect_v(Rect2(GridValley.LEFT, 400, GridValley.WIDE.x, 190), p.sky_low, p.horizon)
	var sun: Color = p.sun
	m.glow(GridValley.SUN, Vector2(980, 300), Color(sun, sun.a * 0.55), 16)
	m.glow(GridValley.SUN, Vector2(360, 170), sun, 14, 0.12)
	# Long evening clouds, lit from below on the sun's side.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for i in 9:
		var at := Vector2(rng.randf_range(-100, 2000), rng.randf_range(250, 420))
		var w := rng.randf_range(160, 420)
		var h := rng.randf_range(7, 15)
		_streak(m, at, w, h, p.cloud, p.cloud_rim)


static func _streak(m: MeshBatch2D, at: Vector2, w: float, h: float, col: Color, rim: Color) -> void:
	m.glow(at, Vector2(w, h * 1.5), Color(col, 0.7), 8, 0.35)
	m.glow(at + Vector2(w * 0.15, h * 0.7), Vector2(w * 0.72, h * 0.6), rim, 6, 0.3)


# --- The land ---


## A ridge from sum-of-sines, top to `bottom`, shading from `top` to `low` down its face.
static func _ridge(m: MeshBatch2D, crest: PackedVector2Array, bottom: float, top: Color, low: Color) -> void:
	for k in crest.size() - 1:
		var a := crest[k]
		var b := crest[k + 1]
		m.quad4(a, b, Vector2(b.x, bottom), Vector2(a.x, bottom), top, top, low, low)


static func _mountains(m: MeshBatch2D, p: Dictionary) -> void:
	# The far range: a few real peaks, lit on the sun's side, with snow on the tallest.
	var peaks := [Vector2(GridValley.LEFT, 470), Vector2(40, 430), Vector2(230, 470), Vector2(470, 400), Vector2(690, 462), Vector2(900, 372), Vector2(1040, 436),
		Vector2(1160, 480), Vector2(1370, 402), Vector2(1560, 464), Vector2(1770, GridValley.RIDGE_TOP + 22.0), Vector2(1950, 448), Vector2(GridValley.RIGHT, 420)]
	var crest := PackedVector2Array()
	for k in peaks.size() - 1:
		var a: Vector2 = peaks[k]
		var b: Vector2 = peaks[k + 1]
		for s in 8:
			var t := s / 8.0
			var y := lerpf(a.y, b.y, t) + sin(t * 9.0 + k * 2.0) * 7.0 * sin(t * PI) + sin(t * 23.0 + k) * 2.5 * sin(t * PI)
			crest.append(Vector2(lerpf(a.x, b.x, t), y))
	crest.append(peaks[peaks.size() - 1])
	_ridge(m, crest, 590.0, p.far, p.far_low)
	for peak in [peaks[3], peaks[5], peaks[8], peaks[10]]:
		_snowcap(m, peak, p.snow, 46.0)
		# The peak's shaded flank, away from the sun.
		var side := -1.0 if peak.x < GridValley.SUN.x else 1.0
		m.quad4(peak, peak + Vector2(side * 130.0, 118.0), peak + Vector2(side * 40.0, 150.0), peak + Vector2(side * 6.0, 40.0),
			Color(p.mid, 0.0), Color(p.mid, 0.0), Color(p.mid, 0.34), Color(p.mid, 0.3))
	# The nearer range, in haze.
	var near := PackedVector2Array()
	var x := GridValley.LEFT
	while x <= GridValley.RIGHT + 20.0:
		near.append(Vector2(x, 508.0 - 30.0 * sin(x * 0.0031 + 1.0) - 16.0 * sin(x * 0.0087) - 6.0 * sin(x * 0.023)))
		x += 20.0
	_ridge(m, near, 600.0, p.mid, p.mid_low)


static func _snowcap(m: MeshBatch2D, peak: Vector2, col: Color, size: float) -> void:
	var s := PackedVector2Array([peak, peak + Vector2(size * 0.72, size * 0.74), peak + Vector2(size * 0.34, size * 0.52), peak + Vector2(size * 0.12, size * 0.8),
		peak + Vector2(-size * 0.2, size * 0.5), peak + Vector2(-size * 0.42, size * 0.76), peak + Vector2(-size * 0.74, size * 0.72)])
	# Convex pieces: a fan from the peak.
	for k in range(1, s.size() - 1):
		m.fill(PackedVector2Array([s[0], s[k], s[k + 1]]), Color(col, 0.82), false)


## The forested hills behind the town: a crest of tree tops, two depths.
static func _hills(m: MeshBatch2D, p: Dictionary) -> void:
	var crest := PackedVector2Array()
	var x := GridValley.LEFT
	while x <= GridValley.RIGHT + 16.0:
		crest.append(Vector2(x, _hill_y(x)))
		x += 16.0
	_ridge(m, crest, GridValley.FLOOR_Y + 40.0, p.hill, p.hill_low)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	# Trees along the crest and down the face, darker at the crest.
	for i in 520:
		var tx := rng.randf_range(GridValley.LEFT, GridValley.RIGHT)
		var top := _hill_y(tx)
		var ty := lerpf(top + 2.0, GridValley.FLOOR_Y + 8.0, pow(rng.randf(), 1.6))
		var r := lerpf(7.0, 12.0, clampf((ty - top) / 50.0, 0.0, 1.0)) * rng.randf_range(0.8, 1.25)
		m.circle(Vector2(tx, ty), r, p.tree, false)
		m.circle(Vector2(tx + r * 0.3, ty - r * 0.3), r * 0.55, Color(p.tree_hi, 0.5), false)


static func _hill_y(x: float) -> float:
	return 524.0 - 22.0 * sin(x * 0.0042 + 2.2) - 10.0 * sin(x * 0.011 + 0.4)


static func _floor(m: MeshBatch2D, p: Dictionary) -> void:
	m.rect_v(Rect2(GridValley.LEFT, GridValley.FLOOR_Y, GridValley.WIDE.x, GridValley.SIZE.y - GridValley.FLOOR_Y), p.floor, p.floor_low)
	# Fields in perspective: strips of two tints running across the valley, hedged.
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	var y := GridValley.FLOOR_Y + 2.0
	while y < 880.0:
		var h := lerpf(8.0, 52.0, (y - GridValley.FLOOR_Y) / 320.0)
		var xx := GridValley.LEFT - rng.randf_range(0, 200)
		while xx < GridValley.RIGHT:
			var w := rng.randf_range(160, 420) * lerpf(0.7, 1.6, (y - GridValley.FLOOR_Y) / 320.0)
			var tint: Color = p.field_a if rng.randf() < 0.45 else p.field_b
			var lean := rng.randf_range(-24.0, 24.0)
			m.quad(Vector2(xx + lean, y), Vector2(xx + w + lean, y), Vector2(xx + w, y + h), Vector2(xx, y + h), Color(tint, tint.a * rng.randf_range(0.2, 0.8)))
			if rng.randf() < 0.6:
				m.line(Vector2(xx + w + lean, y), Vector2(xx + w, y + h), 2.0, Color(p.hedge, 0.45))
			xx += w
		y += h
	# Hedgerow trees dotted along the field lines, right of the river especially.
	for copse in 11:
		var c := Vector2(rng.randf_range(1370, GridValley.RIGHT), rng.randf_range(GridValley.FLOOR_Y + 10.0, 660.0))
		for i in 6:
			var at := c + Vector2(rng.randf_range(-34, 34), rng.randf_range(-7, 7))
			var r := lerpf(5.0, 11.0, (at.y - GridValley.FLOOR_Y) / 110.0) * rng.randf_range(0.8, 1.2)
			m.circle(at, r, Color(p.tree, 0.9), false)
			m.circle(at + Vector2(r * 0.3, -r * 0.3), r * 0.5, Color(p.tree_hi, 0.4), false)


static func _river(m: MeshBatch2D, p: Dictionary, from_y := 0.0) -> void:
	var edges := GridValley.river_edges()
	var left: PackedVector2Array = edges[0]
	var right: PackedVector2Array = edges[1]
	var y0 := left[0].y
	var y1 := left[left.size() - 1].y
	for k in left.size() - 1:
		if left[k].y < from_y:
			continue
		var ca: Color = (p.river_far as Color).lerp(p.river_near, pow(inverse_lerp(y0, y1, left[k].y), 0.6))
		var cb: Color = (p.river_far as Color).lerp(p.river_near, pow(inverse_lerp(y0, y1, left[k + 1].y), 0.6))
		var bank := Vector2(lerpf(1.5, 7.0, inverse_lerp(y0, y1, left[k].y)), 0)
		m.quad4(left[k] - bank, right[k] + bank, right[k + 1] + bank, left[k + 1] - bank, p.river_bank, p.river_bank, p.river_bank, p.river_bank)
		m.quad4(left[k], right[k], right[k + 1], left[k + 1], ca, ca, cb, cb)


static func _stadium(m: MeshBatch2D, p: Dictionary) -> void:
	var c := GridValley.STADIUM_AT
	var r := GridValley.STADIUM_R
	m.glow(c + Vector2(0, r.y + 6.0), Vector2(r.x * 1.1, 16.0), Color(0, 0, 0, 0.32), 6)
	# The outer wall, the stands stepping down, the pitch.
	var wall := MeshBatch2D._ellipse(c + Vector2(0, 12), r, 56)
	m.fill(wall, p.stand_lo)
	m.fill(MeshBatch2D._ellipse(c, r, 56), p.stand)
	# Tiers: rings of slightly different value, with aisles.
	for k in 5:
		var t := float(k) / 5.0
		var ring := r * lerpf(1.0, 0.68, t)
		var inner := r * lerpf(1.0, 0.68, t + 0.2)
		m.band(MeshBatch2D._ellipse(c, inner, 56), MeshBatch2D._ellipse(c, ring, 56), Color(p.stand_lo, 0.5 if k % 2 == 0 else 0.15), Color(p.stand_lo, 0.5 if k % 2 == 0 else 0.15))
	for k in 20:
		var a := TAU * k / 20.0
		m.line(c + Vector2(cos(a), sin(a)) * r * 0.68, c + Vector2(cos(a), sin(a)) * r * 0.98, 1.5, Color(p.stand_lo, 0.6))
	var pitch := r * 0.66
	m.fill(MeshBatch2D._ellipse(c, pitch, 48), p.pitch)
	for k in 8:
		if k % 2 == 0:
			var x0 := c.x - pitch.x * 0.8 + k * pitch.x * 0.2
			var hh := pitch.y * 0.82
			m.quad(Vector2(x0 + 4, c.y - hh), Vector2(x0 + pitch.x * 0.2 + 4, c.y - hh), Vector2(x0 + pitch.x * 0.2 - 4, c.y + hh), Vector2(x0 - 4, c.y + hh), Color(p.pitch_alt, 0.8))
	var field := Vector2(pitch.x * 0.76, pitch.y * 0.72)
	m.line(c + Vector2(-field.x, -field.y), c + Vector2(field.x, -field.y), 1.5, p.line)
	m.line(c + Vector2(-field.x - 6, field.y), c + Vector2(field.x + 6, field.y), 1.5, p.line)
	m.line(c + Vector2(-field.x, -field.y), c + Vector2(-field.x - 6, field.y), 1.5, p.line)
	m.line(c + Vector2(field.x, -field.y), c + Vector2(field.x + 6, field.y), 1.5, p.line)
	m.line(c + Vector2(0, -field.y), c + Vector2(0, field.y), 1.5, p.line)
	m.ring(c, 12.0, 13.5, p.line)
	# The floodlight masts, each with its bank of lamps.
	for at in GridValley.MASTS:
		var top: Vector2 = at + Vector2(0, -GridValley.MAST_H)
		m.line(at, top, 4.0, p.steel)
		m.line(at + Vector2(-5, 0), top + Vector2(0, 30), 2.0, p.steel)
		m.line(at + Vector2(5, 0), top + Vector2(0, 30), 2.0, p.steel)
		m.round_rect(Rect2(top + Vector2(-17, -11), Vector2(34, 18)), 2.0, p.steel_hi, p.steel)


static func _funfair(m: MeshBatch2D, p: Dictionary) -> void:
	# The yard, then the wheel's stand (the wheel itself turns in its own layer).
	var yard := PackedVector2Array([Vector2(976, 740), Vector2(1296, 740), Vector2(1300, 850), Vector2(960, 852)])
	m.fill(yard, Color(p.yard, 0.75))
	var hub := GridValley.WHEEL_AT
	var foot_y := hub.y + GridValley.WHEEL_R + 22.0
	for side in [-1.0, 1.0]:
		m.line(hub, Vector2(hub.x + side * 70.0, foot_y), 8.0, p.steel)
		m.line(hub + Vector2(side * 36.0, 70.0), hub + Vector2(-side * 36.0, 70.0), 3.0, p.steel)
	m.round_rect(Rect2(hub.x - 88, foot_y - 3, 176, 10), 3.0, p.steel_hi, p.steel)
	for t in GridValley.TENTS:
		_tent(m, t[0], t[1], p, int(t[2]))
	_carousel(m, p)
	# Stalls along the road side of the yard: striped awnings.
	for k in 4:
		var at := GridValley.stall_at(k)
		m.rect(Rect2(at + Vector2(-20, -18), Vector2(40, 20)), p.stone_dark)
		for s in 4:
			m.quad(at + Vector2(-24 + s * 12, -32), at + Vector2(-12 + s * 12, -32), at + Vector2(-11 + s * 12, -17), at + Vector2(-25 + s * 12, -17),
				p.tent_a if s % 2 == 0 else p.tent_b)


## A striped tent: a pointed roof over a short drum.
static func _tent(m: MeshBatch2D, foot: Vector2, w: float, p: Dictionary, style: int) -> void:
	var h := w * 0.6
	var roof := w * 0.86
	var a: Color = p.tent_a if style == 0 else p.tent_c
	var b: Color = p.tent_b
	m.rect_v(Rect2(foot.x - w, foot.y - h, 2.0 * w, h), (b as Color).darkened(0.12), (b as Color).darkened(0.34))
	var apex := foot + Vector2(0, -h - roof)
	for k in 6:
		var x0 := foot.x - w - 4.0 + k * ((2.0 * w + 8.0) / 6.0)
		var x1 := x0 + (2.0 * w + 8.0) / 6.0
		m.fill(PackedVector2Array([apex, Vector2(x1, foot.y - h), Vector2(x0, foot.y - h)]), a if k % 2 == 0 else b, false)
	m.fill(PackedVector2Array([apex, Vector2(foot.x + w + 4.0, foot.y - h), foot + Vector2(0, -h - roof * 0.12)]), Color(0, 0, 0, 0.14), false)
	m.line(apex, apex + Vector2(0, -9), 2.0, p.steel)
	m.fill(PackedVector2Array([apex + Vector2(0, -9), apex + Vector2(12, -6), apex + Vector2(0, -3)]), a, false)
	m.round_rect(Rect2(foot.x - w * 0.24, foot.y - h * 0.8, w * 0.48, h * 0.8), 3.0, p.glass)


static func _carousel(m: MeshBatch2D, p: Dictionary) -> void:
	var c := GridValley.CAROUSEL_AT
	m.fill(MeshBatch2D._ellipse(c + Vector2(0, 8), Vector2(58, 13), 28), p.stone_dark)
	m.fill(MeshBatch2D._ellipse(c + Vector2(0, 3), Vector2(55, 12), 28), p.stone)
	for k in 8:
		var x := c.x - 49.0 + k * 14.0
		m.line(Vector2(x, c.y - 42), Vector2(x, c.y + 5), 2.0, p.steel_hi)
	m.rect_v(Rect2(c.x - 50, c.y - 44, 100, 42), Color(p.glass, 0.7), Color(p.glass, 0.9))
	var apex := c + Vector2(0, -76)
	for k in 8:
		var x0 := c.x - 58.0 + k * 14.5
		m.fill(PackedVector2Array([apex, Vector2(x0 + 14.5, c.y - 44), Vector2(x0, c.y - 44)]), p.tent_a if k % 2 == 0 else p.tent_b, false)
	m.rect_v(Rect2(c.x - 60, c.y - 48, 120, 9), p.tent_b, (p.tent_b as Color).darkened(0.3))
	m.line(apex, apex + Vector2(0, -11), 2.0, p.steel)


static func _town(m: MeshBatch2D, p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var drawn_church := false
	for h in GridValley.houses():
		if not drawn_church and (h.at as Vector2).y >= GridValley.CHURCH_AT.y:
			_church(m, p)
			drawn_church = true
		if rng.randf() < 0.32:
			var tx: float = (h.at as Vector2).x + float(h.w) * 0.72
			var ty: float = (h.at as Vector2).y - 3.0
			var r: float = float(h.w) * 0.32
			m.circle(Vector2(tx, ty - r), r, p.tree, false)
			m.circle(Vector2(tx + r * 0.3, ty - r * 1.3), r * 0.55, Color(p.tree_hi, 0.55), false)
		_house(m, h, p)


static func _house(m: MeshBatch2D, h: Dictionary, p: Dictionary) -> void:
	var at: Vector2 = h.at
	var w: float = h.w
	var ht: float = h.h
	var roof: float = h.roof
	var wall: Color = p[h.wall]
	var shade: Color = p.wall_shade
	var tile: Color = p[h.tile]
	var hi: Color = p.roof_hi
	m.glow(at + Vector2(w * 0.08, 1), Vector2(w * 0.68, 5.0), Color(0, 0, 0, 0.28), 4)
	# Sun from the right: the wall is lit toward it.
	m.quad4(at + Vector2(-w * 0.5, -ht), at + Vector2(w * 0.5, -ht), at + Vector2(w * 0.5, 0), at + Vector2(-w * 0.5, 0),
		wall.lerp(shade, 0.35), wall, wall.lerp(shade, 0.25), wall.lerp(shade, 0.15))
	if h.chimney:
		var cx: float = at.x + w * (0.26 if h.flip else -0.26)
		m.rect(Rect2(cx - w * 0.05, at.y - ht - roof * 0.92, w * 0.11, roof * 0.7), p.stone_dark)
		m.rect(Rect2(cx - w * 0.07, at.y - ht - roof * 0.96, w * 0.15, 3.0), p.stone)
	if h.front:
		# The gable faces us: a triangle of wall under two roof slopes.
		var apex := at + Vector2(0, -ht - roof)
		var el := at + Vector2(-w * 0.5, -ht)
		var er := at + Vector2(w * 0.5, -ht)
		m.fill(PackedVector2Array([apex, er, el]), wall.lerp(shade, 0.12), false)
		var over := w * 0.08
		var thick := maxf(w * 0.09, 3.0)
		m.line(apex, el + Vector2(-over, over * 0.8), thick, tile)
		m.line(apex, er + Vector2(over, over * 0.8), thick, tile.lerp(hi, hi.a))
	else:
		# The long side faces us: a roof slope.
		var a := at + Vector2(-w * 0.56, -ht + 1.0)
		var b := at + Vector2(w * 0.56, -ht + 1.0)
		var c := at + Vector2(w * 0.42, -ht - roof * 0.9)
		var d := at + Vector2(-w * 0.42, -ht - roof * 0.9)
		m.quad4(d, c, b, a, tile.lerp(hi, hi.a * 0.5), tile.lerp(hi, hi.a), tile.darkened(0.15), tile.darkened(0.1))
		m.line(d, c, 1.5, Color(hi, hi.a * 0.9))
	for r: Rect2 in h.windows:
		m.rect(r, p.glass)
		m.rect(Rect2(r.position + Vector2(-1, r.size.y), Vector2(r.size.x + 2, 1.5)), Color(p.stone, 0.8))
	if ht > 30.0:
		m.rect(Rect2(at.x - w * 0.06, at.y - ht * 0.36, w * 0.12, ht * 0.36), tile.darkened(0.3))


static func _church(m: MeshBatch2D, p: Dictionary) -> void:
	var c := GridValley.CHURCH_AT
	var wall: Color = p.stone
	var shade: Color = p.stone_dark
	# The nave, then the tower with its pointed spire.
	m.quad4(c + Vector2(-8, -46), c + Vector2(64, -46), c + Vector2(64, 0), c + Vector2(-8, 0), shade, wall, shade, wall)
	m.fill(PackedVector2Array([c + Vector2(-12, -44), c + Vector2(4, -74), c + Vector2(68, -74), c + Vector2(72, -44)]), p.roof_b, false)
	m.line(c + Vector2(4, -74), c + Vector2(68, -74), 1.5, p.roof_hi)
	m.quad4(c + Vector2(-44, -84), c + Vector2(-8, -84), c + Vector2(-8, 0), c + Vector2(-44, 0), shade, wall, shade, wall.lerp(shade, 0.3))
	m.fill(PackedVector2Array([c + Vector2(-26, -148), c + Vector2(-4, -84), c + Vector2(-48, -84)]), p.roof_b, false)
	m.fill(PackedVector2Array([c + Vector2(-26, -148), c + Vector2(-4, -84), c + Vector2(-24, -84)]), Color(p.roof_hi, 0.4), false)
	m.line(c + Vector2(-26, -148), c + Vector2(-26, -158), 1.5, p.steel_hi)
	m.line(c + Vector2(-31, -154), c + Vector2(-21, -154), 1.5, p.steel_hi)
	for r: Rect2 in GridValley.church_windows():
		m.round_rect(r, 3.0, p.glass)


static func _road(m: MeshBatch2D, p: Dictionary) -> void:
	var x := GridValley.LEFT
	while x < GridValley.RIGHT:
		var x2 := x + 12.0
		var y0 := GridValley.road_y(x)
		var y1 := GridValley.road_y(x2)
		var w0 := GridValley.road_w(y0)
		var w1 := GridValley.road_w(y1)
		m.quad(Vector2(x, y0 - w0 * 0.5 - 2.0), Vector2(x2, y1 - w1 * 0.5 - 2.0), Vector2(x2, y1 + w1 * 0.5 + 2.0), Vector2(x, y0 + w0 * 0.5 + 2.0), p.road_edge)
		m.quad(Vector2(x, y0 - w0 * 0.5), Vector2(x2, y1 - w1 * 0.5), Vector2(x2, y1 + w1 * 0.5), Vector2(x, y0 + w0 * 0.5), p.road)
		x = x2
	# Dashes down the middle.
	x = 700.0
	while x < 1880.0:
		var a := Vector2(x, GridValley.road_y(x))
		var b := Vector2(x + 14.0, GridValley.road_y(x + 14.0))
		m.line(a, b, 1.5, Color(p.line, (p.line as Color).a * 0.6))
		x += 34.0
	_bridge(m, p)
	# Lamp posts on the south verge (their heads light in the light mesh).
	for at in GridValley.lamps():
		var foot: Vector2 = at + Vector2(0, GridValley.road_w(at.y) * 0.5 + 3.0)
		var h := lerpf(38.0, 52.0, clampf((at.y - 860.0) / 90.0, 0.0, 1.0))
		m.line(foot, foot + Vector2(0, -h), 3.0, p.steel)
		m.line(foot + Vector2(0, -h), foot + Vector2(-8, -h - 2.0), 2.0, p.steel)
		m.circle(foot + Vector2(-8, -h - 1.0), 2.6, p.steel_hi)


## A stone road bridge over the river: a parapet and three low arches.
static func _bridge(m: MeshBatch2D, p: Dictionary) -> void:
	var c := GridValley.BRIDGE_AT
	var w := 74.0
	var water := c.y + 34.0
	m.rect_v(Rect2(c.x - w, c.y + 6, 2.0 * w, 28), p.stone, p.stone_dark)
	# Three low arches: half ellipses down to the water, dark under the stone.
	for k in 3:
		var ax := c.x + (k - 1) * 46.0
		var arch := MeshBatch2D.arc_points(Vector2(ax, water), 19.0, PI, TAU, 14)
		m.fill(arch, Color(p.river_bank, 0.95), false)
	m.rect(Rect2(c.x - w - 4, c.y + 3, 2.0 * w + 8, 5), p.stone)
	m.rect(Rect2(c.x - w, c.y - 9, 2.0 * w, 3), Color(p.stone, 0.9))
	for k in 7:
		m.rect(Rect2(c.x - w + k * (2.0 * w - 4.0) / 6.0, c.y - 9, 4, 12), Color(p.stone_dark, 0.9))


static func _pylons(m: MeshBatch2D, p: Dictionary) -> void:
	for i in range(GridValley.PYLONS.size() - 1, -1, -1):
		_pylon(m, GridValley.PYLONS[i][0], float(GridValley.PYLONS[i][1]), p, 1.0 + 1.4 * float(GridValley.PYLONS[i][1]) / 262.0)
	for wire in GridValley.wires():
		var pts: PackedVector2Array = wire.points
		for k in pts.size() - 1:
			m.line(pts[k], pts[k + 1], 2.0, p.wire)


## A lattice tower: splayed legs, cross braces, three arms that taper to a point at the top.
static func _pylon(m: MeshBatch2D, foot: Vector2, h: float, p: Dictionary, w: float) -> void:
	var steel: Color = p.steel
	var base := h * 0.17
	var waist := h * 0.05
	var top := foot + Vector2(0, -h)
	var neck := foot + Vector2(0, -h * 0.72)
	var ll := foot + Vector2(-base, 0)
	var lr := foot + Vector2(base, 0)
	var nl := neck + Vector2(-waist, 0)
	var nr := neck + Vector2(waist, 0)
	m.line(ll, nl, w * 1.5, steel)
	m.line(lr, nr, w * 1.5, steel)
	m.line(nl, top, w * 1.3, steel)
	m.line(nr, top, w * 1.3, steel)
	var bays := 5
	for k in bays:
		var t0 := float(k) / bays
		var t1 := float(k + 1) / bays
		var a := ll.lerp(nl, t0)
		var b := lr.lerp(nr, t0)
		var c := ll.lerp(nl, t1)
		var d := lr.lerp(nr, t1)
		m.line(a, d, w * 0.7, steel)
		m.line(b, c, w * 0.7, steel)
		m.line(c, d, w * 0.8, steel)
	# The arms: wider at the bottom; insulators hang from their tips.
	for k in 2:
		var y := lerpf(0.0, h * 0.13, float(k))
		var reach := h * (0.15 if k == 0 else 0.19)
		var at := top + Vector2(0, y + h * 0.03)
		m.line(at + Vector2(-reach, 0), at + Vector2(reach, 0), w * 1.1, steel)
		m.line(at + Vector2(-reach, 0), at + Vector2(0, -h * 0.05), w * 0.7, steel)
		m.line(at + Vector2(reach, 0), at + Vector2(0, -h * 0.05), w * 0.7, steel)
	m.line(nr + Vector2(0, h * 0.06), nr + Vector2(0, -h * 0.02), w * 0.8, p.steel_hi)


## The near land: the hill the shed stands on, the right bank, the foreground.
static func _near(m: MeshBatch2D, p: Dictionary) -> void:
	# The right bank: a low swell of meadow under the road's far end.
	var right_bank := PackedVector2Array()
	var x := 1380.0
	while x <= GridValley.RIGHT + 20.0:
		right_bank.append(Vector2(x, 926.0 + 16.0 * sin(x * 0.006) + 4.0 * sin(x * 0.02)))
		x += 20.0
	_ridge(m, right_bank, GridValley.SIZE.y, p.near, p.near_low)
	# The shed's hill, from behind the left edge down to the road, then along the bottom.
	var crest := PackedVector2Array()
	x = GridValley.LEFT
	while x <= 1520.0:
		crest.append(Vector2(x, GridValley.near_y(x)))
		x += 16.0
	_ridge(m, crest, GridValley.SIZE.y, p.near, p.near_low)
	for k in crest.size() - 1:
		m.line(crest[k], crest[k + 1], 3.0, Color(p.near_hi, 0.45))
	# Mown tufts and a rail fence running down the hill.
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for i in 420:
		var tx := rng.randf_range(GridValley.LEFT, GridValley.RIGHT)
		var top := GridValley.near_y(tx) if tx <= 1400.0 else 945.0
		var ty := rng.randf_range(top + 6.0, GridValley.SIZE.y)
		if absf(tx - 1400.0 - (ty - 900.0) * 0.8) < 150.0:
			continue
		var hh := lerpf(5.0, 18.0, (ty - 860.0) / 220.0)
		var col: Color = p.grass if i % 3 else p.grass_hi
		for blade in 3:
			m.line(Vector2(tx + blade * 3, ty), Vector2(tx + blade * 3 + rng.randf_range(-3, 3), ty - hh * rng.randf_range(0.6, 1.0)), 2.0, Color(col, 0.7))
	for h in GridValley.cottages():
		for t in [Vector2(-0.82, -0.6), Vector2(-0.62, -0.95), Vector2(-0.98, -1.05), Vector2(-0.74, -1.3)]:
			var c: Vector2 = (h.at as Vector2) + Vector2(t.x * float(h.w), t.y * float(h.h))
			m.circle(c, float(h.w) * 0.24, p.tree, false)
			m.circle(c + Vector2(6, -6), float(h.w) * 0.11, Color(p.tree_hi, 0.45), false)
		_house(m, h, p)
	# The fence down the hill.
	var post := 760.0
	while post < 1240.0:
		var y := GridValley.near_y(post)
		m.line(Vector2(post, y + 16.0), Vector2(post, y - 8.0), 4.0, p.fence)
		var y2 := GridValley.near_y(post + 72.0)
		m.line(Vector2(post, y - 3.0), Vector2(post + 72.0, y2 - 3.0), 2.5, p.fence)
		m.line(Vector2(post, y + 6.0), Vector2(post + 72.0, y2 + 6.0), 2.5, p.fence)
		post += 72.0


## The wheel's frame (it turns in its own layer), for either palette: `shade` is its colour.
static func paint_wheel(m: MeshBatch2D, ink: Color) -> void:
	var r := GridValley.WHEEL_R
	m.ring(Vector2.ZERO, r - 4.0, r + 1.0, ink)
	m.ring(Vector2.ZERO, r * 0.55 - 2.0, r * 0.55 + 1.0, ink)
	for k in GridValley.WHEEL_SPOKES:
		var a := TAU * k / float(GridValley.WHEEL_SPOKES)
		var at := Vector2(cos(a), sin(a))
		m.line(Vector2.ZERO, at * r, 3.0, ink)
		var b := Vector2(cos(a + TAU / GridValley.WHEEL_SPOKES), sin(a + TAU / GridValley.WHEEL_SPOKES))
		m.line(at * r, b * r * 0.55, 1.5, Color(ink, 0.8))
	m.circle(Vector2.ZERO, 9.0, ink)
