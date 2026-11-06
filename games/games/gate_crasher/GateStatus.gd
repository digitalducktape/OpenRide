class_name GateStatus
extends PanelContainer
## Gate Crasher's HUD widget, in the HUD's top-centre slot, at most 820 x 120 px with the longest
## texts (`gate_crasher_scene_test`):
##
##     FENCE 3/8    o o O . . . . .     [ CLEAR SO FAR ]
##     ROUND 2
##
## Left: the fence and the round. Middle: a pip per fence (teal clear, red down, ring next). Right:
## a chip with the round's state, always in words. Watts never show here: the ride metrics are the
## only place they appear.
##
## Budget (UI_STYLE.md §8): labels change only with their values, and the pips redraw only when a
## fence is decided.

const PIP := 24.0
const PIP_GAP := 8.0
const FENCE_WIDTH := 190.0

var look: GameTheme
var fence_label: Label
var round_label: Label
var chip: PanelContainer
var chip_label: Label
var pips: Control

var _count := 8
var _results: Array[int] = []
var _next := 0
var _chip_key := ""
var _fence_text := ""
var _round_text := ""


func _init(theme: GameTheme = null) -> void:
	look = theme if theme else GameTheme.new(GateMeshes.ACCENT, GateMeshes.INK, 0.08)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := look.panel_style()
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	var left := VBoxContainer.new()
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left.add_theme_constant_override("separation", -4)
	left.custom_minimum_size = Vector2(FENCE_WIDTH, 0)
	left.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(left)
	fence_label = look.label("FENCE 1/8", HudTheme.BODY, GameTheme.INK, true)
	fence_label.name = "Fence"
	left.add_child(fence_label)
	round_label = look.label("ROUND 1", HudTheme.SMALL, GameTheme.MUTED, true)
	round_label.name = "Round"
	left.add_child(round_label)
	pips = Control.new()
	pips.name = "Pips"
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.draw.connect(_draw_pips)
	row.add_child(pips)
	chip = PanelContainer.new()
	chip.name = "Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip_label = look.label("", HudTheme.SMALL, GameTheme.INK, true)
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.add_child(chip_label)
	row.add_child(chip)
	set_fences(8)
	set_chip("clear", 0)


func set_fences(count: int) -> void:
	_count = count
	pips.custom_minimum_size = Vector2(count * PIP + (count - 1) * PIP_GAP, PIP)
	pips.queue_redraw()


## The fence coming up (from 1), the round, and this round's results so far (GateLogic.Call).
func set_progress(fence: int, round_index: int, results: Array[int]) -> void:
	var text := "FENCE %d/%d" % [fence, _count]
	if text != _fence_text:
		_fence_text = text
		fence_label.text = text
	var rtext := "ROUND %d" % round_index
	if rtext != _round_text:
		_round_text = rtext
		round_label.text = rtext
	if results != _results or fence - 1 != _next:
		_results = results.duplicate()
		_next = fence - 1
		pips.queue_redraw()


## The chip's state: "clear" (no rail down this round), "faults" (value: this round's faults),
## "circling" (the camera lost the rider) or "pedal".
func set_chip(state: String, value: int) -> void:
	var key := "%s:%d" % [state, value]
	if key == _chip_key:
		return
	var was := _chip_key.get_slice(":", 0)
	_chip_key = key
	var fill := GateMeshes.INK
	var color := GameTheme.INK
	var text := ""
	match state:
		"clear":
			text = "CLEAR SO FAR"
			color = look.accent
		"faults":
			text = "%d FAULTS" % value
			fill = GameTheme.BAD.darkened(0.3)
		"circling":
			text = "CIRCLING"
			fill = GameTheme.WARN.darkened(0.35)
		"pedal":
			text = "PEDAL ON"
			fill = GameTheme.WARN.darkened(0.35)
	chip_label.text = text
	chip_label.add_theme_color_override("font_color", color)
	chip.add_theme_stylebox_override("panel", look.badge_style(fill, true))
	if state != was and state != "clear":
		GameTheme.pop(chip, 1.15)


func chip_state() -> String:
	return _chip_key.get_slice(":", 0)


func _draw_pips() -> void:
	for i in _count:
		var c := Vector2(i * (PIP + PIP_GAP) + PIP / 2.0, pips.size.y / 2.0)
		if i < _results.size():
			var fill: Color = look.accent
			if _results[i] == GateLogic.Call.NO_PEDAL:
				fill = GameTheme.MUTED
			elif _results[i] != GateLogic.Call.CLEAR:
				fill = GameTheme.BAD
			pips.draw_circle(c, PIP / 2.0, fill, true, -1.0, true)
		elif i == _next:
			pips.draw_circle(c, PIP / 2.0 - 2.0, GameTheme.TARGET, false, 4.0, true)
		else:
			pips.draw_circle(c, PIP / 2.0 - 2.0, Color(1, 1, 1, 0.3), false, 3.0, true)
