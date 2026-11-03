class_name KeepyBackdrop
extends Node2D
## The place behind the fan (#77, 2D; ART_BIBLE.md §6): the place's `SafeMesh` batch and a soft
## vignette, baked into a texture when the place changes (a SubViewport rendered once, as Safe
## Cracker's `SafeBackdrop`), shown as one opaque sprite, and the place's slow ambient life as
## children that never redraw:
##   every place   three cumulus clouds drifting across (moved, not redrawn)
##   meadow        butterflies flitting over the grass (CPUParticles2D)
##   seaside       the sea's glitter on the sun's path (a shader on one rect), two gulls gliding
##   rooftop       lit windows that come and go (a shader on one rect over the towers)
##   park          leaves falling (CPUParticles2D)
## A new place cross-fades over FADE_SEC: two bakes take turns, the old one's sprite fades out.

const FADE_SEC := 1.6
const CLOUDS := 3
const CLOUD_SPEED := Vector2(14.0, 24.0)  ## px a second, slowest and fastest
const SEA_RECT := Rect2(-160, 580, 2240, 200)
const WINDOWS_RECT := Rect2(-160, 566, 2240, 150)
const GULLS := 2

var place_index := 0
var bakes := 0  ## renders made, for tests
var _bake: Array[SubViewport] = []
var _view: Array[Sprite2D] = []
var _paint_index: Array[int] = [0, 0]
var _front := 0
var _fade: Tween
var clouds: Array[Node2D] = []
var sea: ColorRect
var windows: ColorRect
var butterflies: CPUParticles2D
var leaves: CPUParticles2D
var gulls: Array[Node2D] = []
var _cloud_speed: Array[float] = []
var _t := 0.0


func _init() -> void:
	for i in 2:
		var bake := SubViewport.new()
		bake.name = "SceneBake%d" % i
		bake.disable_3d = true
		bake.transparent_bg = false
		bake.gui_disable_input = true
		bake.size_2d_override = Vector2i(KeepyPlaces.WIDE)
		bake.size_2d_override_stretch = true
		bake.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(bake)
		var painted := SafeDial.Layer.new()
		painted.name = "Scene"
		painted.position = Vector2(KeepyPlaces.BLEED, 0)
		var slot := i
		painted.paint = func(ci: CanvasItem) -> void: scene_mesh(_paint_index[slot]).draw_on(ci)
		bake.add_child(painted)
		bake.add_child(vignette())
		var view := Sprite2D.new()
		view.name = "Scene%d" % i
		view.centered = false
		view.position = Vector2(-KeepyPlaces.BLEED, 0)
		view.texture = bake.get_texture()
		view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(view)
		_bake.append(bake)
		_view.append(view)
	_view[1].visible = false
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in CLOUDS:
		var c := SafeDial.Layer.new()
		c.name = "Cloud%d" % i
		var w := rng.randf_range(220.0, 340.0)
		c.paint = func(ci: CanvasItem) -> void:
			var m := SafeMesh.new()
			KeepyPlaces.cumulus(m, Vector2.ZERO, w, Color(1, 1, 1, 0.95), Color(0.82, 0.86, 0.92, 0.95))
			m.flush(ci)
		c.position = Vector2(rng.randf_range(-100.0, 2000.0), rng.randf_range(150.0, 400.0))
		add_child(c)
		clouds.append(c)
		_cloud_speed.append(rng.randf_range(CLOUD_SPEED.x, CLOUD_SPEED.y))
	sea = _shader_rect("Sea", SEA_RECT, preload("res://games/keepy_uppy/shaders/keepy_sea.gdshader"))
	windows = _shader_rect("Windows", WINDOWS_RECT, preload("res://games/keepy_uppy/shaders/keepy_windows.gdshader"))
	for i in GULLS:
		var g := SafeDial.Layer.new()
		g.name = "Gull%d" % i
		g.paint = _paint_gull
		g.position = Vector2(300 + i * 900, 230 + i * 70)
		add_child(g)
		gulls.append(g)
	butterflies = _particles("Butterflies", 10, KeepyPlaces.WIDE.x * 0.45, Vector2(960, 860), Vector2(900, 90))
	butterflies.texture = _butterfly_texture()
	butterflies.color_ramp = _ramp([Color("f5d547"), Color("f2efe6"), Color("b8a1e3")])
	butterflies.gravity = Vector2(0, -3)
	butterflies.initial_velocity_min = 12.0
	butterflies.initial_velocity_max = 30.0
	butterflies.angular_velocity_min = -40.0
	butterflies.angular_velocity_max = 40.0
	leaves = _particles("Leaves", 22, 0.0, Vector2(960, -40), Vector2(1100, 10))
	leaves.texture = _leaf_texture()
	leaves.color_ramp = _ramp([Color("d9792f"), Color("c9502c"), Color("e3a83a")])
	leaves.gravity = Vector2(10, 28)
	leaves.initial_velocity_min = 10.0
	leaves.initial_velocity_max = 30.0
	leaves.angular_velocity_min = -90.0
	leaves.angular_velocity_max = 90.0
	leaves.lifetime = 16.0
	leaves.preprocess = 16.0


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


func _particles(p_name: String, amount: int, _unused: float, at: Vector2, extents: Vector2) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = p_name
	p.amount = amount
	p.lifetime = 10.0
	p.preprocess = 10.0
	p.position = at
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = extents
	p.direction = Vector2(1, 0)
	p.spread = 180.0
	p.scale_amount_min = 0.7
	p.scale_amount_max = 1.1
	add_child(p)
	return p


static func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, Color(cols[0], 0.0))
	g.set_color(1, Color(cols[0], 0.0))
	g.add_point(0.1, Color(cols[0], 1.0))
	g.add_point(0.9, Color(cols[cols.size() - 1], 1.0))
	return g


func set_place(index: int, fade := false) -> void:
	place_index = index
	var p := KeepyPlaces.place(index)
	var id: String = p.id
	sea.visible = id == "seaside"
	windows.visible = id == "rooftop"
	for g in gulls:
		g.visible = id == "seaside"
	butterflies.visible = id == "meadow"
	butterflies.emitting = butterflies.visible
	leaves.visible = id == "park"
	leaves.emitting = leaves.visible
	var sea_mat := sea.material as ShaderMaterial
	sea_mat.set_shader_parameter("sun_x", ((p.sun as Vector2).x - SEA_RECT.position.x) / SEA_RECT.size.x)
	sea_mat.set_shader_parameter("sun_col", p.sun_col)
	# Clouds take the place's light: whiter at noon, warm at dusk.
	var tint: Color = Color.WHITE.lerp(p.sun_col, 0.35)
	if id == "rooftop":
		tint = Color(1.0, 0.72, 0.7)
	for c in clouds:
		c.modulate = tint
	if fade and is_inside_tree():
		var back := 1 - _front
		_paint_index[back] = index
		_render(back)
		_view[back].visible = true
		_view[back].modulate.a = 0.0
		move_child(_view[back], _view[_front].get_index() + 1)
		if _fade:
			_fade.kill()
		var old := _front
		_front = back
		_fade = create_tween()
		_fade.tween_property(_view[back], "modulate:a", 1.0, FADE_SEC).set_trans(Tween.TRANS_SINE)
		_fade.tween_callback(func(): _view[old].visible = false)
	else:
		_paint_index[_front] = index
		_view[_front].visible = true
		_view[_front].modulate.a = 1.0
		_view[1 - _front].visible = false
		rebake()


func _enter_tree() -> void:
	if not get_tree().root.size_changed.is_connected(rebake):
		get_tree().root.size_changed.connect(rebake)
	rebake()


func _exit_tree() -> void:
	if get_tree().root.size_changed.is_connected(rebake):
		get_tree().root.size_changed.disconnect(rebake)


## Renders the front bake once at the size the canvas is shown on screen.
func rebake() -> void:
	if is_inside_tree():
		_render(_front)


func _render(slot: int) -> void:
	if not is_inside_tree():
		return
	var win := Vector2(get_tree().root.size)
	var s := clampf(minf(win.x / KeepyPlaces.SIZE.x, win.y / KeepyPlaces.SIZE.y), 0.25, 1.0)
	var px := Vector2i((KeepyPlaces.WIDE * s).ceil())
	if _bake[slot].size != px:
		_bake[slot].size = px
	_view[slot].scale = KeepyPlaces.WIDE / Vector2(px)
	_bake[slot].get_child(0).queue_redraw()
	_bake[slot].render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1


## The ambient life's motion: clouds drift and wrap, gulls glide and flap.
func step(delta: float) -> void:
	_t += delta
	for i in clouds.size():
		var c := clouds[i]
		c.position.x += _cloud_speed[i] * delta
		if c.position.x > KeepyPlaces.SIZE.x + KeepyPlaces.BLEED + 220.0:
			c.position.x = -KeepyPlaces.BLEED - 220.0
	if gulls[0].visible:
		for i in gulls.size():
			var g := gulls[i]
			g.position.x = fposmod(300.0 + i * 900.0 + _t * (38.0 + i * 9.0), KeepyPlaces.WIDE.x) - KeepyPlaces.BLEED
			g.position.y = 230.0 + i * 70.0 + sin(_t * 0.4 + i) * 18.0
			g.scale.y = 0.75 + 0.25 * sin(_t * (3.0 + i))


## The scene's batch for a place, built once (`SafeMesh.built`).
static func scene_mesh(index: int) -> SafeMesh:
	return SafeMesh.built("keepy:%d" % index, func(m: SafeMesh) -> void: KeepyPlaces.build_scene(m, index))


## A soft vignette baked with the scene, so the eye goes to the balloon (its centre of interest
## is the column's middle). Light: the places are open air, not a dark room.
static func vignette() -> TextureRect:
	var ink := Color(0.04, 0.07, 0.12)
	var g := Gradient.new()
	g.set_color(0, Color(ink, 0.0))
	g.set_color(1, Color(ink, 0.42))
	for k in [[0.55, 0.0], [0.7, 0.05], [0.84, 0.16]]:
		g.add_point(k[0], Color(ink, k[1]))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.52)
	tex.fill_to = Vector2(1.08, 1.08)
	tex.width = 256
	tex.height = 144
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = KeepyPlaces.WIDE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## A gull far off: a shallow "m" of two curved wings, no tail (ART_BIBLE §5's silhouette rule).
func _paint_gull(ci: CanvasItem) -> void:
	var m := SafeMesh.new()
	var col := Color(0.97, 0.97, 0.95)
	var left := SafeMesh.arc_points(Vector2(-11, 6), 12.0, PI * 1.05, PI * 1.85, 6)
	var right := SafeMesh.arc_points(Vector2(11, 6), 12.0, PI * 1.15, PI * 1.95, 6)
	for pts in [left, right]:
		for k in pts.size() - 1:
			m.line(pts[k], pts[k + 1], 3.0, col)
	m.flush(ci)


## A butterfly sprite: two pairs of round wings (16 px), drawn into an image once.
static func _butterfly_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var p := Vector2(x + 0.5, y + 0.5)
			var a := 0.0
			for c in [Vector2(4.5, 5.5), Vector2(11.5, 5.5)]:
				a = maxf(a, 1.0 - smoothstep(3.2, 4.4, p.distance_to(c)))
			for c in [Vector2(5.5, 11), Vector2(10.5, 11)]:
				a = maxf(a, 1.0 - smoothstep(2.2, 3.2, p.distance_to(c)))
			if absf(p.x - 8.0) < 0.9 and p.y > 3.0 and p.y < 14.0:
				a = 1.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## A leaf sprite: a pointed oval (16 px), drawn into an image once.
static func _leaf_texture() -> Texture2D:
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 16:
			var p := Vector2(x + 0.5 - 8.0, y + 0.5 - 8.0)
			var r := Vector2(p.x / 7.0, p.y / 3.8)
			var a := 1.0 - smoothstep(0.85, 1.0, r.length() + absf(p.x) * 0.02)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)
