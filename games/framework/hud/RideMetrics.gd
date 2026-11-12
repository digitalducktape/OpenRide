class_name RideMetrics
extends PanelContainer
## The shared ride readout in the HUD's ride panel (top left, under the effort badge): cadence,
## power and resistance in three equal columns, each a number at the same size with the same
## small unit underneath (rpm · W · %), and heart rate (bpm) in a fourth while a strap is
## sending (InputBus.heart_rate; rider's ask, 2026-10-27).
##
## A game sets its cadence floor or band with `set_cadence_band(low, high)` and its power target
## with `set_power_band(low, high)`. The rpm turns green in the band, amber just under it and red
## well under; the watts turn gold at the target (inside the band when it has both ends, amber
## over its top). A game whose rules read a smoothed power shows that same number here with
## `set_power_source(callable)` (Watt Lane, #78), so the HUD never shows two different watts.
## A slim tick gauge under a number shows where the
## floor or target sits (filled to the current value, with a white tick at the line to cross):
## self-explanatory without words, so no "floor 85" caption. Columns without a band keep the
## gauge's space empty, so the units line up. Labels only change with their values: re-laying
## out the HUD every frame cost frame time on the tablet.

const UNDER_WARN := 5.0  ## rpm under the floor that still reads amber; below that, red
const VALUE_SIZE := 72
const COLUMN_WIDTH := 170.0
## With the bpm column, every column narrows and its number shrinks, so the top bar still fits
## 1920 px beside the clock ("1888" W still fits).
const VALUE_SIZE_FOUR := 60
const COLUMN_WIDTH_FOUR := 140.0
const COLUMN_GAP := 12
const COLUMN_GAP_FOUR := 6
const GAUGE_SIZE := Vector2(120, 8)
const RPM_SCALE := 130.0  ## the rpm gauge's full scale
const POWER_SCALE := 2.0  ## the watts gauge's full scale, × the target

var cadence_low := -INF
var cadence_high := INF
var power_low := -INF
var power_high := INF

## The three value labels and their units, for layout checks.
var values: Array[Label] = []
var units: Array[Label] = []

var _rpm: Label
var _watts: Label
var _resistance: Label
var _bpm: Label
var _bpm_column: Control
var _row: HBoxContainer
var _rpm_gauge: Control
var _watts_gauge: Control
var _cadence := 0.0
var _power := 0.0
var _power_source := Callable()  ## () -> float: the watts to show instead of the raw reading
var _shown := {}


## `framed`: false inside a shared panel (the HUD's ride panel).
func _init(framed := true) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudTheme.panel_style() if framed else StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", COLUMN_GAP)
	add_child(row)
	_row = row
	_rpm_gauge = _gauge(_draw_rpm_gauge)
	_rpm = _column(row, "rpm", _rpm_gauge)
	_watts_gauge = _gauge(_draw_watts_gauge)
	_watts = _column(row, "W", _watts_gauge)
	_resistance = _column(row, "%", _gauge(Callable()))
	_bpm = _column(row, "bpm", _gauge(Callable()))
	_bpm_column = _bpm.get_parent()
	_bpm_column.visible = false


## The cadence band the game asks for: `low` is a floor, `high` a ceiling (INF for none).
func set_cadence_band(low: float, high := INF) -> void:
	cadence_low = low
	cadence_high = high
	_shown.clear()


## The power band: `low` is a target to reach (e.g. a power bonus), `high` a cap.
func set_power_band(low: float, high := INF) -> void:
	power_low = low
	power_high = high
	_shown.clear()


## The watts this panel shows come from `source` (`() -> float`), the number the game's rules
## use, instead of `InputBus.power`. An empty Callable puts the raw reading back.
func set_power_source(source: Callable) -> void:
	_power_source = source
	_shown.clear()


## The watts the panel shows now.
func shown_power() -> float:
	return float(_power_source.call()) if _power_source.is_valid() else InputBus.power


## Clears the game's bands and power source (`Hud.clear_widgets`, when a game leaves).
func clear_bands() -> void:
	set_cadence_band(-INF)
	set_power_band(-INF)
	_power_source = Callable()


## The watts' colour for `power` against the band: gold from the target (to the band's top, when
## it has one), amber over the top. Compared as shown, in whole watts.
func power_color(power: float) -> Color:
	var shown := float(roundi(power))
	if shown > power_high:
		return HudTheme.WARN
	if power_low > -INF and shown >= power_low:
		return HudTheme.STAR_ON
	return HudTheme.INK


## The rpm's colour for `cadence` against the band.
func cadence_color(cadence: float) -> Color:
	if cadence_low == -INF and cadence_high == INF:
		return HudTheme.INK
	if cadence < cadence_low:
		return HudTheme.WARN if cadence >= cadence_low - UNDER_WARN else HudTheme.BAD
	if cadence > cadence_high:
		return HudTheme.WARN
	return HudTheme.GOOD


func _process(_delta: float) -> void:
	refresh(InputBus.cadence, shown_power(), InputBus.resistance, InputBus.heart_rate)


## `heart_rate` < 0: no strap sending, and the bpm column hides.
func refresh(cadence: float, power: float, resistance: float, heart_rate := -1.0) -> void:
	_show(_rpm, "rpm", str(roundi(cadence)), cadence_color(cadence))
	var watts_color := power_color(power)
	_show(_watts, "watts", str(roundi(power)), watts_color)
	_show(_resistance, "resistance", str(roundi(resistance)), HudTheme.INK)
	var has_heart := heart_rate >= 0.0
	if _bpm_column.visible != has_heart:
		_set_four_columns(has_heart)  # a layout change only when the strap comes or goes
	if has_heart:
		_show(_bpm, "heart_rate", str(roundi(heart_rate)), HudTheme.INK)
	_rpm_gauge.visible = cadence_low > -INF or cadence_high < INF
	_watts_gauge.visible = power_low > -INF or power_high < INF
	if roundi(cadence) != roundi(_cadence):
		_cadence = cadence
		_rpm_gauge.queue_redraw()
	if roundi(power) != roundi(_power):
		_power = power
		_watts_gauge.queue_redraw()


func _set_four_columns(on: bool) -> void:
	_bpm_column.visible = on
	_row.add_theme_constant_override("separation", COLUMN_GAP_FOUR if on else COLUMN_GAP)
	for value in values:
		value.add_theme_font_size_override("font_size", VALUE_SIZE_FOUR if on else VALUE_SIZE)
		(value.get_parent() as Control).custom_minimum_size.x = COLUMN_WIDTH_FOUR if on else COLUMN_WIDTH


func _show(label: Label, key: String, text: String, color: Color) -> void:
	var state := [text, color]
	if _shown.get(key) == state:
		return
	_shown[key] = state
	label.text = text
	label.add_theme_color_override("font_color", color)


## One column: the value, a slot for its gauge, and its unit, centred in an equal width.
func _column(row: HBoxContainer, unit: String, gauge: Control) -> Label:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	box.custom_minimum_size = Vector2(COLUMN_WIDTH, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var value := HudTheme.label("--", VALUE_SIZE)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(value)
	var slot := CenterContainer.new()
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.custom_minimum_size = Vector2(0, GAUGE_SIZE.y + 6)
	slot.add_child(gauge)
	box.add_child(slot)
	var unit_label := HudTheme.label(unit, HudTheme.SMALL, HudTheme.MUTED)
	unit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(unit_label)
	values.append(value)
	units.append(unit_label)
	return value


func _gauge(draw: Callable) -> Control:
	var gauge := Control.new()
	gauge.custom_minimum_size = GAUGE_SIZE
	gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gauge.visible = false
	if draw.is_valid():
		gauge.draw.connect(draw)
	return gauge


func _draw_rpm_gauge() -> void:
	var low := cadence_low if cadence_low > -INF else 0.0
	_draw_tick_gauge(_rpm_gauge, _cadence / RPM_SCALE, low / RPM_SCALE, cadence_color(_cadence))


func _draw_watts_gauge() -> void:
	var line := power_low if power_low > -INF else power_high
	var scale := maxf(line * POWER_SCALE, 1.0)
	var color := power_color(_power)
	if color == HudTheme.INK:
		color = HudTheme.MUTED
	if power_low > -INF and power_high < INF:
		# A band: its span marked on the track, the fill up to the current value.
		scale = maxf(power_high * 1.5, 1.0)
		var s := _watts_gauge.size
		_watts_gauge.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.15))
		_watts_gauge.draw_rect(Rect2(s.x * power_low / scale, 0, s.x * (power_high - power_low) / scale, s.y), Color(HudTheme.STAR_ON, 0.35))
		_watts_gauge.draw_rect(Rect2(0, 0, s.x * clampf(_power / scale, 0.0, 1.0), s.y * 0.5 + 1), color)
		return
	_draw_tick_gauge(_watts_gauge, _power / scale, line / scale, color)


## A slim bar filled to `fill` (0-1) with a white tick at `tick` (0-1).
func _draw_tick_gauge(gauge: Control, fill: float, tick: float, color: Color) -> void:
	var s := gauge.size
	gauge.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.15))
	gauge.draw_rect(Rect2(0, 0, s.x * clampf(fill, 0.0, 1.0), s.y), color)
	var x := s.x * clampf(tick, 0.0, 1.0)
	gauge.draw_rect(Rect2(x - 1.5, -4, 3, s.y + 8), HudTheme.INK)
