extends RefCounted
## Keepy Uppy's own sounds (#77), registered with AudioDirector by the game scene.
##
## Rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/keepy_uppy.py, in the music's key
## of G), named `keepy_*` because AudioDirector keeps one sound per name across every game:
## keepy_squeak (the balloon near the ground), keepy_pop, keepy_bird_flutter, keepy_birds_shaken,
## keepy_gust, keepy_downdraft_warn, keepy_rain_warn, keepy_new_balloon and keepy_high_chime are
## one-shots through `AudioDirector.play_sfx`. keepy_fan_hum and keepy_rain are seamless loops the
## game plays on its own two players (`loop_player`), because a one-shot voice can't be pitched
## or faded while it plays. The music is "Meadow Breeze" (KeepyMusic). Bus effects for this game
## only: a wide, airy reverb (an open field, not a room) and a glue compressor on the music.

const KeepyMusic := preload("res://games/keepy_uppy/KeepyMusic.gd")
const LOOPS := ["keepy_fan_hum", "keepy_rain"]

static var _registered := false


static func register() -> void:
	if _registered:
		return
	_registered = true
	for sound in KeepyMusic.SOUNDS:
		if sound in LOOPS:
			continue
		var rendered := load(KeepyMusic.SOUNDS[sound]) as AudioStream
		if rendered:
			AudioDirector.register_sound(sound, rendered)


## A player on the SFX bus for one of the loops, silent until the game raises it.
static func loop_player(sound: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = sound.capitalize().replace(" ", "")
	p.bus = AudioDirector.SFX_BUS
	var stream := load(KeepyMusic.SOUNDS.get(sound, "")) as AudioStreamOggVorbis
	if stream:
		stream = stream.duplicate()
		stream.loop = true
		p.stream = stream
	p.volume_db = -80.0
	return p


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.65
	reverb.damping = 0.45
	reverb.spread = 1.0
	reverb.dry = 1.0
	reverb.wet = 0.12
	reverb.predelay_msec = 40.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -15.0
	glue.ratio = 2.5
	glue.attack_us = 10000.0
	glue.release_ms = 200.0
	glue.gain = 1.5
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.5
	reverb.damping = 0.4
	reverb.dry = 1.0
	reverb.wet = 0.09
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
