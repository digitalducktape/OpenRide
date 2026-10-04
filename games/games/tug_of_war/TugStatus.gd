class_name TugStatus
extends PanelContainer
## Tug of War's HUD widget, in the HUD's top-centre slot. Slim, so it sits above the horizon
## and never covers the rope: two rows.
##
##   YOU 260 W  ▕──────●─────▏  220 W BOT
##   Round 2 · 1-0 · Rust Mule          SURGE!
##
## The rope bar fills from the middle toward the winner (green for the rider, red for the bot)
## and the marker sits at p. The watts round to 5 W so the labels change a few times a second,
## not every frame: re-laying out the HUD every frame cost frame time on the tablet.

const BAR_SIZE := Vector2(380, 26)

var p := 0.0
var surge := ""

var _you: Label
var _bot: Label
var _bar: Control
var _info: Label
var _alert: Label
var _you_text := ""
var _bot_text := ""
var _info_text := ""
var _alert_text := ""
var _t := 0.0


func _init() -> void:
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

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_theme_constant_override("separation", 16)
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(top)
	_you = HudTheme.label("YOU 0 W", HudTheme.SMALL, HudTheme.GOOD)
	_you.custom_minimum_size = Vector2(190, 0)
	_you.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	top.add_child(_you)
	_bar = Control.new()
	_bar.custom_minimum_size = BAR_SIZE
	_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	top.add_child(_bar)
	_bot = HudTheme.label("0 W BOT", HudTheme.SMALL, HudTheme.BAD)
	_bot.custom_minimum_size = Vector2(190, 0)
	top.add_child(_bot)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.add_theme_constant_override("separation", 24)
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(bottom)
	_info = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	bottom.add_child(_info)
	_alert = HudTheme.label("", HudTheme.SMALL, HudTheme.WARN)
	_alert.custom_minimum_size = Vector2(200, 0)
	bottom.add_child(_alert)


## `info` is the round line ("Round 2 · 1-0 · Rust Mule"); `alert` a short call to action
## ("SURGE!", "Keep pedaling").
func set_state(rider_watts: float, bot_watts: float, rope: float, surge_state: String, info: String, alert: String) -> void:
	var you_text := "YOU %d W" % (roundi(rider_watts / 5.0) * 5)
	if you_text != _you_text:
		_you_text = you_text
		_you.text = you_text
	var bot_text := "%d W BOT" % (roundi(bot_watts / 5.0) * 5)
	if bot_text != _bot_text:
		_bot_text = bot_text
		_bot.text = bot_text
	if info != _info_text:
		_info_text = info
		_info.text = info
	if alert != _alert_text:
		_alert_text = alert
		_alert.text = alert
	if not is_equal_approx(rope, p) or surge_state != surge:
		p = rope
		surge = surge_state
		_bar.queue_redraw()


func _process(delta: float) -> void:
	if surge != "":
		_t += delta
		_bar.queue_redraw()


func _draw_bar() -> void:
	var r := Rect2(Vector2.ZERO, BAR_SIZE)
	var mid := BAR_SIZE.x * 0.5
	_bar.draw_rect(r, Color(1, 1, 1, 0.16))
	var x := mid + p * mid
	var fill := HudTheme.GOOD if p >= 0.0 else HudTheme.BAD
	_bar.draw_rect(Rect2(minf(mid, x), 3.0, absf(x - mid), BAR_SIZE.y - 6.0), fill)
	_bar.draw_rect(Rect2(mid - 2.0, 0.0, 4.0, BAR_SIZE.y), Color(1, 1, 1, 0.6))
	var marker := Color.WHITE
	if surge == "telegraph":
		marker = HudTheme.WARN
	elif surge == "surge":
		marker = HudTheme.BAD.lerp(Color.WHITE, 0.5 + 0.5 * sin(_t * 14.0))
	_bar.draw_circle(Vector2(x, BAR_SIZE.y * 0.5), BAR_SIZE.y * 0.62, marker)
