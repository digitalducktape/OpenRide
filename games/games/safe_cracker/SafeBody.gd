class_name SafeBody
extends Node2D
## The safe's body and the vault behind its door (#41), centred on the door: one batch, redrawn
## only when the place changes. The door and dial are `SafeDial` (a sibling drawn after).
##
## The body is a frame round the door's hole, not a slab under the door, and the vault
## (`build_vault`) is `SafeDial`'s `Vault` layer, shown only while the door is open: the door
## covers both while it's shut, and the tablet pays for every pixel drawn, seen or not.
##
## A soft shadow cast away from the room's key light, a contact shadow and short feet; top-lit
## steel with the key light's side brighter, brushed streaks and a bevel; the dark seam round the
## door and the keepers the bolts shoot into. Inside: a lamp-lit steel vault in perspective (back
## wall, side walls, ceiling, floor), a shelf of coin stacks and a stack of gold bars with lit
## top faces.

const BODY := Rect2(-490, -370, 980, 740)
const DOOR := Rect2(-440, -320, 880, 640)
const GOLD := Color(0.95, 0.75, 0.25)
## The vault's back wall (its far end, in perspective toward the middle).
const BACK := Rect2(-320, -215, 640, 440)

var place_index := 0


func set_place(index: int) -> void:
	place_index = index
	queue_redraw()


func _draw() -> void:
	mesh_for(place_index).draw_on(self)


## The body's batch for a place, built once (`MeshBatch2D.built`).
static func mesh_for(index: int) -> MeshBatch2D:
	return MeshBatch2D.built("body:%d" % index, build_place.bind(index))


func build(m: MeshBatch2D) -> void:
	build_place(m, place_index)


static func build_place(m: MeshBatch2D, place_index: int) -> void:
	var p := SafePlaces.place(place_index)
	var colour: Color = p.safe
	var to_light := SafePlaces.to_light(place_index)
	var light_col: Color = SafePlaces.light(place_index).color
	var shadow_col := Color((p.wall2 as Color).darkened(0.7), 0.6)
	# Cast away from the light, onto the wall; a dark contact shadow on the floor.
	var cast := -to_light * 46.0 + Vector2(0, 22)
	m.soft_shadow(Rect2(BODY.position + cast, BODY.size), 34.0, 50.0, shadow_col, 90.0)
	m.glow(Vector2(0, BODY.end.y + 26.0), Vector2(600, 46), Color(0, 0, 0, 0.6), 10, 0.4)
	for x in [-420.0, 340.0]:
		m.quad(Vector2(x, BODY.end.y - 10.0), Vector2(x + 80.0, BODY.end.y - 10.0),
			Vector2(x + 70.0, BODY.end.y + 26.0), Vector2(x + 10.0, BODY.end.y + 26.0), colour.darkened(0.65))
	m.shade = SafePlaces.steel_shade(to_light, BODY.size * 0.5, light_col)
	m.round_frame(BODY, 30.0, DOOR.grow(10.0), 30.0, colour.darkened(0.05), colour.darkened(0.4))
	var rng := RandomNumberGenerator.new()
	rng.seed = 211 + place_index
	for i in 30:
		var y := rng.randf_range(BODY.position.y + 12.0, BODY.end.y - 12.0)
		var x0 := rng.randf_range(BODY.position.x + 14.0, BODY.end.x - 200.0)
		m.line(Vector2(x0, y), Vector2(minf(x0 + rng.randf_range(100.0, 600.0), BODY.end.x - 14.0), y),
			rng.randf_range(1.2, 2.0), Color(1, 1, 1, rng.randf_range(0.04, 0.06)))
	m.bevel(BODY, 30.0, 6.0, to_light, colour.lightened(0.45).lerp(light_col, 0.35), colour.darkened(0.7))
	m.shade = Callable()
	# The seam round the door: a dark gap the door sits in (a ring: the door or the vault fills it).
	m.round_frame(DOOR.grow(10.0), 30.0, DOOR, 22.0, Color(0.03, 0.03, 0.035), Color(0.02, 0.02, 0.025))
	for y: float in SafeDial.BOLT_Y:
		m.rect(Rect2(DOOR.end.x + 8.0, y - 15.0, 34.0, 30.0), Color(0.02, 0.02, 0.025))
		m.rect(Rect2(DOOR.end.x + 8.0, y + 13.0, 34.0, 2.0), colour.lightened(0.2))


## The vault behind the door, filling the door's opening (drawn by `SafeDial`'s `Vault` layer).
static func build_vault(m: MeshBatch2D, colour: Color) -> void:
	var steel := colour.darkened(0.55).lerp(Color(0.25, 0.18, 0.1), 0.25)
	var warm := Color(1.0, 0.78, 0.45)
	var d := DOOR
	var tl := d.position
	var tr := Vector2(d.end.x, d.position.y)
	var br := d.end
	var bl := Vector2(d.position.x, d.end.y)
	var btl := BACK.position
	var btr := Vector2(BACK.end.x, BACK.position.y)
	var bbr := BACK.end
	var bbl := Vector2(BACK.position.x, BACK.end.y)
	m.quad4(tl, tr, btr, btl, steel.darkened(0.5), steel.darkened(0.5), steel.darkened(0.2), steel.darkened(0.2))
	m.quad4(tl, btl, bbl, bl, steel.darkened(0.35), steel.lerp(warm, 0.08), steel.lerp(warm, 0.05), steel.darkened(0.45))
	m.quad4(btr, tr, br, bbr, steel.lerp(warm, 0.06), steel.darkened(0.4), steel.darkened(0.5), steel.darkened(0.1))
	m.quad4(bbl, bbr, br, bl, steel.lerp(warm, 0.22), steel.lerp(warm, 0.22), steel.darkened(0.15), steel.darkened(0.15))
	m.rect_v(BACK, steel.lerp(warm, 0.18), steel.darkened(0.1))
	# The vault's lamp at the top of the back wall, and its pool.
	m.glow(Vector2(0, BACK.position.y + 30.0), Vector2(520, 360), Color(warm, 0.3), 12)
	m.rect_v(Rect2(-70, BACK.position.y + 4.0, 140, 10), Color(1.0, 0.95, 0.8), Color(1.0, 0.8, 0.5))
	# Seams where the walls meet.
	for pair in [[tl, btl], [tr, btr], [br, bbr], [bl, bbl]]:
		m.line(pair[0], pair[1], 2.0, Color(0, 0, 0, 0.35))
	# A shelf across the back wall with coin stacks.
	var shelf_y := -20.0
	m.quad(Vector2(BACK.position.x, shelf_y - 14.0), Vector2(BACK.end.x, shelf_y - 14.0),
		Vector2(BACK.end.x + 30.0, shelf_y), Vector2(BACK.position.x - 30.0, shelf_y), steel.lightened(0.15).lerp(warm, 0.15))
	m.rect_v(Rect2(BACK.position.x - 30.0, shelf_y, BACK.size.x + 60.0, 14.0), steel.lightened(0.05), steel.darkened(0.3))
	for i in 5:
		var x := -40.0 + i * 64.0
		var h := 26.0 + (i * 17 % 30)
		var r := Rect2(x - 22.0, shelf_y - 8.0 - h, 44.0, h)
		m.rect_h(r, GOLD.darkened(0.25), GOLD.lightened(0.15))
		for k in int(h / 6.0):
			m.rect(Rect2(r.position.x, r.end.y - 6.0 * (k + 1), r.size.x, 1.2), Color(0.45, 0.3, 0.05, 0.6))
		m.fill(MeshBatch2D._ellipse(Vector2(x, r.position.y), Vector2(22, 7), 18), GOLD.lightened(0.35))
	# The stack of bars on the floor: four, three, two, one; each a lit top face and a front face.
	m.glow(Vector2(120, 210), Vector2(460, 170), Color(1.0, 0.8, 0.35, 0.22), 10)
	for row in 4:
		for col in 4 - row:
			var x := -150.0 + col * 128.0 + row * 64.0
			var y := 268.0 - row * 46.0
			_bar(m, Vector2(x, y), row)


## A gold bar: front face (120 x 34) at `front` (its top-left), the top face going back.
static func _bar(m: MeshBatch2D, front: Vector2, row: int) -> void:
	var w := 120.0
	var h := 34.0
	var back := Vector2(10.0, -14.0)
	var face := GOLD.darkened(0.08 + 0.04 * (3 - row))
	m.quad(front + back * 0.0 + Vector2(6, 0), front + Vector2(w - 6, 0), front + Vector2(w - 6, 0) + back, front + Vector2(6, 0) + back, GOLD.lightened(0.35))
	m.rect_v(Rect2(front, Vector2(w, h)), face, face.darkened(0.3))
	m.rect(Rect2(front + Vector2(8, 5), Vector2(w - 16, 3)), Color(1, 0.97, 0.8, 0.55))
	m.rect(Rect2(front + Vector2(0, h - 3), Vector2(w, 3)), Color(0.3, 0.18, 0.02, 0.6))
