class_name PauseOverlay
extends CanvasLayer
## The pause screen (Resume, End session) and the end-session confirmation. Session shows the
## pause screen on session_paused, whether the rider or auto-pause paused, and the
## confirmation from the HUD's End button or the pause screen's.

signal resume_pressed
signal end_confirmed
## The rider picked a new value for one of the game's options (`GameInfo.options`).
signal option_changed(key: String, value: String)

const LAYER := 30

var _paused_box: VBoxContainer
var _confirm_box: VBoxContainer
var _options_box: VBoxContainer
var _options_button: Button
var _paused := false
## The game's declared options, and a getter for an option's current value.
var _options: Array[Dictionary] = []
var _value_of: Callable


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
	_options_button = HudTheme.button("Game options", show_options)
	_options_button.visible = false
	_paused_box.add_child(_options_button)
	_paused_box.add_child(HudTheme.button("End session", show_confirm, Color(0.45, 0.16, 0.2)))

	_options_box = _card("Game options", "Remembered for you, for this game.")

	_confirm_box = _card("End the session?", "Your ride so far is saved.")
	_confirm_box.add_child(HudTheme.button("End session", func(): hide_confirm(); end_confirmed.emit(), Color(0.45, 0.16, 0.2)))
	_confirm_box.add_child(HudTheme.button("Keep riding", hide_confirm, Color(0.16, 0.45, 0.3)))


## The current game's options (`GameInfo.options`); `value_of(key) -> String` reads one. An
## empty list hides the "Game options" button.
func set_options(options: Array[Dictionary], value_of: Callable) -> void:
	_options = options
	_value_of = value_of
	_options_button.visible = not options.is_empty()
	for child in _options_box.get_children().slice(2):
		child.queue_free()
	for spec in options:
		var key := str(spec.key)
		var button := HudTheme.button("", func(): _cycle(key))
		button.name = "Option_%s" % key
		_options_box.add_child(button)
	_options_box.add_child(HudTheme.button("Back", hide_options, Color(0.16, 0.45, 0.3)))
	_refresh_options()


func show_options() -> void:
	_refresh_options()
	_paused_box.get_parent().visible = false
	_options_box.get_parent().visible = true


func hide_options() -> void:
	set_paused(_paused)


func is_showing_options() -> bool:
	return visible and _options_box.get_parent().visible


func _cycle(key: String) -> void:
	for spec in _options:
		if spec.key == key:
			option_changed.emit(key, GameOptions.next_choice(spec, str(_value_of.call(key))))
	_refresh_options()


func _refresh_options() -> void:
	if not _value_of.is_valid():
		return
	for spec in _options:
		var button := _options_box.get_node_or_null("Option_%s" % spec.key) as Button
		if button:
			button.text = "%s: %s" % [spec.label, GameOptions.label_for(spec, str(_value_of.call(spec.key)))]


func set_paused(paused: bool) -> void:
	_paused = paused
	_confirm_box.get_parent().visible = false
	_options_box.get_parent().visible = false
	_paused_box.get_parent().visible = paused
	visible = paused


func show_confirm() -> void:
	_paused_box.get_parent().visible = false
	_options_box.get_parent().visible = false
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
