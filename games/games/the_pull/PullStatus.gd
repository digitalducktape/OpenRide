class_name PullStatus
extends PanelContainer
## The Pull's HUD widget, in the HUD's top-centre slot, at most 820 x 120 px with the longest
## texts (`the_pull_scene_test`):
##
##             [      SLED NEEDS 182 W       ]
##     214 m   PULL 2/3  ▕▓▓▓▓▓▓▓▓▓▓▏ ⚑   ▒▒▏
##
## Left: the distance, the hero (80 px, the green gradient). Right, on top: a state chip. Between pulls
## and while things are fine the chip shows the sled's need in watts, the same rounded number
## as the ride metrics' power band tick (`PullLogic.shown_need`), so the two never disagree.
## Other states take its place, each with words, not only colour: GET SET, DIG IN! NEEDS n W · s
## (amber, breathing; the sled's need again, and s seconds to the stall), STALLED, BONUS +n (a
## Full Pull: the centre message says the words), TIME!, REST n.
## Right, under it: the pull count and the progress bar from the start to the Full Pull line: filled to
## the distance in the accent, a gold flag tick at the rider's best, a checked end.
## The widget never shows the rider's watts: the ride metrics are the only place they appear
## (DESIGN.md, "HUD agreement").
##
## Budget (UI_STYLE.md §8): labels change only with their values, the bar redraws only when its
## fill moves a pixel, and the warning's breathing is a tween.

const BAR_SIZE := Vector2(310, 26)
const PULL_WIDTH := 190.0  ## "PULL 5/5" at BODY size
const HERO_SIZE := 80
const DISTANCE_WIDTH := 170.0  ## "1888" at the hero size, right-aligned so the "m" stays put

var look: GameTheme
var distance_label: Label
var unit_label: Label
var chip: PanelContainer
var chip_label: Label
var pull_label: Label
var bar: Control

var full_m := 336.0
var best_m := 0.0
var _distance_m := -1
var _fill_px := -1
var _chip_key := ""
var _pull_text := ""


func _init(theme: GameTheme = null) -> void:
	look = theme if theme else GameTheme.new(PullMeshes.ACCENT, PullMeshes.INK, 0.08)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := look.panel_style()
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 22
	style.content_margin_right = 22
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	add_child(row)
	distance_label = look.hero("0", HERO_SIZE, GameTheme.GOOD_GRADIENT, true)
	distance_label.name = "Distance"
	distance_label.custom_minimum_size = Vector2(DISTANCE_WIDTH, 0)
	distance_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	distance_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(distance_label)
	unit_label = look.label("m", HudTheme.BODY, GameTheme.MUTED, true)
	unit_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(unit_label)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.custom_minimum_size = Vector2(12, 0)
	row.add_child(spacer)
	var right := VBoxContainer.new()
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_theme_constant_override("separation", 4)
	right.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(right)
	chip = PanelContainer.new()
	chip.name = "Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip_label = look.label("", HudTheme.SMALL, GameTheme.INK, true)
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(chip_label)
	right.add_child(chip)
	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 14)
	right.add_child(bottom)
	pull_label = look.label("PULL 1", HudTheme.BODY, GameTheme.INK, true)
	pull_label.custom_minimum_size = Vector2(PULL_WIDTH, 0)
	pull_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(pull_label)
	bar = Control.new()
	bar.name = "Progress"
	bar.custom_minimum_size = BAR_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(_draw_bar)
	bottom.add_child(bar)
	set_chip("need", 0)


## The track's length to the Full Pull line and the best flag, for the bar.
func set_track(new_full_m: float, new_best_m: float) -> void:
	full_m = maxf(new_full_m, 1.0)
	best_m = new_best_m
	_fill_px = -1
	bar.queue_redraw()


## The distance in whole metres (`PullLogic.shown_m`).
func set_distance(metres: int) -> void:
	if metres == _distance_m:
		return
	_distance_m = metres
	distance_label.text = str(metres)
	var px := roundi(BAR_SIZE.x * clampf(metres / full_m, 0.0, 1.0))
	if px != _fill_px:
		_fill_px = px
		bar.queue_redraw()


## "PULL 2/3" in rounds, "PULL 2" otherwise.
func set_pull(index: int, of := 0) -> void:
	var text := "PULL %d/%d" % [index, of] if of > 0 else "PULL %d" % index
	if text == _pull_text:
		return
	_pull_text = text
	pull_label.text = text


## The chip's state: "need" (value: the sled's need in W), "set", "dig_in" (value: seconds to the
## stall, need: the sled's need in W), "stalled", "full" (value: the bonus as counted), "time" or
## "rest" (value: seconds left).
func set_chip(state: String, value: int, need := 0) -> void:
	var key := "%s:%d:%d" % [state, value, need]
	if key == _chip_key:
		return
	var was := _chip_key.get_slice(":", 0)
	_chip_key = key
	var fill := PullMeshes.INK
	var text := ""
	var color := GameTheme.INK
	match state:
		"need":
			text = "SLED NEEDS %d W" % value
			color = GameTheme.TARGET
		"set":
			text = "GET SET"
			color = GameTheme.TARGET
		"dig_in":
			text = "DIG IN! NEEDS %d W · %d" % [need, value]
			fill = GameTheme.WARN.darkened(0.35)
		"stalled":
			text = "STALLED"
			fill = GameTheme.BAD.darkened(0.3)
		"full":
			text = "BONUS +%d" % value
			fill = look.accent.darkened(0.2)
		"time":
			text = "TIME!"
			fill = GameTheme.WARN.darkened(0.35)
		"rest":
			text = "REST %d" % value
			color = GameTheme.MUTED
		_:
			text = ""
	chip_label.text = text
	chip_label.add_theme_color_override("font_color", color)
	chip.add_theme_stylebox_override("panel", look.badge_style(fill, true))
	if state != was:
		GameTheme.pulse(chip, state == "dig_in")
		if state in ["dig_in", "stalled", "full", "time"]:
			GameTheme.pop(chip, 1.15)


func chip_state() -> String:
	return _chip_key.get_slice(":", 0)


func _draw_bar() -> void:
	var s := bar.size
	var radius := s.y / 2.0
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0, 0, 0, 0.45)
	track.border_color = Color(1, 1, 1, 0.25)
	track.set_border_width_all(2)
	track.set_corner_radius_all(int(radius))
	track.anti_aliasing = true
	bar.draw_style_box(track, Rect2(Vector2.ZERO, s))
	# The checked end: the Full Pull line.
	var check := 8.0
	for i in 2:
		for j in int(s.y / check):
			if (i + j) % 2 == 0:
				bar.draw_rect(Rect2(s.x - check * (i + 1) - 4, j * check + 1, check, check), Color("f2c230", 0.85))
	if _fill_px > 0:
		var fill := StyleBoxFlat.new()
		fill.bg_color = look.accent
		fill.set_corner_radius_all(int(radius))
		fill.anti_aliasing = true
		bar.draw_style_box(fill, Rect2(0, 0, maxf(_fill_px, s.y), s.y))
	if best_m > 0.5:
		var x := s.x * clampf(best_m / full_m, 0.0, 1.0)
		bar.draw_rect(Rect2(x - 2, -6, 4, s.y + 12), GameTheme.TARGET)
		bar.draw_colored_polygon(PackedVector2Array([Vector2(x + 2, -6), Vector2(x + 18, -1), Vector2(x + 2, 4)]),
			GameTheme.TARGET)
