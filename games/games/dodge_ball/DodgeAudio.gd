extends RefCounted
## Dodge Ball's own sounds (#39), registered with AudioDirector by the game scene.
##
## - Synth presets (`sfx/*.tres`, through SfxSynth): launch_whoosh, dodge_tick, streak_chime,
##   hit_body, shield_zap, shield_ready, game_over.
## - Recorded CC0 one-shots (`sounds/`, Kenney "Impact Sounds"; see assets/SOURCES.md): the
##   hit's thud, the shield's glassy break and a ball's bounce. A hit plays the recording and
##   the synth body together, so it has both a real impact and a deep thump.
## - Bus effects for this game only (AudioDirector.set_bus_effects): a short room reverb and a
##   glue compressor on the music, a smaller reverb on the effects.

const SFX_DIR := "res://games/dodge_ball/sfx"
const SOUNDS := {
	"hit_thud": "res://games/dodge_ball/sounds/impactPunch_heavy_001.ogg",
	"shield_break": "res://games/dodge_ball/sounds/impactGlass_heavy_002.ogg",
	"ball_bounce": "res://games/dodge_ball/sounds/impactSoft_heavy_000.ogg",
}

static var _registered := false


static func register() -> void:
	if _registered:
		return
	_registered = true
	SfxSynth.add_preset_dir(SFX_DIR)
	for sound in SOUNDS:
		var stream := load(SOUNDS[sound]) as AudioStream
		if stream:
			AudioDirector.register_sound(sound, stream)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.35
	reverb.damping = 0.6
	reverb.spread = 0.8
	reverb.dry = 1.0
	reverb.wet = 0.12
	reverb.predelay_msec = 20.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -14.0
	glue.ratio = 3.0
	glue.attack_us = 8000.0
	glue.release_ms = 180.0
	glue.gain = 2.0
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.25
	reverb.damping = 0.5
	reverb.dry = 1.0
	reverb.wet = 0.08
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
