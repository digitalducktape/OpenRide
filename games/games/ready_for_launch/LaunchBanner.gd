class_name LaunchBanner
extends CanvasLayer
## Ready for Launch's callouts ("Hold 120 W to fill the tank", "Push past 210 W!", "Orbit! 412 km"),
## centred in a lane under the status widget, above the rocket's tip and between the side panels
## (`launch_scene_test` checks both), as Keepy Uppy's `KeepyBanner`. One label with a heavy ink
## outline, so it reads over any sky. Under the HUD (layer 10), a child of the game, so it pauses
## with it. Every callout tells the rider what to do, with a number the rules use.

const LAYER := 6
const LANE := Rect2(620, 132, 790, 72)
const SIZE := 52
const OUTLINE := 15

var label: Label
var _box: CenterContainer
var _tween: Tween


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


## Slams `text` in, holds it for `seconds` and fades it out.
func show_callout(text: String, color: Color, seconds: float) -> void:
	label.text = text
	label.add_theme_color_override("font_color", color)
	GameTheme.stop(label, "fade")
	label.visible = true
	label.modulate.a = 1.0
	if _tween and _tween.is_valid():
		_tween.kill()
	label.pivot_offset = Vector2(LANE.size.x * 0.5, SIZE * 0.6)
	GameTheme.slam(label, 1.4, 0.3)
	_tween = label.create_tween()
	_tween.tween_interval(maxf(seconds - GameTheme.FADE_SEC, 0.4))
	_tween.tween_callback(func(): GameTheme.fade(label, false))


func is_showing() -> bool:
	return label.visible and label.modulate.a > 0.0


## The lane on the canvas, for the layout test.
func lane_rect() -> Rect2:
	return _box.get_global_rect()
