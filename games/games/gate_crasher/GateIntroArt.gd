class_name GateIntroArt
extends Control
## The intro card's picture (#80): a painted fence side-on with its flower box and take-off line,
## an arrow rising at the line and the arc of a jump over the fence, which is the whole game. Drawn
## once (no `_process`), in the game's look. Shapes only: posts, poles, dashes and an arrow, no
## figure, nothing that reads as anything else at a small size (ART_BIBLE §10).

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
	# The sand and rake marks.
	draw_rect(Rect2(0, ground, SIZE.x, 8), GateMeshes.SAND)
	for i in 12:
		draw_rect(Rect2(14 + i * 38, ground + 12, 20, 3), Color(GateMeshes.SAND, 0.5))
	# The take-off line, and the arrow rising from it: stand here.
	var line_x := 96.0
	draw_rect(Rect2(line_x - 26, ground - 3, 52, 8), GateMeshes.WHITE)
	draw_line(Vector2(line_x, ground - 12), Vector2(line_x, ground - 70), look.accent, 10.0, true)
	draw_colored_polygon(PackedVector2Array([Vector2(line_x, ground - 96), Vector2(line_x - 20, ground - 64),
		Vector2(line_x + 20, ground - 64)]), look.accent)
	# The fence: two standards, three banded poles, a flower box at the foot.
	var fx := 318.0
	for x: float in [fx - 66.0, fx + 66.0]:
		draw_rect(Rect2(x - 4, ground - 112, 8, 112), GateMeshes.WHITE)
		draw_rect(Rect2(x - 5, ground - 116, 10, 14), GateMeshes.RAIL_SETS[0][0])
	for i in 3:
		var y := ground - 36 - i * 28
		draw_rect(Rect2(fx - 62, y - 5, 124, 10), ink)
		for b in 6:
			draw_rect(Rect2(fx - 60 + b * 20, y - 3, 20, 6), GateMeshes.RAIL_SETS[0][b % 2])
	draw_rect(Rect2(fx - 58, ground - 16, 116, 16), Color("6b4a2c"))
	for i in 11:
		draw_circle(Vector2(fx - 52 + i * 10.4, ground - 19), 6.0,
			GateMeshes.FLOWERS[i % GateMeshes.FLOWERS.size()] if i % 2 else GateMeshes.HEDGE)
	# The jump: a dashed arc from beyond the line over the fence.
	var from := Vector2(170, ground - 10)
	var to := Vector2(450, ground - 10)
	for i in 15:
		draw_line(_arc(from, to, (i + 0.15) / 15.0), _arc(from, to, (i + 0.7) / 15.0), GameTheme.TARGET, 6.0, true)


func _arc(from: Vector2, to: Vector2, u: float) -> Vector2:
	return Vector2(lerpf(from.x, to.x, u), from.y - 4.0 * u * (1.0 - u) * 128.0)
