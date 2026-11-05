extends SceneTree
## Renders a game's audio offline to WAV files, for listening and analysis without speakers
## (#55, the audio pass). Headless Godot has no audio output, so this mixes every player itself,
## the way the AudioServer would: each AudioStreamPlayer's stream decoded natively
## (AudioStreamPlayback.mix_audio) at its pitch_scale and volume_db, through its bus's volume
## (the music duck included), frame by frame. Bus effects (reverb, compressors, the Master
## limiter) are not applied: the analysis applies the limiter itself.
##   $GODOT_BIN --headless --fixed-fps 60 --path games -s res://tests/render_game_audio.gd -- \
##       --game=dodge_ball --out=/abs/dir [--seconds=90]
##   ... -- --reel=dodge_ball --out=/abs/dir     # every sound the game uses, one after another
## A scripted rider plays (see _ride): cadence, resistance and lean move through each game's
## states, so its music layers and effects all come up. Writes 22.05 kHz mono 32-bit float WAVs
## (floats keep any overs visible): `mix.wav`, `music.wav`, `sfx.wav` (effects and cues), and
## `events.json`: each sound with its time, bus, volume and pitch, and per 0.1 s the intensity,
## the music duck and which stems are up.

const SR := 22050
const FPS := 60
const REELS := {
	"dodge_ball": ["launch_whoosh", "dodge_tick", "catch_chime", "miss_whiff", "fumble_thud", "ball_bounce",
		"streak_chime", "shield_break", "shield_zap", "shield_ready", "hit_thud", "hit_body", "game_over"],
	"tug_of_war": ["rope_creak", "surge_drumroll", "crowd_swell", "win_sting", "lose_sting", "splash"],
	"safe_cracker": ["proximity_tick", "tumbler_click", "soft_alarm", "vault_open", "door_creak"],
	"cadence_karaoke": ["beat_tick", "streak_up", "band_exit", "ease_off_chime"],
	"watt_lane": ["jump_chime", "count_tick", "lane_shift", "caught", "missed", "off_buzz", "streak_up"],
	"demo": ["dodge", "hit"],
	"cues": ["countdown", "go", "segment_end", "pause", "resume", "summary"],
}
const GAME_SCRIPTS := {
	"dodge_ball": "res://games/dodge_ball/DodgeAudio.gd",
	"tug_of_war": "res://games/tug_of_war/TugAudio.gd",
	"safe_cracker": "res://games/safe_cracker/SafeAudio.gd",
	"cadence_karaoke": "res://games/cadence_karaoke/CadenceAudio.gd",
	"watt_lane": "res://games/watt_lane/WattLaneAudio.gd",
}

var out_dir := ""
var _director: Node
var _input: Node
var _voices := []  # {player, playback, kind}
var _known := {}  # player instance id -> {playing, stream id}
var _music := PackedFloat32Array()
var _sfx := PackedFloat32Array()
var _events := []
var _states := []
var _t := 0.0
var _knob := 30.0
var _paced := 0
var _voice_pos := {}  # playback id -> seconds mixed (plus where it started)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	await process_frame
	var game_id := ""
	var reel := ""
	var seconds := 90.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.get_slice("=", 1)
		elif a.begins_with("--game="):
			game_id = a.get_slice("=", 1)
		elif a.begins_with("--reel="):
			reel = a.get_slice("=", 1)
		elif a.begins_with("--seconds="):
			seconds = float(a.get_slice("=", 1))
	if out_dir.is_empty() or (game_id.is_empty() and reel.is_empty()):
		push_error("render_game_audio: --out and --game or --reel are required")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(out_dir)
	_director = root.get_node("AudioDirector")
	_input = root.get_node("InputBus")
	_director.sound_played.connect(_on_sound)
	_director.music_started.connect(_on_music)
	_director.tempo_swapped.connect(func(_k, _since):
		_events.append({"t": snappedf(_t, 0.001), "sound": "(tempo swap)", "bus": "Music", "db": 0.0, "pitch": 1.0,
			"len": 0.0, "from": snappedf(_director._decks[_director._deck].get_playback_position(), 0.001)}))
	if not reel.is_empty():
		await _reel(reel)
	else:
		await _play(game_id, seconds)
	_write()
	quit()


# --- A reel: each sound alone, 0.25 s apart after it ends ---

func _reel(game_id: String) -> void:
	if GAME_SCRIPTS.has(game_id):
		load(GAME_SCRIPTS[game_id]).register()
	elif game_id == "demo":  # the demo registers its sounds itself, when it starts
		var sounds: Dictionary = load("res://games/demo/DemoMusic.gd").get_script_constant_map().SOUNDS
		for sound in sounds:
			_director.register_sound(sound, load(sounds[sound]))
	await process_frame
	for sound in REELS.get(game_id, []):
		_director.play_sfx(sound) if game_id != "cues" else _director.play_cue(sound)
		var length := 0.6
		var p: AudioStreamPlayer = _voices[-1].player if not _voices.is_empty() else null
		if p and p.stream:
			length = maxf(0.2, p.stream.get_length())
		for f in int((length + 0.35) * FPS):
			_mix_frame()


# --- A game played by a scripted rider ---

func _play(game_id: String, seconds: float) -> void:
	var params := {}
	match game_id:
		"dodge_ball":
			params = {"target_watts": 200.0}
		"tug_of_war":
			params = {"ftp": 200.0, "bot_watts": 180.0, "surge_watts": 240.0}
		"safe_cracker":
			params = {"power_cap_watts": 160.0}
		"cadence_karaoke":
			params = {"ftp_watts": 250.0, "pace": 70}
		"watt_lane":
			params = {"ftp_watts": 250.0}
	var session: Node = root.get_node("Session")
	var director: Node = session.director
	session._local.start({"kind": "just_ride", "plan_id": "render", "difficulty": "standard", "total_sec": int(seconds),
		"segments": [{"game_id": game_id, "role": "free", "duration_sec": int(seconds), "end_mode": "timer", "params": params}]})
	var frames := int((seconds + 12.0) * FPS)
	for f in frames:
		await process_frame
		# A music render runs on a worker thread in real time while these frames run faster:
		# hold the game until it's done, as the intro card would on the bike.
		while _director._render_task != -1 and not WorkerThreadPool.is_task_completed(_director._render_task):
			OS.delay_msec(2)
		_ride(game_id, director)
		_mix_frame()
		if director.phase_name() in ["SUMMARY", "IDLE"] and _t > seconds:
			break
	print("RENDER %s %.1f s, %d sounds" % [game_id, _t, _events.size()])


## The scripted rider: per game, cadence (rpm), resistance (%) and lean move through the game's
## states (InputBus's keyboard simulator turns them into power).
func _ride(game_id: String, director: Node) -> void:
	var t := _t
	var cad := 85.0
	var res := 35.0
	var lean := 0.0
	match game_id:
		"dodge_ball":
			# Brisk, a power push (the bonus) from 30-45 s, below the floor at 60-70 s.
			cad = 88.0
			res = 60.0 if t > 30.0 and t < 45.0 else 35.0
			if t > 60.0 and t < 70.0:
				cad = 50.0
			lean = sin(t * 1.3) * 0.9
			if director.game and "logic" in director.game and director.game.logic:
				director.game.logic.target_watts = 200.0  # the power target, for the bonus
		"tug_of_war":
			cad = 85.0
			res = 30.0 + 30.0 * (0.5 + 0.5 * sin(t * 0.25))
		"safe_cracker":
			# A rider who reads the dial: the knob eases toward each number, overshoots a little
			# and settles; one hard burst (50-56 s) trips the alarm.
			cad = 70.0
			var game: Node = director.game
			if game and "logic" in game and game.logic and director.phase_name() == "PLAYING":
				var want := float(game.logic.target()) + 3.0 * sin(t * 0.9)
				_knob = move_toward(_knob, want, 12.0 / FPS)
			res = _knob
			if t > 50.0 and t < 56.0:
				cad = 120.0
		"cadence_karaoke":
			# On the target, drifting out of the band (25-31 s) and back; then the rider asks for
			# +10 rpm (at 40 s) and -20 rpm (at 70 s), and the music's tempo follows on a phrase
			# boundary.
			var game: Node = director.game
			cad = 60.0
			if game and "logic" in game and game.logic:
				cad = float(game.logic.target())
				if _paced < 1 and t > 40.0:
					game.adjust_pace(2)
					print("RENDER pace +10 at %.1f s: pending %s" % [t, game.logic.pending_adjust])
					_paced = 1
				elif _paced < 2 and t > 70.0:
					game.adjust_pace(-4)
					print("RENDER pace -20 at %.1f s: pending %s" % [t, game.logic.pending_adjust])
					_paced = 2
			if t > 25.0 and t < 31.0:
				cad += 12.0
		"watt_lane":
			# Follows the lane a moment ahead (the 3 s window lags), off it from 30 to 36 s.
			var game: Node = director.game
			res = 35.0
			if game and "logic" in game and game.logic:
				var want: float = game.logic.course.visual_centre_at(game.logic.time + 1.2)
				if t > 30.0 and t < 36.0:
					want -= 50.0
				cad = want / (0.3 + res * 0.045)
		"demo":
			cad = 80.0 if t < 40.0 or t > 60.0 else 55.0
			lean = sin(t * 1.1) * 0.8
	cad += sin(t * 2.3) * 1.5
	_input._sim_cadence = cad
	_input._sim_resistance = res
	_input._sim_lean_x = lean
	if int(t * 10.0) != int((t - 1.0 / FPS) * 10.0):
		var stems := {}
		for s in ["drums", "bass", "harmony", "lead", "bed", "lift"]:
			var level: float = _director.stem_level(s)
			if level >= 0.0:
				stems[s] = snappedf(level, 0.01)
		_states.append({"t": snappedf(t, 0.01), "intensity": snappedf(_director.intensity, 0.01),
			"duck": snappedf(_director.duck_db, 0.1), "stems": stems, "phase": director.phase_name()})


# --- The mixer ---

func _on_sound(sound: String, bus: String) -> void:
	var player: AudioStreamPlayer
	if bus == _director.CUES_BUS:
		player = _director._cue_players[(_director._next_cue - 1 + _director._cue_players.size()) % _director._cue_players.size()]
	else:
		player = _director._sfx_players[(_director._next_sfx - 1 + _director._sfx_players.size()) % _director._sfx_players.size()]
	_events.append({"t": snappedf(_t, 0.001), "sound": sound, "bus": bus, "db": snappedf(player.volume_db, 0.1),
		"pitch": snappedf(player.pitch_scale, 0.001), "len": snappedf(player.stream.get_length(), 0.001)})
	_start_voice(player, 0.0, "sfx")


func _on_music(key: String) -> void:
	var player: AudioStreamPlayer = _director._decks[_director._deck]
	print("RENDER music at %.2f s: tempo %s" % [_t, JSON.parse_string(key).get("tempo_bpm", 0)])
	# A tempo swap starts the new loop part-way in (on the boundary, maybe at the same phrase).
	_start_voice(player, player.get_playback_position(), "music")


func _start_voice(player: AudioStreamPlayer, from: float, kind: String) -> void:
	for v in _voices:
		if v.player == player:
			_voices.erase(v)
			break
	if player.stream == null:
		return
	var pb := player.stream.instantiate_playback()
	pb.start(from)
	_voices.append({"player": player, "playback": pb, "kind": kind, "from": from})
	_known[player.get_instance_id()] = {"playing": true, "stream": player.stream.get_instance_id()}


## Players the director doesn't own (a game's own loops): started when they start playing.
func _scan_players() -> void:
	var owned := []
	owned.append_array(_director._decks)
	owned.append_array(_director._sfx_players)
	owned.append_array(_director._cue_players)
	for p in root.find_children("*", "AudioStreamPlayer", true, false):
		if p in owned:
			continue
		var player := p as AudioStreamPlayer
		var id := player.get_instance_id()
		var was: Dictionary = _known.get(id, {"playing": false, "stream": 0})
		var sid := player.stream.get_instance_id() if player.stream else 0
		if player.playing and (not was.playing or was.stream != sid):
			_start_voice(player, 0.0, "sfx" if player.bus != _director.MUSIC_BUS else "music")
		_known[id] = {"playing": player.playing, "stream": sid}


func _mix_frame() -> void:
	_scan_players()
	# The real players' positions run on the wall clock here (headless), not on these frames:
	# while a tempo change waits for a phrase boundary, keep the playing deck where this mix is.
	if not _director._pending_key.is_empty():
		var deck: AudioStreamPlayer = _director._decks[_director._deck]
		for v in _voices:
			if v.player == deck:
				deck.seek(_voice_pos[v.playback.get_instance_id()] if _voice_pos.has(v.playback.get_instance_id()) else 0.0)
	var rate := AudioServer.get_mix_rate()
	var n_out := SR / FPS
	var n_mix := int(round(rate / FPS))
	var music := PackedFloat32Array()
	music.resize(n_out)
	var sfx := PackedFloat32Array()
	sfx.resize(n_out)
	var master_db := AudioServer.get_bus_volume_db(0)
	for v in _voices.duplicate():
		var player: AudioStreamPlayer = v.player
		if not is_instance_valid(player):
			_voices.erase(v)
			continue
		if player.stream_paused:
			continue
		if not player.playing:
			_voices.erase(v)
			continue
		var bus := AudioServer.get_bus_index(player.bus)
		var gain := db_to_linear(player.volume_db + AudioServer.get_bus_volume_db(bus) + master_db)
		if AudioServer.is_bus_mute(bus):
			gain = 0.0
		var buf: PackedVector2Array = v.playback.mix_audio(player.pitch_scale, n_mix)
		var pid: int = v.playback.get_instance_id()
		_voice_pos[pid] = _voice_pos.get(pid, v.get("from", 0.0)) + float(n_mix) / rate * player.pitch_scale
		var target := music if v.kind == "music" else sfx
		var step := float(buf.size()) / n_out
		for i in n_out:
			var j := int(i * step)
			if j >= buf.size():
				break
			var a: Vector2 = buf[j]
			var b: Vector2 = buf[mini(j + 1, buf.size() - 1)]
			target[i] += (a.x + a.y + b.x + b.y) * 0.25 * gain
	_music.append_array(music)
	_sfx.append_array(sfx)
	_t += 1.0 / FPS


func _write() -> void:
	var mix := PackedFloat32Array()
	mix.resize(_music.size())
	for i in _music.size():
		mix[i] = _music[i] + _sfx[i]
	write_wav(out_dir + "/music.wav", _music)
	write_wav(out_dir + "/sfx.wav", _sfx)
	write_wav(out_dir + "/mix.wav", mix)
	var f := FileAccess.open(out_dir + "/events.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"sr": SR, "seconds": _t, "events": _events, "states": _states}))
	f.close()
	print("RENDER wrote %s (%.1f s)" % [out_dir, _t])


static func write_wav(path: String, x: PackedFloat32Array) -> void:
	var data := x.to_byte_array()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + data.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(3)
	f.store_16(1)
	f.store_32(SR)
	f.store_32(SR * 4)
	f.store_16(4)
	f.store_16(32)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(data.size())
	f.store_buffer(data)
	f.close()
