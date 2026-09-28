extends SceneTree
## Headless smoke check of the desktop simulator's session lifecycle (Session + LocalSession):
##   $GODOT_BIN --headless --path games -s res://tests/sim_lifecycle_check.gd
## Prints PASS/FAIL and exits non-zero on failure. GdUnit4 suites arrive with #34.

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

	# Open-ended default plan: started automatically.
	_expect(["session_started", "segment_started"], "default plan starts")
	_expect_true(session.plan.segments[0].game_id == "placeholder", "default game is the placeholder")
	session.request_pause()
	session.request_resume()
	session.segment_finished({"game_id": "placeholder", "score": 12, "stars": 1, "won": null, "skipped": false, "stats": {}})
	_expect_true(session.active, "open-ended session waits for request_end")
	session.request_end()
	_expect(["session_started", "segment_started", "session_paused", "session_resumed", "session_finished"], "open-ended lifecycle")
	_expect_true(int(session.summary.totals.stars) == 1, "summary totals the stars")

	# request_exit on a desktop restarts the local plan.
	_events.clear()
	session.request_exit()
	_expect(["session_started", "segment_started"], "request_exit restarts the local plan")

	# A timed plan: segment_ending after intro + duration, then a zero result after the grace.
	_events.clear()
	session._local.start({"kind": "circuit", "plan_id": "check", "difficulty": "easy", "total_sec": 1,
		"segments": [{"game_id": "placeholder", "role": "work", "duration_sec": 1}]})
	session._local._process(session._local.INTRO_SEC + 0.1)  # intro card
	session._local._process(1.1)  # gameplay
	_expect(["session_started", "segment_started", "segment_ending"], "timer ends the segment")
	session._local._process(session._local.GRACE_SEC + 0.1)
	_expect(["session_started", "segment_started", "segment_ending", "session_finished"], "no result: zero, then finished")
	_expect_true(int(session.summary.totals.stars) == 0, "zero result recorded")

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
