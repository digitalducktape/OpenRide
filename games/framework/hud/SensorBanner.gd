class_name SensorBanner
extends PanelContainer
## "Sensors not detected" across the top while `sensors_ok` is 0 (contract, "Sensor loss").
## Scoring is frozen meanwhile: `Effort.award` returns 0. The ride keeps recording in Kotlin.


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_stylebox_override("panel", HudTheme.panel_style(HudTheme.BAD, 0))
	var text := HudTheme.label("Sensors not detected — scoring paused", HudTheme.MEDIUM)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(text)
	visible = false


func _process(_delta: float) -> void:
	visible = not InputBus.sensors_ok
