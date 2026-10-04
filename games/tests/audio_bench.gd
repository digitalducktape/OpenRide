extends SceneTree
## Times MusicGen renders (#36): every library style, 16 bars, 4 stems, from scratch (no disk
## cache), serial and with the stems in parallel, and every SfxSynth preset.
##   $GODOT_BIN --headless --path games -s res://tests/audio_bench.gd [-- --tempo=90 --wav=DIR]
## With --wav, it also writes each style's mix and every preset as .wav files for auditioning.

const Dsp := preload("res://audio/Dsp.gd")


func _initialize() -> void:
	var tempo := 90.0
	var wav_dir := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tempo="):
			tempo = float(arg.get_slice("=", 1))
		elif arg.begins_with("--wav="):
			wav_dir = arg.get_slice("=", 1)
	var t := Time.get_ticks_usec()
	Dsp.warm()
	print("tables %.0f ms" % ((Time.get_ticks_usec() - t) / 1000.0))
	MusicGen.cache_enabled = false
	for style_name in MusicGen.style_names():
		var style := MusicGen.style(style_name)
		var times := []
		for par in [false, true]:
			MusicGen.parallel = par
			t = Time.get_ticks_usec()
			var stems := MusicGen.render(style, tempo, 7)
			times.append((Time.get_ticks_usec() - t) / 1000.0)
			if par and not wav_dir.is_empty():
				_write_mix(stems, "%s/%s_%d.wav" % [wav_dir, style_name, int(tempo)])
		print("%-11s %d bpm 16 bars: serial %6.0f ms, parallel %6.0f ms (%.1f s of audio)" % [style_name, tempo,
			times[0], times[1], MusicGen.loop_samples(tempo) / float(Dsp.SR)])
	t = Time.get_ticks_usec()
	for sound in SfxSynth.names():
		var wav := SfxSynth.render(SfxSynth.preset(sound))
		if not wav_dir.is_empty():
			wav.save_to_wav("%s/sfx_%s.wav" % [wav_dir, sound])
	print("all %d presets: %.0f ms" % [SfxSynth.names().size(), (Time.get_ticks_usec() - t) / 1000.0])
	quit()


## Sums the stems into one file (for listening; the game plays them as separate stems).
func _write_mix(stems: Dictionary, path: String) -> void:
	var n := Dsp.frames(stems.drums)
	var mix := PackedFloat32Array()
	mix.resize(n)
	var peak := 0.0
	for stem in stems:
		var wav: AudioStreamWAV = stems[stem]
		for i in n:
			mix[i] += Dsp.sample(wav, i)
	for i in n:
		peak = maxf(peak, absf(mix[i]))
	Dsp.to_wav(mix).save_to_wav(path)
	print("  wrote %s (mix peak %.2f)" % [path, peak])
