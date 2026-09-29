class_name CalibrationOverlay
extends CanvasLayer
## The head tracker's prompted calibration, drawn from calibration_progress (epic #31,
## "Calibration flow"): 3-2-1 while sitting centred, lean left, lean right, and lean in / sit
## back for lean_2d. It shows only in camera games:
##   - while calibrating (tracker_state 2, or progress arrived in the last second)
##   - "tap to calibrate" when the tracker needs calibration (tracker_state 1)
##   - a slim "can't see you" strip when the face is lost (tracker_state 4)
##   - a slim "camera steering is off" strip when a calibration ended in tracker_state 0 (no
##     face found after two tries)
## Tapping it asks for a recalibration (`recalibrate_requested`), except while a calibration
## runs. It shows the step (with its
## 3-2-1 for the centre), "step 2 of 3" (step_index, step_count), the attempt and the
## retry_reason from calibration_progress.

signal recalibrate_requested

const LAYER := 25
const RECENT_MSEC := 1000
const CENTRE_COUNT := 3  ## the centre step's 3-2-1
## Modes in which a tap asks for a calibration; never "calibrating".
const TAPPABLE_MODES := ["needs", "lost", "unavailable"]

const PROMPTS := {
	"centre": "Sit centred and look at the screen",
	"left": "Lean comfortably left",
	"right": "Lean comfortably right",
	"in": "Lean in towards the screen",
	"back": "Sit back",
}
const RETRY_REASONS := {
	"unstable": "Hold still for a moment",
	"no_face": "Can't see you. Face the screen: is the room bright enough?",
	"too_small": "Lean a little further",
	"wrong_direction": "Other way!",
}
const ARROWS := {"left": Vector2.LEFT, "right": Vector2.RIGHT, "in": Vector2.UP, "back": Vector2.DOWN}

## Set by Session: whether the game on screen uses the camera.
var camera_game := false
var mode := ""  ## "", "calibrating", "needs", "lost" or "unavailable": what is showing

var _full: Control
var _strip: PanelContainer
var _strip_text: Label
var _prompt: Label
var _count: Label
var _detail: Label
var _retry: Label
var _bar: ColorRect
var _arrow: Control
var _step := ""
var _fraction := 0.0


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_full = ColorRect.new()
	_full.color = Color(0.03, 0.04, 0.09, 0.88)
	_full.size = Vector2(HudTheme.W, HudTheme.H)
	_full.mouse_filter = Control.MOUSE_FILTER_STOP
	_full.gui_input.connect(_on_gui_input)
	add_child(_full)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 24)
	box.position = Vector2(0, 120)
	box.size = Vector2(HudTheme.W, HudTheme.H - 240)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full.add_child(box)
	_detail = _centred(box, HudTheme.SMALL, HudTheme.MUTED)
	_prompt = _centred(box, HudTheme.BIG)
	_arrow = Control.new()
	_arrow.custom_minimum_size = Vector2(0, 200)
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.draw.connect(_draw_arrow)
	box.add_child(_arrow)
	_count = _centred(box, HudTheme.HUGE, HudTheme.WARN)
	_retry = _centred(box, HudTheme.BODY, HudTheme.WARN)
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.12)
	track.custom_minimum_size = Vector2(900, 24)
	track.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(track)
	_bar = ColorRect.new()
	_bar.color = HudTheme.GOOD
	_bar.size = Vector2(0, 24)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(_bar)

	_strip = PanelContainer.new()
	_strip.add_theme_stylebox_override("panel", HudTheme.panel_style(Color(0.35, 0.2, 0.05, 0.92), 0))
	_strip.position = Vector2(0, HudTheme.H - 100)
	_strip.custom_minimum_size = Vector2(HudTheme.W, 100)
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP
	_strip.gui_input.connect(_on_gui_input)
	add_child(_strip)
	_strip_text = HudTheme.label("", HudTheme.BODY)
	_strip_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_strip.add_child(_strip_text)
	_show("")


func _process(_delta: float) -> void:
	_show(_mode_now())
	if mode == "calibrating":
		_update_progress(Session.calibration)


## What to show for the tracker's state and the latest progress.
func _mode_now() -> String:
	if not camera_game or not Session.active:
		return ""
	var progress: Dictionary = Session.calibration
	var recent := not progress.is_empty() and Time.get_ticks_msec() - int(progress.get("at_msec", 0)) < RECENT_MSEC
	if InputBus.tracker_state == InputBus.TRACKER_CALIBRATING or recent:
		return "calibrating"
	if InputBus.tracker_state == InputBus.TRACKER_NEEDS_CALIBRATION:
		return "needs"
	if InputBus.tracker_state == InputBus.TRACKER_FACE_LOST:
		return "lost"
	if InputBus.tracker_state == InputBus.TRACKER_OFF and not progress.is_empty() and Session.tracker_mode != "off":
		# Calibration ended in 0: the camera is unavailable (no face found after two tries).
		return "unavailable"
	return ""


func _show(new_mode: String) -> void:
	mode = new_mode
	visible = not mode.is_empty()
	_full.visible = mode == "calibrating" or mode == "needs"
	_strip.visible = mode == "lost" or mode == "unavailable"
	if mode == "needs":
		_step = ""
		_detail.text = "CAMERA"
		_prompt.text = "Tap to calibrate the camera"
		_count.text = ""
		_retry.text = "Sit centred, then lean when asked"
		_bar.size.x = 0
		_arrow.queue_redraw()
	elif mode == "lost":
		_strip_text.text = "Can't see you: face the screen  ·  tap to recalibrate"
	elif mode == "unavailable":
		_strip_text.text = "Camera steering is off: no face found. Is the room bright enough?  ·  tap to try again"


## Draws the latest calibration_progress (Session.calibration).
func _update_progress(progress: Dictionary) -> void:
	if progress.is_empty():
		return  # tracker_state is 2 but the first progress hasn't arrived yet
	_step = progress.step
	_fraction = clampf(progress.fraction, 0.0, 1.0)
	_prompt.text = PROMPTS.get(_step, _step.capitalize())
	var parts := PackedStringArray(["CALIBRATING"])
	if progress.step_count > 1:
		parts.append("STEP %d OF %d" % [progress.step_index + 1, progress.step_count])
	if progress.attempt > 1:
		parts.append("TRY %d" % progress.attempt)
	_detail.text = "  ·  ".join(parts)
	_count.text = str(maxi(1, ceili(CENTRE_COUNT * (1.0 - _fraction)))) if _step == "centre" and _fraction < 1.0 else ""
	_retry.text = RETRY_REASONS.get(progress.retry_reason, "")
	_bar.size.x = 900.0 * _fraction
	_arrow.queue_redraw()


func _draw_arrow() -> void:
	var direction: Vector2 = ARROWS.get(_step, Vector2.ZERO)
	var centre := _arrow.size / 2
	if direction == Vector2.ZERO:
		# Centre: a ring to look at.
		_arrow.draw_arc(centre, 70, 0, TAU, 48, HudTheme.GOOD, 10)
		return
	var tip := centre + direction * 90
	var tail := centre - direction * 90
	var side := direction.orthogonal() * 50
	_arrow.draw_line(tail, tip - direction * 40, HudTheme.GOOD, 24)
	_arrow.draw_colored_polygon(PackedVector2Array([tip, tip - direction * 70 + side, tip - direction * 70 - side]), HudTheme.GOOD)


## A tap asks for a calibration only when none is running: "tap to calibrate", "can't see you"
## and "camera off". During a calibration the screen still takes the tap (so it can't skip the
## intro card underneath) but ignores it: on the bike, stray taps restarted runs mid-step.
## SessionDirector debounces what gets through.
func _on_gui_input(event: InputEvent) -> void:
	if visible and mode in TAPPABLE_MODES and event is InputEventMouseButton and event.pressed:
		recalibrate_requested.emit()


func _centred(box: Container, font_size: int, color := HudTheme.INK) -> Label:
	var label := HudTheme.label("", font_size, color)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(label)
	return label
