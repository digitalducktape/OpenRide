class_name SafeDial
extends Node2D
## Safe Cracker's door and dial (#41), centred on the door. Redrawn only when something shown
## changes (the needle, the hold ring, the lights, the alarm or the door swinging). The dial
## runs 0-100 over 270 degrees, from the lower left round to the lower right; the needle is the
## live resistance reading.

const R := 262.0
const DOOR := Rect2(-440, -320, 880, 640)
const SWEEP_START := 135.0
const SWEEP := 270.0

var reading := 0.0
var target := 0
var tolerance := 2.0
var target_hidden := false
var hold_frac := 0.0  ## 0-1, how far through the hold
var closeness := 0.0
var powered := true
var tumblers_done := 0
var tumblers_total := 3
var door_open := 0.0  ## 0 closed, 1 fully open
var alarm := 0.0  ## 0-1, the alarm light
var colour := Color(0.5, 0.52, 0.55)
var accent := Color(0.95, 0.75, 0.35)

var _drawn := {}
var _t := 0.0


static func angle_for(value: float) -> float:
	return deg_to_rad(SWEEP_START + clampf(value, 0.0, 100.0) * SWEEP / 100.0)


## Redraws only when a shown value changed.
func refresh() -> void:
	var state := {"r": roundi(reading * 2.0), "t": target, "tol": tolerance, "h": target_hidden, "f": roundi(hold_frac * 60.0),
		"c": roundi(closeness * 20.0), "p": powered, "d": tumblers_done, "n": tumblers_total,
		"o": roundi(door_open * 120.0), "a": roundi(alarm * 10.0), "col": colour}
	if target_hidden or alarm > 0.0 or tumblers_done < tumblers_total:
		state["pulse"] = int(_t * 6.0)
	if state != _drawn:
		_drawn = state
		queue_redraw()


func _process(delta: float) -> void:
	_t += delta


func _draw() -> void:
	var font := ThemeDB.fallback_font
	_draw_door(font)
	_draw_lights()
	if alarm > 0.0:
		var flash := 0.35 + 0.35 * sin(_t * 12.0)
		draw_rect(Rect2(-492, -372, 984, 744), Color(0.95, 0.15, 0.1, alarm * flash), false, 12)


func _draw_door(font: Font) -> void:
	var s := maxf(1.0 - door_open, 0.0)
	if s <= 0.02:
		return
	draw_set_transform_matrix(Transform2D(Vector2(s, 0), Vector2(0, 1), Vector2(DOOR.position.x * (1.0 - s), 0)))
	var face := StyleBoxFlat.new()
	face.bg_color = colour
	face.set_corner_radius_all(22)
	face.border_color = colour.lightened(0.25)
	face.set_border_width_all(6)
	draw_style_box(face, DOOR)
	for corner in [DOOR.position + Vector2(36, 36), Vector2(DOOR.end.x - 36, DOOR.position.y + 36),
			Vector2(DOOR.position.x + 36, DOOR.end.y - 36), DOOR.end - Vector2(36, 36)]:
		draw_circle(corner, 11, colour.darkened(0.3))
		draw_circle(corner, 5, colour.lightened(0.3))
	# The bezel and the face of the dial.
	draw_circle(Vector2.ZERO, R + 40.0, colour.darkened(0.35))
	draw_circle(Vector2.ZERO, R + 24.0, colour.lightened(0.1))
	draw_circle(Vector2.ZERO, R + 8.0, Color(0.07, 0.07, 0.09))
	for i in range(0, 101, 5):
		var a := angle_for(float(i))
		var major := i % 10 == 0
		var from := Vector2(cos(a), sin(a)) * (R - (34.0 if major else 20.0))
		draw_line(from, Vector2(cos(a), sin(a)) * (R - 4.0), Color(0.85, 0.85, 0.8) if major else Color(0.5, 0.5, 0.5), 5.0 if major else 3.0)
		if major:
			var at := Vector2(cos(a), sin(a)) * (R - 66.0)
			draw_string(font, at + Vector2(-30, 12), str(i), HORIZONTAL_ALIGNMENT_CENTER, 60, 30, Color(0.9, 0.9, 0.85))
	# The target: a gold band the width of the tolerance, or a glow that warms as you close in.
	if not target_hidden:
		draw_arc(Vector2.ZERO, R - 22.0, angle_for(float(target) - tolerance), angle_for(float(target) + tolerance), 24, Color(accent, 0.85), 26.0)
		var ta := angle_for(float(target))
		var tip := Vector2(cos(ta), sin(ta)) * (R + 6.0)
		var side := Vector2(-sin(ta), cos(ta)) * 14.0
		var out := Vector2(cos(ta), sin(ta)) * 30.0
		draw_colored_polygon(PackedVector2Array([tip, tip + out + side, tip + out - side]), accent)
		draw_string(font, Vector2(-80, -110), str(target), HORIZONTAL_ALIGNMENT_CENTER, 160, 78, accent)
	else:
		draw_arc(Vector2.ZERO, R + 33.0, 0.0, TAU, 72, Color(accent, closeness * closeness * 0.9), 10.0)
		draw_string(font, Vector2(-80, -110), "?", HORIZONTAL_ALIGNMENT_CENTER, 160, 78, Color(0.75, 0.78, 0.85))
	# The hold ring, filling as the needle stays on the target.
	if hold_frac > 0.0:
		draw_arc(Vector2.ZERO, R + 33.0, -PI / 2.0, -PI / 2.0 + hold_frac * TAU, 72, Color(0.35, 0.95, 0.55), 12.0)
	# The needle and hub, and the reading in numbers.
	var na := angle_for(reading)
	var dir := Vector2(cos(na), sin(na))
	draw_line(-dir * 40.0, dir * (R - 12.0), Color(0.95, 0.3, 0.25), 9.0)
	draw_circle(Vector2.ZERO, 30.0, Color(0.85, 0.85, 0.8))
	draw_circle(Vector2.ZERO, 14.0, Color(0.2, 0.2, 0.22))
	draw_string(font, Vector2(-70, 150), str(roundi(reading)), HORIZONTAL_ALIGNMENT_CENTER, 140, 64, Color(0.95, 0.95, 0.9))
	if not powered:
		draw_circle(Vector2.ZERO, R + 40.0, Color(0.02, 0.02, 0.04, 0.6))
		draw_string(font, Vector2(-190, 60), "KEEP PEDALLING", HORIZONTAL_ALIGNMENT_CENTER, 380, 44, Color(1.0, 0.8, 0.35))
	draw_set_transform_matrix(Transform2D.IDENTITY)


## One light per tumbler under the dial: gold when clicked, a pulsing outline for the next.
func _draw_lights() -> void:
	var gap := 56.0
	var x0 := -(tumblers_total - 1) * gap / 2.0
	for i in tumblers_total:
		var at := Vector2(x0 + i * gap, 343.0)
		if i < tumblers_done:
			draw_circle(at, 17.0, accent)
			draw_circle(at, 9.0, accent.lightened(0.5))
		else:
			var pulse := 0.5 + 0.5 * sin(_t * 6.0) if i == tumblers_done else 0.0
			draw_circle(at, 17.0, Color(0, 0, 0, 0.4))
			draw_arc(at, 15.0, 0.0, TAU, 20, Color(accent, 0.35 + 0.5 * pulse), 4.0)
