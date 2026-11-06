class_name GridBanner
extends CanvasLayer
## Power Grid's callouts ("Funfair next: hold 130 W", "Line down! Hold 170 W for 10 s"), centred in
## a lane just under the status widget. The HUD's centre message would sit on the town, the hero, so
## the game has its own lane over the sky (Safe Cracker's and Keepy Uppy's answer). The lane is clear
## of every HUD panel and of the moon (grid_layout_test checks both).
##
## One label with a heavy ink outline, so it reads over any sky; slammed in and faded out in the
## meaning colour it's given. Under the HUD (layer 10), a child of the game, so it pauses with it.

const LAYER := 6
## The lane (1920x1080 canvas): under the status widget, between the side panels. A circuit's
## progress strip pushes the widget down, so `set_lane_top` moves it.
const LANE := Rect2(650, 150, 830, 70)
const SIZE := HudTheme.BODY + 4  ## 48 px: the longest instruction fits the lane on one line
const NARROW_SIZE := HudTheme.BODY  ## the longest instruction in a lane cut short by `set_lane_end`
const OUTLINE := 14

var label: Label
var _box: CenterContainer
var _tween: Tween
var _hold := 0  ## the priority of what's showing


func _init(look: GameTheme) -> void:
	layer = LAYER
	_box = CenterContainer.new()
	_box.name = "Lane"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.position = LANE.position
	_box.size = LANE.size
	add_child(_box)
	label = look.label("", SIZE, GameTheme.INK, true)
	label.name = "Callout"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", OUTLINE)
	label.add_theme_color_override("font_outline_color", look.ink)
	label.custom_minimum_size = Vector2(LANE.size.x, 0)
	label.visible = false
	_box.add_child(label)


## Moves the lane's top (under a taller status area).
func set_lane_top(y: float) -> void:
	_box.position.y = y


## Ends the lane at `x` (the Music button, in a circuit: `PowerGrid._fit_lane`), or at its own end
## again. The text is centred in what's left, a size down so the longest instruction still fits.
func set_lane_end(x: float) -> void:
	var width := minf(x, LANE.end.x) - LANE.position.x
	label.add_theme_font_size_override("font_size", SIZE if width >= LANE.size.x else NARROW_SIZE)
	label.custom_minimum_size.x = width
	_box.size.x = width


## Slams `text` in, holds it for `seconds` and fades it out. A callout of lower `priority` never
## cuts in on one that's still showing: a storm's instruction outranks a district's news.
func show_callout(text: String, color: Color, seconds: float, priority := 0) -> void:
	if is_showing() and priority < _hold:
		return
	_hold = priority
	label.text = text
	label.add_theme_color_override("font_color", color)
	GameTheme.stop(label, "fade")
	label.visible = true
	label.modulate.a = 1.0
	if _tween and _tween.is_valid():
		_tween.kill()
	label.pivot_offset = Vector2(_box.size.x * 0.5, SIZE * 0.6)
	GameTheme.slam(label, 1.4, 0.35)
	_tween = label.create_tween()
	_tween.tween_interval(maxf(seconds - GameTheme.FADE_SEC, 0.4))
	_tween.tween_callback(func() -> void:
		_hold = 0
		GameTheme.fade(label, false))


func is_showing() -> bool:
	return label.visible and label.modulate.a > 0.0


## The lane on the canvas, for the layout test.
func lane_rect() -> Rect2:
	return _box.get_global_rect()
