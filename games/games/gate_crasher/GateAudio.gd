class_name GateAudio
extends RefCounted
## Gate Crasher's sounds (#80): rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/
## gate_crasher.py, in the theme's key), registered with AudioDirector and played through it. The
## hoofbeats are one three-beat stride played per stride, so they follow the pace. The music is
## "Clear Round" (GateMusic). Bus effects: an open-air room.

const GateMusic := preload("res://games/gate_crasher/GateMusic.gd")


static func register() -> void:
	GameAudio.register(GateMusic.SOUNDS)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.55
	reverb.damping = 0.5
	reverb.spread = 1.0
	reverb.dry = 1.0
	reverb.wet = 0.1
	reverb.predelay_msec = 35.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -14.0
	glue.ratio = 3.0
	glue.attack_us = 8000.0
	glue.release_ms = 200.0
	glue.gain = 2.0
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.5
	reverb.damping = 0.5
	reverb.dry = 1.0
	reverb.wet = 0.08
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
