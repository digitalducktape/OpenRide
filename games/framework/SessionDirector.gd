class_name SessionDirector
extends Node
## Runs the session on screen: the part of the `Session` autoload that games see (docs/GAMES.md,
## "The framework"). Session creates it as its child; it listens to Session's signals.
##
## Per segment (segment_started):
##   load `res://games/<game_id>/…tscn` from GameRegistry, set the tracker mode from the game's
##   declaration (Kotlin calibrates on a session's first camera mode by itself; see
##   `_calibrate_for`), start Effort and AudioDirector, then show the intro card for
##   `intro_sec`. Its "Skip this game" button skips the game when another segment follows
##   (segment_finished with `skipped: true`); any other touch on the card does nothing. Then gameplay: HUD on, scoring live.
## Ending: `end_mode: game` games end themselves; on segment_ending the game gets 4.5 s to
## wrap up (Kotlin allows 5) before the director reports for it. Results carry the stars from
## the game's thresholds.
## Pause, end (with confirmation), recalibrate, the summary on session_finished and its "Done"
## → request_exit are handled here too.

enum Phase { IDLE, INTRO, PLAYING, ENDING, BETWEEN, SUMMARY }

const GRACE_SEC := 4.5  ## Kotlin's grace is 5 s; report before it gives up
const IDLE_SCENE := "res://Main.tscn"
const COUNTDOWN_CUES := 3  ## countdown cue on each of the intro card's last 3 seconds
const FRAME_LOG_SEC := 5.0
const RECALIBRATE_DEBOUNCE_MSEC := 1000

var phase := Phase.IDLE
var game: Game  ## the game on screen, if any
var info: GameInfo  ## its declarations
var segment: Dictionary = {}
var results: Array = []  ## results reported this session, in order

var hud: Hud
var intro_card: IntroCard
var pause_overlay: PauseOverlay
var calibration: CalibrationOverlay
var summary_screen: SummaryScreen
var done_panel: CanvasLayer  ## an open-ended plan's "segment done: end the session"

var _intro_left := 0.0
var _grace_left := 0.0
var _last_count := 0
## The calibration this session has covered: "" (none yet), "lean_x" or "lean_2d".
var calibrated_mode := ""

var _log_left := FRAME_LOG_SEC
var _pause_screen_up := false
## The current pause began (or ran) under a calibration: its resume plays no cue.
var _calibration_pause := false
var _last_recalibrate_msec := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	hud = Hud.new()
	hud.visible = false
	hud.pause_pressed.connect(_on_pause_pressed)
	hud.end_pressed.connect(func(): pause_overlay.show_confirm())
	hud.recalibrate_pressed.connect(_recalibrate)
	add_child(hud)
	intro_card = IntroCard.new()
	intro_card.skip_requested.connect(skip)
	add_child(intro_card)
	calibration = CalibrationOverlay.new()
	calibration.strip_host = hud.status_slot
	calibration.recalibrate_requested.connect(_recalibrate)
	add_child(calibration)
	pause_overlay = PauseOverlay.new()
	pause_overlay.resume_pressed.connect(Session.request_resume)
	pause_overlay.end_confirmed.connect(Session.request_end)
	pause_overlay.option_changed.connect(func(key: String, value: String):
		if game:
			game.change_option(key, value))
	add_child(pause_overlay)
	summary_screen = SummaryScreen.new()
	summary_screen.done_pressed.connect(Session.request_exit)
	add_child(summary_screen)
	done_panel = _build_done_panel()
	add_child(done_panel)

	Session.session_started.connect(_on_session_started)
	Session.segment_started.connect(_on_segment_started)
	Session.segment_ending.connect(_on_segment_ending)
	Session.session_paused.connect(_on_session_paused)
	Session.session_resumed.connect(_on_session_resumed)
	Session.session_finished.connect(_on_session_finished)


## "IDLE", "INTRO", "PLAYING", "ENDING", "BETWEEN" or "SUMMARY", for logs and checks.
func phase_name() -> String:
	return Phase.keys()[phase]


## Gameplay seconds of the current segment (the HUD's count-up clock).
func played_sec() -> float:
	return game.played_sec if game else 0.0


## Whether the intro card may be skipped: only when a later segment follows. Skipping the last
## one would end the session (a timed plan finishes after its last result), and only End with
## its confirmation may do that. A one-segment Just Ride therefore never offers a skip.
func can_skip() -> bool:
	if segment.is_empty():
		return false
	return int(segment.get("index", 0)) < int(segment.get("count", 1)) - 1


## The rider pressed the intro card's "Skip this game".
func skip() -> void:
	if phase != Phase.INTRO or not can_skip():
		return
	_report(skipped_result(str(segment.get("game_id", ""))))


static func skipped_result(game_id: String) -> Dictionary:
	return {"game_id": game_id, "score": 0, "stars": 0, "won": null, "skipped": true, "stats": {}}


# --- Session signals ---

func _on_session_started(_plan: Dictionary) -> void:
	results = []
	segment = {}
	calibrated_mode = ""
	_close_game()
	_hide_overlays()
	summary_screen.visible = false
	Effort.begin_segment(false)
	AudioDirector.begin_session()
	phase = Phase.BETWEEN


func _on_segment_started(new_segment: Dictionary) -> void:
	segment = new_segment
	done_panel.visible = false
	var game_id := str(segment.get("game_id", ""))
	info = GameRegistry.info(game_id)
	var next := _take_game(game_id) if info else null
	if next == null:
		push_error("SessionDirector: unknown game '%s'; skipping it" % game_id)
		_close_game()
		phase = Phase.INTRO
		_report(skipped_result(game_id))
		return
	_show_game(next)
	Session.set_tracker_mode(info.tracker_mode)
	calibration.camera_game = info.uses_camera()
	_calibrate_for(info)
	Effort.begin_segment(bool(segment.get("effort", false)))
	AudioDirector.begin_segment(segment)
	hud.setup(info, segment)
	hud.visible = false
	game.hud = hud
	pause_overlay.set_options(info.options, game.option)
	game.prepare(segment)
	game.set_paused(Session.paused)

	var previous: Dictionary = results.back() if not results.is_empty() else {}
	var previous_info := GameRegistry.info(str(previous.get("game_id", ""))) if not previous.is_empty() else null
	intro_card.show_segment(info, segment, game.target_text(segment), previous,
		previous_info.title if previous_info else str(previous.get("game_id", "")), can_skip(),
		game.how_to_text(segment), game.intro_visual())
	phase = Phase.INTRO
	_intro_left = float(segment.get("intro_sec", 0))
	_last_count = ceili(_intro_left) + 1
	if _intro_left <= 0.0:
		_start_gameplay()


func _on_segment_ending() -> void:
	match phase:
		Phase.INTRO:
			# Ended before gameplay began (the rider ended the session on the card).
			_report(skipped_result(str(segment.get("game_id", ""))))
		Phase.PLAYING:
			phase = Phase.ENDING
			_grace_left = GRACE_SEC
			Effort.set_live(false)
			game.request_finish()  # may end at once, reporting before this returns


## Kotlin also pauses the session while the head tracker calibrates (docs/GAMES.md, "A session
## on screen"). The calibration screen then stands in for the pause screen, and no pause or
## resume cue plays: the pause screen appears only once calibration is over, if the session is
## still paused.
func _on_session_paused() -> void:
	if game:
		game.set_paused(true)
	AudioDirector.set_paused(true)
	if not is_calibrating():
		AudioDirector.play_cue(AudioDirector.CUE_PAUSE)
	hud.set_paused(true)
	_sync_pause_screen()


func _on_session_resumed() -> void:
	if game:
		game.set_paused(false)
	AudioDirector.set_paused(false)
	if not _calibration_pause:
		AudioDirector.play_cue(AudioDirector.CUE_RESUME)
	_calibration_pause = false
	hud.set_paused(false)
	_sync_pause_screen()


## Whether the head tracker is calibrating (the calibration screen is up).
func is_calibrating() -> bool:
	return Session.is_calibrating()


## The pause screen shows while the session is paused, except under the calibration screen.
func _sync_pause_screen() -> void:
	var calibrating := Session.paused and is_calibrating()
	if calibrating:
		_calibration_pause = true
	var want := Session.paused and not calibrating
	if want != _pause_screen_up:
		_pause_screen_up = want
		pause_overlay.set_paused(want)


func _on_session_finished(summary: Dictionary) -> void:
	phase = Phase.SUMMARY
	Effort.set_live(false)
	_close_game()
	_hide_overlays()
	Session.set_tracker_mode("off")
	AudioDirector.end_session()
	AudioDirector.play_cue(AudioDirector.CUE_SUMMARY)
	summary_screen.show_summary(summary, Session.plan)


# --- Game ---

func _on_game_ended() -> void:
	if phase in [Phase.PLAYING, Phase.ENDING]:
		_report(game.finish())


func _start_gameplay() -> void:
	phase = Phase.PLAYING
	intro_card.visible = false
	hud.visible = true
	Effort.set_live(true)
	AudioDirector.play_cue(AudioDirector.CUE_GO)
	game.start(segment)


func _report(result: Dictionary) -> void:
	phase = Phase.BETWEEN
	Effort.set_live(false)
	intro_card.visible = false
	results.append(result)
	Session.segment_finished(result)
	AudioDirector.play_cue(AudioDirector.CUE_SEGMENT_END)
	var open_ended := float(segment.get("duration_sec", -1)) < 0
	var last := int(segment.get("index", 0)) >= int(segment.get("count", 1)) - 1
	if open_ended and last and Session.active:
		# Kotlin now waits for request_end: offer it.
		hud.visible = false
		done_panel.visible = true


func _process(delta: float) -> void:
	if Session.active:
		_sync_pause_screen()
	match phase:
		Phase.INTRO:
			if not Session.paused:
				_intro_left -= delta
				intro_card.set_time_left(_intro_left)
				var count := ceili(_intro_left)
				if count < _last_count:
					_last_count = count
					if count >= 1 and count <= COUNTDOWN_CUES:
						AudioDirector.play_cue(AudioDirector.CUE_COUNTDOWN)
				if _intro_left <= 0.0:
					_start_gameplay()
		Phase.ENDING:
			if not Session.paused:
				_grace_left -= delta
				if _grace_left <= 0.0:
					push_warning("SessionDirector: %s didn't end within %.1f s; ending it" % [game.game_id, GRACE_SEC])
					_report(game.finish())
	_log_left -= delta
	if _log_left <= 0.0:
		# Every second while the camera runs (for tuning steering on the bike), else every 5 s.
		_log_left = 1.0 if Session.tracker_mode != "off" else FRAME_LOG_SEC
		print("OPENRIDE_GAMES frame fps=%d phase=%s game=%s cadence=%d power=%d resistance=%d sensors_ok=%s time_left=%.0f tracker=%d lean_x=%+.2f lean_depth=%+.2f standing=%s score=%d effort=%.2f" % [
			Engine.get_frames_per_second(), Phase.keys()[phase], game.game_id if game else "-",
			InputBus.cadence, InputBus.power, InputBus.resistance, InputBus.sensors_ok,
			InputBus.segment_time_left, InputBus.tracker_state, InputBus.lean_x, InputBus.lean_depth,
			InputBus.standing, Effort.score, Effort.multiplier])


# --- Buttons ---

func _on_pause_pressed() -> void:
	if Session.paused:
		Session.request_resume()
	else:
		Session.request_pause()


## The rider asked to recalibrate (Recalibrate, or a tap on the calibration overlay): every
## step runs again. Ignored while a calibration runs, and within RECALIBRATE_DEBOUNCE_MSEC of
## the last request (a double tap on the bike sent two, the second restarting the first).
func _recalibrate() -> void:
	if not (info and info.uses_camera() and Session.active):
		return
	if InputBus.tracker_state == InputBus.TRACKER_CALIBRATING:
		return
	var now := Time.get_ticks_msec()
	if _last_recalibrate_msec >= 0 and now - _last_recalibrate_msec < RECALIBRATE_DEBOUNCE_MSEC:
		return
	_last_recalibrate_msec = now
	Session.request_calibration(info.calibration_mode())
	calibrated_mode = _wider(calibrated_mode, info.calibration_mode())


## Called after set_tracker_mode for each segment. Kotlin (TrackerLink) starts the session's
## first calibration by itself on the first camera mode, re-taking only the centre when the
## rider's extremes from earlier today cover the mode, so Godot never asks for that one: asking
## would force a second, full run. Godot asks only when a lean_2d game follows a session whose
## calibration covered lean_x alone, since depth needs its own extremes (docs/GAMES.md, "Head
## tracker").
func _calibrate_for(game_info: GameInfo) -> void:
	if not game_info.uses_camera():
		return
	var needed := game_info.calibration_mode()
	if calibrated_mode.is_empty():
		calibrated_mode = needed  # Kotlin's automatic calibration covers this game's mode
	elif needed == "lean_2d" and calibrated_mode != "lean_2d":
		Session.request_calibration(needed)
		calibrated_mode = needed


static func _wider(a: String, b: String) -> String:
	return "lean_2d" if "lean_2d" in [a, b] else b


# --- Scenes ---

## The game scene for game_id: the running scene when it's an unused instance of that game
## (a game scene run on its own with F6), otherwise a fresh one.
func _take_game(game_id: String) -> Game:
	var current := get_tree().current_scene
	if current is Game and not current.was_prepared() and current.game_id == game_id:
		return current
	return GameRegistry.instantiate(game_id)


func _show_game(next: Game) -> void:
	if game and game != next:
		game.ended.disconnect(_on_game_ended)
	_swap_scene(next)
	game = next
	if not game.ended.is_connected(_on_game_ended):
		game.ended.connect(_on_game_ended)


func _close_game() -> void:
	if game:
		game.ended.disconnect(_on_game_ended)
		game = null
	info = null
	hud.visible = false
	hud.clear_widgets()
	calibration.camera_game = false
	var current := get_tree().current_scene
	if current is Game or current == null:
		_swap_scene(load(IDLE_SCENE).instantiate())


## Makes `next` the current scene, freeing the old one when it's ours (a game or the idle
## scene). Anything else (a test runner) is left alone.
func _swap_scene(next: Node) -> void:
	var tree := get_tree()
	var old := tree.current_scene
	if old == next:
		return
	if next.get_parent() == null:
		tree.root.add_child(next)
	tree.current_scene = next
	if old and (old is Game or old.scene_file_path == IDLE_SCENE):
		old.queue_free()


func _hide_overlays() -> void:
	hud.visible = false
	intro_card.visible = false
	pause_overlay.set_paused(false)
	done_panel.visible = false


func _build_done_panel() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.layer = IntroCard.LAYER
	layer.visible = false
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", HudTheme.panel_style(HudTheme.CARD, 32))
	card.custom_minimum_size = Vector2(1000, 0)
	card.position = Vector2(HudTheme.W / 2 - 500, 300)
	layer.add_child(card)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 28)
	card.add_child(box)
	var title := HudTheme.label("Game over", HudTheme.BIG)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var line := HudTheme.label("Keep pedalling as long as you like.", HudTheme.BODY, HudTheme.MUTED)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(line)
	box.add_child(HudTheme.button("End session", end_from_done_panel, Color(0.45, 0.16, 0.2)))
	return layer


## The open-ride "Game over" panel's End: confirmed first, like every other End.
func end_from_done_panel() -> void:
	pause_overlay.show_confirm()
