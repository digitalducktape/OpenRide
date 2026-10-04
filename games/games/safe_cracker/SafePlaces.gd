class_name SafePlaces
extends RefCounted
## The places Safe Cracker's safes are found in (#41). Each is a palette and a few shapes drawn
## in code, so there are no assets: the picture is small enough to redraw only when the safe
## changes. Names are plain descriptions; nothing here refers to any existing game or film.

const SIZE := Vector2(1920, 1080)
const FLOOR_Y := 905.0

const PLACES := [
	{"id": "office", "name": "Night office", "wall": Color(0.1, 0.17, 0.22), "wall2": Color(0.06, 0.1, 0.14),
		"floor": Color(0.1, 0.08, 0.07), "safe": Color(0.34, 0.37, 0.4), "accent": Color(0.95, 0.75, 0.35)},
	{"id": "bank", "name": "Bank vault", "wall": Color(0.36, 0.38, 0.41), "wall2": Color(0.24, 0.26, 0.29),
		"floor": Color(0.16, 0.16, 0.18), "safe": Color(0.5, 0.52, 0.55), "accent": Color(0.85, 0.65, 0.25)},
	{"id": "museum", "name": "Museum hall", "wall": Color(0.62, 0.56, 0.46), "wall2": Color(0.5, 0.44, 0.36),
		"floor": Color(0.33, 0.25, 0.2), "safe": Color(0.25, 0.3, 0.36), "accent": Color(0.9, 0.8, 0.5)},
	{"id": "cabin", "name": "Ship's cabin", "wall": Color(0.38, 0.25, 0.15), "wall2": Color(0.28, 0.18, 0.11),
		"floor": Color(0.2, 0.13, 0.09), "safe": Color(0.22, 0.3, 0.28), "accent": Color(0.9, 0.7, 0.3)},
	{"id": "lab", "name": "Laboratory", "wall": Color(0.62, 0.74, 0.7), "wall2": Color(0.5, 0.62, 0.58),
		"floor": Color(0.3, 0.36, 0.36), "safe": Color(0.7, 0.72, 0.74), "accent": Color(0.4, 0.9, 0.6)},
	{"id": "library", "name": "Old library", "wall": Color(0.3, 0.19, 0.14), "wall2": Color(0.2, 0.12, 0.09),
		"floor": Color(0.14, 0.09, 0.07), "safe": Color(0.28, 0.24, 0.3), "accent": Color(0.9, 0.72, 0.3)},
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


## Draws the room onto `ci`: wall, floor and props. The safe covers the middle, so the props sit
## to either side and behind it.
static func draw_room(ci: CanvasItem, index: int) -> void:
	var p := place(index)
	var wall: Color = p.wall
	var wall2: Color = p.wall2
	# A wall that darkens toward the floor, in a few bands.
	for i in 6:
		ci.draw_rect(Rect2(0, i * FLOOR_Y / 6.0, SIZE.x, FLOOR_Y / 6.0 + 1.0), wall.lerp(wall2, i / 5.0))
	ci.draw_rect(Rect2(0, FLOOR_Y, SIZE.x, SIZE.y - FLOOR_Y), p.floor)
	ci.draw_rect(Rect2(0, FLOOR_Y, SIZE.x, 6), Color(0, 0, 0, 0.35))
	match str(p.id):
		"office":
			_office(ci, p)
		"bank":
			_bank(ci, p)
		"museum":
			_museum(ci, p)
		"cabin":
			_cabin(ci, p)
		"lab":
			_lab(ci, p)
		"library":
			_library(ci, p)


static func _office(ci: CanvasItem, p: Dictionary) -> void:
	# A rainy window on the left, a desk lamp's glow on the right.
	ci.draw_rect(Rect2(50, 300, 340, 420), Color(0.05, 0.08, 0.14))
	ci.draw_rect(Rect2(50, 300, 340, 420), Color(0.4, 0.45, 0.5), false, 10)
	ci.draw_line(Vector2(220, 300), Vector2(220, 720), Color(0.4, 0.45, 0.5), 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var x := rng.randf_range(62, 378)
		var y := rng.randf_range(312, 680)
		ci.draw_line(Vector2(x, y), Vector2(x - 6, y + rng.randf_range(20, 40)), Color(0.6, 0.7, 0.85, 0.35), 2)
	for r in 6:
		ci.draw_circle(Vector2(1680, 560), 190.0 - r * 28.0, Color(1.0, 0.8, 0.4, 0.05 + r * 0.012))
	ci.draw_rect(Rect2(1500, 780, 420, 125), Color(0.2, 0.13, 0.09))
	ci.draw_rect(Rect2(1660, 640, 14, 140), Color(0.15, 0.15, 0.17))
	ci.draw_circle(Vector2(1667, 628), 34, p.accent)


static func _bank(ci: CanvasItem, p: Dictionary) -> void:
	for x in range(0, 1920, 160):
		ci.draw_line(Vector2(x, 0), Vector2(x, FLOOR_Y), Color(0, 0, 0, 0.25), 4)
		for y in range(60, 880, 120):
			ci.draw_circle(Vector2(x + 14, y), 6, Color(0.7, 0.72, 0.75, 0.8))
			ci.draw_circle(Vector2(x + 146, y), 6, Color(0.7, 0.72, 0.75, 0.8))
	for i in 7:  # brass bars on the left
		ci.draw_rect(Rect2(60 + i * 52, 330, 22, 520), p.accent.darkened(0.2))
	ci.draw_rect(Rect2(40, 330, 380, 22), p.accent)
	ci.draw_rect(Rect2(40, 828, 380, 22), p.accent)


static func _museum(ci: CanvasItem, p: Dictionary) -> void:
	var frames := [Rect2(70, 330, 300, 380), Rect2(1550, 330, 300, 380)]
	var tints := [Color(0.55, 0.35, 0.3), Color(0.3, 0.45, 0.55)]
	for i in 2:
		var r: Rect2 = frames[i]
		ci.draw_rect(r.grow(18), p.accent.darkened(0.3))
		ci.draw_rect(r, tints[i])
		ci.draw_circle(r.get_center() + Vector2(0, -30), 70, tints[i].lightened(0.35))
		ci.draw_rect(Rect2(r.position.x + 40, r.position.y + 230, r.size.x - 80, 100), tints[i].darkened(0.3))
	ci.draw_rect(Rect2(1560, 770, 160, 135), Color(0.75, 0.72, 0.66))  # a pedestal
	ci.draw_circle(Vector2(1640, 735), 46, Color(0.55, 0.3, 0.2))


static func _cabin(ci: CanvasItem, p: Dictionary) -> void:
	for y in range(40, 900, 70):
		ci.draw_line(Vector2(0, y), Vector2(1920, y), Color(0, 0, 0, 0.25), 3)
	ci.draw_circle(Vector2(230, 520), 150, Color(0.62, 0.5, 0.25))  # a porthole
	ci.draw_circle(Vector2(230, 520), 125, Color(0.2, 0.45, 0.6))
	ci.draw_line(Vector2(105, 560), Vector2(355, 480), Color(0.3, 0.55, 0.7), 18)
	ci.draw_line(Vector2(1700, 300), Vector2(1700, 420), Color(0.15, 0.1, 0.07), 6)  # a hanging lantern
	for r in 5:
		ci.draw_circle(Vector2(1700, 450), 130.0 - r * 24.0, Color(1.0, 0.75, 0.3, 0.05 + r * 0.015))
	ci.draw_circle(Vector2(1700, 450), 28, p.accent)


static func _lab(ci: CanvasItem, p: Dictionary) -> void:
	for side in [0, 1]:
		var x0 := 60.0 if side == 0 else 1520.0
		for shelf in 3:
			var y := 420.0 + shelf * 150.0
			ci.draw_rect(Rect2(x0, y + 100, 340, 12), Color(0.25, 0.3, 0.3))
			for k in 4:
				var c: Color = [Color(0.4, 0.85, 0.6), Color(0.9, 0.6, 0.3), Color(0.5, 0.7, 0.95), Color(0.9, 0.5, 0.6)][(k + shelf + side) % 4]
				var cx := x0 + 50 + k * 80.0
				ci.draw_rect(Rect2(cx - 10, y + 20, 20, 30), Color(0.85, 0.9, 0.9, 0.8))
				ci.draw_circle(Vector2(cx, y + 75), 28, c)
	for x in range(0, 1920, 120):
		ci.draw_line(Vector2(x, FLOOR_Y), Vector2(x - 60, 1080), Color(0, 0, 0, 0.2), 3)


static func _library(ci: CanvasItem, p: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for side in [0, 1]:
		var x0 := 40.0 if side == 0 else 1500.0
		ci.draw_rect(Rect2(x0, 260, 380, 645), Color(0.13, 0.08, 0.06))
		for shelf in 4:
			var y := 280.0 + shelf * 155.0
			var x := x0 + 14
			while x < x0 + 360:
				var w := rng.randf_range(16, 30)
				var h := rng.randf_range(90, 130)
				var tone := rng.randf()
				ci.draw_rect(Rect2(x, y + 135 - h, w, h), Color.from_hsv(rng.randf_range(0.0, 0.12) + (0.55 if tone > 0.7 else 0.0), 0.6, 0.35 + tone * 0.3))
				x += w + 2.0
			ci.draw_rect(Rect2(x0, y + 135, 380, 8), Color(0.3, 0.2, 0.12))
