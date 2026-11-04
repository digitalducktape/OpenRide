class_name KeepyBanner
extends CanvasLayer
## Keepy Uppy's callouts ("Rain: 130 W holds it up", "Downdraft! Push!", "POP! −50", "Shook it
## off!"), centred in a lane just under the status widget (UI_POLISH.md item 1). The HUD's centre
## message sat on the balloon and the column, exactly where the rider looks; Safe Cracker solved
## the same problem with its own banner (`SafeBanner`). The lane is clear of every HUD panel and
## above the balloon at its highest, birds included (keepy_scene_test checks both).
##
## One label with a heavy ink outline, so it reads over any sky; slammed in and faded out in the
## meaning colour it's given. Under the HUD (layer 10), a child of the game, so it pauses with it.

const LAYER := 6
## The lane (1920x1080 canvas): under the status widget, between the side panels.
const LANE := Rect2(660, 124, 720, 70)
const SIZE := HudTheme.MEDIUM
const OUTLINE := 14

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
	GameTheme.slam(label, 1.5, 0.35)
	_tween = label.create_tween()
	_tween.tween_interval(maxf(seconds - GameTheme.FADE_SEC, 0.4))
	_tween.tween_callback(func(): GameTheme.fade(label, false))


func is_showing() -> bool:
	return label.visible and label.modulate.a > 0.0


## The lane on the canvas, for the layout test.
func lane_rect() -> Rect2:
	return _box.get_global_rect()
