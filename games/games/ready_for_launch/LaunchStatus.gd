class_name LaunchStatus
extends PanelContainer
## Ready for Launch's HUD widget, in the HUD's top-centre slot. One row, at most 800 x 90 px:
##
##     [ FUEL ]  [=========|-----]  72%          on the ground: the tank
##     [ PUSH ]  [==|===|==|==---]  412 km       in flight: the climb, a tick per milestone
##
## Watts never show here: they're once only, in the ride panel. No "×" either: the ride panel's
## effort badge owns that sign, so the tank reads as a percentage and the climb as kilometres.
## Budget (UI_STYLE.md §8): text and styles change only when their value does, and the bar
## redraws only when its fill moves a pixel.

const CHIP_SIZE := Vector2(190, 62)
const BAR_SIZE := Vector2(262, 34)
const VALUE_W := 256.0
const CHIP_GOOD := Color("2fd6c8")

var look: GameTheme
var chip: PanelContainer
var chip_label: Label
var value: Label
var bar: GaugeBar

var _chip_text := ""
var _chip_color := Color.BLACK
var _value_text := ""


func _init(theme: GameTheme = null) -> void:
	look = theme if theme else GameTheme.new(CHIP_GOOD, Color("0a1a2e"), 0.1)
	name = "LaunchStatus"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := look.panel_style()
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	style.content_margin_left = 12
	style.content_margin_right = 14
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	add_child(row)
	chip = PanelContainer.new()
	chip.name = "Chip"
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.custom_minimum_size = CHIP_SIZE
	row.add_child(chip)
	chip_label = look.label("", 40, look.ink, true)
	chip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip_label.add_theme_constant_override("outline_size", 0)
	chip.add_child(chip_label)
	bar = GaugeBar.new(BAR_SIZE, look.ink)
	bar.name = "Bar"
	row.add_child(bar)
	value = look.label("", 52, GameTheme.INK, true)
	value.custom_minimum_size = Vector2(VALUE_W, 0)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(value)


## The whole widget: the phase word on its chip, a 0-1 fill with its ticks, the figure beside it.
func show_state(word: String, chip_color: Color, fill: float, fill_color: Color, figure: String, ticks: Array[float] = []) -> void:
	if word != _chip_text or chip_color != _chip_color:
		var pop := word != _chip_text and _chip_text != ""
		_chip_text = word
		_chip_color = chip_color
		chip_label.text = tr(word)
		chip.add_theme_stylebox_override("panel", look.badge_style(chip_color, true))
		if pop:
			GameTheme.pop(chip, 1.12)
	if figure != _value_text:
		_value_text = figure
		value.text = figure
	bar.set_fill(fill, fill_color)
	bar.set_ticks(ticks)

