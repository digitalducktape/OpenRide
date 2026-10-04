extends RefCounted
## Tug of War's own sounds (#40), registered with AudioDirector by the game scene.
##
## Synth presets (`sfx/*.tres`, through SfxSynth): rope_creak (its pitch follows the rope's
## tension), crowd_swell (a noise-filtered swell), surge_drumroll (the one-second warning),
## win_sting, lose_sting and splash. The music is the `heave` style: heavy half-time drums
## and a bass that builds, with the drum stem louder while the rope is tight.
## Bus effects for this game only: a river-wide reverb and a glue compressor on the music.

const SFX_DIR := "res://games/tug_of_war/sfx"

static var _registered := false


static func register() -> void:
	if _registered:
		return
	_registered = true
	SfxSynth.add_preset_dir(SFX_DIR)


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
