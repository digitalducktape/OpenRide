class_name SettingsScreen
extends HubScreen
## The app's game settings (spec §8.3), owned by Kotlin (GamesSettings) and changed through
## `update_setting`: camera games On/Off, game music On/Off, and the music and effects volumes
## as Steppers in 10% steps with a level bar (not sliders: a poor target while
## pedalling). A volume plays at once on its bus (`volume_preview`); hub_state confirms it.
## Game music on still stays off by itself while the rider's own music app has a track
## (AudioDirector); effects always play (rider, 2026-10-27).

signal volume_preview(key: String, value: float)

const BODY_TOP := 200.0
const LABEL_WIDTH := 640.0
const ROW_GAP := 36
const VOLUMES := [0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0]

var camera: Segmented
var game_music: Segmented
var music_volume: Stepper
var sfx_volume: Stepper
var _bars := {}


func build() -> void:
	top_bar("Settings")
	var col := VBoxContainer.new()
	col.name = "Body"
	col.position = Vector2(HubTheme.MARGIN + 40, BODY_TOP)
	col.size = Vector2(HubTheme.W - 2 * HubTheme.MARGIN - 80, HubTheme.H - BODY_TOP - 40)
	col.add_theme_constant_override("separation", ROW_GAP)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(col)
	var s: Dictionary = state.settings
	camera = Segmented.new(["on", "off"], ["On", "Off"], "on" if bool(s.camera_games) else "off")
	camera.name = "CameraGames"
	camera.changed.connect(func(v: String): setting.emit("camera_games", v == "on"))
	col.add_child(_row("Camera games", "Lean or stand to play. The camera only runs in those games.", camera))
	game_music = Segmented.new(["on", "off"], ["On", "Off"], "on" if bool(s.get("game_music", true)) else "off")
	game_music.name = "GameMusic"
	game_music.changed.connect(func(v: String): setting.emit("game_music", v == "on"))
	col.add_child(_row("Game music", "Your own music plays instead while it's on.", game_music))
	music_volume = _volume("music_volume", float(s.music_volume))
	col.add_child(_row("Music volume", "", _with_bar(music_volume, "music_volume")))
	sfx_volume = _volume("sfx_volume", float(s.sfx_volume))
	col.add_child(_row("Effects volume", "", _with_bar(sfx_volume, "sfx_volume")))


func _row(title: String, caption: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var words := VBoxContainer.new()
	words.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	row.add_child(words)
	words.add_child(HubTheme.label(title, HudTheme.MEDIUM))
	if not caption.is_empty():
		var c := HubTheme.label(caption, HudTheme.SMALL, GameTheme.MUTED)
		c.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		c.custom_minimum_size = Vector2(LABEL_WIDTH, 0)
		words.add_child(c)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return row


## A volume as a stepper over 0-100% (the nearest 10% to the stored value).
func _volume(key: String, current: float) -> Stepper:
	var nearest := snappedf(clampf(current, 0.0, 1.0), 0.1)
	var values: Array = VOLUMES.duplicate()
	var shown := 0.0
	for v in values:
		if absf(v - nearest) < absf(shown - nearest):
			shown = v
	var st := Stepper.new(values, shown, func(v): return "%d%%" % roundi(float(v) * 100.0), 200.0)
	st.name = key.to_pascal_case()
	st.changed.connect(func(v):
		_set_bar(key, float(v))
		volume_preview.emit(key, float(v))
		setting.emit(key, float(v)))
	return st


func _with_bar(st: Stepper, key: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	row.add_child(st)
	var track := PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = Color(HubTheme.look().ink, 0.8)
	ts.set_corner_radius_all(14)
	ts.border_color = Color(1, 1, 1, 0.25)
	ts.set_border_width_all(3)
	track.add_theme_stylebox_override("panel", ts)
	track.custom_minimum_size = Vector2(420, 44)
	track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(track)
	var fill := Panel.new()
	var fs := StyleBoxFlat.new()
	fs.bg_color = HubTheme.look().accent
	fs.set_corner_radius_all(11)
	fill.add_theme_stylebox_override("panel", fs)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var holder := Control.new()  # the track's container would stretch the fill; place it by hand
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(holder)
	holder.add_child(fill)
	_bars[key] = fill
	_set_bar(key, float(st.value()))
	return row


func _set_bar(key: String, v: float) -> void:
	var fill: Panel = _bars.get(key)
	if fill:
		fill.size = Vector2(maxf(0.0, (420.0 - 6.0) * v), 38)
		fill.position = Vector2(3, 3)
		fill.visible = v > 0.0


func refresh(hub_state: Dictionary) -> void:
	state = hub_state
	var s: Dictionary = state.settings
	camera.show_value("on" if bool(s.camera_games) else "off")
	game_music.show_value("on" if bool(s.get("game_music", true)) else "off")
