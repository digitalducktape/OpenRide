class_name KeepyRig
extends Node2D
## Keepy Uppy's built things (#77, 2D; ART_BIBLE.md §3 and §5): the hero pedal fan (a pine crate
## with brass corner brackets and rivets, a brass grille over four turning blades, a drive pulley),
## its rails, the height pole painted in the three
## bands with its streamers, and the column of air the fan blows. Every shape goes through
## `MeshBatch2D` (one draw call a layer) and is drawn once per place; per frame only the fan's x, the
## blades' rotation and the column's two uniforms change.
##
## Layers, back to front: Pole, Streamers (sway shader), Rails, Fan (its Column, Crate, Bowl,
## Blades, Grille), HeightMarker. The balloon is drawn between this and the foreground (`KeepyUppy`).

const PLANK := Color("c9a577")
const PLANK_DARK := Color("8a6a44")
const BRASS := Color("d9a441")
const IRON := Color("2b2a2e")
const TOP_DEPTH := 46.0  ## the crate's top face, from the grille's centre to its front edge
const SHADOW_BELOW := 46.0  ## the feet, rails and ground shadow reach this far under the crate
const BLADE_SPIN := 34.0  ## radians a second at a power of FTP
const COLUMN_W := 420.0

var fan: Node2D
var crate: Node2D
var blades: Node2D
var blade_spin: Node2D
var grille: Node2D
var shadow: Node2D
var column: ColorRect
var pole: Node2D
var streamers: Node2D
var rails: Node2D
var marker: Node2D
var place_index := 0
var _blade_angle := 0.0


func _init() -> void:
	pole = _layer("Pole", _paint_pole, self)
	streamers = _layer("Streamers", _paint_streamers, self)
	var sway := ShaderMaterial.new()
	sway.shader = preload("res://games/keepy_uppy/shaders/keepy_sway.gdshader")
	sway.set_shader_parameter("amount", 10.0)
	sway.set_shader_parameter("flutter", 7.0)
	streamers.material = sway
	rails = _layer("Rails", _paint_rails, self)
	fan = Node2D.new()
	fan.name = "Fan"
	fan.position = Vector2(KeepyPlaces.FAN_AT.x, 0)
	add_child(fan)
	column = ColorRect.new()
	column.name = "Column"
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.position = Vector2(-COLUMN_W * 0.5, KeepyPlaces.BALLOON_HIGH - 260.0)
	column.size = Vector2(COLUMN_W, KeepyPlaces.FAN_AT.y - column.position.y)
	var cm := ShaderMaterial.new()
	cm.shader = preload("res://games/keepy_uppy/shaders/keepy_column.gdshader")
	column.material = cm
	fan.add_child(column)
	crate = _layer("Crate", _paint_crate, fan)
	blades = Node2D.new()
	blades.name = "Bowl"
	blades.position = Vector2(0, KeepyPlaces.FAN_AT.y + 4)
	blades.scale = Vector2(1.0, KeepyPlaces.GRILLE.y / KeepyPlaces.GRILLE.x)
	fan.add_child(blades)
	blade_spin = _layer("Blades", _paint_blades, blades)
	grille = _layer("Grille", _paint_grille, fan)
	# The balloon's shadow on the grille: darker and tighter the lower it flies.
	shadow = _layer("BalloonShadow", func(ci: CanvasItem) -> void:
		var m := MeshBatch2D.new()
		m.glow(Vector2.ZERO, Vector2(110, 26), Color(0, 0, 0, 0.55), 8)
		m.flush(ci), fan)
	shadow.position = Vector2(0, KeepyPlaces.FAN_AT.y - 4.0)
	# The balloon's height on the pole: a small coral pointer beside the bands.
	marker = _layer("HeightMarker", func(ci: CanvasItem) -> void:
		var m := MeshBatch2D.new()
		m.fill(PackedVector2Array([Vector2(-26, -13), Vector2(0, 0), Vector2(-26, 13)]), Color("12233a"))
		m.fill(PackedVector2Array([Vector2(-22, -8), Vector2(-5, 0), Vector2(-22, 8)]), KeepyBalloon.CORAL)
		m.flush(ci), self)
	marker.position = Vector2(KeepyPlaces.POLE_X - 10.0, KeepyPlaces.BALLOON_LOW)


func _layer(layer_name: String, paint: Callable, parent: Node) -> Node2D:
	var l := PaintLayer.new()
	l.name = layer_name
	l.paint = paint
	parent.add_child(l)
	return l


func set_place(index: int) -> void:
	place_index = index
	for l in [pole, streamers, rails, crate, blade_spin, grille]:
		l.queue_redraw()


## The rig's state: the fan's rail offset (metres), its power as a share of FTP (the blades),
## the column's strength (0-1) and climb speed, the gust (0-1, the streamers) and the wind.
func update(delta: float, fan_x_m: float, power_share: float, strength: float, climb: float, gust: float, wind: float) -> void:
	fan.position.x = KeepyPlaces.FAN_AT.x + clampf(fan_x_m, -KeepyPlaces.X_SHOWN, KeepyPlaces.X_SHOWN) * KeepyPlaces.PX_PER_M
	_blade_angle = fmod(_blade_angle + delta * clampf(power_share, 0.0, 1.5) * BLADE_SPIN, TAU)
	blade_spin.rotation = _blade_angle
	var cm := column.material as ShaderMaterial
	cm.set_shader_parameter("strength", strength)
	cm.set_shader_parameter("speed", climb)
	var sm := streamers.material as ShaderMaterial
	sm.set_shader_parameter("gust", gust)
	sm.set_shader_parameter("wind", wind)


## The balloon's shadow on the grille for its height `h` (0-1, -1 when there is no balloon)
## and its offset from the fan's centre in px.
func set_shadow(h: float, dx: float) -> void:
	shadow.visible = h >= 0.0 and h < 0.6
	if shadow.visible:
		var k := 1.0 - h / 0.6
		shadow.modulate.a = k
		shadow.scale = Vector2.ONE * lerpf(1.4, 0.8, k)
		shadow.position.x = clampf(dx, -KeepyPlaces.GRILLE.x, KeepyPlaces.GRILLE.x)


static func pulley_y() -> float:
	return KeepyPlaces.FAN_AT.y + TOP_DEPTH + KeepyPlaces.CRATE_H * 0.55


## The crate's rect (front face) in the fan's space (x centred on 0).
static func front_rect() -> Rect2:
	var top := KeepyPlaces.FAN_AT.y + TOP_DEPTH
	return Rect2(-KeepyPlaces.CRATE_W * 0.5, top, KeepyPlaces.CRATE_W, KeepyPlaces.CRATE_H)


## The whole rig's on-screen bounds at a rail offset (for the frame check).
static func bounds(fan_x_m: float) -> Rect2:
	var x := KeepyPlaces.FAN_AT.x + clampf(fan_x_m, -KeepyPlaces.X_SHOWN, KeepyPlaces.X_SHOWN) * KeepyPlaces.PX_PER_M
	var r := front_rect()
	var top := KeepyPlaces.FAN_AT.y - TOP_DEPTH
	return Rect2(x + r.position.x - 10.0, top, r.size.x + 20.0, r.end.y + SHADOW_BELOW - top)


func _shade() -> Callable:
	var dir := KeepyPlaces.to_sun(place_index)
	var half := Vector2(KeepyPlaces.CRATE_W * 0.5, KeepyPlaces.CRATE_H)
	return func(p: Vector2, c: Color) -> Color:
		var n := Vector2(p.x / half.x, (p.y - KeepyPlaces.FAN_AT.y) / half.y)
		var f := 0.07 * n.dot(dir) - 0.05 * clampf(n.y - 0.5, 0.0, 1.0)
		return Color(c.r + f, c.g + f, c.b + f * 0.8, c.a)


func _paint_crate(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var pl := KeepyPlaces.place(place_index)
	var sun_col: Color = pl.sun_col
	var r := front_rect()
	var gy := KeepyPlaces.FAN_AT.y
	var hw := KeepyPlaces.CRATE_W * 0.5
	# A soft contact shadow on the ground, away from the sun.
	var away := -KeepyPlaces.to_sun(place_index)
	m.glow(Vector2(away.x * 60.0, r.end.y + 14.0), Vector2(hw + 90.0, 30.0), Color(0, 0, 0, 0.55), 10)
	m.shade = _shade()
	# Feet on the rails.
	for x in [-hw + 26.0, hw - 26.0]:
		m.round_rect(Rect2(x - 22, r.end.y - 6, 44, 20), 5.0, PLANK_DARK.darkened(0.3))
	# The front face: five planks with grain and gaps.
	var planks := 5
	var ph := r.size.y / planks
	for k in planks:
		var pr := Rect2(r.position.x, r.position.y + k * ph, r.size.x, ph - 3.0)
		var tone := PLANK.darkened(0.04 * (k % 2)).lerp(PLANK_DARK, 0.12 * k / planks)
		m.rect_v(pr, tone.lightened(0.06), tone.darkened(0.08))
		var rng := RandomNumberGenerator.new()
		rng.seed = 77 + k
		for g in 5:
			var y := pr.position.y + rng.randf_range(5.0, ph - 7.0)
			var x0 := pr.position.x + rng.randf_range(0.0, 120.0)
			m.line(Vector2(x0, y), Vector2(x0 + rng.randf_range(80.0, 200.0), y + rng.randf_range(-1.5, 1.5)), 1.6, Color(PLANK_DARK, 0.35))
		m.rect(Rect2(pr.position.x, pr.end.y, pr.size.x, 3.0), Color(0.25, 0.17, 0.1, 0.7))
	# Cross braces on the front (a shipping crate's X, behind the brackets), a plinth board at the
	# foot and a light bevel along the top edge: weight, as GFX_POLISH item 1 asks.
	var brace := PLANK_DARK.lightened(0.08)
	for d in [[Vector2(r.position.x + 30, r.position.y + 10), Vector2(r.end.x - 30, r.end.y - 10)],
			[Vector2(r.end.x - 30, r.position.y + 10), Vector2(r.position.x + 30, r.end.y - 10)]]:
		m.line(d[0] + Vector2(2, 4), d[1] + Vector2(2, 4), 18.0, Color(0.2, 0.13, 0.07, 0.35))
		m.line(d[0], d[1], 16.0, brace)
		m.line(d[0] + Vector2(0, -5), d[1] + Vector2(0, -5), 2.5, brace.lightened(0.25))
	m.rect_v(Rect2(r.position.x - 6, r.end.y - 16, r.size.x + 12, 18), PLANK_DARK, PLANK_DARK.darkened(0.35))
	m.rect(Rect2(r.position.x, r.position.y, r.size.x, 4), PLANK.lightened(0.3))
	# The top face: a lighter board frame round the grille, in perspective.
	var back := gy - TOP_DEPTH
	var front := gy + TOP_DEPTH
	m.quad4(Vector2(-hw + 22, back), Vector2(hw - 22, back), Vector2(hw, front), Vector2(-hw, front),
		PLANK.lightened(0.1), PLANK.lightened(0.1), PLANK.lightened(0.18), PLANK.lightened(0.18))
	m.line(Vector2(-hw, front), Vector2(hw, front), 4.0, PLANK.lightened(0.35))
	# Brass corner brackets on the front face, each with two rivets.
	for sx in [-1.0, 1.0]:
		for top in [true, false]:
			var y0 := r.position.y if top else r.end.y - 34.0
			var x0 := r.position.x if sx < 0.0 else r.end.x - 34.0
			m.round_rect(Rect2(x0, y0, 34, 34), 4.0, BRASS.lightened(0.15), BRASS.darkened(0.25))
			for d in [Vector2(10, 10), Vector2(24, 24)]:
				var at: Vector2 = Vector2(x0, y0) + (d if sx < 0.0 else Vector2(34.0 - d.x, d.y))
				if not top:
					at.y = y0 + 34.0 - (at.y - y0)
				m.circle(at, 3.6, BRASS.darkened(0.45))
				m.circle(at + Vector2(-0.8, -0.8), 2.2, BRASS.lightened(0.45))
	# A brass maker's plate (blank: no words) and the drive pulley with its hub.
	m.round_rect(Rect2(-60, r.position.y + 14, 120, 26), 6.0, BRASS.lightened(0.2), BRASS.darkened(0.2))
	m.round_rect(Rect2(-52, r.position.y + 19, 104, 16), 4.0, BRASS.darkened(0.12), BRASS.darkened(0.3))
	var pc := Vector2(0, pulley_y())
	m.circle(pc + Vector2(3, 4), 36.0, Color(0, 0, 0, 0.3))
	m.circle(pc, 36.0, IRON)
	m.ring(pc, 26.0, 33.0, IRON.lightened(0.25))
	for k in 6:
		var a := k * TAU / 6.0
		m.line(pc, pc + Vector2(cos(a), sin(a)) * 26.0, 4.0, IRON.lightened(0.15))
	m.circle(pc, 10.0, BRASS)
	m.circle(pc + Vector2(-2, -2), 4.0, BRASS.lightened(0.5))
	# The top face's rim highlight on the sun's side.
	var sd := KeepyPlaces.to_sun(place_index)
	m.glow(Vector2(sd.x * hw * 0.6, front - 4.0), Vector2(hw * 0.5, 8.0), Color(sun_col, 0.22), 6)
	m.flush(ci)


## The dark bowl under the grille, so the blades read against it.
func _paint_blades(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var rx := KeepyPlaces.GRILLE.x - 8.0
	m.circle(Vector2.ZERO, rx, Color(0.08, 0.08, 0.09))
	m.glow(Vector2.ZERO, Vector2(rx, rx), Color(0.25, 0.25, 0.28, 0.6), 8)
	for k in 4:
		var a := k * TAU / 4.0
		var d := Vector2(cos(a), sin(a))
		var n := d.orthogonal()
		var tip := d * (rx - 10.0)
		m.fill(PackedVector2Array([d * 20.0 - n * 14.0, tip - n * 40.0, tip + n * 18.0, d * 20.0 + n * 10.0]), Color(0.86, 0.85, 0.8))
		m.line(d * 22.0 - n * 12.0, tip - n * 38.0, 3.0, Color(0.62, 0.6, 0.56))
	m.circle(Vector2.ZERO, 26.0, BRASS.darkened(0.2))
	m.circle(Vector2.ZERO, 14.0, BRASS.lightened(0.2))
	m.flush(ci)


## The brass grille: a rim ring and spokes, over the turning blades.
func _paint_grille(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var c := Vector2(0.0, KeepyPlaces.FAN_AT.y)  # the fan's own space: x is centred on 0
	var g := KeepyPlaces.GRILLE
	var outline := MeshBatch2D._ellipse(c, g + Vector2(10, 4), 64)
	var inner := MeshBatch2D._ellipse(c, g - Vector2(4, 1), 64)
	m.band(outline, inner, BRASS.darkened(0.15), BRASS.lightened(0.25))
	m.band(MeshBatch2D.grow_outline(outline, MeshBatch2D.FEATHER), outline, Color(BRASS, 0.0), BRASS.darkened(0.15))
	for k in 3:
		var t := 0.35 + k * 0.28
		var ring_o := MeshBatch2D._ellipse(c, g * t, 48)
		var ring_i := MeshBatch2D._ellipse(c, g * t - Vector2(3, 0.8), 48)
		m.band(ring_o, ring_i, Color(BRASS.darkened(0.25), 0.85), Color(BRASS.darkened(0.25), 0.85))
	for k in 12:
		var a := k * TAU / 12.0
		var d := Vector2(cos(a) * g.x, sin(a) * g.y)
		m.line(c + d * 0.12, c + d * 0.98, 2.4, Color(BRASS.darkened(0.3), 0.9))
	m.flush(ci)


func _paint_rails(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var y := KeepyPlaces.FAN_AT.y + TOP_DEPTH + KeepyPlaces.CRATE_H + 6.0
	var span := KeepyPlaces.X_SHOWN * KeepyPlaces.PX_PER_M + KeepyPlaces.CRATE_W * 0.5 + 30.0
	var x0 := KeepyPlaces.FAN_AT.x - span
	var x1 := KeepyPlaces.FAN_AT.x + span
	var k := x0
	while k <= x1:
		m.rect_v(Rect2(k - 10, y - 2, 20, 14), PLANK_DARK.darkened(0.2), PLANK_DARK.darkened(0.45))
		k += 70.0
	for dy in [0.0, 8.0]:
		m.rect_v(Rect2(x0, y + dy - 3.0, x1 - x0, 5.0), Color(0.6, 0.6, 0.62), Color(0.32, 0.32, 0.35))
	m.flush(ci)


## The height pole: a pine post painted in the three bands (cream, mint, sun), a peg at each band
## line, a cap; its foot staked in the ground.
func _paint_pole(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var x := KeepyPlaces.POLE_X
	var w := 18.0
	var foot := KeepyPlaces.FAN_AT.y + TOP_DEPTH + 70.0
	var low := KeepyPlaces.band_y(0.0) + KeepyPlaces.BALLOON_R.y
	var mid := KeepyPlaces.band_y(KeepyLogic.MID_FROM)
	var high := KeepyPlaces.band_y(KeepyLogic.HIGH_FROM)
	var top := KeepyPlaces.POLE_TOP
	m.glow(Vector2(x + 30, foot + 4), Vector2(60, 10), Color(0, 0, 0, 0.3), 6)
	m.rect_h(Rect2(x - w * 0.5, low, w, foot - low), PLANK_DARK.lightened(0.1), PLANK_DARK.darkened(0.3))
	var bands := [[mid, low, KeepyStatus.BAND_COLORS[0]], [high, mid, KeepyStatus.BAND_COLORS[1]], [top, high, KeepyStatus.BAND_COLORS[2]]]
	for b in bands:
		var c: Color = b[2]
		m.rect_h(Rect2(x - w * 0.5, b[0], w, b[1] - b[0]), c.lightened(0.1), c.darkened(0.25))
	for y in [mid, high]:
		m.round_rect(Rect2(x - w * 0.9, y - 4.0, w * 1.8, 8.0), 3.0, PLANK_DARK.darkened(0.2))
	m.circle(Vector2(x, top - 6.0), 13.0, BRASS.darkened(0.1))
	m.circle(Vector2(x - 3.0, top - 9.0), 5.0, BRASS.lightened(0.4))
	m.flush(ci)


## A ribbon at each band line, in the band's colour, flying to the right of the pole, and a
## windsock-orange pennant at the top. UV.x (depth) runs 0 at the pole to 1 at the tip: the sway
## shader's weight.
func _paint_streamers(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var x := KeepyPlaces.POLE_X + 10.0
	var lines := [[KeepyPlaces.band_y(KeepyLogic.MID_FROM), KeepyStatus.BAND_COLORS[1], 96.0, 11.0],
		[KeepyPlaces.band_y(KeepyLogic.HIGH_FROM), KeepyStatus.BAND_COLORS[2], 96.0, 11.0],
		[KeepyPlaces.POLE_TOP + 14.0, Color("ff8c42"), 104.0, 18.0]]
	for line in lines:
		var y: float = line[0]
		var c: Color = line[1]
		var length: float = line[2]
		var half: float = line[3]
		var segs := 8
		for k in segs:
			var t0 := float(k) / segs
			var t1 := float(k + 1) / segs
			var h0 := half * (1.0 - t0 * 0.6)
			var h1 := half * (1.0 - t1 * 0.6)
			var a := Vector2(x + t0 * length, y - h0)
			var b := Vector2(x + t1 * length, y - h1)
			var cc := Vector2(x + t1 * length, y + h1)
			var d := Vector2(x + t0 * length, y + h0)
			var shade := c.darkened(0.12 * (k % 2))
			m.depth = t0
			var i := m.vert(a, shade)
			m.vert(d, shade.darkened(0.1))
			m.depth = t1
			m.vert(b, shade)
			m.vert(cc, shade.darkened(0.1))
			m.tri(i, i + 2, i + 3)
			m.tri(i, i + 3, i + 1)
	m.depth = 0.0
	m.flush(ci)
