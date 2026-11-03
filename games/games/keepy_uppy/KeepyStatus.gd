class_name KeepyStatus
extends PanelContainer
## Keepy Uppy's HUD widget, in the HUD's top-centre slot (UX pass, DESIGN.md). Two rows, at most
## 800 x 120 px with the longest texts (`keepy_status_test`):
##
##     [ LOW 1× ][ MID 2× ][ HIGH 3× ]
##       ● ● ○ BIRDS      RAIN CLOUD!       WIND ▶
##
## Row 1, the hero: the three height bands as chips in the height pole's colours (cream, mint,
## sun). The balloon's band is filled and bold, the others dim outlines, so the multiplier the
## rider is earning reads from 1 m at a glance; position carries the meaning too (left = low),
## never colour alone (ART_BIBLE §4).
## Row 2: what the weather is doing, in one badge ("RAIN CLOUD!", "BIRD!", "DOWNDRAFT! PUSH!",
## "GUST", then "RAINING" while it rains), the birds perched (a pip each, with a ring filling
## toward the 3 s shake), and with Steer on the wind's arrow.
##
## Budget (UI_STYLE.md §8): labels and styles change only on a change; the pips and arrow redraw
## only when their value moves; the warning's breathing is a scale tween on the badge.

const CHIP_SIZE := Vector2(196, 56)
const CHIP_GAP := 10
const ROW2_HEIGHT := 46.0
const PIP := 22.0
const PIP_GAP := 6.0
const PIPS_WIDTH := 3 * PIP + 2 * PIP_GAP + 8.0
const ARROW_SIZE := Vector2(60, 40)
const SIDE_WIDTH := 200.0  ## each side column of row 2
const BAND_COLORS := [Color("f2efe6"), Color("8fd0f0"), Color("f5c04a")]
const BAND_NAMES := ["LOW", "MID", "HIGH"]
## Warnings by force: the text and its fill.
const WARNINGS := {
	"rain": ["RAIN CLOUD!", Color(0.38, 0.47, 0.6)],
	"bird": ["BIRD!", Color(0.3, 0.36, 0.46)],
	"downdraft": ["DOWNDRAFT!", Color(0.86, 0.22, 0.22)],
	"gust": ["GUST", Color(0.55, 0.62, 0.72)],
	"raining": ["RAINING", Color(0.33, 0.4, 0.52)],
	"new": ["NEW BALLOON", Color(0.2, 0.55, 0.48)],
}

var look: GameTheme
var chips: Array[PanelContainer] = []
var chip_labels: Array[Label] = []
var badge: PanelContainer
var badge_label: Label
var birds_box: Control
var birds_caption: Label
var wind_box: Control
var wind_arrow: Control
var wind_caption: Label

var _band := -1
var _warning := "-"
var _birds := -1
var _shake_px := -1
var _shake := 0.0
var _wind := 99.0
var _steer := false


func _init(theme: GameTheme = null) -> void:
	look = theme if theme else GameTheme.new(Color("ff7a59"), Color("12233a"), 0.08)
	name = "KeepyStatus"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := look.panel_style()
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.content_margin_left = 18
	style.content_margin_right = 18
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	add_child(box)

	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	top.add_theme_constant_override("separation", CHIP_GAP)
	box.add_child(top)
	for i in 3:
		var chip := PanelContainer.new()
		chip.name = "Band%s" % BAND_NAMES[i]
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = CHIP_SIZE
		var l := look.label("%s %d×" % [tr(BAND_NAMES[i]), KeepyLogic.multiplier(i as KeepyLogic.Band)], HudTheme.SMALL + 4, BAND_COLORS[i], true)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		chip.add_child(l)
		top.add_child(chip)
		chips.append(chip)
		chip_labels.append(l)

	var bottom := HBoxContainer.new()
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_CENTER
	bottom.custom_minimum_size = Vector2(0, ROW2_HEIGHT)
	bottom.add_theme_constant_override("separation", 8)
	box.add_child(bottom)
	birds_box = HBoxContainer.new()
	birds_box.name = "Birds"
	birds_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	birds_box.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	(birds_box as HBoxContainer).add_theme_constant_override("separation", 6)
	bottom.add_child(birds_box)
	var pips := Control.new()
	pips.name = "Pips"
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.custom_minimum_size = Vector2(PIPS_WIDTH, ROW2_HEIGHT)
	pips.draw.connect(_draw_pips.bind(pips))
	birds_box.add_child(pips)
	birds_caption = _caption(tr("BIRDS"))
	birds_box.add_child(birds_caption)
	badge = PanelContainer.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	badge_label = look.label("", HudTheme.SMALL, GameTheme.INK, true)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(badge_label)
	var centre := CenterContainer.new()
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	centre.custom_minimum_size = Vector2(320, 0)
	centre.add_child(badge)
	bottom.add_child(centre)
	wind_box = HBoxContainer.new()
	wind_box.name = "Wind"
	wind_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_box.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	(wind_box as HBoxContainer).alignment = BoxContainer.ALIGNMENT_END
	(wind_box as HBoxContainer).add_theme_constant_override("separation", 6)
	bottom.add_child(wind_box)
	wind_caption = _caption(tr("WIND"))
	wind_box.add_child(wind_caption)
	wind_arrow = Control.new()
	wind_arrow.name = "Arrow"
	wind_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_arrow.custom_minimum_size = ARROW_SIZE
	wind_arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wind_arrow.draw.connect(_draw_arrow)
	wind_box.add_child(wind_arrow)
	set_state(KeepyLogic.Band.MID, "", 0, 0.0, false, 0.0)


## A 34 px caption on the panel, without an outline (one batched draw, as Tug's captions).
func _caption(text: String) -> Label:
	var l := look.label(text, HudTheme.SMALL, GameTheme.MUTED, true)
	l.add_theme_constant_override("outline_size", 0)
	return l


## Every frame: the balloon's band, the weather's warning key ("" or a WARNINGS key), the birds
## perched and their shake progress (0-1), and with `steer` the wind (-1..1, the windsock's).
func set_state(band: int, warning: String, birds: int, shake: float, steer: bool, wind: float) -> void:
	if band != _band:
		var grew := band > _band and _band >= 0
		_band = band
		for i in 3:
			_style_chip(i, i == band)
		if grew:
			GameTheme.pop(chips[band], 1.15)
	if warning != _warning:
		_warning = warning
		_refresh_badge()
	var shake_px := roundi(shake * 20.0)
	if birds != _birds or shake_px != _shake_px:
		var landed := birds > _birds and _birds >= 0
		_birds = birds
		_shake_px = shake_px
		_shake = shake
		birds_box.modulate.a = 1.0 if birds > 0 else 0.0
		birds_box.get_node("Pips").queue_redraw()
		if landed:
			GameTheme.pop(birds_box, 1.2)
	var w := snappedf(wind, 0.1) if steer else 0.0
	if steer != _steer or absf(w - _wind) > 0.05:
		_steer = steer
		_wind = w
		wind_box.modulate.a = 1.0 if steer else 0.0
		wind_arrow.queue_redraw()


func _style_chip(i: int, on: bool) -> void:
	var c: Color = BAND_COLORS[i]
	var style := look.badge_style(Color(c, 0.96) if on else Color(look.ink, 0.6), true)
	if not on:
		style.border_color = Color(c, 0.55)
	chips[i].add_theme_stylebox_override("panel", style)
	chip_labels[i].add_theme_color_override("font_color", look.ink if on else Color(c, 0.7))
	chip_labels[i].add_theme_constant_override("outline_size", 0 if on else GameTheme.outline_for(HudTheme.SMALL))


func _refresh_badge() -> void:
	GameTheme.pulse(badge, false)
	if _warning == "" or not WARNINGS.has(_warning):
		badge.modulate.a = 0.0
		return
	badge.modulate.a = 1.0
	var w: Array = WARNINGS[_warning]
	badge_label.text = tr(w[0])
	var style := look.badge_style(Color(w[1], 0.96), true)
	badge.add_theme_stylebox_override("panel", style)
	if _warning in ["rain", "bird", "downdraft", "gust"]:
		GameTheme.pulse(badge, true, 1.08, 0.6)
		GameTheme.pop(badge, 1.2)


## A pip per perched bird (slate on cream), the next empty; a ring round the first fills with the
## shake's progress.
func _draw_pips(c: Control) -> void:
	var y := c.size.y * 0.5
	for i in KeepyLogic.MAX_BIRDS:
		var centre := Vector2(PIP * 0.5 + 4.0 + i * (PIP + PIP_GAP), y)
		c.draw_circle(centre, PIP * 0.5, look.ink)
		var col := Color("ede6d6") if i < _birds else Color(Color.WHITE, 0.15)
		c.draw_circle(centre, PIP * 0.5 - 3.0, col)
	if _birds > 0 and _shake > 0.0:
		var centre := Vector2(PIP * 0.5 + 4.0, y)
		c.draw_arc(centre, PIP * 0.5 + 1.0, -PI * 0.5, -PI * 0.5 + TAU * _shake, 24, BAND_COLORS[2], 3.0, true)


## The wind's arrow: points the way the wind blows, longer with its strength; a dot when calm.
func _draw_arrow() -> void:
	var mid := ARROW_SIZE * 0.5
	var col := look.accent
	if absf(_wind) < 0.15:
		wind_arrow.draw_circle(mid, 7.0, col)
		return
	var dir := signf(_wind)
	var length := lerpf(18.0, ARROW_SIZE.x * 0.5 - 2.0, clampf(absf(_wind), 0.0, 1.0))
	var tip := mid + Vector2(dir * length, 0.0)
	var tail := mid - Vector2(dir * length, 0.0)
	wind_arrow.draw_line(tail, tip - Vector2(dir * 8.0, 0.0), col, 7.0, true)
	wind_arrow.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-dir * 16.0, -12.0), tip + Vector2(-dir * 16.0, 12.0)]), col)
