extends SceneTree
## Headless playthrough of The Pull (#79) with the keyboard simulator:
##   $GODOT_BIN --headless --path games -s res://tests/sim_pull_check.gd
## A 5-minute local timed Just Ride at 8× speed (`timed_end_mode: game`), ridden at the
## simulator's default 80 rpm and 35% (~150 W: the default FTP, so each pull lasts ~4 minutes).
## The game must start pulls until the time is up, let the last one run past the end (here it
## meets the overtime guard), and end the segment itself before the 1.5× hard stop; the summary
## must appear and the result carry the game's stats.

const SPEED := 8.0
const DURATION := 300
const TIMEOUT_SEC := 120.0  ## real seconds

var _failures: Array[String] = []
var _session: Node
var _director: Node  # untyped: a -s script compiles before the autoloads exist
var _ended_at := -1.0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_session = root.get_node("Session")
	_director = _session.director
	Engine.time_scale = SPEED
	_session._local.start({"kind": "just_ride", "plan_id": "just-ride:the_pull:minutes:5", "difficulty": "standard",
		"total_sec": DURATION + 10, "segments": [{"game_id": "the_pull", "role": "free", "duration_sec": DURATION}]})
	await _frames(3)
	_check(_director.intro_card.visible, "the intro card shows")
	_check(_session.tracker_mode == "off", "no camera (%s)" % _session.tracker_mode)
	_check(str(_session.segment.end_mode) == "game", "a timed pull ends on its own terms (%s)" % _session.segment.end_mode)
	var game: Node = _director.game
	_check(game != null and game.game_id == "the_pull", "The Pull is loaded")
	game.ended.connect(func(): _ended_at = game.played_sec)
	await _until(func(): return _director.phase_name() == "PLAYING", 30.0)
	_check(_director.phase_name() == "PLAYING", "gameplay starts")
	var results: Array = _session._local._results
	var session_phase := ""
	var start := Time.get_ticks_msec()
	while results.is_empty() and Time.get_ticks_msec() - start < TIMEOUT_SEC * 1000.0:
		session_phase = _session._local._phase
		await process_frame
	_check(results.size() == 1, "the ride reported a result (%s)" % [results])
	_check(_ended_at > 0.0, "the game ended the segment itself")
	_check(session_phase == "playing", "before the hard stop (%s)" % session_phase)
	_check(_ended_at >= DURATION, "it kept pulling until the time was up (%.0f s)" % _ended_at)
	_check(_ended_at < DURATION * 1.5, "inside 1.5 × the length (%.0f s)" % _ended_at)
	if results.size() == 1:
		var r: Dictionary = results[0]
		_check(r.game_id == "the_pull" and not r.skipped, "the result is The Pull's")
		_check(float(r.score) > 0.0, "it scored (%s)" % r.score)
		for key in ["distance_m", "best_distance_m", "peak_power", "pull_sec", "pulls", "full_pulls", "effort_avg"]:
			_check(r.stats.has(key), "stats.%s is there" % key)
		_check(int(r.stats.get("pulls", 0)) >= 2, "more than one pull in five minutes (%s)" % r.stats.get("pulls"))
		print("SIM pull: ended after %.0f s of play, score %d, stars %d, stats %s" % [_ended_at, r.score, r.stars,
			JSON.stringify(r.stats)])
	await _frames(3)
	_check(not _session.active, "the session finished")
	_check(_director.summary_screen.visible, "the summary shows")
	Engine.time_scale = 1.0
	if _failures.is_empty():
		print("PASS sim pull")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL ", f)
		quit(1)


func _until(condition: Callable, timeout_sec: float) -> void:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < timeout_sec * 1000.0:
		await process_frame


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _check(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
