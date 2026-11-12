class_name DodgeStatus
extends PanelContainer
## Dodge Ball's HUD widget, in the HUD's top-centre slot. Slim, so it sits above the horizon
## and never covers the road: two short rows.
##
##   DODGE  [SHIELD]  ▕████▁▁▁▁▏
##   STREAK 12   ●●○   WAVE 2   [×2 POINTS]
##
## The hero is the shield (framework/ui/UI_STYLE.md, "One hero per screen"): a 320x30 bar on a
## dark ink track. Under the cadence floor its caption becomes an amber "PEDAL UP!" badge; once
## the shield is empty the badge turns red and breathes, and the bar throbs (a modulate tween,
## not a redraw), until the shield is full again. The mode in its colour (danger red / reward
## gold), the streak, and in a Just Ride the lives (drawn as balls) and the wave. The power
## bonus shows only while it's on, as a gold "×2 POINTS" badge that slams in and fades out; its
## slot keeps its width, so nothing moves when it comes and goes. Labels only change with their
## values: re-laying out the HUD every frame cost frame time on the tablet.

## Dodge Ball's look: sky cyan (the shield's colour) on navy, badges leaning 0.18 in the italic
## face. `DodgeBall.ui_theme()` returns it, so the intro card and the pause screen match.
static var look := GameTheme.new(Color("38b6ff"), Color("0e1b3d"), 0.18, true)

const BAR_SIZE := Vector2(320, 30)
const LIFE_RADIUS := 14.0
const LIFE_GAP := 8.0
const CAPTIONS := ["SHIELD", "PEDAL UP!", "NO SHIELD"]

enum Caption { SHIELD, PEDAL_UP, EMPTY }

var shield := 1.0
var draining := false
## True from the moment the shield empties until it's full again (`shield_ready`).
var empty := false
var floor_rpm := 85.0
var lives := -1  ## -1: no lives (circuit)

## The elements the game pops on its events (DodgeBall._handle).
var streak_label: Label
var lives_box: Control
var bar: GaugeBar
var bonus_badge: PanelContainer

var _mode: Label
var _caption_box: PanelContainer
var _caption: Label
var _bonus_slot: MarginContainer
var _wave: Label
var _bonus_on := false
var _streak_count := -1
var _wave_number := -1
var _caption_state := -1
var _bar_throb: Tween
var _lost_life := -1  ## the life that's popping down, or -1
var _lost_scale := 0.0
## How often the lives have drawn (the bar counts its own: `bar.draws`) (tests: no per-frame redraws).
var draws := 0


func _init(floor_value := 85.0, with_lives := false, is_catch := false) -> void:
	floor_rpm = floor_value
	lives = DodgeBallLogic.LIVES if with_lives else -1
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := look.panel_style()
	style.content_margin_top = 6
	style.content_margin_bottom = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)

	var top := _row(box)
	_mode = look.label("", HudTheme.SMALL)
	top.add_child(_mode)
	_caption_box = PanelContainer.new()
	_caption_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_caption_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_caption = look.label("", HudTheme.SMALL)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# As wide as the widest caption, so the bar never moves when the caption changes.
	var font := look.font()
	var widest := 0.0
	for text in CAPTIONS:
		widest = maxf(widest, font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, HudTheme.SMALL).x)
	_caption.custom_minimum_size = Vector2(ceilf(widest) + GameTheme.outline_for(HudTheme.SMALL), 0)
	_caption_box.add_child(_caption)
	top.add_child(_caption_box)
	bar = GaugeBar.new(BAR_SIZE, look.ink)
	top.add_child(bar)

	var bottom := _row(box)
	streak_label = look.label("STREAK 0", HudTheme.SMALL, GameTheme.INK, true)
	bottom.add_child(streak_label)
	lives_box = Control.new()
	lives_box.custom_minimum_size = Vector2(LIFE_RADIUS * 2.0 * DodgeBallLogic.LIVES + LIFE_GAP * (DodgeBallLogic.LIVES - 1) + 4.0,
		LIFE_RADIUS * 2.0 + 4.0)
	lives_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lives_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lives_box.draw.connect(_draw_lives)
	lives_box.visible = with_lives
	bottom.add_child(lives_box)
	_wave = look.label("", HudTheme.SMALL, GameTheme.MUTED, true)
	_wave.visible = with_lives
	bottom.add_child(_wave)
	# The power bonus: a gold badge in a slot that keeps its width while the badge is hidden.
	_bonus_slot = MarginContainer.new()
	_bonus_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bonus_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bonus_badge = PanelContainer.new()
	bonus_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bonus_badge.add_theme_stylebox_override("panel", _badge(GameTheme.TARGET))
	bonus_badge.add_child(look.label("×2 POINTS", HudTheme.SMALL, look.ink))
	_bonus_slot.add_child(bonus_badge)
	_bonus_slot.custom_minimum_size = bonus_badge.get_combined_minimum_size()
	bonus_badge.visible = false
	bottom.add_child(_bonus_slot)
	_refresh_caption()
	set_catch(is_catch)


## Shows the mode, in its colour: DODGE in danger red, CATCH in reward gold.
func set_catch(is_catch: bool) -> void:
	_mode.text = "CATCH" if is_catch else "DODGE"
	_mode.add_theme_color_override("font_color", GameTheme.TARGET if is_catch else Color(0.98, 0.32, 0.25))


func set_state(value: float, below_floor: bool, bonus_on: bool, streak: int, lives_left: int, wave: int) -> void:
	shield = value
	draining = below_floor
	if value <= 0.0 and not empty:
		_set_empty(true)
	elif value >= 1.0 and empty:
		_set_empty(false)
	_refresh_caption()
	if bonus_on != _bonus_on:
		_bonus_on = bonus_on
		if bonus_on:
			bonus_badge.visible = true
			GameTheme.slam(bonus_badge)
		else:
			GameTheme.fade(bonus_badge, false)
	if streak != _streak_count:
		_streak_count = streak
		streak_label.text = "STREAK %d" % streak
	if lives >= 0 and lives_left != lives:
		if lives_left < lives:
			_pop_life(lives_left)
		lives = lives_left
		lives_box.queue_redraw()
	if wave != _wave_number:
		_wave_number = wave
		_wave.text = "WAVE %d" % wave
	bar.set_fill(value, GameTheme.WARN if below_floor else look.accent)


## The shield emptied (true) or is full again (false): the badge turns red and breathes and the
## bar throbs, or both settle and the bar pops.
func _set_empty(on: bool) -> void:
	empty = on
	if _bar_throb and _bar_throb.is_valid():
		_bar_throb.kill()
	bar.modulate = Color.WHITE
	if on:
		_bar_throb = bar.create_tween().set_loops()
		_bar_throb.tween_property(bar, "modulate", Color(1.35, 1.35, 1.35), 0.3).set_trans(Tween.TRANS_SINE)
		_bar_throb.tween_property(bar, "modulate", Color(0.75, 0.75, 0.75), 0.3).set_trans(Tween.TRANS_SINE)
	else:
		GameTheme.pop(bar, 1.12)
	bar.set_alert(on)


func _refresh_caption() -> void:
	var state := Caption.SHIELD
	if empty:
		state = Caption.PEDAL_UP if draining else Caption.EMPTY
	elif draining:
		state = Caption.PEDAL_UP
	var key := state + (10 if empty else 0)
	if key == _caption_state:
		return
	var was_pulsing := _caption_state >= 10
	_caption_state = key
	_caption.text = CAPTIONS[state]
	if state == Caption.SHIELD:
		var plain := StyleBoxEmpty.new()
		var badge := _badge(GameTheme.WARN)
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			plain.set_content_margin(side, badge.get_content_margin(side))
		_caption_box.add_theme_stylebox_override("panel", plain)
		_caption.add_theme_color_override("font_color", GameTheme.MUTED)
		_caption.add_theme_color_override("font_outline_color", look.ink)
	else:
		_caption_box.add_theme_stylebox_override("panel", _badge(GameTheme.BAD if empty else GameTheme.WARN))
		_caption.add_theme_color_override("font_color", Color.WHITE if empty else look.ink)
		_caption.add_theme_color_override("font_outline_color", look.ink if empty else Color(GameTheme.WARN, 0.0))
	if empty != was_pulsing:
		GameTheme.pulse(_caption_box, empty, 1.08, 0.6)


## A badge for the status rows: the theme's, with slim margins so two rows fit the budget.
func _badge(fill: Color) -> StyleBoxFlat:
	var s := look.badge_style(fill)
	s.content_margin_top = 0
	s.content_margin_bottom = 2
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.shadow_size = 4
	s.shadow_offset = Vector2(2, 3)
	s.border_width_bottom = 4
	return s


func _pop_life(index: int) -> void:
	_lost_life = index
	var t := lives_box.create_tween()
	t.tween_method(func(v: float):
		_lost_scale = v
		lives_box.queue_redraw(), 1.0, 0.0, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_callback(func(): _lost_life = -1)


func _row(parent: Container) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(row)
	return row


func _draw_lives() -> void:
	draws += 1
	for i in DodgeBallLogic.LIVES:
		var c := Vector2(2.0 + LIFE_RADIUS + i * (LIFE_RADIUS * 2.0 + LIFE_GAP), LIFE_RADIUS + 2.0)
		if i < lives or i == _lost_life:
			var r := LIFE_RADIUS * (lerpf(0.8, 1.0, _lost_scale) if i == _lost_life else 1.0)
			var a := _lost_scale if i == _lost_life else 1.0
			lives_box.draw_circle(c, r + 2.0, Color(look.ink, a))
			lives_box.draw_circle(c, r, Color(0.98, 0.32, 0.2, a))
			lives_box.draw_arc(c, r * 0.6, -0.6, 0.9, 12, Color(1, 1, 1, 0.5 * a), 3.0)
		if i >= lives:
			lives_box.draw_arc(c, LIFE_RADIUS - 1.5, 0.0, TAU, 24, Color(1, 1, 1, 0.35), 3.0)
