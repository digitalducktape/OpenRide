class_name Hud
extends CanvasLayer
## The standard in-game HUD that Session puts over every game (docs/GAMES.md, "HUD kit").
##
## Every element sits in a container slot, so nothing overlaps in any state and nothing has a
## hand-placed position. The middle of the screen stays clear for the game:
##
##   Frame (MarginContainer, full screen)
##   └ Rows (VBox)
##     ├ sensor banner                          (only on sensor loss)
##     ├ TopBar (HBox)
##     │  ├ Left  (expand):  title · role, effort badge
##     │  ├ Centre:          segment timer, then the game's widgets (`add_widget`)
##     │  └ Right (expand):  score, Pause | End
##     ├ Middle (expand):    a centred message (`show_message`), e.g. "Game over"
##     ├ status slot:        the camera strip ("Camera steering is off", …), when showing
##     └ BottomBar (HBox)
##        ├ ride metrics:    rpm with the game's band, watts, resistance
##        ├ spacer (expand)
##        └ Recalibrate      (camera games)
##
## Left and Right expand equally, so the centre column stays centred. Games reach the HUD as
## `hud`: they add widgets in `_on_prepare`, set the metrics' bands, and show messages; Session
## clears all three when the game leaves.

signal pause_pressed
signal end_pressed
signal recalibrate_pressed

const LAYER := 10
const GAP := 20
const SIDE_BUTTON_WIDTH := 160.0

var title: Label
var role: Label
var timer: SegmentTimer
var score: BigNumber
var effort: EffortBadge
var sensor_banner: SensorBanner
var pause_button: Button
var end_button: Button
var recalibrate_button: Button
var metrics: RideMetrics
## Where the calibration overlay's camera strip lives during play (see CalibrationOverlay).
var status_slot: HBoxContainer

var frame: MarginContainer
var _widgets: HBoxContainer
var _message: Label
var _score_text := ""


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	frame = MarginContainer.new()
	frame.name = "Frame"
	# The canvas is always 1920x1080 (stretch mode canvas_items), so the frame is that size.
	frame.size = Vector2(HudTheme.W, HudTheme.H)
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, int(HudTheme.MARGIN))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var rows := _box(VBoxContainer.new(), frame, "Rows")

	sensor_banner = SensorBanner.new()
	rows.add_child(sensor_banner)

	var top := _box(HBoxContainer.new(), rows, "TopBar")
	var left := _box(VBoxContainer.new(), top, "Left")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title_row := _box(HBoxContainer.new(), left, "TitleRow")
	title = HudTheme.label("", HudTheme.MEDIUM)
	title_row.add_child(title)
	role = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	role.size_flags_vertical = Control.SIZE_SHRINK_END
	title_row.add_child(role)
	effort = EffortBadge.new()
	effort.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	left.add_child(effort)

	var centre := _box(VBoxContainer.new(), top, "Centre")
	centre.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	timer = SegmentTimer.new()
	timer.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	centre.add_child(timer)
	_widgets = _box(HBoxContainer.new(), centre, "Widgets")
	_widgets.alignment = BoxContainer.ALIGNMENT_CENTER

	var right := _box(VBoxContainer.new(), top, "Right")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score = BigNumber.new("score", "0")
	score.size_flags_horizontal = Control.SIZE_SHRINK_END
	score.custom_minimum_size = Vector2(2 * SIDE_BUTTON_WIDTH + GAP, 0)
	right.add_child(score)
	var buttons := _box(HBoxContainer.new(), right, "Buttons")
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	pause_button = HudTheme.button("Pause", func(): pause_pressed.emit())
	pause_button.custom_minimum_size.x = SIDE_BUTTON_WIDTH
	buttons.add_child(pause_button)
	end_button = HudTheme.button("End", func(): end_pressed.emit(), Color(0.45, 0.16, 0.2))
	end_button.custom_minimum_size.x = SIDE_BUTTON_WIDTH
	buttons.add_child(end_button)

	var middle := CenterContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(middle)
	_message = HudTheme.label("", HudTheme.BIG)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_constant_override("outline_size", 16)
	_message.visible = false
	middle.add_child(_message)

	status_slot = _box(HBoxContainer.new(), rows, "StatusSlot")
	status_slot.alignment = BoxContainer.ALIGNMENT_CENTER

	var bottom := _box(HBoxContainer.new(), rows, "BottomBar")
	metrics = RideMetrics.new()
	metrics.size_flags_vertical = Control.SIZE_SHRINK_END
	bottom.add_child(metrics)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_child(spacer)
	recalibrate_button = HudTheme.button("Recalibrate", func(): recalibrate_pressed.emit())
	recalibrate_button.size_flags_vertical = Control.SIZE_SHRINK_END
	recalibrate_button.visible = false
	bottom.add_child(recalibrate_button)


## Fills the HUD for a new segment.
func setup(info: GameInfo, segment: Dictionary) -> void:
	clear_widgets()
	title.text = info.title
	var role_id := str(segment.get("role", "free"))
	var count := int(segment.get("count", 1))
	role.text = HudTheme.role_name(role_id)
	if count > 1:
		role.text += "  ·  %d of %d" % [int(segment.get("index", 0)) + 1, count]
	role.add_theme_color_override("font_color", HudTheme.role_color(role_id))
	recalibrate_button.visible = info.uses_camera()


## Adds a game widget under the timer.
func add_widget(widget: Control) -> void:
	_widgets.add_child(widget)


func clear_widgets() -> void:
	for child in _widgets.get_children():
		child.queue_free()
	metrics.clear_bands()
	hide_message()


## A short centred message over the middle of the screen ("Game over! Next run in 5").
func show_message(text: String, color := HudTheme.INK) -> void:
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = true


func hide_message() -> void:
	_message.visible = false


func is_showing_message() -> bool:
	return _message.visible


func set_paused(paused: bool) -> void:
	pause_button.text = "Resume" if paused else "Pause"


func _process(_delta: float) -> void:
	var shown := str(floori(Effort.score))
	if shown != _score_text:
		_score_text = shown
		score.set_value(shown)


func _box(box: BoxContainer, parent: Control, node_name: String) -> BoxContainer:
	box.name = node_name
	box.add_theme_constant_override("separation", GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box
