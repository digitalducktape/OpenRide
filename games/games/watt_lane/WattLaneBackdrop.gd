class_name WattLaneBackdrop
extends Node2D
## The abstract field behind Watt Lane's lane (#78; ART_BIBLE.md): one full-window shader rect
## (`shaders/wl_field.gdshader`) in depth layers that move at different speeds (far bokeh, a mid
## dot grid, near beat lines at the lane's speed and the watt scale's faint guides), flaring on
## the music's beat and warming a little around the lane while the rider is in it. No geometry,
## nothing redrawn: a few uniforms a frame.

const SHADER := preload("res://games/watt_lane/shaders/wl_field.gdshader")

var field: ColorRect
var _mat: ShaderMaterial
var _warmth := 0.0


func _init() -> void:
	field = ColorRect.new()
	field.name = "Field"
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise_tex", WorldLook.noise_texture())
	_mat.set_shader_parameter("guide_top", WattLaneTrack.GUIDE_TOP)
	_mat.set_shader_parameter("guide_gap", WattLaneTrack.GUIDE_GAP)
	field.material = _mat
	add_child(field)


func _ready() -> void:
	_fit()
	Stage.changed.connect(_fit)


func _exit_tree() -> void:
	if Stage.changed.is_connected(_fit):
		Stage.changed.disconnect(_fit)


func _fit() -> void:
	Stage.bleed(field)
	var r := Stage.bleed_rect()
	_mat.set_shader_parameter("origin", r.position)
	_mat.set_shader_parameter("rect_size", r.size)


## The beat's spacing on screen (px between beat lines) and which line starts a bar.
func set_beat_px(px: float) -> void:
	_mat.set_shader_parameter("beat_px", px)


## One frame: the lane's scroll (px), the beat's flare (0-1), the lane's middle near the cursor
## and whether the rider is in it.
func update_view(delta: float, scroll: float, beat: float, lane_mid: float, in_lane: bool, bar_offset := 0.0) -> void:
	_warmth = move_toward(_warmth, 1.0 if in_lane else 0.0, delta * 1.5)
	_mat.set_shader_parameter("scroll", scroll)
	_mat.set_shader_parameter("beat", beat)
	_mat.set_shader_parameter("lane_mid", lane_mid)
	_mat.set_shader_parameter("warmth", _warmth)
	_mat.set_shader_parameter("bar_offset", bar_offset)
