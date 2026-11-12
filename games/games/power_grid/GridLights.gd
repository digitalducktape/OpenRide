class_name GridLights
extends RefCounted
## The town's lights as one mesh (#81; ART_BIBLE.md §7). Every window, lamp, bulb and beam is a few
## vertices whose UV carries its channel and its turn: UV.x = channel + threshold, UV.y = seed.
## `grid_lights.gdshader` reads them against four uniform levels, so a district coming on window by
## window, or a brown-out dropping lights one by one, costs one uniform a frame and no redraw.
## MeshBatch2D can't be used here: every vertex of one light must share one UV, and a light has no
## feather (they're additive and soft already).
##
## Seeds: 0-1 twinkles slowly; 2 and up is a chasing bulb (2.0, 2.25, 2.5, 2.75 are its four phases).

const CIRCLE_SEGS := 10
const BULB_SEGS := 8

var points := PackedVector2Array()
var colors := PackedColorArray()
var uvs := PackedVector2Array()
var indices := PackedInt32Array()


func _uv(channel: int, threshold: float, seed_value: float) -> Vector2:
	return Vector2(channel + clampf(threshold, 0.0, 0.99), seed_value)


func _vert(p: Vector2, c: Color, uv: Vector2) -> int:
	points.append(p)
	colors.append(c)
	uvs.append(uv)
	return points.size() - 1


## A flat lit rectangle.
func rect(r: Rect2, col: Color, channel: int, threshold: float, seed_value: float) -> void:
	var uv := _uv(channel, threshold, seed_value)
	var a := _vert(r.position, col, uv)
	var b := _vert(r.position + Vector2(r.size.x, 0), col, uv)
	var c := _vert(r.end, col, uv)
	var d := _vert(r.position + Vector2(0, r.size.y), col, uv)
	indices.append_array(PackedInt32Array([a, b, c, a, c, d]))


## A soft pool: `col` at the centre fading to nothing at `radius`.
func glow(center: Vector2, radius: Vector2, col: Color, channel: int, threshold: float, seed_value: float) -> void:
	var uv := _uv(channel, threshold, seed_value)
	var hub := _vert(center, col, uv)
	var mid_col := Color(col, col.a * 0.32)
	var clear := Color(col, 0.0)
	var mid := points.size()
	for k in CIRCLE_SEGS:
		var a := TAU * k / CIRCLE_SEGS
		_vert(center + Vector2(cos(a), sin(a)) * radius * 0.45, mid_col, uv)
	var rim := points.size()
	for k in CIRCLE_SEGS:
		var a := TAU * k / CIRCLE_SEGS
		_vert(center + Vector2(cos(a), sin(a)) * radius, clear, uv)
	for k in CIRCLE_SEGS:
		var n := (k + 1) % CIRCLE_SEGS
		indices.append_array(PackedInt32Array([hub, mid + k, mid + n, mid + k, rim + k, rim + n, mid + k, rim + n, mid + n]))


## A bulb: a solid bright core of radius `r` and a halo. One fan: a soft glow alone leaves a bulb
## too faint to read as a lamp at this size.
func bulb(center: Vector2, r: float, col: Color, channel: int, threshold: float, seed_value: float) -> void:
	var uv := _uv(channel, threshold, seed_value)
	var hot := Color(col.lerp(Color.WHITE, 0.6), 1.0)
	var hub := _vert(center, hot, uv)
	var core := points.size()
	var halo := core + BULB_SEGS
	var rim := halo + BULB_SEGS
	for k in BULB_SEGS:
		_vert(center + Vector2.from_angle(TAU * k / BULB_SEGS) * r, hot, uv)
	for k in BULB_SEGS:
		_vert(center + Vector2.from_angle(TAU * k / BULB_SEGS) * r * 1.5, Color(col, 0.55), uv)
	for k in BULB_SEGS:
		_vert(center + Vector2.from_angle(TAU * k / BULB_SEGS) * r * 3.6, Color(col, 0.0), uv)
	for k in BULB_SEGS:
		var n := (k + 1) % BULB_SEGS
		indices.append_array(PackedInt32Array([hub, core + k, core + n, core + k, halo + k, halo + n, core + k, halo + n, core + n,
			halo + k, rim + k, rim + n, halo + k, rim + n, halo + n]))


## A beam of light: bright along a-b, fading to nothing along d-c.
func beam(a: Vector2, b: Vector2, c: Vector2, d: Vector2, col: Color, channel: int, threshold: float, seed_value: float) -> void:
	var uv := _uv(channel, threshold, seed_value)
	var clear := Color(col, 0.0)
	var i := _vert(a, col, uv)
	var j := _vert(b, col, uv)
	var k := _vert(c, clear, uv)
	var l := _vert(d, clear, uv)
	indices.append_array(PackedInt32Array([i, j, k, i, k, l]))


## The finished mesh.
func mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## A strip along `pts`, `width` wide, for the wires: UV.x is the length along it and UV.y the
## channel (`grid_wires.gdshader`). Added to `into`, a GridLights used only for its arrays.
func strip(pts: PackedVector2Array, width: float, channel: int) -> void:
	var run := 0.0
	var prev := -1
	for k in pts.size():
		if k > 0:
			run += pts[k].distance_to(pts[k - 1])
		var dir := (pts[mini(k + 1, pts.size() - 1)] - pts[maxi(k - 1, 0)]).normalized().orthogonal() * width * 0.5
		var a := _vert(pts[k] + dir, Color.WHITE, Vector2(run, channel))
		var b := _vert(pts[k] - dir, Color.WHITE, Vector2(run, channel))
		if prev >= 0:
			indices.append_array(PackedInt32Array([prev, prev + 1, b, prev, b, a]))
		prev = a
