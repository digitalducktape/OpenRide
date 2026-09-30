extends SceneTree
## Headless check of AudioDirector's tempo change on a phrase boundary (#36), with the real
## MusicGen (registered by res://audio/Cues.gd at startup) and real playback:
##   $GODOT_BIN --headless --path games -s res://tests/sim_phrase_swap_check.gd
## A 4-bar loop at 180 bpm plays; a request for 170 bpm renders while it plays, waits for the
## loop's next phrase boundary, then swaps in within a few ms of it. Prints PASS/FAIL.

const STYLE := {"name": "demo_drive", "bars": 4, "stem_gates": {"harmony": 0.5, "lead": 0.85}}
const MAX_LATE_SEC := 0.02  ## the swap must land within this of the boundary (about a frame)

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var director: Node = root.get_node("AudioDirector")
	MusicGen.cache_enabled = false
	director.begin_session()
	director.begin_segment({"audio": {"music": true, "music_volume": 0.8, "sfx_volume": 1.0}})
	var swaps := []
	director.tempo_swapped.connect(func(key, since): swaps.append([key, since, Time.get_ticks_msec()]))

	director.play_music(STYLE, 180.0, 5)
	await _until(func(): return director.is_music_playing(), 10.0)
	_expect(director.is_music_playing(), "the first tempo plays")
	var first: AudioStreamPlayer = director._decks[director._deck]
	var phrase: float = director._deck_phrase_sec[director._deck]
	_expect(absf(phrase - MusicGen.bar_samples(180.0) * 4 / 22050.0) < 0.001, "phrase length from the stream")
	await _until(func(): return first.get_playback_position() > 1.0, 5.0)

	# Two tempo changes in a row: the newer one replaces the pending one.
	director.play_music(STYLE, 160.0, 5)
	director.play_music(STYLE, 170.0, 5)
	var target: String = director.music_key({"style": STYLE, "tempo_bpm": 170.0, "seed": 5})
	await _until(func(): return director.pending_music_key() == target, 10.0)
	_expect(director.pending_music_key() == target, "the newest tempo is pending")
	var left := phrase - fposmod(first.get_playback_position(), phrase)
	var asked := Time.get_ticks_msec()
	await _until(func(): return not swaps.is_empty(), phrase + 2.0)
	_expect(swaps.size() == 1, "one swap")
	if swaps.size() == 1:
		var since: float = swaps[0][1]
		var waited: float = (int(swaps[0][2]) - asked) / 1000.0
		print("swapped %.1f ms after the boundary, %.2f s after the render was ready (%.2f s were left in the phrase)"
			% [since * 1000.0, waited, left])
		_expect(swaps[0][0] == target, "the swap plays the newest tempo")
		_expect(since >= 0.0 and since < MAX_LATE_SEC, "the swap lands within %d ms of the boundary" % int(MAX_LATE_SEC * 1000))
		_expect(absf(waited - left) < 0.25, "the swap waited for the boundary")
		_expect(director.current_music_key() == target, "the new tempo is current")
		_expect(director._fade_sec == director.SWAP_FADE_SEC, "a short crossfade")
		var second: AudioStreamPlayer = director._decks[director._deck]
		_expect(second != first and second.playing, "the new tempo plays on the other deck")
	director.end_session()
	for i in 5:
		await process_frame

	if _failures.is_empty():
		print("PASS sim phrase swap")
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL ", f)
		quit(1)


func _until(condition: Callable, timeout: float) -> void:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < timeout * 1000.0:
		await process_frame


func _expect(ok: bool, what: String) -> void:
	if not ok:
		_failures.append(what)
