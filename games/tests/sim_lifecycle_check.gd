extends SceneTree
## Headless smoke check of the desktop simulator's session lifecycle (Session + LocalSession):
##   $GODOT_BIN --headless --path games -s res://tests/sim_lifecycle_check.gd
## Prints PASS/FAIL and exits non-zero on failure. The framework's own tests are GdUnit4 suites
## in tests/unit (docs/GAMES.md, "Tests").

var _events: Array[String] = []
var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var session: Node = root.get_node("Session")
	session.session_started.connect(func(_p): _events.append("session_started"))
	session.segment_started.connect(func(_s): _events.append("segment_started"))
	session.segment_ending.connect(func(): _events.append("segment_ending"))
	session.session_paused.connect(func(): _events.append("session_paused"))
	session.session_resumed.connect(func(): _events.append("session_resumed"))
	session.session_finished.connect(func(_s): _events.append("session_finished"))
	await process_frame
	await process_frame
	_expect([], "nothing starts under a -s script")

	# Open-ended default plan (a scene run in the editor starts it by itself).
	session._local.start()
	_expect(["session_started", "segment_started"], "default plan starts")
	# The demo's camera mode starts the session's calibration by itself, once (as TrackerLink).
	_expect_true(session._local.is_calibrating() and session._local.calibrations_started == 1,
		"the first camera mode calibrates once (%d)" % session._local.calibrations_started)
	_expect_true(session.plan.segments[0].game_id == "demo", "default game is the demo")
	session.request_pause()
	session.request_resume()
	session.segment_finished({"game_id": "demo", "score": 12, "stars": 1, "won": null, "skipped": false, "stats": {}})
	_expect_true(session.active, "open-ended session waits for request_end")
	session.request_end()
	_expect(["session_started", "segment_started", "session_paused", "session_resumed", "session_finished"], "open-ended lifecycle")
	_expect_true(int(session.summary.totals.stars) == 1, "summary totals the stars")

	# request_exit on a desktop restarts the local plan.
	_events.clear()
	session.request_exit()
	_expect(["session_started", "segment_started"], "request_exit restarts the local plan")
	_expect_true(session._local.calibrations_started == 2, "a new session calibrates again")

	# A timed plan: segment_ending after intro + duration, then a zero result after the grace.
	# The director answers segment_ending for its game, so unhook it to see the grace.
	_events.clear()
	session.segment_ending.disconnect(session.director._on_segment_ending)
	session._local.start({"kind": "circuit", "plan_id": "check", "difficulty": "easy", "total_sec": 1,
		"segments": [{"game_id": "demo", "role": "work", "duration_sec": 1}]})
	session._local._process(session._local.INTRO_SEC + 0.1)  # intro card
	session._local._process(1.1)  # gameplay
	_expect(["session_started", "segment_started", "segment_ending"], "timer ends the segment")
	session._local._process(session._local.GRACE_SEC + 0.1)
	_expect(["session_started", "segment_started", "segment_ending", "session_finished"], "no result: zero, then finished")
	_expect_true(int(session.summary.totals.stars) == 0, "zero result recorded")
	session.segment_ending.connect(session.director._on_segment_ending)

	if _failures.is_empty():
		print("PASS sim lifecycle")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL ", f)
		quit(1)


func _expect(expected: Array, what: String) -> void:
	if _events != expected:
		_failures.append("%s: expected %s, got %s" % [what, expected, _events])


func _expect_true(condition: bool, what: String) -> void:
	if not condition:
		_failures.append(what)
