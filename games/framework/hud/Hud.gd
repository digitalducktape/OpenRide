class_name Hud
extends CanvasLayer
## The standard in-game HUD that Session puts over every game (docs/GAMES.md, "HUD kit"):
##
##   top:     sensor banner (full width, only on sensor loss)
##   left:    game title and role, then the effort badge (effort segments only)
##   centre:  segment timer
##   right:   score, then Pause and End
##   centre, under the timer: the game's own widgets (`add_widget`)
##   bottom right: Recalibrate, for camera games
##
## Games reach it as `hud` and add widgets such as a `TargetBand` in `_on_prepare`; Session
## clears them when the game leaves.

signal pause_pressed
signal end_pressed
signal recalibrate_pressed

const LAYER := 10

var title: Label
var role: Label
var timer: SegmentTimer
var score: BigNumber
var effort: EffortBadge
var sensor_banner: SensorBanner
var pause_button: Button
var end_button: Button
var recalibrate_button: Button

var _widgets: HBoxContainer


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	var m := HudTheme.MARGIN

	var left := VBoxContainer.new()
	left.position = Vector2(m, m)
	left.add_theme_constant_override("separation", 12)
	left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(left)
	title = HudTheme.label("", HudTheme.MEDIUM)
	left.add_child(title)
	role = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	left.add_child(role)
	effort = EffortBadge.new()
	left.add_child(effort)

	timer = SegmentTimer.new()
	timer.custom_minimum_size = Vector2(360, 0)
	timer.position = Vector2(HudTheme.W / 2 - 180, m)
	add_child(timer)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.position = Vector2(HudTheme.W - m - 340, m)
	right.custom_minimum_size = Vector2(340, 0)
	add_child(right)
	score = BigNumber.new("score", "0")
	right.add_child(score)
	pause_button = HudTheme.button("Pause", func(): pause_pressed.emit())
	right.add_child(pause_button)
	end_button = HudTheme.button("End", func(): end_pressed.emit(), Color(0.45, 0.16, 0.2))
	right.add_child(end_button)

	_widgets = HBoxContainer.new()
	_widgets.add_theme_constant_override("separation", 40)
	_widgets.alignment = BoxContainer.ALIGNMENT_CENTER
	_widgets.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Under the timer, so the bottom of the screen stays clear for the rider's avatar.
	_widgets.position = Vector2(HudTheme.W / 2 - 500, m + 200)
	_widgets.size = Vector2(1000, 140)
	add_child(_widgets)

	recalibrate_button = HudTheme.button("Recalibrate", func(): recalibrate_pressed.emit())
	recalibrate_button.position = Vector2(HudTheme.W - m - 340, HudTheme.H - m - HudTheme.BUTTON_HEIGHT)
	recalibrate_button.size = Vector2(340, HudTheme.BUTTON_HEIGHT)
	recalibrate_button.visible = false
	add_child(recalibrate_button)

	sensor_banner = SensorBanner.new()
	sensor_banner.position = Vector2.ZERO
	sensor_banner.size = Vector2(HudTheme.W, 0)
	sensor_banner.custom_minimum_size = Vector2(HudTheme.W, 0)
	add_child(sensor_banner)


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


## Adds a game widget along the bottom of the screen.
func add_widget(widget: Control) -> void:
	_widgets.add_child(widget)


func clear_widgets() -> void:
	for child in _widgets.get_children():
		child.queue_free()


func set_paused(paused: bool) -> void:
	pause_button.text = "Resume" if paused else "Pause"


func _process(_delta: float) -> void:
	score.set_value(str(floori(Effort.score)))
