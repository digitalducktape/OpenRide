extends RefCounted
## Balloon Pump's own sounds (#76), registered with AudioDirector by the game scene, and the
## rules for when they play (so the scene only reports what happened).
##
## Rendered effects (`music/sfx/*.ogg`, games/tools/music/songs/balloon_pump.py, in the music's
## key): pump_chuff (one a pedal stroke, pitched up as the balloon fills), pump_squeak (the rubber
## stretching, every so often while it takes air), pump_tie (the pop and twang of a tie-off),
## pump_hiss (a leak), pump_gold, pump_heat_start, pump_won, pump_lost and pump_tick (a Race's last
## seconds). The music is "Midnight Carousel" (PumpMusic): the bed always, the harmony while the
## balloon takes air, the lead once the rider is well over the push line.
## Bus effects for this game only: a small open-air reverb and a glue compressor on the music.

const PumpMusic := preload("res://games/balloon_pump/PumpMusic.gd")

const MUSIC_STYLE := {
	"name": "midnight_carousel",
	"stem_files": PumpMusic.STEM_FILES,
	"loop_from": PumpMusic.LOOP_FROM,
	"stem_gates": {"harmony": 0.5, "lead": 0.85},
}
const MUSIC_BPM := PumpMusic.BPM
const SQUEAK_GAP := Vector2(0.7, 1.4)  ## seconds between squeaks: slow when empty, quick near full
const HISS_GAP := 0.5
const TICK_FROM := 5  ## a Race heat ticks each of its last seconds from here

var _stroke := 0.0  ## 0-1 through the current pedal stroke
var _squeak_left := 0.6
var _hiss_left := 0.0
var _last_tick := -1


static func register() -> void:
	GameAudio.register(PumpMusic.SOUNDS)


static func start_music() -> void:
	AudioDirector.play_music(MUSIC_STYLE, MUSIC_BPM)
	AudioDirector.set_intensity(0.3)
	GameAudio.apply_mix(music_effects(), sfx_effects())


## The music's intensity for the moment: the bed alone while resting or leaking, the harmony
## while the balloon takes air, the lead while the valve is wide open (the rider is over the push
## line: the tune is the reward, as Safe Cracker's plays while the rider is steady).
static func intensity(logic: PumpLogic) -> float:
	if logic.phase == PumpLogic.Phase.BREAK or logic.phase == PumpLogic.Phase.OVER:
		return 0.3
	if logic.phase != PumpLogic.Phase.FILL:
		return 0.7
	if logic.leaking or logic.open < 0.3:
		return 0.3
	return 1.0 if logic.open > 0.9 else 0.7


## Every gameplay frame: the pump's chuffs, the squeaks, the hiss and the last-seconds ticks.
func step(delta: float, logic: PumpLogic, cadence: float) -> void:
	_stroke += delta * cadence / 60.0
	if _stroke >= 1.0:
		_stroke = fmod(_stroke, 1.0)
		if cadence > 20.0:
			AudioDirector.play_sfx("pump_chuff", -11.0 + 4.0 * logic.open, 0.9 + 0.3 * logic.fill)
	if logic.phase == PumpLogic.Phase.FILL and logic.open > 0.5:
		_squeak_left -= delta
		if _squeak_left <= 0.0:
			_squeak_left = lerpf(SQUEAK_GAP.y, SQUEAK_GAP.x, logic.fill)
			AudioDirector.play_sfx("pump_squeak", -14.0 + 6.0 * logic.fill, 0.85 + 0.5 * logic.fill)
	if logic.phase == PumpLogic.Phase.FILL and logic.leaking and logic.fill > 0.05:
		_hiss_left -= delta
		if _hiss_left <= 0.0:
			_hiss_left = HISS_GAP
			AudioDirector.play_sfx("pump_hiss", -9.0)
	if logic.mode == "race" and logic.phase != PumpLogic.Phase.BREAK and logic.heat_left <= TICK_FROM:
		var sec := ceili(logic.heat_left)
		if sec != _last_tick and sec > 0:
			_last_tick = sec
			AudioDirector.play_sfx("pump_tick", -6.0, 1.0 if sec > 1 else 1.3)


## The logic's events: a tie-off, a gold, a heat's start and end.
func on_event(event: Dictionary) -> void:
	match event.type:
		"filled":
			# The tie-off is the game's payoff: full level, the music dipped under it (the first mix
			# check had it only 3.5 dB over the music in its best band).
			AudioDirector.play_sfx("pump_tie", -1.0, 1.12 if event.kind == "small" else (0.9 if event.kind == "large" else 1.0))
			GameMix.duck_for_moment(0.6)
			if event.gold:
				AudioDirector.play_sfx("pump_gold", -1.0)
		"heat_start":
			_last_tick = -1
			if int(event.target) > 0:
				AudioDirector.play_sfx("pump_heat_start", -3.0)
				GameMix.duck_for_moment(1.5)
		"heat_end":
			if event.won == false:
				AudioDirector.play_sfx("pump_lost", -4.0)
			else:
				AudioDirector.play_sfx("pump_won", -4.0)
			GameMix.duck_for_sting(2.0)


static func music_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.35
	reverb.damping = 0.6
	reverb.spread = 0.8
	reverb.dry = 1.0
	reverb.wet = 0.1
	reverb.predelay_msec = 20.0
	var glue := AudioEffectCompressor.new()
	glue.threshold = -14.0
	glue.ratio = 2.5
	glue.attack_us = 8000.0
	glue.release_ms = 180.0
	glue.gain = 1.5
	return [glue, reverb]


static func sfx_effects() -> Array[AudioEffect]:
	var reverb := AudioEffectReverb.new()
	reverb.room_size = 0.3
	reverb.damping = 0.6
	reverb.dry = 1.0
	reverb.wet = 0.08
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -0.5
	return [reverb, limiter]
