extends RefCounted
## Watt Lane's sounds (#78), registered with AudioDirector by the game scene.
##
## Rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/watt_lane.py, in F minor):
## jump_chime (a jump announced), count_tick (3, 2, 1), lane_shift (the jump), caught, missed,
## off_buzz (left the lane) and streak_up. The music is "Night Current" (WattLaneMusic), synthwave
## at 104 bpm. The hum is the bike's: a seamless one-second loop rendered here, played on the SFX
## bus by the scene, warmer and louder in the lane and thin out of it (the issue's "hum that
## brightens in-lane"). Bus effects for this game only: a long night-road reverb on the music.

const WattLaneMusic := preload("res://games/watt_lane/WattLaneMusic.gd")

const HUM_RATE := 22050
const HUM_HZ := 87.0  ## near F2, the key; whole cycles in a second, so the loop is seamless

static var _registered := false
static var _hums := {}


static func register() -> void:
	if _registered:
		return
	_registered = true
	for sound in WattLaneMusic.SOUNDS:
		var rendered := load(WattLaneMusic.SOUNDS[sound]) as AudioStream
		if rendered:
			AudioDirector.register_sound(sound, rendered)


## The hum loop: `bright` adds the saw's upper harmonics and a fifth (in the lane); without it,
## a soft sine pair (out of the lane). Rendered once, 16-bit, looping forward.
static func hum(bright: bool) -> AudioStreamWAV:
	if _hums.has(bright):
		return _hums[bright]
	var data := PackedByteArray()
	data.resize(HUM_RATE * 2)
	var harmonics := 9 if bright else 2
	for i in HUM_RATE:
		var t := float(i) / HUM_RATE
		var v := 0.0
		for h in range(1, harmonics + 1):
			v += sin(TAU * HUM_HZ * h * t) / float(h) * (0.6 if h > 1 else 1.0)
		if bright:
			v += 0.25 * sin(TAU * HUM_HZ * 3.0 * t + 0.4 * sin(TAU * 2.0 * t))  # a slow shimmer
		data.encode_s16(i * 2, clampi(roundi(v * 0.28 * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = HUM_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = HUM_RATE
	_hums[bright] = wav
	return wav


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.7
	reverb.damping = 0.4
	reverb.spread = 1.0
	reverb.dry = 1.0
	reverb.wet = 0.14
	reverb.predelay_msec = 40.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -14.0
	glue.ratio = 2.5
	glue.attack_us = 15000.0
	glue.release_ms = 220.0
	glue.gain = 1.0
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.45
	reverb.damping = 0.5
	reverb.dry = 1.0
	reverb.wet = 0.12
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
