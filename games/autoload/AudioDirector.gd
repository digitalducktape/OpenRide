extends Node
## Game audio (epic #31, "Audio"; interface in docs/GAMES.md, "Audio"): the Master, Music, SFX
## and Cues buses, music stems with crossfades between segments, effects, and cues that duck
## the music.
##
## Nothing here makes sound by itself. Generators register with it (#36: `SfxSynth`,
## `MusicGen`, from `res://audio/`) through `register_sound`, `register_sound_factory` and
## `register_music_generator`; until they do, every call plays silence. Games only ask for
## sounds by name and music by style:
##
##   AudioDirector.play_music({"name": "drive", "stem_gates": {"lead": 0.6}}, 90.0, seed)
##   AudioDirector.set_intensity(power / target)   # stems fade in at their gate
##   AudioDirector.play_sfx("whoosh")
##
## Session drives the rest: begin_segment honours `segment.audio` (music off when the rider
## brings their own; the volumes), cues play for the countdown and the segment's end, and
## pause pauses the music.

signal sound_played(sound: String, bus: String)  ## an effect or cue started
signal music_started(key: String)  ## a rendered music request started playing

const MUSIC_BUS := "Music"
const SFX_BUS := "SFX"
const CUES_BUS := "Cues"
const CROSSFADE_SEC := 2.0
const STEM_FADE_SEC := 1.5
const DUCK_DB := -10.0  ## music under a cue
const DUCK_ATTACK_SEC := 0.08
const DUCK_RELEASE_SEC := 0.6
const SILENT_DB := -80.0
const SFX_VOICES := 8
const CUE_VOICES := 2
const MUSIC_CACHE_SIZE := 4
## Optional hook for #36: a script with `func register(director: Node) -> void`, instantiated
## once at startup, so generated sounds register without an autoload of their own.
const HOOK_SCRIPT := "res://audio/Cues.gd"

## Cue names Session plays (docs/GAMES.md lists them for #36).
const CUE_COUNTDOWN := "countdown"  ## each of the intro card's 3, 2, 1
const CUE_GO := "go"  ## gameplay starts
const CUE_SEGMENT_END := "segment_end"  ## a segment's result is in
const CUE_PAUSE := "pause"
const CUE_RESUME := "resume"
const CUE_SUMMARY := "summary"  ## the session summary appears

var music_enabled := true  ## `segment.audio.music`
var music_volume := 0.8  ## `segment.audio.music_volume`, 0-1
var sfx_volume := 1.0  ## `segment.audio.sfx_volume`, 0-1 (effects and cues)
var intensity := 1.0  ## 0-1, set by the game; gates stems in
var duck_db := 0.0  ## the Music bus's current duck

var _sounds := {}  # name -> AudioStream
var _sound_factories: Array[Callable] = []
var _music_generator := Callable()
var _missing := {}  # names already reported as silent

var _decks: Array[AudioStreamPlayer] = []  # two players, crossfading
var _deck := 0  # the current deck
var _deck_keys := ["", ""]
var _deck_stems: Array = [[], []]  # stem names in stream order, per deck
var _deck_gates: Array = [{}, {}]  # stem name -> intensity gate, per deck
var _deck_levels: Array = [[], []]  # each stem's current linear level, per deck
var _fade := 1.0  # crossfade progress to the current deck
var _fade_sec := CROSSFADE_SEC

var _requested := {}  # the latest play_music request, kept while music is off
var _requested_key := ""
var _music_cache := {}  # key -> stems
var _cache_order: Array[String] = []
var _render_task := -1
var _render_key := ""
var _render_result := {}
var _render_mutex := Mutex.new()

var _sfx_players: Array[AudioStreamPlayer] = []
var _cue_players: Array[AudioStreamPlayer] = []
var _next_sfx := 0
var _next_cue := 0
var _cue_left := 0.0  # seconds of cue still sounding: the duck holds meanwhile
var _paused := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for bus in [MUSIC_BUS, SFX_BUS, CUES_BUS]:
		_ensure_bus(bus)
	for i in 2:
		_decks.append(_player(MUSIC_BUS))
	for i in SFX_VOICES:
		_sfx_players.append(_player(SFX_BUS))
	for i in CUE_VOICES:
		_cue_players.append(_player(CUES_BUS))
	_apply_bus_volumes()
	if ResourceLoader.exists(HOOK_SCRIPT):
		var hook = load(HOOK_SCRIPT).new()
		if hook.has_method("register"):
			hook.register(self)
			print("OPENRIDE_GAMES audio hook %s registered" % HOOK_SCRIPT)


# --- Registration (for the generators, #36) ---

## A named effect or cue, e.g. register_sound("whoosh", wav). Replaces any earlier one.
func register_sound(sound: String, stream: AudioStream) -> void:
	_sounds[sound] = stream
	_missing.erase(sound)


## `factory(name: String) -> AudioStream` (or null), asked on the main thread the first time an
## unregistered name plays; its answer is cached. Lets a generator render presets lazily.
func register_sound_factory(factory: Callable) -> void:
	_sound_factories.append(factory)


## `generator(request: Dictionary) -> Dictionary` of stem name → looping AudioStream, all the
## same length. `request` is {style, tempo_bpm, seed}. It runs on a WorkerThreadPool thread,
## so it must not touch the scene tree. Replaces any earlier generator.
func register_music_generator(generator: Callable) -> void:
	_music_generator = generator
	_missing.erase("music")


func has_music_generator() -> bool:
	return _music_generator.is_valid()


# --- For games ---

## Plays a named effect on the SFX bus. Returns false (silence) when nothing provides it.
func play_sfx(sound: String, volume_db := 0.0, pitch := 1.0) -> bool:
	var player := _sfx_players[_next_sfx]
	_next_sfx = (_next_sfx + 1) % _sfx_players.size()
	return _play(player, sound, volume_db, pitch)


## Plays a named cue on the Cues bus and ducks the music under it.
func play_cue(sound: String) -> bool:
	var player := _cue_players[_next_cue]
	_next_cue = (_next_cue + 1) % _cue_players.size()
	var played := _play(player, sound, 0.0, 1.0)
	if played:
		_cue_left = maxf(_cue_left, player.stream.get_length() if player.stream.get_length() > 0.0 else 0.5)
	return played


## Asks for music: `style` is the game's (passed to the generator as is; `stem_gates` maps a
## stem name to the intensity at which it plays, 0 by default), at `tempo_bpm` (a segment's
## target cadence: one beat per pedal stroke), seeded. It renders off the main thread (the
## intro card covers it) and crossfades in; the old music plays until then. Asking for what
## is already playing changes nothing. With music off, the request is kept but not played.
func play_music(style: Dictionary, tempo_bpm: float, music_seed := 0) -> void:
	_requested = {"style": style, "tempo_bpm": tempo_bpm, "seed": music_seed}
	_requested_key = music_key(_requested)
	if music_enabled:
		_want(_requested_key)


## Fades the music out.
func stop_music(fade_sec := CROSSFADE_SEC) -> void:
	if _deck_keys[_deck].is_empty():
		return
	_crossfade_to_silence(fade_sec)


## 0-1: stems whose gate is at or below it play; the rest fade out.
func set_intensity(value: float) -> void:
	intensity = clampf(value, 0.0, 1.0)


func current_music_key() -> String:
	return _deck_keys[_deck]


func is_music_playing() -> bool:
	return not _deck_keys[_deck].is_empty() and _decks[_deck].playing


## The same request always gives the same key (style keys are sorted).
static func music_key(request: Dictionary) -> String:
	return JSON.stringify(request)


# --- For Session ---

func begin_session() -> void:
	_requested = {}
	_requested_key = ""
	intensity = 1.0
	set_paused(false)


## Applies the segment's `audio` settings. The music keeps playing across the intro card until
## the game asks for its own, which then crossfades in.
func begin_segment(segment: Dictionary) -> void:
	var audio: Dictionary = segment.get("audio", {})
	music_enabled = bool(audio.get("music", true))
	music_volume = clampf(float(audio.get("music_volume", 0.8)), 0.0, 1.0)
	sfx_volume = clampf(float(audio.get("sfx_volume", 1.0)), 0.0, 1.0)
	intensity = 1.0
	_apply_bus_volumes()
	if not music_enabled:
		stop_music()


func set_paused(paused: bool) -> void:
	_paused = paused
	for player in _decks + _sfx_players:
		player.stream_paused = paused


func end_session() -> void:
	_requested = {}
	_requested_key = ""
	stop_music()


# --- Internals ---

func _process(delta: float) -> void:
	_collect_render()
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta / maxf(_fade_sec, 0.01))
	var old := 1 - _deck
	_decks[_deck].volume_db = _gain_db(sin(_fade * PI / 2))
	_decks[old].volume_db = _gain_db(cos(_fade * PI / 2))
	if _fade >= 1.0 and not _deck_keys[old].is_empty():
		_decks[old].stop()
		_deck_keys[old] = ""
	_update_stems(delta)
	_cue_left = maxf(0.0, _cue_left - delta)
	var target := DUCK_DB if _cue_left > 0.0 else 0.0
	var rate := absf(DUCK_DB) / (DUCK_ATTACK_SEC if target < duck_db else DUCK_RELEASE_SEC)
	duck_db = move_toward(duck_db, target, rate * delta)
	_apply_bus_volumes()


func _want(key: String) -> void:
	if key == _deck_keys[_deck]:
		return
	if _music_cache.has(key):
		_start(key, _music_cache[key])
		return
	if not _music_generator.is_valid():
		_note_silent("music")
		return
	if _render_task != -1:
		return  # _collect_render picks up the newest request when this one is done
	_render_key = key
	var request := _requested.duplicate(true)
	_render_task = WorkerThreadPool.add_task(_render.bind(request), false, "AudioDirector music")


func _render(request: Dictionary) -> void:
	var stems = _music_generator.call(request)
	_render_mutex.lock()
	_render_result = stems if stems is Dictionary else {}
	_render_mutex.unlock()


func _collect_render() -> void:
	if _render_task == -1 or not WorkerThreadPool.is_task_completed(_render_task):
		return
	WorkerThreadPool.wait_for_task_completion(_render_task)
	_render_task = -1
	_render_mutex.lock()
	var stems: Dictionary = _render_result
	_render_result = {}
	_render_mutex.unlock()
	if stems.is_empty():
		push_warning("AudioDirector: the music generator returned no stems")
	else:
		_music_cache[_render_key] = stems
		_cache_order.append(_render_key)
		while _cache_order.size() > MUSIC_CACHE_SIZE:
			_music_cache.erase(_cache_order.pop_front())
	if music_enabled and not _requested_key.is_empty():
		_want(_requested_key)


func _start(key: String, stems: Dictionary) -> void:
	var names: Array = stems.keys()
	names.sort()
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = names.size()
	var gates: Dictionary = _requested.get("style", {}).get("stem_gates", {}) if key == _requested_key else {}
	var levels := []
	for i in names.size():
		sync.set_sync_stream(i, stems[names[i]])
		var level := 1.0 if intensity >= float(gates.get(names[i], 0.0)) else 0.0
		levels.append(level)
		sync.set_sync_stream_volume(i, _gain_db(level))
	_deck = 1 - _deck
	var player := _decks[_deck]
	player.stream = sync
	player.volume_db = SILENT_DB
	player.play()
	player.stream_paused = _paused
	_deck_keys[_deck] = key
	_deck_stems[_deck] = names
	_deck_gates[_deck] = gates
	_deck_levels[_deck] = levels
	_fade_sec = CROSSFADE_SEC
	_fade = 0.0
	music_started.emit(key)


func _crossfade_to_silence(fade_sec: float) -> void:
	_deck = 1 - _deck
	_decks[_deck].stop()
	_deck_keys[_deck] = ""
	_deck_stems[_deck] = []
	_deck_levels[_deck] = []
	_fade_sec = fade_sec
	_fade = 0.0 if fade_sec > 0.0 else 1.0


func _update_stems(delta: float) -> void:
	var sync := _decks[_deck].stream as AudioStreamSynchronized
	if sync == null or _deck_keys[_deck].is_empty():
		return
	var names: Array = _deck_stems[_deck]
	var levels: Array = _deck_levels[_deck]
	var gates: Dictionary = _deck_gates[_deck]
	for i in names.size():
		var target := 1.0 if intensity >= float(gates.get(names[i], 0.0)) else 0.0
		var level := move_toward(levels[i], target, delta / STEM_FADE_SEC)
		if level != levels[i]:
			levels[i] = level
			sync.set_sync_stream_volume(i, _gain_db(level))


## A stem's current level (0-1) in the playing music, or -1 when it isn't playing.
func stem_level(stem: String) -> float:
	var i: int = _deck_stems[_deck].find(stem)
	return _deck_levels[_deck][i] if i >= 0 else -1.0


func _play(player: AudioStreamPlayer, sound: String, volume_db: float, pitch: float) -> bool:
	var stream := _stream_for(sound)
	if stream == null:
		return false
	player.stream = stream
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()
	sound_played.emit(sound, player.bus)
	return true


func _stream_for(sound: String) -> AudioStream:
	if _sounds.has(sound):
		return _sounds[sound]
	for factory in _sound_factories:
		var stream = factory.call(sound)
		if stream is AudioStream:
			_sounds[sound] = stream
			return stream
	_note_silent(sound)
	return null


func _note_silent(what: String) -> void:
	if not _missing.has(what):
		_missing[what] = true
		print("OPENRIDE_GAMES audio: nothing provides '%s' yet; silent" % what)


func _apply_bus_volumes() -> void:
	_set_bus_db(MUSIC_BUS, _gain_db(music_volume) + duck_db)
	_set_bus_db(SFX_BUS, _gain_db(sfx_volume))
	_set_bus_db(CUES_BUS, _gain_db(sfx_volume))


func _set_bus_db(bus: String, db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), db)


func _ensure_bus(bus: String) -> void:
	if AudioServer.get_bus_index(bus) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus)
	AudioServer.set_bus_send(index, "Master")


func _player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	add_child(player)
	return player


static func _gain_db(linear: float) -> float:
	return SILENT_DB if linear <= 0.0001 else maxf(SILENT_DB, linear_to_db(linear))
