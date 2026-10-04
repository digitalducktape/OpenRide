class_name EffortBadge
extends PanelContainer
## The effort multiplier on the HUD: a resistance gauge (30% and 60% marked) and an
## "Effort ×1.3" badge that glows as it climbs. Hidden in segments with `effort: false`.

const GAUGE_SIZE := Vector2(320, 26)

var _badge: Label
var _hint: Label
var _gauge: Control
var _shown_multiplier := -1.0
var _shown_resistance := -1


## `framed`: false inside a shared panel (the HUD's ride panel).
func _init(framed := true) -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudTheme.panel_style() if framed else StyleBoxEmpty.new())
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_badge = HudTheme.label("Effort ×1.0", HudTheme.BODY, HudTheme.EFFORT)
	box.add_child(_badge)
	_gauge = Control.new()
	_gauge.custom_minimum_size = GAUGE_SIZE
	_gauge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gauge.draw.connect(_draw_gauge)
	box.add_child(_gauge)
	_hint = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	box.add_child(_hint)


func _process(_delta: float) -> void:
	visible = Effort.enabled
	if not visible:
		return
	var m := snappedf(Effort.multiplier, 0.1)
	var hint: String
	if InputBus.cadence < EffortMeter.MIN_CADENCE and InputBus.resistance > EffortMeter.RESISTANCE_FLOOR:
		hint = "pedal %d+ rpm for it" % EffortMeter.MIN_CADENCE
	elif InputBus.resistance < EffortMeter.RESISTANCE_FLOOR + EffortMeter.RESISTANCE_SPAN:
		hint = "more resistance scores more"
	else:
		hint = "max bonus"
	# Text and theme overrides re-lay out the HUD, so they change only with the values: doing it
	# every frame cost frame time on the tablet.
	if m != _shown_multiplier:
		_shown_multiplier = m
		_badge.text = "Effort ×%.1f" % m
		# 1.0 → plain orange, 1.5 → bright and glowing.
		var glow := clampf((m - 1.0) / EffortMeter.MAX_BONUS, 0.0, 1.0)
		_badge.add_theme_color_override("font_color", HudTheme.EFFORT.lerp(Color(1, 0.95, 0.6), glow))
		_badge.add_theme_constant_override("outline_size", 6 + int(glow * 14))
		_badge.add_theme_color_override("font_outline_color", Color(1, 0.4, 0.0, 0.25 + glow * 0.5))
	if hint != _hint.text:
		_hint.text = hint
	var resistance := roundi(InputBus.resistance)
	if resistance != _shown_resistance:
		_shown_resistance = resistance
		_gauge.queue_redraw()


func _draw_gauge() -> void:
	var s := _gauge.size
	_gauge.draw_rect(Rect2(Vector2.ZERO, s), Color(1, 1, 1, 0.12))
	var fill := clampf(InputBus.resistance / 100.0, 0.0, 1.0)
	_gauge.draw_rect(Rect2(0, 0, s.x * fill, s.y), HudTheme.EFFORT)
	for mark in [EffortMeter.RESISTANCE_FLOOR, EffortMeter.RESISTANCE_FLOOR + EffortMeter.RESISTANCE_SPAN]:
		var x: float = s.x * mark / 100.0
		_gauge.draw_rect(Rect2(x - 2, -6, 4, s.y + 12), HudTheme.INK)
