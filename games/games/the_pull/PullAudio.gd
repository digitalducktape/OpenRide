class_name PullAudio
extends Node
## The Pull's sounds (#79). The one-shots are rendered effects (`music/sfx/*.ogg`,
## games/tools/music/songs/the_pull.py, in the theme's key), registered with AudioDirector and
## played through it: pull_horn, stall_horn, dig_in, board_pass, best_pass, full_pull and
## crowd_swell. Three loops the game plays on its own players on the SFX bus, their level and
## pitch following the pull (looping is set in their .import files):
##   engine_drone  a pedal-powered motor's rumble, pitched by the rider's watts
##   chain_strain  the chain under load, louder as the sled bogs down
##   box_scrape    the weight box grinding along the pan, as loud as the sled is fast
## The music is "Heavy Haul" (PullMusic). Bus effects for this game: a big outdoor reverb.

const PullMusic := preload("res://games/the_pull/PullMusic.gd")
const SILENT_DB := -60.0
const LOOPS := ["engine_drone", "chain_strain", "box_scrape"]

static var _registered := false

var players := {}  ## loop name -> AudioStreamPlayer


static func register() -> void:
	if _registered:
		return
	_registered = true
	for sound in PullMusic.SOUNDS:
		if sound in LOOPS:
			continue
		var rendered := load(PullMusic.SOUNDS[sound]) as AudioStream
		if rendered:
			AudioDirector.register_sound(sound, rendered)


func _ready() -> void:
	for sound in LOOPS:
		var player := AudioStreamPlayer.new()
		player.name = sound
		player.bus = AudioDirector.SFX_BUS
		player.stream = load(PullMusic.SOUNDS[sound]) as AudioStream
		player.volume_db = SILENT_DB
		add_child(player)
		players[sound] = player


## Starts the loops (quiet until `follow` says otherwise).
func start_loops() -> void:
	for p: AudioStreamPlayer in players.values():
		if not p.playing:
			p.play()


func set_paused(paused: bool) -> void:
	for p: AudioStreamPlayer in players.values():
		p.stream_paused = paused


## The loops follow the pull: `power_share` (watts / FTP), `strain` 0-1, `speed_share` (speed /
## V_MAX) and whether a pull is on (between pulls the motor idles and the rest falls silent).
## Eased per frame so the 1 Hz readings don't step the sound.
func follow(delta: float, power_share: float, strain: float, speed_share: float, pulling: bool) -> void:
	var k := 1.0 - exp(-delta / 0.25)
	var engine: AudioStreamPlayer = players.engine_drone
	engine.pitch_scale = lerpf(engine.pitch_scale, lerpf(0.7, 1.6, clampf(power_share, 0.0, 1.2) / 1.2), k)
	engine.volume_db = lerpf(engine.volume_db, lerpf(-22.0, -9.0, clampf(power_share, 0.0, 1.0)) if pulling else -26.0, k)
	var chain: AudioStreamPlayer = players.chain_strain
	chain.volume_db = lerpf(chain.volume_db, lerpf(-30.0, -8.0, strain) if pulling else SILENT_DB, k)
	chain.pitch_scale = lerpf(0.9, 1.2, strain)
	var scrape: AudioStreamPlayer = players.box_scrape
	scrape.volume_db = lerpf(scrape.volume_db, lerpf(-34.0, -11.0, clampf(speed_share, 0.0, 1.0)) if pulling and speed_share > 0.02 else SILENT_DB, k)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.7
	reverb.damping = 0.4
	reverb.spread = 1.0
	reverb.dry = 1.0
	reverb.wet = 0.12
	reverb.predelay_msec = 45.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -14.0
	glue.ratio = 3.0
	glue.attack_us = 8000.0
	glue.release_ms = 200.0
	glue.gain = 2.0
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.6
	reverb.damping = 0.45
	reverb.dry = 1.0
	reverb.wet = 0.1
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
