class_name SafeStatus
extends PanelContainer
## Safe Cracker's HUD widget, in the HUD's top-centre slot: two short rows.
##
##   VAULT 3 · 2 cracked          Target 32
##   Easy on the pedals: under 90 W    ALARM
##
## Labels only change with their values, so the HUD isn't re-laid out every frame.

var _vault: Label
var _target: Label
var _power: Label
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
	_vault = HudTheme.label("", HudTheme.SMALL)
	_vault.custom_minimum_size = Vector2(330, 0)
	top.add_child(_vault)
	_target = HudTheme.label("", HudTheme.SMALL, HudTheme.WARN)
	_target.custom_minimum_size = Vector2(250, 0)
	_target.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_target)
	var bottom := _row(box)
	_power = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	_power.custom_minimum_size = Vector2(430, 0)
	bottom.add_child(_power)
	_alert = HudTheme.label("", HudTheme.SMALL, HudTheme.BAD)
	_alert.custom_minimum_size = Vector2(150, 0)
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_alert)


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 16)
	parent.add_child(row)
	return row


## `power_warning` colours the power line amber when the rider is over the cap.
func set_state(vault_text: String, target_text: String, power_text: String, alert_text: String, power_warning: bool) -> void:
	if vault_text != _texts[0]:
		_texts[0] = vault_text
		_vault.text = vault_text
	if target_text != _texts[1]:
		_texts[1] = target_text
		_target.text = target_text
	var power_full := power_text + ("!" if power_warning else "")
	if power_full != _texts[2]:
		_texts[2] = power_full
		_power.text = power_text
		_power.add_theme_color_override("font_color", HudTheme.WARN if power_warning else HudTheme.MUTED)
	if alert_text != _texts[3]:
		_texts[3] = alert_text
		_alert.text = alert_text
