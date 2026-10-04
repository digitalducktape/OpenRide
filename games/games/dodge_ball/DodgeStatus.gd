class_name DodgeStatus
extends PanelContainer
## Dodge Ball's HUD widget, in the HUD's top-centre slot. Slim, so it sits above the horizon
## and never covers the road: two short rows.
##
##   DODGE  shield ▕████▁▁▁▁▏
##   ×2   streak 12   ●●○   wave 2
##
## The mode in its colour (danger red / reward gold); the shield bar drains under the cadence
## floor (amber, "pedal up!") and pulses red when empty; the power bonus, the streak and, in a
## Just Ride, the lives (drawn as balls, so no font glyph is needed) and the wave. Labels only
## change with their values: re-laying out the HUD every frame cost frame time on the tablet.

const BAR_SIZE := Vector2(300, 22)
const LIFE_RADIUS := 12.0

var shield := 1.0
var draining := false
var floor_rpm := 85.0
var lives := -1  ## -1: no lives (circuit)

var _mode: Label
var _caption: Label
var _bar: Control
var _bonus: Label
var _streak: Label
var _lives_box: Control
var _wave: Label
var _t := 0.0
var _drawn_shield := -1.0
var _bonus_on := false
var _streak_count := -1
var _wave_number := -1


func _init(floor_value := 85.0, with_lives := false, is_catch := false) -> void:
	floor_rpm = floor_value
	lives = DodgeBallLogic.LIVES if with_lives else -1
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
	_mode = HudTheme.label("", HudTheme.SMALL)
	top.add_child(_mode)
	_caption = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	_caption.custom_minimum_size = Vector2(150, 0)
	top.add_child(_caption)
	_bar = Control.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	top.add_child(_bar)

	var bottom := _row(box)
	_bonus = HudTheme.label("×1", HudTheme.SMALL, HudTheme.MUTED)
	bottom.add_child(_bonus)
	_streak = HudTheme.label("streak 0", HudTheme.SMALL)
	bottom.add_child(_streak)
	_lives_box = Control.new()
	_lives_box.custom_minimum_size = Vector2(LIFE_RADIUS * 2.0 * 3 + 16, LIFE_RADIUS * 2.0 + 4)
	_lives_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_lives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lives_box.draw.connect(_draw_lives)
	_lives_box.visible = with_lives
	bottom.add_child(_lives_box)
	_wave = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	_wave.visible = with_lives
	bottom.add_child(_wave)
	_refresh_caption()
	set_catch(is_catch)


## Shows the mode, in its colour: DODGE in danger red, CATCH in reward gold.
func set_catch(is_catch: bool) -> void:
	_mode.text = "CATCH" if is_catch else "DODGE"
	_mode.add_theme_color_override("font_color", Color(1.0, 0.8, 0.18) if is_catch else Color(0.98, 0.32, 0.25))


func set_state(value: float, below_floor: bool, bonus_on: bool, streak: int, lives_left: int, wave: int) -> void:
	shield = value
	if below_floor != draining:
		draining = below_floor
		_refresh_caption()
	if bonus_on != _bonus_on:
		_bonus_on = bonus_on
		_bonus.text = "×2" if bonus_on else "×1"
		_bonus.add_theme_color_override("font_color", HudTheme.STAR_ON if bonus_on else HudTheme.MUTED)
	if streak != _streak_count:
		_streak_count = streak
		_streak.text = "streak %d" % streak
	if lives >= 0 and lives_left != lives:
		lives = lives_left
		_lives_box.queue_redraw()
	if wave != _wave_number:
		_wave_number = wave
		_wave.text = "wave %d" % wave
	if absf(value - _drawn_shield) > 0.002:
		_drawn_shield = value
		_bar.queue_redraw()


func _process(delta: float) -> void:
	_t += delta
	if shield <= 0.0:
		_bar.queue_redraw()


func _refresh_caption() -> void:
	_caption.text = "pedal up!" if draining else "shield"
	_caption.add_theme_color_override("font_color", HudTheme.WARN if draining else HudTheme.MUTED)


func _row(parent: Container) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	return row


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, BAR_SIZE)
	_bar.draw_rect(r, Color(1, 1, 1, 0.12))
	var color := Color(0.35, 0.78, 1.0)
	if shield <= 0.0:
		color = HudTheme.BAD.lerp(Color(1, 0.5, 0.45), 0.5 + 0.5 * sin(_t * 8.0))
		_bar.draw_rect(r, Color(color, 0.35))
	elif draining:
		color = HudTheme.WARN
	_bar.draw_rect(Rect2(Vector2.ZERO, Vector2(BAR_SIZE.x * clampf(shield, 0.0, 1.0), BAR_SIZE.y)), color)
	_bar.draw_rect(r, Color(1, 1, 1, 0.5), false, 2.0)


func _draw_lives() -> void:
	for i in DodgeBallLogic.LIVES:
		var c := Vector2(LIFE_RADIUS + i * (LIFE_RADIUS * 2.0 + 8.0), LIFE_RADIUS + 2.0)
		if i < lives:
			_lives_box.draw_circle(c, LIFE_RADIUS, Color(0.98, 0.32, 0.2))
			_lives_box.draw_arc(c, LIFE_RADIUS * 0.6, -0.6, 0.9, 12, Color(1, 1, 1, 0.5), 3.0)
		else:
			_lives_box.draw_arc(c, LIFE_RADIUS - 1.5, 0.0, TAU, 24, Color(1, 1, 1, 0.3), 3.0)
