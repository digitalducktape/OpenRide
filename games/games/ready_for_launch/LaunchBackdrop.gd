class_name LaunchBackdrop
extends Node2D
## The place behind the pad (#82; ART_BIBLE.md §6): its `SafeMesh` batch and a soft vignette, baked
## into a texture when the place changes (a SubViewport rendered once, as Safe Cracker's
## `SafeBackdrop`), shown as one opaque sprite, with the place's slow ambient life as children that
## never redraw:
##   coast    the sun's glitter on the sea (a shader on one rect), gulls gliding
##   desert   slow dust (LaunchPad), nothing here
##   polar    the aurora's curtains (a shader on one rect, additive)

const SEA_RECT := Rect2(-160, 682, 2240, 106)
const AURORA_RECT := Rect2(-160, 300, 2240, 370)
const GULLS := 3

var place_index := 0
var bakes := 0  ## renders made, for tests
var _bake: SubViewport
var _view: Sprite2D
var sea: ColorRect
var aurora: ColorRect
var gulls: Array[Node2D] = []
var _t := 0.0


func _init() -> void:
	name = "Backdrop"
	_bake = SubViewport.new()
	_bake.name = "SceneBake"
	_bake.disable_3d = true
	_bake.transparent_bg = false
	_bake.gui_disable_input = true
	_bake.size_2d_override = Vector2i(LaunchPlaces.WIDE)
	_bake.size_2d_override_stretch = true
	_bake.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_bake)
	var painted: Node2D = SafeDial.Layer.new()
	painted.name = "Scene"
	painted.position = Vector2(LaunchPlaces.BLEED, 0)
	painted.paint = func(ci: CanvasItem) -> void: scene_mesh(place_index).draw_on(ci)
	_bake.add_child(painted)
	_bake.add_child(vignette())
	_view = Sprite2D.new()
	_view.name = "Scene"
	_view.centered = false
	_view.position = Vector2(-LaunchPlaces.BLEED, 0)
	_view.texture = _bake.get_texture()
	_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_view)
	sea = _shader_rect("Sea", SEA_RECT, preload("res://games/ready_for_launch/shaders/rfl_sea.gdshader"))
	aurora = _shader_rect("Aurora", AURORA_RECT, preload("res://games/ready_for_launch/shaders/rfl_aurora.gdshader"))
	for i in GULLS:
		var g: Node2D = SafeDial.Layer.new()
		g.name = "Gull%d" % i
		g.paint = _paint_gull
		add_child(g)
		gulls.append(g)


func _shader_rect(rect_name: String, r: Rect2, shader: Shader) -> ColorRect:
	var c := ColorRect.new()
	c.name = rect_name
	c.position = r.position
	c.size = r.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	c.material = mat
	add_child(c)
	return c


func set_place(index: int) -> void:
	place_index = index
	var p := LaunchPlaces.place(index)
	var id: String = p.id
	sea.visible = id == "coast"
	aurora.visible = id == "polar"
	for g in gulls:
		g.visible = id == "coast"
	var sea_mat := sea.material as ShaderMaterial
	sea_mat.set_shader_parameter("sun_x", ((p.sun as Vector2).x - SEA_RECT.position.x) / SEA_RECT.size.x)
	sea_mat.set_shader_parameter("sun_col", p.sun_col)
	rebake()


func _enter_tree() -> void:
	if not get_tree().root.size_changed.is_connected(rebake):
		get_tree().root.size_changed.connect(rebake)
	rebake()


func _exit_tree() -> void:
	if get_tree().root.size_changed.is_connected(rebake):
		get_tree().root.size_changed.disconnect(rebake)


## Renders the bake once at the size the canvas is shown on screen.
func rebake() -> void:
	if not is_inside_tree():
		return
	var win := Vector2(get_tree().root.size)
	var s := clampf(minf(win.x / LaunchPlaces.SIZE.x, win.y / LaunchPlaces.SIZE.y), 0.25, 1.0)
	var px := Vector2i((LaunchPlaces.WIDE * s).ceil())
	if _bake.size != px:
		_bake.size = px
	_view.scale = LaunchPlaces.WIDE / Vector2(px)
	_bake.get_child(0).queue_redraw()
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1


## The ambient life's motion: the gulls glide and flap.
func step(delta: float) -> void:
	_t += delta
	if gulls[0].visible:
		for i in gulls.size():
			var g := gulls[i]
			g.position.x = fposmod(200.0 + i * 700.0 + _t * (34.0 + i * 8.0), LaunchPlaces.WIDE.x) - LaunchPlaces.BLEED
			g.position.y = 520.0 + i * 46.0 + sin(_t * 0.4 + i) * 16.0
			g.scale.y = 0.75 + 0.25 * sin(_t * (3.0 + i))


## The scene's batch for a place, built once (`SafeMesh.built`).
static func scene_mesh(index: int) -> SafeMesh:
	return SafeMesh.built("rfl:place:%d" % index, func(m: SafeMesh) -> void: LaunchPlaces.build_scene(m, index))


## A soft vignette baked with the scene, so the eye goes to the rocket.
static func vignette() -> TextureRect:
	var ink := Color(0.03, 0.04, 0.1)
	var g := Gradient.new()
	g.set_color(0, Color(ink, 0.0))
	g.set_color(1, Color(ink, 0.62))
	for k in [[0.5, 0.0], [0.66, 0.08], [0.82, 0.26]]:
		g.add_point(k[0], Color(ink, k[1]))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.56)
	tex.fill_to = Vector2(1.08, 1.08)
	tex.width = 256
	tex.height = 144
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = LaunchPlaces.WIDE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A gull far off: a shallow "m" of two wings, no body and no tail (ART_BIBLE §3).
func _paint_gull(ci: CanvasItem) -> void:
	var m := SafeMesh.new()
	var col := Color(0.16, 0.16, 0.26, 0.85)
	m.line(Vector2(-22, -4), Vector2(-10, -10), 3.5, col)
	m.line(Vector2(-10, -10), Vector2(0, 0), 3.5, col)
	m.line(Vector2(0, 0), Vector2(10, -10), 3.5, col)
	m.line(Vector2(10, -10), Vector2(22, -4), 3.5, col)
	m.flush(ci)
