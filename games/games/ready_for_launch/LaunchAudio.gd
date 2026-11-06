extends RefCounted
## Ready for Launch's own sounds (#82), registered with AudioDirector by the game scene.
##
## Rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/ready_for_launch.py, in the music's
## key), named `rfl_*` because AudioDirector keeps one sound per name across every game. One-shots
## go through `AudioDirector.play_sfx`. rfl_hiss (the fuel line) and rfl_engine are seamless loops
## on the game's own players (`loop_player`), because a one-shot voice can't be pitched or faded
## while it plays. The countdown "voice" is tones only (rfl_count, pitched per second): no recorded
## speech. The music is LaunchMusic's. Bus effects for this game only: a big open reverb.

const LaunchMusic := preload("res://games/ready_for_launch/LaunchMusic.gd")
const LOOPS := ["rfl_hiss", "rfl_engine"]

static var _registered := false


static func register() -> void:
	if _registered:
		return
	_registered = true
	for sound in LaunchMusic.SOUNDS:
		if sound in LOOPS:
			continue
		var rendered := load(LaunchMusic.SOUNDS[sound]) as AudioStream
		if rendered:
			AudioDirector.register_sound(sound, rendered)


## A player on the SFX bus for one of the loops, silent until the game raises it.
static func loop_player(sound: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = sound.capitalize().replace(" ", "")
	p.bus = AudioDirector.SFX_BUS
	var stream := load(LaunchMusic.SOUNDS.get(sound, "")) as AudioStreamOggVorbis
	if stream:
		stream = stream.duplicate()
		stream.loop = true
		p.stream = stream
	p.volume_db = -80.0
	return p


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.75
	reverb.damping = 0.4
	reverb.spread = 1.0
	reverb.dry = 1.0
	reverb.wet = 0.1
	reverb.predelay_msec = 30.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -15.0
	glue.ratio = 2.5
	glue.attack_us = 10000.0
	glue.release_ms = 200.0
	glue.gain = 1.5
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.6
	reverb.damping = 0.4
	reverb.dry = 1.0
	reverb.wet = 0.1
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
