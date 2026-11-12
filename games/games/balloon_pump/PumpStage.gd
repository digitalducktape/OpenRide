class_name PumpStage
extends Node2D
## Balloon Pump's picture (#76, the 2D rework; ART_BIBLE.md): a brass pump and its balloon in a
## lit, moody place, drawn in code on the full 1080p canvas, Safe Cracker's way. The game tells
## it the state each frame (`update_view`) and the events (`tie_off`, `set_balloons`,
## `celebrate`, `set_place`).
##
## What draws what (GFX_POLISH.md, "Budget"):
##   Room       the place, the pump, its hose and stand, the key light and the vignette, baked into
##              one texture per place (a SubViewport rendered once) and shown as one sprite;
##   Sea        the pier's sea, a shader rect under the bake (the pier's bake leaves it clear);
##   Wheel      the fair's Ferris wheel, turning on a rotation tween, its lamps twinkling;
##   Bulbs      the place's string lights, breathing in a shader (no redraws);
##   Plunger    the T handle, moved each frame with the pedal stroke (a transform only);
##   Wedge      the gauge's push line, a shader band moved by one uniform; Needle turned by rotation;
##   Bunch      every tied balloon, one MultiMesh, swaying on a rotation tween; its strings one batch
##              redrawn only when a balloon lands;
##   Nozzle / Flyer  the balloon on the nozzle and the one flying up: a quad each, shaded per pixel.
## Each MeshBatch2D batch (Safe Cracker's batcher, read only) is one draw call.

const BUNCH_MAX := 40  ## the bunch shows at most this many; later balloons replace the oldest
const BUNCH_SCALE := 0.42  ## a bunch balloon's size as a share of its nozzle size
const FLIGHT_SEC := 1.7
const FLIGHT_ARC := 36.0  ## px the flight bows upward
## Confetti: the tie-off's and the heat's bursts, and how fast and how far they rise (they stay
## under the HUD's Pause | End and the status widget; pump_layout_test).
const TIE_BURST := PumpPlaces.NOZZLE + Vector2(0, -260)
const WIN_BURST := PumpPlaces.TETHER + Vector2(0, -300)
const CONFETTI_GRAVITY := 520.0
const CONFETTI_SPEED := {false: 330.0, true: 380.0}
const STROKE := 52.0  ## the plunger's travel, px (its handle stays above the collar)
const PLUNGER_TOP := 262.0  ## the handle's centre at the top of its stroke
const SWAY_DEG := 1.6
const SWAY_SEC := 2.8
const DUST := 18
const WARM_FRAMES := 3

const BalloonShader := preload("res://games/balloon_pump/shaders/pump_balloon.gdshader")
const TwinkleShader := preload("res://games/balloon_pump/shaders/pump_twinkle.gdshader")
const SeaShader := preload("res://games/balloon_pump/shaders/pump_sea.gdshader")
const WedgeShader := preload("res://games/balloon_pump/shaders/pump_wedge.gdshader")

var place_index := -1
var bakes := 0  ## room renders made (tests)

var _bake: SubViewport
var _room: MeshLayer
var _room_view: Sprite2D
var _sea: ColorRect
var _wheel: MeshLayer
var _wheel_tween: Tween
var _bulbs: MeshLayer
var _dust: CPUParticles2D
var _plunger_clip: Control
var _plunger: MeshLayer
var _lip: MeshLayer
var _wedge: ColorRect
var _wedge_mat: ShaderMaterial
var _needle: MeshLayer
var _bunch: Node2D
var _strings: MeshLayer
var _bunch_mm: MultiMesh
var _bunch_mat: ShaderMaterial
var _sway_tween: Tween
var _nozzle: MeshInstance2D
var _nozzle_mat: ShaderMaterial
var _flyer: MeshInstance2D
var _flyer_mat: ShaderMaterial
var _confetti: CPUParticles2D
var _hiss: CPUParticles2D
var _puff: CPUParticles2D
var _shadow: Sprite2D

var _kind := ""
var _next_kind := ""
var _fill_shown := 0.0
var _needle_shown := 0.0
var _stroke_phase := 0.0
var _wobble := 0.0
var _load_t := 1.0
var _flight := -1.0
var _flight_kind := ""
var _flight_from := Transform2D()
var _flight_slot := 0
var _bunch_count := 0
var _slot_kinds := {}
var _warming := false
var _lx := 0.0


func _init() -> void:
	_sea = ColorRect.new()
	_sea.name = "Sea"
	_sea.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sea.position = PumpPlaces.SEA.position
	_sea.size = PumpPlaces.SEA.size
	var sea_mat := ShaderMaterial.new()
	sea_mat.shader = SeaShader
	sea_mat.set_shader_parameter("moon_u", (PumpPlaces.MOON.x - PumpPlaces.SEA.position.x) / PumpPlaces.SEA.size.x)
	_sea.material = sea_mat
	add_child(_sea)
	_bake = SubViewport.new()
	_bake.name = "RoomBake"
	_bake.disable_3d = true
	_bake.gui_disable_input = true
	_bake.size = Vector2i(PumpPlaces.WIDE)
	_bake.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_bake)
	_room = MeshLayer.new()
	_room.name = "Room"
	_room.position = Vector2(PumpPlaces.BLEED, 0)
	_bake.add_child(_room)
	_room_view = Sprite2D.new()
	_room_view.name = "RoomView"
	_room_view.centered = false
	_room_view.position = Vector2(-PumpPlaces.BLEED, 0)
	_room_view.texture = _bake.get_texture()
	_room_view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(_room_view)
	_wheel = _layer("Wheel", _paint_wheel, _twinkle_material(0.8))
	_wheel.position = PumpPlaces.WHEEL_AT
	_bulbs = _layer("Bulbs", _paint_bulbs, _twinkle_material(1.3))
	_dust = _make_dust()
	add_child(_dust)
	# The plunger runs into the collar: it's clipped at the collar's top.
	_plunger_clip = Control.new()
	_plunger_clip.name = "PlungerClip"
	_plunger_clip.clip_contents = true
	_plunger_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plunger_clip.position = Vector2(PumpPlaces.PUMP_X - 160, 160)
	_plunger_clip.size = Vector2(320, PumpPlaces.COLLAR.position.y - 160)
	add_child(_plunger_clip)
	_plunger = MeshLayer.new()
	_plunger.name = "Plunger"
	_plunger.paint = func(m: MeshBatch2D): PumpArt.paint_plunger(m, _lx)
	_plunger.position = Vector2(160, PLUNGER_TOP - 160)
	_plunger_clip.add_child(_plunger)
	_lip = _layer("CollarLip", func(m: MeshBatch2D): PumpArt.paint_collar_lip(m, _lx))
	_wedge = ColorRect.new()
	_wedge.name = "Wedge"
	_wedge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wedge.position = PumpPlaces.GAUGE_AT - Vector2.ONE * PumpPlaces.GAUGE_R
	_wedge.size = Vector2.ONE * PumpPlaces.GAUGE_R * 2.0
	_wedge_mat = ShaderMaterial.new()
	_wedge_mat.shader = WedgeShader
	_wedge.material = _wedge_mat
	add_child(_wedge)
	_needle = _layer("Needle", PumpArt.paint_needle)
	_needle.position = PumpPlaces.GAUGE_AT
	_needle.rotation = PumpArt.gauge_angle(0.0)
	_bunch = Node2D.new()
	_bunch.name = "Bunch"
	_bunch.position = PumpPlaces.TETHER
	add_child(_bunch)
	_strings = MeshLayer.new()
	_strings.name = "Strings"
	_strings.paint = _paint_strings
	_bunch.add_child(_strings)
	_bunch_mat = _balloon_material()
	_bunch_mm = MultiMesh.new()
	_bunch_mm.transform_format = MultiMesh.TRANSFORM_2D
	_bunch_mm.use_colors = true
	_bunch_mm.use_custom_data = true
	_bunch_mm.mesh = balloon_quad()
	_bunch_mm.instance_count = BUNCH_MAX
	_bunch_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance2D.new()
	mmi.name = "BunchBalloons"
	mmi.multimesh = _bunch_mm
	mmi.material = _bunch_mat
	_bunch.add_child(mmi)
	# The nozzle balloon's soft shadow on the floor, growing with it (a sprite: no redraw).
	_shadow = Sprite2D.new()
	_shadow.name = "BalloonShadow"
	_shadow.texture = MeshBatch2D.soft_dot()
	_shadow.modulate = Color(0, 0, 0, 0.5)
	_shadow.position = Vector2(PumpPlaces.NOZZLE.x - 30, PumpPlaces.FLOOR_Y - 2)
	add_child(_shadow)
	_flyer_mat = _balloon_material()
	_flyer_mat.set_shader_parameter("taut", 0.8)
	_flyer = _balloon_node("Flyer", _flyer_mat)
	_flyer.visible = false
	_nozzle_mat = _balloon_material()
	_nozzle = _balloon_node("Nozzle", _nozzle_mat)
	_confetti = _make_confetti()
	add_child(_confetti)
	_hiss = _make_hiss()
	add_child(_hiss)
	_puff = _make_puff()
	add_child(_puff)
	set_place(0)
	set_balloons("small", "medium")


func _ready() -> void:
	_start_sway()


func _layer(layer_name: String, paint: Callable, mat: Material = null) -> MeshLayer:
	var l := MeshLayer.new()
	l.name = layer_name
	l.paint = paint
	l.material = mat
	add_child(l)
	return l


func _twinkle_material(speed: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TwinkleShader
	m.set_shader_parameter("speed", speed)
	return m


func _balloon_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = BalloonShader
	return m


func _balloon_node(node_name: String, mat: ShaderMaterial) -> MeshInstance2D:
	var mi := MeshInstance2D.new()
	mi.name = node_name
	mi.mesh = balloon_quad()
	mi.material = mat
	add_child(mi)
	return mi


static var _quad: ArrayMesh

## The balloon's quad: the knot at the origin, the body above (-y), half-width 1 (scale it by the
## balloon's radius).
static func balloon_quad() -> ArrayMesh:
	if _quad == null:
		var t := PumpArt.BALLOON_TALL
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-1, -t), Vector2(1, -t), Vector2(1, 0), Vector2(-1, 0)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		_quad = ArrayMesh.new()
		_quad.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return _quad


# --- Places ---

## Builds every place's room batch ahead (behind the intro card), so a place change only bakes.
static func prebuild() -> void:
	for i in PumpPlaces.count():
		MeshBatch2D.built("pump_room_%d" % i, func(m: MeshBatch2D): PumpPlaces.paint(m, i))

## Moves the stage to place `index` (PumpPlaces): the room is baked again, the ambient life
## switches, and every balloon takes the new key light.
func set_place(index: int) -> void:
	index = posmod(index, PumpPlaces.count())
	if index == place_index:
		return
	place_index = index
	var p := PumpPlaces.place(index)
	var id := str(p.id)
	var l := PumpPlaces.light(index)
	_lx = clampf(((l.at as Vector2).x - PumpPlaces.PUMP_X) / 600.0, -1.0, 1.0)
	_room.batch = MeshBatch2D.built("pump_room_%d" % index, func(m: MeshBatch2D): PumpPlaces.paint(m, index))
	_room.queue_redraw()
	_bake.transparent_bg = id == "pier"
	_bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	bakes += 1
	_sea.visible = id == "pier"
	_wheel.visible = id == "fair"
	if _wheel_tween:
		_wheel_tween.kill()
		_wheel_tween = null
	if _wheel.visible and is_inside_tree():
		_spin_wheel()
	_dust.visible = id == "bigtop"
	_dust.emitting = _dust.visible
	_bulbs.queue_redraw()
	_plunger.queue_redraw()
	_lip.queue_redraw()
	var to_light := PumpPlaces.to_light(index, PumpPlaces.NOZZLE + Vector2(0, -200))
	var lc: Color = l.color
	for mat in [_nozzle_mat, _flyer_mat, _bunch_mat]:
		mat.set_shader_parameter("light_dir", to_light)
		mat.set_shader_parameter("light_color", lc)


func _spin_wheel() -> void:
	_wheel_tween = create_tween().set_loops()
	_wheel_tween.tween_property(_wheel, "rotation", _wheel.rotation + TAU, 90.0).from(_wheel.rotation)


func _start_sway() -> void:
	if _sway_tween:
		_sway_tween.kill()
	_sway_tween = create_tween().set_loops()
	_sway_tween.tween_property(_bunch, "rotation", deg_to_rad(SWAY_DEG), SWAY_SEC).set_trans(Tween.TRANS_SINE)
	_sway_tween.tween_property(_bunch, "rotation", deg_to_rad(-SWAY_DEG), SWAY_SEC).set_trans(Tween.TRANS_SINE)
	if _wheel.visible and _wheel_tween == null:
		_spin_wheel()


# --- Balloons ---

## The nozzle's balloon kind and the next one's (a new balloon was loaded, or at the start).
func set_balloons(kind: String, next_kind: String) -> void:
	_next_kind = next_kind
	if kind != _kind:
		_kind = kind
		_load_t = 0.0
		_fill_shown = 0.0
		_paint_balloon(_nozzle, _nozzle_mat, kind)


func _paint_balloon(node: CanvasItem, mat: ShaderMaterial, kind: String) -> void:
	node.modulate = PumpArt.BALLOON_COLORS[kind]
	mat.set_shader_parameter("gold", 1.0 if kind == "gold" else 0.0)


## The view each frame: `fill` (0-1) of the nozzle's balloon, whether it `leaks`, the valve's
## `open` (0-1), the gauge's `needle` and `line` (0-1 along its scale), and the cadence (rpm) that
## drives the plunger. `loaded` is false while no balloon is on the nozzle (tie and load).
func update_view(delta: float, fill: float, leaks: bool, open: float, needle: float, line: float,
		cadence: float, loaded := true) -> void:
	# The plunger: one stroke a pedal revolution, eased at the ends.
	var stroked := _stroke_phase + delta * cadence / 60.0 >= 1.0
	_stroke_phase = fmod(_stroke_phase + delta * cadence / 60.0, 1.0)
	# Each stroke that pushes air puffs a little vapour at the collar.
	if stroked and open > 0.3 and loaded:
		_puff.restart()
		_puff.emitting = true
	var down := 0.5 - 0.5 * cos(_stroke_phase * TAU)
	_plunger.position.y = PLUNGER_TOP - 160.0 + down * STROKE * clampf(cadence / 40.0, 0.0, 1.0)
	# The gauge: the needle eases toward the reading (the bike reports once a second).
	_needle_shown = move_toward(_needle_shown, clampf(needle, 0.0, 1.05), delta * maxf(absf(needle - _needle_shown) * 6.0, 0.05))
	_needle.rotation = PumpArt.gauge_angle(_needle_shown)
	_wedge_mat.set_shader_parameter("line", clampf(line, 0.0, 1.0))
	_wedge_mat.set_shader_parameter("filling", open)
	# The nozzle's balloon eases toward the fill, so the steps never show.
	_load_t = minf(_load_t + delta / 0.35, 1.0)
	_nozzle.visible = (loaded or _load_t < 1.0) and _kind != ""
	if loaded:
		_fill_shown = move_toward(_fill_shown, fill, delta * maxf(absf(fill - _fill_shown) * 8.0, 0.05))
	_wobble = move_toward(_wobble, 1.0 if leaks and loaded else 0.0, delta * 2.5)
	_place_nozzle_balloon()
	_nozzle_mat.set_shader_parameter("taut", smoothstep(0.5, 1.0, _fill_shown))
	_nozzle_mat.set_shader_parameter("wobble", _wobble)
	_hiss.emitting = _wobble > 0.5 and _fill_shown > 0.1
	if _flight >= 0.0:
		_flight = minf(_flight + delta / FLIGHT_SEC, 1.0)
		_place_flyer()
		if _flight >= 1.0:
			_land_flyer()


func _place_nozzle_balloon() -> void:
	if _kind == "":
		return
	var r: float = PumpArt.BALLOON_RADIUS[_kind]
	var f := _fill_shown
	var s := r * lerpf(0.24, 1.0, pow(f, 0.6))
	var limp := 1.0 + 0.24 * (1.0 - f) * (1.0 - f)
	var slide := (1.0 - ease(_load_t, 0.4)) * -60.0
	var lean := sin(Time.get_ticks_msec() * 0.0011) * 0.025 * (0.3 + f)
	_nozzle.transform = Transform2D(lean, Vector2(s, s * limp), 0.0, PumpPlaces.NOZZLE + Vector2(0, slide))
	var dot := float(MeshBatch2D.soft_dot().get_width())
	_shadow.scale = Vector2(s * 1.7, s * 0.28) / (dot * 0.5)
	_shadow.modulate.a = 0.22 + 0.25 * f


## Bunch slot `i` for a balloon of `kind`: [its transform in the bunch's space (knot at origin,
## turned along its string), its centre in the bunch's space].
func _slot(i: int, kind: String) -> Array:
	var golden := 2.39996
	var k := sqrt(float(i + 1) / BUNCH_MAX)
	var tilt := clampf(sin(i * golden) * (0.12 + 0.42 * k), -0.46, 0.46)
	var length := 226.0 + 88.0 * k + 10.0 * float(i % 3)
	var up := Vector2(sin(tilt), -cos(tilt))
	var r: float = PumpArt.BALLOON_RADIUS[kind] * BUNCH_SCALE
	var knot := up * length
	return [Transform2D(tilt, Vector2(r, r), 0.0, knot), knot + up * r * 1.22]


func _paint_strings(m: MeshBatch2D) -> void:
	for i in mini(_bunch_count, BUNCH_MAX):
		var knot: Vector2 = (_slot(i, _slot_kinds.get(i, "small"))[0] as Transform2D).origin
		var mid := knot * 0.5 + Vector2(sin(i * 1.7) * 10.0, 0)
		m.line(Vector2.ZERO, mid, 2.0, Color(0.95, 0.92, 0.85, 0.7))
		m.line(mid, knot, 2.0, Color(0.95, 0.92, 0.85, 0.7))


func _set_slot(i: int, kind: String) -> void:
	var slot := _slot(i, kind)
	_bunch_mm.set_instance_transform_2d(i, slot[0])
	_bunch_mm.set_instance_color(i, PumpArt.BALLOON_COLORS[kind])
	_bunch_mm.set_instance_custom_data(i, Color(0.0, 1.0 if kind == "gold" else 0.0, 0.0, 0.0))


## The nozzle's balloon is full and tied: it pops off with confetti and floats into the bunch.
func tie_off(kind: String) -> void:
	if _flight >= 0.0:
		_land_flyer()
	_flight_kind = kind
	_flight_from = _nozzle.transform
	_flight_slot = _bunch_count % BUNCH_MAX
	_flight = 0.0
	_paint_balloon(_flyer, _flyer_mat, kind)
	_flyer.visible = true
	_place_flyer()
	_nozzle.visible = false
	_fill_shown = 0.0
	_kind = ""
	_burst(TIE_BURST, kind == "gold")


func _place_flyer() -> void:
	_flyer.transform = flight_at(_flight_from, _flight_slot, _flight_kind, _flight, _bunch.transform)


## The flying balloon's transform `progress` (0-1) of the way from the nozzle (`from`) to its
## bunch slot: a low arc (it shrinks as it rises, so it never reaches the HUD; pump_layout_test).
func flight_at(from: Transform2D, slot_index: int, kind: String, progress: float, bunch := Transform2D(0.0, PumpPlaces.TETHER)) -> Transform2D:
	var to: Transform2D = _slot(slot_index, kind)[0]
	var end_knot := bunch * to.origin
	var t := ease(progress, -1.8)
	var p := from.origin.lerp(end_knot, t)
	p.y -= sin(t * PI) * FLIGHT_ARC
	var s := lerpf(from.get_scale().x, to.get_scale().x, ease(progress, 0.4))
	var rot := lerpf(0.0, to.get_rotation() + bunch.get_rotation(), t) + sin(t * PI) * 0.25
	return Transform2D(rot, Vector2(s, s), 0.0, p)


func _land_flyer() -> void:
	_flight = -1.0
	_flyer.visible = _warming
	_slot_kinds[_flight_slot] = _flight_kind
	_set_slot(_flight_slot, _flight_kind)
	_bunch_count += 1
	_bunch_mm.visible_instance_count = mini(_bunch_count, BUNCH_MAX)
	_strings.queue_redraw()


func bunch_count() -> int:
	return _bunch_count


## A Race heat won: confetti over the bunch and the bunch bobs.
func celebrate() -> void:
	_burst(WIN_BURST, true)
	var t := create_tween()
	t.tween_property(_bunch, "scale", Vector2(1.04, 0.96), 0.18).set_trans(Tween.TRANS_SINE)
	t.tween_property(_bunch, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


## A posed scene for stills (the hub card): the bunch holds `tied` (kinds) and the nozzle a balloon
## of `kind` at `fill`.
func pose(tied: Array, kind: String, fill: float) -> void:
	for k in tied:
		_flight_kind = k
		_flight_slot = _bunch_count % BUNCH_MAX
		_land_flyer()
	set_balloons(kind, "gold")
	_fill_shown = fill
	_load_t = 1.0
	_place_nozzle_balloon()
	_nozzle.visible = true
	_nozzle_mat.set_shader_parameter("taut", smoothstep(0.5, 1.0, fill))


## Draws every effect that starts hidden once, behind the intro card, so its shader compiles then.
func prewarm() -> void:
	_warming = true
	_flyer.visible = true
	_flyer.position = Vector2(-500, -500)
	_confetti.position = Vector2(-500, -500)
	_confetti.restart()
	_confetti.emitting = true
	_hiss.emitting = true
	_puff.restart()
	_puff.emitting = true
	for i in WARM_FRAMES:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_warming = false
	_hiss.emitting = false
	_confetti.emitting = false
	if _flight < 0.0:
		_flyer.visible = false


# --- Bounds (pump_layout_test: nothing clipped by the frame, the ground line or a HUD panel) ---

## The plunger's T handle (with its grips) on the canvas, `down` 0 at the top of its stroke, 1 at
## the bottom.
static func handle_rect(down: float) -> Rect2:
	var y := PLUNGER_TOP + down * STROKE
	return Rect2(PumpPlaces.PUMP_X - 134.0, y - 17.0, 268.0, 34.0)


## The nozzle's balloon at its fullest for `kind` (its quad: the shape stays inside it).
static func balloon_rect(kind: String) -> Rect2:
	var r: float = PumpArt.BALLOON_RADIUS[kind]
	var tall := r * PumpArt.BALLOON_TALL
	return Rect2(PumpPlaces.NOZZLE.x - r, PumpPlaces.NOZZLE.y - tall, r * 2.0, tall)


## The Ferris wheel's reach as it turns: the rim's circle and the cars hanging under it.
static func wheel_rect() -> Rect2:
	var r := PumpPlaces.WHEEL_R + 4.0
	var car := PumpPlaces.WHEEL_CAR
	return Rect2(PumpPlaces.WHEEL_AT - Vector2(r + car.x * 0.5, r + car.x * 0.5),
		Vector2(2.0 * r + car.x, 2.0 * r + car.x * 0.5 + car.y + 4.0))


## Every bunch balloon's box (canvas), for the largest kind, at the sway's extremes.
func bunch_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in BUNCH_MAX:
		var centre: Vector2 = _slot(i, "large")[1]
		var r: float = PumpArt.BALLOON_RADIUS.large * BUNCH_SCALE
		for sway in [-SWAY_DEG, SWAY_DEG]:
			var c := PumpPlaces.TETHER + centre.rotated(deg_to_rad(sway))
			out.append(Rect2(c - Vector2(r, r * 1.05), Vector2(r * 2.0, r * 2.3)))
	return out


## The highest a confetti burst at `at` reaches (no drag: an upper bound), `big` for a gold or a
## heat won.
static func burst_top(at: Vector2, big: bool) -> float:
	var v: float = CONFETTI_SPEED[big]
	return at.y - v * v / (2.0 * CONFETTI_GRAVITY) - 12.0


# --- Drawings and effects ---

func _paint_wheel(m: MeshBatch2D) -> void:
	var r := PumpPlaces.WHEEL_R
	var ink := Color(0.16, 0.12, 0.22)
	m.ring(Vector2.ZERO, r - 6.0, r + 4.0, ink)
	m.ring(Vector2.ZERO, r * 0.62 - 4.0, r * 0.62 + 3.0, ink)
	for k in 16:
		var a := TAU * k / 16.0
		m.line(Vector2.ZERO, Vector2(cos(a), sin(a)) * r, 5.0, ink)
	m.circle(Vector2.ZERO, 16.0, ink.lightened(0.1))
	for k in 12:
		var a := TAU * k / 12.0 + 0.13
		var at := Vector2(cos(a), sin(a)) * r
		var car := PumpPlaces.WHEEL_CAR
		m.round_rect(Rect2(at + Vector2(-car.x * 0.5, 4), car), 6.0, ink.lightened(0.08), ink)
		m.rect(Rect2(at + Vector2(-car.x * 0.32, 8), Vector2(car.x * 0.64, car.y * 0.32)), Color(1.0, 0.8, 0.45, 0.55))
	var lamps := [Color(1.0, 0.85, 0.5), Color(1.0, 0.5, 0.6), Color(0.6, 0.9, 1.0)]
	for k in 48:
		var a := TAU * k / 48.0
		m.depth = 0.01 + float(k) / 48.0
		var at := Vector2(cos(a), sin(a)) * r
		var c: Color = lamps[k % 3]
		m.glow(at, Vector2(11, 11), Color(c, 0.45), 4)
		m.circle(at, 3.0, c.lightened(0.4))
	m.depth = 0.0


func _paint_bulbs(m: MeshBatch2D) -> void:
	if place_index < 0:
		return
	var colours := [Color(1.0, 0.88, 0.55), Color(1.0, 0.6, 0.55), Color(0.7, 0.9, 1.0), Color(0.75, 1.0, 0.7)]
	var seed := 0
	for wire in PumpPlaces.string_wires(place_index):
		var pts: PackedVector2Array = wire
		for k in range(1, pts.size() - 1):
			seed += 1
			m.depth = 0.01 + fmod(seed * 0.137, 1.0)
			var c: Color = colours[seed % colours.size()]
			var at := pts[k] + Vector2(0, 9)
			if PumpPlaces.behind_hero(at):
				continue
			m.glow(at, Vector2(26, 26), Color(c, 0.4), 5)
			m.circle(at, 6.0, c.lightened(0.3))
			m.circle(at + Vector2(-2, -2), 2.0, Color(1, 1, 1, 0.9))
	m.depth = 0.0


func _make_dust() -> CPUParticles2D:
	var d := CPUParticles2D.new()
	d.name = "Dust"
	d.amount = DUST
	d.lifetime = 9.0
	d.preprocess = 9.0
	d.texture = MeshBatch2D.soft_dot()
	d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	d.emission_rect_extents = Vector2(380, 320)
	d.position = Vector2(930, 520)
	d.direction = Vector2(0.2, -1)
	d.spread = 180.0
	d.gravity = Vector2(0, 2)
	d.initial_velocity_min = 3.0
	d.initial_velocity_max = 9.0
	d.scale_amount_min = 0.12
	d.scale_amount_max = 0.24
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 0.95, 0.8, 0.0))
	ramp.set_color(1, Color(1, 0.95, 0.8, 0.0))
	ramp.add_point(0.3, Color(1, 0.95, 0.8, 0.3))
	ramp.add_point(0.7, Color(1, 0.95, 0.8, 0.22))
	d.color_ramp = ramp
	d.visible = false
	d.emitting = false
	return d


func _make_confetti() -> CPUParticles2D:
	var c := CPUParticles2D.new()
	c.name = "Confetti"
	c.amount = 40
	c.lifetime = 1.8
	c.one_shot = true
	c.emitting = false
	c.explosiveness = 0.92
	c.direction = Vector2(0, -1)
	c.spread = 75.0
	c.initial_velocity_min = 220.0
	c.initial_velocity_max = CONFETTI_SPEED[true]
	c.gravity = Vector2(0, CONFETTI_GRAVITY)
	c.damping_min = 80.0
	c.damping_max = 160.0
	c.angular_velocity_min = -540.0
	c.angular_velocity_max = 540.0
	c.angle_min = 0.0
	c.angle_max = 360.0
	c.scale_amount_min = 6.0
	c.scale_amount_max = 10.0
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([Color("ff4f96"), Color("ffc530"), Color("3fd0a8"), Color("8a7dff"), Color("fff4de")])
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	c.color_initial_ramp = ramp
	var fade := Gradient.new()
	fade.set_color(0, Color.WHITE)
	fade.set_color(1, Color(1, 1, 1, 0))
	fade.add_point(0.75, Color.WHITE)
	c.color_ramp = fade
	return c


func _make_hiss() -> CPUParticles2D:
	var h := CPUParticles2D.new()
	h.name = "Hiss"
	h.amount = 10
	h.lifetime = 0.7
	h.emitting = false
	h.texture = MeshBatch2D.soft_dot()
	h.position = PumpPlaces.NOZZLE + Vector2(14, -6)
	h.direction = Vector2(1, -0.3)
	h.spread = 25.0
	h.gravity = Vector2.ZERO
	h.initial_velocity_min = 60.0
	h.initial_velocity_max = 110.0
	h.scale_amount_min = 0.25
	h.scale_amount_max = 0.6
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.5))
	fade.set_color(1, Color(1, 1, 1, 0))
	h.color_ramp = fade
	return h


func _make_puff() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Puff"
	p.amount = 6
	p.lifetime = 0.6
	p.one_shot = true
	p.explosiveness = 0.9
	p.emitting = false
	p.texture = MeshBatch2D.soft_dot()
	p.position = Vector2(PumpPlaces.PUMP_X, PumpPlaces.COLLAR.position.y - 4)
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, -30)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 0.4
	p.scale_amount_max = 0.9
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.35))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	return p


func _burst(at: Vector2, big: bool) -> void:
	_confetti.position = at
	_confetti.initial_velocity_max = CONFETTI_SPEED[big]
	_confetti.restart()
	_confetti.emitting = true
