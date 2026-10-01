extends GdUnitTestSuite
## Cues.gd, the audio entry point AudioDirector calls at startup (#36): every cue the
## framework plays and the demo's effects come from SfxSynth, and music comes from MusicGen.

const FRAMEWORK_CUES := ["countdown", "go", "segment_end", "pause", "resume", "summary"]


func before_test() -> void:
	_reset()
	load("res://audio/Cues.gd").new().register(AudioDirector)


func after_test() -> void:
	_reset()


func _reset() -> void:
	AudioDirector._sounds.clear()
	AudioDirector._sound_factories.clear()
	AudioDirector._music_generator = Callable()
	AudioDirector._music_cache.clear()
	AudioDirector.stop_music(0.0)


func test_every_framework_cue_and_demo_effect_plays() -> void:
	for cue in FRAMEWORK_CUES:
		assert_bool(AudioDirector.play_cue(cue)).override_failure_message("cue %s is silent" % cue).is_true()
	for sound in ["dodge", "hit", "whoosh", "chime"]:
		assert_bool(AudioDirector.play_sfx(sound)).override_failure_message("effect %s is silent" % sound).is_true()
	assert_bool(AudioDirector.play_sfx("no_such_sound")).is_false()


func test_music_renders_off_the_main_thread_and_plays() -> void:
	MusicGen.cache_enabled = false
	assert_bool(AudioDirector.has_music_generator()).is_true()
	AudioDirector.play_music({"name": "demo_drive", "stem_gates": {"harmony": 0.5, "lead": 0.85}, "bars": 4}, 90.0, 1)
	var started := []
	AudioDirector.music_started.connect(func(key): started.append(key))
	var waited := 0
	while started.is_empty() and waited < 300:
		await get_tree().process_frame
		waited += 1
	MusicGen.cache_enabled = true
	assert_int(started.size()).is_equal(1)
	assert_float(AudioDirector.stem_level("lead")).is_equal(1.0)  # intensity starts at 1
	assert_float(AudioDirector.stem_level("drums")).is_equal(1.0)
