class_name LaunchRocket
extends Node2D
## The hero (#82; ART_BIBLE.md §3): a chunky stepped spacecraft, drawn in code. Each section is one
## `MeshBatch2D` layer, built once per mark, so a stage can drop away as its own node. The origin is
## the engines' exit, on the launch table; y is negative upward.
##
## Silhouette (the rider's warning): the outline is a stepped tower that gets narrower going up,
## a wide base with big angular fins, flared skirts and collars wider than the hull at every
## joint, and a straight-sided faceted cone. No smooth tube, no round nose, no strap-on boosters
## beside the base. `tests/capture_launch.gd --silhouette` draws each mark in solid black.
##
## The flame is `rfl_flame.gdshader` on one rect under the lowest section: a wide flat curtain of
## tongues, never a teardrop.

const MARKS := [
	{"name": "Mk I", "bells": 1, "sections": [
		{"kind": "booster", "h": 170.0, "w": 172.0, "fin": 96.0},
		{"kind": "upper", "h": 96.0, "w": 136.0},
		{"kind": "capsule", "h": 136.0, "w": 112.0}], "drops": {"clouds": true, "orbit": true}},
	{"name": "Mk II", "bells": 2, "sections": [
		{"kind": "booster", "h": 176.0, "w": 196.0, "fin": 112.0},
		{"kind": "middle", "h": 110.0, "w": 160.0},
		{"kind": "upper", "h": 74.0, "w": 132.0},
		{"kind": "capsule", "h": 140.0, "w": 116.0}], "drops": {"clouds": true, "edge": true, "orbit": true}},
	{"name": "Mk III", "bells": 3, "sections": [
		{"kind": "booster", "h": 200.0, "w": 224.0, "fin": 128.0},
		{"kind": "middle", "h": 130.0, "w": 184.0},
		{"kind": "upper", "h": 80.0, "w": 146.0},
		{"kind": "capsule", "h": 150.0, "w": 122.0}], "drops": {"clouds": true, "edge": true, "orbit": true}},
]
const BELL_H := 40.0  ## the booster's engines, under its hull
const UPPER_BELL_H := 34.0  ## the engine under every section above the booster
const SKIRT_H := 26.0  ## the flared adapter on top of a section
const HULL := Color("f1ece0")
const HULL_LOW := Color("c9c3bb")
const TRIM := Color("e4572e")  ## the signal orange: only on the rocket
const TRIM2 := Color("24324f")
const BRASS := Color("d9a441")
const STEEL := Color("7a8294")
const FALL := 300.0  ## px a second a dropped stage starts falling at
const FLAME_MIN := 130.0
const FLAME_MAX := 300.0
const FLAME_IN_SPACE := 0.42  ## vacuum: a short wide fan, never a long tail
const LEG_FOOT := 58.0  ## how far the landing legs reach below the capsule's section origin

var mark := 0
var sections: Array[Node2D] = []
var offsets: Array[float] = []  ## each section's bottom, above the origin
var bottom := 0  ## the lowest section still attached
var flame: ColorRect
var legs: Node2D
var sight: Node2D  ## the fuel sight glass's level, scaled by the tank
var separation: CPUParticles2D
var thrust := 0.0  ## 0 off, 1 the target, up to 1.3
var space := 0.0  ## 0 in air, 1 in vacuum: the flame shortens
var _shown_thrust := 0.0
var _falling: Array[Dictionary] = []


func _init() -> void:
	name = "Rocket"
	flame = ColorRect.new()
	flame.name = "Flame"
	flame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://games/ready_for_launch/shaders/rfl_flame.gdshader")
	flame.material = mat
	flame.visible = false
	add_child(flame)
	separation = CPUParticles2D.new()
	separation.name = "Separation"
	separation.amount = 14
	separation.lifetime = 0.55
	separation.one_shot = true
	separation.explosiveness = 0.95
	separation.emitting = false
	separation.texture = LaunchPad.puff_texture()
	separation.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	separation.emission_rect_extents = Vector2(90.0, 6.0)
	separation.direction = Vector2(0, 0)
	separation.spread = 180.0
	separation.gravity = Vector2.ZERO
	separation.initial_velocity_min = 120.0
	separation.initial_velocity_max = 280.0
	separation.damping_min = 180.0
	separation.damping_max = 260.0
	separation.scale_amount_min = 0.5
	separation.scale_amount_max = 1.0
	separation.color_ramp = LaunchPad.ramp([Color(1, 0.96, 0.86, 0.9), Color(1, 1, 1, 0.0)])
	add_child(separation)


## Builds mark `index` (0-2), fully stacked and on the pad.
func setup(index: int) -> void:
	mark = posmod(index, MARKS.size())
	for s in sections:
		remove_child(s)
		s.free()
	for f in _falling:
		if is_instance_valid(f.node):
			f.node.free()
	_falling.clear()
	sections.clear()
	offsets.clear()
	bottom = 0
	thrust = 0.0
	_shown_thrust = 0.0
	flame.visible = false
	legs = null
	sight = null
	var spec: Dictionary = MARKS[mark]
	var y := BELL_H
	var parts: Array = spec.sections
	var made: Array[Node2D] = []
	for i in parts.size():
		var layer: Node2D = PaintLayer.new()
		layer.name = "Section%d" % i
		layer.position = Vector2(0, -y)
		var key := "rfl:mk%d:%d" % [mark, i]
		var part: Dictionary = parts[i]
		var next_w: float = float(parts[i + 1].w) if i + 1 < parts.size() else 0.0
		var bells: int = spec.bells
		layer.paint = func(ci: CanvasItem) -> void:
			MeshBatch2D.built(key, func(m: MeshBatch2D) -> void: paint_section(m, part, next_w, bells, i)).draw_on(ci)
		made.append(layer)
		sections.append(layer)
		offsets.append(y)
		y += float(part.h) + SKIRT_H
	# Upper sections first, so each lower one's skirt covers the engine above it.
	for i in range(made.size() - 1, -1, -1):
		add_child(made[i])
	# The sight glass's level on the booster, and the capsule's folded legs.
	sight = PaintLayer.new()
	sight.name = "FuelLevel"
	var booster_h: float = parts[0].h
	sight.position = Vector2(0, -24.0)
	sight.paint = func(ci: CanvasItem) -> void:
		var m := MeshBatch2D.new()
		m.rect_v(Rect2(-13.0, -(booster_h - 48.0), 26.0, booster_h - 48.0), Color("ffe08a"), Color("f5a623"))
		m.flush(ci)
	sight.scale.y = 0.0
	sections[0].add_child(sight)
	legs = PaintLayer.new()
	legs.name = "Legs"
	var cap_w: float = parts[-1].w
	legs.paint = func(ci: CanvasItem) -> void:
		var m := MeshBatch2D.new()
		paint_legs(m, cap_w)
		m.flush(ci)
	legs.visible = false
	sections[-1].add_child(legs)
	move_child(flame, 0)
	move_child(separation, get_child_count() - 1)
	_place_flame()


## The whole stack's height above the origin, as it stands now.
func stack_height() -> float:
	return height_of(mark) + lowest_y()


## The full height of mark `index`.
static func height_of(index: int) -> float:
	var h := BELL_H
	for s: Dictionary in MARKS[posmod(index, MARKS.size())].sections:
		h += float(s.h) + SKIRT_H
	return h - SKIRT_H + 20.0  # the mast above the capsule's cone


## The widest the mark gets, fins included: for the frame check.
static func half_width_of(index: int) -> float:
	var b: Dictionary = MARKS[posmod(index, MARKS.size())].sections[0]
	return float(b.w) * 0.5 + float(b.fin)


## Where the stack now ends: the mouth of the lowest engine (0 for the whole rocket).
func lowest_y() -> float:
	return 0.0 if bottom == 0 else -offsets[bottom] + UPPER_BELL_H


## The tank's level on the sight glass, 0-1.
func set_fuel(level: float) -> void:
	sight.scale.y = clampf(level, 0.0, 1.0)


## Drops the lowest section; false when only the capsule is left.
func drop_stage() -> bool:
	if bottom >= sections.size() - 1:
		return false
	var s := sections[bottom]
	_falling.append({"node": s, "v": FALL, "spin": deg_to_rad(10.0 if bottom % 2 == 0 else -12.0), "drift": -22.0 if bottom % 2 == 0 else 26.0, "t": 0.0})
	separation.position = Vector2(0, -offsets[bottom + 1] + 6.0)
	separation.restart()
	bottom += 1
	_place_flame()
	return true


## Whether the mark drops a stage at this milestone.
func drops_at(milestone_id: String) -> bool:
	return bool(MARKS[mark].drops.get(milestone_id, false))


func deploy_legs() -> void:
	legs.visible = true
	legs.scale = Vector2(0.4, 1.0)
	create_tween().tween_property(legs, "scale", Vector2.ONE, 0.8).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## One frame: the flame follows the thrust; dropped stages fall behind.
func step(delta: float) -> void:
	_shown_thrust = move_toward(_shown_thrust, thrust, delta * 2.5)
	flame.visible = _shown_thrust > 0.02
	if flame.visible:
		var s := clampf(_shown_thrust, 0.0, 1.3)
		var length := lerpf(FLAME_MIN, FLAME_MAX, clampf(s / 1.3, 0.0, 1.0)) * lerpf(1.0, FLAME_IN_SPACE, space)
		flame.size.y = length
		var mat := flame.material as ShaderMaterial
		mat.set_shader_parameter("power", s)
		mat.set_shader_parameter("space", space)
	for i in range(_falling.size() - 1, -1, -1):
		var f: Dictionary = _falling[i]
		f.t += delta
		f.v += 620.0 * delta
		var n: Node2D = f.node
		n.position += Vector2(f.drift, f.v) * delta
		n.rotation += f.spin * delta
		n.modulate.a = clampf(2.2 - f.t, 0.0, 1.0)
		if f.t > 2.2:
			n.visible = false
			_falling.remove_at(i)


func _place_flame() -> void:
	var spec: Dictionary = MARKS[mark].sections[bottom]
	var w: float = float(spec.w) * (1.0 if bottom == 0 else 1.15)
	var count: int = MARKS[mark].bells if bottom == 0 else 3
	if count == 1:
		count = 3  # a curtain of tongues at every size
	flame.size = Vector2(w, FLAME_MIN)
	flame.position = Vector2(-w * 0.5, lowest_y() - 3.0)
	(flame.material as ShaderMaterial).set_shader_parameter("tongues", float(count))


# --- Painting (all once per mark, through MeshBatch2D.built) ---

## The cylinder's light across its width: u is -1 at the left, 1 at the right; the key light is
## right of centre, a soft bounce on the far left edge.
static func _lit(col: Color, u: float) -> Color:
	var key := 1.0 - pow(absf(u - 0.38) / 1.38, 1.7)
	var shade := lerpf(0.5, 1.08, clampf(key, 0.0, 1.0))
	var out := Color(col.r * shade, col.g * shade, col.b * shade * lerpf(1.08, 1.0, key), col.a)
	if u < -0.82:
		out = out.lerp(Color("8ea6c8"), (-0.82 - u) / 0.18 * 0.3)
	return out


## A hull band from `y0` to `y1` (y0 lower, both negative up), `w0` wide at y0 and `w1` at y1.
static func _hull(m: MeshBatch2D, y0: float, y1: float, w0: float, w1: float, col: Color) -> void:
	var strips := 12
	for k in strips:
		var a := -1.0 + 2.0 * k / strips
		var b := -1.0 + 2.0 * (k + 1) / strips
		var ca := _lit(col, a)
		var cb := _lit(col, b)
		m.quad4(Vector2(a * w1 * 0.5, y1), Vector2(b * w1 * 0.5, y1), Vector2(b * w0 * 0.5, y0), Vector2(a * w0 * 0.5, y0), ca, cb, cb, ca)
	# Feathered silhouette edges.
	m.line(Vector2(-w0 * 0.5, y0), Vector2(-w1 * 0.5, y1), 2.0, _lit(col, -1.0).darkened(0.3))
	m.line(Vector2(w0 * 0.5, y0), Vector2(w1 * 0.5, y1), 2.0, _lit(col, 1.0).darkened(0.3))


## A straight joint round the hull with a row of rivets on it.
static func _seam(m: MeshBatch2D, y: float, w: float, rivets := 9) -> void:
	m.line(Vector2(-w * 0.5, y), Vector2(w * 0.5, y), 2.0, Color(0.1, 0.1, 0.16, 0.34))
	m.line(Vector2(-w * 0.5, y + 2.0), Vector2(w * 0.5, y + 2.0), 1.4, Color(1, 1, 1, 0.22))
	for k in rivets:
		var u := sin((float(k) + 0.5) / rivets * PI - PI * 0.5)  # bunched toward the edges, as on a drum
		m.circle(Vector2(u * w * 0.47, y - 6.0), 2.4, _lit(STEEL, u).darkened(0.1), false)


## A collar: a ring wider than the hull, the silhouette's step.
static func _collar(m: MeshBatch2D, y: float, w: float, h := 14.0) -> void:
	_hull(m, y, y - h, w + 20.0, w + 20.0, STEEL)
	m.line(Vector2(-w * 0.5 - 10.0, y - h), Vector2(w * 0.5 + 10.0, y - h), 2.0, Color(1, 1, 1, 0.38))
	for k in 11:
		var u := sin((float(k) + 0.5) / 11.0 * PI - PI * 0.5)
		m.circle(Vector2(u * (w + 20.0) * 0.46, y - h * 0.5), 2.2, Color(0.12, 0.13, 0.2, 0.7), false)


## A ribbed adapter, `w0` wide at the bottom and `w1` at the top.
static func _skirt(m: MeshBatch2D, y: float, w0: float, w1: float) -> void:
	_hull(m, y, y - SKIRT_H, w0, w1, Color("9aa0ae"))
	for k in 15:
		var u := -0.93 + 1.86 * k / 14.0
		m.line(Vector2(u * w0 * 0.5, y), Vector2(u * w1 * 0.5, y - SKIRT_H), 1.6, Color(0.1, 0.1, 0.16, 0.3))


## A porthole: a brass rim with bolts, warm glass and a glint.
static func _porthole(m: MeshBatch2D, at: Vector2, r: float) -> void:
	m.circle(at + Vector2(-1.5, 3.0), r + 7.0, Color(0, 0, 0, 0.25))
	m.circle(at, r + 6.0, BRASS.darkened(0.15))
	m.ring(at, r + 2.0, r + 6.0, BRASS.lightened(0.25), -PI * 0.5, PI * 0.4)
	m.circle(at, r, Color("1c3050"))
	m.glow(at + Vector2(0, r * 0.3), Vector2(r, r) * 0.9, Color("ffc66a"), 6)
	m.fill(PackedVector2Array([at + Vector2(r * 0.1, -r * 0.82), at + Vector2(r * 0.62, -r * 0.52), at + Vector2(r * 0.32, -r * 0.1), at + Vector2(-r * 0.1, -r * 0.5)]), Color(1, 1, 1, 0.55))
	for k in 6:
		var a := TAU * k / 6.0
		m.circle(at + Vector2(cos(a), sin(a)) * (r + 4.0), 1.6, Color(0.2, 0.14, 0.05, 0.8), false)


## One engine bell, its mouth at `y` and throat above.
static func _bell(m: MeshBatch2D, x: float, y: float, h: float, w: float) -> void:
	var dark := Color("2c2f3c")
	var strips := 6
	for k in strips:
		var a := -1.0 + 2.0 * k / strips
		var b := -1.0 + 2.0 * (k + 1) / strips
		var ca := _lit(Color("6a6f80"), a)
		var cb := _lit(Color("6a6f80"), b)
		m.quad4(Vector2(x + a * w * 0.26, y - h), Vector2(x + b * w * 0.26, y - h), Vector2(x + b * w * 0.5, y), Vector2(x + a * w * 0.5, y), ca, cb, cb, ca)
	for k in 3:
		var t := (float(k) + 0.6) / 3.5
		var half := lerpf(0.26, 0.5, t) * w
		m.line(Vector2(x - half, y - h + h * t), Vector2(x + half, y - h + h * t), 2.0, Color(dark, 0.6))
	m.rect(Rect2(x - w * 0.5 - 2.0, y - 4.0, w + 4.0, 5.0), dark)


## An angular swept fin on side `s` (-1 left, 1 right): straight edges, sharp corners.
static func _fin(m: MeshBatch2D, s: float, root_top: float, root_bottom: float, half_w: float, span: float) -> void:
	var a := Vector2(s * (half_w - 3.0), root_top)
	var b := Vector2(s * (half_w + span * 0.8), root_bottom + 6.0)
	var c := Vector2(s * (half_w + span), root_bottom + BELL_H + 10.0)
	var d := Vector2(s * (half_w + span * 0.5), root_bottom + BELL_H)
	var e := Vector2(s * (half_w - 3.0), root_bottom)
	var lit := TRIM.lightened(0.14) if s > 0.0 else TRIM.darkened(0.2)
	var deep := TRIM.darkened(0.12) if s > 0.0 else TRIM.darkened(0.36)
	m.quad4(a, b, d, e, lit, lit, deep, deep)
	m.fill(PackedVector2Array([b, c, d]), deep)
	# A white leading edge band and a panel line.
	m.line(a, b, 7.0, Color("f7efe0").darkened(0.04 if s > 0.0 else 0.26))
	m.line(b, c, 7.0, Color("f7efe0").darkened(0.04 if s > 0.0 else 0.26))
	m.line(e.lerp(a, 0.5), b.lerp(d, 0.5), 2.0, Color(0, 0, 0, 0.3))
	for k in 4:
		m.circle(e.lerp(a, (float(k) + 0.5) / 4.0) + Vector2(s * 10.0, 0.0), 2.4, Color(0, 0, 0, 0.35), false)


## Grime running down from a seam: soft dark streaks, never many.
static func _streaks(m: MeshBatch2D, seed_value: int, y0: float, y1: float, w: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for k in 7:
		var x := rng.randf_range(-0.44, 0.44) * w
		var half := rng.randf_range(3.0, 7.0)
		var top := lerpf(y1, y0, rng.randf_range(0.0, 0.5))
		var low := top + rng.randf_range(24.0, 60.0)
		m.quad4(Vector2(x - half, top), Vector2(x + half, top), Vector2(x + half * 0.6, low), Vector2(x - half * 0.6, low),
			Color(0.16, 0.13, 0.13, 0.17), Color(0.16, 0.13, 0.13, 0.17), Color(0.16, 0.13, 0.13, 0.0), Color(0.16, 0.13, 0.13, 0.0))


static func paint_section(m: MeshBatch2D, part: Dictionary, next_w: float, bells: int, index: int) -> void:
	var w: float = part.w
	var h: float = part.h
	match str(part.kind):
		"booster":
			_paint_booster(m, w, h, next_w, bells, float(part.fin))
		"middle":
			_paint_middle(m, w, h, next_w, index)
		"upper":
			_paint_upper(m, w, h, next_w, index)
		"capsule":
			_paint_capsule(m, w, h)


static func _paint_booster(m: MeshBatch2D, w: float, h: float, next_w: float, bells: int, fin: float) -> void:
	var bell_w := w * (0.62 if bells == 1 else 0.44 if bells == 2 else 0.34)
	var spread := 0.0 if bells == 1 else w * 0.26 if bells == 2 else w * 0.33
	for k in bells:
		var x := 0.0 if bells == 1 else lerpf(-spread, spread, float(k) / (bells - 1))
		_bell(m, x, BELL_H, BELL_H + 6.0, bell_w)
	_fin(m, -1.0, -h * 0.62, 0.0, w * 0.5, fin)
	_fin(m, 1.0, -h * 0.62, 0.0, w * 0.5, fin)
	_hull(m, 0.0, -h, w, w, HULL)
	_collar(m, 8.0, w, 16.0)
	# The base band and a chunky roll pattern up the side.
	_hull(m, -6.0, -46.0, w, w, TRIM)
	for k in 3:
		var y := -60.0 - k * ((h - 80.0) / 3.0)
		var cell := (h - 80.0) / 3.0
		var left := -w * 0.5 if k % 2 == 0 else w * 0.18
		_block(m, left, y, w * 0.32, cell, TRIM2, w)
	_seam(m, -46.0, w)
	_seam(m, -h * 0.55, w)
	_streaks(m, 3 + bells, -h, -40.0, w)
	# The fuel sight glass: a brass-framed window up the hull's front.
	var frame := Rect2(-20.0, -(h - 16.0), 40.0, h - 34.0)
	m.round_rect(frame, 8.0, BRASS.lightened(0.15), BRASS.darkened(0.2))
	m.round_rect(frame.grow(-6.0), 4.0, Color("1a2438"), Color("28344e"))
	# The ticks go on the glass; the level (`sight`) rises behind them on the next layer.
	var top_w := next_w if next_w > 0.0 else w * 0.7
	_skirt(m, -h, w, top_w)


## A wrapped colour block on the hull between `left` and `left + block` (x), shaded with the hull.
static func _block(m: MeshBatch2D, left: float, y: float, block: float, h: float, col: Color, w: float) -> void:
	var strips := 4
	for k in strips:
		var x0 := left + block * k / strips
		var x1 := left + block * (k + 1) / strips
		var c0 := _lit(col, x0 / (w * 0.5))
		var c1 := _lit(col, x1 / (w * 0.5))
		m.quad4(Vector2(x0, y - h), Vector2(x1, y - h), Vector2(x1, y), Vector2(x0, y), c0, c1, c1, c0)


static func _paint_middle(m: MeshBatch2D, w: float, h: float, next_w: float, index: int) -> void:
	_bell(m, 0.0, 34.0, 34.0, w * 0.5)
	_hull(m, 0.0, -h, w, w, HULL)
	_collar(m, 6.0, w)
	_hull(m, -h * 0.34, -h * 0.5, w, w, TRIM)
	_seam(m, -h * 0.34, w)
	_seam(m, -h * 0.82, w)
	_block(m, w * 0.12, -h * 0.58, w * 0.22, h * 0.22, TRIM2, w)
	_block(m, -w * 0.36, -h * 0.58, w * 0.22, h * 0.22, TRIM2, w)
	_streaks(m, 11 + index, -h, 0.0, w)
	# Two short stub fins, the step in the outline.
	for s in [-1.0, 1.0]:
		var hw := w * 0.5
		m.fill(PackedVector2Array([Vector2(s * hw, -h * 0.3), Vector2(s * (hw + 26.0), -6.0), Vector2(s * hw, 0.0)]), TRIM.darkened(0.08 if s > 0.0 else 0.32))
	_skirt(m, -h, w, next_w)


static func _paint_upper(m: MeshBatch2D, w: float, h: float, next_w: float, index: int) -> void:
	_bell(m, 0.0, 34.0, 34.0, w * 0.54)
	_hull(m, 0.0, -h, w, w, HULL)
	_collar(m, 6.0, w)
	_hull(m, -h * 0.58, -h * 0.76, w, w, TRIM2)
	_seam(m, -h * 0.3, w, 7)
	_streaks(m, 17 + index, -h, 0.0, w)
	# Two porthole-style hatches, friendly and easy to see small.
	_porthole(m, Vector2(-w * 0.22, -h * 0.3), 11.0)
	_porthole(m, Vector2(w * 0.22, -h * 0.3), 11.0)
	_skirt(m, -h, w, next_w)


## The capsule: a straight-sided cone with a stepped base, big portholes and a sharp tip mast.
static func _paint_capsule(m: MeshBatch2D, w: float, h: float) -> void:
	_bell(m, 0.0, 34.0, 34.0, w * 0.6)
	_collar(m, 6.0, w, 16.0)
	# The service drum, then two cone facets (a break in the line: angular, not an ogive).
	var drum := h * 0.3
	_hull(m, -8.0, -drum, w, w, HULL)
	_hull(m, -drum * 0.62, -drum * 0.86, w, w, TRIM)
	_collar(m, -drum, w - 8.0, 10.0)
	var shoulder := -drum - 10.0
	var mid := shoulder - h * 0.42
	var tip := -h - 2.0
	_hull(m, shoulder, mid, w - 6.0, w * 0.46, HULL)
	_hull(m, mid, tip, w * 0.46, 8.0, TRIM)
	m.line(Vector2(-w * 0.23, mid), Vector2(w * 0.23, mid), 3.0, Color(0.1, 0.1, 0.16, 0.4))
	_porthole(m, Vector2(0.0, shoulder - h * 0.2), 20.0)
	_porthole(m, Vector2(-w * 0.33, -drum * 0.36), 9.0)
	_porthole(m, Vector2(w * 0.33, -drum * 0.36), 9.0)
	# A short plain spike on the tip. (Not a crossbar: in silhouette that read as a steeple's cross.)
	m.fill(PackedVector2Array([Vector2(-4.0, tip + 3.0), Vector2(0.0, tip - 18.0), Vector2(4.0, tip + 3.0)]), STEEL)


## The capsule's landing legs: splayed struts with flat pads.
static func paint_legs(m: MeshBatch2D, w: float) -> void:
	for s in [-1.0, 1.0]:
		var hip := Vector2(s * w * 0.44, -18.0)
		var foot := Vector2(s * (w * 0.5 + 44.0), 52.0)
		m.line(hip, foot, 8.0, STEEL.lightened(0.15))
		m.line(hip + Vector2(0, 26.0), foot + Vector2(-s * 12.0, -18.0), 5.0, STEEL)
		m.rect(Rect2(foot.x - 22.0, foot.y - 2.0, 44.0, 8.0), STEEL.darkened(0.15))
