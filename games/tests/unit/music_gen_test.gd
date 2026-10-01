extends GdUnitTestSuite
## MusicGen (#36): deterministic output for a seed, sample-accurate loops with no clicks,
## stem lengths for the tempo and bar count, every style, threading, the phrase clock and the
## disk cache.

const Dsp := preload("res://audio/Dsp.gd")
const GAME_STYLES := ["drive", "heave", "noir", "bright", "racer", "demo_drive"]


func before() -> void:
	MusicGen.cache_enabled = false
	MusicGen.parallel = true


func after() -> void:
	MusicGen.cache_enabled = true
	MusicGen.parallel = true


static func _peak(wav: AudioStreamWAV) -> float:
	var peak := 0.0
	var data := wav.data
	for i in data.size() / 2:
		peak = maxf(peak, absf(data.decode_s16(i * 2) / 32768.0))
	return peak


func test_the_game_styles_exist() -> void:
	for style_name in GAME_STYLES:
		assert_object(MusicGen.style(style_name)).override_failure_message("missing style " + style_name).is_not_null()


func test_same_seed_same_music() -> void:
	var style := MusicGen.style("drive")
	var a := MusicGen.render(style, 90.0, 42, 8)
	var b := MusicGen.render(style, 90.0, 42, 8)
	for stem in MusicGen.STEMS:
		assert_bool((a[stem] as AudioStreamWAV).data == (b[stem] as AudioStreamWAV).data) \
			.override_failure_message(stem + " differs for the same seed").is_true()


func test_another_seed_another_tune() -> void:
	var style := MusicGen.style("drive")
	assert_bool(MusicGen.compose(style, 1).lead == MusicGen.compose(style, 2).lead).is_false()
	var a := MusicGen.render(style, 90.0, 1, 8)
	var b := MusicGen.render(style, 90.0, 2, 8)
	assert_bool((a.lead as AudioStreamWAV).data == (b.lead as AudioStreamWAV).data).is_false()


func test_the_tune_does_not_depend_on_the_tempo() -> void:
	var style := MusicGen.style("bright")
	assert_bool(MusicGen.compose(style, 5) == MusicGen.compose(style, 5)).is_true()
	var slow := MusicGen.render(style, 70.0, 5, 4)
	var fast := MusicGen.render(style, 100.0, 5, 4)
	assert_int(Dsp.frames(slow.bass)).is_greater(Dsp.frames(fast.bass))


func test_stem_length_matches_tempo_and_bars() -> void:
	var style := MusicGen.style("racer")
	for case in [[90.0, 16], [73.3, 8], [120.0, 4], [61.0, 16]]:
		var tempo: float = case[0]
		var bars: int = case[1]
		var stems := MusicGen.render(style, tempo, 3, bars)
		var expected := bars * int(round(4 * 60.0 * Dsp.SR / tempo))
		assert_int(MusicGen.loop_samples(tempo, bars)).is_equal(expected)
		# The length is within half a sample per bar of the exact tempo.
		assert_float(absf(expected - bars * 4 * 60.0 * Dsp.SR / tempo)).is_less_equal(bars * 0.5)
		assert_array(stems.keys()).contains_exactly_in_any_order(MusicGen.STEMS)
		for stem in MusicGen.STEMS:
			var wav: AudioStreamWAV = stems[stem]
			assert_int(Dsp.frames(wav)).override_failure_message("%s at %s bpm, %d bars" % [stem, tempo, bars]).is_equal(expected)
			assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
			assert_int(wav.loop_begin).is_equal(0)
			assert_int(wav.loop_end).is_equal(expected)


func test_tempo_scale_multiplies_the_requested_tempo() -> void:
	var double := MusicGen.resolve_style({"name": "drive", "tempo_scale": 2.0})
	assert_float(MusicGen.music_tempo(double, 80.0)).is_equal(160.0)
	assert_float(MusicGen.music_tempo(MusicGen.style("drive"), 80.0)).is_equal(80.0)
	var stems := MusicGen.render(double, 80.0, 4, 4)
	assert_int(Dsp.frames(stems.drums)).is_equal(MusicGen.loop_samples(160.0, 4))


func test_loops_join_without_clicks() -> void:
	# Every bar (so the loop point too) starts and ends at silence, and the step across each
	# join is no bigger than the stem's steps elsewhere.
	for style_name in GAME_STYLES:
		var stems := MusicGen.render(MusicGen.style(style_name), 88.0, 11, 8)
		var bar := MusicGen.bar_samples(88.0)
		for stem in MusicGen.STEMS:
			var wav: AudioStreamWAV = stems[stem]
			var n := Dsp.frames(wav)
			assert_float(Dsp.sample(wav, 0)).is_equal(0.0)
			assert_float(Dsp.sample(wav, n - 1)).is_equal(0.0)
			for b in range(1, 8):
				var join := b * bar
				var step := absf(Dsp.sample(wav, join) - Dsp.sample(wav, join - 1))
				assert_float(step).override_failure_message("%s %s bar %d join" % [style_name, stem, b]).is_less(0.01)


func test_every_style_renders_audible_unclipped_stems() -> void:
	for style_name in GAME_STYLES:
		var stems := MusicGen.render(MusicGen.style(style_name), 80.0, 9, 16)
		for stem in MusicGen.STEMS:
			var peak := _peak(stems[stem])
			assert_float(peak).override_failure_message("%s %s peak %.3f" % [style_name, stem, peak]).is_between(0.1, 0.5)


func test_melody_and_bass_stay_in_range() -> void:
	for style_name in GAME_STYLES:
		var style := MusicGen.style(style_name)
		var score := MusicGen.compose(style, 17)
		for bar: Array in score.lead:
			for ev: Array in bar:
				assert_int(int(ev[2])).override_failure_message("%s lead note %d" % [style_name, ev[2]]) \
					.is_between(style.lead_low, style.lead_high)
		for bar: Array in score.bass:
			for ev: Array in bar:
				assert_int(int(ev[2])).is_between(style.root - 7, style.root + 19)


func test_the_form_repeats_the_first_phrase_at_the_end() -> void:
	var score := MusicGen.compose(MusicGen.style("bright"), 23)
	for stem in ["lead", "harmony", "bass"]:
		for k in 4:
			assert_array(score[stem][12 + k]).is_equal(score[stem][k])
	assert_str(score.chords[8].section).is_equal("B")


func test_parallel_and_serial_renders_match() -> void:
	var style := MusicGen.style("noir")
	MusicGen.parallel = false
	var serial := MusicGen.render(style, 75.0, 8, 4)
	MusicGen.parallel = true
	var par := MusicGen.render(style, 75.0, 8, 4)
	for stem in MusicGen.STEMS:
		assert_bool((serial[stem] as AudioStreamWAV).data == (par[stem] as AudioStreamWAV).data).is_true()


func test_overrides_change_the_render() -> void:
	var base := MusicGen.resolve_style({"name": "racer"})
	var lap := MusicGen.resolve_style({"name": "racer", "transpose": 2, "energy": 1.0, "stem_gates": {"lead": 0.5}})
	assert_int(lap.transpose).is_equal(2)
	assert_float(lap.energy).is_equal(1.0)
	assert_int(base.transpose).is_equal(0)
	assert_int(MusicGen.style("racer").transpose).is_equal(0)  # the library style is untouched
	assert_str(MusicGen.cache_key(base, 90.0, 1, 16)).is_not_equal(MusicGen.cache_key(lap, 90.0, 1, 16))


func test_generate_follows_the_director_contract_on_a_worker_thread() -> void:
	var result := []
	var request := {"style": {"name": "demo_drive", "stem_gates": {"harmony": 0.5, "lead": 0.85}, "bars": 4}, "tempo_bpm": 95.0, "seed": 3}
	var task := WorkerThreadPool.add_task(func(): result.append(MusicGen.generate(request)))
	WorkerThreadPool.wait_for_task_completion(task)
	var stems: Dictionary = result[0]
	assert_array(stems.keys()).contains_exactly_in_any_order(["drums", "bass", "harmony", "lead"])
	for stem in stems:
		assert_int(Dsp.frames(stems[stem])).is_equal(MusicGen.loop_samples(95.0, 4))
	assert_dict(MusicGen.generate({"style": {"name": "no_such_style"}, "tempo_bpm": 90.0, "seed": 0})).is_empty()


func test_phrase_clock() -> void:
	var phrase := MusicGen.bar_samples(90.0) * 4 / float(Dsp.SR)  # 10.67 s
	assert_float(MusicGen.seconds_to_next_phrase(0.0, 90.0)).is_equal(0.0)
	assert_float(MusicGen.seconds_to_next_phrase(1.0, 90.0)).is_equal_approx(phrase - 1.0, 0.0001)
	assert_float(MusicGen.seconds_to_next_phrase(phrase + 2.5, 90.0)).is_equal_approx(phrase - 2.5, 0.0001)
	assert_float(MusicGen.seconds_to_next_phrase(phrase - 0.01, 90.0)).is_equal_approx(0.01, 0.0001)


func test_the_disk_cache_returns_the_same_stems_and_prunes() -> void:
	MusicGen.clear_cache()
	MusicGen.cache_enabled = true
	var style := MusicGen.style("heave")
	var first := MusicGen.render(style, 66.0, 1, 4)
	var path := "%s/%s.stems" % [MusicGen.CACHE_DIR, MusicGen.cache_key(style, 66.0, 1, 4)]
	assert_bool(FileAccess.file_exists(path)).is_true()
	var again := MusicGen.render(style, 66.0, 1, 4)
	for stem in MusicGen.STEMS:
		assert_bool((first[stem] as AudioStreamWAV).data == (again[stem] as AudioStreamWAV).data).is_true()
		assert_int((again[stem] as AudioStreamWAV).loop_end).is_equal(Dsp.frames(first[stem]))
	# A second entry, then a limit that fits only one: the other one goes, never `keep`.
	MusicGen.render(style, 67.0, 1, 4)
	var newer := "%s/%s.stems" % [MusicGen.CACHE_DIR, MusicGen.cache_key(style, 67.0, 1, 4)]
	var size := FileAccess.open(newer, FileAccess.READ).get_length()
	MusicGen.prune_cache(size + 1, newer)
	assert_bool(FileAccess.file_exists(newer)).is_true()
	assert_int(DirAccess.get_files_at(MusicGen.CACHE_DIR).size()).is_equal(1)
	MusicGen.clear_cache()
	MusicGen.cache_enabled = false
