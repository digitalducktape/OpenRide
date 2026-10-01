extends GdUnitTestSuite
## AudioDirector's tempo changes on a phrase boundary (#36; docs/GAMES.md, "Tempo changes on
## a phrase boundary"): a tempo change waits, pending, for the playing loop's next boundary,
## then swaps in with a short crossfade, starting on the boundary and keeping the stem levels.
## The director's own _process is off here; the tests drive renders and the phrase clock.

const STYLE := {"name": "drive", "bars": 4, "stem_gates": {"harmony": 0.5, "lead": 0.85}}
const RATE := 8000


## Stems as long as `bars` bars at the request's tempo (so a phrase is one 4-bar loop here).
static func _stems(request: Dictionary) -> Dictionary:
	var bars := int(request.style.get("bars", 16))
	var seconds: float = bars * 4 * 60.0 / float(request.tempo_bpm)
	var stems := {}
	for stem in ["drums", "bass", "harmony", "lead"]:
		var wav := AudioStreamWAV.new()
		wav.format = AudioStreamWAV.FORMAT_16_BITS
		wav.mix_rate = RATE
		var data := PackedByteArray()
		data.resize(int(RATE * seconds) * 2)
		wav.data = data
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = int(RATE * seconds)
		stems[stem] = wav
	return stems


func before_test() -> void:
	AudioDirector.set_process(false)
	AudioDirector.begin_session()
	AudioDirector.begin_segment({"audio": {"music": true, "music_volume": 0.8, "sfx_volume": 1.0}})
	AudioDirector._music_cache.clear()
	AudioDirector._cache_order.clear()
	AudioDirector.stop_music(0.0)
	AudioDirector._process(0.0)
	AudioDirector.register_music_generator(_stems)


func after_test() -> void:
	AudioDirector.end_session()
	AudioDirector._music_generator = Callable()
	AudioDirector._music_cache.clear()
	AudioDirector._cache_order.clear()
	AudioDirector.set_process(true)


## Plays `tempo` and waits until it is the current music.
func _play(tempo: float, style := STYLE, music_seed := 3) -> void:
	AudioDirector.play_music(style, tempo, music_seed)
	await _rendered()


## Waits for the render in flight to be collected.
func _rendered() -> void:
	for i in 300:
		await get_tree().process_frame
		AudioDirector._collect_render()
		if AudioDirector._render_task == -1:
			return


func _key(tempo: float, style := STYLE, music_seed := 3) -> String:
	return AudioDirector.music_key({"style": style, "tempo_bpm": tempo, "seed": music_seed})


func test_the_phrase_length_comes_from_the_stream() -> void:
	await _play(120.0)
	# 4 bars at 120 bpm = 8 s = one phrase.
	assert_float(AudioDirector._deck_phrase_sec[AudioDirector._deck]).is_equal_approx(8.0, 0.001)
	var sixteen := _stems({"style": {"bars": 16}, "tempo_bpm": 120.0})
	assert_float(AudioDirector.phrase_seconds(sixteen, {"style": {"bars": 16}})).is_equal_approx(8.0, 0.001)
	assert_float(AudioDirector.phrase_seconds(sixteen, {"style": {}})).is_equal_approx(8.0, 0.001)


func test_a_tempo_change_waits_for_the_phrase_boundary() -> void:
	await _play(120.0)
	var started := []
	var record := func(key): started.append(key)
	AudioDirector.music_started.connect(record)
	await _play(110.0)
	assert_str(AudioDirector.pending_music_key()).is_equal(_key(110.0))
	assert_str(AudioDirector.current_music_key()).is_equal(_key(120.0))
	assert_array(started).is_empty()
	# Mid-phrase: nothing yet.
	AudioDirector._phrase_last = 2.0
	AudioDirector._check_phrase_swap(5.0)
	AudioDirector._check_phrase_swap(7.99)
	assert_str(AudioDirector.current_music_key()).is_equal(_key(120.0))
	# The first check past the boundary swaps, 4 ms in.
	var swaps := []
	var record_swap := func(key, since): swaps.append([key, since])
	AudioDirector.tempo_swapped.connect(record_swap)
	AudioDirector._check_phrase_swap(0.004)
	AudioDirector.music_started.disconnect(record)
	AudioDirector.tempo_swapped.disconnect(record_swap)
	assert_str(AudioDirector.current_music_key()).is_equal(_key(110.0))
	assert_str(AudioDirector.pending_music_key()).is_empty()
	assert_array(started).is_equal([_key(110.0)])
	assert_array(swaps).is_equal([[_key(110.0), 0.004]])
	# A short crossfade, and the new phrase length.
	assert_float(AudioDirector._fade_sec).is_equal(AudioDirector.SWAP_FADE_SEC)
	assert_float(AudioDirector._deck_phrase_sec[AudioDirector._deck]).is_equal_approx(4 * 4 * 60.0 / 110.0, 0.001)
	AudioDirector._process(AudioDirector.SWAP_FADE_SEC)
	assert_bool(AudioDirector._decks[1 - AudioDirector._deck].playing).is_false()


func test_position_jitter_is_not_a_boundary() -> void:
	await _play(120.0)
	await _play(100.0)
	AudioDirector._phrase_last = 5.0
	AudioDirector._check_phrase_swap(4.99)  # a mix later reports a few ms back
	AudioDirector._check_phrase_swap(4.95)
	assert_str(AudioDirector.pending_music_key()).is_equal(_key(100.0))


func test_the_swap_carries_the_stem_levels() -> void:
	await _play(120.0)
	AudioDirector.set_intensity(0.6)  # harmony (0.5) plays, lead (0.85) doesn't
	AudioDirector._process(AudioDirector.STEM_FADE_SEC)
	AudioDirector._process(AudioDirector.STEM_FADE_SEC)
	AudioDirector.set_intensity(0.9)
	AudioDirector._process(AudioDirector.STEM_FADE_SEC / 2)  # the lead is half-way in
	var lead := AudioDirector.stem_level("lead")
	assert_float(lead).is_between(0.3, 0.7)
	await _play(110.0)
	AudioDirector._phrase_last = 7.9
	AudioDirector._check_phrase_swap(0.01)
	assert_str(AudioDirector.current_music_key()).is_equal(_key(110.0))
	assert_float(AudioDirector.stem_level("lead")).is_equal(lead)
	assert_float(AudioDirector.stem_level("harmony")).is_equal(1.0)
	assert_float(AudioDirector.stem_level("drums")).is_equal(1.0)


func test_a_newer_request_replaces_the_pending_one() -> void:
	await _play(120.0)
	await _play(110.0)
	assert_str(AudioDirector.pending_music_key()).is_equal(_key(110.0))
	await _play(100.0)
	assert_str(AudioDirector.pending_music_key()).is_equal(_key(100.0))
	# Back to the playing tempo: nothing is pending, and nothing swaps.
	AudioDirector.play_music(STYLE, 120.0, 3)
	assert_str(AudioDirector.pending_music_key()).is_empty()
	AudioDirector._phrase_last = 7.9
	AudioDirector._check_phrase_swap(0.01)
	assert_str(AudioDirector.current_music_key()).is_equal(_key(120.0))


func test_music_off_drops_the_pending_change() -> void:
	await _play(120.0)
	await _play(110.0)
	AudioDirector.begin_segment({"audio": {"music": false}})
	assert_str(AudioDirector.pending_music_key()).is_empty()
	await _play(120.0)
	await _play(100.0)
	AudioDirector.stop_music()
	assert_str(AudioDirector.pending_music_key()).is_empty()


func test_other_music_still_crossfades_at_once() -> void:
	await _play(120.0)
	await _play(110.0, STYLE, 4)  # another seed: new music, not a tempo change
	assert_str(AudioDirector.pending_music_key()).is_empty()
	assert_str(AudioDirector.current_music_key()).is_equal(_key(110.0, STYLE, 4))
	assert_float(AudioDirector._fade_sec).is_equal(AudioDirector.CROSSFADE_SEC)


func test_no_swap_while_paused() -> void:
	await _play(120.0)
	await _play(110.0)
	AudioDirector.set_paused(true)
	AudioDirector.set_process(true)
	await get_tree().process_frame
	AudioDirector.set_process(false)
	AudioDirector.set_paused(false)
	assert_str(AudioDirector.pending_music_key()).is_equal(_key(110.0))
