class_name BigNumber
extends PanelContainer
## A number readable at bike distance with a small caption: under it ("182 / watts"), or with
## `compact`, beside it in a slim row and without a panel of its own (for a shared panel).

const COMPACT_SIZE := 72
const CAPTION_WIDTH := 150.0

## In a compact row, a value this long or longer takes the caption's spare width, so the row keeps
## its size (the score: with a heart strap's column, a wider clock panel crowded End). 0: never.
var tight_from := 0

var _value: Label
var _caption: Label
var _color := Color(-1, -1, -1)
var _size_before := 0  ## `set_value_size`: the size to go back to


func _init(caption := "", value := "--", color := HudTheme.INK, compact := false) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", StyleBoxEmpty.new() if compact else HudTheme.panel_style())
	var box: BoxContainer = HBoxContainer.new() if compact else VBoxContainer.new()
	box.add_theme_constant_override("separation", 14 if compact else 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_value = HudTheme.label(value, COMPACT_SIZE if compact else HudTheme.BIG, color)
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT if compact else HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_value)
	_caption = HudTheme.label(caption, HudTheme.SMALL, HudTheme.MUTED)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if compact else HORIZONTAL_ALIGNMENT_CENTER
	if compact:
		_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_caption.custom_minimum_size = Vector2(CAPTION_WIDTH, 0)
		_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(_caption)


## The setters do nothing when the value is unchanged: callers set them every frame, and a theme
## override re-lays out the HUD (frame time on the tablet).
func set_value(text: String) -> void:
	if _value.text != text:
		_value.text = text
		if tight_from > 0:
			_caption.custom_minimum_size.x = 0.0 if text.length() >= tight_from else CAPTION_WIDTH


## The value's size for now (`Hud._fit_clock`), or 0 for the size it had before.
func set_value_size(size: int) -> void:
	if size > 0:
		_size_before = _value.get_theme_font_size("font_size")
		_value.add_theme_font_size_override("font_size", mini(size, _size_before))
	elif _size_before > 0:
		_value.add_theme_font_size_override("font_size", _size_before)
		_size_before = 0


func set_caption(text: String) -> void:
	if _caption.text != text:
		_caption.text = text


func set_color(color: Color) -> void:
	if color != _color:
		_color = color
		_value.add_theme_color_override("font_color", color)
