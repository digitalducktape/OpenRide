extends RefCounted
## The audio entry point (#36). AudioDirector instantiates this script at startup and calls
## `register(director)`, which plugs the generators in:
##
## - effects and cues: SfxSynth presets, rendered on first use (`register_sound_factory`);
## - music: MusicGen, on a WorkerThreadPool thread (`register_music_generator`).
##
## The framework's cue names map to presets here; every other name is a preset name.
##
## On-device timing: if `user://audio_bench` exists at startup, it is deleted and, 15 s later
## (with a game running), every style's 16-bar render is timed on a WorkerThreadPool thread and
## logged as `OPENRIDE_GAMES audio_bench …` (docs/GAMES.md, "Generated audio").

const Dsp := preload("res://audio/Dsp.gd")

## Framework cue → SfxSynth preset, where the names differ.
const ALIASES := {
	"countdown": "countdown_beep",
}
const BENCH_FLAG := "user://audio_bench"
const BENCH_DELAY_SEC := 15.0
const BENCH_TEMPO := 90.0


func register(director: Node) -> void:
	# Build the tables and load the styles on the main thread, so renders only read them.
	Dsp.warm()
	MusicGen.preload_styles()
	director.register_sound_factory(sound)
	director.register_music_generator(MusicGen.generate)
	if FileAccess.file_exists(BENCH_FLAG):
		DirAccess.remove_absolute(BENCH_FLAG)
		director.get_tree().create_timer(BENCH_DELAY_SEC).timeout.connect(func():
			WorkerThreadPool.add_task(_bench, false, "audio bench"))


## The effect or cue for a name, or null when there is no such preset.
static func sound(sound_name: String) -> AudioStream:
	return SfxSynth.stream(ALIASES.get(sound_name, sound_name))


## Times every style's uncached 16-bar render, as AudioDirector would run it (on a worker
## thread, stems in parallel), then the effect library.
static func _bench() -> void:
	var was_cached := MusicGen.cache_enabled
	MusicGen.cache_enabled = false
	var worst := 0
	for style_name in MusicGen.style_names():
		var started := Time.get_ticks_msec()
		MusicGen.render(MusicGen.style(style_name), BENCH_TEMPO, 1, MusicGen.DEFAULT_BARS)
		var ms := Time.get_ticks_msec() - started
		worst = maxi(worst, ms)
		print("OPENRIDE_GAMES audio_bench style=%s tempo=%d bars=16 stems=4 ms=%d" % [style_name, BENCH_TEMPO, ms])
	MusicGen.cache_enabled = was_cached
	var started := Time.get_ticks_msec()
	for p in SfxSynth.names():
		SfxSynth.render(SfxSynth.preset(p))
	print("OPENRIDE_GAMES audio_bench presets=%d ms=%d" % [SfxSynth.names().size(), Time.get_ticks_msec() - started])
	print("OPENRIDE_GAMES audio_bench done worst_ms=%d cores=%d" % [worst, OS.get_processor_count()])
