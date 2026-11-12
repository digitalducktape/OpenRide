class_name WattLaneTrack
extends Node2D
## Watt Lane's lane and cursor (#78; ART_BIBLE.md): an illuminated horizontal band that comes in
## from the right `SPEED` px a second (the course's future) and steps up or down, and a chevron
## cursor (▶) at RIDER_X whose height is your smoothed power (`y_of`: more watts, higher). An
## announced step shows its riser, amber chevrons and its new bounds in watts where it lands.
## Behind the cursor, the dashed path it rode.
##
## It only draws: `WattLaneLogic` holds the rules. Cost (the tablet is fill-bound): the lane is a
## strip mesh over just the lane and its glow, its light worked out per vertex from 64-column
## arrays (`shaders/wl_lane.gdshader`), one texture read a pixel; the path a thin strip
## (`wl_path.gdshader`); the beam, the riser, the step's chevrons and the cursor are small static
## drawings moved by `position`; one CPUParticles2D for a catch.

const RIDER_X := 520.0  ## the cursor's x on the stage
const SPEED := 150.0  ## px a second: course time ahead is distance to the right
const COLS := 64
const GUIDE_TOP := 400.0  ## the watt scale's guides, one every 12.5% of FTP
const GUIDE_GAP := 110.0
const MID_Y := 620.0  ## the middle guide
const MID_SHARE := 0.60  ## the share of FTP at the middle guide
const PX_PER_FTP := GUIDE_GAP / 0.125
const TOP_Y := 372.0  ## the cursor stays between these (clear of the HUD's top bar)
const BOTTOM_Y := 960.0
const HIST_DT := 0.05  ## seconds between the path's samples
const HIST := 90
const CURSOR_EASE := 12.0
const SHADER := preload("res://games/watt_lane/shaders/wl_lane.gdshader")
const PATH_SHADER := preload("res://games/watt_lane/shaders/wl_path.gdshader")
const TILE := 512.0  ## WattLaneBackdrop.TILE
const STREAK_SPEED := 1.8  ## of the lane's speed
## The strip's rows: (t, off): y = mix(hi, lo, t) + off px. Packed around the edges, so the light
## worked out per vertex stays crisp; the outer rows carry the wide glow.
const ROWS: Array[Vector2] = [Vector2(0, -110), Vector2(0, -70), Vector2(0, -40), Vector2(0, -20), Vector2(0, -9),
	Vector2(0, -4), Vector2(0, -2.6), Vector2(0, -1.2), Vector2(0, 0), Vector2(0, 1.2), Vector2(0, 2.6), Vector2(0, 4),
	Vector2(0, 9), Vector2(0, 20), Vector2(0.25, 0), Vector2(0.5, 0), Vector2(0.75, 0), Vector2(1, -20), Vector2(1, -9),
	Vector2(1, -4), Vector2(1, -2.6), Vector2(1, -1.2), Vector2(1, 0), Vector2(1, 1.2), Vector2(1, 2.6), Vector2(1, 4),
	Vector2(1, 9), Vector2(1, 20), Vector2(1, 40), Vector2(1, 70), Vector2(1, 110)]
const MARKS := 3  ## the step's chevrons
const MARK_GAP := 70.0
const MARK_FIRST := 175.0  ## px before the step: the nearest mark stops short of the bend
const INK := Color("0f1a2e")
const WARN_LIGHT := Color(1.0, 0.69, 0.13)

var ftp := 150.0
var width_watts := 40
var cursor: Node2D
var label: Label  ## the announced step's new bounds, 56 px, just inside the new lane
var cursor_y := MID_Y
var flash := 0.0
var lane: MeshInstance2D
var scroll := 0.0  ## px the lane has moved (the backdrop's layers follow it)

var _mat: ShaderMaterial
var _path_mat: ShaderMaterial
var _path: MeshInstance2D
var _beam: Node2D
var _riser: Sprite2D
var _marks: Array[Node2D] = []
var _lo := PackedFloat32Array()
var _hi := PackedFloat32Array()
var _trail := PackedFloat32Array()
var _hist := PackedFloat32Array()
var _hist_left := 0.0
var _x0 := -68.0
var _dx := 33.0
var _cursor_paint: Node2D
var _cursor_glow: Sprite2D
var _state := ""
var _clock := 0.0
var _glow := 1.0
var _in := 1.0
var _label_bounds := Vector2i(-1, -1)
var _burst: CPUParticles2D


func _init() -> void:
	_lo.resize(COLS)
	_hi.resize(COLS)
	_trail.resize(COLS)
	_hist.resize(HIST)
	_hist.fill(-1.0)
	_trail.fill(-1.0)
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("rider_x", RIDER_X)
	lane = MeshInstance2D.new()
	lane.name = "Lane"
	lane.mesh = lane_mesh()
	lane.material = _mat
	_path_mat = ShaderMaterial.new()
	_path_mat.shader = PATH_SHADER
	_path_mat.set_shader_parameter("rider_x", RIDER_X)
	_path = MeshInstance2D.new()
	_path.name = "Path"
	_path.mesh = path_mesh()
	_path.material = _path_mat
	_build_step_marks()
	_build_cursor()
	label = Label.new()
	label.name = "NextBand"
	label.visible = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst = _make_burst()


func _ready() -> void:
	add_child(lane)
	add_child(_path)
	add_child(_beam)
	add_child(_riser)
	for m in _marks:
		add_child(m)
	# The meshes hold (column, row) until their vertex shaders place them: never cull them.
	for mesh_node in [lane, _path]:
		RenderingServer.canvas_item_set_custom_rect(mesh_node.get_canvas_item(), true, Rect2(-4000, -4000, 8000, 8000))
	add_child(cursor)
	add_child(_burst)
	add_child(label)
	_fit()
	Stage.changed.connect(_fit)


func _exit_tree() -> void:
	if Stage.changed.is_connected(_fit):
		Stage.changed.disconnect(_fit)


## The rider's FTP, the lane's width (W), the look (the step label's style) and the repeating
## tile the lane's streaks come from (WattLaneBackdrop).
func setup(ftp_watts: float, lane_watts: int, look: GameTheme, tile: Texture2D = null) -> void:
	_mat.set_shader_parameter("tile_tex", tile)
	ftp = maxf(ftp_watts, 50.0)
	width_watts = lane_watts
	look.style_label(label, HudTheme.MEDIUM, GameTheme.INK, true)
	_hist.fill(-1.0)


static func guide_y(i: int) -> float:
	return GUIDE_TOP + GUIDE_GAP * i


## y on the stage for `watts` (more watts, higher), within the cursor's range.
func y_of(watts: float) -> float:
	return clampf(MID_Y - (watts / ftp - MID_SHARE) * PX_PER_FTP, TOP_Y, BOTTOM_Y)


## Course time at stage x `x` when it is `t` at the cursor.
static func time_at(x: float, t: float) -> float:
	return t + (x - RIDER_X) / SPEED


## The lane's middle at the cursor (stage y), for the backdrop's warm light.
func lane_mid() -> float:
	var i := clampi(int((RIDER_X - _x0) / _dx), 0, COLS - 1)
	return (_lo[i] + _hi[i]) * 0.5


## One frame: `t` the course clock, `watts` the smoothed power, the rules' verdict, the announced
## step (`step_at` seconds ahead, < 0 none; its new bounds `lo`-`hi`) and the beat's flare.
func update_view(delta: float, course: WattLaneCourse, t: float, watts: float, in_lane: bool,
		step_at: float, up: bool, lo := 0, hi := 0, beat := 0.0) -> void:
	_clock += delta
	scroll += delta * SPEED
	_record(delta, watts)
	var half := float(width_watts) / 2.0
	for i in COLS:
		var x := _x0 + float(i) * _dx
		var centre := course.visual_centre_at(time_at(x, t))
		_lo[i] = y_of(centre - half)
		_hi[i] = y_of(centre + half)
		_trail[i] = _trail_at(x)
	var target := y_of(watts)
	cursor_y = lerpf(cursor_y, target, minf(delta * CURSOR_EASE, 1.0)) if _clock > delta else target
	cursor.position = Vector2(RIDER_X, cursor_y)
	_cursor_glow.scale = Vector2.ONE * (_glow_base() * (1.0 + 0.15 * beat + 0.6 * flash))
	_set_state("in" if in_lane else "out")
	_glow = move_toward(_glow, 1.0 if in_lane else 0.68, delta * 2.5)
	_in = move_toward(_in, 1.0 if in_lane else 0.0, delta * 4.0)
	flash = maxf(flash - delta * 2.5, 0.0)
	_apply(beat)
	_show_step(course, t, step_at, up)
	_show_label(step_at, up, lo, hi)


func _apply(beat: float) -> void:
	_mat.set_shader_parameter("band_lo", _lo)
	_mat.set_shader_parameter("band_hi", _hi)
	_mat.set_shader_parameter("glow", _glow + flash)
	_mat.set_shader_parameter("beat", beat)
	_mat.set_shader_parameter("streak_scroll", fposmod(scroll * STREAK_SPEED, TILE))
	_path_mat.set_shader_parameter("trail", _trail)
	_path_mat.set_shader_parameter("dash_scroll", fposmod(scroll, 26.0))
	# The beam: from the cursor along the lane, while the rider is in it.
	_beam.position = Vector2(RIDER_X + 20.0, cursor_y)
	_beam.modulate.a = _in
	_beam.visible = _in > 0.01


## The announced step on the lane: a riser of light where it jumps, whole chevrons on the flat
## lane before the bend.
func _show_step(course: WattLaneCourse, t: float, step_at: float, up: bool) -> void:
	var on := step_at >= 0.0
	_riser.visible = on
	for m in _marks:
		m.visible = on
	if not on:
		return
	var pulse := 0.75 + 0.25 * sin(_clock * TAU * 2.0)
	var x := RIDER_X + step_at * SPEED
	var mid := y_of(course.visual_centre_at(time_at(x, t)))
	_riser.position = Vector2(x, mid)
	_riser.scale = Vector2(70.0, PX_PER_FTP * float(width_watts) / ftp * 1.1) / float(_riser.texture.get_width())
	_riser.modulate.a = 0.8 * pulse
	for k in MARKS:
		var mx := x - MARK_FIRST - MARK_GAP * float(k)
		_marks[k].position = Vector2(mx, y_of(course.visual_centre_at(time_at(mx, t))))
		_marks[k].scale.y = 1.0 if up else -1.0
		_marks[k].modulate.a = pulse


## A catch: the lane and the cursor flash, and gold sparks fly off the cursor.
func caught() -> void:
	flash = 1.0
	_burst.position = cursor.position
	_burst.restart()
	_burst.emitting = true


# --- The path ---

func _record(delta: float, watts: float) -> void:
	_hist_left -= delta
	while _hist_left <= 0.0:
		_hist_left += HIST_DT
		for i in HIST - 1:
			_hist[i] = _hist[i + 1]
		_hist[HIST - 1] = y_of(watts)


func _trail_at(x: float) -> float:
	if x >= RIDER_X:
		return -1.0
	var idx := float(HIST - 1) - (RIDER_X - x) / SPEED / HIST_DT
	if idx < 0.0:
		return -1.0
	var i := int(idx)
	var a := _hist[i]
	var b := _hist[mini(i + 1, HIST - 1)]
	if a < 0.0 or b < 0.0:
		return -1.0
	return lerpf(a, b, idx - float(i))


func _fit() -> void:
	var r := Stage.bleed_rect()
	_x0 = r.position.x
	_dx = r.size.x / float(COLS - 1)
	for mat in [_mat, _path_mat]:
		mat.set_shader_parameter("col_x0", _x0)
		mat.set_shader_parameter("col_dx", _dx)
		mat.set_shader_parameter("view_x0", r.position.x)
	_mat.set_shader_parameter("view_x1", r.end.x)


## The lane's strip: COLS columns of ROWS, VERTEX = (column, row), UV = (t, off).
static func lane_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var rows := ROWS.size()
	for c in COLS:
		for r in rows:
			verts.append(Vector2(c, r))
			uvs.append(ROWS[r])
	for c in COLS - 1:
		for r in rows - 1:
			var a := c * rows + r
			indices.append_array([a, a + rows, a + 1, a + 1, a + rows, a + rows + 1])
	return _mesh(verts, uvs, indices)


## The path's strip: VERTEX = (column, side -1 or +1).
static func path_mesh() -> ArrayMesh:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for c in COLS:
		verts.append(Vector2(c, -1))
		verts.append(Vector2(c, 1))
		uvs.append(Vector2.ZERO)
		uvs.append(Vector2.ZERO)
	for c in COLS - 1:
		var a := c * 2
		indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])
	return _mesh(verts, uvs, indices)


static func _mesh(verts: PackedVector2Array, uvs: PackedVector2Array, indices: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


# --- The beam and the step's marks ---

func _build_step_marks() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_beam = WattLaneTrack.Paint.new(_paint_beam)
	_beam.name = "Beam"
	_beam.material = add
	_riser = Sprite2D.new()
	_riser.name = "Riser"
	_riser.texture = MeshBatch2D.soft_dot()
	_riser.material = add
	_riser.modulate = Color(WARN_LIGHT, 0.8)
	_riser.visible = false
	for k in MARKS:
		var m := WattLaneTrack.Paint.new(_paint_mark)
		m.name = "StepMark%d" % k
		m.visible = false
		_marks.append(m)


## A soft horizontal shaft of light, fading along its length and to either side.
func _paint_beam(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var hot := Color(1.0, 0.93, 0.75, 1.0) * Color(0.5, 0.5, 0.5, 1.0)
	var clear := Color(hot, 0.0)
	clear.r = 0.0
	clear.g = 0.0
	clear.b = 0.0
	for side in [-1.0, 1.0]:
		m.quad4(Vector2(0, 0), Vector2(620, 0), Vector2(620, 26.0 * side), Vector2(0, 26.0 * side), hot, clear, clear, clear)
	m.flush(ci)


## One chevron (Λ), amber with an ink edge; `scale.y` -1 points it down.
func _paint_mark(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var pts := [Vector2(-28, 14), Vector2(0, -16), Vector2(28, 14)]
	for pass_ in [[20.0, Color("0f1a2e", 0.5)], [14.0, WARN_LIGHT]]:
		m.line(pts[0], pts[1], pass_[0], pass_[1])
		m.line(pts[1], pts[2], pass_[0], pass_[1])
	m.flush(ci)


# --- The cursor ---

## The cursor's outline: a chevron (▶) pointing along the lane, 62 px long. Angular on purpose:
## a moving marker never gets a round head with a tail (ART_BIBLE.md, silhouette check).
static func chevron() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-30, -34), Vector2(32, 0), Vector2(-30, 34), Vector2(-14, 0)])


func _build_cursor() -> void:
	cursor = Node2D.new()
	cursor.name = "Cursor"
	_cursor_glow = Sprite2D.new()
	_cursor_glow.texture = MeshBatch2D.soft_dot()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_cursor_glow.material = add
	cursor.add_child(_cursor_glow)
	_cursor_paint = WattLaneTrack.Paint.new(_paint_cursor)
	cursor.add_child(_cursor_paint)


func _glow_base() -> float:
	return 170.0 / float(_cursor_glow.texture.get_width())


func _set_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	var col := GameTheme.GOOD if state == "in" else GameTheme.WARN
	_cursor_glow.modulate = Color(col.lerp(Color.WHITE, 0.25), 0.75)
	_cursor_paint.queue_redraw()


## The chevron: an ink outline, a rim in the state's colour (green in the lane, amber out) and
## a white-hot core, with a lit upper facet so it reads as a solid shape.
func _paint_cursor(ci: CanvasItem) -> void:
	var m := MeshBatch2D.new()
	var rim := GameTheme.GOOD if _state == "in" else GameTheme.WARN
	var shape := chevron()
	_fill(m, MeshBatch2D.grow_outline(shape, 7.0), INK)
	_fill(m, MeshBatch2D.grow_outline(shape, 3.5), rim)
	_fill(m, shape, Color(1.0, 0.98, 0.92))
	_fill(m, PackedVector2Array([Vector2(-24, -27), Vector2(22, -2), Vector2(-10, -2)]), Color(1, 1, 1))
	_fill(m, PackedVector2Array([Vector2(-24, 27), Vector2(22, 2), Vector2(-10, 2)]), rim.lerp(Color.WHITE, 0.55))
	m.flush(ci)


## A possibly concave outline, triangulated (MeshBatch2D.fill fans from the centre).
static func _fill(m: MeshBatch2D, pts: PackedVector2Array, col: Color) -> void:
	var tris := Geometry2D.triangulate_polygon(pts)
	var base := m.vertex_count()
	for p in pts:
		m.vert(p, col)
	for k in range(0, tris.size(), 3):
		m.tri(base + tris[k], base + tris[k + 1], base + tris[k + 2])


func _make_burst() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "CatchSparks"
	p.one_shot = true
	p.emitting = false
	p.amount = 24
	p.lifetime = 0.7
	p.explosiveness = 0.95
	p.spread = 180.0
	p.initial_velocity_min = 160.0
	p.initial_velocity_max = 340.0
	p.gravity = Vector2(0, 260)
	p.scale_amount_min = 3.0
	p.scale_amount_max = 6.0
	p.color = Color("ffd24a")
	return p


func _show_label(step_at: float, up: bool, lo: int, hi: int) -> void:
	if step_at < 0.0:
		if label.visible:
			label.visible = false
			_label_bounds = Vector2i(-1, -1)
		return
	var b := Vector2i(lo, hi)
	if b != _label_bounds:
		_label_bounds = b
		label.text = "%d–%d W" % [lo, hi]
		label.reset_size()
	label.visible = true
	# Just inside the new lane, at its top, right of the riser: where the eye goes next.
	label.position = Vector2(RIDER_X + step_at * SPEED + 22.0, y_of(float(hi)) + 6.0)


## A Node2D that draws with a callable, once (redrawn only on `queue_redraw`).
class Paint:
	extends Node2D

	var paint: Callable

	func _init(p: Callable) -> void:
		paint = p

	func _draw() -> void:
		paint.call(self)
