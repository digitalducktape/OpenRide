class_name SafeBackdrop
extends Node2D
## The room behind the safe (#41): the room's `MeshBatch2D` batch and the soot vignette, baked into
## one texture when the place changes (`RoomBake`, a SubViewport at the screen's own resolution)
## and shown as one opaque sprite, and the place's slow ambient life as children that never
## redraw: rain on the office window and
## the sea in the cabin's porthole (shaders on one rect each), the cabin's lantern swaying (a
## rotation tween), the lab's flasks shimmering (a shader), and dust drifting in the key light
## (one CPUParticles2D, 16 motes). Each lives in its place and is hidden in the others.
##
## Why the bake (GFX_POLISH.md, "Tablet performance"): the tablet's GPU pays for every pixel of
## every blended layer. Drawn live, the room was 2-3 screens of stacked fills (the wall, the
## floor and boards over it, the props, two or three big light pools) plus a full-screen
## vignette; baked, it's one screen of texture, drawn once a frame.

const RAIN_RECT := Rect2(64, 314, 312, 392)
const PORTHOLE := Vector2(230, 520)
const PORTHOLE_R := 124.0
const LANTERN_PIVOT := Vector2(1700, 120)
const LANTERN_SWAY := 2.5  ## degrees each way
const LANTERN_SEC := 3.6  ## one way
const DUST := 16

var place_index := 0
## The room and vignette render here once per place change (or window resize), not per frame.
var bake: SubViewport
var room: Node2D
var view: Sprite2D
## Renders made, for tests.
var bakes: int:
	get:
		return _baked.bakes
var _baked: BakedBackdrop
var rain: ColorRect
var sea: ColorRect
var lantern: Node2D
var flasks: Node2D
var dust: CPUParticles2D
var _lantern_tween: Tween


func _init() -> void:
	_baked = BakedBackdrop.new(SafePlaces.SIZE, SafePlaces.WIDE, SafePlaces.BLEED, "RoomBake", "Room")
	_baked.name = "Baked"
	add_child(_baked)
	bake = _baked.bake
	view = _baked.view
	room = PaintLayer.new()
	room.name = "Room"
	room.paint = _paint_room
	room.position = Vector2(SafePlaces.BLEED, 0)
	_baked.add_painted(room)
	_baked.add_painted(vignette())
	rain = _shader_rect("Rain", RAIN_RECT, preload("res://games/safe_cracker/safe_rain.gdshader"))
	sea = _shader_rect("Sea", Rect2(PORTHOLE - Vector2.ONE * PORTHOLE_R, Vector2.ONE * PORTHOLE_R * 2.0),
		preload("res://games/safe_cracker/safe_sea.gdshader"))
	flasks = PaintLayer.new()
	flasks.name = "Flasks"
	flasks.paint = _paint_flasks
	var shimmer := ShaderMaterial.new()
	shimmer.shader = preload("res://games/safe_cracker/safe_shimmer.gdshader")
	flasks.material = shimmer
	add_child(flasks)
	lantern = PaintLayer.new()
	lantern.name = "Lantern"
	lantern.paint = _paint_lantern
	lantern.position = LANTERN_PIVOT
	add_child(lantern)
	dust = _make_dust()
	add_child(dust)


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
	var id: String = SafePlaces.place(index).id
	rain.visible = id == "office"
	sea.visible = id == "cabin"
	flasks.visible = id == "lab"
	lantern.visible = id == "cabin"
	if _lantern_tween:
		_lantern_tween.kill()
		_lantern_tween = null
	lantern.rotation = 0.0
	if lantern.visible and is_inside_tree():
		_lantern_tween = create_tween().set_loops()
		_lantern_tween.tween_property(lantern, "rotation", deg_to_rad(LANTERN_SWAY), LANTERN_SEC).set_trans(Tween.TRANS_SINE)
		_lantern_tween.tween_property(lantern, "rotation", deg_to_rad(-LANTERN_SWAY), LANTERN_SEC).set_trans(Tween.TRANS_SINE)
	var l := SafePlaces.light(index)
	var at: Vector2 = l.at
	var overhead := at.y < 100.0
	dust.position = at + (Vector2(0, 200) if overhead else Vector2.ZERO)
	dust.emission_rect_extents = Vector2(700, 150) if overhead else (l.radius as Vector2) * 0.4
	var lc: Color = l.color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(lc, 0.0))
	ramp.set_color(1, Color(lc, 0.0))
	ramp.add_point(0.25, Color(lc, 0.28))
	ramp.add_point(0.75, Color(lc, 0.22))
	dust.color_ramp = ramp
	dust.restart()
	flasks.queue_redraw()
	rebake()


## Renders the room once (`BakedBackdrop`), at the size the canvas is shown on screen.
func rebake() -> void:
	_baked.rebake()


func _paint_room(ci: CanvasItem) -> void:
	room_mesh(place_index).draw_on(ci)


## The room's batch for a place, built once (`MeshBatch2D.built`).
static func room_mesh(index: int) -> MeshBatch2D:
	return MeshBatch2D.built("room:%d" % index, func(m: MeshBatch2D) -> void: SafePlaces.build_room(m, index))


## A soft soot vignette over the room, so the eye goes to the safe: baked with the room, so it
## costs nothing a frame. The ambient life draws over it (it is under 6% where they are).
static func vignette() -> TextureRect:
	var ink := SafeDial.INK
	var g := Gradient.new()
	g.set_color(0, Color(ink, 0.0))
	g.set_color(1, Color(ink, 0.72))
	# A smooth shoulder (no visible edge where the darkening starts).
	for k in [[0.5, 0.0], [0.62, 0.05], [0.74, 0.18], [0.86, 0.4]]:
		g.add_point(k[0], Color(ink, k[1]))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, SafePlaces.SAFE_AT.y / SafePlaces.SIZE.y)
	tex.fill_to = Vector2(1.05, 1.05)
	tex.width = 256
	tex.height = 144
	var rect := TextureRect.new()
	rect.name = "Vignette"
	rect.texture = tex
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.size = SafePlaces.WIDE  # over the whole painted room: its edges stay soot-dark (#57)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect


## The flasks' liquids on the lab's shelves (the glass is in the room).
func _paint_flasks(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var tints := [Color(0.4, 0.85, 0.6), Color(0.9, 0.6, 0.3), Color(0.5, 0.7, 0.95), Color(0.9, 0.5, 0.6)]
	for shelf in 3:
		var y := 420.0 + shelf * 150.0
		for k in 4:
			var c: Color = tints[(k + shelf) % 4]
			var at := Vector2(110.0 + k * 80.0, y + 72.0)
			var cut := 10.0 - 4.0 * ((k + shelf) % 3)
			var arc := MeshBatch2D.arc_points(at, 26.0, asin(-cut / 26.0), PI - asin(-cut / 26.0), 18)
			m.fill(arc, c)
			m.rect(Rect2(at.x - 18, at.y - cut - 2.0, 36, 3), c.lightened(0.4))
			m.circle(at + Vector2(-9, 8), 5.0, Color(1, 1, 1, 0.25))
	m.flush(ci)


## The lantern on its chain, from the pivot: a cage with a glowing glass.
func _paint_lantern(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var iron := Color(0.14, 0.11, 0.08)
	var acc: Color = SafePlaces.place(place_index).accent
	for k in 8:
		m.line(Vector2(0, k * 26.0), Vector2(0, k * 26.0 + 20.0), 4.0, iron.lightened(0.15))
	var top := 220.0
	m.glow(Vector2(0, top + 80), Vector2(110, 110), Color(1.0, 0.75, 0.35, 0.35), 10)
	m.quad(Vector2(-22, top), Vector2(22, top), Vector2(38, top + 26), Vector2(-38, top + 26), iron.lightened(0.1))
	m.rect_v(Rect2(-32, top + 26, 64, 104), Color(1.0, 0.85, 0.5, 0.9), Color(1.0, 0.65, 0.3, 0.9))
	m.glow(Vector2(0, top + 78), Vector2(18, 30), Color(1, 0.97, 0.85, 1.0), 6, 0.3)
	for x in [-32.0, 0.0, 32.0]:
		m.line(Vector2(x, top + 26), Vector2(x, top + 130), 5.0, iron)
	m.rect_v(Rect2(-40, top + 128, 80, 16), acc, acc.darkened(0.4))
	m.circle(Vector2(0, top - 6), 9.0, iron)
	m.flush(ci)


func _make_dust() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Dust"
	p.amount = DUST
	p.lifetime = 9.0
	p.preprocess = 9.0
	p.texture = MeshBatch2D.soft_dot()
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(200, 200)
	p.direction = Vector2(0.3, -1)
	p.spread = 180.0
	p.gravity = Vector2(0, 2)
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.1
	p.scale_amount_max = 0.2
	return p
