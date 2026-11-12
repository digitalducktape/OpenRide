class_name PullIntroArt
extends Control
## The intro card's picture (#79, UI polish): the sled side-on, its weight box over the rear
## with an arrow showing it slides forward, and the chain running off to the left toward the
## bike. Drawn once (no `_process`), in the game's look. Shapes only: blocks, a frame and an
## arrow, nothing that reads as anything else at a small size (ART_BIBLE §10).

const SIZE := Vector2(460, 170)  ## the drawing's own units
const SCALE := 1.75  ## on the card

var look: GameTheme


func _init(theme: GameTheme) -> void:
	look = theme
	custom_minimum_size = SIZE * SCALE
	size = SIZE * SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(SCALE, SCALE))
	var ground := 150.0
	var ink := look.ink
	# The track, and tread marks.
	draw_rect(Rect2(0, ground, SIZE.x, 6), Color("8a5236"))
	for i in 12:
		draw_rect(Rect2(20 + i * 38, ground + 10, 18, 4), Color("8a5236", 0.5))
	# The chain from the left edge to the hitch.
	var hitch := Vector2(150, ground - 34)
	for i in 9:
		var p := Vector2(10, ground - 26).lerp(hitch, i / 8.0)
		draw_arc(p, 6, 0, TAU, 12, Color("c9ced6"), 3.0, true)
	# The pan and runners.
	_poly([Vector2(150, ground - 6), Vector2(430, ground - 6), Vector2(440, ground - 22), Vector2(140, ground - 22)], Color("2c2f33"), ink)
	_poly([Vector2(140, ground - 22), Vector2(150, ground - 40), Vector2(170, ground - 40), Vector2(165, ground - 22)], PullMeshes.SLED_YELLOW, ink)
	# The frame.
	for x in [180.0, 420.0]:
		draw_rect(Rect2(x - 5, ground - 96, 10, 74), PullMeshes.SLED_YELLOW)
	draw_rect(Rect2(175, ground - 100, 250, 10), PullMeshes.SLED_YELLOW)
	# The weight box near the rear: slate blocks in a cage.
	var box := Rect2(310, ground - 86, 96, 64)
	for row in 2:
		for col in 2:
			draw_rect(Rect2(box.position + Vector2(col * 48 + 3, row * 32 + 3), Vector2(42, 26)),
				PullMeshes.WEIGHT.lightened(0.08 * ((row + col) % 2)))
	draw_rect(box, ink, false, 4.0)
	# The arrow: the box slides toward the front as the sled goes.
	var y := ground - 122
	draw_line(Vector2(380, y), Vector2(220, y), look.accent, 10.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(196, y), Vector2(226, y - 18), Vector2(226, y + 18)]), look.accent)


func _poly(points: Array, fill: Color, outline: Color) -> void:
	var packed := PackedVector2Array(points)
	draw_colored_polygon(packed, fill)
	packed.append(points[0])
	draw_polyline(packed, outline, 3.0, true)
