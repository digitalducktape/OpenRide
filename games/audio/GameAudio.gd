class_name GameAudio
extends RefCounted
## What every game's `*Audio.gd` does the same way: registering its rendered effects with
## AudioDirector, building a looping player for a sound it fades itself, and putting its bus
## effects on.
##
## AudioDirector keeps one stream per sound name across every game, and two games may use the
## same name (`count_tick`, `streak_up`, `crowd_swell`). So a game registers its sounds every time
## its scene is built (`_ready`), never once per process: the game on screen always owns its names.
## The streams stay cached while AudioDirector holds them, so registering again is a dictionary
## write per sound.


## Registers `sounds` (name -> res:// path of a rendered stream) with AudioDirector, without the
## names in `skip` (the loops a game plays on its own players).
static func register(sounds: Dictionary, skip: Array = []) -> void:
	for sound: String in sounds:
		if sound in skip:
			continue
		var rendered := load(sounds[sound]) as AudioStream
		if rendered:
			AudioDirector.register_sound(sound, rendered)


## A silent player on the SFX bus looping the stream at `path`, named after `sound`. The game adds
## it to its scene (so it pauses and is freed with it), plays it on start and moves its volume.
## A one-shot voice can't be pitched or faded while it plays; this can.
static func loop_player(sound: String, path: String, silent_db := -80.0) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = sound.capitalize().replace(" ", "")
	p.bus = AudioDirector.SFX_BUS
	var stream := (load(path) as AudioStream) if not path.is_empty() else null
	if stream is AudioStreamOggVorbis and not (stream as AudioStreamOggVorbis).loop:
		stream = stream.duplicate()
		(stream as AudioStreamOggVorbis).loop = true
	p.stream = stream
	p.volume_db = silent_db
	return p


## The game's own effects on the music and SFX buses, and the shared master chain (GameMix).
## AudioDirector takes them off again when the segment ends.
static func apply_mix(music_effects: Array[AudioEffect], sfx_effects: Array[AudioEffect]) -> void:
	AudioDirector.set_bus_effects(AudioDirector.MUSIC_BUS, music_effects)
	AudioDirector.set_bus_effects(AudioDirector.SFX_BUS, sfx_effects)
	AudioDirector.set_bus_effects(AudioDirector.MASTER_BUS, GameMix.master_effects())
