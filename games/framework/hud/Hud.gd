class_name Hud
extends CanvasLayer
## The standard in-game HUD that Session puts over every game (docs/GAMES.md, "HUD kit").
##
## Every element sits in a container slot, so nothing overlaps in any state and nothing has a
## hand-placed position. Everything persistent sits above the horizon or at the edges, so the
## road (or any game's playfield) stays clear from the horizon down:
##
##   Frame (MarginContainer, full screen)
##   └ Rows (VBox)
##     ├ sensor banner                       (only on sensor loss)
##     ├ TopBar (HBox)
##     │  ├ Left (expand):   the ride panel: effort multiplier and gauge, then rpm (with the
##     │  │                  game's floor or band), watts and resistance
##     │  ├ Centre:          the game's own status widgets (`add_widget`), compact
##     │  └ Right (expand):  time left over the score in one panel, [Music |] Pause | End under it
##     │                     (Music while the rider's own music app has a track: opens the panel;
##     │                     it hangs left of the column, which keeps its width: `_ButtonRow`)
##     ├ Middle (expand):    a brief centred message (`show_message`), translucent
##     ├ status slot:        the camera strip ("Camera steering is off", …), when showing
##     └ BottomBar (HBox):   Recalibrate on the right (camera games)
##
## Left and Right expand equally, so the centre column stays centred. The game's title and
## role aren't shown during play: the intro card names the game. Games reach the HUD as `hud`:
## they add widgets in `_on_prepare`, set the metrics' bands, and show messages; Session clears
## all three when the game leaves.

signal pause_pressed
signal end_pressed
signal recalibrate_pressed
## The Music button: SessionDirector opens the music panel (it doesn't pause).
signal music_pressed
## The status widgets or the button row moved on screen: a game keeping its callouts clear of them
## looks again.
signal top_bar_moved

const LAYER := 10
const GAP := 16
const SIDE_BUTTON_WIDTH := 160.0
const MUSIC_BUTTON_WIDTH := 110.0
const MESSAGE_ALPHA := 0.85
## About what the clock panel gives back at `HudTheme.MEDIUM`: the top bar has to have this spare
## before the clock grows again.
const CLOCK_SQUEEZE_PX := 60.0

var timer: SegmentTimer
var score: BigNumber
var effort: EffortBadge
var metrics: RideMetrics
var sensor_banner: SensorBanner
var music_button: Button  ## only while the rider's music app has a track (Session.now_playing)
var pause_button: Button
var end_button: Button
var recalibrate_button: Button
## Where the calibration overlay's camera strip lives during play (see CalibrationOverlay).
var status_slot: HBoxContainer
## The persistent panels (for layout checks): the ride panel, the clock-and-score panel, the
## buttons and the game's widget row.
var ride_panel: PanelContainer
var clock_panel: PanelContainer

var frame: MarginContainer
var top_bar: HBoxContainer
var bottom_bar: HBoxContainer
var circuit_strip: CircuitStrip
var _widgets: HBoxContainer
var _message: Label
var _score_text := ""
var _clock_squeezed := false  ## `_fit_clock`: the time and score at `HudTheme.MEDIUM`
var _message_left := 0.0  ## seconds until a timed message hides (`show_message`); 0: it stays
var _paused := false
var _message_pop := false  ## a skin's `message_font`: the message pops in
## What `set_skin` overrode, to put back: [Control, kind, name, had_override, old value].
var _skin_saved: Array = []


func _init() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	frame = MarginContainer.new()
	frame.name = "Frame"
	# The canvas is always 1920x1080 (stretch mode canvas_items), so the frame is that size.
	frame.size = Vector2(HudTheme.W, HudTheme.H)
	for side in ["left", "right", "top", "bottom"]:
		frame.add_theme_constant_override("margin_" + side, int(HudTheme.MARGIN))
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var rows := _box(VBoxContainer.new(), frame, "Rows")

	sensor_banner = SensorBanner.new()
	rows.add_child(sensor_banner)

	var top := _box(HBoxContainer.new(), rows, "TopBar")
	top_bar = top
	var left := _box(VBoxContainer.new(), top, "Left")
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ride_panel = _panel(left, "RidePanel")
	ride_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var ride := _box(VBoxContainer.new(), ride_panel, "Ride")
	effort = EffortBadge.new(false)
	ride.add_child(effort)
	metrics = RideMetrics.new(false)
	ride.add_child(metrics)

	var centre := _box(VBoxContainer.new(), top, "Centre")
	centre.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	circuit_strip = CircuitStrip.new()
	centre.add_child(circuit_strip)
	_widgets = _box(_WidgetRow.new(), centre, "Widgets")
	(_widgets as _WidgetRow).moved.connect(func(): top_bar_moved.emit())
	_widgets.alignment = BoxContainer.ALIGNMENT_CENTER

	var right := _box(VBoxContainer.new(), top, "Right")
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_panel = _panel(right, "ClockPanel")
	clock_panel.size_flags_horizontal = Control.SIZE_SHRINK_END
	clock_panel.custom_minimum_size = Vector2(2 * SIDE_BUTTON_WIDTH + GAP, 0)
	var clock := _box(VBoxContainer.new(), clock_panel, "Clock")
	clock.add_theme_constant_override("separation", 0)
	timer = SegmentTimer.new(true)
	clock.add_child(timer)
	score = BigNumber.new("score", "0", HudTheme.INK, true)
	score.tight_from = 5
	clock.add_child(score)
	var buttons := _ButtonRow.new()
	buttons.name = "Buttons"
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	buttons.size_flags_horizontal = Control.SIZE_SHRINK_END
	right.add_child(buttons)
	buttons.moved.connect(func(): top_bar_moved.emit())
	# A drawn note rather than the word: three text buttons are wider than the right column, so
	# it hangs off the row's left end (`_ButtonRow`), under the status widget's end.
	music_button = HudTheme.button("", func(): music_pressed.emit())
	music_button.name = "Music"
	music_button.tooltip_text = "Music"
	music_button.custom_minimum_size = Vector2(MUSIC_BUTTON_WIDTH, HudTheme.BUTTON_HEIGHT * 0.8)
	var note := _NoteIcon.new()
	note.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	music_button.add_child(note)
	buttons.add_child(music_button)
	Session.now_playing_changed.connect(func(track: Dictionary): music_button.visible = not track.is_empty())
	music_button.visible = not Session.now_playing.is_empty()
	pause_button = HudTheme.button("Pause", func(): pause_pressed.emit())
	pause_button.custom_minimum_size = Vector2(SIDE_BUTTON_WIDTH, HudTheme.BUTTON_HEIGHT * 0.8)
	buttons.add_child(pause_button)
	end_button = HudTheme.button("End", func(): end_pressed.emit(), Color(0.45, 0.16, 0.2))
	end_button.custom_minimum_size = Vector2(SIDE_BUTTON_WIDTH, HudTheme.BUTTON_HEIGHT * 0.8)
	buttons.add_child(end_button)

	var middle := CenterContainer.new()
	middle.name = "Middle"
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_child(middle)
	_message = HudTheme.label("", HudTheme.BIG)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_constant_override("outline_size", 16)
	_message.modulate.a = MESSAGE_ALPHA
	_message.visible = false
	middle.add_child(_message)

	status_slot = _box(HBoxContainer.new(), rows, "StatusSlot")
	status_slot.alignment = BoxContainer.ALIGNMENT_CENTER

	top.minimum_size_changed.connect(_fit_clock)

	var bottom := _box(HBoxContainer.new(), rows, "BottomBar")
	bottom_bar = bottom
	bottom.alignment = BoxContainer.ALIGNMENT_END
	recalibrate_button = HudTheme.button("Recalibrate", func(): recalibrate_pressed.emit())
	recalibrate_button.size_flags_vertical = Control.SIZE_SHRINK_END
	recalibrate_button.visible = false
	bottom.add_child(recalibrate_button)


## A session starts: a circuit shows its progress strip, anything else hides it.
func set_plan(plan: Dictionary) -> void:
	circuit_strip.set_plan(plan)


## Fills the HUD for a new segment.
func setup(info: GameInfo, segment: Dictionary) -> void:
	clear_widgets()
	recalibrate_button.visible = info.uses_camera()
	circuit_strip.set_segment(int(segment.get("index", 0)), float(segment.get("duration_sec", 0)))


## Adds a game widget under the timer.
func add_widget(widget: Control) -> void:
	_widgets.add_child(widget)


func clear_widgets() -> void:
	for child in _widgets.get_children():
		child.queue_free()
	metrics.clear_bands()
	hide_message()
	clear_skin()


## Opt-in restyling of the persistent panels for a game with its own look (Kart Race). Every key
## is optional: `font` (Font) for every label and button, `outline_color` (Color) and
## `outline_size` (int) for the labels, `panel` (StyleBox) for the ride and clock panels,
## `button` (StyleBox, with `button_pressed`) for Pause, End and Recalibrate, `end_button` for End.
## Layout, sizes, colours that carry meaning (the rpm band, the effort glow) and every number
## stay the framework's. Games that never call it look exactly as before; `clear_skin` (and
## `clear_widgets`, when a game leaves) puts everything back.
##
## Three layout keys let a game with its own ride readout slim the HUD down (Kart Race draws a
## ride-metrics strip at the bottom centre and a big item button in the top-right corner):
## `ride_panel: false` hides the ride panel (the game then shows rpm, watts, resistance and the
## effort multiplier itself); `clock_value_size` (int) shrinks the time left and the score (never
## below `HudTheme.MEDIUM`); `reserve_right` (px) keeps that much of the top bar's right end free,
## so the clock and Pause | End sit just left of it. Every button keeps its full touch size.
##
## Four more keys move the touch targets and the camera strip for a game that needs the bottom
## right (Kart Race's item button): `recalibrate_top: true` puts Recalibrate in the top bar, left
## of Pause | End (End keeps the corner), styled by `recalibrate_button` (StyleBox) if given;
## `status_width` (px) narrows the camera strip's row to that width, centred (its text wraps);
## `reserve_bottom` (px) keeps that much free under it (the game's own bottom widgets; without
## it, the emptied bottom bar folds away and the strip sits on the bottom margin). A game can move
## the strip later with `set_status_area` (Kart Race's boards).
##
## Two keys style the centre message (`show_message`): `message_font` (Font; the message then
## pops in, `GameTheme.pop`, whenever it appears or its text changes) and
## `message_outline_color` (Color). `GameTheme.hud_skin()` sets both.
func set_skin(skin: Dictionary) -> void:
	clear_skin()
	_squeeze_clock(false)
	if skin.has("message_font"):
		_skin_set(_message, "font", "font", skin.message_font)
		_message_pop = true
	if skin.has("message_outline_color"):
		_skin_set(_message, "color", "font_outline_color", skin.message_outline_color)
	if bool(skin.get("recalibrate_top", false)):
		var buttons := pause_button.get_parent()
		_skin_saved.append([recalibrate_button, "parent", &"", true, [recalibrate_button.get_parent(), recalibrate_button.get_index()]])
		recalibrate_button.reparent(buttons, false)
		buttons.move_child(recalibrate_button, 0)
		_skin_set(recalibrate_button, "property", "size_flags_vertical", Control.SIZE_FILL)
		_skin_set(recalibrate_button, "property", "custom_minimum_size", Vector2(0, HudTheme.BUTTON_HEIGHT * 0.8))
	if float(skin.get("status_width", 0.0)) > 0.0 or float(skin.get("reserve_bottom", 0.0)) > 0.0:
		set_status_area(float(skin.get("status_width", 0.0)), float(skin.get("reserve_bottom", 0.0)))
	elif bool(skin.get("recalibrate_top", false)):
		_skin_set(bottom_bar, "property", "visible", false)  # empty: the strip takes the bottom edge
	if skin.has("ride_panel") and not bool(skin.ride_panel):
		_skin_set(ride_panel, "property", "visible", false)
	if skin.has("clock_value_size"):
		var size := maxi(int(skin.clock_value_size), HudTheme.MEDIUM)
		for node in clock_panel.find_children("*", "Label", true, false):
			var value := node as Label
			if value.get_theme_font_size("font_size") > HudTheme.MEDIUM:
				_skin_set(value, "font_size", "font_size", size)
	if float(skin.get("reserve_right", 0.0)) > 0.0:
		var spacer := Control.new()
		spacer.name = "ReservedRight"
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.custom_minimum_size = Vector2(float(skin.reserve_right), 0)
		top_bar.add_child(spacer)
		_skin_saved.append([spacer, "node", &"", false, null])
	var labels: Array[Node] = []
	for root in [ride_panel, clock_panel]:
		labels.append_array(root.find_children("*", "Label", true, false))
	for node in labels:
		var l := node as Label
		if skin.has("font"):
			_skin_set(l, "font", "font", skin.font)
		if skin.has("outline_color"):
			_skin_set(l, "color", "font_outline_color", skin.outline_color)
		if skin.has("outline_size"):
			_skin_set(l, "constant", "outline_size", maxi(int(skin.outline_size), l.get_theme_font_size("font_size") / 10))
	if skin.has("panel"):
		for panel in [ride_panel, clock_panel]:
			_skin_set(panel, "stylebox", "panel", skin.panel)
	for b: Button in [music_button, pause_button, end_button, recalibrate_button]:
		if skin.has("font"):
			_skin_set(b, "font", "font", skin.font)
		var style: StyleBox = skin.get("button")
		if b == end_button and skin.has("end_button"):
			style = skin.end_button
		elif b == recalibrate_button and skin.has("recalibrate_button"):
			style = skin.recalibrate_button
		if style:
			for state in ["normal", "hover", "disabled"]:
				_skin_set(b, "stylebox", state, style)
			_skin_set(b, "stylebox", "pressed", skin.get("button_pressed", style))


## Moves the camera strip's row while a skin is on, without re-skinning (a re-skin re-lays out
## every label): `width` (px, 0 = full) centred, `reserve_bottom` (px) kept free under it; with
## none and Recalibrate moved up, the emptied bottom bar folds away. `clear_skin` undoes it.
func set_status_area(width: float, reserve_bottom: float) -> void:
	_skin_set(status_slot, "property", "size_flags_horizontal", Control.SIZE_SHRINK_CENTER if width > 0.0 else Control.SIZE_FILL)
	_skin_set(status_slot, "property", "custom_minimum_size", Vector2(maxf(width, 0.0), 0))
	_skin_set(bottom_bar, "property", "custom_minimum_size", Vector2(0, maxf(reserve_bottom, 0.0)))
	_skin_set(bottom_bar, "property", "visible", reserve_bottom > 0.0 or recalibrate_button.get_parent() == bottom_bar)


func clear_skin() -> void:
	_squeeze_clock(false)
	_message_pop = false
	for i in range(_skin_saved.size() - 1, -1, -1):
		var entry: Array = _skin_saved[i]
		var c: Control = entry[0]
		if not is_instance_valid(c):
			continue
		var kind: String = entry[1]
		var key: StringName = entry[2]
		var had: bool = entry[3]
		match kind:
			"node":
				c.get_parent().remove_child(c)
				c.queue_free()
			"property":
				c.set(key, entry[4])
			"parent":
				var home: Node = entry[4][0]
				if is_instance_valid(home):
					c.reparent(home, false)
					home.move_child(c, mini(int(entry[4][1]), home.get_child_count() - 1))
			"font_size":
				c.remove_theme_font_size_override(key)
				if had:
					c.add_theme_font_size_override(key, entry[4])
			"font":
				c.remove_theme_font_override(key)
				if had:
					c.add_theme_font_override(key, entry[4])
			"color":
				c.remove_theme_color_override(key)
				if had:
					c.add_theme_color_override(key, entry[4])
			"constant":
				c.remove_theme_constant_override(key)
				if had:
					c.add_theme_constant_override(key, entry[4])
			"stylebox":
				c.remove_theme_stylebox_override(key)
				if had:
					c.add_theme_stylebox_override(key, entry[4])
	_skin_saved.clear()


## The top bar too wide for the screen (a heart strap's column, the widest status widget and a long
## clock together) would push End off it: the time and score drop to `HudTheme.MEDIUM` until there's
## room again. Every other state keeps the big clock.
func _fit_clock() -> void:
	var spare := HudTheme.W - 2.0 * HudTheme.MARGIN - top_bar.get_combined_minimum_size().x
	if spare < 0.0:
		_squeeze_clock(true)
	elif spare >= CLOCK_SQUEEZE_PX:
		_squeeze_clock(false)


func _squeeze_clock(on: bool) -> void:
	if on == _clock_squeezed:
		return
	_clock_squeezed = on
	# The panel keeps its height, so the buttons under it stay put.
	clock_panel.custom_minimum_size.y = clock_panel.size.y if on else 0.0
	timer.set_value_size(HudTheme.MEDIUM if on else 0)
	score.set_value_size(HudTheme.MEDIUM if on else 0)


func _skin_set(c: Control, kind: String, key: StringName, value: Variant) -> void:
	match kind:
		"property":
			_skin_saved.append([c, kind, key, true, c.get(key)])
			c.set(key, value)
		"font_size":
			_skin_saved.append([c, kind, key, c.has_theme_font_size_override(key), c.get_theme_font_size(key)])
			c.add_theme_font_size_override(key, value)
		"font":
			_skin_saved.append([c, kind, key, c.has_theme_font_override(key), c.get_theme_font(key) if c.has_theme_font_override(key) else null])
			c.add_theme_font_override(key, value)
		"color":
			_skin_saved.append([c, kind, key, c.has_theme_color_override(key), c.get_theme_color(key)])
			c.add_theme_color_override(key, value)
		"constant":
			_skin_saved.append([c, kind, key, c.has_theme_constant_override(key), c.get_theme_constant(key)])
			c.add_theme_constant_override(key, value)
		"stylebox":
			_skin_saved.append([c, kind, key, c.has_theme_stylebox_override(key), c.get_theme_stylebox(key) if c.has_theme_stylebox_override(key) else null])
			c.add_theme_stylebox_override(key, value)


## A short centred message over the middle of the screen ("Game over! Next run in 5").
## Shows `text` in the middle of the screen. With `seconds` it hides by itself after that long
## (the countdown stops while the game is paused); without, it stays until `hide_message`.
func show_message(text: String, color := HudTheme.INK, seconds := 0.0) -> void:
	_message_left = maxf(seconds, 0.0)
	var fresh := text != _message.text or not _message.visible
	_message.text = text
	_message.add_theme_color_override("font_color", color)
	_message.visible = true
	if fresh and _message_pop:
		GameTheme.pop(_message, 1.15)


func hide_message() -> void:
	_message.visible = false
	_message_left = 0.0


func is_showing_message() -> bool:
	return _message.visible


func set_paused(paused: bool) -> void:
	_paused = paused
	pause_button.text = "Resume" if paused else "Pause"


func _process(delta: float) -> void:
	if _message_left > 0.0 and not _paused:
		_message_left -= delta
		if _message_left <= 0.0:
			hide_message()
	var shown := str(Effort.whole_points(Effort.score))
	if shown != _score_text:
		_score_text = shown
		score.set_value(shown)


func _panel(parent: Control, node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.add_theme_stylebox_override("panel", HudTheme.panel_style())
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _box(box: BoxContainer, parent: Control, node_name: String) -> BoxContainer:
	box.name = node_name
	box.add_theme_constant_override("separation", GAP)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(box)
	return box


## The status widgets' row, saying when it moves (a circuit's strip pushes it down).
class _WidgetRow extends HBoxContainer:
	signal moved

	func _init() -> void:
		set_notify_transform(true)

	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSFORM_CHANGED:
			moved.emit()


## [Music |] Pause | End, packed against the right. The Music button first in the row doesn't count
## towards the row's width: it hangs off the left end, so a track showing leaves the top bar's
## columns as they were (with it counted, the widest status widget and ride panel pushed End off
## the screen). Kart Race's row starts with Recalibrate and has room saved for all of it, so there
## every button counts.
class _ButtonRow extends Container:
	signal moved

	func _init() -> void:
		set_notify_transform(true)

	func _shown() -> Array[Control]:
		var out: Array[Control] = []
		for child in get_children():
			if child is Control and (child as Control).visible:
				out.append(child)
		return out

	func _hangs(c: Control) -> bool:
		return c.name == &"Music" and c.get_index() == 0

	func _get_minimum_size() -> Vector2:
		var total := Vector2.ZERO
		var counted := 0
		for c in _shown():
			var m := c.get_combined_minimum_size()
			total.y = maxf(total.y, m.y)
			if not _hangs(c):
				total.x += m.x
				counted += 1
		total.x += GAP * maxi(counted - 1, 0)
		return total

	func _notification(what: int) -> void:
		if what == NOTIFICATION_TRANSFORM_CHANGED:
			moved.emit()
		if what != NOTIFICATION_SORT_CHILDREN:
			return
		var x := size.x
		var shown := _shown()
		shown.reverse()
		for c in shown:
			var w := c.get_combined_minimum_size().x
			x -= w
			fit_child_in_rect(c, Rect2(x, 0.0, w, size.y))
			x -= GAP


## The Music button's note, drawn (the faces have no ♪); it follows the button's text colour.
class _NoteIcon extends Control:
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var b := ShapeBatch.new()
		b.note(size / 2.0, 0.85, Color.WHITE)
		b.draw(self)
