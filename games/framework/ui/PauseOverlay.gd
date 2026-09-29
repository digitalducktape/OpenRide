class_name PauseOverlay
extends CanvasLayer
## The pause screen (Resume, End session) and the end-session confirmation. Session shows the
## pause screen on session_paused, whether the rider or auto-pause paused, and the
## confirmation from the HUD's End button or the pause screen's.

signal resume_pressed
signal end_confirmed

const LAYER := 30

var _paused_box: VBoxContainer
var _confirm_box: VBoxContainer
var _paused := false


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.size = Vector2(HudTheme.W, HudTheme.H)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)

	_paused_box = _card("Paused", "Tap Resume to carry on.")
	_paused_box.add_child(HudTheme.button("Resume", func(): resume_pressed.emit(), Color(0.16, 0.45, 0.3)))
	_paused_box.add_child(HudTheme.button("End session", show_confirm, Color(0.45, 0.16, 0.2)))

	_confirm_box = _card("End the session?", "Your ride so far is saved.")
	_confirm_box.add_child(HudTheme.button("End session", func(): hide_confirm(); end_confirmed.emit(), Color(0.45, 0.16, 0.2)))
	_confirm_box.add_child(HudTheme.button("Keep riding", hide_confirm, Color(0.16, 0.45, 0.3)))


func set_paused(paused: bool) -> void:
	_paused = paused
	_confirm_box.get_parent().visible = false
	_paused_box.get_parent().visible = paused
	visible = paused


func show_confirm() -> void:
	_paused_box.get_parent().visible = false
	_confirm_box.get_parent().visible = true
	visible = true


func hide_confirm() -> void:
	set_paused(_paused)


func is_confirming() -> bool:
	return visible and _confirm_box.get_parent().visible


func _card(heading: String, line: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudTheme.panel_style(HudTheme.CARD, 32))
	card.custom_minimum_size = Vector2(900, 0)
	card.position = Vector2(HudTheme.W / 2 - 450, 220)
	card.visible = false
	add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 28)
	card.add_child(box)
	var title := HudTheme.label(heading, HudTheme.BIG)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text := HudTheme.label(line, HudTheme.BODY, HudTheme.MUTED)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(text)
	return box
