class_name CadenceStatus
extends PanelContainer
## Cadence Karaoke's HUD widget, in the HUD's top-centre slot: two short rows.
##
##   TARGET 85 rpm    → 90 rpm in 7 s
##   In band 78% · streak ×1.5            EASE OFF
##
## Labels only change with their values, so the HUD isn't re-laid out every frame.

var _target: Label
var _next: Label
var _info: Label
var _alert: Label
var _texts := ["", "", "", ""]


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := HudTheme.panel_style()
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var top := _row(box)
	_target = HudTheme.label("", HudTheme.SMALL)
	_target.custom_minimum_size = Vector2(250, 0)
	top.add_child(_target)
	_next = HudTheme.label("", HudTheme.SMALL, HudTheme.WARN)
	_next.custom_minimum_size = Vector2(330, 0)
	top.add_child(_next)
	var bottom := _row(box)
	_info = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	_info.custom_minimum_size = Vector2(420, 0)
	bottom.add_child(_info)
	_alert = HudTheme.label("", HudTheme.SMALL, HudTheme.WARN)
	_alert.custom_minimum_size = Vector2(160, 0)
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_alert)


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	return row


func set_state(target_text: String, next_text: String, info_text: String, alert_text: String) -> void:
	var values := [target_text, next_text, info_text, alert_text]
	var labels := [_target, _next, _info, _alert]
	for i in 4:
		if values[i] != _texts[i]:
			_texts[i] = values[i]
			(labels[i] as Label).text = values[i]
