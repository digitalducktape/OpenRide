class_name TargetBand
extends Control
## A horizontal gauge with a target band, e.g. a cadence floor (60 rpm and up) or a power cap
## (up to 90 W). The marker turns green inside the band and amber outside it.
##
##   var band := TargetBand.new("cadence", 0, 130, 60, INF, "rpm")
##   band.source = func(): return InputBus.cadence
##   hud.add_widget(band)

var caption := ""
var unit := ""
var min_value := 0.0
var max_value := 100.0
var band_low := -INF  ## -INF: no floor
var band_high := INF  ## INF: no cap
## Polled every frame when set; otherwise call set_value().
var source := Callable()
var value := 0.0

var _label: Label


func _init(caption_text := "", lowest := 0.0, highest := 100.0, low := -INF, high := INF, unit_text := "") -> void:
	caption = caption_text
	min_value = lowest
	max_value = highest
	band_low = low
	band_high = high
	unit = unit_text
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(640, 120)
	_label = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	_label.position = Vector2(0, 0)
	add_child(_label)


func set_band(low: float, high: float) -> void:
	band_low = low
	band_high = high
	queue_redraw()


func set_value(v: float) -> void:
	value = v
	queue_redraw()


func in_band() -> bool:
	return value >= band_low and value <= band_high


func _process(_delta: float) -> void:
	if source.is_valid():
		set_value(float(source.call()))
	_label.text = "%s  %d %s  (%s)" % [caption, roundi(value), unit, _band_text()]


func _band_text() -> String:
	if band_low > -INF and band_high < INF:
		return "%d-%d" % [band_low, band_high]
	if band_low > -INF:
		return "%d+" % band_low
	if band_high < INF:
		return "max %d" % band_high
	return "any"


func _draw() -> void:
	var bar := Rect2(0, 56, size.x, 44)
	draw_rect(bar, Color(1, 1, 1, 0.12))
	var lo := _x(maxf(band_low, min_value))
	var hi := _x(minf(band_high, max_value))
	draw_rect(Rect2(lo, bar.position.y, maxf(hi - lo, 0.0), bar.size.y), Color(HudTheme.GOOD, 0.35))
	var x := _x(clampf(value, min_value, max_value))
	draw_rect(Rect2(x - 6, bar.position.y - 10, 12, bar.size.y + 20), HudTheme.GOOD if in_band() else HudTheme.WARN)


func _x(v: float) -> float:
	return size.x * clampf((v - min_value) / maxf(max_value - min_value, 0.001), 0.0, 1.0)
