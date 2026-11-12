class_name GaugeBar
extends Control
## A status widget's bar: a rounded track, a fill, and whichever marks the game needs. One look for
## every game's "how much, against what" (Balloon Pump's pressure, Power Grid's supply, Ready for
## Launch's fuel and climb, The Pull's distance), so the same HUD slot reads the same in a circuit.
##
## - `set_fill(share, colour)`: the fill, 0-1 along the bar, in a meaning colour.
## - `set_line(share)`: a target line to reach, gold and inked, with the track past it tinted
##   (what's still to do). Negative: none.
## - `set_ticks(shares)`: white ticks across the bar (milestones).
## - `set_flag(share)`: a gold flag standing on the bar (a best to beat). Negative: none.
## - `checked_end`: the last stretch chequered (a finish line).
## - `set_alert(on)`: the track turns red (Dodge Ball's empty shield).
##
## Budget (UI_STYLE.md §8): it redraws only when something moves a pixel or changes colour, and
## every shape goes through one ShapeBatch (one draw call).

var checked_end := false
## How often it has drawn (tests: no per-frame redraws).
var draws := 0

var _ink: Color
var _fill := 0.0
var _fill_color := GameTheme.GOOD
var _line := -1.0
var _flag := -1.0
var _ticks: Array[float] = []
var _fill_px := -1
var _line_px := -1
var _flag_px := -1
var _alert := false


func _init(bar_size: Vector2, ink: Color) -> void:
	_ink = ink
	custom_minimum_size = bar_size
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_fill(share: float, color: Color) -> void:
	_fill = clampf(share, 0.0, 1.0)
	var px := roundi(_fill * custom_minimum_size.x)
	if px != _fill_px or color != _fill_color:
		_fill_px = px
		_fill_color = color
		queue_redraw()


func set_line(share: float) -> void:
	_line = clampf(share, 0.0, 1.0) if share >= 0.0 else -1.0
	var px := roundi(_line * custom_minimum_size.x)
	if px != _line_px:
		_line_px = px
		queue_redraw()


func set_flag(share: float) -> void:
	_flag = clampf(share, 0.0, 1.0) if share >= 0.0 else -1.0
	var px := roundi(_flag * custom_minimum_size.x)
	if px != _flag_px:
		_flag_px = px
		queue_redraw()


func set_alert(on: bool) -> void:
	if on != _alert:
		_alert = on
		queue_redraw()


func set_ticks(shares: Array[float]) -> void:
	if shares != _ticks:
		_ticks = shares.duplicate()
		queue_redraw()


func _draw() -> void:
	draws += 1
	var b := ShapeBatch.new()
	var w := size.x
	var h := size.y
	var r := h * 0.5
	pill(b, Rect2(Vector2.ZERO, size), Color(_ink.lerp(GameTheme.BAD, 0.55), 0.95) if _alert else Color(_ink.darkened(0.4), 0.92))
	var line_x := clampf(_line * w, r, w - 2.0)
	if _line >= 0.0:
		pill(b, Rect2(line_x - r, 4.0, w - line_x + r - 4.0, h - 8.0), Color(GameTheme.TARGET, 0.2))
	if checked_end:
		var check := (h - 12.0) / 2.0
		for i in 2:
			for j in 2:
				if (i + j) % 2 == 0:
					var at := Vector2(w - r - check * (i + 1), 6.0 + j * check)
					b.quad(at, at + Vector2(check, 0), at + Vector2(check, check), at + Vector2(0, check), Color(GameTheme.TARGET, 0.85))
	var fill_w := _fill * w
	if fill_w > 2.0:
		pill(b, Rect2(4.0, 6.0, maxf(fill_w - 8.0, h - 12.0), h - 12.0), _fill_color)
	for t in _ticks:
		var x := 4.0 + (w - 8.0) * t
		b.line(Vector2(x, 2.0), Vector2(x, h - 2.0), 4.0, Color.WHITE, false)
	if _flag >= 0.0:
		var x := clampf(_flag * w, r, w - 2.0)
		b.line(Vector2(x, -6.0), Vector2(x, h + 6.0), 8.0, _ink, false)
		b.line(Vector2(x, -6.0), Vector2(x, h + 6.0), 4.0, GameTheme.TARGET, false)
		b.convex(PackedVector2Array([Vector2(x + 2, -6), Vector2(x + 18, -1), Vector2(x + 2, 4)]), GameTheme.TARGET)
	if _line >= 0.0:
		# The line to reach: a gold tick standing proud of the bar, inked.
		b.line(Vector2(line_x, -4.0), Vector2(line_x, h + 4.0), 9.0, _ink)
		b.line(Vector2(line_x, -2.0), Vector2(line_x, h + 2.0), 5.0, GameTheme.TARGET)
	b.draw(self)


## A rounded bar inside `rect`: a box with round ends.
static func pill(b: ShapeBatch, rect: Rect2, color: Color) -> void:
	var r := rect.size.y * 0.5
	if rect.size.x <= rect.size.y:
		b.circle(rect.get_center(), r, color, 16)
		return
	b.line(rect.position + Vector2(r, r), rect.position + Vector2(rect.size.x - r, r), rect.size.y, color)
