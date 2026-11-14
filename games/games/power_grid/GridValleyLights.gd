class_name GridValleyLights
extends RefCounted
## Power Grid's town lights (#81): every window, lamp and bulb of GridValley's layout, listed into
## the additive light mesh (`GridLights`), each on its district's channel, plus the big wheel's own
## lamps. GridValley.lights and wheel_lights call in here.


## Every light in the town (`m` is a `GridLights`), each on its district's channel.
static func lights(m: GridLights) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	_house_lights(m, rng)
	_lamp_lights(m)
	_fair_lights(m, rng)
	_stadium_lights(m, rng)
	# The river catches the lit town, in long soft columns.
	for at in [[Vector2(1344, 790), 2, Color(1.0, 0.55, 0.4)], [Vector2(1296, 716), 2, Color(1.0, 0.7, 0.4)]]:
		m.glow(at[0], Vector2(18, 60), Color(at[2], 0.6), at[1], 0.1, 0.3)
	for at: Vector2 in [Vector2(1366, 920), Vector2(1430, 976)]:
		m.glow(at, Vector2(36, 64), Color(1.0, 0.86, 0.6, 0.42), 1, 0.4, 0.3)
	m.glow(Vector2(1500, 1040), Vector2(100, 80), Color(0.82, 0.9, 1.0, 0.34), 3, 0.2, 0.3)


static func _house_lights(m: GridLights, rng: RandomNumberGenerator) -> void:
	var warm := [Color(1.0, 0.82, 0.48), Color(1.0, 0.72, 0.4), Color(1.0, 0.9, 0.66)]
	for h in GridValley.houses():
		for r: Rect2 in h.windows:
			if rng.randf() < 0.14:
				continue  # somebody's out
			var th := rng.randf_range(0.04, 0.96)
			var col: Color = warm[rng.randi_range(0, 2)]
			_panes(m, r, col, th, rng.randf())
			m.glow(r.get_center(), r.size * 3.2, Color(col, 0.34), 0, th, rng.randf())
	for h in GridValley.cottages():
		for r: Rect2 in h.windows:
			_panes(m, r, warm[0], 0.3, 0.2)
			m.glow(r.get_center(), r.size * 3.2, Color(warm[0], 0.34), 0, 0.3, 0.2)
	for r: Rect2 in GridValley.church_windows():
		m.rect(r, Color(1.0, 0.7, 0.42, 0.9), 0, 0.5, 0.5)
		m.glow(r.get_center(), r.size * 2.0, Color(1.0, 0.6, 0.4, 0.24), 0, 0.5, 0.5)


## A window: two lit panes with a bar between, once it's big enough to show one.
static func _panes(m: GridLights, r: Rect2, col: Color, th: float, seed_value: float) -> void:
	if r.size.x < 8.0:
		m.rect(r, Color(col, 0.95), 0, th, seed_value)
		return
	var half := (r.size.x - 1.5) * 0.5
	m.rect(Rect2(r.position, Vector2(half, r.size.y)), Color(col, 0.95), 0, th, seed_value)
	m.rect(Rect2(r.position + Vector2(half + 1.5, 0), Vector2(half, r.size.y)), Color(col, 0.95), 0, th, seed_value)


static func _lamp_lights(m: GridLights) -> void:
	var list := GridValley.lamps()
	for i in list.size():
		var at: Vector2 = list[i]
		var th := float(i) / list.size() * 0.9 + 0.04  # a wave along the road, left to right
		var head := GridValley.lamp_head(at)
		var col := Color(1.0, 0.8, 0.46)
		m.glow(head, Vector2(4.5, 4.5), Color(1, 0.96, 0.82, 1.0), 1, th, 0.0)
		m.glow(head, Vector2(26, 26), Color(col, 0.42), 1, th, 0.0)
		m.glow(at + Vector2(-8, 3), Vector2(48, 13), Color(col, 0.34), 1, th, 0.0)


static func _fair_lights(m: GridLights, rng: RandomNumberGenerator) -> void:
	# Bulb strings from the wheel's foot out over the yard, the carousel's crown, the tents' doors.
	var strings := [[Vector2(1000, 680), Vector2(1062, 746)], [Vector2(1062, 746), Vector2(1150, 770)], [Vector2(1150, 770), Vector2(1250, 716)],
		[Vector2(1250, 716), Vector2(1296, 774)]]
	var colors := [Color(1.0, 0.42, 0.5), Color(1.0, 0.84, 0.42), Color(0.5, 0.86, 1.0), Color(0.72, 1.0, 0.56)]
	var n := 0
	for s in strings:
		var pts := GridValley.catenary(s[0], s[1], 14.0, 9)
		for pt in pts:
			m.bulb(pt, 4.2, colors[n % 4], 2, rng.randf_range(0.05, 0.95), 2.0 + float(n % 4) * 0.25)
			n += 1
	var c := GridValley.CAROUSEL_AT
	for k in 13:
		var x := c.x - 58.0 + k * 9.7
		m.bulb(Vector2(x, c.y - 44.0), 3.8, colors[k % 4], 2, rng.randf_range(0.05, 0.95), 2.0 + float(k % 4) * 0.25)
	m.glow(c + Vector2(0, -18), Vector2(96, 60), Color(1.0, 0.7, 0.45, 0.5), 2, 0.3, 0.1)
	m.glow(Vector2(1120, 800), Vector2(230, 90), Color(1.0, 0.45, 0.5, 0.26), 2, 0.2, 0.1)
	m.rect(Rect2(c.x - 49, c.y - 40, 98, 36), Color(1.0, 0.72, 0.42, 0.34), 2, 0.3, 0.1)
	for k in 4:
		var at := GridValley.stall_at(k)
		m.rect(Rect2(at + Vector2(-18, -16), Vector2(36, 16)), Color(1.0, 0.8, 0.5, 0.9), 2, 0.2 + k * 0.2, 0.3)
		m.glow(at + Vector2(0, -4), Vector2(38, 24), Color(1.0, 0.7, 0.42, 0.3), 2, 0.2 + k * 0.2, 0.3)
	for t in GridValley.TENTS:
		var foot: Vector2 = t[0]
		var w: float = t[1]
		var h := w * 0.6
		m.rect(Rect2(foot.x - w * 0.24, foot.y - h * 0.8, w * 0.48, h * 0.8), Color(1.0, 0.76, 0.46, 0.9), 2, 0.4, 0.4)
		m.glow(foot + Vector2(0, -h * 0.4), Vector2(w * 0.9, w * 0.6), Color(1.0, 0.66, 0.4, 0.3), 2, 0.4, 0.4)


static func _stadium_lights(m: GridLights, rng: RandomNumberGenerator) -> void:
	var c := GridValley.STADIUM_AT
	var white := Color(0.86, 0.93, 1.0)
	# The pitch under the floods, then each mast's bank and its beam.
	var pitch := GridValley.STADIUM_R * 0.66
	m.glow(c, pitch * 1.5, Color(0.7, 1.0, 0.62, 0.72), 3, 0.3, 0.0)
	m.glow(c, GridValley.STADIUM_R * 1.7, Color(white, 0.3), 3, 0.3, 0.0)
	for i in GridValley.MASTS.size():
		var top: Vector2 = (GridValley.MASTS[i] as Vector2) + Vector2(0, -GridValley.MAST_H)
		var th := 0.1 + i * 0.22
		var to := c + Vector2((top.x - c.x) * 0.2, 0)
		m.beam(top + Vector2(-14, 2), top + Vector2(14, 2), to + Vector2(70, 0), to + Vector2(-70, 0), Color(white, 0.42), 3, th, 0.0)
		for r in 2:
			for k in 4:
				m.bulb(top + Vector2(-12.0 + k * 8.0, -6.0 + r * 8.0), 3.4, white, 3, th, 0.0)
		m.glow(top, Vector2(66, 52), Color(white, 0.62), 3, th, 0.0)
	# The crowd's phones and scarves: a few warm sparks in the stands.
	for i in 60:
		var a := rng.randf() * TAU
		var k := rng.randf_range(0.72, 0.97)
		m.bulb(c + Vector2(cos(a), sin(a)) * GridValley.STADIUM_R * k, 1.5, Color(1.0, 0.9, 0.7), 3, rng.randf_range(0.2, 0.95), rng.randf())


## The wheel's lamps, on the rim, for the wheel's own light mesh (origin at the hub).
static func wheel_lights(m: GridLights) -> void:
	var colors := [Color(1.0, 0.42, 0.5), Color(1.0, 0.84, 0.42), Color(0.5, 0.86, 1.0)]
	for k in GridValley.WHEEL_SPOKES * 2:
		var a := TAU * k / (GridValley.WHEEL_SPOKES * 2.0)
		m.bulb(Vector2(cos(a), sin(a)) * GridValley.WHEEL_R, 5.0, colors[k % 3], 2, float(k) / (GridValley.WHEEL_SPOKES * 2.0) * 0.9 + 0.05, 2.0 + float(k % 4) * 0.25)
	for k in GridValley.WHEEL_SPOKES:
		var a := TAU * k / float(GridValley.WHEEL_SPOKES)
		m.bulb(Vector2(cos(a), sin(a)) * GridValley.WHEEL_R * 0.55, 3.4, Color(1.0, 0.9, 0.7), 2, 0.5, 2.5)
		m.beam(Vector2.ZERO, Vector2.ZERO, Vector2(cos(a + 0.02), sin(a + 0.02)) * GridValley.WHEEL_R, Vector2(cos(a - 0.02), sin(a - 0.02)) * GridValley.WHEEL_R, Color(1.0, 0.7, 0.5, 0.5), 2, 0.4, 0.2)
	m.glow(Vector2.ZERO, Vector2.ONE * GridValley.WHEEL_R * 1.5, Color(1.0, 0.55, 0.5, 0.26), 2, 0.3, 0.2)
