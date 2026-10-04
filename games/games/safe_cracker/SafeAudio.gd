extends RefCounted
## Safe Cracker's own sounds (#41), registered with AudioDirector by the game scene.
##
## Synth presets (`sfx/*.tres`, through SfxSynth): tumbler_click, proximity_tick (played faster
## as the dial nears a hidden target), soft_alarm (gentle: no sirens during recovery),
## vault_open and door_creak. The music is the `noir` style, sparse and calm, which thins out
## while the alarm light is on. Bus effects for this game only: a small-room reverb and a
## glue compressor on the music.

const SFX_DIR := "res://games/safe_cracker/sfx"

static var _registered := false


static func register() -> void:
	if _registered:
		return
	_registered = true
	SfxSynth.add_preset_dir(SFX_DIR)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.3
	reverb.damping = 0.65
	reverb.spread = 0.7
	reverb.dry = 1.0
	reverb.wet = 0.12
	reverb.predelay_msec = 15.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -16.0
	glue.ratio = 2.5
	glue.attack_us = 10000.0
	glue.release_ms = 220.0
	glue.gain = 1.5
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.2
	reverb.damping = 0.5
	reverb.dry = 1.0
	reverb.wet = 0.07
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
