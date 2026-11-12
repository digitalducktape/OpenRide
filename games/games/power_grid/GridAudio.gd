extends RefCounted
## Power Grid's own sounds (#81), registered with AudioDirector by the game scene, and the rules for
## when they play (so the scene only reports what happened).
##
## Rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/power_grid.py, in the music's key of
## A-flat), named `grid_*` because AudioDirector keeps one sound per name across every game. The
## dynamo's hum and the storm's rain are seamless loops on the game's own two players, because a
## one-shot voice can't be pitched or faded while it plays. The music is "Evening Current" (GridMusic):
## the bed always, the harmony while the rider meets demand, the lead with the whole town lit.
## Bus effects for this game only: an open evening reverb and a glue compressor on the music.

const GridMusic := preload("res://games/power_grid/GridMusic.gd")

const MUSIC_STYLE := {
	"name": "evening_current",
	"stem_files": GridMusic.STEM_FILES,
	"loop_from": GridMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
const MUSIC_BPM := GridMusic.BPM
const LOOPS := ["grid_hum", "grid_rain"]
const HUM_DB := Vector2(-30.0, -15.0)  ## the hum at no supply, and at full
const HUM_PITCH := Vector2(0.72, 1.12)
const RAIN_DB := -15.0
const CRACKLE_GAP := 1.1  ## s between crackles while a district dims
const SILENT_DB := -60.0

var _hum: AudioStreamPlayer
var _rain: AudioStreamPlayer
var _hum_level := 0.0
var _rain_level := 0.0
var _crackle_left := 0.0


static func register() -> void:
	GameAudio.register(GridMusic.SOUNDS, LOOPS)


static func start_music() -> void:
	AudioDirector.play_music(MUSIC_STYLE, MUSIC_BPM)
	AudioDirector.set_intensity(0.6)
	GameAudio.apply_mix(music_effects(), sfx_effects())


## Gives the two loops their players, under `holder` (so they're freed with the scene).
func attach(holder: Node) -> void:
	_hum = _loop_player("grid_hum")
	_rain = _loop_player("grid_rain")
	holder.add_child(_hum)
	holder.add_child(_rain)


static func _loop_player(sound: String) -> AudioStreamPlayer:
	return GameAudio.loop_player(sound, GridMusic.SOUNDS.get(sound, ""))


func start() -> void:
	_hum.play()
	_rain.play()


func set_paused(paused: bool) -> void:
	_hum.stream_paused = paused
	_rain.stream_paused = paused


## The music's intensity for the moment: the bed alone while short, the harmony while demand is
## met, the lead while the whole online town is lit: the tune is the reward.
static func intensity(logic: GridLogic) -> float:
	if not logic.meeting:
		return 0.3
	return 1.0 if logic.lit() >= logic.online else 0.7


## Every gameplay frame: the hum follows the supply; the rain follows the storm; a dimming district
## crackles.
func step(delta: float, logic: GridLogic) -> void:
	var share := clampf(logic.supply / maxf(logic.hi, 1.0), 0.0, 1.2) / 1.2
	if not logic.pedalling:
		share *= 0.5
	_hum_level = move_toward(_hum_level, share, delta * 0.8)
	_hum.volume_db = lerpf(HUM_DB.x, HUM_DB.y, sqrt(_hum_level))
	_hum.pitch_scale = lerpf(HUM_PITCH.x, HUM_PITCH.y, _hum_level)
	var raining := logic.storm != GridLogic.Storm.CALM
	_rain_level = move_toward(_rain_level, 1.0 if raining else 0.0, delta / 1.5)
	_rain.volume_db = lerpf(SILENT_DB, RAIN_DB, sqrt(_rain_level))
	if logic.dim > 0.0:
		_crackle_left -= delta
		if _crackle_left <= 0.0:
			_crackle_left = CRACKLE_GAP
			AudioDirector.play_sfx("grid_crackle", 1.0)
	else:
		_crackle_left = 0.0


## The logic's events.
func on_event(event: Dictionary) -> void:
	match event.type:
		"district_on":
			AudioDirector.play_sfx("grid_on_%d" % event.index, -1.0)
			GameMix.duck_for_moment(0.9)
		"relit":
			AudioDirector.play_sfx("grid_relit", -3.0)
			GameMix.duck_for_moment(0.6)
		"district_out":
			AudioDirector.play_sfx("grid_out", -2.0)
			GameMix.duck_for_moment(1.0)
		"full_town":
			AudioDirector.play_sfx("grid_full_town", -2.0)
			AudioDirector.play_sfx("grid_firework", -6.0)
			GameMix.duck_for_sting(2.0)
		"evening":
			AudioDirector.play_sfx("grid_bell", -3.0)
			GameMix.duck_for_moment(1.5)
		"storm_warn":
			AudioDirector.play_sfx("grid_thunder", 1.0)
			GameMix.duck_for_moment(2.5)
		"strike":
			AudioDirector.play_sfx("grid_strike", 0.0)
			GameMix.duck_for_sting(1.6)
		"restored":
			AudioDirector.play_sfx("grid_restored", -1.0)
			GameMix.duck_for_sting(1.6)
		"crew_fixed":
			AudioDirector.play_sfx("grid_crew_fixed", -5.0)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.6
	reverb.damping = 0.55
	reverb.spread = 1.0
	reverb.dry = 1.0
	reverb.wet = 0.12
	reverb.predelay_msec = 35.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -15.0
	glue.ratio = 2.5
	glue.attack_us = 12000.0
	glue.release_ms = 220.0
	glue.gain = 1.5
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.55
	reverb.damping = 0.45
	reverb.dry = 1.0
	reverb.wet = 0.1
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
