class_name SafeDoor
extends Node2D
## Safe Cracker's door (#41): the static steel slab under the live dial, in door coordinates
## (centred on the door). One batch, redrawn only on a place, lights-count or hint change
## (`SafeDial.refresh`); the swing is the door shader (`safe_door.gdshader`), so opening never
## redraws it.
##
## Top-lit steel with the room's key light on one side, a bevel bright on the lit edges and
## dark on the far ones, brushed streaks, a machined inner groove, rivets, two hinges, a
## four-spoke handle wheel under the tumbler lights, sockets for the lights, a knurled bezel
## round a dark dial face with its ticks, and the target's plate. The back of the far edge is
## marked with depth 1, so its thickness shows as the door turns.

const D := SafeDial.DOOR
const HANDLE := Vector2(371, 245)
const HANDLE_R := 45.0
const HINGE_Y := [-200.0, 200.0]

var dial: SafeDial


func _draw() -> void:
	var m := MeshBatch2D.new()
	build(m)
	m.flush(self)


func build(m: MeshBatch2D) -> void:
	var colour := dial.colour
	var accent := dial.accent
	var index := dial.place_index
	var to_light := SafePlaces.to_light(index)
	var light_col: Color = SafePlaces.light(index).color
	var half := D.size * 0.5
	# The far edge's thickness: the front at depth 0, the back at 1 (behind the face, so hidden
	# until the door turns).
	var edge := colour.darkened(0.45)
	var a := m.vert(Vector2(D.end.x - 1.0, D.position.y + 20.0), edge.lightened(0.15))
	m.vert(Vector2(D.end.x - 1.0, D.end.y - 20.0), edge.darkened(0.3))
	m.depth = 1.0
	m.vert(Vector2(D.end.x - 1.0, D.end.y - 20.0), edge.darkened(0.45))
	m.vert(Vector2(D.end.x - 1.0, D.position.y + 20.0), edge)
	m.tri(a, a + 1, a + 2)
	m.tri(a, a + 2, a + 3)
	m.depth = 0.0
	# The slab: top-lit steel, the key light's side brighter.
	m.shade = SafePlaces.steel_shade(to_light, half, light_col)
	# A hole under the dial's face (r + 8 covers it), so no pixels go on steel nobody sees.
	m.holed_round_rect(D, 22.0, colour.lightened(0.1), colour.darkened(0.2), Vector2.ZERO, SafeDial.R)
	_streaks(m, colour, index)
	m.bevel(D, 22.0, 5.0, to_light, colour.lightened(0.5).lerp(light_col, 0.25), colour.darkened(0.55))
	# A machined groove 28 in: dark on the lit side, bright on the far side (it's cut in).
	m.bevel(D.grow(-28.0), 12.0, 3.0, -to_light, colour.lightened(0.3), colour.darkened(0.45))
	m.shade = Callable()
	for p in _rivets():
		MeshBatch2D.rivet(m, p, 10.0, colour, to_light)
	_hinges(m, colour, to_light)
	_handle(m, colour, to_light)
	_sockets(m, colour, to_light)
	_dial_face(m, colour, to_light)
	_plate(m, accent)


## 36 thin horizontal streaks at 4-6% white, seeded by the place.
func _streaks(m: MeshBatch2D, colour: Color, index: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 101 + index
	for i in 36:
		var y := rng.randf_range(D.position.y + 14.0, D.end.y - 14.0)
		var x0 := rng.randf_range(D.position.x + 16.0, D.end.x - 220.0)
		var x1 := minf(x0 + rng.randf_range(120.0, 520.0), D.end.x - 16.0)
		var white := rng.randf() < 0.65
		m.line(Vector2(x0, y), Vector2(x1, y), rng.randf_range(1.2, 2.2),
			Color(1, 1, 1, rng.randf_range(0.04, 0.06)) if white else Color(0, 0, 0, 0.06))


## The four corners and a few along the top and bottom, clear of the plate, bezel and handle.
func _rivets() -> Array[Vector2]:
	var out: Array[Vector2] = []
	var inset := 40.0
	# Not the bottom right: the handle wheel is there.
	for p in [Vector2(D.position.x + inset, D.position.y + inset), Vector2(D.end.x - inset, D.position.y + inset),
			Vector2(D.position.x + inset, D.end.y - inset)]:
		out.append(p)
	for x in [-230.0, 230.0]:
		out.append(Vector2(x, D.position.y + inset))
		out.append(Vector2(x, D.end.y - inset))
	return out


## Two hinge barrels on the hinge (left) edge: lit cylinders with caps and a pin.
func _hinges(m: MeshBatch2D, colour: Color, to_light: Vector2) -> void:
	var steel := colour.lightened(0.15)
	var hi := steel.lightened(0.45)
	var lo := steel.darkened(0.55)
	for y: float in HINGE_Y:
		var r := Rect2(D.position.x - 22.0, y - 55.0, 30.0, 110.0)
		m.soft_shadow(Rect2(r.position + Vector2(6, 8), r.size), 8.0, 10.0, Color(0, 0, 0, 0.35))
		var left := lo if to_light.x > 0.0 else hi
		var right := hi if to_light.x > 0.0 else lo
		m.rect_h(Rect2(r.position.x, r.position.y, r.size.x * 0.4, r.size.y), left, steel.lightened(0.25))
		m.rect_h(Rect2(r.position.x + r.size.x * 0.4, r.position.y, r.size.x * 0.6, r.size.y), steel.lightened(0.25), right)
		for cap_y in [r.position.y, r.end.y - 8.0, y - 2.0]:
			m.rect_v(Rect2(r.position.x - 2.0, cap_y, r.size.x + 4.0, 8.0 if cap_y != y - 2.0 else 4.0), hi, lo)
		MeshBatch2D.rivet(m, Vector2(r.get_center().x, r.position.y - 6.0), 6.0, colour, to_light)


## A compact four-spoke handle wheel under the tumbler lights.
func _handle(m: MeshBatch2D, colour: Color, to_light: Vector2) -> void:
	var c := HANDLE
	var steel := colour.lightened(0.35)
	m.glow(c + Vector2(8, 12), Vector2(HANDLE_R + 16, HANDLE_R + 16), Color(0, 0, 0, 0.45), 8, 0.5)
	for k in 4:
		var a := PI / 4.0 + k * PI / 2.0
		var dir := Vector2(cos(a), sin(a))
		m.line(c + dir * 12.0, c + dir * (HANDLE_R - 4.0), 9.0, steel.darkened(0.2))
		m.line(c + dir * 12.0 + dir.orthogonal() * -2.0, c + dir * (HANDLE_R - 6.0) + dir.orthogonal() * -2.0, 3.0, steel.lightened(0.3))
		m.circle(c + dir * HANDLE_R, 8.0, steel.darkened(0.1))
		m.circle(c + dir * HANDLE_R + to_light * 3.0, 3.5, steel.lightened(0.5))
	MeshBatch2D.lit_ring(m, c, HANDLE_R - 6.0, HANDLE_R + 3.0, steel.lightened(0.4), steel.darkened(0.45), to_light)
	m.circle(c, 16.0, steel.darkened(0.35))
	m.circle(c + Vector2(-2, -3), 12.0, steel.lightened(0.2))
	m.circle(c + Vector2(-4, -5), 4.0, Color(1, 1, 1, 0.55))


## Recessed sockets for the tumbler lights (dark on the lit side: they're cut in).
func _sockets(m: MeshBatch2D, colour: Color, to_light: Vector2) -> void:
	for i in dial.tumblers_total:
		var at := SafeDial.light_at(i, dial.tumblers_total)
		MeshBatch2D.lit_ring(m, at, SafeDial.LIGHT_R + 4.0, SafeDial.LIGHT_R + 10.0, colour.darkened(0.5), colour.lightened(0.35), to_light)


## The bezel (a knurled steel ring), the dark dial face with a faint centre lift, the ticks.
func _dial_face(m: MeshBatch2D, colour: Color, to_light: Vector2) -> void:
	var r := SafeDial.R
	# The bezel's shadow: only its rim shows past the bezel (the face disc, r + 8, covers the
	# rings inside r - 10 even 19 px off centre).
	m.glow(Vector2(10, 16), Vector2(r + 70.0, r + 70.0), Color(0, 0, 0, 0.5), 10, 0.75, r - 10.0)
	MeshBatch2D.lit_ring(m, Vector2.ZERO, r + 22.0, r + 40.0, colour.lightened(0.15), colour.darkened(0.6), to_light)
	MeshBatch2D.lit_ring(m, Vector2.ZERO, r + 8.0, r + 24.0, colour.lightened(0.5), colour.darkened(0.25), to_light)
	# The knurl: short radial ridges on the outer ring.
	for k in 120:
		var a := TAU * k / 120.0
		var dir := Vector2(cos(a), sin(a))
		var lit := 0.5 + 0.5 * dir.dot(to_light)
		m.line(dir * (r + 25.0), dir * (r + 38.0), 2.0, Color(0, 0, 0, 0.28) if k % 2 == 0 else Color(1, 1, 1, 0.1 + 0.14 * lit))
	m.circle(Vector2.ZERO, r + 8.0, Color(0.06, 0.06, 0.08))
	m.glow(Vector2(-30, -40), Vector2(r * 0.9, r * 0.9), Color(0.16, 0.17, 0.2, 0.9), 10)
	for i in range(0, 101, 5):
		var a := SafeDial.angle_for(float(i))
		var dir := Vector2(cos(a), sin(a))
		var major := i % 10 == 0
		m.line(dir * (r - (34.0 if major else 20.0)), dir * (r - 4.0),
			5.0 if major else 3.0, Color(0.85, 0.85, 0.8) if major else Color(0.5, 0.5, 0.5))


## The target's plate: soot with a brass edge (grey when the target is hidden), two brass pins.
func _plate(m: MeshBatch2D, accent: Color) -> void:
	var plate := SafeDial.TARGET_PLATE
	var edge := accent if not dial.target_hidden else Color(0.75, 0.78, 0.85)
	m.soft_shadow(Rect2(plate.position + Vector2(4, 8), plate.size), 16.0, 12.0, Color(0, 0, 0, 0.45))
	m.round_rect(plate, 16.0, edge.lightened(0.2), edge.darkened(0.25))
	var inner := Rect2(plate.position + Vector2(4, 4), plate.size - Vector2(8, 11))
	m.round_rect(inner, 12.0, Color(SafeDial.INK.lightened(0.06), 0.97), Color(SafeDial.INK, 0.97))
	for x in [plate.position.x + 14.0, plate.end.x - 14.0]:
		m.circle(Vector2(x, plate.get_center().y - 2.0), 4.5, edge.darkened(0.3))
		m.circle(Vector2(x - 1.0, plate.get_center().y - 3.0), 2.5, edge.lightened(0.4))


