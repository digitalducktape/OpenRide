class_name WattLaneTrack
extends Node2D
## Watt Lane's lane and cursor (#78; ART_BIBLE.md): an illuminated horizontal band that comes in
## from the right `SPEED` px a second (the course's future) and steps up or down, and a chevron
## cursor (▶) at RIDER_X whose height is your smoothed power (`y_of`: more watts, higher). An
## announced step shows its riser, amber chevrons and its new bounds in watts where it lands.
## Behind the cursor, the dashed path it rode.
##
## It only draws: `WattLaneLogic` holds the rules. Cost: the lane is one shader rect fed 64-column
## arrays a frame (`shaders/wl_lane.gdshader`); the cursor is a static drawing moved by
## `position`, redrawn only when its state changes; one CPUParticles2D for a catch.

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
const RECT_Y := 290.0
const RECT_H := 720.0
const HIST_DT := 0.05  ## seconds between the path's samples
const HIST := 90
const CURSOR_EASE := 12.0
const SHADER := preload("res://games/watt_lane/shaders/wl_lane.gdshader")
const INK := Color("0f1a2e")

var ftp := 150.0
var width_watts := 40
var cursor: Node2D
var label: Label  ## the announced step's new bounds
var cursor_y := MID_Y
var flash := 0.0
var rect: ColorRect
var scroll := 0.0  ## px the lane has moved (the backdrop's layers follow it)

var _mat: ShaderMaterial
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
	rect = ColorRect.new()
	rect.name = "Lane"
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = SHADER
	_mat.set_shader_parameter("noise_tex", WorldLook.noise_texture())
	_mat.set_shader_parameter("rider_x", RIDER_X)
	rect.material = _mat
	_build_cursor()
	label = Label.new()
	label.name = "NextBand"
	label.visible = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_burst = _make_burst()


func _ready() -> void:
	add_child(rect)
	add_child(cursor)
	add_child(_burst)
	add_child(label)
	_fit()
	Stage.changed.connect(_fit)


func _exit_tree() -> void:
	if Stage.changed.is_connected(_fit):
		Stage.changed.disconnect(_fit)


## The rider's FTP, the lane's width (W) and the look (the step label's style).
func setup(ftp_watts: float, lane_watts: int, look: GameTheme) -> void:
	ftp = maxf(ftp_watts, 50.0)
	width_watts = lane_watts
	look.style_label(label, HudTheme.SMALL + 6, GameTheme.WARN, true)
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
	_apply(step_at, up, beat)
	_show_label(step_at, up, lo, hi)


func _apply(step_at: float, up: bool, beat: float) -> void:
	_mat.set_shader_parameter("band_lo", _lo)
	_mat.set_shader_parameter("band_hi", _hi)
	_mat.set_shader_parameter("trail", _trail)
	_mat.set_shader_parameter("scroll", scroll)
	_mat.set_shader_parameter("glow", _glow + flash)
	_mat.set_shader_parameter("in_lane", _in)
	_mat.set_shader_parameter("rider_y", cursor_y)
	_mat.set_shader_parameter("beat", beat)
	var announced := step_at >= 0.0
	_mat.set_shader_parameter("step_x", RIDER_X + step_at * SPEED if announced else -1.0)
	_mat.set_shader_parameter("step_dir", -1.0 if up else 1.0)
	_mat.set_shader_parameter("chevrons", (0.75 + 0.25 * sin(_clock * TAU * 2.0)) if announced else 0.0)


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
	rect.position = Vector2(r.position.x, RECT_Y)
	rect.size = Vector2(r.size.x, RECT_H)
	_mat.set_shader_parameter("col_x0", _x0)
	_mat.set_shader_parameter("col_dx", _dx)
	_mat.set_shader_parameter("origin", rect.position)
	_mat.set_shader_parameter("rect_size", rect.size)


# --- The cursor ---

## The cursor's outline: a chevron (▶) pointing along the lane, 62 px long. Angular on purpose:
## a moving marker never gets a round head with a tail (ART_BIBLE.md, silhouette check).
static func chevron() -> PackedVector2Array:
	return PackedVector2Array([Vector2(-30, -34), Vector2(32, 0), Vector2(-30, 34), Vector2(-14, 0)])


func _build_cursor() -> void:
	cursor = Node2D.new()
	cursor.name = "Cursor"
	_cursor_glow = Sprite2D.new()
	_cursor_glow.texture = SafePlaces.soft_dot()
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
	var m := SafeMesh.new()
	var rim := GameTheme.GOOD if _state == "in" else GameTheme.WARN
	var shape := chevron()
	_fill(m, SafeMesh.grow_outline(shape, 7.0), INK)
	_fill(m, SafeMesh.grow_outline(shape, 3.5), rim)
	_fill(m, shape, Color(1.0, 0.98, 0.92))
	_fill(m, PackedVector2Array([Vector2(-24, -27), Vector2(22, -2), Vector2(-10, -2)]), Color(1, 1, 1))
	_fill(m, PackedVector2Array([Vector2(-24, 27), Vector2(22, 2), Vector2(-10, 2)]), rim.lerp(Color.WHITE, 0.55))
	m.flush(ci)


## A possibly concave outline, triangulated (SafeMesh.fill fans from the centre).
static func _fill(m: SafeMesh, pts: PackedVector2Array, col: Color) -> void:
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
	var x := RIDER_X + step_at * SPEED + 16.0
	label.position = Vector2(x, y_of(float(hi)) - label.size.y - 12.0 if up else y_of(float(lo)) + 10.0)


## A Node2D that draws with a callable, once (redrawn only on `queue_redraw`).
class Paint:
	extends Node2D

	var paint: Callable

	func _init(p: Callable) -> void:
		paint = p

	func _draw() -> void:
		paint.call(self)
