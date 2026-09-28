extends Node
## Desktop stand-in for the Kotlin session (docs/GAMES.md, "Desktop simulation"). Plays a local
## plan through Session with the same timeline as the app (StubGameSession.kt):
##   session_started → per segment: segment_started → intro card (intro_sec) → gameplay →
##   segment_ending when the timer runs out (1.5 × duration for end_mode "game") → the game's
##   segment_finished, or a zero result after 5 s. A timed plan then finishes by itself; an
##   open-ended one waits for request_end.
## Payloads go through a JSON round trip so games see exactly the types the bridge delivers
## (every number a float).

const INTRO_SEC := 10
const GRACE_SEC := 5.0
const DEFAULT_GAME_ID := "placeholder"

var _session: Node
var _plan: Dictionary = {}
var _segment: Dictionary = {}
var _phase := ""  # "", "intro", "playing", "ending", "awaiting_end", "finished"
var _intro_left := 0.0
var _played := 0.0
var _grace_left := 0.0
var _elapsed := 0.0
var _paused := false
var _end_requested := false
var _results: Array = []


func _init(session: Node) -> void:
	_session = session
	process_mode = Node.PROCESS_MODE_ALWAYS


## A Just Ride of the open game: a scene run on its own (F6) may declare `game_id`.
func default_plan() -> Dictionary:
	var game_id := DEFAULT_GAME_ID
	var scene := get_tree().current_scene
	if scene and scene.get("game_id") is String:
		game_id = scene.get("game_id")
	return {
		"kind": "just_ride",
		"plan_id": "just-ride:%s" % game_id,
		"difficulty": "standard",
		"total_sec": -1,
		"segments": [{"game_id": game_id, "role": "free", "duration_sec": -1}],
	}


func start(plan: Dictionary = {}) -> void:
	_plan = plan if not plan.is_empty() else default_plan()
	_segment = {}
	_phase = ""
	_elapsed = 0.0
	_paused = false
	_end_requested = false
	_results = []
	_session._on_session_started(_wire(_plan))
	_start_segment(0)


func time_left() -> float:
	if _phase in ["", "awaiting_end", "finished"]:
		return -1.0
	var duration: float = _segment.get("duration_sec", -1)
	return -1.0 if duration < 0 else maxf(0.0, duration - _played)


func segment_finished(result: Dictionary) -> void:
	if _phase not in ["intro", "playing", "ending"]:
		return
	_results.append(result if result.has("game_id") else _zero_result())
	_advance()


func request_pause() -> void:
	if _paused or _phase in ["", "finished"]:
		return
	_paused = true
	_session._on_session_paused()


func request_resume() -> void:
	if not _paused:
		return
	_paused = false
	_session._on_session_resumed()


func request_end() -> void:
	_end_requested = true
	match _phase:
		"intro", "playing":
			_begin_ending()
		"", "awaiting_end":
			_finish()


func _process(delta: float) -> void:
	if _paused or _phase in ["", "awaiting_end", "finished"]:
		return
	_elapsed += delta
	match _phase:
		"intro":
			_intro_left -= delta
			if _intro_left <= 0.0:
				_phase = "playing"
		"playing":
			_played += delta
			var duration: float = _segment.duration_sec
			var stop_at := -1.0
			if duration >= 0:
				stop_at = duration if _segment.end_mode == "timer" else duration * 1.5
			if stop_at >= 0 and _played >= stop_at:
				_begin_ending()
		"ending":
			_grace_left -= delta
			if _grace_left <= 0.0:
				_results.append(_zero_result())
				_advance()


func _start_segment(index: int) -> void:
	var planned: Dictionary = _plan.segments[index]
	_segment = {
		"index": index,
		"count": _plan.segments.size(),
		"game_id": planned.game_id,
		"duration_sec": planned.duration_sec,
		"intro_sec": INTRO_SEC,
		"end_mode": "game" if planned.duration_sec < 0 else "timer",
		"role": planned.role,
		"difficulty": _plan.difficulty,
		"effort": planned.role == "work",
		"seed": randi(),
		"audio": {"music": true, "music_volume": 0.8, "sfx_volume": 1.0},
		"params": {},
	}
	_phase = "intro"
	_intro_left = INTRO_SEC
	_played = 0.0
	_session._on_segment_started(_wire(_segment))


func _begin_ending() -> void:
	_phase = "ending"
	_grace_left = GRACE_SEC
	_session._on_segment_ending()


func _advance() -> void:
	var next: int = _segment.index + 1
	if _end_requested:
		_finish()
	elif next < _plan.segments.size():
		_start_segment(next)
	elif _segment.duration_sec < 0:
		_phase = "awaiting_end"
	else:
		_finish()


func _finish() -> void:
	_phase = "finished"
	var score := 0.0
	var stars := 0
	for r in _results:
		score += float(r.get("score", 0))
		stars += int(r.get("stars", 0))
	_session._on_session_finished(_wire({
		"ride_id": null,
		"results": _results,
		"totals": {"score": score, "stars": stars, "segments": _results.size(), "elapsed_sec": int(_elapsed)},
		"bests": {},
	}))


func _zero_result() -> Dictionary:
	return {"game_id": _segment.get("game_id", ""), "score": 0, "stars": 0, "won": null, "skipped": false, "stats": {}}


func _wire(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))
