extends RefCounted
## The audio entry point (#36). AudioDirector instantiates this script at startup and calls
## `register(director)`, which plugs the generators in:
##
## - effects and cues: SfxSynth presets, rendered on first use (`register_sound_factory`);
## - music: MusicGen, on a WorkerThreadPool thread (`register_music_generator`).
##
## The framework's cue names map to presets here; every other name is a preset name.

const Dsp := preload("res://audio/Dsp.gd")

## Framework cue → SfxSynth preset, where the names differ.
const ALIASES := {
	"countdown": "countdown_beep",
}


func register(director: Node) -> void:
	# Build the tables and load the styles on the main thread, so renders only read them.
	Dsp.warm()
	MusicGen.preload_styles()
	director.register_sound_factory(sound)
	director.register_music_generator(MusicGen.generate)


## The effect or cue for a name, or null when there is no such preset.
static func sound(sound_name: String) -> AudioStream:
	return SfxSynth.stream(ALIASES.get(sound_name, sound_name))
