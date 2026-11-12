extends GdUnitTestSuite
## GameAudio: AudioDirector keeps one stream per sound name, and two games may use the same name
## (`streak_up`: Cadence Karaoke and Watt Lane). The game whose scene was built last owns it.

const CadenceAudio := preload("res://games/cadence_karaoke/CadenceAudio.gd")
const CadenceMusic := preload("res://games/cadence_karaoke/CadenceMusic.gd")
const WattLaneAudio := preload("res://games/watt_lane/WattLaneAudio.gd")
const WattLaneMusic := preload("res://games/watt_lane/WattLaneMusic.gd")


func test_two_games_do_share_a_sound_name() -> void:
	assert_bool(CadenceMusic.SOUNDS.has("streak_up") and WattLaneMusic.SOUNDS.has("streak_up")).is_true()
	assert_str(CadenceMusic.SOUNDS.streak_up).is_not_equal(WattLaneMusic.SOUNDS.streak_up)


func test_the_game_built_last_owns_a_shared_sound_name() -> void:
	CadenceAudio.register()
	var cadence: AudioStream = AudioDirector._sounds["streak_up"]
	assert_str(cadence.resource_path).is_equal(CadenceMusic.SOUNDS.streak_up)
	WattLaneAudio.register()
	assert_str(AudioDirector._sounds["streak_up"].resource_path).is_equal(WattLaneMusic.SOUNDS.streak_up)
	# Back to the first game (a circuit plays it twice): it gets its own sound back.
	CadenceAudio.register()
	assert_str(AudioDirector._sounds["streak_up"].resource_path).is_equal(CadenceMusic.SOUNDS.streak_up)


func test_a_games_own_loops_are_not_registered_as_one_shots() -> void:
	AudioDirector._sounds.erase("only_a_loop")
	GameAudio.register({"only_a_loop": WattLaneMusic.SOUNDS.streak_up}, ["only_a_loop"])
	assert_bool(AudioDirector._sounds.has("only_a_loop")).is_false()


func test_a_loop_player_is_silent_on_the_sfx_bus_and_loops() -> void:
	var p: AudioStreamPlayer = auto_free(GameAudio.loop_player("fan_hum", WattLaneMusic.SOUNDS.streak_up))
	assert_str(p.bus).is_equal(AudioDirector.SFX_BUS)
	assert_float(p.volume_db).is_equal(-80.0)
	assert_bool((p.stream as AudioStreamOggVorbis).loop).is_true()
	# The registered one-shot is not the looping copy.
	assert_bool((load(WattLaneMusic.SOUNDS.streak_up) as AudioStreamOggVorbis).loop).is_false()
