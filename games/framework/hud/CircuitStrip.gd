class_name CircuitStrip
extends VBoxContainer
## The circuit progress strip (#37): above the game's own widgets in the HUD's top-centre slot, a
## row of pills, one per segment, and a line of text. Pills are as wide as their segment is long
## and take the role's colour (work warm, recovery cool); done segments are dimmed, the current
## one is outlined and fills as it plays, and the rest are faint. The line says where you are and
## how long the circuit has left. Shown only in a circuit.

const BAR_WIDTH := 760.0
const BAR_HEIGHT := 16.0
const GAP := 4.0
const MIN_PILL := 10.0
const INTRO_SEC := 10  ## the card before each segment, which the plan's total includes

var segments: Array = []  ## [{game_id, role, duration_sec}] from session_started
var index := 0  ## the current segment
var _bar: Control
var _label: Label
var _left_sec := 0.0  ## gameplay seconds left in the current segment
var _text := ""


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 2)
	_bar = Control.new()
	_bar.custom_minimum_size = Vector2(BAR_WIDTH, BAR_HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.draw.connect(_draw_bar)
	add_child(_bar)
	_label = HudTheme.label("", HudTheme.SMALL, HudTheme.MUTED)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_label)
	visible = false


## A circuit starts: `plan` is the session_started payload. Anything but a circuit hides the strip.
func set_plan(plan: Dictionary) -> void:
	segments = plan.get("segments", []) if str(plan.get("kind", "")) == "circuit" else []
	index = 0
	visible = not segments.is_empty()
	_refresh(0.0)
	_bar.queue_redraw()


## The segment at `new_index` starts.
func set_segment(new_index: int, duration_sec: float) -> void:
	index = clampi(new_index, 0, maxi(segments.size() - 1, 0))
	_refresh(duration_sec)
	_bar.queue_redraw()


## Seconds of the circuit left: the rest of the current segment, plus every later segment and the
## card before it.
func remaining_sec(current_left: float) -> float:
	var total := maxf(current_left, 0.0)
	for i in range(index + 1, segments.size()):
		total += float(segments[i].get("duration_sec", 0)) + INTRO_SEC
	return total


func _process(_delta: float) -> void:
	if not visible or segments.is_empty():
		return
	var left := InputBus.segment_time_left
	if left < 0.0:
		return
	if absf(left - _left_sec) >= 0.5:
		_refresh(left)
		_bar.queue_redraw()


func _refresh(current_left: float) -> void:
	_left_sec = current_left
	var text := ""
	if not segments.is_empty():
		text = "%d of %d · %s left" % [index + 1, segments.size(), HudTheme.clock(remaining_sec(current_left))]
	if text != _text:
		_text = text
		_label.text = text


func _draw_bar() -> void:
	if segments.is_empty():
		return
	var total := 0.0
	for s in segments:
		total += float(s.get("duration_sec", 1))
	var usable := BAR_WIDTH - GAP * (segments.size() - 1)
	var x := 0.0
	for i in segments.size():
		var seg: Dictionary = segments[i]
		var width := maxf(usable * float(seg.get("duration_sec", 1)) / total, MIN_PILL)
		var color: Color = HudTheme.ROLE_COLORS.get(str(seg.get("role", "free")), HudTheme.ROLE_COLORS.free)
		var rect := Rect2(x, 0, width, BAR_HEIGHT)
		if i < index:
			_bar.draw_rect(rect, Color(color, 0.7))
		elif i == index:
			_bar.draw_rect(rect, Color(color, 0.3))
			var duration := float(seg.get("duration_sec", 0))
			var done := clampf(1.0 - _left_sec / duration, 0.0, 1.0) if duration > 0.0 else 0.0
			_bar.draw_rect(Rect2(x, 0, width * done, BAR_HEIGHT), color)
			_bar.draw_rect(rect.grow(1.0), Color.WHITE, false, 2.0)
		else:
			_bar.draw_rect(rect, Color(color, 0.3))
		x += width + GAP
