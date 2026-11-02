class_name WattLaneStatus
extends PanelContainer
## Watt Lane's HUD widget (#78), in the HUD's top-centre slot. The hero is the lane: its exact
## bounds in watts, the same numbers the rules compare against the ride panel's W (which shows
## the same smoothed power). Two caption rows beside it:
##
##   150–190   W LANE   ×2.5
##             In lane 82%   [▲ PUSH]          (or, before a jump: [▲ UP 175–215 in 4])
##
## The countdown chip takes the second row's place while a jump is announced, and pops each
## second. Within 850 x 120 px with the longest texts (watt_lane_scene_test). Labels change only
## with their values; motion is scale and modulate only (framework/ui/UI_STYLE.md).

const ARROW_UP := 0
const ARROW_DOWN := 1

const ALERT_NONE := ""
const ALERT_PUSH := "push"  ## under the lane
const ALERT_EASE := "ease"  ## over it
const ALERT_PEDAL := "pedal"  ## stopped
const ALERT_TEXTS := {"push": "PUSH", "ease": "EASE", "pedal": "PEDAL"}

var lane: Label  ## the hero
var caption: Label
var streak: Label
var info: Label
var alert: PanelContainer
var alert_label: Label
var countdown: PanelContainer
var countdown_label: Label

var _look: GameTheme
var _alert_arrow: _Arrow
var _count_arrow: _Arrow
var _texts := {}
var _alert := ALERT_NONE
var _count_n := -1
var _bounds := Vector2i(-1, -1)


func _init(look: GameTheme) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := _box(HBoxContainer.new(), self, 12)
	var hero_box := MarginContainer.new()
	hero_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hero_box.add_theme_constant_override("margin_top", -4)
	hero_box.add_theme_constant_override("margin_bottom", -18)
	row.add_child(hero_box)
	lane = Label.new()
	lane.name = "Lane"
	lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lane.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lane.custom_minimum_size = Vector2(280, 0)  # most lanes fit; a wider one grows it
	hero_box.add_child(lane)
	var rows := _box(VBoxContainer.new(), row, 4)
	rows.alignment = BoxContainer.ALIGNMENT_CENTER
	var top := _box(HBoxContainer.new(), rows, 14)
	caption = _label("W LANE", top)
	streak = _label("", top)
	streak.custom_minimum_size = Vector2(84, 0)
	var bottom := _box(HBoxContainer.new(), rows, 12)
	info = _label("", bottom)
	info.custom_minimum_size = Vector2(200, 0)  # "In lane 100%"
	alert = _chip(bottom)
	_alert_arrow = _Arrow.new(ARROW_UP)
	alert.get_child(0).add_child(_alert_arrow)
	alert_label = _label("", alert.get_child(0))
	alert.visible = false
	countdown = _chip(bottom)
	countdown.name = "Countdown"
	_count_arrow = _Arrow.new(ARROW_UP)
	countdown.get_child(0).add_child(_count_arrow)
	countdown_label = _label("", countdown.get_child(0))
	countdown.visible = false
	apply_theme(look)


func apply_theme(look: GameTheme) -> void:
	_look = look
	var style := look.panel_style()
	style.content_margin_top = 8
	style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	look.style_label(lane, HudTheme.BIG, GameTheme.INK, true)
	look.set_gradient(lane)
	look.style_label(caption, HudTheme.SMALL, GameTheme.MUTED, true)
	look.style_label(streak, HudTheme.SMALL, GameTheme.TARGET, true)
	look.style_label(info, HudTheme.SMALL, GameTheme.MUTED, true)
	look.style_label(alert_label, HudTheme.SMALL, GameTheme.INK)
	look.style_label(countdown_label, HudTheme.SMALL, GameTheme.INK)
	alert.add_theme_stylebox_override("panel", look.badge_style(GameTheme.WARN.darkened(0.15), true))
	countdown.add_theme_stylebox_override("panel", look.badge_style(Palette.AMBER.darkened(0.1), true))
	_alert_arrow.color = GameTheme.INK
	_count_arrow.color = GameTheme.INK


## The lane's bounds, watts. Pops when they jump (not on a 5 W drift, not the first time).
func set_lane(lo: int, hi: int) -> void:
	var bounds := Vector2i(lo, hi)
	if bounds == _bounds:
		return
	var big := _bounds.x >= 0 and absi(lo - _bounds.x) > 5
	_bounds = bounds
	lane.text = "%d–%d" % [lo, hi]
	if big:
		GameTheme.pop(lane, 1.25)


func set_info(pct_in_lane: int, multiplier: float) -> void:
	if _changed("info", str(pct_in_lane)):
		info.text = "In lane %d%%" % pct_in_lane
	if _changed("streak", str(multiplier)):
		streak.text = "×%d!" % roundi(multiplier) if multiplier >= WattLaneLogic.STREAK_MAX else "×%s" % String.num(multiplier, 1)


## The streak stepped up: pop it, or slam it at the top.
func streak_up(multiplier: float) -> void:
	if multiplier >= WattLaneLogic.STREAK_MAX:
		GameTheme.slam(streak, 2.0)
	else:
		GameTheme.pop(streak, 1.35)


## Out of the lane: which way to go (ALERT_*), or ALERT_NONE.
func set_alert(kind: String) -> void:
	if kind == _alert:
		return
	_alert = kind
	if kind == ALERT_NONE:
		alert.visible = false
		return
	alert_label.text = ALERT_TEXTS[kind]
	_alert_arrow.set_direction(ARROW_DOWN if kind == ALERT_EASE else ARROW_UP)
	_show_alert_row()
	if not countdown.visible:
		GameTheme.pop(alert, 1.15)


func alert_kind() -> String:
	return _alert


## The announced jump: "UP 175–215 in 4" (watts: the hero's caption says W) (`n` whole seconds left, 0 for "NOW"), or
## `n` < 0 to hide the chip.
func set_countdown(up: bool, lo: int, hi: int, n: int) -> void:
	if n < 0:
		if countdown.visible:
			countdown.visible = false
			_count_n = -1
			_show_alert_row()
		return
	var text := "%s %d–%d %s" % ["UP" if up else "DOWN", lo, hi, ("in %d" % n) if n > 0 else "NOW"]
	if _changed("countdown", text):
		countdown_label.text = text
		_count_arrow.set_direction(ARROW_UP if up else ARROW_DOWN)
	var first := not countdown.visible
	countdown.visible = true
	info.visible = false
	alert.visible = false
	if n != _count_n:
		_count_n = n
		if first:
			GameTheme.fade(countdown, true)
		GameTheme.pop(countdown, 1.18 if first else 1.08)


func _show_alert_row() -> void:
	if countdown.visible:
		return
	info.visible = true
	alert.visible = _alert != ALERT_NONE


func _chip(parent: Control) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(chip)
	var box := _box(HBoxContainer.new(), chip, 6)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	return chip


func _label(text: String, parent: Control) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l


func _box(box: BoxContainer, parent: Control, separation: int) -> BoxContainer:
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", separation)
	parent.add_child(box)
	return box


func _changed(key: String, value: String) -> bool:
	if _texts.get(key) == value:
		return false
	_texts[key] = value
	return true


## The game's own colours the HUD shares with the world (ART_BIBLE.md §4).
class Palette:
	const LIME := Color("c8ff3e")
	const AMBER := Color("ffb020")
	const INK := Color("061418")


## A triangle drawn as a shape (the display face has no arrow glyphs). Redraws only on a change.
class _Arrow:
	extends Control

	var direction := ARROW_UP
	var color := Color.WHITE:
		set(value):
			if value != color:
				color = value
				queue_redraw()

	func _init(dir: int) -> void:
		direction = dir
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(26, 26)
		size_flags_vertical = Control.SIZE_SHRINK_CENTER

	func set_direction(dir: int) -> void:
		if dir != direction:
			direction = dir
			queue_redraw()

	func _draw() -> void:
		var s := size
		var points: PackedVector2Array
		if direction == ARROW_UP:
			points = [Vector2(s.x * 0.5, 0), Vector2(s.x, s.y), Vector2(0, s.y)]
		else:
			points = [Vector2(0, 0), Vector2(s.x, 0), Vector2(s.x * 0.5, s.y)]
		draw_colored_polygon(points, color)
