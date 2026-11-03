class_name PumpArt
extends RefCounted
## Balloon Pump's hero drawn in code (#76, the 2D rework; ART_BIBLE.md §4 and §5): the brass pump
## on its painted plinth, the gauge's face and bezel, the red hose, the nozzle stand and a basket
## of spare balloons, all lit by the place's key light, into a `SafeMesh` batch (baked with the
## room). The parts that move (the plunger, the gauge's needle and push wedge, the balloons) are
## `PumpStage`'s nodes; their static drawings are here too.

const BRASS := Color(0.86, 0.66, 0.28)
const BRASS_DARK := Color(0.45, 0.3, 0.1)
const BRASS_HI := Color(1.0, 0.93, 0.68)
const PAINT := Color(0.66, 0.14, 0.13)  ## the plinth's red
const HOSE := Color(0.62, 0.12, 0.1)
const FACE := Color(0.98, 0.95, 0.87)
const INK := Color(0.12, 0.06, 0.1)

## Balloon kinds (PumpLogic.KINDS): their colours and full radius (px, the body's half-width).
const BALLOON_COLORS := {"small": Color("3fd0a8"), "medium": Color("ff4f96"), "large": Color("8a7dff"),
	"gold": Color("ffc530")}
const BALLOON_RADIUS := {"small": 140.0, "medium": 170.0, "large": 200.0, "gold": 170.0}
## The balloon quad's height over its half-width: the knot at the bottom, the body above.
const BALLOON_TALL := 2.3

## The gauge's scale: 270° from lower left, clockwise (radians, canvas angles: y down).
const GAUGE_FROM := PI * 0.75
const GAUGE_SWEEP := PI * 1.5


## The canvas angle of a reading `t` (0-1 along the gauge's scale).
static func gauge_angle(t: float) -> float:
	return GAUGE_FROM + GAUGE_SWEEP * clampf(t, 0.0, 1.05)


static func paint_machine(m: SafeMesh, index: int) -> void:
	var l := PumpPlaces.light(index)
	var accent: Color = PumpPlaces.place(index).accent
	var lx := clampf(((l.at as Vector2).x - PumpPlaces.PUMP_X) / 600.0, -1.0, 1.0)  # the light's side
	var away := Vector2(-signf(lx) if absf(lx) > 0.05 else 0.3, 0.0)
	_shadows(m, away)
	_basket(m, lx)
	_hose(m, lx)
	_stand(m, lx)
	_plinth(m, lx, accent)
	_barrel(m, lx)
	_gauge_face(m, lx)


# --- Shadows ---

static func _shadows(m: SafeMesh, away: Vector2) -> void:
	var foot := Vector2(PumpPlaces.PUMP_X, PumpPlaces.FLOOR_Y + 2.0)
	m.glow(foot + away * 60.0, Vector2(230, 40), Color(0, 0, 0, 0.6), 10, 0.3)
	m.glow(PumpPlaces.STAND_FOOT + away * 30.0 + Vector2(0, 4), Vector2(110, 20), Color(0, 0, 0, 0.55), 8, 0.3)
	m.glow(PumpPlaces.TETHER + Vector2(0, 8), Vector2(60, 12), Color(0, 0, 0, 0.5), 8, 0.3)


# --- Brass ---

## A vertical cylinder's shading across `r`: dark edges, a broad body, a hot highlight toward the
## light (`lx` -1 left .. 1 right) and a faint reflected light on the far edge.
static func cylinder(m: SafeMesh, r: Rect2, base: Color, lx: float) -> void:
	var hi_at := 0.5 + 0.22 * lx
	var stops := [[0.0, base.darkened(0.55)], [0.12, base.darkened(0.2)], [hi_at - 0.14, base.lightened(0.05)],
		[hi_at - 0.04, base.lightened(0.45)], [hi_at, BRASS_HI if base == BRASS else base.lightened(0.6)],
		[hi_at + 0.05, base.lightened(0.3)], [hi_at + 0.18, base], [0.86, base.darkened(0.35)],
		[0.94, base.darkened(0.15)], [1.0, base.darkened(0.6)]]
	if lx < 0.0:
		stops = [[0.0, base.darkened(0.6)], [0.06, base.darkened(0.15)], [0.14, base.darkened(0.35)],
			[hi_at - 0.18, base], [hi_at - 0.05, base.lightened(0.3)], [hi_at, BRASS_HI if base == BRASS else base.lightened(0.6)],
			[hi_at + 0.04, base.lightened(0.45)], [hi_at + 0.14, base.lightened(0.05)], [0.88, base.darkened(0.2)], [1.0, base.darkened(0.55)]]
	for k in stops.size() - 1:
		var a: float = stops[k][0]
		var b: float = stops[k + 1][0]
		if b <= a:
			continue
		m.rect_h(Rect2(r.position.x + r.size.x * a, r.position.y, r.size.x * (b - a) + 0.5, r.size.y), stops[k][1], stops[k + 1][1])


## A band round the barrel (a hoop): cylinder shading, a lit top lip and a dark seam under it,
## and rivets spaced as on a cylinder.
static func hoop(m: SafeMesh, cx: float, y: float, half: float, h: float, lx: float, rivets := 7) -> void:
	cylinder(m, Rect2(cx - half, y, half * 2.0, h), BRASS.darkened(0.12), lx)
	m.line(Vector2(cx - half + 4, y + 1), Vector2(cx + half - 4, y + 1), 2.0, Color(1, 0.95, 0.75, 0.55))
	m.line(Vector2(cx - half + 2, y + h), Vector2(cx + half - 2, y + h), 2.5, Color(0.18, 0.1, 0.02, 0.6))
	for k in rivets:
		var a := PI * (k + 0.5) / rivets
		var x := cx - cos(a) * (half - 6.0)
		var r := 3.5 * (0.55 + 0.45 * sin(a))
		SafePlaces.rivet(m, Vector2(x, y + h * 0.5), r, BRASS, Vector2(lx * 0.7, -0.7).normalized())


static func _barrel(m: SafeMesh, lx: float) -> void:
	var b := PumpPlaces.BARREL
	var cx := b.get_center().x
	# A rim of key light down the lit side, then the barrel.
	cylinder(m, b, BRASS, lx)
	m.rect_v(Rect2(b.position.x, b.position.y, b.size.x, 40), Color(1, 0.9, 0.6, 0.12), Color(1, 0.9, 0.6, 0.0))
	# A soft vertical reflection of the room, faint, on the far side.
	m.rect_h(Rect2(cx - 50.0 * signf(lx + 0.001), b.position.y + 20, 8, b.size.y - 40), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.08))
	hoop(m, cx, b.position.y + 26.0, b.size.x * 0.5 + 6.0, 20.0, lx)
	hoop(m, cx, b.position.y + 236.0, b.size.x * 0.5 + 4.0, 16.0, lx)
	hoop(m, cx, b.end.y - 36.0, b.size.x * 0.5 + 10.0, 26.0, lx, 9)
	# The dome: a shaded half-ellipse, a hot spot toward the light, and the collar on it.
	var dome := PackedVector2Array()
	var cols := PackedColorArray()
	var dc := Vector2(cx, b.position.y + 2.0)
	var rx := b.size.x * 0.5 + 6.0
	var ry := 64.0
	for k in 25:
		var a := PI + PI * k / 24.0
		var p := dc + Vector2(cos(a) * rx, sin(a) * ry)
		dome.append(p)
		var side := (p.x - cx) / rx
		cols.append(BRASS.lerp(BRASS_DARK, clampf(0.35 + 0.5 * absf(side - lx * 0.5), 0.0, 0.85)))
	var ci := m.vert(dc, BRASS.lightened(0.12))
	var first := m.points.size()
	for k in dome.size():
		m.vert(dome[k], cols[k])
	for k in dome.size() - 1:
		m.tri(ci, first + k, first + k + 1)
	m.band_colors(dome, SafeMesh.grow_outline(dome, SafeMesh.FEATHER), cols, _clear(cols), false)
	m.glow(dc + Vector2(lx * 30.0, -36), Vector2(34, 16), Color(1, 0.97, 0.82, 0.7), 8, 0.3)
	var c := PumpPlaces.COLLAR
	m.soft_shadow(c, 6.0, 8.0, Color(0, 0, 0, 0.35))
	cylinder(m, c, BRASS.darkened(0.1), lx)
	m.rect(Rect2(c.position.x - 4, c.position.y - 6, c.size.x + 8, 8), BRASS.lightened(0.15))
	# A blank maker's plate (no lettering) between the hoops.
	var plate := Rect2(cx - 46, b.position.y + 76, 92, 40)
	m.round_rect(plate, 6.0, BRASS_DARK.darkened(0.2), BRASS_DARK.darkened(0.5))
	m.round_rect(plate.grow(-5), 4.0, Color(0.16, 0.09, 0.05), Color(0.1, 0.05, 0.03))
	for dx in [-36.0, 36.0]:
		SafePlaces.rivet(m, Vector2(cx + dx, plate.get_center().y), 3.5, BRASS, Vector2(0, -1))
	m.line(Vector2(cx - 26, plate.get_center().y), Vector2(cx + 26, plate.get_center().y), 3.0, BRASS.darkened(0.2))


static func _clear(cols: PackedColorArray) -> PackedColorArray:
	var out := PackedColorArray()
	for c in cols:
		out.append(Color(c, 0.0))
	return out


# --- The plinth ---

static func _plinth(m: SafeMesh, lx: float, accent: Color) -> void:
	var r := PumpPlaces.PLINTH
	var top_h := 20.0
	# The top face in a gentle perspective, lit; the front face painted red with a gold pinstripe.
	m.quad4(Vector2(r.position.x + 14, r.position.y - top_h), Vector2(r.end.x - 14, r.position.y - top_h),
		Vector2(r.end.x, r.position.y), r.position, PAINT.lightened(0.35), PAINT.lightened(0.35), PAINT.lightened(0.15), PAINT.lightened(0.15))
	m.rect_v(r, PAINT.lightened(0.05), PAINT.darkened(0.45))
	m.rect_h(Rect2(r.position.x, r.position.y, 26, r.size.y), Color(0, 0, 0, 0.0 if lx < 0.0 else 0.25), Color(0, 0, 0, 0))
	m.rect_h(Rect2(r.end.x - 26, r.position.y, 26, r.size.y), Color(0, 0, 0, 0), Color(0, 0, 0, 0.25 if lx < 0.0 else 0.0))
	var stripe := r.grow(-12)
	for e in [[stripe.position, Vector2(stripe.end.x, stripe.position.y)], [Vector2(stripe.end.x, stripe.position.y), stripe.end],
			[stripe.end, Vector2(stripe.position.x, stripe.end.y)], [Vector2(stripe.position.x, stripe.end.y), stripe.position]]:
		m.line(e[0], e[1], 3.0, accent.darkened(0.1))
	# A painted star in the panel's middle, and brass corners and feet.
	var star := PackedVector2Array()
	var sc := r.get_center()
	for k in 10:
		var a := -PI * 0.5 + TAU * k / 10.0
		star.append(sc + Vector2(cos(a), sin(a)) * (18.0 if k % 2 == 0 else 8.0))
	m.fill(star, accent)
	for x in [r.position.x, r.end.x - 18.0]:
		m.rect_v(Rect2(x, r.position.y, 18, 18), BRASS.lightened(0.1), BRASS_DARK)
		m.rect_v(Rect2(x, r.end.y - 18, 18, 18), BRASS, BRASS_DARK)
		m.rect_v(Rect2(x - 2, r.end.y, 22, 8), BRASS_DARK, BRASS_DARK.darkened(0.4))
	# The outlet pipe at the barrel's foot, turning down to the hose.
	var b := PumpPlaces.BARREL
	cylinder_h(m, Rect2(b.end.x - 4, b.end.y - 34, 52, 22), BRASS, -1.0)
	m.circle(Vector2(b.end.x + 50, b.end.y - 23), 15.0, BRASS.darkened(0.15))
	m.circle(Vector2(b.end.x + 50, b.end.y - 23), 9.0, BRASS_DARK.darkened(0.3))


## A horizontal cylinder's shading across `r` (top lit).
static func cylinder_h(m: SafeMesh, r: Rect2, base: Color, _lx: float) -> void:
	var h := r.size.y
	m.rect_v(Rect2(r.position.x, r.position.y, r.size.x, h * 0.3), base.darkened(0.2), BRASS_HI)
	m.rect_v(Rect2(r.position.x, r.position.y + h * 0.3, r.size.x, h * 0.7), BRASS_HI, base.darkened(0.55))


# --- The hose, the stand, the basket ---

## The hose: a thick rubber tube on a curve from the outlet, down to the floor and along it to the
## stand's foot, shaded across (dark edges, a highlight stripe toward the light).
static func _hose(m: SafeMesh, lx: float) -> void:
	var b := PumpPlaces.BARREL
	var p0 := Vector2(b.end.x + 50, b.end.y - 14)
	var p1 := Vector2(b.end.x + 70, PumpPlaces.FLOOR_Y + 10)
	var p2 := Vector2(980, PumpPlaces.FLOOR_Y + 40)
	var p3 := Vector2(PumpPlaces.STAND_FOOT.x - 60, PumpPlaces.STAND_FOOT.y - 4)
	var pts := PackedVector2Array()
	for k in 33:
		var t := float(k) / 32.0
		var u := 1.0 - t
		pts.append(u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3)
	var w := 13.0
	var offsets := [-w - SafeMesh.FEATHER, -w, -w * 0.55, -w * 0.15 + lx * 2.0, w * 0.3, w, w + SafeMesh.FEATHER]
	var shades := [Color(HOSE.darkened(0.6), 0.0), HOSE.darkened(0.6), HOSE.darkened(0.1), HOSE.lightened(0.5),
		HOSE, HOSE.darkened(0.55), Color(HOSE.darkened(0.55), 0.0)]
	var lines := []
	for o in offsets:
		var line := PackedVector2Array()
		for k in pts.size():
			var tan := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized()
			line.append(pts[k] + tan.orthogonal() * float(o))
		lines.append(line)
	for i in lines.size() - 1:
		var ca := PackedColorArray()
		var cb := PackedColorArray()
		ca.resize(pts.size())
		cb.resize(pts.size())
		ca.fill(shades[i])
		cb.fill(shades[i + 1])
		m.band_colors(lines[i], lines[i + 1], ca, cb, false)
	# Brass clamps at each end.
	for at in [p0, p3]:
		m.circle(at, w + 3.0, BRASS.darkened(0.1))
		m.circle(at + Vector2(-3, -3), w * 0.5, BRASS_HI)


static func _stand(m: SafeMesh, lx: float) -> void:
	var foot := PumpPlaces.STAND_FOOT
	var top := PumpPlaces.NOZZLE
	# A weighted round foot, a polished pole, a red valve wheel and the nozzle's cone.
	m.fill(SafeMesh._ellipse(foot + Vector2(0, 2), Vector2(84, 20), 40), BRASS_DARK.darkened(0.3))
	m.fill(SafeMesh._ellipse(foot, Vector2(80, 17), 40), BRASS.darkened(0.05))
	m.glow(foot + Vector2(lx * 30.0, -4), Vector2(50, 8), Color(1, 0.95, 0.75, 0.6), 6, 0.3)
	m.rect_v(Rect2(foot.x - 30, foot.y - 26, 60, 26), BRASS.lightened(0.1), BRASS_DARK)
	cylinder(m, Rect2(top.x - 11, top.y + 34, 22, foot.y - top.y - 60), BRASS, lx)
	var wheel := Vector2(top.x, foot.y - 70)
	m.ring(wheel, 18.0, 26.0, PAINT)
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		m.line(wheel, wheel + Vector2(cos(a), sin(a)) * 20.0, 5.0, PAINT.darkened(0.15))
	m.circle(wheel, 7.0, BRASS)
	m.quad4(Vector2(top.x - 26, top.y + 34), Vector2(top.x + 26, top.y + 34), Vector2(top.x + 9, top.y + 4), Vector2(top.x - 9, top.y + 4),
		BRASS.darkened(0.3), BRASS.lightened(0.2), BRASS_HI, BRASS)
	m.rect_v(Rect2(top.x - 30, top.y + 32, 60, 10), BRASS.lightened(0.2), BRASS_DARK)
	# The bunch's weight: a brass bell on the floor.
	var t := PumpPlaces.TETHER
	m.quad4(Vector2(t.x - 22, t.y - 34), Vector2(t.x + 22, t.y - 34), Vector2(t.x + 40, t.y), Vector2(t.x - 40, t.y),
		BRASS.lightened(0.1), BRASS, BRASS_DARK, BRASS_DARK.darkened(0.2))
	m.circle(Vector2(t.x, t.y - 40), 9.0, BRASS.lightened(0.2))


## A wicker basket of spare, limp balloons by the pump's foot.
static func _basket(m: SafeMesh, _lx: float) -> void:
	var r := PumpPlaces.BASKET
	var limp := [Color("3fd0a8"), Color("ff4f96"), Color("8a7dff"), Color("ff4f96"), Color("3fd0a8")]
	for k in limp.size():
		var at := Vector2(r.position.x + 30 + k * 28, r.position.y + 6 - (k % 2) * 10)
		var c: Color = limp[k]
		m.fill(SafeMesh._ellipse(at, Vector2(16, 24), 16), c.darkened(0.25))
		m.circle(at + Vector2(-5, -9), 4.0, Color(1, 1, 1, 0.35))
	var wicker := Color(0.62, 0.45, 0.25)
	m.quad4(r.position, Vector2(r.end.x, r.position.y), Vector2(r.end.x - 14, r.end.y), Vector2(r.position.x + 14, r.end.y),
		wicker, wicker, wicker.darkened(0.5), wicker.darkened(0.5))
	for k in 5:
		var y := r.position.y + 10 + k * 14
		m.line(Vector2(r.position.x + 4 + k * 2.5, y), Vector2(r.end.x - 4 - k * 2.5, y), 3.0, wicker.darkened(0.35))
	m.rect_v(Rect2(r.position.x - 4, r.position.y - 6, r.size.x + 8, 10), wicker.lightened(0.15), wicker.darkened(0.2))


# --- The gauge ---

## The gauge's static face: a lit brass bezel, a cream dial with ticks and a printed red tail
## past the end of the scale. The push wedge and the needle move above it (PumpStage).
static func _gauge_face(m: SafeMesh, lx: float) -> void:
	var c := PumpPlaces.GAUGE_AT
	var r := PumpPlaces.GAUGE_R
	var to_light := Vector2(lx, -0.8).normalized()
	m.soft_shadow(Rect2(c - Vector2(r + 22, r + 22) + Vector2(6, 10), Vector2(r + 22, r + 22) * 2.0), r + 22, 18.0, Color(0, 0, 0, 0.45))
	SafeDoor.lit_ring(m, c, r + 6.0, r + 22.0, BRASS_HI, BRASS_DARK, to_light)
	SafeDoor.lit_ring(m, c, r, r + 6.0, BRASS_DARK.darkened(0.3), BRASS.lightened(0.2), to_light)
	var face := SafeMesh._ellipse(c, Vector2(r, r), 64)
	m.fill(face, FACE)
	m.glow(c + Vector2(0, r * 0.25), Vector2(r, r * 0.8), Color(0.55, 0.45, 0.35, 0.18), 8, 0.5)
	for k in 21:
		var a := gauge_angle(float(k) / 20.0)
		var d := Vector2(cos(a), sin(a))
		var long := k % 5 == 0
		m.line(c + d * (r - (24.0 if long else 14.0)), c + d * (r - 6.0), 4.0 if long else 2.5, INK)
	# Knurled screws round the bezel.
	for k in 4:
		var a := PI * 0.25 + PI * 0.5 * k
		SafePlaces.rivet(m, c + Vector2(cos(a), sin(a)) * (r + 14.0), 4.0, BRASS, to_light)


## The needle: a tapered ink blade with a counterweight and a brass hub, pointing along +x from
## the origin (its node turns it).
static func paint_needle(m: SafeMesh) -> void:
	var r := PumpPlaces.GAUGE_R
	m.fill(PackedVector2Array([Vector2(-26, -7), Vector2(r - 16, -2.0), Vector2(r - 6, 0), Vector2(r - 16, 2.0), Vector2(-26, 7)]), INK)
	m.fill(PackedVector2Array([Vector2(r - 34, -3), Vector2(r - 6, 0), Vector2(r - 34, 3)]), Color(0.85, 0.15, 0.12))
	m.circle(Vector2(-22, 0), 10.0, INK)
	m.circle(Vector2.ZERO, 14.0, BRASS_DARK)
	m.circle(Vector2.ZERO, 10.0, BRASS)
	m.circle(Vector2(-3, -3), 4.0, BRASS_HI)


## The plunger: a polished rod and a T handle with red grips; its origin is the handle's centre,
## the rod running down (+y).
static func paint_plunger(m: SafeMesh, lx: float) -> void:
	cylinder(m, Rect2(-9, 0, 18, 150), Color(0.85, 0.82, 0.76), lx)
	cylinder_h(m, Rect2(-100, -12, 200, 24), BRASS, lx)
	for side in [-1.0, 1.0]:
		var g := Rect2(side * 100.0 - 34.0, -17, 68, 34)
		m.round_rect(g, 14.0, PAINT.lightened(0.3), PAINT.darkened(0.5))
		m.line(Vector2(g.position.x + 12, g.position.y + 8), Vector2(g.end.x - 12, g.position.y + 8), 3.0, Color(1, 1, 1, 0.3))
	m.circle(Vector2.ZERO, 18.0, BRASS_DARK)
	m.circle(Vector2.ZERO, 13.0, BRASS)
	m.circle(Vector2(-4, -4), 5.0, BRASS_HI)


## The collar's lip, drawn over the plunger's rod so the rod runs into the pump.
static func paint_collar_lip(m: SafeMesh, lx: float) -> void:
	var c := PumpPlaces.COLLAR
	cylinder(m, Rect2(c.position.x - 4, c.position.y - 6, c.size.x + 8, 14), BRASS, lx)
