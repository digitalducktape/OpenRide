class_name GridShed
extends RefCounted
## The generator shed on the hill (#81; ART_BIBLE.md §3): the rider's half of the picture. An open
## timber bay, lit by one hanging lamp, with the machine in it: a pedal crank, its chain, a heavy
## flywheel, a belt and a copper dynamo. No rider is drawn: the empty pedals turn at the rider's own
## cadence, so the rider's legs are what's turning them.
##
## `paint` is everything that stands still (baked with the valley, in both palettes). The moving
## parts are `paint_crank`, `paint_flywheel`, `paint_pulley`, `paint_pedal` and `paint_needle`,
## each drawn once into its own layer and turned by `rotation`.

const FLOOR := 892.0  ## the bay's floor, on the hill
const POST_L := 70.0
const POST_R := 640.0
const EAVE := 640.0
const APEX := Vector2(355, 512)
const LAMP := Vector2(258, 676)
const CRANK := Vector2(186, 800)  ## the pedal crank's axle
const CRANK_R := 54.0  ## its chainring
const CRANK_ARM := 64.0
const PEDAL := Vector2(40, 12)
const FLYWHEEL := Vector2(390, 762)
const FLYWHEEL_R := 112.0
const PINION_R := 20.0
const DYNAMO := Rect2(494, 750, 108, 94)  ## the copper drum, between its end bells
const PULLEY := Vector2(548, 796)
const PULLEY_R := 22.0
const METER := Vector2(556, 696)
const METER_R := 40.0
const METER_FROM := deg_to_rad(150.0)  ## the scale's zero, clockwise to its end
const METER_SWEEP := deg_to_rad(240.0)
const MAST_TOP := Vector2(624, 560)

const WOOD := [Color("6b4a35"), Color("2c2230")]
const WOOD_DARK := [Color("3f2c26"), Color("171422")]
const TIN := [Color("7e6a72"), Color("1c1e36")]
const TIN_HI := [Color("e0a483"), Color("3a4468")]
const STONE := [Color("7d7070"), Color("20223a")]
## Inside the bay the lamp rules in both palettes: only a little darker at night.
const BOARD := [Color("6a452e"), Color("432c26")]
const BOARD_LOW := [Color("3e2a22"), Color("231a1e")]
const IRON := Color("23252e")
const IRON_HI := Color("6d7482")
const BRASS := Color("d9a441")
const BRASS_LO := Color("7f5a20")
const COPPER := Color("c8703e")
const COPPER_LO := Color("6f3519")
const CREAM := Color("efe4c8")


## The shed and the still parts of its machine, in the palette `night` (0 dusk, 1 night).
static func paint(m: MeshBatch2D, night: int) -> void:
	var wood: Color = WOOD[night]
	var dark: Color = WOOD_DARK[night]
	var tin: Color = TIN[night]
	var hi: Color = TIN_HI[night]
	# The bay: back wall of vertical boards, warm from the lamp.
	m.glow(Vector2(355, FLOOR + 8.0), Vector2(380, 24), Color(0, 0, 0, 0.4), 8)
	var x := POST_L
	var k := 0
	while x < POST_R:
		var w := 34.0
		var tone := 1.0 - 0.1 * float((k * 7) % 3)
		m.rect_v(Rect2(x, EAVE, w - 1.5, FLOOR - EAVE), (BOARD[night] as Color) * Color(tone, tone, tone), (BOARD_LOW[night] as Color) * Color(tone, tone, tone))
		x += w
		k += 1
	# The lamp's pool on the boards.
	m.glow(LAMP + Vector2(90, 70), Vector2(340, 250), Color(1.0, 0.72, 0.4, 0.42 if night == 0 else 0.3), 14, 0.1)
	# A spanner rack on the wall.
	m.rect(Rect2(102, 668, 96, 7), dark)
	for s in 4:
		m.line(Vector2(116 + s * 22, 674), Vector2(116 + s * 22, 696 + (s % 2) * 8), 4.0, Color(0.2, 0.2, 0.24))
	# The concrete bed.
	m.rect_v(Rect2(POST_L, 866, POST_R - POST_L, FLOOR - 866), Color("8a8078"), Color("4c4644"))
	m.rect(Rect2(POST_L, 866, POST_R - POST_L, 2), Color(1, 0.9, 0.75, 0.35))
	_crank_stand(m)
	_chain(m)
	_flywheel_stand(m)
	_belt(m)
	_dynamo(m)
	_meter(m)
	# The posts, the lintel and the gable.
	for px in [POST_L - 14.0, POST_R - 14.0]:
		m.rect_h(Rect2(px, EAVE, 28, FLOOR - EAVE + 4.0), wood.darkened(0.25), wood)
	m.rect_v(Rect2(POST_L - 26.0, EAVE - 14.0, POST_R - POST_L + 52.0, 22), wood, dark)
	var el := Vector2(POST_L - 36.0, EAVE - 10.0)
	var er := Vector2(POST_R + 36.0, EAVE - 10.0)
	var gable := PackedVector2Array([APEX, er, el])
	m.fill(gable, wood.darkened(0.2), false)
	# Boards on the gable, and a round vent.
	var bx := el.x + 30.0
	while bx < er.x:
		var t := absf(bx - APEX.x) / (er.x - APEX.x)
		var top := lerpf(APEX.y, EAVE - 10.0, t)
		m.line(Vector2(bx, top + 4.0), Vector2(bx, EAVE - 11.0), 2.0, Color(dark, 0.7))
		bx += 34.0
	m.circle(Vector2(APEX.x, 586), 25.0, dark)
	m.ring(Vector2(APEX.x, 586), 22.0, 27.0, wood.lightened(0.15))
	_bolt(m, Vector2(APEX.x, 586), 19.0, BRASS)
	# The tin roof's edge, thick, lit on the sun's side.
	m.line(APEX + Vector2(0, -10), er + Vector2(22, 6), 20.0, tin)
	m.line(APEX + Vector2(0, -10), el + Vector2(-22, 6), 20.0, tin.darkened(0.2))
	m.line(APEX + Vector2(0, -18), er + Vector2(22, -2), 3.0, hi)
	m.line(APEX + Vector2(0, -18), el + Vector2(-22, -2), 2.0, Color(hi, 0.4))
	# The lamp's cord; the shade (its glow is live).
	m.line(Vector2(LAMP.x, EAVE + 6.0), LAMP + Vector2(0, -16), 2.5, Color(0.1, 0.08, 0.08))
	m.fill(PackedVector2Array([LAMP + Vector2(-9, -16), LAMP + Vector2(9, -16), LAMP + Vector2(30, 5), LAMP + Vector2(-30, 5)]), Color("3f4a44"))
	m.line(LAMP + Vector2(-30, 5), LAMP + Vector2(30, 5), 2.5, BRASS_LO)
	# The feed: a short mast on the right post, insulators, and the line out.
	m.rect_h(Rect2(POST_R - 20.0, MAST_TOP.y, 8, EAVE - 16.0 - MAST_TOP.y), wood.darkened(0.3), wood)
	m.rect(Rect2(MAST_TOP.x - 22, MAST_TOP.y + 2, 44, 5), wood)
	for side in [-18.0, 18.0]:
		m.rect(Rect2(MAST_TOP.x + side - 3, MAST_TOP.y - 8, 6, 11), Color("c9ced6") if night == 0 else Color("56607e"))
	# The cable down the post to the dynamo.
	m.line(MAST_TOP + Vector2(-12, 8), Vector2(POST_R - 10.0, 700), 3.0, Color(0.1, 0.09, 0.1))
	m.line(Vector2(POST_R - 10.0, 700), Vector2(DYNAMO.end.x - 4.0, 760), 3.0, Color(0.1, 0.09, 0.1))


## A lightning-bolt plate: a jagged flash, two convex halves.
static func _bolt(m: MeshBatch2D, c: Vector2, s: float, col: Color) -> void:
	m.fill(PackedVector2Array([c + Vector2(0.15, -1.0) * s, c + Vector2(-0.55, 0.15) * s, c + Vector2(0.05, 0.15) * s]), col, false)
	m.fill(PackedVector2Array([c + Vector2(-0.15, 1.0) * s, c + Vector2(0.55, -0.15) * s, c + Vector2(-0.05, -0.15) * s]), col, false)


static func _crank_stand(m: MeshBatch2D) -> void:
	# An A-frame of iron tube carrying the crank's axle.
	var foot_l := Vector2(CRANK.x - 66.0, 868)
	var foot_r := Vector2(CRANK.x + 66.0, 868)
	m.line(foot_l, CRANK, 13.0, IRON)
	m.line(foot_r, CRANK, 13.0, IRON)
	m.line(foot_l + Vector2(3, -2), CRANK + Vector2(-2, -3), 2.5, IRON_HI)
	m.line(foot_r + Vector2(-3, -2), CRANK + Vector2(2, -3), 2.5, IRON_HI)
	m.round_rect(Rect2(foot_l.x - 16, 862, 164, 9), 3.0, IRON_HI, IRON)


static func _tangent(c0: Vector2, r0: float, c1: Vector2, r1: float, side: float) -> Array:
	var d := c1 - c0
	var a := d.angle() + side * acos(clampf((r0 - r1) / d.length(), -1.0, 1.0))
	var n := Vector2(cos(a), sin(a))
	return [c0 + n * r0, c1 + n * r1]


static func _chain(m: MeshBatch2D) -> void:
	for side in [-1.0, 1.0]:
		var t := _tangent(CRANK, CRANK_R, FLYWHEEL, PINION_R, side)
		m.line(t[0], t[1], 7.0, Color(0.1, 0.1, 0.13))
		var a: Vector2 = t[0]
		var b: Vector2 = t[1]
		var links := int(a.distance_to(b) / 9.0)
		for k in links:
			var p := a.lerp(b, (k + 0.5) / links)
			m.circle(p, 1.7, Color(0.62, 0.64, 0.7), false)


static func _flywheel_stand(m: MeshBatch2D) -> void:
	var f := FLYWHEEL
	# A cast pedestal under the axle; the wheel turns in front of it.
	m.fill(PackedVector2Array([f + Vector2(-18, 6), f + Vector2(18, 6), f + Vector2(64, 868 - f.y), f + Vector2(-64, 868 - f.y)]), Color("2b2f3a"))
	m.round_rect(Rect2(f.x - 78, 860, 156, 10), 3.0, IRON_HI, IRON)


static func _belt(m: MeshBatch2D) -> void:
	for side in [-1.0, 1.0]:
		var t := _tangent(FLYWHEEL, FLYWHEEL_R * 0.86, PULLEY, PULLEY_R, side)
		m.line(t[0], t[1], 8.0, Color("3a2418"))
		m.line(t[0], t[1], 2.0, Color("7a5234"))


static func _dynamo(m: MeshBatch2D) -> void:
	var r := DYNAMO
	# Its feet and bed.
	m.round_rect(Rect2(r.position.x - 10, 852, r.size.x + 20, 16), 3.0, IRON_HI, IRON)
	m.rect(Rect2(r.position.x + 6, r.end.y - 2, 16, 14), IRON)
	m.rect(Rect2(r.end.x - 22, r.end.y - 2, 16, 14), IRON)
	# The copper windings, band by band, a highlight along the top.
	m.round_rect(r, 12.0, COPPER, COPPER_LO)
	var y := r.position.y + 5.0
	while y < r.end.y - 5.0:
		m.line(Vector2(r.position.x + 3, y), Vector2(r.end.x - 3, y), 1.8, Color(0.25, 0.1, 0.03, 0.55))
		y += 6.0
	m.glow(r.position + Vector2(r.size.x * 0.4, 22), Vector2(r.size.x * 0.5, 15), Color(1.0, 0.86, 0.66, 0.5), 8)
	# Two iron bands and a brass plate; brushes at the top.
	for bx in [r.position.x + 18.0, r.end.x - 18.0]:
		m.rect_v(Rect2(bx - 6, r.position.y - 3, 12, r.size.y + 6), IRON_HI, IRON)
	m.round_rect(Rect2(r.position.x + 32, r.position.y + 40, 44, 26), 3.0, BRASS, BRASS_LO)
	_bolt(m, r.position + Vector2(54, 53), 10.0, Color("3a2a10"))


static func _meter(m: MeshBatch2D) -> void:
	var c := METER
	var r := METER_R
	m.soft_shadow(Rect2(c - Vector2(r, r) + Vector2(4, 6), Vector2(r, r) * 2.0), r, 12.0, Color(0, 0, 0, 0.5))
	m.circle(c, r + 8.0, BRASS_LO)
	m.ring(c, r + 1.0, r + 8.0, BRASS)
	m.ring(c, r + 5.0, r + 6.5, Color(1, 0.93, 0.7, 0.8), PI * 1.05, PI * 1.6)
	m.circle(c, r, CREAM)
	for k in 11:
		var a := METER_FROM + METER_SWEEP * k / 10.0
		var d := Vector2(cos(a), sin(a))
		m.line(c + d * (r - (11.0 if k % 5 == 0 else 7.0)), c + d * (r - 3.0), 3.0 if k % 5 == 0 else 1.8, Color("2a2420"))
	m.circle(c + Vector2(0, 16), 6.0, Color("e0a02c"))
	_bolt(m, c + Vector2(0, 16), 5.5, Color("2a2420"))


## The meter's angle for `share` (0-1 along its scale).
static func meter_angle(share: float) -> float:
	return METER_FROM + METER_SWEEP * clampf(share, 0.0, 1.0)


## The supply needle (drawn pointing along +x; turned by rotation).
static func paint_needle(m: MeshBatch2D) -> void:
	m.fill(PackedVector2Array([Vector2(-8, -3.5), Vector2(METER_R - 7.0, 0), Vector2(-8, 3.5)]), Color("b8261e"))
	m.circle(Vector2.ZERO, 6.0, BRASS)
	m.circle(Vector2.ZERO, 2.5, BRASS_LO)


## The demand marker: a gold pointer on the scale's edge, a plain triangle.
static func paint_marker(m: MeshBatch2D) -> void:
	var r := METER_R
	m.fill(PackedVector2Array([Vector2(r - 16.0, 0), Vector2(r + 1.0, -8), Vector2(r + 1.0, 8)]), Color("2a2420"))
	m.fill(PackedVector2Array([Vector2(r - 12.0, 0), Vector2(r, -5), Vector2(r, 5)]), Color("f2b632"))


## The chainring and the crank arms, turned about the axle.
static func paint_crank(m: MeshBatch2D) -> void:
	var r := CRANK_R
	# Teeth, then the ring, then its spider.
	var teeth := 28
	for k in teeth:
		var a := TAU * k / teeth
		var d := Vector2(cos(a), sin(a))
		var s := d.orthogonal() * 3.6
		m.quad(d * (r - 2.0) - s, d * (r - 2.0) + s, d * (r + 5.0) + s * 0.5, d * (r + 5.0) - s * 0.5, Color("8f96a4"))
	m.ring(Vector2.ZERO, r - 12.0, r, Color("757c8c"))
	m.ring(Vector2.ZERO, r - 3.0, r - 1.0, Color(1, 1, 1, 0.3))
	for k in 5:
		var a := TAU * k / 5.0 + 0.3
		m.line(Vector2.ZERO, Vector2(cos(a), sin(a)) * (r - 8.0), 11.0, Color("5c6372"))
	# The two arms.
	for side in [-1.0, 1.0]:
		var tip := Vector2(0, side * CRANK_ARM)
		m.line(Vector2.ZERO, tip, 15.0, IRON)
		m.line(Vector2(-4, 0), tip + Vector2(-4, 0), 2.5, IRON_HI)
		m.circle(tip, 8.0, IRON)
		m.circle(tip, 3.5, IRON_HI)
	m.circle(Vector2.ZERO, 12.0, BRASS_LO)
	m.circle(Vector2.ZERO, 9.0, BRASS)
	m.circle(Vector2(-2, -3), 3.0, Color(1, 0.95, 0.75, 0.8))


## One pedal, kept level as the crank turns (its layer is moved, never turned).
static func paint_pedal(m: MeshBatch2D) -> void:
	var s := PEDAL
	m.round_rect(Rect2(-s * 0.5, s), 3.0, Color("3a3f4c"), Color("20222a"))
	m.rect(Rect2(-s.x * 0.5 + 3, -2, s.x - 6, 3), Color("8a92a2"))


## The flywheel: a heavy cast rim, six spokes and a hub, its pinion in front.
static func paint_flywheel(m: MeshBatch2D) -> void:
	var r := FLYWHEEL_R
	m.ring(Vector2.ZERO, r - 24.0, r, Color("2b2f3a"))
	m.ring(Vector2.ZERO, r - 24.0, r - 20.0, Color("181a22"))
	# The rim's face catches the lamp from above, as an arc; it turns, so it's spaced evenly.
	for k in 6:
		var a := TAU * k / 6.0
		m.ring(Vector2.ZERO, r - 9.0, r - 3.0, Color(0.72, 0.76, 0.84, 0.5), a, a + 0.5)
		var d := Vector2(cos(a + 0.26), sin(a + 0.26))
		m.quad(d.orthogonal() * 13.0, -d.orthogonal() * 13.0 , d * (r - 22.0) - d.orthogonal() * 7.0, d * (r - 22.0) + d.orthogonal() * 7.0, Color("2b2f3a"))
		m.line(d * 26.0 + d.orthogonal() * 6.0, d * (r - 26.0) + d.orthogonal() * 4.0, 2.0, Color(0.6, 0.64, 0.72, 0.5))
		m.circle(d * (r - 12.0), 3.2, Color("8f96a4"))
	m.circle(Vector2.ZERO, 34.0, Color("2b2f3a"))
	m.ring(Vector2.ZERO, 30.0, 34.0, IRON_HI)
	# The pinion the chain drives.
	var teeth := 14
	for k in teeth:
		var a := TAU * k / teeth
		var d := Vector2(cos(a), sin(a))
		m.line(d * (PINION_R - 3.0), d * (PINION_R + 3.0), 4.0, Color("8f96a4"))
	m.circle(Vector2.ZERO, PINION_R, Color("757c8c"))
	m.circle(Vector2.ZERO, 11.0, BRASS)
	m.circle(Vector2.ZERO, 5.0, BRASS_LO)
	# One red-painted spoke mark, so the wheel's turning reads even when it's slow.
	m.round_rect(Rect2(40, -5, 40, 10), 4.0, Color("b8261e"))


## The dynamo's pulley.
static func paint_pulley(m: MeshBatch2D) -> void:
	var r := PULLEY_R
	m.circle(Vector2.ZERO, r, Color("5c6372"))
	m.ring(Vector2.ZERO, r - 5.0, r, Color("2b2f3a"))
	for k in 3:
		var a := TAU * k / 3.0
		m.line(Vector2.ZERO, Vector2(cos(a), sin(a)) * (r - 5.0), 5.0, Color("2b2f3a"))
	m.circle(Vector2.ZERO, 6.0, BRASS)


## The shed's reach on the canvas, roof and mast included, for the layout test.
static func bounds() -> Rect2:
	return Rect2(POST_L - 60.0, APEX.y - 26.0, POST_R - POST_L + 120.0, FLOOR - APEX.y + 34.0)
