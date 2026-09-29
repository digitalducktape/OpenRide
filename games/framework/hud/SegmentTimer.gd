class_name SegmentTimer
extends BigNumber
## The segment clock. Counts down `segment_time_left` from Kotlin's clock; in an open-ended
## segment (`segment_time_left` = -1) it counts up the gameplay time Session measures.

const WARN_SEC := 10.0


func _init() -> void:
	super("time left", "--:--")


func _process(_delta: float) -> void:
	var left := InputBus.segment_time_left
	if left < 0.0:
		set_caption("riding")
		set_value(HudTheme.clock(Session.played_sec()))
		set_color(HudTheme.INK)
	else:
		set_caption("time left")
		set_value(HudTheme.clock(left))
		set_color(HudTheme.WARN if left <= WARN_SEC else HudTheme.INK)
