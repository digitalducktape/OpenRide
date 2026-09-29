class_name StarRow
extends Control
## Three stars, `stars` of them lit. Drawn as shapes, so no font needs the glyph.

var stars := 0:
	set(value):
		stars = clampi(value, 0, 3)
		queue_redraw()
var star_size := 56.0:
	set(value):
		star_size = value
		custom_minimum_size = Vector2(star_size * 3.4, star_size)
		queue_redraw()


func _init(lit := 0, size_px := 56.0) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	stars = lit
	star_size = size_px


func _draw() -> void:
	for i in 3:
		var centre := Vector2(star_size * (0.5 + i * 1.2), star_size * 0.5)
		draw_colored_polygon(_star(centre, star_size * 0.5), HudTheme.STAR_ON if i < stars else HudTheme.STAR_OFF)


static func _star(centre: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 10:
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI / 2 + i * PI / 5
		points.append(centre + Vector2(cos(angle), sin(angle)) * r)
	return points
