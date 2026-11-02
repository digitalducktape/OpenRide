class_name PumpWorld
extends Node3D
## Balloon Pump's 3D view (#76), first person from the bike: a big brass pump on a rug in front
## of a candy-striped fairground stall at noon. The pump's plunger rises and falls with each pedal
## stroke, its gauge shows the needle against the push line, a hose runs to the nozzle where the
## balloon grows, the next balloon waits on the rack, and every tied balloon floats up into the
## bunch over the stall. The look is in ART_BIBLE.md (this folder).
##
## It only draws: `PumpLogic` holds the rules, and the game tells it the state each frame
## (`update_view`) and the events (`tie_off`, `load`, `celebrate`). The tablet recipe (docs/GAMES.md,
## "World look (3D)"): every surface unshaded and lit by hand on the shared look (`WorldLook`,
## shaders/pump_look.gdshaderinc), the statics baked into one vertex-coloured mesh (`PumpMeshes`),
## the bunch one MultiMesh that sways in its shader. Per frame, GDScript moves the plunger, scales
## the nozzle's balloon, flies at most one tied balloon and sets a few uniforms.

const EYE_HEIGHT := 1.5
const CAMERA_PITCH := -3.0
const FOV := 60.0
const BUNCH_MAX := 48  ## the bunch shows at most this many; later balloons replace the oldest
const FLIGHT_SEC := 1.9
const STROKE := 0.2  ## the plunger's travel, metres
## The plunger's foot at the top of its stroke (its handle then about 1.8 m up, under the HUD).
const PLUNGER_REST := 1.25
const RACK_SCALE := 0.45  ## the next balloon on the rack, part-blown, as a share of its size
const WARM_FRAMES := 3
const SHADERS := "res://games/balloon_pump/shaders/"

## The light (WorldLook's uniforms): one fixed noon.
const LOOK := {
	&"sun_color": Color(0.8, 0.76, 0.68),
	&"sky_color": Color(0.52, 0.6, 0.72),
	&"ground_color": Color(0.34, 0.36, 0.26),
	&"haze_color": Color(0.8, 0.9, 0.97),
	&"haze_density": 0.006,
	&"haze_max": 0.75,
}
const SUN_ELEVATION := 58.0
const SUN_AZIMUTH := -150.0  ## behind the rider's left shoulder, so the stall faces the sun

var camera: Camera3D

var _noise: ImageTexture
var _lit: Array[ShaderMaterial] = []
var _sky_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _brass_mat: ShaderMaterial
var _gauge_mat: ShaderMaterial
var _plunger: MeshInstance3D
var _wheel: MeshInstance3D
var _nozzle: MeshInstance3D
var _nozzle_mat: ShaderMaterial
var _rack: MeshInstance3D
var _rack_mat: ShaderMaterial
var _flyer: MeshInstance3D
var _flyer_mat: ShaderMaterial
var _bunch_mm: MultiMesh
var _bunch_mat: ShaderMaterial
var _confetti: CPUParticles3D
var _hiss: CPUParticles3D

var _kind := ""
var _fill_shown := 0.0
var _stroke_phase := 0.0
var _wobble := 0.0
var _flight := -1.0  ## 0-1 through a tied balloon's flight, -1 when none flies
var _flight_kind := ""
var _flight_from := Transform3D()
var _flight_slot := 0
var _bunch_count := 0  ## balloons tied so far (the bunch shows the last BUNCH_MAX)
var _slot_kinds := {}  ## bunch slot → the kind shown there
var _bob := 0.0
var _load_t := 1.0  ## 0-1 through a new balloon sliding onto the nozzle
var _warming := false
var _t := 0.0


func _ready() -> void:
	_noise = WorldLook.noise_texture()
	_build_environment()
	_build_scenery()
	_build_pump()
	_build_balloons()
	_build_bunch()
	_build_fx()
	_build_rig()
	WorldLook.apply(_lit, look())


## The light for every hand-lit material (WorldLook's uniforms, the sun from its angles).
static func look() -> Dictionary:
	var l := LOOK.duplicate()
	l[&"sun_dir"] = WorldLook.sun_dir(SUN_ELEVATION, SUN_AZIMUTH)
	return l


## The nozzle's balloon kind and the rack's (a new balloon was loaded, or at the start).
func set_balloons(kind: String, next_kind: String) -> void:
	if kind != _kind:
		_kind = kind
		_load_t = 0.0
		_fill_shown = 0.0
		_paint(_nozzle_mat, kind)
	_paint(_rack_mat, next_kind)
	_rack.scale = Vector3.ONE * PumpMeshes.BALLOON_RADIUS[next_kind] * RACK_SCALE


## The view each frame: `fill` (0-1) of the nozzle's balloon, whether it `leaks`, the valve's
## `open` (0-1), the gauge's `needle` and `line` (0-1 along its scale), and the cadence (rpm) that
## drives the plunger. `loaded` is false while no balloon is on the nozzle (tie and load).
func update_view(delta: float, fill: float, leaks: bool, open: float, needle: float, line: float,
		cadence: float, loaded := true) -> void:
	_t += delta
	_wheel.rotation.z = fmod(_wheel.rotation.z + delta * 0.06, TAU)
	# The plunger: one stroke per pedal revolution, eased at the ends.
	_stroke_phase = fmod(_stroke_phase + delta * cadence / 60.0, 1.0)
	var down := 0.5 - 0.5 * cos(_stroke_phase * TAU)
	_plunger.position.y = PLUNGER_REST - down * STROKE * clampf(cadence / 40.0, 0.0, 1.0)
	# The gauge.
	_gauge_mat.set_shader_parameter("needle", needle)
	_gauge_mat.set_shader_parameter("line", line)
	_gauge_mat.set_shader_parameter("filling", open)
	# The nozzle's balloon: it eases toward the fill, so the 30 Hz steps never show.
	_load_t = minf(_load_t + delta / 0.35, 1.0)
	_nozzle.visible = loaded or _load_t < 1.0
	if loaded:
		_fill_shown = move_toward(_fill_shown, fill, delta * maxf(absf(fill - _fill_shown) * 8.0, 0.05))
	_wobble = move_toward(_wobble, 1.0 if leaks and loaded else 0.0, delta * 2.5)
	_place_nozzle_balloon()
	_nozzle_mat.set_shader_parameter("taut", smoothstep(0.55, 1.0, _fill_shown))
	_nozzle_mat.set_shader_parameter("wobble", _wobble)
	_hiss.emitting = _wobble > 0.5 and _fill_shown > 0.1
	# A tied balloon on its way up.
	if _flight >= 0.0:
		_flight = minf(_flight + delta / FLIGHT_SEC, 1.0)
		_place_flyer()
		if _flight >= 1.0:
			_land_flyer()
	if _bob > 0.0:
		_bob = move_toward(_bob, 0.0, delta * 0.4)
		_bunch_mat.set_shader_parameter("bob", _bob)


## The nozzle's balloon is full and tied: it pops off with confetti and floats up into the bunch.
func tie_off(kind: String) -> void:
	if _flight >= 0.0:
		_land_flyer()
	_flight_kind = kind
	_flight_from = _nozzle.transform
	_flight_slot = _bunch_count % BUNCH_MAX
	_flight = 0.0
	_paint(_flyer_mat, kind)
	_flyer.visible = true
	_place_flyer()
	_nozzle.visible = false
	_fill_shown = 0.0
	_kind = ""
	_burst(PumpMeshes.NOZZLE_POS + Vector3(0, 0.5, 0), kind == "gold")


## A Race heat won: confetti over the stall and the bunch bobs.
func celebrate() -> void:
	_burst(PumpMeshes.TETHER + Vector3(0, 1.8, 0), true)
	_bob = 1.0


## A posed scene for stills (the hub card): the bunch holds `tied` (kinds) and the nozzle a
## balloon of `kind` at `fill`.
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
	_nozzle_mat.set_shader_parameter("taut", smoothstep(0.55, 1.0, fill))


func bunch_count() -> int:
	return _bunch_count


## Draws every effect that starts hidden once, behind the intro card, so its shader compiles then
## (the Compatibility renderer compiles a material the first time it draws it).
func prewarm() -> void:
	_warming = true
	_flyer.visible = true
	_flyer.position = Vector3(0, -5, -6)
	_confetti.position = Vector3(0, -5, -6)
	_confetti.restart()
	_confetti.emitting = true
	_hiss.emitting = true
	_bunch_mm.visible_instance_count = 1
	_bunch_mm.set_instance_transform(0, Transform3D(Basis.IDENTITY, Vector3(0, -5, -6)))
	for i in WARM_FRAMES:
		await get_tree().process_frame
	if not is_inside_tree():
		return
	_warming = false
	_hiss.emitting = false
	_confetti.emitting = false
	if _flight < 0.0:
		_flyer.visible = false
	_bunch_mm.visible_instance_count = mini(_bunch_count, BUNCH_MAX)
	for i in mini(_bunch_count, BUNCH_MAX):
		_set_slot(i, _slot_kinds.get(i, "small"))


# --- Balloons ---

func _paint(mat: ShaderMaterial, kind: String) -> void:
	mat.set_shader_parameter("body_color", PumpMeshes.lin(PumpMeshes.BALLOON_COLORS[kind]))
	mat.set_shader_parameter("gold", 1.0 if kind == "gold" else 0.0)


func _place_nozzle_balloon() -> void:
	if _kind == "":
		return
	var r: float = PumpMeshes.BALLOON_RADIUS[_kind]
	var f := _fill_shown
	var s := r * lerpf(0.26, 1.0, pow(f, 0.6))
	var limp := 1.0 + 0.22 * (1.0 - f) * (1.0 - f)
	# A new balloon slides down onto the nozzle.
	var slide := (1.0 - ease(_load_t, 0.4)) * 0.25
	# It sways a little on its neck.
	var sway := Vector3(sin(_t * 1.3) * 0.03, 0.0, sin(_t * 1.7) * 0.025) * (0.3 + f)
	_nozzle.transform = Transform3D(Basis.from_euler(sway).scaled(Vector3(s, s * limp, s)),
		PumpMeshes.NOZZLE_POS + Vector3(0, slide, 0))


## Bunch slot `i`'s transform (an instance of PumpMeshes.bunch_balloon: its centre, local -Y
## toward the tether) and its string's length in local units, for a balloon of `kind`.
func _slot(i: int, kind: String) -> Array:
	var golden := 2.39996
	var a := i * golden
	var k := sqrt(float(i + 1) / BUNCH_MAX)
	var tilt := 0.12 + 0.5 * k
	var length := 1.15 + 0.35 * k + 0.1 * float(i % 3)
	var dir := Vector3(cos(a) * sin(tilt), cos(tilt), sin(a) * sin(tilt) * 0.55).normalized()
	var center := PumpMeshes.TETHER + dir * length
	var s: float = PumpMeshes.BALLOON_RADIUS[kind] * 0.9
	var x := dir.cross(Vector3.BACK).normalized()
	var z := x.cross(dir)
	var basis := Basis(x * s, dir * s, z * s)
	return [Transform3D(basis, center), length / s + PumpMeshes.BUNCH_KNOT]


func _set_slot(i: int, kind: String) -> void:
	var slot := _slot(i, kind)
	_bunch_mm.set_instance_transform(i, slot[0])
	_bunch_mm.set_instance_color(i, PumpMeshes.lin(PumpMeshes.BALLOON_COLORS[kind]))
	_bunch_mm.set_instance_custom_data(i, Color(fmod(i * 0.618, 1.0), 1.0 if kind == "gold" else 0.0, slot[1], 0.0))


## The flyer's path: from the nozzle, up and over in an arc, to its slot's knot, turning to point
## along its string.
func _place_flyer() -> void:
	var slot: Array = _slot(_flight_slot, _flight_kind)
	var target: Transform3D = slot[0]
	var dir := target.basis.y.normalized()
	var s: float = target.basis.y.length()
	var end_knot := target.origin + dir * s * PumpMeshes.BUNCH_KNOT
	var t := ease(_flight, -1.8)
	var start := _flight_from.origin
	var p := start.lerp(end_knot, t)
	p.y += sin(t * PI) * 0.45
	p.x += sin(t * PI) * 0.2
	var r: float = PumpMeshes.BALLOON_RADIUS[_flight_kind]
	var from_basis := Basis.IDENTITY.scaled(Vector3.ONE * r)
	var to_basis := Basis(target.basis.x.normalized() * s, dir * s, target.basis.z.normalized() * s)
	var b := Basis(from_basis.get_rotation_quaternion().slerp(to_basis.get_rotation_quaternion(), t))
	var scale_now := lerpf(r, s, t)
	# A spin of the knot as it flies (a quick twirl, then settled).
	b = b * Basis(Vector3.UP, sin(t * PI) * 1.2)
	_flyer.transform = Transform3D(b.scaled(Vector3.ONE * scale_now), p)


func _land_flyer() -> void:
	_flight = -1.0
	_flyer.visible = _warming
	var slot := _flight_slot
	_slot_kinds[slot] = _flight_kind
	_set_slot(slot, _flight_kind)
	_bunch_count += 1
	_bunch_mm.visible_instance_count = mini(_bunch_count, BUNCH_MAX)


# --- Building ---

func _material(shader_file: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + shader_file)
	m.set_shader_parameter("noise_tex", _noise)
	_lit.append(m)
	return m


func _instance(mesh: Mesh, mat: Material, node_name: String, parent: Node3D = self) -> MeshInstance3D:
	var mi := KartMeshKit.mesh_node(mesh, mat, node_name)
	parent.add_child(mi)
	return mi


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load(SHADERS + "sky.gdshader")
	_sky_mat.set_shader_parameter("noise_tex", _noise)
	_lit.append(_sky_mat)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	# Drawn once into its radiance cubemap and sampled by the background (sky.gdshader).
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	# The sun only places the sky's halo (LIGHT0_DIRECTION); it lights nothing.
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	var to_sun := WorldLook.sun_dir(SUN_ELEVATION, SUN_AZIMUTH)
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	add_child(_sun)


func _build_scenery() -> void:
	var scenery := _instance(PumpMeshes.scenery(), _material("scenery.gdshader"), "Scenery")
	scenery.extra_cull_margin = 4.0
	_wheel = _instance(PumpMeshes.wheel(), _material("scenery.gdshader"), "Wheel")
	_wheel.position = PumpMeshes.WHEEL_POS


func _build_pump() -> void:
	_brass_mat = _material("scenery.gdshader")
	_brass_mat.set_shader_parameter("gloss", 1.0)
	_instance(PumpMeshes.brass(), _brass_mat, "Pump")
	_plunger = _instance(PumpMeshes.plunger(), _brass_mat, "Plunger")
	_plunger.position = PumpMeshes.PUMP_POS + Vector3(0, PLUNGER_REST, 0)
	_gauge_mat = _material("gauge.gdshader")
	var face := QuadMesh.new()
	face.size = Vector2.ONE * PumpMeshes.GAUGE_RADIUS * 2.0
	var gauge := _instance(face, _gauge_mat, "Gauge")
	gauge.position = PumpMeshes.gauge_center()


func _build_balloons() -> void:
	var mesh := PumpMeshes.balloon()
	_nozzle_mat = _material("balloon.gdshader")
	_nozzle = _instance(mesh, _nozzle_mat, "NozzleBalloon")
	_rack_mat = _material("balloon.gdshader")
	_rack = _instance(mesh, _rack_mat, "NextBalloon")
	_rack.position = PumpMeshes.RACK_POS
	_flyer_mat = _material("balloon.gdshader")
	_flyer_mat.set_shader_parameter("taut", 0.8)
	_flyer = _instance(mesh, _flyer_mat, "FlyingBalloon")
	_flyer.visible = false
	set_balloons("small", "medium")


func _build_bunch() -> void:
	_bunch_mm = MultiMesh.new()
	_bunch_mm.transform_format = MultiMesh.TRANSFORM_3D
	_bunch_mm.use_colors = true
	_bunch_mm.use_custom_data = true
	_bunch_mm.mesh = PumpMeshes.bunch_balloon()
	_bunch_mm.instance_count = BUNCH_MAX
	_bunch_mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Bunch"
	mmi.multimesh = _bunch_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bunch_mat = _material("bunch.gdshader")
	mmi.material_override = _bunch_mat
	mmi.extra_cull_margin = 6.0
	add_child(mmi)


func _build_fx() -> void:
	# Confetti: little paper squares tumbling down, one pooled one-shot emitter.
	var paper := QuadMesh.new()
	paper.size = Vector2(0.05, 0.035)
	var paper_mat := StandardMaterial3D.new()
	paper_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paper_mat.vertex_color_use_as_albedo = true
	paper_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	paper_mat.disable_fog = true
	paper.material = paper_mat
	_confetti = CPUParticles3D.new()
	_confetti.name = "Confetti"
	_confetti.mesh = paper
	_confetti.amount = 48
	_confetti.lifetime = 1.6
	_confetti.one_shot = true
	_confetti.emitting = false
	_confetti.explosiveness = 0.92
	_confetti.direction = Vector3.UP
	_confetti.spread = 70.0
	_confetti.initial_velocity_min = 1.6
	_confetti.initial_velocity_max = 3.2
	_confetti.gravity = Vector3(0, -3.2, 0)
	_confetti.damping_min = 1.0
	_confetti.damping_max = 2.0
	_confetti.angular_velocity_min = -400.0
	_confetti.angular_velocity_max = 400.0
	_confetti.particle_flag_rotate_y = true
	_confetti.local_coords = false
	var ramp := Gradient.new()
	ramp.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	ramp.colors = PackedColorArray([PumpMeshes.PINK, Color("ffc530"), Color("3fd0a8"), Color("6e7cff"), PumpMeshes.CREAM])
	ramp.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	_confetti.color_initial_ramp = ramp
	add_child(_confetti)
	# A hiss of air at the nozzle while the balloon leaks: a few faint puffs.
	var puff := SphereMesh.new()
	puff.radius = 0.02
	puff.height = 0.04
	puff.radial_segments = 6
	puff.rings = 3
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.albedo_color = Color(1, 1, 1, 0.45)
	puff_mat.disable_fog = true
	puff.material = puff_mat
	_hiss = CPUParticles3D.new()
	_hiss.name = "Hiss"
	_hiss.mesh = puff
	_hiss.amount = 8
	_hiss.lifetime = 0.6
	_hiss.emitting = false
	_hiss.direction = Vector3(1, 0.2, 0.3)
	_hiss.spread = 30.0
	_hiss.initial_velocity_min = 0.3
	_hiss.initial_velocity_max = 0.6
	_hiss.gravity = Vector3.ZERO
	_hiss.scale_amount_min = 0.6
	_hiss.scale_amount_max = 1.4
	_hiss.position = PumpMeshes.NOZZLE_POS + Vector3(0.05, 0.0, 0.05)
	add_child(_hiss)


func _burst(at: Vector3, big: bool) -> void:
	_confetti.position = at
	# A fixed amount (changing it reallocates the particles); a small burst just throws slower.
	_confetti.initial_velocity_max = 3.2 if big else 2.2
	_confetti.restart()
	_confetti.emitting = true


func _build_rig() -> void:
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 400.0
	camera.position = Vector3(0, EYE_HEIGHT, 0)
	camera.rotation_degrees = Vector3(CAMERA_PITCH, 0, 0)
	add_child(camera)
