class_name HudTheme
extends RefCounted
## Sizes and colours for the HUD kit, tuned for a 1920x1080 canvas read from about 1 m away on
## the bike (docs/GAMES.md, "HUD kit"). Text never goes below `SMALL`; touch targets are at
## least `BUTTON_HEIGHT` tall. Everything uses Godot's default font.

const W := 1920.0
const H := 1080.0
const MARGIN := 40.0

const HUGE := 160  ## countdowns
const BIG := 96  ## the numbers a rider glances at: score, timer, cadence
const MEDIUM := 56  ## headings and badges
const BODY := 44  ## sentences on cards
const SMALL := 34  ## captions under big numbers
const BUTTON_HEIGHT := 110.0
const BUTTON_FONT := 44

const INK := Color(1, 1, 1)
const MUTED := Color(0.72, 0.76, 0.86)
const PANEL := Color(0.07, 0.08, 0.14, 0.82)
const CARD := Color(0.12, 0.16, 0.3, 0.96)
const GOOD := Color(0.3, 0.88, 0.55)
const WARN := Color(1.0, 0.72, 0.25)
const BAD := Color(0.86, 0.22, 0.22)
const EFFORT := Color(1.0, 0.55, 0.15)
const STAR_ON := Color(1.0, 0.84, 0.25)
const STAR_OFF := Color(1, 1, 1, 0.22)

## Role colours: work is warm, recovery and the easy ends are cool (epic #31, progress strip).
const ROLE_COLORS := {
	"warmup": Color(0.35, 0.7, 1.0),
	"work": Color(1.0, 0.45, 0.25),
	"recovery": Color(0.35, 0.85, 0.8),
	"cooldown": Color(0.55, 0.6, 1.0),
	"free": Color(0.7, 0.75, 0.9),
}
const ROLE_NAMES := {
	"warmup": "Warm-up",
	"work": "Work",
	"recovery": "Recovery",
	"cooldown": "Cool-down",
	"free": "Just Ride",
}


static func label(text: String, font_size: int, color := INK) -> Label:
	var l := Label.new()
	l.text = text
	style_label(l, font_size, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Gives a label the kit's plain look (also undoing a `GameTheme` restyle: its face, shadow and
## gradient).
static func style_label(l: Label, font_size: int, color := INK) -> void:
	l.remove_theme_font_override("font")
	l.remove_theme_color_override("font_shadow_color")
	l.material = null
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("outline_size", maxi(4, font_size / 12))


static func panel_style(color := PANEL, radius := 24) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(radius)
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


## A big touch button. Focus is off: on a desktop, Space is the simulator's "stand".
static func button(text: String, action: Callable, color := Color(0.22, 0.28, 0.5)) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(300, BUTTON_HEIGHT)
	style_button(b, color)
	b.pressed.connect(action)
	return b


## Gives a button the kit's plain look in `color` (also undoing a `GameTheme` restyle).
static func style_button(b: Button, color := Color(0.22, 0.28, 0.5)) -> void:
	b.remove_theme_font_override("font")
	b.remove_theme_color_override("font_outline_color")
	b.remove_theme_constant_override("outline_size")
	b.remove_theme_stylebox_override("focus")
	b.add_theme_font_size_override("font_size", BUTTON_FONT)
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := panel_style(color if state != "pressed" else color.lightened(0.2), 20)
		if state == "hover":
			style.bg_color = color.lightened(0.1)
		b.add_theme_stylebox_override(state, style)


## "12:05" (or "1:02:03"); negative input reads "--:--".
static func grouped(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func clock(seconds: float) -> String:
	if seconds < 0.0:
		return "--:--"
	var s := int(ceil(seconds - 0.001))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s / 60) % 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


static func role_name(role: String) -> String:
	return ROLE_NAMES.get(role, role.capitalize())


static func role_color(role: String) -> Color:
	return ROLE_COLORS.get(role, MUTED)
