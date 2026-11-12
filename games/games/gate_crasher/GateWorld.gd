class_name GateWorld
extends Node3D
## Gate Crasher's 3D view (#80), first person from the saddle: an outdoor arena on a clear morning,
## the horse's ears and mane ahead, painted fences with flower boxes round a loop, and a grandstand
## down the first straight. ART_BIBLE.md is the look.
##
## It only draws: `GateLogic` holds the rules, and `update_view` is told where the horse is. The
## tablet recipe (docs/GAMES.md "World look (3D)"): every surface is unshaded and lit by hand, the
## statics are one baked mesh, the crowd is one MultiMesh moved in its shader. Per frame, GDScript
## moves the rig and at most one falling rail.

const EYE_HEIGHT := 2.35
const CAMERA_PITCH := -6.5
const FOV := 68.0
const FAR := 620.0
const SKY_RADIUS := 600.0  ## inside FAR; the dome follows the camera
const STRIDE_M := 3.4  ## metres a canter stride covers
const BOB := 0.05  ## metres, at a full canter
const NOD := 3.2  ## degrees the neck nods with the stride
const BANK := 2.5  ## degrees the view leans into a turn
const RAIL_FALL_SEC := 0.7
const CROWD_FILL := 0.6
const CROWD_COLORS := [Color("d94a3a"), Color("f2c230"), Color("3a7fd9"), Color("2fc4b2"), Color("f4f1e8"),
	Color("8a4ad9"), Color("f28a30"), Color("2a2e33")]
## The morning (ART_BIBLE §3-4) for WorldLook.
const LOOK := {
	"sun_color": Color(0.62, 0.56, 0.44),
	"sky_color": Color(0.62, 0.68, 0.76),
	"ground_color": Color(0.5, 0.45, 0.36),
	"haze_color": Color(0.84, 0.86, 0.84),
	"haze_density": 0.0026,
	"haze_max": 0.7,
}
const SHADERS := "res://games/gate_crasher/shaders/"

var camera: Camera3D
var excitement := 0.0  ## 0-1, how much the crowd is cheering
var fences := 0

var _lit: Array[ShaderMaterial] = []
var _ground_mat: ShaderMaterial
var _scenery_mat: ShaderMaterial
var _horse_mat: ShaderMaterial
var _marker_mat: ShaderMaterial
var _crowd_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _rig: Node3D
var _horse: MeshInstance3D
var _sky: MeshInstance3D
var _scenery: MeshInstance3D
var _markers: MeshInstance3D
var _lower: Array[Node3D] = []  ## each fence's fixed rails
var _rails: Array[Node3D] = []  ## each fence's top rail
var _rail_home: Array[Transform3D] = []
var _falling := -1
var _fall_t := 0.0
var _dust: CPUParticles3D
var _confetti: CPUParticles3D
var _phase := 0.0
var _pitch := 0.0  ## degrees: the jump's rock
var _last_height := 0.0
var _stride_count := 0
var _excite_shown := -1.0
var _warming := 0
var _stage_shown := -1
var _active_shown := -1


func _ready() -> void:
	_build_materials()
	_build_environment()
	_build_ground()
	_build_rig()
	_build_crowd()
	_build_fx()
	set_process(false)


## Builds the course: `count` fences `spacing` metres apart with their take-off lines.
func build(count: int, spacing: float, line_gap: float, stripe_m: float) -> void:
	if fences == count and _scenery:
		reset_rails()
		return
	fences = count
	for old: Node3D in [_scenery, _markers] + _lower + _rails:
		if old:
			remove_child(old)
			old.free()
	_lower.clear()
	_rails.clear()
	_rail_home.clear()
	_scenery = MeshKit3D.mesh_node(GateMeshes.scenery(count, spacing), _scenery_mat, "Scenery")
	add_child(_scenery)
	_markers = MeshKit3D.mesh_node(GateMeshes.markers(count, spacing, line_gap, stripe_m), _marker_mat, "Markers")
	_markers.custom_aabb = AABB(Vector3(-60, -60, -130), Vector3(120, 70, 260))
	add_child(_markers)
	for k in count:
		var f := GateCourse.frame((k + 1) * spacing)
		var lower := MeshKit3D.mesh_node(GateMeshes.rails(k), _scenery_mat, "Rails%d" % k)
		lower.transform = f
		add_child(lower)
		_lower.append(lower)
		var top := MeshKit3D.mesh_node(GateMeshes.top_rail(k), _scenery_mat, "TopRail%d" % k)
		top.transform = f * Transform3D(Basis(), Vector3(0.0, GateMeshes.RAIL_HEIGHTS[-1], 0.0))
		add_child(top)
		_rails.append(top)
		_rail_home.append(top.transform)


## The rider's view this frame. `s` metres along the course, `speed` m/s, `height` the jump's height,
## `circle` the angle round the lost-camera circle of `radius` (0 on the course).
func update_view(delta: float, s: float, speed: float, height: float, circle: float, radius: float) -> void:
	_phase += speed * delta / STRIDE_M * TAU
	var canter := clampf(speed / 6.0, 0.0, 1.0)
	var gait := 0.0 if height > 0.02 else sin(_phase)
	var f := GateCourse.frame(s)
	var ahead := GateCourse.heading(s + 6.0)
	var yaw := lerp_angle(GateCourse.heading(s), ahead, 0.5)
	var at := f.origin
	if circle != 0.0:
		# A loop off to the left of the course, back to where it left.
		at += -f.basis.x * radius * (1.0 - cos(circle)) - f.basis.z * radius * sin(circle)
		yaw += circle
	var turn := wrapf(ahead - GateCourse.heading(s), -PI, PI)
	var climb := (height - _last_height) / delta if delta > 0.0 else 0.0
	_last_height = height
	_pitch = lerpf(_pitch, clampf(climb * 3.2, -9.0, 9.0), 1.0 - exp(-delta * 9.0))
	_rig.position = at + Vector3.UP * (height + gait * BOB * canter)
	_rig.rotation = Vector3(0.0, yaw, 0.0)
	camera.rotation_degrees = Vector3(CAMERA_PITCH + _pitch + gait * 0.5 * canter, 0.0, -rad_to_deg(turn) * BANK / 12.0)
	_horse.rotation_degrees.x = gait * NOD * canter + _pitch * 0.8
	_sky.position = _rig.position
	if _falling >= 0:
		_step_fall(delta)
	excitement = move_toward(excitement, 0.0, delta * 0.2)
	var shown := snappedf(excitement, 0.02)
	if shown != _excite_shown:
		_excite_shown = shown
		_crowd_mat.set_shader_parameter("excitement", shown)


## True once per stride (for the hoofbeats).
func take_stride() -> bool:
	var count := floori(_phase / TAU)
	if count != _stride_count:
		_stride_count = count
		return true
	return false


## The next fence's marker: `fence` in the round and `stage` (0 dark, 1-3 chevrons, 4 the line live).
func set_marker(fence: int, stage: int) -> void:
	if fence != _active_shown:
		_active_shown = fence
		_marker_mat.set_shader_parameter("active", float(fence))
	if stage != _stage_shown:
		_stage_shown = stage
		_marker_mat.set_shader_parameter("stage", float(stage))


## The top rail of fence `k` comes down, away from the horse.
func knock_rail(k: int) -> void:
	if _falling >= 0:
		_rails[_falling].transform = _landed(_falling)
	_falling = k
	_fall_t = 0.0


func reset_rails() -> void:
	_falling = -1
	for i in _rails.size():
		_rails[i].transform = _rail_home[i]


func landing_dust() -> void:
	_dust.global_position = Vector3(_rig.position.x, 0.2, _rig.position.z) - _rig.basis.z * 3.0
	_dust.restart()


func clear_round_burst() -> void:
	_confetti.global_position = _rig.position + _rig.basis * Vector3(0.0, 1.0, -14.0)
	_confetti.visible = true
	_confetti.restart()
	excitement = 1.0


## Draws the dust and confetti once behind the intro card, so their shaders compile then.
func prewarm() -> void:
	_warming = 3
	_dust.emitting = true
	_confetti.visible = true
	_confetti.restart()
	set_process(true)


func _process(_delta: float) -> void:
	if _warming <= 0:
		set_process(false)
		return
	_warming -= 1
	if _warming == 0:
		_dust.emitting = false
		_confetti.emitting = false
		_confetti.visible = false


func _landed(k: int) -> Transform3D:
	var drop := Transform3D(Basis(Vector3.BACK, 0.09), Vector3(0.0, 0.08 - GateMeshes.RAIL_HEIGHTS[-1], -1.4))
	return _rail_home[k] * drop


func _step_fall(delta: float) -> void:
	_fall_t = minf(_fall_t + delta / RAIL_FALL_SEC, 1.0)
	_rails[_falling].transform = _rail_home[_falling].interpolate_with(_landed(_falling), _fall_t * _fall_t)
	if _fall_t >= 1.0:
		_falling = -1


# --- Building ---

func _material(file: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADERS + file) as Shader
	_lit.append(mat)
	return mat


func _build_materials() -> void:
	_ground_mat = _material("ground.gdshader")
	_ground_mat.set_shader_parameter("straight", GateCourse.STRAIGHT)
	_ground_mat.set_shader_parameter("radius", GateCourse.RADIUS)
	_ground_mat.set_shader_parameter("track_half", GateMeshes.TRACK_HALF)
	_ground_mat.set_shader_parameter("ring", GateMeshes.RING_MARGIN)
	_scenery_mat = _material("scenery.gdshader")
	_scenery_mat.set_shader_parameter("sway", 0.03)
	_horse_mat = _material("scenery.gdshader")
	_horse_mat.set_shader_parameter("self_lit", 0.7)
	_horse_mat.set_shader_parameter("rim", 0.9)
	_horse_mat.set_shader_parameter("sway", 0.035)
	_marker_mat = _material("marker.gdshader")
	_crowd_mat = _material("crowd.gdshader")
	_sky_mat = _material("sky.gdshader")
	var look := LOOK.duplicate()
	look["sun_dir"] = WorldLook.sun_dir(38.0, 120.0)
	look["noise_tex"] = WorldLook.noise_texture()
	WorldLook.apply(_lit, look)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("9cc4e8")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.name = "Environment"
	we.environment = env
	add_child(we)
	var dome := SphereMesh.new()
	dome.radius = SKY_RADIUS
	dome.height = SKY_RADIUS * 2.0
	dome.radial_segments = 16
	dome.rings = 8
	_sky = MeshKit3D.mesh_node(dome, _sky_mat, "Sky")
	add_child(_sky)


func _build_ground() -> void:
	var ground := MeshKit3D.ground_grid(1000.0, 1000.0, 40, 40, 500.0)
	add_child(MeshKit3D.mesh_node(ground, _ground_mat, "Ground"))


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	camera.rotation_degrees.x = CAMERA_PITCH
	camera.fov = FOV
	camera.near = 0.05
	camera.far = FAR
	camera.current = true
	_rig.add_child(camera)
	_horse = MeshKit3D.mesh_node(GateMeshes.horse(), _horse_mat, "Horse")
	_horse.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	_rig.add_child(_horse)


func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 8080
	var transforms := []
	var custom := []
	var colors := []
	for t in GateMeshes.STAND_TIERS:
		var x := GateMeshes.STAND_X + GateMeshes.TIER_DEPTH * (t + 0.5)
		var y := GateMeshes.TIER_RISE * (t + 1)
		var z := GateMeshes.STAND_Z.x + 0.6
		while z < GateMeshes.STAND_Z.y - 0.6:
			if rng.randf() < CROWD_FILL:
				transforms.append(Transform3D(Basis(), Vector3(x + rng.randf_range(-0.2, 0.2), y, z)))
				custom.append(Color(rng.randf(), rng.randf_range(0.4, 1.0), rng.randf(), 0.0))
				colors.append(CROWD_COLORS[rng.randi() % CROWD_COLORS.size()])
			z += 0.85
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.85)
	quad.center_offset = Vector3(0.0, 0.425, 0.0)
	var crowd := MeshKit3D.multimesh_node(quad, transforms, "Crowd", custom, colors)
	crowd.material_override = _crowd_mat
	crowd.custom_aabb = AABB(Vector3(GateMeshes.STAND_X - 2.0, -1.0, GateMeshes.STAND_Z.x - 2.0), Vector3(12.0, 8.0, 120.0))
	add_child(crowd)


func _build_fx() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 18
	_dust.lifetime = 0.9
	_dust.one_shot = true
	_dust.explosiveness = 0.9
	_dust.local_coords = false
	_dust.emitting = false
	_dust.direction = Vector3(0, 1, 0)
	_dust.spread = 60.0
	_dust.initial_velocity_min = 1.0
	_dust.initial_velocity_max = 2.4
	_dust.gravity = Vector3(0, -1.0, 0)
	_dust.scale_amount_min = 0.6
	_dust.scale_amount_max = 1.3
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(1.2, 0.05, 0.6)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.85, 0.74, 0.55, 0.6))
	ramp.set_color(1, Color(0.85, 0.74, 0.55, 0.0))
	_dust.color_ramp = ramp
	_dust.mesh = _particle_quad(0.7, MeshKit3D.soft_disc())
	add_child(_dust)
	_confetti = CPUParticles3D.new()
	_confetti.name = "Confetti"
	_confetti.amount = 48
	_confetti.lifetime = 2.2
	_confetti.one_shot = true
	_confetti.explosiveness = 1.0
	_confetti.local_coords = false
	_confetti.emitting = false
	_confetti.visible = false
	_confetti.direction = Vector3(0, 1, 0)
	_confetti.spread = 70.0
	_confetti.initial_velocity_min = 4.0
	_confetti.initial_velocity_max = 8.0
	_confetti.gravity = Vector3(0, -4.0, 0)
	var colors := Gradient.new()
	colors.set_color(0, Color("f2c230"))
	colors.set_color(1, GateMeshes.ACCENT)
	_confetti.color_initial_ramp = colors
	_confetti.mesh = _particle_quad(0.09)
	add_child(_confetti)


func _particle_quad(size: float, texture: Texture2D = null) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_fog = true
	mat.albedo_texture = texture
	quad.material = mat
	return quad
