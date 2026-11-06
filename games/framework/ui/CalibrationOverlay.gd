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
## runs. It shows the step (with its 3-2-1 for the centre), "step 2 of 3" (step_index,
## step_count) with a dot per step, the attempt and the retry_reason from calibration_progress.
##
## In the game's look (`apply_theme`, from `Game.ui_theme()`; the house look otherwise):
##
##   CalibrationOverlay (CanvasLayer 25)
##   ├ shade: ColorRect (full rect; takes every touch: `_on_gui_input`)
##   │ └ card: PanelContainer (centred)
##   │   └ VBoxContainer
##   │     ├ HBox: detail ("CALIBRATING · STEP 2 OF 3 · TRY 2") + StepDots
##   │     ├ prompt ("Lean comfortably left"), slammed in on each new step
##   │     ├ HBox: PoseFigure (a drawn rider leaning, inside the step's progress ring) + 3-2-1
##   │     ├ retry hint (or "Got it!")
##   │     └ tap pill ("Tap anywhere to start"; only for "tap to calibrate")
##   └ own slot: MarginContainer > VBox (bottom), for the strip while the HUD is hidden
##   strip: PanelContainer > HBox: camera icon, what to do, "TAP TO RETRY"

signal recalibrate_requested
## Hub mode only: the rider tapped Cancel.
signal cancel_pressed

const LAYER := 25
const STRIP_HEIGHT := 80.0
const RECENT_MSEC := 1000
const CENTRE_COUNT := 3  ## the centre step's 3-2-1
const CARD_SIZE := Vector2(1240, 720)
const PROMPT_SIZE := 64
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
	# The step failed 3 times; calibration moves on with the rider's previous or a default value.
	"used_default": "Using your usual range; recalibrate later if steering feels off",
}
const STRIP_TEXTS := {
	"lost": ["Can't see you: face the camera, and check the room is lit", "TAP TO RECALIBRATE"],
	"unavailable": ["Camera steering is off: no face found. Turn a light on and face the camera", "TAP TO TRY AGAIN"],
}
## A game that reads the rider standing (`lean_stand`) has nothing to steer.
const STAND_UNAVAILABLE := "Can't see you stand: no face found. Turn a light on and face the camera"
const ARROWS := {"left": Vector2.LEFT, "right": Vector2.RIGHT, "in": Vector2.UP, "back": Vector2.DOWN}

## Set by Session: whether the game on screen uses the camera.
var camera_game := false
## The Games hub's calibration (plan phase E, `use_hub_mode`): full screen while the hub's
## calibration runs (`begin_hub` .. `end_hub`), with Cancel; no strips, no "tap to calibrate",
## and no processing at all while idle.
var hub_mode := false
var cancel_button: Button
var _hub_running := false
var _hub_since_msec := 0
var mode := ""  ## "", "calibrating", "needs", "lost" or "unavailable": what is showing
## The look on screen: the game's, or the house look.
var theme: GameTheme

var _full: ColorRect
var _card: PanelContainer
var _strip: PanelContainer
## The HUD's status slot: the strip lives there while the HUD shows, so it takes a row of its own
## above the HUD's bottom bar and never covers Recalibrate. Otherwise (the intro card) it sits in
## this layer's own bottom slot.
var strip_host: Container
var _own_slot: VBoxContainer
var _strip_icon: CameraIcon
var _strip_text: Label
var _strip_action: Label
var _prompt: Label
var _count: Label
var _detail: Label
var _dots: StepDots
var _retry: Label
var _figure: PoseFigure
var _tap_pill: PanelContainer
var _tap_label: Label
var _step := ""
var _fraction := 0.0
var _attempt := 0
var _shown_count := ""
var _shown_retry := ""
var _shown := false


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS

	_full = ColorRect.new()
	_full.mouse_filter = Control.MOUSE_FILTER_STOP
	_full.gui_input.connect(_on_gui_input)
	add_child(_full)
	Stage.bleed(_full)  # the whole window, past the centred stage (#57)
	Stage.changed.connect(_centre_card)
	_card = PanelContainer.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size = CARD_SIZE
	_full.add_child(_card)
	_centre_card()
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(box)

	var head := _hbox(box, 26)
	_detail = Label.new()
	_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(_detail)
	_dots = StepDots.new()
	_dots.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_dots)
	_prompt = _centred(box)
	_prompt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var figure_row := _hbox(box, 40)
	_figure = PoseFigure.new()
	figure_row.add_child(_figure)
	_count = Label.new()
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.custom_minimum_size = Vector2(120, 0)
	figure_row.add_child(_count)
	_retry = _centred(box)
	_retry.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_retry.custom_minimum_size = Vector2(0, 56)
	_tap_pill = PanelContainer.new()
	_tap_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tap_pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tap_pill.custom_minimum_size = Vector2(520, HudTheme.BUTTON_HEIGHT)
	box.add_child(_tap_pill)
	_tap_label = _centred(_tap_pill)
	_tap_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tap_label.text = "Tap anywhere to start"

	var own_frame := MarginContainer.new()
	own_frame.size = Vector2(HudTheme.W, HudTheme.H)
	own_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		own_frame.add_theme_constant_override("margin_" + side, int(HudTheme.MARGIN))
	add_child(own_frame)
	_own_slot = VBoxContainer.new()
	_own_slot.alignment = BoxContainer.ALIGNMENT_END
	_own_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	own_frame.add_child(_own_slot)
	_strip = PanelContainer.new()
	_strip.custom_minimum_size = Vector2(0, STRIP_HEIGHT)
	_strip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip.mouse_filter = Control.MOUSE_FILTER_STOP  # the whole strip is the tap target
	_strip.gui_input.connect(_on_gui_input)
	_own_slot.add_child(_strip)
	var strip_row := HBoxContainer.new()
	strip_row.add_theme_constant_override("separation", 18)
	strip_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_strip.add_child(strip_row)
	_strip_icon = CameraIcon.new()
	_strip_icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	strip_row.add_child(_strip_icon)
	_strip_text = Label.new()
	_strip_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_strip_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_strip_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_strip_text.custom_minimum_size = Vector2(300, 0)
	strip_row.add_child(_strip_text)
	_strip_action = Label.new()
	_strip_action.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	strip_row.add_child(_strip_action)

	for label in [_detail, _prompt, _count, _retry, _tap_label, _strip_text, _strip_action]:
		(label as Label).mouse_filter = Control.MOUSE_FILTER_IGNORE
	apply_theme(null)
	_show("")


## Styles the screen and the strips in a game's look (`Game.ui_theme()`); null gives the house
## look. Layout, text and touch behaviour stay the same.
func apply_theme(new_theme: GameTheme) -> void:
	theme = new_theme if new_theme else GameTheme.house()
	_full.color = Color(theme.ink.darkened(0.3), 0.84)
	_card.add_theme_stylebox_override("panel", theme.card_style())
	theme.style_label(_detail, HudTheme.SMALL, GameTheme.MUTED, true)
	theme.style_label(_prompt, PROMPT_SIZE, GameTheme.INK, true)
	theme.style_label(_count, HudTheme.HUGE, GameTheme.INK, true)
	theme.set_gradient(_count, GameTheme.GOLD_GRADIENT)
	theme.style_label(_retry, HudTheme.BODY, GameTheme.WARN, true)
	theme.style_label(_tap_label, HudTheme.BUTTON_FONT, GameTheme.INK, true)
	_tap_pill.add_theme_stylebox_override("panel", theme.button_style(GameTheme.PRIMARY))
	theme.style_label(_strip_text, HudTheme.SMALL, GameTheme.INK, true)
	_strip_text.add_theme_constant_override("line_spacing", -8)  # two lines still fit a slim strip
	theme.style_label(_strip_action, HudTheme.SMALL, GameTheme.TARGET, true)
	_figure.set_colours(theme.accent, theme.ink)
	_dots.set_colours(theme.accent, theme.ink)
	_strip_icon.ink = theme.ink
	_shown_count = ""
	_shown_retry = ""
	if not mode.is_empty():
		_style_strip()


## Turns this overlay into the hub's: a Cancel button under the figure, and idle until
## `begin_hub`.
## The card in the middle of the stage (`_full` covers the whole window, from `-Stage.pad`).
func _centre_card() -> void:
	_card.position = Stage.pad + (Vector2(HudTheme.W, HudTheme.H) - _card.size) / 2


func use_hub_mode() -> void:
	hub_mode = true
	cancel_button = theme.button("Cancel", func(): cancel_pressed.emit(), GameTheme.SECONDARY)
	cancel_button.name = "Cancel"
	cancel_button.custom_minimum_size = Vector2(320, 120)
	cancel_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_tap_pill.get_parent().add_child(cancel_button)
	_card.size = Vector2(CARD_SIZE.x, CARD_SIZE.y + 120)
	_centre_card()
	set_process(false)
	_show("")


## The hub's calibration started: show it (progress older than now is the last game's).
func begin_hub() -> void:
	_hub_running = true
	_hub_since_msec = Time.get_ticks_msec()
	_shown = false
	_show("calibrating")
	_detail.text = "CAMERA"
	_dots.set_steps(0, 0, false)
	_prompt.text = "Starting the camera…"
	_count.text = ""
	_count.visible = false
	_retry.text = "Sit centred and look at the screen"
	_set_retry_colour(GameTheme.MUTED)
	_figure.show_pose("centre", 0.0, false)
	set_process(true)


func end_hub() -> void:
	_hub_running = false
	_show("")
	set_process(false)


func _process(_delta: float) -> void:
	_show(_mode_now())
	_place_strip()
	if mode == "calibrating":
		_update_progress(Session.calibration)


## What to show for the tracker's state and the latest progress.
func _mode_now() -> String:
	if hub_mode:
		return "calibrating" if _hub_running else ""
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


## The strip goes in the HUD's slot while the HUD is up, else in this layer's own.
func _place_strip() -> void:
	var host: Container = strip_host if strip_host and strip_host.is_visible_in_tree() else _own_slot
	if _strip.get_parent() != host:
		_strip.reparent(host, false)


## The strip, for layout checks.
func strip() -> Control:
	return _strip


## The calibration figure, for checks: its progress ring shows `fraction`.
func figure() -> PoseFigure:
	return _figure


## Shows a mode; called every frame, it changes nothing until the mode does.
func _show(new_mode: String) -> void:
	if _shown and new_mode == mode:
		return
	_shown = true
	var was := mode
	mode = new_mode
	visible = not mode.is_empty()
	_full.visible = mode == "calibrating" or mode == "needs"
	_strip.visible = not hub_mode and (mode == "lost" or mode == "unavailable")
	_tap_pill.visible = mode == "needs"
	GameTheme.pulse(_tap_pill, false)
	if mode != "calibrating":
		GameTheme.pulse(_figure, false)
		_step = ""
		_attempt = 0
	if mode == "needs":
		_detail.text = "CAMERA"
		_dots.set_steps(0, 0, false)
		_prompt.text = "Tap to calibrate the camera"
		_count.text = ""
		_count.visible = false
		_retry.text = "Sit centred, then lean when asked"
		_set_retry_colour(GameTheme.MUTED)
		_figure.show_pose("", 0.0, false)
		GameTheme.pulse(_tap_pill, true, 1.05, 1.1)
		_tap_pill.pivot_offset = _tap_pill.get_combined_minimum_size() / 2.0
		if was != "needs":
			GameTheme.slam(_prompt, 1.3)
	elif mode == "lost" or mode == "unavailable":
		_strip_text.text = strip_text(mode, Session.tracker_mode)
		_strip_action.text = STRIP_TEXTS[mode][1]
		_strip_icon.crossed = mode == "unavailable"
		_style_strip()
		if was != mode:
			GameTheme.pop(_strip, 1.06)


## The strip's words for `strip_mode`, in the camera's `tracker_mode`.
static func strip_text(strip_mode: String, tracker_mode: String) -> String:
	if strip_mode == "unavailable" and tracker_mode == "lean_stand":
		return STAND_UNAVAILABLE
	return STRIP_TEXTS[strip_mode][0]


## The strip's panel: amber for "can't see you" (it may come back by itself), the ink with an
## amber edge for "camera off" (it needs the rider). Words and the icon carry the meaning too.
func _style_strip() -> void:
	var lost := mode == "lost"
	var style := theme.panel_style(Color(GameTheme.WARN.darkened(0.62), 0.95) if lost else Color(theme.ink, 0.95))
	style.border_color = Color(GameTheme.WARN, 0.95 if lost else 0.7)
	style.content_margin_left = 18
	style.content_margin_right = 26
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	_strip.add_theme_stylebox_override("panel", style)


## Draws the latest calibration_progress (Session.calibration).
func _update_progress(progress: Dictionary) -> void:
	if progress.is_empty() or (hub_mode and int(progress.get("at_msec", 0)) < _hub_since_msec):
		return  # tracker_state is 2 but the first progress hasn't arrived yet
	var step: String = progress.step
	var attempt := int(progress.attempt)
	var new_step := step != _step or attempt != _attempt
	_step = step
	_attempt = attempt
	_fraction = clampf(progress.fraction, 0.0, 1.0)
	_prompt.text = PROMPTS.get(_step, _step.capitalize())
	var parts := PackedStringArray(["CALIBRATING"])
	if progress.step_count > 1:
		parts.append("STEP %d OF %d" % [progress.step_index + 1, progress.step_count])
	if progress.attempt > 1:
		parts.append("TRY %d" % progress.attempt)
	_detail.text = "  ·  ".join(parts)
	var done := _fraction >= 1.0
	_dots.set_steps(int(progress.step_count), int(progress.step_index), done)
	var fallback: bool = progress.retry_reason == "used_default"  # fraction counts the 1.5 s notice
	_count.text = str(maxi(1, ceili(CENTRE_COUNT * (1.0 - _fraction)))) if _step == "centre" and _fraction < 1.0 and not fallback else ""
	_count.visible = not _count.text.is_empty()
	_retry.text = RETRY_REASONS.get(progress.retry_reason, "")
	if _retry.text.is_empty() and done:
		_retry.text = "Got it!"
		_set_retry_colour(GameTheme.GOOD)
	else:
		_set_retry_colour(GameTheme.MUTED if fallback else GameTheme.WARN)
	_figure.show_pose(_step, _fraction, done and not fallback)

	# Motion: a new step slams in and the figure breathes while it's held; a new count digit
	# slams; a new hint pops.
	if new_step:
		GameTheme.slam(_prompt, 1.3)
		GameTheme.pulse(_figure, true, 1.04, 1.0)
		_figure.pivot_offset = _figure.custom_minimum_size / 2.0
	if _count.text != _shown_count:
		_shown_count = _count.text
		if not _count.text.is_empty():
			GameTheme.slam(_count, 1.8)
	if _retry.text != _shown_retry:
		_shown_retry = _retry.text
		if not _retry.text.is_empty():
			GameTheme.pop(_retry, 1.15)


## Called every frame of a calibration: the override is set only when the colour changes (each
## one re-shapes the label).
func _set_retry_colour(c: Color) -> void:
	if _retry.has_theme_color_override("font_color") and _retry.get_theme_color("font_color") == c:
		return
	_retry.add_theme_color_override("font_color", c)


## A tap asks for a calibration only when none is running: "tap to calibrate", "can't see you"
## and "camera off". During a calibration the screen still takes the tap (so it can't skip the
## intro card underneath) but ignores it: on the bike, stray taps restarted runs mid-step.
## SessionDirector debounces what gets through.
func _on_gui_input(event: InputEvent) -> void:
	if visible and mode in TAPPABLE_MODES and event is InputEventMouseButton and event.pressed:
		recalibrate_requested.emit()


func _centred(parent: Container) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _hbox(parent: Container, separation: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", separation)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(row)
	return row


## The rider as the camera sees them (a mirror: their left is the screen's left), inside the
## step's progress ring: upright for the centre, leaning for left and right (a faint upright
## ghost behind), bigger with outward arrows for "lean in", smaller with inward ones for "sit
## back", with the way to go in gold outside the ring. A tick badge when the step is done.
## One triangle array (one draw call); it redraws only when the step or progress changes.
class PoseFigure:
	extends Control

	const SIZE := Vector2(660, 360)
	const RING := 164.0
	const LEAN := 0.3
	var fraction := 0.0
	var step := ""
	var done := false
	var accent := Color(0.48, 0.49, 1.0)
	var ink := Color(0.09, 0.08, 0.23)

	func _init() -> void:
		custom_minimum_size = SIZE
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_colours(accent_colour: Color, ink_colour: Color) -> void:
		accent = accent_colour
		ink = ink_colour
		queue_redraw()

	func show_pose(new_step: String, new_fraction: float, is_done: bool) -> void:
		if new_step == step and is_equal_approx(new_fraction, fraction) and is_done == done:
			return
		step = new_step
		fraction = new_fraction
		done = is_done
		queue_redraw()

	func _draw() -> void:
		var b := ShapeBatch.new()
		var c := size / 2.0
		var hip := c + Vector2(0, 118)
		# The ring's well behind the rider; the progress goes on top.
		b.circle(c, RING - 10.0, Color(ink, 0.55), 48)
		if step in ["left", "right", "in", "back"]:
			_rider(b, hip, 0.0, 1.0, Color(1, 1, 1, 0.14), Color(0, 0, 0, 0))
		var angle := -LEAN if step == "left" else (LEAN if step == "right" else 0.0)
		var grow := 1.18 if step == "in" else (0.8 if step == "back" else 1.0)
		_rider(b, hip, angle, grow, Color(0.94, 0.95, 1.0), ink)
		b.arc(c, RING, 0.0, TAU, 18.0, ink, 64)
		if fraction > 0.0:
			var colour := GameTheme.GOOD if done else accent.lightened(0.2)
			b.arc(c, RING, -PI / 2, -PI / 2 + TAU * fraction, 12.0, colour, 64)
			var tip := c + Vector2.from_angle(-PI / 2 + TAU * fraction) * RING
			b.circle(tip, 13.0, ink).circle(tip, 9.0, Color.WHITE)
		_arrows(b, c)
		if done:
			var badge := c + Vector2(RING * 0.72, -RING * 0.72)
			b.circle(badge, 42.0, ink).circle(badge, 35.0, GameTheme.GOOD)
			b.polyline(PackedVector2Array([badge + Vector2(-16, 1), badge + Vector2(-5, 12), badge + Vector2(16, -11)]), 9.0, Color.WHITE)
		b.draw(self)

	## Shoulders (a capsule) and a head with a face, rotated `angle` about the hip and scaled;
	## an `edge` with alpha draws an ink outline under it.
	func _rider(b: ShapeBatch, hip: Vector2, angle: float, grow: float, fill: Color, edge: Color) -> void:
		b.xform = Transform2D(angle, Vector2(grow, grow), 0.0, hip)
		if edge.a > 0.0:
			b.line(Vector2(-44, -44), Vector2(44, -44), 98.0, edge)
			b.circle(Vector2(0, -150), 57.0, edge, 32)
		b.line(Vector2(-44, -44), Vector2(44, -44), 86.0, fill)
		b.circle(Vector2(0, -150), 51.0, fill, 32)
		if edge.a > 0.0:
			b.circle(Vector2(-18, -156), 7.5, edge, 12).circle(Vector2(18, -156), 7.5, edge, 12)
			b.arc(Vector2(0, -148), 21.0, 0.45, PI - 0.45, 6.0, edge, 16)
		b.xform = Transform2D.IDENTITY

	## The way to go, in gold (the thing to aim for), just outside the ring at head height.
	func _arrows(b: ShapeBatch, c: Vector2) -> void:
		var at := Vector2(c.x, c.y - 40.0)
		match step:
			"left", "right":
				var d := Vector2.LEFT if step == "left" else Vector2.RIGHT
				_arrow(b, at + d * (RING + 26.0), d, 104.0)
			"in":
				for d in [Vector2.LEFT, Vector2.RIGHT]:
					_arrow(b, at + d * (RING + 26.0), d, 76.0)
			"back":
				for d in [Vector2.LEFT, Vector2.RIGHT]:
					_arrow(b, at + d * (RING + 104.0), -d, 76.0)

	## A thick arrow from `from` along `d`, gold with an ink edge.
	func _arrow(b: ShapeBatch, from: Vector2, d: Vector2, length: float) -> void:
		var tip := from + d * length
		var back := tip - d * 42.0
		var side := d.orthogonal()
		b.line(from, back, 30.0, ink, false)
		b.convex(PackedVector2Array([tip + d * 9.0, back + side * 44.0 - d * 6.0, back - side * 44.0 - d * 6.0]), ink)
		b.line(from + d * 4.0, back + d * 2.0, 18.0, GameTheme.TARGET, false)
		b.convex(PackedVector2Array([tip, back + side * 34.0, back - side * 34.0]), GameTheme.TARGET)


## A dot per calibration step: done ones green with a tick, the current one bigger in the
## accent, the rest dim. Hidden for a one-step (centre only) run. One draw call.
class StepDots:
	extends Control

	const GAP := 46.0
	var count := 0
	var current := 0
	var current_done := false
	var accent := Color(0.48, 0.49, 1.0)
	var ink := Color(0.09, 0.08, 0.23)

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_colours(accent_colour: Color, ink_colour: Color) -> void:
		accent = accent_colour
		ink = ink_colour
		queue_redraw()

	func set_steps(new_count: int, new_current: int, is_done: bool) -> void:
		visible = new_count > 1
		if new_count == count and new_current == current and is_done == current_done:
			return
		count = new_count
		current = new_current
		current_done = is_done
		custom_minimum_size = Vector2(maxf(count, 1) * GAP, 44)
		queue_redraw()

	func _draw() -> void:
		var b := ShapeBatch.new()
		for i in count:
			var p := Vector2(GAP * (i + 0.5), size.y / 2.0)
			var finished := i < current or (i == current and current_done)
			if finished:
				b.circle(p, 17.0, ink).circle(p, 14.0, GameTheme.GOOD)
				b.polyline(PackedVector2Array([p + Vector2(-6, 0), p + Vector2(-1.5, 5), p + Vector2(7, -5)]), 4.0, Color.WHITE)
			elif i == current:
				b.circle(p, 20.0, Color.WHITE).circle(p, 16.0, accent)
			else:
				b.circle(p, 12.0, Color(1, 1, 1, 0.35)).circle(p, 8.0, Color(ink, 0.9))
		b.draw(self)


## A camera, crossed out in red when steering is off. One draw call.
class CameraIcon:
	extends Control

	var crossed := false:
		set(value):
			crossed = value
			queue_redraw()
	var ink := Color(0.09, 0.08, 0.23):
		set(value):
			ink = value
			queue_redraw()

	func _init() -> void:
		custom_minimum_size = Vector2(64, 56)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var b := ShapeBatch.new()
		var body := GameTheme.WARN
		b.line(Vector2(25, 13), Vector2(39, 13), 12.0, body)
		b.line(Vector2(14, 31), Vector2(50, 31), 36.0, body)  # a rounded body
		b.circle(Vector2(32, 31), 14.0, ink).circle(Vector2(32, 31), 8.0, body.lightened(0.45))
		if crossed:
			b.line(Vector2(8, 52), Vector2(56, 8), 11.0, ink).line(Vector2(8, 52), Vector2(56, 8), 6.0, GameTheme.BAD)
		b.draw(self)
