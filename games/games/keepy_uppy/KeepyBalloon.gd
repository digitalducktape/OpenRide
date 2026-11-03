class_name KeepyBalloon
extends Node2D
## Keepy Uppy's balloon (#77, 2D; ART_BIBLE.md §4-5): a coral party balloon lit from the place's
## sun (a soft body gradient, a sky-blue rim on its shadow side, a broad sheen and a window
## highlight), its knot, and no string (the silhouette rule: never a round head with a tail).
## Perched birds ride on its top. Drawn once per place; per frame only its position, squash and
## tilt change. The pop (shards and a ring) and the shadow on the grille are here too.

const CORAL := Color("ff5e5b")
const HIGHLIGHT := Color("ffd6c9")
const BIRD := Color("465466")
const BIRD_BELLY := Color("ede6d6")
const BEAK := Color("f5a623")
## Where perched birds sit on the balloon (its local space), in landing order.
const PERCHES := [Vector2(0, -112), Vector2(-50, -96), Vector2(52, -94)]
const POP_SEC := 0.5

var body: Node2D
var birds: Array[Node2D] = []
var shards: CPUParticles2D
var ring: Node2D
var place_index := 0
var _popping := false
var _ring_tween: Tween


func _init() -> void:
	body = SafeDial.Layer.new()
	body.name = "Body"
	body.paint = _paint_body
	add_child(body)
	for i in PERCHES.size():
		var b := SafeDial.Layer.new()
		b.name = "Bird%d" % i
		b.paint = func(ci: CanvasItem) -> void: KeepyBalloon.paint_bird(ci, i % 2 == 1, false)
		b.position = PERCHES[i]
		b.scale = Vector2.ONE * 1.3
		b.visible = false
		body.add_child(b)
		birds.append(b)
	shards = CPUParticles2D.new()
	shards.name = "Shards"
	shards.amount = 26
	shards.lifetime = 1.0
	shards.one_shot = true
	shards.emitting = false
	shards.explosiveness = 1.0
	shards.local_coords = false
	shards.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	shards.emission_sphere_radius = 50.0
	shards.direction = Vector2(0, -1)
	shards.spread = 180.0
	shards.initial_velocity_min = 260.0
	shards.initial_velocity_max = 520.0
	shards.gravity = Vector2(0, 900)
	shards.damping_min = 120.0
	shards.damping_max = 220.0
	shards.angular_velocity_min = -540.0
	shards.angular_velocity_max = 540.0
	shards.scale_amount_min = 1.4
	shards.scale_amount_max = 2.4
	shards.texture = _shard_texture()
	shards.color = CORAL
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.7, Color(1, 1, 1, 1))
	shards.color_ramp = fade
	add_child(shards)
	ring = SafeDial.Layer.new()
	ring.name = "Ring"
	ring.paint = func(ci: CanvasItem) -> void:
		var m := SafeMesh.new()
		m.ring(Vector2.ZERO, 92.0, 104.0, Color(1, 0.97, 0.9, 0.9))
		m.flush(ci)
	ring.visible = false
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	ring.material = add
	add_child(ring)


func set_place(index: int) -> void:
	place_index = index
	body.queue_redraw()


## Places the balloon: its centre `at`, a squash (its climb or sink rate, -0.3..0.3) and a tilt
## (degrees), and how many birds perch on it.
func show_at(at: Vector2, squash: float, tilt_deg: float, perched: int) -> void:
	body.visible = true
	body.position = at
	body.scale = Vector2(1.0 - squash * 0.2, 1.0 + squash * 0.35)
	body.rotation_degrees = tilt_deg
	for i in birds.size():
		birds[i].visible = i < perched


func hide_balloon() -> void:
	body.visible = false


## The balloon's on-screen bounds as drawn now (for the frame check), birds included.
func drawn_bounds() -> Rect2:
	var r := KeepyPlaces.BALLOON_R
	var top := r.y + (60.0 if birds[0].visible else 0.0)
	var s := body.scale
	return Rect2(body.position - Vector2(r.x * s.x + 4.0, top * s.y), Vector2(r.x * s.x * 2.0 + 8.0, (top + r.y + 22.0) * s.y))


func pop() -> void:
	shards.position = body.position
	shards.restart()
	shards.emitting = true
	ring.position = body.position
	ring.visible = true
	ring.scale = Vector2.ONE * 0.4
	ring.modulate.a = 1.0
	_popping = true
	if _ring_tween:
		_ring_tween.kill()
	_ring_tween = create_tween().set_parallel(true)
	_ring_tween.tween_property(ring, "scale", Vector2.ONE * 1.6, POP_SEC).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_ring_tween.tween_property(ring, "modulate:a", 0.0, POP_SEC)
	_ring_tween.chain().tween_callback(func():
		_popping = false
		ring.visible = false)
	hide_balloon()


## Draws the shards and the ring once, hidden by alpha, so their materials compile behind the
## intro card rather than on the first pop.
func prewarm() -> void:
	ring.visible = true
	ring.modulate.a = 0.0
	shards.position = Vector2(-400, -400)
	shards.restart()
	shards.emitting = true
	for i in 3:
		await get_tree().process_frame
	if not _popping:
		ring.visible = false


func _paint_body(ci: CanvasItem) -> void:
	var m := SafeMesh.new()
	var r := KeepyPlaces.BALLOON_R
	var sun := KeepyPlaces.to_sun(place_index)
	var pl := KeepyPlaces.place(place_index)
	var sky: Color = pl.sky_top
	var sun_col: Color = pl.sun_col
	# The body: an egg (a little fuller at the top), shaded from the sun's side to the far side.
	var outline := PackedVector2Array()
	var cols := PackedColorArray()
	var segs := 64
	for k in segs:
		var a := TAU * k / segs
		var d := Vector2(cos(a), sin(a))
		var p := Vector2(d.x * r.x * (1.0 - 0.08 * maxf(d.y, 0.0)), d.y * r.y)
		outline.append(p)
		var lit := clampf(0.5 + 0.5 * d.dot(sun), 0.0, 1.0)
		cols.append(CORAL.darkened(0.32).lerp(CORAL.lightened(0.06), lit))
	var ci_center := m.vert(sun * 18.0, CORAL)
	var first := m.points.size()
	for k in segs:
		m.vert(outline[k], cols[k])
	for k in segs:
		m.tri(ci_center, first + k, first + (k + 1) % segs)
	var clear := PackedColorArray()
	for c in cols:
		clear.append(Color(c, 0.0))
	m.band_colors(outline, SafeMesh.grow_outline(outline, SafeMesh.FEATHER), cols, clear)
	# A sky-coloured rim on the shadow side, and the sun showing through the latex at the edge.
	var rim_in := SafeMesh.grow_outline(outline, -9.0)
	var rim_c := PackedColorArray()
	var rim_clear := PackedColorArray()
	for k in segs:
		var d := outline[k].normalized()
		var w := clampf(-d.dot(sun) * 1.2, 0.0, 1.0)
		rim_c.append(Color(sky.lightened(0.35), 0.45 * w))
		rim_clear.append(Color(sky.lightened(0.35), 0.0))
	m.band_colors(rim_in, outline, rim_clear, rim_c)
	# The sheen and the window highlight, toward the sun.
	m.glow(sun * r.x * 0.38, Vector2(r.x * 0.55, r.y * 0.5), Color(HIGHLIGHT, 0.32), 10)
	var hl := sun * r.x * 0.5 + Vector2(0, -6)
	m.glow(hl, Vector2(16, 24), Color(1, 1, 1, 0.85), 8, 0.3)
	m.glow(hl + Vector2(14, 22).rotated(sun.angle() + PI * 0.5) * 0.4, Vector2(5, 7), Color(1, 1, 1, 0.7), 4)
	m.glow(Vector2(-sun.x * r.x * 0.2, r.y * 0.6), Vector2(r.x * 0.5, r.y * 0.25), Color(sun_col, 0.12), 6)
	# The knot: a little pinched neck and a tied lip, no string.
	m.fill(PackedVector2Array([Vector2(-10, r.y - 4), Vector2(10, r.y - 4), Vector2(5, r.y + 8), Vector2(-5, r.y + 8)]), CORAL.darkened(0.25))
	m.round_rect(Rect2(-11, r.y + 6, 22, 9), 4.0, CORAL.darkened(0.12), CORAL.darkened(0.4))
	m.flush(ci)


## A small round bird: slate body, cream belly, a dark eye, a short wedge tail and a folded wing
## (perched), or both wings raised (`flying`). Facing right unless `mirror`. About 70 px across.
static func paint_bird(ci: CanvasItem, mirror: bool, flying: bool) -> void:
	var m := SafeMesh.new()
	var s := -1.0 if mirror else 1.0
	if flying:
		# Both wings up: broad triangles, the far one a little darker.
		m.fill(PackedVector2Array([Vector2(-12 * s, -6), Vector2(-24 * s, -50), Vector2(6 * s, -10)]), BIRD.darkened(0.3))
		m.fill(PackedVector2Array([Vector2(-6 * s, -4), Vector2(18 * s, -48), Vector2(10 * s, -6)]), BIRD.darkened(0.12))
	# The tail: a short wedge, wider than it is long (never a tapering tail).
	m.fill(PackedVector2Array([Vector2(-18 * s, 2), Vector2(-34 * s, -6), Vector2(-34 * s, 12)]), BIRD.darkened(0.2))
	m.circle(Vector2(0, 0), 20.0, BIRD)
	m.circle(Vector2(5 * s, 7), 13.0, BIRD_BELLY)
	m.circle(Vector2(14 * s, -14), 13.0, BIRD)
	m.fill(PackedVector2Array([Vector2(24 * s, -17), Vector2(36 * s, -12), Vector2(24 * s, -9)]), BEAK)
	m.circle(Vector2(17 * s, -17), 3.2, Color(0.05, 0.05, 0.06))
	m.circle(Vector2(18 * s, -18), 1.2, Color(1, 1, 1))
	if not flying:
		m.fill(PackedVector2Array([Vector2(-12 * s, -6), Vector2(8 * s, -8), Vector2(2 * s, 8), Vector2(-14 * s, 6)]), BIRD.darkened(0.15))
		for dx in [-5.0, 5.0]:
			m.line(Vector2(dx, 18), Vector2(dx, 26), 2.5, BEAK.darkened(0.3))
	m.flush(ci)


## A latex shard: a small irregular triangle (12 px), drawn into an image once.
static func _shard_texture() -> Texture2D:
	var img := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	var a := Vector2(1, 2)
	var b := Vector2(11, 4)
	var c := Vector2(4, 11)
	for y in 12:
		for x in 12:
			var p := Vector2(x + 0.5, y + 0.5)
			var inside := Geometry2D.point_is_inside_triangle(p, a, b, c)
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if inside else 0.0))
	return ImageTexture.create_from_image(img)
