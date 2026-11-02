class_name PumpStatus
extends PanelContainer
## Balloon Pump's HUD widget, in the HUD's top-centre slot: the pump's gauge as a bar, the hero
## (UI_STYLE.md §5: "am I over the push line?"). Two rows, at most 800 x 120 px with the longest
## texts (`pump_status_test`):
##
##     214 W  ▕▓▓▓▓▓▓▓▓▓▓▓▓|▒▒▒▒▒▒▒▏  FILLING
##     (●) 12 balloons     RACE 3/5 · 1:24     NEXT (●)
##
## Row 1: the smoothed watts (56 px), the pressure bar (400 x 40: the needle as a fill, green over
## the push line and amber under it, the line as a gold tick with the rest of the scale tinted
## past it) and a state badge: FILLING (green), PUSH! (amber, breathing), TIED! (gold), PEDAL!
## (amber), REST (the break between heats). The badge's word carries the meaning, so colour is
## never alone (§4).
## Row 2: a drawn balloon and the count; in Race the heat's progress and clock (amber in the last
## 10 s); the next balloon's kind as a drawn balloon in its colour and size, gold with a star.
##
## Budget (§8): labels change only on a change (watts round to 5 W, the clock to the second), the
## bar redraws only when the fill or the line moves a pixel, every shape goes through ShapeBatch
## (one draw call a drawing), and PUSH!'s breathing is a scale tween, not a redraw.

const BAR_SIZE := Vector2(400, 40)
const SIDE_WIDTH := 150.0
const BADGE_WIDTH := 180.0
const ICON := Vector2(44, 44)
const BALLOON_COLORS := PumpMeshes.BALLOON_COLORS

var look: GameTheme

var watts: Label
var bar: Control
var badge: PanelContainer
var badge_label: Label
var count_icon: Control
var count_label: Label
var race_label: Label
var next_caption: Label
var next_icon: Control

var _watts_text := ""
var _fill_px := -1
var _line_px := -1
var _over := false
var _state := ""
var _count := -1
var _race_text := ""
var _race_warn := false
var _next := ""
var _fill := 0.0
var _line := 0.5


func _init(theme: GameTheme = null) -> void:
	look = theme if theme else GameTheme.new(Color("ff5fa2"), Color("2b0f2a"), 0.1)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := look.panel_style()
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	style.content_margin_left = 18
	style.content_margin_right = 18
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	add_child(box)

	var top := _row(box)
	var col := HBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	col.alignment = BoxContainer.ALIGNMENT_END
	col.add_theme_constant_override("separation", 4)
	top.add_child(col)
	watts = look.label("0", HudTheme.MEDIUM, GameTheme.INK, true)
	watts.name = "Watts"
	watts.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(watts)
	var unit := _caption("W", GameTheme.MUTED)
	unit.size_flags_vertical = Control.SIZE_SHRINK_END
	col.add_child(unit)
	bar = Control.new()
	bar.name = "PressureBar"
	bar.custom_minimum_size = BAR_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.draw.connect(_draw_bar)
	top.add_child(bar)
	var badge_slot := CenterContainer.new()
	badge_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_slot.custom_minimum_size = Vector2(BADGE_WIDTH, 0)
	top.add_child(badge_slot)
	badge = PanelContainer.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_label = look.label("", HudTheme.SMALL, GameTheme.INK, true)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(badge_label)
	badge_slot.add_child(badge)

	var bottom := _row(box)
	bottom.add_theme_constant_override("separation", 10)
	count_icon = _icon("CountIcon", _draw_count_icon)
	bottom.add_child(count_icon)
	count_label = _caption("", GameTheme.INK)
	count_label.name = "Count"
	count_label.custom_minimum_size = Vector2(200, 0)
	bottom.add_child(count_label)
	race_label = _caption("", GameTheme.TARGET)
	race_label.name = "Race"
	race_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	race_label.custom_minimum_size = Vector2(250, 0)
	bottom.add_child(race_label)
	next_caption = _caption(tr("NEXT"), GameTheme.MUTED)
	next_caption.name = "NextCaption"
	bottom.add_child(next_caption)
	next_icon = _icon("NextIcon", _draw_next_icon)
	bottom.add_child(next_icon)
	set_state(0.0, 0.0, 0.3, "filling")
	set_count(0)
	set_race(0, 0, -1.0)
	set_next("small")


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


## A 34 px caption on the panel (ink at 86%, not the 3D scene), so no outline: plain captions of
## one size batch into one draw call (Tug's TugStatus).
func _caption(text: String, color: Color) -> Label:
	var l := look.label(text, HudTheme.SMALL, color, true)
	l.add_theme_constant_override("outline_size", 0)
	return l


func _icon(node_name: String, painter: Callable) -> Control:
	var c := Control.new()
	c.name = node_name
	c.custom_minimum_size = ICON
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.pivot_offset = ICON * 0.5
	c.draw.connect(painter)
	return c


## Every frame: the smoothed watts, the needle and the push line (0-1 along the gauge's scale),
## and the state: "filling", "push" (under the line), "tied", "pedal" or "rest".
func set_state(smoothed_watts: float, needle: float, line: float, state: String) -> void:
	var text := str(roundi(smoothed_watts / 5.0) * 5)
	if text != _watts_text:
		_watts_text = text
		watts.text = text
	_fill = clampf(needle, 0.0, 1.0)
	_line = clampf(line, 0.0, 1.0)
	var fill_px := roundi(_fill * BAR_SIZE.x)
	var line_px := roundi(_line * BAR_SIZE.x)
	var over := needle >= line
	if fill_px != _fill_px or line_px != _line_px or over != _over:
		_fill_px = fill_px
		_line_px = line_px
		_over = over
		bar.queue_redraw()
	if state != _state:
		_set_badge(state)


func _set_badge(state: String) -> void:
	var was := _state
	_state = state
	var text := ""
	var fill: Color
	match state:
		"filling":
			text = tr("FILLING")
			fill = Color(GameTheme.GOOD.darkened(0.2), 0.96)
		"push":
			text = tr("PUSH!")
			fill = Color(GameTheme.WARN.darkened(0.2), 0.96)
		"tied":
			text = tr("TIED!")
			fill = Color(GameTheme.TARGET.darkened(0.15), 0.96)
		"pedal":
			text = tr("PEDAL!")
			fill = Color(GameTheme.WARN.darkened(0.2), 0.96)
		_:
			text = tr("REST")
			fill = Color(look.panel_edge, 0.9)
	badge.add_theme_stylebox_override("panel", look.badge_style(fill, true))
	badge_label.text = text
	badge.pivot_offset = badge.size * 0.5
	GameTheme.pulse(badge, state == "push" or state == "pedal")
	if state == "tied" and was != "tied":
		GameTheme.pop(badge, 1.3)


## The balloons tied so far; the icon pops on each new one.
func set_count(balloons: int) -> void:
	if balloons == _count:
		return
	var grew := _count >= 0 and balloons > _count
	_count = balloons
	count_label.text = tr("1 balloon") if balloons == 1 else tr("%d balloons") % balloons
	if grew:
		GameTheme.pop(count_icon, 1.35)


## Race: `done` of `target` this heat with `sec_left` on its clock; target 0 hides it (Max).
func set_race(done: int, target: int, sec_left: float) -> void:
	var text := ""
	var warn := false
	if target > 0:
		var s := maxi(ceili(sec_left), 0)
		text = tr("RACE %d/%d · %d:%02d") % [done, target, s / 60, s % 60]
		warn = sec_left <= PumpLogic.WARN_SEC
	if text != _race_text:
		_race_text = text
		race_label.text = text
	if warn != _race_warn:
		_race_warn = warn
		race_label.add_theme_color_override("font_color", GameTheme.WARN if warn else GameTheme.TARGET)


## The balloon waiting on the rack.
func set_next(kind: String) -> void:
	if kind == _next:
		return
	_next = kind
	next_icon.queue_redraw()
	if kind == "gold":
		GameTheme.pop(next_icon, 1.35)


func _draw_bar() -> void:
	var b := ShapeBatch.new()
	var w := BAR_SIZE.x
	var h := BAR_SIZE.y
	var r := h * 0.5
	var track := Rect2(Vector2.ZERO, BAR_SIZE)
	# The track (rounded ends), the part past the push line tinted gold.
	_pill(b, track, Color(0.06, 0.02, 0.06, 0.9))
	var line_x := clampf(_line * w, r, w - 2.0)
	_pill(b, Rect2(line_x - r, 4.0, w - line_x + r - 4.0, h - 8.0), Color(GameTheme.TARGET, 0.22))
	# The fill: green over the line, amber under it.
	var fill_w := _fill * w
	if fill_w > 2.0:
		_pill(b, Rect2(4.0, 6.0, maxf(fill_w - 8.0, h - 12.0), h - 12.0), GameTheme.GOOD if _over else GameTheme.WARN)
	# The push line: a gold tick standing proud of the bar, inked.
	b.line(Vector2(line_x, -4.0), Vector2(line_x, h + 4.0), 9.0, look.ink)
	b.line(Vector2(line_x, -2.0), Vector2(line_x, h + 2.0), 5.0, GameTheme.TARGET)
	b.draw(bar)


## A rounded bar inside `rect`: a box with round ends.
static func _pill(b: ShapeBatch, rect: Rect2, color: Color) -> void:
	var r := rect.size.y * 0.5
	if rect.size.x <= rect.size.y:
		b.circle(rect.get_center(), r, color, 16)
		return
	b.line(rect.position + Vector2(r, r), rect.position + Vector2(rect.size.x - r, r), rect.size.y, color)


## A little balloon on a string, in `color`, sized `scale` (1 fills the icon).
static func _balloon(b: ShapeBatch, c: Vector2, scale: float, color: Color, ink: Color, star := false) -> void:
	var rx := 15.0 * scale
	var ry := 18.0 * scale
	var body := c + Vector2(0, -4.0)
	var ring := PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		ring.append(body + Vector2(cos(a) * (rx + 3.0), sin(a) * (ry + 3.0)))
	b.convex(ring, ink)
	ring = PackedVector2Array()
	for i in 20:
		var a := TAU * i / 20.0
		ring.append(body + Vector2(cos(a) * rx, sin(a) * ry))
	b.convex(ring, color)
	b.circle(body + Vector2(-rx * 0.38, -ry * 0.42), 3.5 * scale + 1.0, Color(1, 1, 1, 0.75), 10)
	var knot := body + Vector2(0, ry)
	b.convex(PackedVector2Array([knot + Vector2(-4, 5), knot + Vector2(4, 5), knot]), color.darkened(0.25))
	b.line(knot + Vector2(0, 4), c + Vector2(2, 22), 2.5, Color(1, 1, 1, 0.8))
	if star:
		b.star(body, 7.0 * scale, Color.WHITE)


func _draw_count_icon() -> void:
	var b := ShapeBatch.new()
	_balloon(b, ICON * 0.5, 1.0, PumpMeshes.BALLOON_COLORS.medium, look.ink)
	b.draw(count_icon)


func _draw_next_icon() -> void:
	if _next == "":
		return
	var b := ShapeBatch.new()
	var r: float = PumpMeshes.BALLOON_RADIUS[_next] / PumpMeshes.BALLOON_RADIUS.large
	_balloon(b, ICON * 0.5, lerpf(0.7, 1.0, r), BALLOON_COLORS[_next], look.ink, _next == "gold")
	b.draw(next_icon)
