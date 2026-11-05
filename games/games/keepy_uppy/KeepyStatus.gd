class_name KeepyStatus
extends PanelContainer
## Keepy Uppy's HUD widget, in the HUD's top-centre slot (UX pass, DESIGN.md). One row, content
## centred, at most 800 x 90 px (`keepy_scene_test`):
##
##     ^ ^ ^   [ LOW * ][ MID ** ][ HIGH *** ]   -->
##
## The middle, the hero: the three height bands as chips in the height pole's colours (cream,
## mint, sun). The balloon's band is filled and bold, the others dim outlines, so what the rider
## is earning reads from 1 m at a glance. A chip's stars are the band's worth, one to three, from
## `KeepyLogic.multiplier`: drawn, not "2×", because the ride panel beside it already shows the
## effort multiplier and two multipliers read as a contradiction. Not a points rate either: the
## effort multiplier scales every band, so a "20/s" would be wrong on the score. The count, the
## word and the position all carry the meaning, never colour alone (ART_BIBLE §4).
## Left: the birds perched, a small gull each, with a ring filling toward the 3 s shake. Right,
## with Steer on: the wind's arrow. Warnings are callouts (`KeepyBanner`), in words, not here.
##
## Budget (UI_STYLE.md §8): styles change only on a change; the pips and arrow redraw only when
## their value moves.

const CHIP_SIZE := Vector2(172, 60)
const CHIP_GAP := 10
const STAR_R := 11.0
const STAR_GAP := 3.0
const PIP_W := 26.0
const PIP_GAP := 4.0
const SIDE_SIZE := Vector2(92, 60)  ## each side column, equal so the chips stay centred
const BAND_COLORS := [Color("f2efe6"), Color("8fd0f0"), Color("f5c04a")]
const BAND_NAMES := ["LOW", "MID", "HIGH"]

var look: GameTheme
var chips: Array[PanelContainer] = []
var chip_labels: Array[Label] = []
var chip_stars: Array[Control] = []
var birds_box: Control
var wind_arrow: Control

var _band := -1
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
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", CHIP_GAP)
	add_child(row)

	birds_box = Control.new()
	birds_box.name = "Birds"
	birds_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	birds_box.custom_minimum_size = SIDE_SIZE
	birds_box.draw.connect(_draw_pips)
	row.add_child(birds_box)
	for i in 3:
		var chip := PanelContainer.new()
		chip.name = "Band%s" % BAND_NAMES[i]
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.custom_minimum_size = CHIP_SIZE
		var inside := HBoxContainer.new()
		inside.mouse_filter = Control.MOUSE_FILTER_IGNORE
		inside.alignment = BoxContainer.ALIGNMENT_CENTER
		inside.add_theme_constant_override("separation", 8)
		chip.add_child(inside)
		var l := look.label(tr(BAND_NAMES[i]), HudTheme.SMALL, BAND_COLORS[i], true)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		inside.add_child(l)
		var stars := Control.new()
		stars.name = "Stars"
		stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var count := KeepyLogic.multiplier(i as KeepyLogic.Band)
		stars.custom_minimum_size = Vector2(stars_width(count, STAR_R), CHIP_SIZE.y - 16.0)
		stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stars.draw.connect(_draw_chip_stars.bind(i, count))
		inside.add_child(stars)
		row.add_child(chip)
		chips.append(chip)
		chip_labels.append(l)
		chip_stars.append(stars)
	wind_arrow = Control.new()
	wind_arrow.name = "Wind"
	wind_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wind_arrow.custom_minimum_size = SIDE_SIZE
	wind_arrow.draw.connect(_draw_arrow)
	row.add_child(wind_arrow)
	set_state(KeepyLogic.Band.MID, 0, 0.0, false, 0.0)


## Every frame: the balloon's band, the birds perched and their shake progress (0-1), and with
## `steer` the wind (-1..1, the windsock's).
func set_state(band: int, birds: int, shake: float, steer: bool, wind: float) -> void:
	if band != _band:
		var grew := band > _band and _band >= 0
		_band = band
		for i in 3:
			_style_chip(i, i == band)
		if grew:
			GameTheme.pop(chips[band], 1.15)
	var shake_px := roundi(shake * 20.0)
	if birds != _birds or shake_px != _shake_px:
		var landed := birds > _birds and _birds >= 0
		_birds = birds
		_shake_px = shake_px
		_shake = shake
		birds_box.queue_redraw()
		if landed:
			GameTheme.pop(birds_box, 1.2)
	var w := snappedf(wind, 0.1) if steer else 0.0
	if steer != _steer or absf(w - _wind) > 0.05:
		_steer = steer
		_wind = w
		wind_arrow.queue_redraw()


func _style_chip(i: int, on: bool) -> void:
	var c: Color = BAND_COLORS[i]
	var style := look.badge_style(Color(c, 0.96) if on else Color(look.ink, 0.6), true)
	if not on:
		style.border_color = Color(c, 0.55)
	chips[i].add_theme_stylebox_override("panel", style)
	chip_labels[i].add_theme_color_override("font_color", look.ink if on else Color(c, 0.7))
	chip_labels[i].add_theme_constant_override("outline_size", 0 if on else GameTheme.outline_for(HudTheme.SMALL))
	chip_stars[i].queue_redraw()


func _draw_chip_stars(i: int, count: int) -> void:
	var c: Control = chip_stars[i]
	var col: Color = look.ink if i == _band else Color(BAND_COLORS[i], 0.7)
	draw_stars(c, count, Vector2(STAR_R, c.size.y * 0.5), STAR_R, col)


## The width `count` stars of radius `r` take.
static func stars_width(count: int, r: float) -> float:
	return count * r * 2.0 + (count - 1) * STAR_GAP


## `count` five-pointed stars in a row from `first` (the first star's centre).
static func draw_stars(c: CanvasItem, count: int, first: Vector2, r: float, col: Color) -> void:
	for s in count:
		var at := first + Vector2(s * (r * 2.0 + STAR_GAP), 0.0)
		var pts := PackedVector2Array()
		for k in 10:
			var a := -PI * 0.5 + k * PI / 5.0
			pts.append(at + Vector2.from_angle(a) * (r if k % 2 == 0 else r * 0.45))
		c.draw_colored_polygon(pts, col)


## A gull per perched bird, the wings a shallow chevron (no head or tail: ART_BIBLE §3's
## silhouette rule), dim for an empty perch; only shown with a bird up. A ring round the first
## fills with the shake's progress.
func _draw_pips() -> void:
	if _birds <= 0:
		return
	var y := birds_box.size.y * 0.5
	for i in KeepyLogic.MAX_BIRDS:
		var x := PIP_W * 0.5 + i * (PIP_W + PIP_GAP) + 2.0
		var col := Color("ede6d6") if i < _birds else Color(Color.WHITE, 0.2)
		var wings := PackedVector2Array([Vector2(x - 12, y - 4), Vector2(x - 5, y - 7), Vector2(x, y + 2),
			Vector2(x + 5, y - 7), Vector2(x + 12, y - 4)])
		birds_box.draw_polyline(wings, col, 4.0, true)
	if _shake > 0.0:
		birds_box.draw_arc(Vector2(PIP_W * 0.5 + 2.0, y), PIP_W * 0.5 + 2.0, -PI * 0.5, -PI * 0.5 + TAU * _shake, 24, BAND_COLORS[2], 3.0, true)


## The wind's arrow, with Steer on: points the way the wind blows, longer with its strength; a
## dot when calm.
func _draw_arrow() -> void:
	if not _steer:
		return
	var mid := wind_arrow.size * 0.5
	var col := look.accent
	if absf(_wind) < 0.15:
		wind_arrow.draw_circle(mid, 7.0, col)
		return
	var dir := signf(_wind)
	var length := lerpf(18.0, SIDE_SIZE.x * 0.5 - 6.0, clampf(absf(_wind), 0.0, 1.0))
	var tip := mid + Vector2(dir * length, 0.0)
	var tail := mid - Vector2(dir * length, 0.0)
	wind_arrow.draw_line(tail, tip - Vector2(dir * 8.0, 0.0), col, 7.0, true)
	wind_arrow.draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-dir * 16.0, -12.0), tip + Vector2(-dir * 16.0, 12.0)]), col)
