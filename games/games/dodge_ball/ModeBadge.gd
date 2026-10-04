extends Control
## The intro card's picture of the chosen mode, as a little loop: a ball rolls down a lane at a
## bike, and the bike swerves out of its way (Dodge, a red ball) or into it (Catch, a gold ball
## that bursts into a sparkle). Drawn with shapes, so no font glyph or image is needed.

const SIZE := Vector2(560, 120)
const LOOP_SEC := 2.2

var catch_mode := false
var _t := 0.0


func _init(is_catch := false) -> void:
	catch_mode = is_catch
	custom_minimum_size = SIZE
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(delta: float) -> void:
	_t = fmod(_t + delta, LOOP_SEC)
	queue_redraw()


func _draw() -> void:
	var word := "CATCH" if catch_mode else "DODGE"
	var color := Color(1.0, 0.8, 0.18) if catch_mode else Color(0.98, 0.25, 0.18)
	var font := get_theme_default_font()
	draw_string(font, Vector2(0, 82), word, HORIZONTAL_ALIGNMENT_LEFT, -1, 72, color)
	# The lane: the ball rolls from the right towards the bike on the left.
	var lane_x0 := 300.0
	var lane_x1 := SIZE.x
	draw_line(Vector2(lane_x0, 104), Vector2(lane_x1, 104), Color(1, 1, 1, 0.25), 3.0)
	var f := _t / LOOP_SEC
	var ball_x := lerpf(lane_x1 - 20.0, lane_x0 + 20.0, minf(f / 0.7, 1.0))
	var ball_y := 80.0
	# The bike (a simple rider-and-wheel mark) moves up out of the lane, or onto the ball's line.
	var bike_x := lane_x0 + 20.0
	var dodge_off := clampf((f - 0.35) / 0.2, 0.0, 1.0)
	var bike_y := 80.0 - 52.0 * dodge_off if not catch_mode else 80.0
	if catch_mode:
		bike_y = lerpf(36.0, 80.0, clampf((f - 0.3) / 0.25, 0.0, 1.0))
	draw_circle(Vector2(bike_x, bike_y + 10.0), 13.0, Color(1, 1, 1, 0.9))
	draw_line(Vector2(bike_x, bike_y + 10.0), Vector2(bike_x, bike_y - 18.0), Color(1, 1, 1, 0.9), 5.0)
	draw_circle(Vector2(bike_x, bike_y - 24.0), 7.0, Color(1, 1, 1, 0.9))
	var arrived := f >= 0.7
	if catch_mode and arrived:
		# Caught: a gold sparkle at the bike.
		var s := (f - 0.7) / 0.3
		for i in 8:
			var a := TAU * i / 8.0
			var r := 10.0 + 30.0 * s
			draw_circle(Vector2(bike_x, ball_y) + Vector2(cos(a), sin(a)) * r, 5.0 * (1.0 - s), color)
	elif not arrived or not catch_mode:
		var x := ball_x if not arrived else lerpf(lane_x0 + 20.0, lane_x0 - 60.0, (f - 0.7) / 0.3)
		draw_circle(Vector2(x, ball_y), 16.0, color)
		draw_arc(Vector2(x, ball_y), 10.0, -0.6, 0.9, 10, Color(1, 1, 1, 0.5), 3.0)
