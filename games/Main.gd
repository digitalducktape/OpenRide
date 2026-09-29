extends Control
## Placeholder main scene for the foundation (#32): shows the live input frame and drives the
## whole session lifecycle over the bridge by hand. The Godot framework (#34) replaces it with
## the scene that loads real games.
##
## Buttons: Pause/Resume, Finish segment (segment_finished), End session (request_end) and,
## after the summary, Exit (request_exit). A segment_ending is answered automatically.

const W := 1920.0
const H := 1080.0
const GAME_ID := "placeholder"
const LOG_LINES := 12

var _mode_label: Label
var _metrics_label: Label
var _tracker_label: Label
var _status_label: Label
var _log_label: Label
var _fps_label: Label
var _cadence_bar: ColorRect
var _resistance_bar: ColorRect
var _sensor_banner: Label
var _intro_card: Label
var _pause_button: Button
var _finish_button: Button
var _end_button: Button
var _exit_button: Button
var _camera_button: Button
var _camera_on := false
var _calibration := ""
var _last_calibration_key := ""

var _log: PackedStringArray = []
var _intro_left := 0.0
var _in_segment := false
var _score := 0.0
var _report_timer := 0.0


func _ready() -> void:
	_build_ui()
	Session.session_started.connect(_on_session_started)
	Session.segment_started.connect(_on_segment_started)
	Session.segment_ending.connect(_on_segment_ending)
	Session.session_paused.connect(func(): _event("session_paused"))
	Session.session_resumed.connect(func(): _event("session_resumed"))
	Session.calibration_progress.connect(_on_calibration_progress)
	Session.session_finished.connect(_on_session_finished)
	_mode_label.text = "keyboard simulator" if InputBus.is_simulated() else "bridge: OpenRideBridge"
	_refresh_buttons()
	print("OPENRIDE_GAMES main ready renderer=%s adapter=%s" % [
		RenderingServer.get_current_rendering_method(), RenderingServer.get_video_adapter_name()])


func _process(delta: float) -> void:
	var playing := _in_segment and not Session.paused
	if playing and _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
	_intro_card.visible = _in_segment and _intro_left > 0.0
	_intro_card.text = "Up next: bridge check\npedal to see your cadence\n%d" % ceili(_intro_left)
	# Sensor loss freezes scoring (contract); the ride keeps recording on the Kotlin side.
	if playing and _intro_left <= 0.0 and InputBus.sensors_ok:
		_score += InputBus.cadence / 60.0 * delta  # one point per pedal stroke
	_sensor_banner.visible = not InputBus.sensors_ok

	_metrics_label.text = "cadence %d rpm    power %d W    resistance %d    speed %.1f mph    heart rate %s" % [
		InputBus.cadence, InputBus.power, InputBus.resistance, InputBus.speed,
		"--" if InputBus.heart_rate < 0 else str(int(InputBus.heart_rate))]
	_tracker_label.text = "lean x %+.2f    lean depth %+.2f    %s    tracker %d    %s" % [
		InputBus.lean_x, InputBus.lean_depth, "standing" if InputBus.standing else "seated", InputBus.tracker_state,
		_calibration if InputBus.tracker_state == InputBus.TRACKER_CALIBRATING else ""]
	_cadence_bar.size.x = (W - 120.0) * clampf(InputBus.cadence / 120.0, 0.0, 1.0)
	_resistance_bar.size.x = (W - 120.0) * clampf(InputBus.resistance / 100.0, 0.0, 1.0)
	var time_left := "open-ended" if InputBus.segment_time_left < 0 else "%d s left" % ceili(InputBus.segment_time_left)
	_status_label.text = "%s    %s    score %d" % [_state_text(), time_left, _score]
	_fps_label.text = "%d fps" % Engine.get_frames_per_second()

	_report_timer += delta
	if _report_timer >= 5.0:
		_report_timer = 0.0
		print("OPENRIDE_GAMES frame fps=%d cadence=%d power=%d resistance=%d speed=%.1f hr=%d sensors_ok=%s time_left=%.0f tracker=%d" % [
			Engine.get_frames_per_second(), InputBus.cadence, InputBus.power, InputBus.resistance,
			InputBus.speed, InputBus.heart_rate, InputBus.sensors_ok, InputBus.segment_time_left,
			InputBus.tracker_state])


func _state_text() -> String:
	if not Session.active:
		return "finished" if not Session.summary.is_empty() else "waiting for the session"
	if Session.paused:
		return "paused"
	if not _in_segment:
		return "segment done — end the session when ready"
	return "intro card" if _intro_left > 0.0 else "playing"


func _on_session_started(plan: Dictionary) -> void:
	_score = 0.0
	_in_segment = false
	_log = []
	# Kotlin starts every session with the camera off.
	_camera_on = false
	_camera_button.text = "Camera: off"
	_last_calibration_key = ""
	_event("session_started %s" % plan.get("plan_id", "?"))
	_refresh_buttons()


func _on_segment_started(segment: Dictionary) -> void:
	_in_segment = true
	_intro_left = float(segment.get("intro_sec", 0))
	_event("segment_started %d/%d %s" % [int(segment.index) + 1, int(segment.count), segment.game_id])
	_refresh_buttons()


func _on_calibration_progress(step: String, fraction: float, step_index: int, step_count: int, attempt: int, retry_reason: String) -> void:
	_calibration = "calibrating %s (%d/%d) %d%%%s" % [
		step, step_index + 1, step_count, int(fraction * 100),
		"" if retry_reason.is_empty() else "  attempt %d: %s" % [attempt, retry_reason]]
	var key := "%s#%d" % [step, attempt]
	if key != _last_calibration_key:
		_event("calibration_progress %s %d/%d attempt %d %s" % [step, step_index + 1, step_count, attempt, retry_reason])
		_last_calibration_key = key


func _on_camera_pressed() -> void:
	_camera_on = not _camera_on
	Session.set_tracker_mode("lean_x" if _camera_on else "off")
	_camera_button.text = "Camera: lean_x" if _camera_on else "Camera: off"


func _on_segment_ending() -> void:
	_event("segment_ending")
	_finish_segment()


func _on_session_finished(summary: Dictionary) -> void:
	_in_segment = false
	var totals: Dictionary = summary.get("totals", {})
	_event("session_finished: %d results, %d stars" % [summary.get("results", []).size(), int(totals.get("stars", 0))])
	_refresh_buttons()


func _finish_segment() -> void:
	if not _in_segment:
		return
	_in_segment = false
	var skipped := _intro_left > 0.0
	Session.segment_finished({
		"game_id": GAME_ID,
		"score": int(_score),
		"stars": 0 if skipped else (3 if _score >= 150 else (2 if _score >= 60 else 1)),
		"won": null,
		"skipped": skipped,
		"stats": {"effort_avg": 1.0},
	})
	_event("segment_finished score %d%s" % [_score, " (skipped)" if skipped else ""])
	_refresh_buttons()


func _refresh_buttons() -> void:
	_pause_button.disabled = not Session.active
	_pause_button.text = "Resume" if Session.paused else "Pause"
	_finish_button.disabled = not _in_segment
	_end_button.disabled = not Session.active
	_exit_button.disabled = Session.active or Session.summary.is_empty()


func _event(text: String) -> void:
	_log.append("%6.1f  %s" % [Time.get_ticks_msec() / 1000.0, text])
	if _log.size() > LOG_LINES:
		_log = _log.slice(_log.size() - LOG_LINES)
	_log_label.text = "\n".join(_log)
	_refresh_buttons()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_add_rect(Vector2.ZERO, Vector2(W, H), Color(0.08, 0.09, 0.15))

	_add_label("OpenRide games: bridge check", Vector2(60, 40), 56, Color(1, 1, 1))
	_mode_label = _add_label("", Vector2(60, 115), 30, Color(0.6, 0.75, 1.0))
	_fps_label = _add_label("", Vector2(W - 260, 50), 36, Color(0.6, 1.0, 0.6))
	_metrics_label = _add_label("", Vector2(60, 190), 40, Color(1, 1, 1))

	_add_label("cadence", Vector2(60, 262), 26, Color(0.7, 0.7, 0.8))
	_add_rect(Vector2(60, 300), Vector2(W - 120, 36), Color(1, 1, 1, 0.08))
	_cadence_bar = _add_rect(Vector2(60, 300), Vector2(0, 36), Color(0.24, 0.86, 0.52))
	_add_label("resistance", Vector2(60, 352), 26, Color(0.7, 0.7, 0.8))
	_add_rect(Vector2(60, 390), Vector2(W - 120, 36), Color(1, 1, 1, 0.08))
	_resistance_bar = _add_rect(Vector2(60, 390), Vector2(0, 36), Color(1.0, 0.6, 0.2))

	_tracker_label = _add_label("", Vector2(60, 460), 32, Color(0.85, 0.85, 0.95))
	_status_label = _add_label("", Vector2(60, 520), 40, Color(1.0, 0.9, 0.3))
	_log_label = _add_label("", Vector2(60, 590), 26, Color(0.75, 0.8, 0.9))

	_sensor_banner = _add_label("Sensors not detected — scoring paused", Vector2(0, 0), 40, Color(1, 1, 1))
	_sensor_banner.size = Vector2(W, 64)
	_sensor_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var banner_bg := StyleBoxFlat.new()
	banner_bg.bg_color = Color(0.75, 0.15, 0.15)
	_sensor_banner.add_theme_stylebox_override("normal", banner_bg)

	_pause_button = _add_button("Pause", 0, _on_pause_pressed)
	_finish_button = _add_button("Finish segment", 1, _finish_segment)
	_end_button = _add_button("End session", 2, Session.request_end)
	_exit_button = _add_button("Exit", 3, Session.request_exit)

	# Head-tracker check (#33): turns the camera on in lean_x, which calibrates on first use.
	_camera_button = Button.new()
	_camera_button.text = "Camera: off"
	_camera_button.position = Vector2(W - 480, 110)
	_camera_button.size = Vector2(420, 90)
	_camera_button.focus_mode = Control.FOCUS_NONE
	_camera_button.add_theme_font_size_override("font_size", 36)
	_camera_button.pressed.connect(_on_camera_pressed)
	add_child(_camera_button)

	_intro_card = _add_label("", Vector2(W / 2 - 600, H / 2 - 220), 64, Color(1, 1, 1))
	_intro_card.size = Vector2(1200, 360)
	_intro_card.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_card.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var card_bg := StyleBoxFlat.new()
	card_bg.bg_color = Color(0.15, 0.2, 0.35, 0.95)
	card_bg.set_corner_radius_all(24)
	_intro_card.add_theme_stylebox_override("normal", card_bg)


func _on_pause_pressed() -> void:
	if Session.paused:
		Session.request_resume()
	else:
		Session.request_pause()


func _add_rect(pos: Vector2, rect_size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = pos
	rect.size = rect_size
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	return rect


func _add_label(text: String, pos: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = pos
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## Bottom row, slot 0-3 (each 420 x 110 at y 930; touch targets for adb checks too).
func _add_button(text: String, slot: int, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.position = Vector2(60 + slot * 460, 930)
	button.size = Vector2(420, 110)
	button.focus_mode = Control.FOCUS_NONE  # Space is the simulator's "stand", not "press"
	button.add_theme_font_size_override("font_size", 40)
	button.pressed.connect(action)
	add_child(button)
	return button
