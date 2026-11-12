extends RefCounted
## Cadence Karaoke's own sounds (#42), registered with AudioDirector by the game scene.
##
## Rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/cadence_karaoke.py, in the
## music's key): beat_tick (the optional metronome), streak_up, band_exit and ease_off_chime.
## They replace the synth presets of the same names (`sfx/*.tres`, SfxSynth's fallback). The
## music is "Neon Lines" at the target cadence (CadenceMusic, through SongSequencer); its lead
## stem plays only while the rider is in the band, so staying on target completes the song. Bus effects for this game only: a spacious reverb and
## a gentle compressor on the music.

const SFX_DIR := "res://games/cadence_karaoke/sfx"
const CadenceMusic := preload("res://games/cadence_karaoke/CadenceMusic.gd")


static func register() -> void:
	SfxSynth.add_preset_dir(SFX_DIR)
	GameAudio.register(CadenceMusic.SOUNDS)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.5
	reverb.damping = 0.5
	reverb.spread = 0.9
	reverb.dry = 1.0
	reverb.wet = 0.16
	reverb.predelay_msec = 20.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -15.0
	glue.ratio = 2.5
	glue.attack_us = 10000.0
	glue.release_ms = 200.0
	glue.gain = 1.5
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.3
	reverb.damping = 0.5
	reverb.dry = 1.0
	reverb.wet = 0.1
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
