class_name BigNumber
extends PanelContainer
## A number readable at bike distance with a small caption under it: "182 / watts".

var _value: Label
var _caption: Label


func _init(caption := "", value := "--", color := HudTheme.INK) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudTheme.panel_style())
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_value = HudTheme.label(value, HudTheme.BIG, color)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_value)
	_caption = HudTheme.label(caption, HudTheme.SMALL, HudTheme.MUTED)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_caption)


func set_value(text: String) -> void:
	_value.text = text


func set_caption(text: String) -> void:
	_caption.text = text


func set_color(color: Color) -> void:
	_value.add_theme_color_override("font_color", color)
