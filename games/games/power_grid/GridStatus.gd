class_name GridStatus
extends PanelContainer
## Power Grid's HUD widget, in the HUD's top-centre slot (UI_STYLE.md §5: "am I keeping the town
## lit?"). Two rows, at most 800 x 120 px with the longest texts (`grid_layout_test`):
##
##     ▕▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓|▒▒▒▒▒▒▒▒▒▏  POWERED
##     [house] [lamp] [wheel] [stadium]    FUNFAIR NEXT
##
## Row 1: the supply bar (560 x 40: the fill is the supply, green when it's meeting demand and amber
## when it isn't; the gold tick is what meets demand, or the repair during a storm) and a state
## badge: POWERED (green), SHORT! (amber, breathing), PEDAL! (amber), REPAIR (gold, the bar's tick
## moved up), EASY (a calm blue: over an easy role's cap the extra gains nothing). The watts are
## the ride panel's: one number on screen, from the same smoothed supply the rules use.
## Row 2: the four districts as drawn pips, lit in their colour, dark, or broken; and one line of
## what's next. A word comes with every colour (§4).
##
## Budget (§8): labels change only on a change, the bar and the pips redraw only when they move a
## pixel, every shape goes through ShapeBatch (one draw call a drawing).

const BAR_SIZE := Vector2(560, 40)
const BADGE_WIDTH := 200.0
const PIP := Vector2(66, 54)
const ROW2 := HudTheme.SMALL + 6  ## 40 px: read at a glance from the saddle
const NOTE_WIDTH := 430.0
const CALM := Color("6fb7ff")
const DISTRICT_COLORS := [Color("ffd27a"), Color("ffe9a8"), Color("ff8fa0"), Color("bfe3ff")]

var look: GameTheme

var bar: GaugeBar
var badge: PanelContainer
var badge_label: Label
var pips: Control
var note: Label

var _good := false
var _state := ""
var _fill := 0.0
var _line := 0.5
var _pip_key := PackedInt32Array()
var _pip_states := PackedInt32Array([0, 0, 0, 0])
var _note := ""


func _init(theme: GameTheme = null) -> void:
	look = theme if theme else GameTheme.house()
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
	bar = GaugeBar.new(BAR_SIZE, look.ink)
	bar.name = "SupplyBar"
	top.add_child(bar)
	var slot := CenterContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(BADGE_WIDTH, 0)
	top.add_child(slot)
	badge = PanelContainer.new()
	badge.name = "Badge"
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge_label = look.label("", HudTheme.SMALL, GameTheme.INK, true)
	badge_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(badge_label)
	slot.add_child(badge)
	var bottom := _row(box)
	bottom.add_theme_constant_override("separation", 14)
	pips = Control.new()
	pips.name = "Districts"
	pips.custom_minimum_size = Vector2(PIP.x * 4.0, PIP.y)
	pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pips.draw.connect(_draw_pips)
	bottom.add_child(pips)
	note = look.label("", ROW2, GameTheme.TARGET, true)
	note.name = "Note"
	note.add_theme_constant_override("outline_size", 0)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.custom_minimum_size = Vector2(NOTE_WIDTH, 0)
	bottom.add_child(note)
	set_state(0.0, 0.5, "powered")
	set_districts(PackedInt32Array([1, 0, 0, 0]))


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	return row


## Every frame: the supply and the line (0-1 along the bar's scale), and the state: "powered",
## "short", "pedal", "repair" or "easy".
func set_state(supply: float, line: float, state: String) -> void:
	_fill = clampf(supply, 0.0, 1.0)
	_line = clampf(line, 0.0, 1.0)
	var good := state == "powered" or state == "easy" or (state == "repair" and _fill >= _line)
	_good = good
	bar.set_line(_line)
	bar.set_fill(_fill, GameTheme.GOOD if good else GameTheme.WARN)
	if state != _state:
		_set_badge(state)


func _set_badge(state: String) -> void:
	_state = state
	var text := ""
	var fill: Color
	match state:
		"powered":
			text = tr("POWERED")
			fill = Color(GameTheme.GOOD.darkened(0.2), 0.96)
		"short":
			text = tr("SHORT!")
			fill = Color(GameTheme.WARN.darkened(0.2), 0.96)
		"pedal":
			text = tr("PEDAL!")
			fill = Color(GameTheme.WARN.darkened(0.2), 0.96)
		"repair":
			text = tr("REPAIR")
			fill = Color(GameTheme.TARGET.darkened(0.15), 0.96)
		_:
			text = tr("EASY")
			fill = Color(CALM.darkened(0.25), 0.96)
	badge.add_theme_stylebox_override("panel", look.badge_style(fill, true))
	badge_label.text = text
	badge.pivot_offset = badge.size * 0.5
	GameTheme.pulse(badge, state == "short" or state == "pedal")


## Each district's state: 0 not online yet, 1 lit, 2 dimming, 3 dark (browned out), 4 line down.
func set_districts(states: PackedInt32Array) -> void:
	if states == _pip_states:
		return
	var came_on := -1
	for i in states.size():
		if states[i] == 1 and _pip_states[i] != 1 and _pip_states[i] != 2:
			came_on = i
	_pip_states = states.duplicate()
	pips.queue_redraw()
	if came_on >= 0 and is_inside_tree():
		pips.pivot_offset = Vector2(PIP.x * (came_on + 0.5), PIP.y * 0.5)
		GameTheme.pop(pips, 1.08)


## The line beside the pips, in `color`: what's next, or "" for nothing.
func set_note(text: String, color := GameTheme.TARGET) -> void:
	if text == _note:
		return
	_note = text
	note.text = text
	note.add_theme_color_override("font_color", color)


func _draw_pips() -> void:
	var b := ShapeBatch.new()
	for i in 4:
		var c := Vector2(PIP.x * (i + 0.5), PIP.y * 0.5)
		var state := _pip_states[i]
		var col: Color
		match state:
			1:
				col = DISTRICT_COLORS[i]
			2:
				col = GameTheme.WARN
			3:
				col = Color(GameTheme.MUTED, 0.55)
			4:
				col = GameTheme.BAD
			_:
				col = Color(GameTheme.MUTED, 0.28)
		draw_icon(b, i, c, 1.0, col)
		if state == 3 or state == 4:
			b.line(c + Vector2(-20, 18), c + Vector2(20, -18), 5.0, look.ink)
			b.line(c + Vector2(-20, 18), c + Vector2(20, -18), 3.0, col)
	b.draw(pips)


## District `i`'s icon at `c`, sized `s` (1 fills a pip): a house, a street lamp, a big wheel, a
## stadium with its floodlights. Plain, unmistakable silhouettes (ART_BIBLE.md §5).
static func draw_icon(b: ShapeBatch, i: int, c: Vector2, s: float, col: Color) -> void:
	match i:
		0:
			b.convex(PackedVector2Array([c + Vector2(0, -20) * s, c + Vector2(21, -2) * s, c + Vector2(-21, -2) * s]), col)
			b.convex(PackedVector2Array([c + Vector2(-15, -2) * s, c + Vector2(15, -2) * s, c + Vector2(15, 18) * s, c + Vector2(-15, 18) * s]), col)
		1:
			b.line(c + Vector2(4, 19) * s, c + Vector2(4, -13) * s, 5.0 * s, col)
			b.line(c + Vector2(4, -13) * s, c + Vector2(-11, -15) * s, 5.0 * s, col)
			b.convex(PackedVector2Array([c + Vector2(-19, -9) * s, c + Vector2(-3, -9) * s, c + Vector2(-7, -18) * s, c + Vector2(-15, -18) * s]), col)
			b.line(c + Vector2(-5, 19) * s, c + Vector2(13, 19) * s, 5.0 * s, col)
		2:
			for k in 8:
				var a := TAU * k / 8.0
				b.line(c + Vector2(0, -3) * s, c + (Vector2(0, -3) + Vector2(cos(a), sin(a)) * 17.0) * s, 2.5 * s, col)
				b.circle(c + (Vector2(0, -3) + Vector2(cos(a), sin(a)) * 18.0) * s, 3.4 * s, col, 8)
			b.line(c + Vector2(0, -3) * s, c + Vector2(-11, 20) * s, 3.5 * s, col)
			b.line(c + Vector2(0, -3) * s, c + Vector2(11, 20) * s, 3.5 * s, col)
		_:
			b.convex(PackedVector2Array([c + Vector2(-23, 6) * s, c + Vector2(-13, -3) * s, c + Vector2(13, -3) * s, c + Vector2(23, 6) * s,
				c + Vector2(23, 13) * s, c + Vector2(13, 19) * s, c + Vector2(-13, 19) * s, c + Vector2(-23, 13) * s]), col)
			for side in [-1.0, 1.0]:
				b.line(c + Vector2(side * 20.0, 6) * s, c + Vector2(side * 20.0, -15) * s, 3.5 * s, col)
				b.line(c + Vector2(side * 20.0 - 7.0, -17) * s, c + Vector2(side * 20.0 + 7.0, -17) * s, 6.0 * s, col)
