extends GdUnitTestSuite
## AudioDirector: buses, segment audio settings, silence until generators register, the
## registration API #36 plugs into, music rendering off the main thread, crossfades, stem
## gates and ducking.

const SEGMENT_AUDIO := {"audio": {"music": true, "music_volume": 0.5, "sfx_volume": 0.25}}


static func _tone(seconds := 0.25) -> AudioStreamWAV:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	var data := PackedByteArray()
	data.resize(int(8000 * seconds) * 2)
	wav.data = data
	return wav


static func _stems(_request: Dictionary) -> Dictionary:
	return {"drums": _tone(), "bass": _tone(), "lead": _tone()}


func before_test() -> void:
	AudioDirector.begin_session()
	AudioDirector.begin_segment(SEGMENT_AUDIO)
	AudioDirector._sounds.clear()
	AudioDirector._sound_factories.clear()
	AudioDirector._music_generator = Callable()
	AudioDirector._music_cache.clear()
	AudioDirector.stop_music(0.0)
	AudioDirector._cue_left = 0.0
	AudioDirector.duck_db = 0.0


func after_test() -> void:
	AudioDirector.end_session()
	AudioDirector._music_generator = Callable()
	AudioDirector._sounds.clear()
	AudioDirector._sound_factories.clear()


func test_buses_exist_and_feed_master() -> void:
	for bus in ["Music", "SFX", "Cues"]:
		var index := AudioServer.get_bus_index(bus)
		assert_int(index).is_greater(0)
		assert_str(AudioServer.get_bus_send(index)).is_equal("Master")


func test_segment_audio_sets_bus_volumes() -> void:
	AudioDirector._process(0.0)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music"))).is_equal_approx(linear_to_db(0.5), 0.01)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("SFX"))).is_equal_approx(linear_to_db(0.25), 0.01)
	assert_float(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Cues"))).is_equal_approx(linear_to_db(0.25), 0.01)


func test_unknown_sounds_are_silent() -> void:
	assert_bool(AudioDirector.play_sfx("whoosh")).is_false()
	assert_bool(AudioDirector.play_cue("go")).is_false()


func test_registered_sounds_play_on_their_bus() -> void:
	var played := []
	var record := func(sound, bus): played.append([sound, bus])
	AudioDirector.sound_played.connect(record)
	AudioDirector.register_sound("whoosh", _tone())
	AudioDirector.register_sound("go", _tone())
	assert_bool(AudioDirector.play_sfx("whoosh")).is_true()
	assert_bool(AudioDirector.play_cue("go")).is_true()
	AudioDirector.sound_played.disconnect(record)
	assert_array(played).is_equal([["whoosh", "SFX"], ["go", "Cues"]])


func test_a_sound_factory_renders_each_name_once() -> void:
	var asked := []
	AudioDirector.register_sound_factory(func(sound: String):
		asked.append(sound)
		return _tone() if sound == "thud" else null)
	assert_bool(AudioDirector.play_sfx("thud")).is_true()
	assert_bool(AudioDirector.play_sfx("thud")).is_true()
	assert_bool(AudioDirector.play_sfx("nothing")).is_false()
	assert_array(asked).is_equal(["thud", "nothing"])


func test_music_is_silent_without_a_generator() -> void:
	AudioDirector.play_music({"name": "x"}, 90.0, 1)
	await await_millis(50)
	assert_bool(AudioDirector.is_music_playing()).is_false()
	assert_bool(AudioDirector.has_music_generator()).is_false()


func test_music_renders_off_the_main_thread_then_plays() -> void:
	var main_thread := OS.get_thread_caller_id()
	var seen := [main_thread, {}]
	AudioDirector.register_music_generator(func(request: Dictionary):
		seen[0] = OS.get_thread_caller_id()
		seen[1] = request
		return _stems(request))
	AudioDirector.play_music({"name": "drive"}, 90.0, 7)
	await _until(func(): return AudioDirector.is_music_playing())
	assert_bool(AudioDirector.is_music_playing()).is_true()
	assert_int(seen[0]).is_not_equal(main_thread)
	assert_dict(seen[1]).is_equal({"style": {"name": "drive"}, "tempo_bpm": 90.0, "seed": 7})
	assert_str(AudioDirector.current_music_key()).is_equal(
		AudioDirector.music_key({"style": {"name": "drive"}, "tempo_bpm": 90.0, "seed": 7}))


func test_asking_again_for_the_same_music_changes_nothing() -> void:
	var renders := [0]
	AudioDirector.register_music_generator(func(request: Dictionary):
		renders[0] += 1
		return _stems(request))
	var started := []
	var record := func(key): started.append(key)
	AudioDirector.music_started.connect(record)
	AudioDirector.play_music({"name": "drive"}, 90.0, 7)
	await _until(func(): return AudioDirector.is_music_playing())
	AudioDirector.play_music({"name": "drive"}, 90.0, 7)
	await await_millis(50)
	AudioDirector.music_started.disconnect(record)
	assert_int(renders[0]).is_equal(1)
	assert_int(started.size()).is_equal(1)


func test_new_music_crossfades_in() -> void:
	AudioDirector.register_music_generator(_stems)
	AudioDirector.play_music({"name": "one"}, 90.0, 1)
	await _until(func(): return AudioDirector.is_music_playing())
	AudioDirector._process(AudioDirector.CROSSFADE_SEC)
	var first := AudioDirector.current_music_key()
	AudioDirector.play_music({"name": "two"}, 100.0, 1)
	await _until(func(): return AudioDirector.current_music_key() != first)
	var new_deck: AudioStreamPlayer = AudioDirector._decks[AudioDirector._deck]
	var old_deck: AudioStreamPlayer = AudioDirector._decks[1 - AudioDirector._deck]
	AudioDirector._process(AudioDirector.CROSSFADE_SEC / 2)
	assert_bool(old_deck.playing).is_true()  # both sound mid-fade
	assert_float(new_deck.volume_db).is_greater(AudioDirector.SILENT_DB)
	assert_float(old_deck.volume_db).is_greater(AudioDirector.SILENT_DB)
	AudioDirector._process(AudioDirector.CROSSFADE_SEC)
	assert_bool(old_deck.playing).is_false()
	assert_float(new_deck.volume_db).is_equal_approx(0.0, 0.01)


func test_music_off_keeps_the_request_but_plays_nothing() -> void:
	AudioDirector.register_music_generator(_stems)
	AudioDirector.begin_segment({"audio": {"music": false, "music_volume": 0.8, "sfx_volume": 1.0}})
	AudioDirector.play_music({"name": "drive"}, 90.0, 7)
	await await_millis(100)
	assert_bool(AudioDirector.is_music_playing()).is_false()
	assert_bool(AudioDirector.music_enabled).is_false()


func test_music_off_in_a_new_segment_fades_the_music_out() -> void:
	AudioDirector.register_music_generator(_stems)
	AudioDirector.play_music({"name": "drive"}, 90.0, 7)
	await _until(func(): return AudioDirector.is_music_playing())
	AudioDirector.begin_segment({"audio": {"music": false}})
	assert_bool(AudioDirector.is_music_playing()).is_false()
	AudioDirector._process(AudioDirector.CROSSFADE_SEC)
	assert_bool(AudioDirector._decks[0].playing or AudioDirector._decks[1].playing).is_false()


func test_stems_follow_intensity_gates() -> void:
	AudioDirector.register_music_generator(_stems)
	AudioDirector.set_intensity(0.2)
	AudioDirector.play_music({"name": "drive", "stem_gates": {"lead": 0.6}}, 90.0, 7)
	await _until(func(): return AudioDirector.is_music_playing())
	assert_float(AudioDirector.stem_level("drums")).is_equal(1.0)
	assert_float(AudioDirector.stem_level("lead")).is_equal(0.0)
	AudioDirector.set_intensity(0.8)
	AudioDirector._process(AudioDirector.STEM_FADE_SEC)
	assert_float(AudioDirector.stem_level("lead")).is_equal(1.0)
	assert_float(AudioDirector.stem_level("missing")).is_equal(-1.0)


func test_cues_duck_the_music_then_release() -> void:
	AudioDirector.register_sound("go", _tone(0.25))
	AudioDirector.play_cue("go")
	AudioDirector._process(0.1)
	assert_float(AudioDirector.duck_db).is_equal(AudioDirector.DUCK_DB)
	AudioDirector._process(0.2)  # the cue is over
	AudioDirector._process(AudioDirector.DUCK_RELEASE_SEC)
	assert_float(AudioDirector.duck_db).is_equal(0.0)


func test_pause_pauses_music_and_effects_not_cues() -> void:
	AudioDirector.register_music_generator(_stems)
	AudioDirector.register_sound("thud", _tone(5.0))
	AudioDirector.play_music({"name": "drive"}, 90.0, 7)
	await _until(func(): return AudioDirector.is_music_playing())
	var sfx: AudioStreamPlayer = AudioDirector._sfx_players[AudioDirector._next_sfx]
	var cue: AudioStreamPlayer = AudioDirector._cue_players[AudioDirector._next_cue]
	AudioDirector.play_sfx("thud")
	AudioDirector.play_cue("thud")
	var music: AudioStreamPlayer = AudioDirector._decks[AudioDirector._deck]
	AudioDirector.set_paused(true)
	assert_bool(music.stream_paused).is_true()
	assert_bool(sfx.stream_paused).is_true()
	assert_bool(cue.stream_paused).is_false()
	AudioDirector.set_paused(false)
	assert_bool(music.stream_paused).is_false()
	assert_bool(sfx.stream_paused).is_false()


func _until(condition: Callable, timeout_ms := 2000) -> void:
	var start := Time.get_ticks_msec()
	while not condition.call() and Time.get_ticks_msec() - start < timeout_ms:
		await get_tree().process_frame
