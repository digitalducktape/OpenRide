class_name WattLaneBackdrop
extends Node2D
## The abstract field behind Watt Lane's lane (#78; ART_BIBLE.md). Everything that doesn't move is
## baked ONCE into a texture at the window's size (`shaders/wl_field_bake.gdshader`: the gradient,
## the washes, the horizon of light, the ribbons, the guides, the vignette), and the dot grid,
## bokeh and the lane's streaks into a 512 px repeating tile (`wl_tile_bake.gdshader`). Per frame
## one opaque rect (`wl_field.gdshader`) reads the two, drifts the tile and adds the beat lines.
## The tablet is fill-bound: this all ran per pixel per frame at first, at 31 fps.

const FIELD_SHADER := preload("res://games/watt_lane/shaders/wl_field.gdshader")
const STATIC_SHADER := preload("res://games/watt_lane/shaders/wl_field_bake.gdshader")
const TILE_SHADER := preload("res://games/watt_lane/shaders/wl_tile_bake.gdshader")
const TILE := 512
const TILE_SPEED := 0.4  ## of the lane's speed

var field: ColorRect
var bakes := 0  ## renders of the static layers, for tests

var _mat: ShaderMaterial
var _static_mat: ShaderMaterial
var _static_view: SubViewport
var _static_rect: ColorRect
var _tile_view: SubViewport
var _beat_px := 80.0


func _init() -> void:
	var noise := WorldLook.noise_texture()
	_static_mat = ShaderMaterial.new()
	_static_mat.shader = STATIC_SHADER
	_static_mat.set_shader_parameter("noise_tex", noise)
	_static_mat.set_shader_parameter("guide_top", WattLaneTrack.GUIDE_TOP)
	_static_mat.set_shader_parameter("guide_gap", WattLaneTrack.GUIDE_GAP)
	_static_view = _bake_view("StaticBake")
	_static_rect = _bake_rect(_static_view, _static_mat)
	var tile_mat := ShaderMaterial.new()
	tile_mat.shader = TILE_SHADER
	tile_mat.set_shader_parameter("noise_tex", noise)
	_tile_view = _bake_view("TileBake")
	_tile_view.size = Vector2i(TILE, TILE)
	_bake_rect(_tile_view, tile_mat).size = Vector2(TILE, TILE)
	field = ColorRect.new()
	field.name = "Field"
	field.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = FIELD_SHADER
	_mat.set_shader_parameter("static_tex", _static_view.get_texture())
	_mat.set_shader_parameter("tile_tex", _tile_view.get_texture())
	field.material = _mat
	add_child(field)


func _bake_view(view_name: String) -> SubViewport:
	var v := SubViewport.new()
	v.name = view_name
	v.disable_3d = true
	v.transparent_bg = false
	v.gui_disable_input = true
	v.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	v.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(v)
	return v


func _bake_rect(view: SubViewport, mat: Material) -> ColorRect:
	var r := ColorRect.new()
	r.material = mat
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(r)
	return r


func _ready() -> void:
	_fit()
	Stage.changed.connect(_fit)


func _exit_tree() -> void:
	if Stage.changed.is_connected(_fit):
		Stage.changed.disconnect(_fit)


## The window changed: size the field and bake the static layers again.
func _fit() -> void:
	Stage.bleed(field)
	var r := Stage.bleed_rect()
	var px := Stage.view_size(1.0)
	_static_view.size = px
	_static_view.size_2d_override = Vector2i(r.size)
	_static_view.size_2d_override_stretch = true
	_static_rect.size = r.size
	_static_mat.set_shader_parameter("origin", r.position)
	_static_mat.set_shader_parameter("rect_size", r.size)
	_static_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1
	_mat.set_shader_parameter("rect_size", r.size)


## The repeating tile, for the lane's streaks too.
func tile_texture() -> Texture2D:
	return _tile_view.get_texture()


## The beat's spacing on screen (px between beat lines).
func set_beat_px(px: float) -> void:
	_beat_px = px
	_mat.set_shader_parameter("beat_px", px)


## One frame: the lane's scroll (px) and the beat's flare (0-1). The scrolls wrap here, in double
## precision, so the shader's numbers stay small.
func update_view(scroll: float, beat: float) -> void:
	_mat.set_shader_parameter("tile_scroll", fposmod(scroll * TILE_SPEED, float(TILE)))
	_mat.set_shader_parameter("bar_scroll", fposmod(scroll, _beat_px * 4.0))
	_mat.set_shader_parameter("beat", beat)
