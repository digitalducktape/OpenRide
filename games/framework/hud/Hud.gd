class_name Hud
extends CanvasLayer
## The standard in-game HUD that Session puts over every game (docs/GAMES.md, "HUD kit").
##
## Every element sits in a container slot, so nothing overlaps in any state and nothing has a
## hand-placed position. Everything persistent sits above the horizon or at the edges, so the
## road (or any game's playfield) stays clear from the horizon down:
##
##   Frame (MarginContainer, full screen)
##   └ Rows (VBox)
##     ├ sensor banner                       (only on sensor loss)
##     ├ TopBar (HBox)
##     │  ├ Left (expand):   the ride panel: effort multiplier and gauge, then rpm (with the
##     │  │                  game's floor or band), watts and resistance
##     │  ├ Centre:          the game's own status widgets (`add_widget`), compact
##     │  └ Right (expand):  time left over the score in one panel, Pause | End under it
##     ├ Middle (expand):    a brief centred message (`show_message`), translucent
##     ├ status slot:        the camera strip ("Camera steering is off", …), when showing
##     └ BottomBar (HBox):   Recalibrate on the right (camera games)
##
## Left and Right expand equally, so the centre column stays centred. The game's title and
## role aren't shown during play: the intro card names the game. Games reach the HUD as `hud`:
## they add widgets in `_on_prepare`, set the metrics' bands, and show messages; Session clears
## all three when the game leaves.

signal pause_pressed
signal end_pressed
signal recalibrate_pressed

const LAYER := 10
const GAP := 16
const SIDE_BUTTON_WIDTH := 160.0
const MESSAGE_ALPHA := 0.85

var timer: SegmentTimer
var score: BigNumber
var effort: EffortBadge
var metrics: RideMetrics
var sensor_banner: SensorBanner
var pause_button: Button
var end_button: Button
var recalibrate_button: Button
## Where the calibration overlay's camera strip lives during play (see CalibrationOverlay).
var status_slot: HBoxContainer
## The persistent panels (for layout checks): the ride panel, the clock-and-score panel, the
## buttons and the game's widget row.
var ride_panel: PanelContainer
var clock_panel: PanelContainer

var frame: MarginContainer
var circuit_strip: CircuitStrip
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
	ride_panel = _panel(left, "RidePanel")
	ride_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ride := _box(VBoxContainer.new(), ride_panel, "Ride")
	effort = EffortBadge.new(false)
	ride.add_child(effort)
	metrics = RideMetrics.new(false)
	ride.add_child(metrics)

	var centre := _box(VBoxContainer.new(), top, "Centre")
	centre.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	circuit_strip = CircuitStrip.new()
	centre.add_child(circuit_strip)
	_widgets = _box(HBoxContainer.new(), centre, "Widgets")
	_widgets.alignment = BoxContainer.ALIGNMENT_CENTER

	var right := _box(VBoxContainer.new(), top, "Right")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_panel = _panel(right, "ClockPanel")
	clock_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	clock_panel.custom_minimum_size = Vector2(2 * SIDE_BUTTON_WIDTH + GAP, 0)
	var clock := _box(VBoxContainer.new(), clock_panel, "Clock")
	clock.add_theme_constant_override("separation", 0)
	timer = SegmentTimer.new(true)
	clock.add_child(timer)
	score = BigNumber.new("score", "0", HudTheme.INK, true)
	clock.add_child(score)
	var buttons := _box(HBoxContainer.new(), right, "Buttons")
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	pause_button = HudTheme.button("Pause", func(): pause_pressed.emit())
	pause_button.custom_minimum_size = Vector2(SIDE_BUTTON_WIDTH, HudTheme.BUTTON_HEIGHT * 0.8)
	buttons.add_child(pause_button)
	end_button = HudTheme.button("End", func(): end_pressed.emit(), Color(0.45, 0.16, 0.2))
	end_button.custom_minimum_size = Vector2(SIDE_BUTTON_WIDTH, HudTheme.BUTTON_HEIGHT * 0.8)
	buttons.add_child(end_button)

	var middle := CenterContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(middle)
	_message = HudTheme.label("", HudTheme.BIG)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_constant_override("outline_size", 16)
	_message.modulate.a = MESSAGE_ALPHA
	_message.visible = false
	middle.add_child(_message)

	status_slot = _box(HBoxContainer.new(), rows, "StatusSlot")
	status_slot.alignment = BoxContainer.ALIGNMENT_CENTER

	var bottom := _box(HBoxContainer.new(), rows, "BottomBar")
	bottom.alignment = BoxContainer.ALIGNMENT_END
	recalibrate_button = HudTheme.button("Recalibrate", func(): recalibrate_pressed.emit())
	recalibrate_button.size_flags_vertical = Control.SIZE_SHRINK_END
	recalibrate_button.visible = false
	bottom.add_child(recalibrate_button)


## A session starts: a circuit shows its progress strip, anything else hides it.
func set_plan(plan: Dictionary) -> void:
	circuit_strip.set_plan(plan)


## Fills the HUD for a new segment.
func setup(info: GameInfo, segment: Dictionary) -> void:
	clear_widgets()
	recalibrate_button.visible = info.uses_camera()
	circuit_strip.set_segment(int(segment.get("index", 0)), float(segment.get("duration_sec", 0)))


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


func _panel(parent: Control, node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _box(box: BoxContainer, parent: Control, node_name: String) -> BoxContainer:
	box.name = node_name
	box.add_theme_constant_override("separation", GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box
