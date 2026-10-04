class_name RideMetrics
extends PanelContainer
## The shared ride readout every game shows in the HUD's bottom-left corner: cadence (big),
## power and resistance, readable at a glance while riding.
##
## A game sets its cadence target with `set_cadence_band(low, high)` (e.g. Dodge Ball's floor)
## and its power target with `set_power_band(low, high)`. The rpm turns green inside the band and
## amber below it (red well below), and the band shows beside it ("floor 85"), so the rider knows
## at once when they're under it. Values only touch the labels when they change: re-laying out
## the HUD every frame cost frame time on the tablet.

const UNDER_WARN := 5.0  ## rpm under the floor that still reads amber; below that, red

var cadence_low := -INF
var cadence_high := INF
var power_low := -INF
var power_high := INF

var _rpm: Label
var _rpm_band: Label
var _watts: Label
var _watts_band: Label
var _resistance: Label
var _shown := {}


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudTheme.panel_style())
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 28)
	add_child(row)
	var rpm_box := _column(row)
	_rpm = HudTheme.label("--", HudTheme.BIG)
	_rpm.custom_minimum_size = Vector2(130, 0)
	_rpm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rpm_box.add_child(_rpm)
	_rpm_band = HudTheme.label("rpm", HudTheme.SMALL, HudTheme.MUTED)
	_rpm_band.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	rpm_box.add_child(_rpm_band)
	var watts_box := _column(row)
	_watts = HudTheme.label("--", HudTheme.MEDIUM)
	watts_box.add_child(_watts)
	_watts_band = HudTheme.label("watts", HudTheme.SMALL, HudTheme.MUTED)
	watts_box.add_child(_watts_band)
	var res_box := _column(row)
	_resistance = HudTheme.label("--", HudTheme.MEDIUM)
	res_box.add_child(_resistance)
	res_box.add_child(HudTheme.label("resist.", HudTheme.SMALL, HudTheme.MUTED))


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


func clear_bands() -> void:
	set_cadence_band(-INF)
	set_power_band(-INF)


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
	refresh(InputBus.cadence, InputBus.power, InputBus.resistance)


func refresh(cadence: float, power: float, resistance: float) -> void:
	_show(_rpm, "rpm", str(roundi(cadence)), cadence_color(cadence))
	var band := "rpm"
	if cadence_low > -INF and cadence_high < INF:
		band = "%d–%d rpm" % [roundi(cadence_low), roundi(cadence_high)]
	elif cadence_low > -INF:
		band = "floor %d rpm" % roundi(cadence_low)
	_show(_rpm_band, "rpm_band", band, HudTheme.MUTED)
	var watts_color := HudTheme.INK
	if power_low > -INF and power >= power_low:
		watts_color = HudTheme.STAR_ON
	elif power_high < INF and power > power_high:
		watts_color = HudTheme.WARN
	_show(_watts, "watts", str(roundi(power)), watts_color)
	var watts_band := "watts"
	if power_low > -INF:
		watts_band = "W · target %d" % roundi(power_low)
	elif power_high < INF:
		watts_band = "W · cap %d" % roundi(power_high)
	_show(_watts_band, "watts_band", watts_band, HudTheme.MUTED)
	_show(_resistance, "resistance", "%d%%" % roundi(resistance), HudTheme.INK)


func _show(label: Label, key: String, text: String, color: Color) -> void:
	var state := [text, color]
	if _shown.get(key) == state:
		return
	_shown[key] = state
	label.text = text
	label.add_theme_color_override("font_color", color)


func _column(row: HBoxContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 0)
	box.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(box)
	return box
