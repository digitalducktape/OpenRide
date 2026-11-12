class_name CalloutBanner
extends CanvasLayer
## A game's callouts ("Rain: 130 W holds it up", "Line down! Hold 170 W for 10 s"), centred in a
## lane just under its status widget. The HUD's centre message sits on the middle of the screen,
## which is where most games put what the rider watches; a game whose hero is there shows its
## words here instead. One label with a heavy ink outline, so it reads over any backdrop, slammed
## in and faded out in the meaning colour it's given. Under the HUD (layer 10) and a child of the
## game, so it pauses and is freed with it.
##
## A game makes one with its look, its lane on the 1920x1080 canvas and its text size (a subclass
## holding those as constants keeps them in one place for its layout test), then calls
## `follow(hud, status)` once the status widget is on the HUD: the lane then stays under the status
## area (a circuit's strip pushes it down), right of a ride panel a heart strap widens, and short
## of the Music button when the two share a row.

const LAYER := 6
const OUTLINE := 14
const STATUS_GAP := 4.0  ## px between the status area's bottom and the lane
const SIDE_GAP := 8.0  ## px kept between the lane and the ride panel or the Music button
const SLAM_SCALE := 1.4
const SLAM_SEC := 0.35

var label: Label
## The lane as designed, before `fit` moves it.
var home_lane: Rect2
var text_size: int
## The text's size in a lane cut shorter than `home_lane`, so the longest callout still fits.
var narrow_size: int

var _box: CenterContainer
var _tween: Tween
var _hold := 0  ## the priority of what's showing
var _hud: Hud
var _status: Control


func _init(look: GameTheme, lane: Rect2, size: int, narrow := 0) -> void:
	layer = LAYER
	home_lane = lane
	text_size = size
	narrow_size = narrow if narrow > 0 else size
	_box = CenterContainer.new()
	_box.name = "Lane"
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.position = lane.position
	_box.size = lane.size
	add_child(_box)
	label = look.label("", size, GameTheme.INK, true)
	label.name = "Callout"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_constant_override("outline_size", OUTLINE)
	label.add_theme_color_override("font_outline_color", look.ink)
	label.custom_minimum_size = Vector2(lane.size.x, 0)
	label.visible = false
	_box.add_child(label)


## Keeps the lane clear of `hud`'s panels from now on, under `status` (the game's widget on it).
func follow(hud: Hud, status: Control) -> void:
	_hud = hud
	_status = status
	status.resized.connect(fit)
	hud.top_bar_moved.connect(fit)
	hud.ride_panel.resized.connect(fit)
	hud.music_button.visibility_changed.connect(fit)
	fit()


## Places the lane for the HUD as it is now (`follow` calls it whenever the HUD moves).
func fit() -> void:
	if not is_instance_valid(_status) or not is_instance_valid(_hud):
		return
	var lane := home_lane
	lane.position.y = lane_top(_status.get_global_rect().end.y)
	var left := maxf(lane.position.x, _hud.ride_panel.get_global_rect().end.x + SIDE_GAP)
	var right := lane.end.x
	var music := _hud.music_button.get_global_rect().grow(SIDE_GAP)
	if _hud.music_button.visible and lane.intersects(music):
		right = music.position.x
	set_lane(Rect2(left, lane.position.y, right - left, lane.size.y))


## The lane's top, a little under a status area ending at `status_bottom`.
func lane_top(status_bottom: float) -> float:
	return maxf(home_lane.position.y, status_bottom + STATUS_GAP)


## Moves the lane. The text is centred in it, at `narrow_size` in a lane shorter than designed.
func set_lane(lane: Rect2) -> void:
	label.add_theme_font_size_override("font_size", text_size if lane.size.x >= home_lane.size.x else narrow_size)
	label.custom_minimum_size.x = lane.size.x
	_box.position = lane.position
	_box.size = lane.size


## Slams `text` in, holds it for `seconds` and fades it out. A callout of lower `priority` never
## cuts in on one that's still showing (a storm's instruction outranks a district's news).
func show_callout(text: String, color: Color, seconds: float, priority := 0) -> void:
	if is_showing() and priority < _hold:
		return
	_hold = priority
	label.text = text
	label.add_theme_color_override("font_color", color)
	GameTheme.stop(label, "fade")
	label.visible = true
	label.modulate.a = 1.0
	if _tween and _tween.is_valid():
		_tween.kill()
	label.pivot_offset = Vector2(_box.size.x * 0.5, text_size * 0.6)
	GameTheme.slam(label, SLAM_SCALE, SLAM_SEC)
	_tween = label.create_tween()
	_tween.tween_interval(maxf(seconds - GameTheme.FADE_SEC, 0.4))
	_tween.tween_callback(func() -> void:
		_hold = 0
		GameTheme.fade(label, false))


func is_showing() -> bool:
	return label.visible and label.modulate.a > 0.0


## The lane on the canvas, for layout tests.
func lane_rect() -> Rect2:
	return _box.get_global_rect()
