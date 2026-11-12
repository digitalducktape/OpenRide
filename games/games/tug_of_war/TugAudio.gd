extends RefCounted
## Tug of War's own sounds (#40), registered with AudioDirector by the game scene.
##
## Rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/tug_of_war.py, in the music's
## key): rope_creak (its pitch follows the rope's tension), crowd_swell, surge_drumroll (the
## one-second warning), win_sting, lose_sting and splash. They replace the synth presets of the
## same names (`sfx/*.tres`, SfxSynth's fallback). The music is "Heave Together" (TugMusic).
## Bus effects for this game only: a river-wide reverb and a glue compressor on the music.

const SFX_DIR := "res://games/tug_of_war/sfx"
const TugMusic := preload("res://games/tug_of_war/TugMusic.gd")


static func register() -> void:
	SfxSynth.add_preset_dir(SFX_DIR)
	GameAudio.register(TugMusic.SOUNDS)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.5
	reverb.damping = 0.55
	reverb.spread = 0.9
	reverb.dry = 1.0
	reverb.wet = 0.14
	reverb.predelay_msec = 30.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -14.0
	glue.ratio = 3.0
	glue.attack_us = 8000.0
	glue.release_ms = 180.0
	glue.gain = 2.0
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.4
	reverb.damping = 0.5
	reverb.dry = 1.0
	reverb.wet = 0.1
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
