class_name IntroCard
extends CanvasLayer
## The card before each segment (epic #31, "Intro card between games"): "Up next: <game>", the
## role, a one-line how-to, the target, the previous result and a countdown ending 3-2-1.
## Tapping it asks to skip the game (`skip_requested`) when skipping is allowed.

signal skip_requested

const LAYER := 20
const CARD_SIZE := Vector2(1320, 760)

var can_skip := false

var _title: Label
var _role: Label
var _how_to: Label
var _target: Label
var _count: Label
var _previous: Label
var _previous_stars: StarRow
var _skip_hint: Label


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.size = Vector2(HudTheme.W, HudTheme.H)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.gui_input.connect(_on_gui_input)
	add_child(shade)

	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudTheme.panel_style(HudTheme.CARD, 32))
	card.position = (Vector2(HudTheme.W, HudTheme.H) - CARD_SIZE) / 2
	card.size = CARD_SIZE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)

	_role = _centred(box, HudTheme.SMALL, HudTheme.MUTED)
	_title = _centred(box, HudTheme.BIG)
	_how_to = _centred(box, HudTheme.BODY)
	_how_to.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_target = _centred(box, HudTheme.BODY, HudTheme.GOOD)
	_count = _centred(box, HudTheme.HUGE, HudTheme.WARN)
	var previous_row := HBoxContainer.new()
	previous_row.alignment = BoxContainer.ALIGNMENT_CENTER
	previous_row.add_theme_constant_override("separation", 24)
	previous_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(previous_row)
	_previous = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	previous_row.add_child(_previous)
	_previous_stars = StarRow.new(0, 40.0)
	previous_row.add_child(_previous_stars)
	_skip_hint = _centred(box, HudTheme.SMALL, HudTheme.MUTED)
	_skip_hint.text = "Tap to skip this game"


## Shows the card for a segment. `previous` is the last result (or empty), with its title.
func show_segment(info: GameInfo, segment: Dictionary, target: String, previous: Dictionary, previous_title: String, skippable: bool) -> void:
	var role := str(segment.get("role", "free"))
	var count := int(segment.get("count", 1))
	_role.text = HudTheme.role_name(role).to_upper()
	if count > 1:
		_role.text += "  ·  %d OF %d" % [int(segment.get("index", 0)) + 1, count]
	_role.add_theme_color_override("font_color", HudTheme.role_color(role))
	_title.text = "Up next: %s" % info.title
	_how_to.text = info.how_to
	_target.text = target
	_target.visible = not target.is_empty()
	var has_previous := not previous.is_empty()
	_previous.visible = has_previous
	_previous_stars.visible = has_previous and not previous.get("skipped", false)
	if has_previous:
		if previous.get("skipped", false):
			_previous.text = "Last: %s (skipped)" % previous_title
		else:
			_previous.text = "Last: %s  %d points" % [previous_title, int(previous.get("score", 0))]
			_previous_stars.stars = int(previous.get("stars", 0))
	can_skip = skippable
	_skip_hint.visible = skippable
	set_time_left(float(segment.get("intro_sec", 0)))
	visible = true


## The countdown: whole seconds, then a big 3-2-1.
func set_time_left(seconds: float) -> void:
	var whole := ceili(seconds)
	_count.text = str(whole) if whole > 0 else "Go!"
	_count.add_theme_font_size_override("font_size", HudTheme.HUGE if whole <= 3 else HudTheme.BIG)
	_count.add_theme_color_override("font_color", HudTheme.WARN if whole <= 3 else HudTheme.MUTED)


func _on_gui_input(event: InputEvent) -> void:
	if visible and can_skip and event is InputEventMouseButton and event.pressed:
		skip_requested.emit()


func _centred(box: Container, font_size: int, color := HudTheme.INK) -> Label:
	var label := HudTheme.label("", font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return label
