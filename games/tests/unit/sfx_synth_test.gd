extends GdUnitTestSuite
## SfxSynth (#36): every library preset renders, deterministically, cleanly (starts and ends
## at silence, no clipping), and the cache, overrides and loops behave.

const Dsp := preload("res://audio/Dsp.gd")
const STARTER := ["whoosh", "thud", "click", "chime", "alarm_soft", "boost", "countdown_beep", "go"]
const CUES := ["segment_end", "pause", "resume", "summary"]


func after_test() -> void:
	SfxSynth._presets.clear()
	SfxSynth.clear_cache()


static func _peak(wav: AudioStreamWAV) -> float:
	var peak := 0.0
	for i in Dsp.frames(wav):
		peak = maxf(peak, absf(Dsp.sample(wav, i)))
	return peak


func test_the_library_has_the_starter_presets_and_the_cues() -> void:
	var names := SfxSynth.names()
	for sound in STARTER + CUES + ["dodge", "hit"]:
		assert_bool(names.has(sound)).override_failure_message("missing preset " + sound).is_true()


func test_every_preset_renders_a_clean_one_shot() -> void:
	for sound in SfxSynth.names():
		var p := SfxSynth.preset(sound)
		var wav := SfxSynth.render(p)
		var n := Dsp.frames(wav)
		assert_int(wav.format).is_equal(AudioStreamWAV.FORMAT_16_BITS)
		assert_int(wav.mix_rate).is_equal(Dsp.SR)
		assert_bool(wav.stereo).is_false()
		# Length matches the envelope (within a sample of rounding per stage).
		assert_int(n).override_failure_message("%s length %d" % [sound, n]).is_between(
			int(p.duration() * Dsp.SR) - 4, int(p.duration() * Dsp.SR) + 4)
		var peak := _peak(wav)
		assert_float(peak).override_failure_message("%s peak %.3f" % [sound, peak]).is_between(0.05, 0.99)
		if not p.loop:
			assert_float(absf(Dsp.sample(wav, 0))).override_failure_message(sound + " starts with a click").is_less(0.002)
			assert_float(absf(Dsp.sample(wav, n - 1))).override_failure_message(sound + " ends with a click").is_less(0.002)
			assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_DISABLED)


func test_rendering_is_deterministic() -> void:
	for sound in ["whoosh", "hit", "chime"]:
		var a := SfxSynth.render(SfxSynth.preset(sound))
		var b := SfxSynth.render(SfxSynth.preset(sound))
		assert_bool(a.data == b.data).override_failure_message(sound + " differs between renders").is_true()


func test_parameters_change_the_sound() -> void:
	var low := SfxPreset.new()
	low.freq_start = 220.0
	low.freq_end = 220.0
	var high := low.duplicate()
	high.freq_start = 880.0
	high.freq_end = 880.0
	assert_bool(SfxSynth.render(low).data == SfxSynth.render(high).data).is_false()


func test_repeats_play_the_sound_again() -> void:
	var p := SfxPreset.new()
	p.sustain = 0.05
	p.decay = 0.05
	p.repeats = 3
	p.repeat_gap = 0.2
	var wav := SfxSynth.render(p)
	assert_int(Dsp.frames(wav)).is_between(int(0.505 * Dsp.SR) - 4, int(0.505 * Dsp.SR) + 4)
	# Sound at the start of each repeat, silence between them.
	for r in 3:
		var at := int((r * 0.2 + 0.02) * Dsp.SR)
		assert_float(absf(Dsp.sample(wav, at)) + absf(Dsp.sample(wav, at + 7))).is_greater(0.01)
	assert_float(absf(Dsp.sample(wav, int(0.15 * Dsp.SR)))).is_less(0.0001)


func test_a_looping_preset_joins_seamlessly() -> void:
	var p := SfxPreset.new()
	p.wave = SfxPreset.Wave.SAW
	p.freq_start = 97.0  # not a whole number of cycles in the loop
	p.freq_end = 97.0
	p.sustain = 0.5
	p.lowpass_start = 1500.0
	p.loop = true
	var wav := SfxSynth.render(p)
	var n := Dsp.frames(wav)
	assert_int(n).is_equal(int(0.5 * Dsp.SR))
	assert_int(wav.loop_mode).is_equal(AudioStreamWAV.LOOP_FORWARD)
	assert_int(wav.loop_end).is_equal(n)
	# The jump from the last sample to the first is no bigger than the sound's usual steps.
	var max_step := 0.0
	for i in range(1, n):
		max_step = maxf(max_step, absf(Dsp.sample(wav, i) - Dsp.sample(wav, i - 1)))
	var seam := absf(Dsp.sample(wav, 0) - Dsp.sample(wav, n - 1))
	assert_float(seam).is_less_equal(max_step * 1.1)


func test_streams_are_cached_and_presets_can_be_added() -> void:
	assert_object(SfxSynth.stream("click")).is_same(SfxSynth.stream("click"))
	assert_object(SfxSynth.stream("no_such_sound")).is_null()
	var p := SfxPreset.new()
	p.wave = SfxPreset.Wave.NOISE
	SfxSynth.add_preset("launch_whoosh", p)
	assert_object(SfxSynth.stream("launch_whoosh")).is_not_null()
	assert_bool(SfxSynth.names().has("launch_whoosh")).is_true()
	# A preset added in code wins over the library's, and replaces its cached render.
	var before := SfxSynth.stream("click")
	SfxSynth.add_preset("click", p)
	assert_object(SfxSynth.stream("click")).is_not_same(before)
