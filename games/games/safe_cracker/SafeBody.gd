class_name SafeBody
extends Node2D
## The safe's body and the vault behind its door (#41), centred on the door: static, redrawn
## only when the place changes. The door and dial are a child (`SafeDial`).

const BODY := Rect2(-490, -370, 980, 740)
const DOOR := Rect2(-440, -320, 880, 640)

var place_index := 0
var gold_shine := 0.0  ## 0-1, how brightly the vault's gold gleams (set as the door opens)


func set_place(index: int) -> void:
	place_index = index
	queue_redraw()


func _draw() -> void:
	var colour: Color = SafePlaces.place(place_index).safe
	var shadow := StyleBoxFlat.new()
	shadow.bg_color = Color(0, 0, 0, 0.35)
	shadow.set_corner_radius_all(34)
	draw_style_box(shadow, Rect2(BODY.position + Vector2(14, 22), BODY.size))
	var body := StyleBoxFlat.new()
	body.bg_color = colour.darkened(0.25)
	body.set_corner_radius_all(30)
	body.border_color = colour.lightened(0.15)
	body.set_border_width_all(8)
	draw_style_box(body, BODY)
	# The vault inside the door: dark, with stacked gold bars.
	draw_rect(DOOR, Color(0.05, 0.04, 0.04))
	var bar := Color(0.95, 0.75, 0.25)
	for row in 4:
		for col in 5 - row:
			var x := DOOR.position.x + 90 + col * 150 + row * 75
			var y := DOOR.end.y - 70 - row * 62
			draw_rect(Rect2(x, y, 140, 52), bar.darkened(row * 0.1))
			draw_rect(Rect2(x + 8, y + 6, 124, 14), bar.lightened(0.35))
	for i in 5:  # a gleam
		draw_circle(Vector2(DOOR.position.x + 200 + i * 130, DOOR.end.y - 280 + (i % 2) * 60), 5, Color(1, 1, 0.8, 0.8))
