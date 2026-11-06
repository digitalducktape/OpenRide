class_name GridStage
extends Node2D
## Power Grid's picture (#81; ART_BIBLE.md): a valley town going from dusk to night, and the shed on
## the hill whose generator lights it, drawn in code on the full 1080p canvas, Safe Cracker's way.
## The game tells it the state each frame (`update_view`) and the events (`storm_warning`,
## `strike`, `storm_over`, `celebrate`).
##
## What draws what (GFX_POLISH.md, "Budget"):
##   Sky       the whole painted valley and shed, baked twice (dusk and night) and blended in one
##             opaque shader: one screen of fill, one draw call;
##   Stars     night's sky, one mesh; Moon, Clouds, Birds: drawn once, then only moved and faded;
##   River     slow glints on a strip mesh;
##   Wheel     the funfair's wheel: a frame and its lamps, turned by `rotation`;
##   Lights    every window, lamp, bulb and floodlight: one mesh, four uniform levels;
##   Wires     the power running down the line: one strip mesh, one phase uniform;
##   Machine   crank, pedals, flywheel, pulley and the meter's needle: static drawings, transformed;
##   Storm     a cloud bank, rain and a bolt, hidden unless a storm is on.
## Each SafeMesh batch (Safe Cracker's batcher, read only) is one draw call.

const SkyShader := preload("res://games/power_grid/shaders/grid_sky.gdshader")
const LightsShader := preload("res://games/power_grid/shaders/grid_lights.gdshader")
const WiresShader := preload("res://games/power_grid/shaders/grid_wires.gdshader")
const RiverShader := preload("res://games/power_grid/shaders/grid_river.gdshader")
const RainShader := preload("res://games/power_grid/shaders/grid_rain.gdshader")

const RISE_SEC := 1.6  ## a district takes this long to come on, window by window
const FALL_SEC := 0.8
const CHASE_HZ := 1.6  ## the funfair's bulbs step this many times a second
const WHEEL_SEC := 40.0  ## a turn of the big wheel at full power
const WIRE_PX := 150.0  ## px a second at full supply
## The moon's path over a night: it stays between the HUD's panels and under the callout lane.
const MOON_FROM := Vector2(1370, 372)
const MOON_TO := Vector2(1180, 262)
const MOON_R := 34.0
## Scenery in the sky keeps to this band: under the ride panel and Pause | End.
const SKY_BAND := Vector2(340.0, 470.0)
const CLOUDS := [[Vector2(300, 372), 0.0, 520.0], [Vector2(1100, 376), 700.0, 380.0], [Vector2(1740, 402), 1300.0, 460.0]]
const CLOUD_PX := 5.0  ## px a second, the near ones faster
const BIRDS_FROM := Vector2(1700, 410)
const BIRDS_TO := Vector2(760, 372)
const BIRDS_SEC := 70.0
const CARS := 3
const CAR_PX := 34.0
const STORM_RECT := Rect2(640, 340, 1320, 150)
const RAIN_RECT := Rect2(-160, 330, 2240, 750)
const BOLT_FROM_Y := 400.0
const FIREWORK_AT := [Vector2(1260, 420), Vector2(1020, 440), Vector2(1420, 440)]
const FIREWORK_SPEED := 130.0
const WARM_FRAMES := 3

var bakes := 0  ## valley renders made (tests)

var _bake_dusk: SubViewport
var _bake_night: SubViewport
var _sky: Sprite2D
var _sky_mat: ShaderMaterial
var _stars: MeshInstance2D
var _stars_mat: ShaderMaterial
var _moon: Layer
var _clouds: Array[Layer] = []
var _birds: Layer
var _river: MeshInstance2D
var _river_mat: ShaderMaterial
var _wheel: Layer
var _wheel_lights: MeshInstance2D
var _lights: MeshInstance2D
var _lights_mat: ShaderMaterial
var _wires: MeshInstance2D
var _wires_mat: ShaderMaterial
var _town_glow: Sprite2D
var _cars: Array[Sprite2D] = []
var _smoke: CPUParticles2D
var _fireflies: CPUParticles2D
var _lamp_glow: Sprite2D
var _coil_glow: Sprite2D
var _brushes: CPUParticles2D
var _crank: Layer
var _pedals: Array[Layer] = []
var _flywheel: Layer
var _pulley: Layer
var _needle: Layer
var _marker: Layer
var _storm_cloud: Layer
var _rain: ColorRect
var _rain_mat: ShaderMaterial
var _bolt: Layer
var _sparks: CPUParticles2D
var _fireworks: Array[CPUParticles2D] = []

var _levels := Vector4.ZERO  ## the districts as shown (eased)
var _night := 0.0
var _supply := 0.0
var _needle_shown := 0.0
var _marker_shown := 0.0
var _crank_angle := 0.0
var _wire_phase := 0.0
var _chase := 0.0
var _rain_fall := 0.0
var _storm := 0.0  ## 0-1, the storm's weight
var _storm_target := 0.0
var _flash := 0.0
var _flashes: Array[float] = []  ## seconds until each pending flash
var _down := -1
var _car_t := [0.1, 0.45, 0.8]
var _bird_t := 0.0
var _bolt_to := Vector2.ZERO
var _bolt_rng := RandomNumberGenerator.new()


## A Node2D that draws one SafeMesh batch, built by `paint` (a Callable taking the SafeMesh).
class Layer extends Node2D:
	var paint: Callable
	var batch: SafeMesh

	func _draw() -> void:
		if batch:
			batch.draw_on(self)
		elif paint.is_valid():
			var m := SafeMesh.new()
			paint.call(m)
			m.flush(self)


func _init() -> void:
	_bake_dusk = _make_bake("BakeDusk", 0)
	_bake_night = _make_bake("BakeNight", 1)
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SkyShader
	_sky_mat.set_shader_parameter("night_tex", _bake_night.get_texture())
	_sky = Sprite2D.new()
	_sky.name = "Sky"
	_sky.centered = false
	_sky.position = Vector2(-GridValley.BLEED, 0)
	_sky.texture = _bake_dusk.get_texture()
	_sky.material = _sky_mat
	add_child(_sky)
	_stars_mat = _lights_material()
	_stars = _mesh_node("Stars", _star_mesh(), _stars_mat)
	_moon = _layer("Moon", _paint_moon)
	for i in CLOUDS.size():
		var c := _layer("Cloud%d" % i, _paint_cloud.bind(i))
		c.position = CLOUDS[i][0]
		_clouds.append(c)
	_birds = _layer("Birds", _paint_birds)
	_river_mat = ShaderMaterial.new()
	_river_mat.shader = RiverShader
	_river = _mesh_node("River", _river_mesh(), _river_mat)
	_lights_mat = _lights_material()
	_wheel = _layer("Wheel", func(m: SafeMesh): GridValley.paint_wheel(m, Color.WHITE))
	_wheel.position = GridValley.WHEEL_AT
	var wheel_lights := GridLights.new()
	GridValley.wheel_lights(wheel_lights)
	_wheel_lights = _mesh_node("WheelLights", wheel_lights.mesh(), _lights_mat)
	_wheel_lights.position = GridValley.WHEEL_AT
	var town := GridLights.new()
	GridValley.lights(town)
	_lights = _mesh_node("Lights", town.mesh(), _lights_mat)
	_town_glow = _glow_sprite("TownGlow", Vector2(1200, 760), Vector2(1400, 420), Color(1.0, 0.72, 0.42))
	_wires_mat = ShaderMaterial.new()
	_wires_mat.shader = WiresShader
	_wires = _mesh_node("Wires", _wire_mesh(), _wires_mat)
	for i in CARS:
		var car := _glow_sprite("Car%d" % i, Vector2.ZERO, Vector2(16, 9), Color(1.0, 0.92, 0.7))
		_cars.append(car)
	_smoke = _make_smoke()
	add_child(_smoke)
	_fireflies = _make_fireflies()
	add_child(_fireflies)
	_build_machine()
	_build_storm()
	for i in FIREWORK_AT.size():
		var f := _make_firework(FIREWORK_AT[i], [Color(1.0, 0.75, 0.3), Color(0.55, 0.85, 1.0), Color(1.0, 0.45, 0.55)][i])
		_fireworks.append(f)
		add_child(f)
	_apply()


func _build_machine() -> void:
	_lamp_glow = _glow_sprite("LampGlow", GridShed.LAMP + Vector2(90, 40), Vector2(640, 500), Color(1.0, 0.74, 0.42))
	_coil_glow = _glow_sprite("CoilGlow", GridShed.DYNAMO.get_center(), Vector2(240, 220), Color(1.0, 0.6, 0.28))
	_flywheel = _layer("Flywheel", GridShed.paint_flywheel)
	_flywheel.position = GridShed.FLYWHEEL
	_pulley = _layer("Pulley", GridShed.paint_pulley)
	_pulley.position = GridShed.PULLEY
	_crank = _layer("Crank", GridShed.paint_crank)
	_crank.position = GridShed.CRANK
	for i in 2:
		var p := _layer("Pedal%d" % i, GridShed.paint_pedal)
		_pedals.append(p)
	_needle = _layer("Needle", GridShed.paint_needle)
	_needle.position = GridShed.METER
	_marker = _layer("Marker", GridShed.paint_marker)
	_marker.position = GridShed.METER
	_brushes = _make_brushes()
	add_child(_brushes)


func _build_storm() -> void:
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = RainShader
	_rain = ColorRect.new()
	_rain.name = "Rain"
	_rain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rain.position = RAIN_RECT.position
	_rain.size = RAIN_RECT.size
	_rain.material = _rain_mat
	_rain.visible = false
	add_child(_rain)
	_storm_cloud = _layer("StormCloud", _paint_storm_cloud)
	_storm_cloud.visible = false
	_bolt = _layer("Bolt", _paint_bolt)
	_bolt.visible = false
	_sparks = _make_sparks()
	add_child(_sparks)


func _make_bake(bake_name: String, night: int) -> SubViewport:
	var bake := SubViewport.new()
	bake.name = bake_name
	bake.disable_3d = true
	bake.gui_disable_input = true
	bake.size = Vector2i(GridValley.WIDE)
	bake.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(bake)
	var layer := Layer.new()
	layer.name = "Valley"
	layer.position = Vector2(GridValley.BLEED, 0)
	layer.batch = valley_batch(night)
	bake.add_child(layer)
	bakes += 1
	return bake


## The valley and the shed in one palette, built once for the engine's life.
static func valley_batch(night: int) -> SafeMesh:
	return SafeMesh.built("grid_valley_%d" % night, func(m: SafeMesh) -> void:
		GridValley.paint(m, night)
		GridShed.paint(m, night)
		GridValley.vignette(m, night))


func _layer(layer_name: String, paint: Callable) -> Layer:
	var l := Layer.new()
	l.name = layer_name
	l.paint = paint
	add_child(l)
	return l


func _mesh_node(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance2D:
	var mi := MeshInstance2D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material = mat
	add_child(mi)
	return mi


func _lights_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LightsShader
	return m


func _glow_sprite(node_name: String, at: Vector2, size: Vector2, color: Color) -> Sprite2D:
	var s := Sprite2D.new()
	s.name = node_name
	s.texture = SafePlaces.soft_dot()
	s.position = at
	s.scale = size / float(SafePlaces.soft_dot().get_width())
	s.modulate = color
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	s.material = add
	add_child(s)
	return s


func _star_mesh() -> ArrayMesh:
	var m := GridLights.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 150:
		var at := Vector2(rng.randf_range(GridValley.LEFT, GridValley.RIGHT), rng.randf_range(6.0, GridValley.RIDGE_TOP - 8.0))
		m.glow(at, Vector2.ONE * rng.randf_range(1.6, 3.4), Color(1, 0.97, 0.92, rng.randf_range(0.5, 1.0)), 0, rng.randf_range(0.0, 0.9), rng.randf())
	return m.mesh()


func _river_mesh() -> ArrayMesh:
	var edges := GridValley.river_edges()
	var left: PackedVector2Array = edges[0]
	var right: PackedVector2Array = edges[1]
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for k in left.size():
		var v := float(k) / (left.size() - 1)
		verts.append(left[k])
		verts.append(right[k])
		uvs.append(Vector2(0, v))
		uvs.append(Vector2(1, v))
		if k > 0:
			var i := 2 * k
			index.append_array(PackedInt32Array([i - 2, i - 1, i + 1, i - 2, i + 1, i]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


func _wire_mesh() -> ArrayMesh:
	var m := GridLights.new()
	for w in GridValley.wires():
		m.strip(w.points, 3.5, int(w.channel))
	return m.mesh()


func _paint_moon(m: SafeMesh) -> void:
	var r := MOON_R
	m.glow(Vector2.ZERO, Vector2.ONE * r * 3.2, Color(0.72, 0.8, 1.0, 0.22), 10)
	m.circle(Vector2.ZERO, r, Color("efe9d6"))
	for c in [[Vector2(-10, -8), 8.0], [Vector2(11, 6), 6.0], [Vector2(-4, 15), 4.5], [Vector2(13, -14), 3.5]]:
		m.circle(c[0], c[1], Color("d4cdb8"), false)


func _paint_cloud(m: SafeMesh, i: int) -> void:
	var w: float = CLOUDS[i][2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 40 + i
	for k in 7:
		var at := Vector2(rng.randf_range(-w * 0.5, w * 0.5), rng.randf_range(-9.0, 9.0))
		m.glow(at, Vector2(rng.randf_range(w * 0.2, w * 0.42), rng.randf_range(11.0, 20.0)), Color(1, 1, 1, 0.7), 7, 0.3)


## Three birds as plain chevrons: wings only, no head and no tail.
func _paint_birds(m: SafeMesh) -> void:
	for b in [Vector2(0, 0), Vector2(30, -13), Vector2(38, 15)]:
		m.line(b + Vector2(-11, -4), b, 2.5, Color.WHITE)
		m.line(b, b + Vector2(11, -4), 2.5, Color.WHITE)


func _paint_storm_cloud(m: SafeMesh) -> void:
	var r := STORM_RECT
	var rng := RandomNumberGenerator.new()
	rng.seed = 8
	var dark := Color("23233f")
	for k in 26:
		var at := Vector2(rng.randf_range(r.position.x, r.end.x), rng.randf_range(r.position.y + 46.0, r.end.y - 34.0))
		var rad := Vector2(rng.randf_range(90, 180), rng.randf_range(26, 42))
		m.glow(at, rad, Color(dark, 0.9), 7, 0.5)
	for k in 14:
		var at := Vector2(rng.randf_range(r.position.x + 40.0, r.end.x - 40.0), rng.randf_range(r.position.y + 44.0, r.position.y + 76.0))
		m.glow(at, Vector2(rng.randf_range(60, 120), 16), Color("4a4a72", 0.6), 6, 0.3)


func _paint_bolt(m: SafeMesh) -> void:
	var from := Vector2(_bolt_to.x + _bolt_rng.randf_range(-90, 90), BOLT_FROM_Y)
	var pts := PackedVector2Array([from])
	var n := 7
	for k in range(1, n):
		var t := float(k) / n
		pts.append(from.lerp(_bolt_to, t) + Vector2(_bolt_rng.randf_range(-26, 26), 0))
	pts.append(_bolt_to)
	for k in pts.size() - 1:
		m.line(pts[k], pts[k + 1], 9.0, Color(0.6, 0.72, 1.0, 0.4))
		m.line(pts[k], pts[k + 1], 3.5, Color(0.96, 0.98, 1.0))


func _make_smoke() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Smoke"
	p.texture = SafePlaces.soft_dot()
	p.position = Vector2(860, 610)
	p.amount = 10
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(120, 6)
	p.direction = Vector2(0.3, -1)
	p.spread = 12.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 6.0
	p.initial_velocity_max = 11.0
	p.scale_amount_min = 0.3
	p.scale_amount_max = 0.9
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.8, 0.85, 0.0))
	ramp.add_point(0.25, Color(0.85, 0.8, 0.85, 0.16))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.85, 0.8, 0.85, 0.0))
	p.color_ramp = ramp
	return p


func _make_fireflies() -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = "Fireflies"
	p.texture = SafePlaces.soft_dot()
	p.position = Vector2(1080, 960)
	p.amount = 14
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(420, 60)
	p.direction = Vector2(1, -0.2)
	p.spread = 180.0
	p.gravity = Vector2.ZERO
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 10.0
	p.scale_amount_min = 0.14
	p.scale_amount_max = 0.24
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.9, 1.0, 0.5, 0.0))
	ramp.add_point(0.5, Color(0.9, 1.0, 0.5, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.9, 1.0, 0.5, 0.0))
	p.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	return p


func _make_brushes() -> CPUParticles2D:
	var p := _spark_base("Brushes", 6, 0.35)
	p.position = Vector2(GridShed.DYNAMO.end.x - 18.0, GridShed.DYNAMO.position.y)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 80.0
	p.gravity = Vector2(0, 240)
	p.emitting = false
	return p


func _make_sparks() -> CPUParticles2D:
	var p := _spark_base("LineSparks", 16, 0.6)
	p.initial_velocity_min = 60.0
	p.initial_velocity_max = 150.0
	p.gravity = Vector2(0, 380)
	p.emitting = false
	return p


func _spark_base(node_name: String, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.name = node_name
	p.texture = SafePlaces.soft_dot()
	p.amount = amount
	p.lifetime = life
	p.direction = Vector2(0, -1)
	p.spread = 80.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.24
	p.color = Color(1.0, 0.86, 0.5)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	return p


## A firework: round dots flung evenly outward, fading. Dots only: no tails.
func _make_firework(at: Vector2, color: Color) -> CPUParticles2D:
	var p := _spark_base("Firework", 34, 1.5)
	p.position = at
	p.one_shot = true
	p.explosiveness = 1.0
	p.spread = 180.0
	p.gravity = Vector2(0, 46)
	p.initial_velocity_min = FIREWORK_SPEED * 0.45
	p.initial_velocity_max = FIREWORK_SPEED
	p.damping_min = 50.0
	p.damping_max = 70.0
	p.scale_amount_min = 0.2
	p.scale_amount_max = 0.34
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color.lerp(Color.WHITE, 0.5), 1.0))
	ramp.add_point(0.55, Color(color, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(color, 0.0))
	p.color_ramp = ramp
	p.color = Color.WHITE
	p.emitting = false
	return p


# --- Each frame ---

## The view each frame: `levels` (the four districts, 0-1), the sky's `night` (0-1), `supply` and
## `need` (0-1 along the meter's scale), `cadence` (rpm), and whether power is going out (`running`).
func update_view(delta: float, levels: Vector4, night: float, supply: float, need: float, cadence: float, running: bool) -> void:
	var rise := delta / RISE_SEC
	var fall := delta / FALL_SEC
	for i in 4:
		var target := levels[i]
		_levels[i] = move_toward(_levels[i], target, rise if target > _levels[i] else fall)
	var flicker := Vector4.ZERO
	for i in 4:
		if levels[i] > 0.0 and levels[i] < 1.0:
			flicker[i] = 1.0
	_night = move_toward(_night, night, delta * maxf(absf(night - _night) * 0.5, 0.01))
	_supply = move_toward(_supply, clampf(supply, 0.0, 1.0), delta * 1.2)
	_needle_shown = move_toward(_needle_shown, clampf(supply, 0.0, 1.02), delta * maxf(absf(supply - _needle_shown) * 5.0, 0.05))
	_marker_shown = move_toward(_marker_shown, clampf(need, 0.0, 1.0), delta * 0.6)
	_step_machine(delta, cadence)
	_wire_phase = fmod(_wire_phase + delta * WIRE_PX * _supply * (1.0 if running else 0.15), 46000.0)
	_chase = fmod(_chase + delta * CHASE_HZ, 4000.0)
	_lights_mat.set_shader_parameter("flicker", Color(flicker.x, flicker.y, flicker.z, flicker.w))
	_wheel.rotation += delta * TAU / WHEEL_SEC * _levels.z
	_wheel_lights.rotation = _wheel.rotation
	_step_ambient(delta)
	_step_storm(delta)
	_apply()


func _step_machine(delta: float, cadence: float) -> void:
	_crank_angle = fmod(_crank_angle + delta * TAU * cadence / 60.0, TAU)
	_crank.rotation = _crank_angle
	_flywheel.rotation = fmod(_flywheel.rotation + delta * TAU * cadence / 60.0 * 0.62, TAU)
	_pulley.rotation = fmod(_pulley.rotation + delta * TAU * cadence / 60.0 * 2.8, TAU)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		_pedals[i].position = GridShed.CRANK + Vector2(0, side * GridShed.CRANK_ARM).rotated(_crank_angle)
	_needle.rotation = GridShed.meter_angle(_needle_shown)
	_marker.rotation = GridShed.meter_angle(_marker_shown)
	_brushes.emitting = _supply > 0.45 and cadence > 40.0


func _step_ambient(delta: float) -> void:
	for i in _clouds.size():
		var c := _clouds[i]
		c.position.x += delta * CLOUD_PX * (0.7 + 0.3 * i)
		if c.position.x > GridValley.RIGHT + 300.0:
			c.position.x = GridValley.LEFT - 300.0
	_bird_t = fposmod(_bird_t + delta / BIRDS_SEC, 1.0)
	_birds.position = BIRDS_FROM.lerp(BIRDS_TO, _bird_t)
	# The cars run along the road; their lamps come on with the streetlights.
	for i in CARS:
		_car_t[i] = fposmod(_car_t[i] + delta * CAR_PX / 1500.0 * (1.0 if i != 1 else -1.0), 1.0)
		var x := lerpf(560.0, 1900.0, _car_t[i])
		_cars[i].position = Vector2(x, GridValley.road_y(x) + (2.0 if i != 1 else -2.0))


func _step_storm(delta: float) -> void:
	_storm = move_toward(_storm, _storm_target, delta / 1.4)
	_rain_fall += delta * 5.0
	var showing := _storm > 0.01
	_storm_cloud.visible = showing
	_rain.visible = showing
	_storm_cloud.modulate.a = _storm
	_rain_mat.set_shader_parameter("amount", _storm)
	_rain_mat.set_shader_parameter("fall", _rain_fall)
	for i in range(_flashes.size() - 1, -1, -1):
		_flashes[i] -= delta
		if _flashes[i] <= 0.0:
			_flashes.remove_at(i)
			_flash = maxf(_flash, 0.3)
	_flash = move_toward(_flash, 0.0, delta * 1.6)


## Pushes the state to the shaders and the fades. Only uniforms and modulates: no redraws.
func _apply() -> void:
	var lv := Color(_levels.x, _levels.y, _levels.z, _levels.w)
	_lights_mat.set_shader_parameter("levels", lv)
	_lights_mat.set_shader_parameter("night", _night)
	_lights_mat.set_shader_parameter("chase", floorf(_chase))
	_sky_mat.set_shader_parameter("night", _night)
	_sky_mat.set_shader_parameter("flash", _flash)
	_sky_mat.set_shader_parameter("gloom", _storm)
	_wires_mat.set_shader_parameter("phase", _wire_phase)
	_wires_mat.set_shader_parameter("glow", clampf(_supply * 1.3, 0.0, 1.0))
	_wires_mat.set_shader_parameter("levels", lv)
	var star := smoothstep(0.35, 0.95, _night)
	_stars_mat.set_shader_parameter("levels", Color(star * (1.0 - 0.8 * _storm), 0, 0, 0))
	_stars.visible = star > 0.01
	var moon_t := smoothstep(0.2, 1.0, _night)
	_moon.position = MOON_FROM.lerp(MOON_TO, moon_t)
	_moon.modulate.a = smoothstep(0.15, 0.55, _night) * (1.0 - _storm)
	_moon.visible = _moon.modulate.a > 0.01
	var cloud_col := Color("e2a0a0").lerp(Color("232c56"), _night)
	for c in _clouds:
		c.modulate = Color(cloud_col, lerpf(0.5, 0.75, _night))
	_birds.modulate = Color(Color("3a2c48"), 0.75 * (1.0 - smoothstep(0.3, 0.6, _night)))
	_birds.visible = _birds.modulate.a > 0.01
	_river_mat.set_shader_parameter("tint", Color("ffcf9a").lerp(Color("8fb0ff"), _night))
	_river_mat.set_shader_parameter("strength", lerpf(0.5, 0.34, _night))
	_wheel.modulate = Color("3a3648").lerp(Color("141a34"), _night)
	var total := (_levels.x + _levels.y + _levels.z * 1.2 + _levels.w * 1.4) / 4.6
	_town_glow.modulate.a = total * lerpf(0.06, 0.16, _night)
	_town_glow.visible = _town_glow.modulate.a > 0.004
	_lamp_glow.modulate.a = lerpf(0.16, 0.1, _night) + lerpf(0.34, 0.2, _night) * _supply
	_coil_glow.modulate.a = 0.5 * _supply * _supply
	for car in _cars:
		car.modulate.a = _levels.y
		car.visible = _levels.y > 0.01
	_fireflies.emitting = _night > 0.6
	_fireflies.visible = _night > 0.5
	_smoke.modulate.a = 1.0 - 0.75 * _night


# --- Events ---

## Lightning on the hills: the cloud bank rolls in and it flickers, at most twice.
func storm_warning(warn_sec: float) -> void:
	_storm_target = 1.0
	_flashes.append(warn_sec * 0.3)
	_flashes.append(warn_sec * 0.75)


## The strike: a bolt on district `index`'s pylon, sparks, and its wire goes dark.
func strike(index: int) -> void:
	_down = index
	var at := strike_point(index)
	_bolt_to = at
	_bolt.queue_redraw()
	_bolt.visible = true
	_flash = 0.42
	var t := create_tween()
	t.tween_interval(0.28)
	t.tween_callback(func(): _bolt.visible = false)
	_sparks.position = at
	_sparks.emitting = true


## Where lightning hits district `index`'s line: its feeder's pylon.
static func strike_point(index: int) -> Vector2:
	return GridValley.pylon_top(int(GridValley.FEEDERS[index][0]))


## The storm has passed (repaired or fixed by the crew).
func storm_over() -> void:
	_storm_target = 0.0
	_down = -1
	_sparks.emitting = false


## Fireworks over the fair: all three, a little apart.
func celebrate() -> void:
	var t := create_tween()
	for f in _fireworks:
		t.tween_callback(func() -> void:
			f.restart()
			f.emitting = true)
		t.tween_interval(0.45)


## A posed scene for stills (the hub card, the captures): straight to these levels.
func pose(levels: Vector4, night: float, supply: float, need: float) -> void:
	_levels = levels
	_night = night
	_supply = supply
	_needle_shown = supply
	_marker_shown = need
	_needle.rotation = GridShed.meter_angle(supply)
	_marker.rotation = GridShed.meter_angle(need)
	_apply()


## Draws every effect that starts hidden once, behind the intro card, so its shader compiles then.
func prewarm() -> void:
	_rain.visible = true
	_storm_cloud.visible = true
	_storm_cloud.modulate.a = 0.0
	_bolt.visible = true
	_bolt.modulate.a = 0.0
	for i in WARM_FRAMES:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_bolt.visible = false
	_bolt.modulate.a = 1.0
	_rain.visible = false
	_storm_cloud.visible = false


# --- Bounds (grid_layout_test: nothing clipped by the frame, the ground line or a HUD panel) ---

## Every prop that stands in the scene, by name, on the canvas.
static func prop_rects() -> Dictionary:
	var out := {"shed": GridShed.bounds()}
	for i in GridValley.PYLONS.size():
		var top := GridValley.pylon_top(i)
		var h := float(GridValley.PYLONS[i][1])
		out["pylon_%d" % i] = Rect2(top.x - h * 0.2, top.y - h * 0.06, h * 0.4, h * 1.06)
	var r := GridValley.WHEEL_R + 6.0
	out["wheel"] = Rect2(GridValley.WHEEL_AT - Vector2(r, r), Vector2(r, r) * 2.0)
	for i in GridValley.MASTS.size():
		var at: Vector2 = GridValley.MASTS[i]
		out["mast_%d" % i] = Rect2(at.x - 20.0, at.y - GridValley.MAST_H - 14.0, 40.0, GridValley.MAST_H + 14.0)
	out["steeple"] = Rect2(GridValley.CHURCH_AT + Vector2(-50, -160), Vector2(124, 160))
	out["ridge"] = Rect2(0.0, GridValley.RIDGE_TOP, GridValley.SIZE.x, 40.0)
	return out


## The moon's box at each end of its path.
static func moon_rects() -> Array[Rect2]:
	var e := Vector2.ONE * MOON_R
	return [Rect2(MOON_FROM - e, e * 2.0), Rect2(MOON_TO - e, e * 2.0)]


## The sky's drifting scenery (clouds, birds, the storm's bank) stays in this band.
static func sky_band_rect(y_from: float) -> Rect2:
	return Rect2(0.0, y_from, GridValley.SIZE.x, 10.0)


## How high a firework reaches: its fastest spark, with no drag (an upper bound).
static func firework_top() -> float:
	var top := INF
	for at: Vector2 in FIREWORK_AT:
		top = minf(top, at.y - FIREWORK_SPEED * 1.5 * 0.6)
	return top
