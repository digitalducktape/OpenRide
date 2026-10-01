extends Control
## The style gallery (#36): a desktop audition scene for game authors. Open
## `res://audio/gallery/StyleGallery.tscn` and press F6.
##
## - Pick a style, tempo (the cadence a game would pass), tempo scale, seed and bar count.
##   Render runs MusicGen on a WorkerThreadPool thread (no disk cache) and shows the time.
## - Intensity gates the stems at the style's suggested gates (what AudioDirector does with a
##   game's `stem_gates`); the checkboxes mute stems by hand.
## - "Change tempo at next phrase" renders the new tempo while the old loop plays, then
##   switches on the next 4-bar boundary: the behaviour AudioDirector needs for tempo
##   changes (docs/GAMES.md, "Tempo changes on a phrase boundary").
## - The buttons at the bottom play every SfxSynth preset.
##
## It plays through its own players, not AudioDirector, so it runs without a session.

const Dsp := preload("res://audio/Dsp.gd")
const SWITCH_FADE_SEC := 0.03  ## a tiny crossfade at the switch, to hide frame jitter

var _style_menu := OptionButton.new()
var _tempo := HSlider.new()
var _scale := HSlider.new()
var _seed := SpinBox.new()
var _bars := OptionButton.new()
var _intensity := HSlider.new()
var _mutes := {}  # stem -> CheckBox
var _status := Label.new()
var _description := Label.new()
var _value_labels := {}  # slider -> Label

var _players: Array[AudioStreamPlayer] = []
var _current := 0
var _stems: Array = []  # stem names in the current stream's order
var _gates := {}
var _task := -1
var _task_result := {}
var _task_started := 0
var _task_request := {}
var _switch_at_phrase := false
var _pending := {}  # a finished render waiting for the phrase boundary
var _fade := 1.0
var _playing_bars := 16  # bars in the stream that is playing
var _last_since := 0.0  # seconds into the phrase at the previous frame
## The last phrase-boundary switch: {since_boundary (s, where the new loop started), phrase_before}.
var last_switch := {}
var _sfx := AudioStreamPlayer.new()


func _ready() -> void:
	Dsp.warm()
	MusicGen.preload_styles()
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	add_child(_sfx)
	_build_ui()
	_on_style_selected(0)


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.1, 0.11, 0.13)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	margin.add_child(col)

	var title := Label.new()
	title.text = "MusicGen style gallery"
	title.add_theme_font_size_override("font_size", 32)
	col.add_child(title)

	for style_name in MusicGen.style_names():
		_style_menu.add_item(style_name)
	_style_menu.item_selected.connect(_on_style_selected)
	_row(col, "Style", _style_menu)
	_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_description)

	_slider(_tempo, 40.0, 180.0, 1.0, "%.0f bpm")
	_row(col, "Tempo (cadence)", _tempo)
	_slider(_scale, 0.5, 2.0, 0.25, "× %.2f")
	_row(col, "Tempo scale", _scale)
	_seed.min_value = 0
	_seed.max_value = 99999
	_seed.value = 1
	_row(col, "Seed", _seed)
	for bars in [4, 8, 16]:
		_bars.add_item("%d bars" % bars, bars)
	_bars.select(2)
	_row(col, "Length", _bars)
	_slider(_intensity, 0.0, 1.0, 0.01, "%.2f")
	_intensity.value = 1.0
	_intensity.value_changed.connect(func(_v): _apply_levels())
	_row(col, "Intensity", _intensity)

	var mutes := HBoxContainer.new()
	for stem in MusicGen.STEMS:
		var box := CheckBox.new()
		box.text = stem
		box.button_pressed = true
		box.toggled.connect(func(_on): _apply_levels())
		_mutes[stem] = box
		mutes.add_child(box)
	_row(col, "Stems", mutes)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	_button(buttons, "Render and play", func(): _request(false))
	_button(buttons, "Change tempo at next phrase", func(): _request(true))
	_button(buttons, "Stop", _stop)
	col.add_child(buttons)
	_status.text = "Pick a style and render."
	col.add_child(_status)

	var sfx_title := Label.new()
	sfx_title.text = "Effects (SfxSynth presets)"
	col.add_child(sfx_title)
	var flow := HFlowContainer.new()
	for sound in SfxSynth.names():
		_button(flow, sound, func():
			_sfx.stream = SfxSynth.stream(sound)
			_sfx.play())
	col.add_child(flow)


func _row(parent: Control, label: String, control: Control) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 220
	row.add_child(l)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	if _value_labels.has(control):
		row.add_child(_value_labels[control])
	parent.add_child(row)


func _slider(slider: HSlider, lo: float, hi: float, step: float, fmt: String) -> void:
	slider.min_value = lo
	slider.max_value = hi
	slider.step = step
	var value := Label.new()
	value.custom_minimum_size.x = 110
	_value_labels[slider] = value
	slider.value_changed.connect(func(v): value.text = fmt % v)


func _button(parent: Control, text: String, action: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	parent.add_child(b)


func _on_style_selected(index: int) -> void:
	var style := MusicGen.style(_style_menu.get_item_text(index))
	_description.text = style.description
	_tempo.value = roundf((style.tempo_min + style.tempo_max) / 2.0)
	_scale.value = style.tempo_scale
	_tempo.value_changed.emit(_tempo.value)
	_scale.value_changed.emit(_scale.value)
	_intensity.value_changed.emit(_intensity.value)


func _request(at_phrase: bool) -> void:
	if _task != -1:
		_status.text = "Still rendering…"
		return
	var style_name := _style_menu.get_item_text(_style_menu.selected)
	_task_request = {"style": {"name": style_name, "tempo_scale": _scale.value, "bars": _bars.get_selected_id()},
		"tempo_bpm": _tempo.value, "seed": int(_seed.value)}
	_switch_at_phrase = at_phrase and _players[_current].playing
	var request := _task_request.duplicate(true)
	MusicGen.cache_enabled = false
	_task_started = Time.get_ticks_msec()
	_task = WorkerThreadPool.add_task(func(): _task_result = MusicGen.generate(request), false, "Gallery render")
	_status.text = "Rendering %s at %.0f bpm…" % [style_name, _tempo.value * _scale.value]


func _process(delta: float) -> void:
	if _task != -1 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		var ms := Time.get_ticks_msec() - _task_started
		_status.text = "Rendered in %d ms (%s bars, %.0f bpm)%s" % [ms, _task_request.style.bars,
			_task_request.tempo_bpm * _task_request.style.tempo_scale,
			"; switching at the next phrase" if _switch_at_phrase else ""]
		if _switch_at_phrase:
			_pending = _task_result
			_last_since = _seconds_into_phrase(_players[_current])
		else:
			_play(_task_result, 0.0)
	if not _pending.is_empty():
		# In the first frame past a phrase boundary, start the new loop from the time already
		# gone since the boundary, so its beat grid starts exactly on the boundary.
		# (The position jitters by a few ms between mixes, so only a wrap counts.)
		var since := _seconds_into_phrase(_players[_current])
		if since < _last_since - _phrase_sec(_players[_current]) / 2.0:
			last_switch = {"since_boundary": since, "phrase_before": _last_since}
			_play(_pending, SWITCH_FADE_SEC, since)
			_pending = {}
		else:
			_last_since = since
	if _fade < 1.0:
		_fade = minf(1.0, _fade + delta / SWITCH_FADE_SEC)
		_players[_current].volume_db = linear_to_db(maxf(_fade, 0.0001))
		_players[1 - _current].volume_db = linear_to_db(maxf(1.0 - _fade, 0.0001))
		if _fade >= 1.0:
			_players[1 - _current].stop()


## Seconds since the last phrase boundary of what `player` plays. A phrase is 4 bars, so a
## stem of `bars` bars has bars / 4 phrases; the length comes from the stream itself.
func _seconds_into_phrase(player: AudioStreamPlayer) -> float:
	return fposmod(player.get_playback_position() + AudioServer.get_time_since_last_mix(), _phrase_sec(player))


func _phrase_sec(player: AudioStreamPlayer) -> float:
	var stream := player.stream as AudioStreamSynchronized
	var stem: AudioStreamWAV = stream.get_sync_stream(0)
	return stem.get_length() / maxi(1, _playing_bars / MusicGen.PHRASE_BARS)


func _play(stems: Dictionary, fade_sec: float, from_sec := 0.0) -> void:
	if stems.is_empty():
		_status.text = "The render failed."
		return
	var sync := AudioStreamSynchronized.new()
	_stems = MusicGen.STEMS.duplicate()
	sync.stream_count = _stems.size()
	for i in _stems.size():
		sync.set_sync_stream(i, stems[_stems[i]])
	var style := MusicGen.style(_task_request.style.name)
	_gates = style.suggested_gates
	_playing_bars = int(_task_request.style.bars)
	var next := 1 - _current if fade_sec > 0.0 else _current
	if fade_sec <= 0.0:
		_players[1 - _current].stop()
	_players[next].stream = sync
	_players[next].volume_db = linear_to_db(0.0001) if fade_sec > 0.0 else 0.0
	_players[next].play(from_sec)
	_current = next
	_fade = 0.0 if fade_sec > 0.0 else 1.0
	_apply_levels()


func _apply_levels() -> void:
	var sync := _players[_current].stream as AudioStreamSynchronized
	if sync == null:
		return
	for i in _stems.size():
		var stem: String = _stems[i]
		var on: bool = _mutes[stem].button_pressed and _intensity.value >= float(_gates.get(stem, 0.0))
		sync.set_sync_stream_volume(i, 0.0 if on else -80.0)


func _stop() -> void:
	_pending = {}
	for p in _players:
		p.stop()
	_status.text = "Stopped."


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
