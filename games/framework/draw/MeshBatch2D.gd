class_name MeshBatch2D
extends RefCounted
## The code-drawn games' shape batcher (from Safe Cracker, #41; shared since the second wave of
## games). A node adds its shapes here and `flush`es them inside its
## `_draw()` as one `canvas_item_add_triangle_array`: one draw call for the whole room, door or
## dial, with per-vertex colours for the gradients. In the Compatibility renderer every
## `draw_circle`, `draw_colored_polygon` and `draw_arc` is a draw call of its own (the bank's
## 168 rivets were 168), and there is no 2D MSAA, so every filled edge here gets a 1.2 px
## feather to transparent instead.
##
## `shade` (optional) relights every vertex as it is added: (point, colour) -> colour. Keep it
## affine in the point (a directional light), so a fan or a band interpolates it exactly.
## `depth` goes into each vertex's UV.x: the door's shader reads it as depth into the safe (its
## thickness band). Text and textures never pass through here.

const FEATHER := 1.2
const CORNER_SEGS := 8

var points := PackedVector2Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()
var shade := Callable()
var depth := 0.0
## Tests and tools only: called on every flush with (canvas item, points, indices), to count
## rebuilds and measure fill (tests/measure_safe.gd). Never set in the game.
static var probe := Callable()
static var _dot: Texture2D
static var _built := {}  ## key -> MeshBatch2D (`built`)


func clear() -> void:
	points.clear()
	colors.clear()
	uvs.clear()
	indices.clear()
	shade = Callable()
	depth = 0.0


func vertex_count() -> int:
	return points.size()


## Draws everything added so far onto `ci` (call from its `_draw()`), then empties the batch.
func flush(ci: CanvasItem) -> void:
	draw_on(ci)
	clear()


## Draws the batch onto `ci` (call from its `_draw()`) and keeps it, for a batch drawn again.
func draw_on(ci: CanvasItem) -> void:
	if probe.is_valid():
		probe.call(ci, points, indices)
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(ci.get_canvas_item(), indices, points, colors, uvs)


## A batch built once by `build` (a Callable taking the MeshBatch2D) and kept under `key`: a
## place's room and body are built in GDScript (the bank's room is 27k vertices, ~11 ms on the
## desktop and several times that on the tablet), so they're built once per place and can be
## built ahead (`SafeCracker` does it while a cracked door stands open), not on the frame the
## next safe slides in. A few MB for all six places.
static func built(key: String, build: Callable) -> MeshBatch2D:
	var m: MeshBatch2D = _built.get(key)
	if m == null:
		m = MeshBatch2D.new()
		build.call(m)
		_built[key] = m
	return m


static func is_built(key: String) -> bool:
	return _built.has(key)


## Drops every kept batch (tests).
static func forget_built() -> void:
	_built.clear()


func vert(p: Vector2, c: Color) -> int:
	points.append(p)
	colors.append(shade.call(p, c) if shade.is_valid() else c)
	uvs.append(Vector2(depth, 0.0))
	return points.size() - 1


func tri(a: int, b: int, c: int) -> void:
	indices.append(a)
	indices.append(b)
	indices.append(c)


func quad4(a: Vector2, b: Vector2, c: Vector2, d: Vector2, ca: Color, cb: Color, cc: Color, cd: Color) -> void:
	var i := vert(a, ca)
	vert(b, cb)
	vert(c, cc)
	vert(d, cd)
	tri(i, i + 1, i + 2)
	tri(i, i + 2, i + 3)


func quad(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color) -> void:
	quad4(a, b, c, d, col, col, col, col)


func rect(r: Rect2, col: Color) -> void:
	quad(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), col)


## A rect shading from `top` to `bottom`.
func rect_v(r: Rect2, top: Color, bottom: Color) -> void:
	quad4(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), top, top, bottom, bottom)


## A rect shading from `left` to `right`.
func rect_h(r: Rect2, left: Color, right: Color) -> void:
	quad4(r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y), left, right, right, left)


## A straight stroke `w` wide, feathered along both long sides.
func line(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized().orthogonal()
	var h := maxf(w * 0.5 - FEATHER * 0.5, 0.1)
	var o := n * h
	var f := n * (h + FEATHER)
	var clear_col := Color(col, 0.0)
	quad(a - o, b - o, b + o, a + o, col)
	quad4(a + o, b + o, b + f, a + f, col, col, clear_col, clear_col)
	quad4(a - f, b - f, b - o, a - o, clear_col, clear_col, col, col)


## A closed convex outline, filled with a fan from its centroid (or `center`), feathered.
func fill(outline: PackedVector2Array, col: Color, feather := true) -> void:
	var c := Vector2.ZERO
	for p in outline:
		c += p
	c /= outline.size()
	var ci := vert(c, col)
	var first := points.size()
	for p in outline:
		vert(p, col)
	var n := outline.size()
	for k in n:
		tri(ci, first + k, first + (k + 1) % n)
	if feather:
		band(outline, grow_outline(outline, FEATHER), col, Color(col, 0.0))


## Joins two closed outlines with the same vertex count with a band of quads, `ca` on the first
## and `cb` on the second (a bevel, a feather, a soft shadow, a ring).
func band(a: PackedVector2Array, b: PackedVector2Array, ca: Color, cb: Color, closed := true) -> void:
	var n := a.size()
	var first := points.size()
	for k in n:
		vert(a[k], ca)
		vert(b[k], cb)
	var last := n if closed else n - 1
	for k in last:
		var i := first + 2 * k
		var j := first + 2 * ((k + 1) % n)
		tri(i, j, j + 1)
		tri(i, j + 1, i + 1)


## The same band with a colour per vertex on each outline.
func band_colors(a: PackedVector2Array, b: PackedVector2Array, ca: PackedColorArray, cb: PackedColorArray, closed := true) -> void:
	var n := a.size()
	var first := points.size()
	for k in n:
		vert(a[k], ca[k])
		vert(b[k], cb[k])
	var last := n if closed else n - 1
	for k in last:
		var i := first + 2 * k
		var j := first + 2 * ((k + 1) % n)
		tri(i, j, j + 1)
		tri(i, j + 1, i + 1)


func circle(center: Vector2, r: float, col: Color, feather := true) -> void:
	fill(circle_outline(center, r), col, feather)


## An annulus (or an arc of one, `from`-`to` radians) between radii `r0` and `r1`, feathered.
func ring(center: Vector2, r0: float, r1: float, col: Color, from := 0.0, to := TAU) -> void:
	var full := is_equal_approx(absf(to - from), TAU)
	var segs := segments_for(r1, absf(to - from))
	var inner := arc_points(center, r0, from, to, segs)
	var outer := arc_points(center, r1, from, to, segs)
	band(inner, outer, col, col, full)
	var clear_col := Color(col, 0.0)
	band(outer, arc_points(center, r1 + FEATHER, from, to, segs), col, clear_col, full)
	if r0 > FEATHER:
		band(arc_points(center, r0 - FEATHER, from, to, segs), inner, clear_col, col, full)


## A soft round pool of light (or shadow): `col` at the centre fading smoothly to nothing at
## `radius` (a Vector2 for an ellipse). Many rings, so the falloff never bands. `hollow` (px)
## leaves out the rings inside that radius, for a pool whose middle something opaque covers.
func glow(center: Vector2, radius: Vector2, col: Color, rings := 14, hot := 0.0, hollow := 0.0) -> void:
	rings = maxi(rings, int(maxf(radius.x, radius.y) / 36.0))
	var segs := 48
	var prev := PackedVector2Array()
	var prev_col := col
	for i in range(1, rings + 1):
		var t := float(i) / rings
		var c := Color(col, col.a * (1.0 - smoothstep(hot, 1.0, t)))
		var cur := _ellipse(center, radius * t, segs)
		if hollow > 0.0 and maxf(radius.x, radius.y) * t <= hollow:
			pass  # covered: skip it, but keep it as the next band's inner edge
		elif i == 1:
			var ci := vert(center, col)
			var first := points.size()
			for p in cur:
				vert(p, c)
			for k in segs:
				tri(ci, first + k, first + (k + 1) % segs)
		else:
			band(prev, cur, prev_col, c)
		prev = cur
		prev_col = c


## A rounded rect, shading top to bottom, feathered.
func round_rect(r: Rect2, radius: float, top: Color, bottom := Color(0, 0, 0, -1)) -> void:
	var outline := round_rect_outline(r, radius)
	if bottom.a < 0.0:
		fill(outline, top)
		return
	var cols := PackedColorArray()
	for p in outline:
		cols.append(top.lerp(bottom, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0)))
	var c := r.get_center()
	var ci := vert(c, top.lerp(bottom, 0.5))
	var first := points.size()
	for k in outline.size():
		vert(outline[k], cols[k])
	var n := outline.size()
	for k in n:
		tri(ci, first + k, first + (k + 1) % n)
	var clear := PackedColorArray()
	for col in cols:
		clear.append(Color(col, 0.0))
	band_colors(outline, grow_outline(outline, FEATHER), cols, clear)


## A rounded rect shading top to bottom, feathered, with a round hole of radius `hole_r` at
## `hole` (inside it): for a slab under an opaque disc (the door under its dial). The hole's
## edge is a polygon on rays through the outline's points, inside that circle.
func holed_round_rect(r: Rect2, radius: float, top: Color, bottom: Color, hole: Vector2, hole_r: float) -> void:
	var outline := round_rect_outline(r, radius)
	var inner := PackedVector2Array()
	var cols := PackedColorArray()
	var icols := PackedColorArray()
	var clear := PackedColorArray()
	for p in outline:
		var q := hole + (p - hole).normalized() * hole_r
		inner.append(q)
		var c := top.lerp(bottom, clampf((p.y - r.position.y) / r.size.y, 0.0, 1.0))
		cols.append(c)
		clear.append(Color(c, 0.0))
		icols.append(top.lerp(bottom, clampf((q.y - r.position.y) / r.size.y, 0.0, 1.0)))
	band_colors(outline, inner, cols, icols)
	band_colors(outline, grow_outline(outline, FEATHER), cols, clear)


## A bevel `width` wide just inside a rounded rect's edge: bright where the edge faces the
## light (`to_light`, a unit vector), dark where it faces away, blending round the corners.
func bevel(r: Rect2, radius: float, width: float, to_light: Vector2, hi: Color, lo: Color) -> void:
	var outer := round_rect_outline(r, radius)
	var inner := round_rect_outline(r.grow(-width), maxf(radius - width, 1.0))
	var cols := PackedColorArray()
	var clear := PackedColorArray()
	var normals := outline_normals(outer)
	for k in outer.size():
		var c := lo.lerp(hi, clampf(0.5 + 0.75 * normals[k].dot(to_light), 0.0, 1.0))
		cols.append(c)
		clear.append(Color(c, 0.0))
	band_colors(outer, inner, cols, cols)
	band_colors(inner, grow_outline(inner, -FEATHER), cols, clear)


## A soft shadow under a rounded rect: `col` inside, fading to nothing over `size` outside.
## `hollow` > 0 leaves out the middle, all but a rim that wide inside the solid part: for a
## shadow under something opaque that covers its middle (the tablet pays for every pixel).
func soft_shadow(r: Rect2, radius: float, size: float, col: Color, hollow := 0.0) -> void:
	var inner := round_rect_outline(r.grow(-size * 0.5), radius)
	if hollow > 0.0:
		band(round_rect_outline(r.grow(-size * 0.5 - hollow), maxf(radius - hollow, 2.0)), inner, col, col)
	else:
		fill(inner, col, false)
	band(inner, round_rect_outline(r.grow(size), radius + size * 1.5), col, Color(col, 0.0))


## A rounded frame: the rounded rect `outer` less the rounded rect `inner` (inside it), shading
## top to bottom over `outer`, feathered on the outside only (what sits in the hole covers the
## inner edge). A slab with a hole is cheaper than a slab under what covers it.
func round_frame(outer: Rect2, outer_radius: float, inner: Rect2, inner_radius: float, top: Color, bottom: Color) -> void:
	var a := round_rect_outline(outer, outer_radius)
	var b := round_rect_outline(inner, inner_radius)
	var ca := PackedColorArray()
	var cb := PackedColorArray()
	var clear := PackedColorArray()
	for k in a.size():
		var c := top.lerp(bottom, clampf((a[k].y - outer.position.y) / outer.size.y, 0.0, 1.0))
		ca.append(c)
		clear.append(Color(c, 0.0))
		cb.append(top.lerp(bottom, clampf((b[k].y - outer.position.y) / outer.size.y, 0.0, 1.0)))
	band_colors(a, b, ca, cb)
	band_colors(a, grow_outline(a, FEATHER), ca, clear)


static func segments_for(r: float, span := TAU) -> int:
	return clampi(int(r * span / 9.0), 10, 96)


static func circle_outline(center: Vector2, r: float) -> PackedVector2Array:
	return _ellipse(center, Vector2(r, r), segments_for(r))


static func _ellipse(center: Vector2, radius: Vector2, segs: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(segs)
	for k in segs:
		var a := TAU * k / segs
		out[k] = center + Vector2(cos(a) * radius.x, sin(a) * radius.y)
	return out


static func arc_points(center: Vector2, r: float, from: float, to: float, segs: int) -> PackedVector2Array:
	var full := is_equal_approx(absf(to - from), TAU)
	var n := segs if full else segs + 1
	var out := PackedVector2Array()
	out.resize(n)
	for k in n:
		var a := from + (to - from) * k / segs
		out[k] = center + Vector2(cos(a), sin(a)) * r
	return out


## A rounded rect's outline, clockwise from the top-left corner, CORNER_SEGS + 1 points a corner
## (so two outlines of the same shape always pair up for `band`).
static func round_rect_outline(r: Rect2, radius: float) -> PackedVector2Array:
	var rad := clampf(radius, 0.0, minf(r.size.x, r.size.y) * 0.5)
	var centers := [r.position + Vector2(rad, rad), Vector2(r.end.x - rad, r.position.y + rad),
		r.end - Vector2(rad, rad), Vector2(r.position.x + rad, r.end.y - rad)]
	var out := PackedVector2Array()
	for c in 4:
		var start := PI + c * PI / 2.0
		for k in CORNER_SEGS + 1:
			var a := start + (PI / 2.0) * k / CORNER_SEGS
			out.append(centers[c] + Vector2(cos(a), sin(a)) * rad)
	return out


## Outward unit normals of a closed clockwise (screen space, y down) outline.
static func outline_normals(outline: PackedVector2Array) -> PackedVector2Array:
	var n := outline.size()
	var out := PackedVector2Array()
	out.resize(n)
	for k in n:
		var prev := outline[(k - 1 + n) % n]
		var next := outline[(k + 1) % n]
		var t := next - prev
		if t.length_squared() < 0.000001:
			t = next - outline[k]
		out[k] = Vector2(t.y, -t.x).normalized()
	return out


## The outline pushed `by` along its normals (negative: inward).
static func grow_outline(outline: PackedVector2Array, by: float) -> PackedVector2Array:
	var normals := outline_normals(outline)
	var out := PackedVector2Array()
	out.resize(outline.size())
	for k in outline.size():
		out[k] = outline[k] + normals[k] * by
	return out


# --- Shared shapes and textures ---

## A domed rivet: a dark ring, the dome, a highlight toward the light.
static func rivet(m: MeshBatch2D, at: Vector2, r: float, colour: Color, dir: Vector2) -> void:
	m.circle(at + Vector2(1.5, 2.5), r, Color(0, 0, 0, 0.35))
	m.circle(at, r, colour.darkened(0.45))
	m.circle(at, r * 0.72, colour.lightened(0.12))
	m.circle(at + dir * r * 0.3, r * 0.3, colour.lightened(0.6))


## A soft white dot (32 px, radial), shared by the dust and the sparkles.
static func soft_dot() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		g.add_point(0.35, Color(1, 1, 1, 0.75))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		t.width = 32
		t.height = 32
		_dot = t
	return _dot


## A ring whose colour follows its normal: `hi` facing the light, `lo` away.
static func lit_ring(m: MeshBatch2D, c: Vector2, r0: float, r1: float, hi: Color, lo: Color, to_light: Vector2) -> void:
	var segs := segments_for(r1)
	var inner := arc_points(c, r0, 0.0, TAU, segs)
	var outer := arc_points(c, r1, 0.0, TAU, segs)
	var cols := PackedColorArray()
	var clear := PackedColorArray()
	for k in segs:
		var a := TAU * k / segs
		var col := lo.lerp(hi, clampf(0.5 + 0.7 * Vector2(cos(a), sin(a)).dot(to_light), 0.0, 1.0))
		cols.append(col)
		clear.append(Color(col, 0.0))
	m.band_colors(inner, outer, cols, cols)
	m.band_colors(outer, arc_points(c, r1 + FEATHER, 0.0, TAU, segs), cols, clear)
