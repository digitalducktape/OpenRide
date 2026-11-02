class_name PullWorld
extends Node3D
## The Pull's 3D view (#79), first person from the bike: a floodlit clay track at a county fair
## at dusk, a chain back to a steel sled whose weight box creeps forward, distance boards every
## 25 m, the rider's best flag and the Full Pull line. The sled shows in a mirror on the bars,
## and in a look back over the shoulder while the pull is being set. ART_BIBLE.md is the look.
##
## It only draws: `PullLogic` holds the rules, and `update_view` is told the distance, speed,
## box, strain and look-back each frame. The tablet recipe (docs/GAMES.md "World look (3D)"):
## every surface is unshaded and lit by hand (shaders/pull_look.gdshaderinc on the shared
## WorldLook), the statics are one baked mesh (PullMeshes), the crowd is one MultiMesh moved in
## its shader. Per frame, GDScript moves the rig, the sled and the box, and lays out 18 chain
## links.

const EYE_HEIGHT := 1.55
const CAMERA_PITCH := -6.0
const FOV := 68.0
const FAR := 900.0
const SKY_RADIUS := 850.0  ## inside FAR; the dome follows the camera
const BARS := Vector3(0.0, 1.16, -0.74)
const MIRROR := Vector3(0.5, 1.3, -0.78)
const MIRROR_SIZE := Vector2(0.2, 0.13)
const MIRROR_VIEW := Vector2i(256, 166)
const MIRROR_CAMERA := Vector3(0.3, 1.5, 0.15)
const SLED_GAP := 3.4  ## the chain's length: the sled's hitch is this far behind the rig
const BOX_REAR := 3.7  ## the weight box's centre on the sled at the start...
const BOX_FRONT := 1.0  ## ...and at the Full Pull line
const CHAIN_LINKS := 18
const CHAIN_FROM := Vector3(0.0, 0.42, 0.45)  ## the bike's tow point, from the rig
const LOOK_BACK_YAW := 150.0
const CROWD_FILL := 0.55
const CROWD_COLORS := [Color("d94a3a"), Color("f2c230"), Color("3a7fd9"), Color("5fd068"), Color("e8e4dc"),
	Color("8a4ad9"), Color("f28a30"), Color("2a2e33")]
const BOARD_LABEL_RANGE := 140.0
const FLARE_SEC := 1.5
## The dusk (ART_BIBLE §3-4) for WorldLook: a low cool moon, a blue sky ambient, a violet haze.
const LOOK := {
	"sun_color": Color(0.16, 0.18, 0.28),
	"sky_color": Color(0.3, 0.34, 0.55),
	"ground_color": Color(0.2, 0.14, 0.12),
	"haze_color": Color(0.36, 0.33, 0.48),
	"haze_density": 0.0055,
	"haze_max": 0.8,
}

const SHADERS := "res://games/the_pull/shaders/"

var camera: Camera3D
var mirror_camera: Camera3D
var excitement := 0.0  ## 0-1, how much the crowd is cheering
var full_m := 336.0
var best_m := 0.0

var _lit: Array[ShaderMaterial] = []
var _track_mat: ShaderMaterial
var _infield_mat: ShaderMaterial
var _scenery_mat: ShaderMaterial
var _flag_mat: ShaderMaterial
var _crowd_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _rig: Node3D
var _sky: MeshInstance3D
var _scenery: MeshInstance3D
var _labels: Node3D
var _sled: Node3D
var _box: MeshInstance3D
var _chain: MultiMesh
var _flag: Node3D
var _crowd: MultiMeshInstance3D
var _mirror_view: SubViewport
var _dust: CPUParticles3D
var _confetti: CPUParticles3D
var _t := 0.0
var _pedal_phase := 0.0
var _slack := 1.0
var _dip := 0.0
var _flare := 0.0
var _excite_shown := -1.0
var _warming := 0
var _mirror_frame := 0


func _ready() -> void:
	_build_materials()
	_build_environment()
	_build_ground()
	_build_rig()
	_build_sled()
	_build_fx()
	build(full_m, best_m)
	set_process(false)


## Builds the statics for a sled whose Full Pull line is at `full_m` metres, with the rider's
## best flag at `best` (hidden for 0). The statics are only rebuilt when the line moves (a
## difficulty other than the one built at `_ready`).
func build(new_full_m: float, best: float) -> void:
	if _scenery and is_equal_approx(new_full_m, full_m):
		set_best(best)
		return
	full_m = new_full_m
	if _scenery:
		remove_child(_scenery)  # gone at once: its name is free for the new one, and no orphan waits
		_scenery.free()
	_scenery = KartMeshKit.mesh_node(PullMeshes.scenery(full_m), _scenery_mat, "Scenery")
	add_child(_scenery)
	_build_labels()
	_build_crowd()
	set_best(best)


## Plants the best flag at `metres` (hidden at 0).
func set_best(metres: float) -> void:
	best_m = metres
	_flag.visible = metres > 0.5
	_flag.position = Vector3(PullMeshes.HALF_WIDTH - 0.6, 0.0, -metres)


## The rider's view this frame. `distance` in metres, `speed` m/s, `box_t` 0-1 (the weight
## box from the sled's rear to its front), `cadence` rpm, `strain` 0-1 (how hard the sled
## bogs), `look_back` 0-1 (the turn over the shoulder), `slack` 0-1 (the chain lying loose).
func update_view(delta: float, distance: float, speed: float, box_t: float, cadence: float, strain: float,
		look_back: float, slack: float) -> void:
	_t += delta
	_pedal_phase += delta * cadence / 60.0 * TAU
	_slack = move_toward(_slack, slack, delta * 2.5)
	_dip = move_toward(_dip, 0.0, delta * 1.2)
	var bob := sin(_pedal_phase * 2.0) * 0.012 * clampf(cadence / 60.0, 0.0, 1.0)
	var shake := Vector3(sin(_t * 47.0), cos(_t * 41.0), 0.0) * 0.009 * strain
	_rig.position = Vector3(0.0, bob, -distance) + shake
	_sky.position = _rig.position
	var turn := smoothstep(0.0, 1.0, look_back)
	camera.rotation_degrees = Vector3(CAMERA_PITCH - 4.0 * turn - _dip * 2.0, -LOOK_BACK_YAW * turn, sin(_pedal_phase) * 0.4)
	_sled.position = Vector3(0.0, 0.0, -distance + SLED_GAP)
	_box.position = Vector3(0.0, 0.22, lerpf(BOX_REAR, BOX_FRONT, clampf(box_t, 0.0, 1.0)))
	_lay_chain()
	_mirror_frame += 1
	if _mirror_frame % 2 == 0:
		_mirror_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	mirror_camera.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(-12.0), PI, 0.0)),
		_rig.position + MIRROR_CAMERA)
	if _warming == 0:
		_dust.emitting = speed > 0.25
	excitement = move_toward(excitement, 0.0, delta * 0.15)
	var shown := snappedf(excitement, 0.02)
	if shown != _excite_shown:
		_excite_shown = shown
		_crowd_mat.set_shader_parameter("excitement", shown)
	if _flare > 0.0:
		_flare = maxf(_flare - delta / FLARE_SEC, 0.0)
		_set_flood(1.0 + 0.7 * _flare)


## The Full Pull: confetti over the line, the floodlights flare and the crowd jumps.
func full_pull_burst() -> void:
	_confetti.global_position = _rig.position + Vector3(0.0, 2.2, -5.0)
	_confetti.visible = true
	_confetti.restart()
	_flare = 1.0
	excitement = 1.0


## The stall: the view dips and the chain drops.
func stall_dip() -> void:
	_dip = 1.0


## Draws the dust and confetti once behind the intro card, so their shaders compile then.
func prewarm() -> void:
	_warming = 3
	_dust.emitting = true
	_confetti.visible = true
	_confetti.restart()
	set_process(true)


## Counts prewarm's frames down (the intro card runs no game frames), then idles.
func _process(_delta: float) -> void:
	if _warming <= 0:
		set_process(false)
		return
	_warming -= 1
	if _warming == 0:
		_dust.emitting = false
		_confetti.emitting = false
		_confetti.visible = false


# --- Building ---

func _shader(file: String) -> Shader:
	return load(SHADERS + file) as Shader


func _material(file: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = _shader(file)
	_lit.append(mat)
	return mat


func _build_materials() -> void:
	_track_mat = _material("track.gdshader")
	_infield_mat = _material("track.gdshader")
	_infield_mat.set_shader_parameter("clay", Color("3a2a22"))
	_infield_mat.set_shader_parameter("ruts", 0.0)
	_infield_mat.set_shader_parameter("lines", 0.0)
	_infield_mat.set_shader_parameter("grain_scale", 0.6)
	_scenery_mat = _material("scenery.gdshader")
	_flag_mat = _material("scenery.gdshader")
	_flag_mat.set_shader_parameter("wave", 0.05)
	_flag_mat.set_shader_parameter("sway", 0.03)
	_crowd_mat = _material("crowd.gdshader")
	_sky_mat = _material("sky.gdshader")
	var look := LOOK.duplicate()
	look["sun_dir"] = WorldLook.sun_dir(30.0, 160.0)
	look["noise_tex"] = WorldLook.noise_texture()
	WorldLook.apply(_lit, look)


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("141c46")
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
	_sky = KartMeshKit.mesh_node(dome, _sky_mat, "Sky")
	add_child(_sky)


func _build_ground() -> void:
	var track := PullMeshes.ground_grid(PullMeshes.HALF_WIDTH * 2.0, PullMeshes.LENGTH + 20.0, 8, 240, 20.0)
	add_child(KartMeshKit.mesh_node(track, _track_mat, "Track"))
	# The infield: wide strips either side of the track, out past the trees.
	for side: float in [-1.0, 1.0]:
		var strip := PullMeshes.ground_grid(60.0, PullMeshes.LENGTH + 140.0, 20, 120, 60.0)
		var node := KartMeshKit.mesh_node(strip, _infield_mat, "Infield")
		node.position.x = side * (PullMeshes.HALF_WIDTH + 30.0)
		node.position.y = -0.01
		add_child(node)
	var far := PullMeshes.ground_grid(140.0, 140.0, 14, 14, -PullMeshes.LENGTH - 20.0)
	var far_node := KartMeshKit.mesh_node(far, _infield_mat, "FarField")
	far_node.position.y = -0.01
	add_child(far_node)


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	camera.fov = FOV
	camera.near = 0.05
	camera.far = FAR
	camera.current = true
	_rig.add_child(camera)
	_rig.add_child(KartMeshKit.mesh_node(PullMeshes.bike(BARS, MIRROR), _scenery_mat, "Bike"))
	# The mirror: a small camera looking back, shown on the glass.
	_mirror_view = SubViewport.new()
	_mirror_view.name = "MirrorView"
	_mirror_view.size = MIRROR_VIEW
	_mirror_view.msaa_3d = Viewport.MSAA_DISABLED
	# Rendered every other frame (`update_view`): half the second pass's cost on the tablet.
	_mirror_view.render_target_update_mode = SubViewport.UPDATE_ONCE
	_mirror_view.audio_listener_enable_3d = false
	add_child(_mirror_view)
	mirror_camera = Camera3D.new()
	mirror_camera.name = "MirrorCamera"
	mirror_camera.fov = 42.0
	mirror_camera.far = 160.0
	mirror_camera.current = true
	_mirror_view.add_child(mirror_camera)
	var glass_mat := ShaderMaterial.new()
	glass_mat.shader = _shader("mirror.gdshader")
	glass_mat.set_shader_parameter("view", _mirror_view.get_texture())
	var quad := QuadMesh.new()
	quad.size = MIRROR_SIZE
	var glass := KartMeshKit.mesh_node(quad, glass_mat, "MirrorGlass")
	glass.position = MIRROR
	_rig.add_child(glass)


func _build_sled() -> void:
	_sled = Node3D.new()
	_sled.name = "Sled"
	add_child(_sled)
	_sled.add_child(KartMeshKit.mesh_node(PullMeshes.sled(), _scenery_mat, "Pan"))
	_box = KartMeshKit.mesh_node(PullMeshes.weight_box(), _scenery_mat, "WeightBox")
	_sled.add_child(_box)
	var transforms := []
	for i in CHAIN_LINKS:
		transforms.append(Transform3D())
	var chain := KartMeshKit.multimesh_node(PullMeshes.chain_link(), transforms, "Chain")
	chain.material_override = _scenery_mat
	# Its links are placed in world space along the whole track.
	chain.custom_aabb = AABB(Vector3(-2, -1, -PullMeshes.LENGTH - 20.0), Vector3(4, 4, PullMeshes.LENGTH + 40.0))
	add_child(chain)
	_chain = chain.multimesh
	_flag = Node3D.new()
	_flag.name = "BestFlag"
	_flag.add_child(KartMeshKit.mesh_node(PullMeshes.flag(), _flag_mat, "Cloth"))
	var label := _label("YOUR BEST", 56, PullMeshes.INK)
	label.position = Vector3(-0.62, 2.92, 0.09)
	_flag.add_child(label)
	add_child(_flag)


func _build_fx() -> void:
	_dust = CPUParticles3D.new()
	_dust.name = "Dust"
	_dust.amount = 24
	_dust.lifetime = 1.6
	_dust.local_coords = false
	_dust.emitting = false
	_dust.direction = Vector3(0, 1, 0.4)
	_dust.spread = 35.0
	_dust.initial_velocity_min = 0.4
	_dust.initial_velocity_max = 1.1
	_dust.gravity = Vector3(0, 0.15, 0)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.2
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(0.9, 0.05, 0.1)
	_dust.position = Vector3(0.0, 0.15, 4.7)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.4, 0.3, 0.55))
	ramp.set_color(1, Color(0.4, 0.33, 0.35, 0.0))
	_dust.color_ramp = ramp
	_dust.mesh = _particle_quad(0.6)
	_sled.add_child(_dust)
	_confetti = CPUParticles3D.new()
	_confetti.name = "Confetti"
	_confetti.amount = 48
	_confetti.lifetime = 2.4
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
	_confetti.angular_velocity_min = -360.0
	_confetti.angular_velocity_max = 360.0
	var colors := Gradient.new()
	colors.set_color(0, Color("f2c230"))
	colors.set_color(1, PullMeshes.ACCENT)
	_confetti.color_initial_ramp = colors
	_confetti.mesh = _particle_quad(0.14)
	add_child(_confetti)


func _particle_quad(size: float) -> QuadMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.disable_fog = true
	quad.material = mat
	return quad


func _build_labels() -> void:
	if _labels:
		remove_child(_labels)  # gone at once: its name is free for the new one, and no orphan waits
		_labels.free()
	_labels = Node3D.new()
	_labels.name = "Labels"
	add_child(_labels)
	var m := 25
	while m < PullMeshes.LENGTH - 10.0:
		var label := _label(str(m), 150, PullMeshes.INK)
		label.position = Vector3(PullMeshes.BOARD_X, 1.82, -m + 0.06)
		label.visibility_range_end = BOARD_LABEL_RANGE
		_labels.add_child(label)
		m += 25
	var banner := _label("FULL PULL", 150, Color("f2e6c8"))
	banner.position = Vector3(0.0, 4.7, -full_m + 0.07)
	_labels.add_child(banner)


func _label(text: String, size: int, color: Color) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = GameTheme.display_font()
	label.font_size = size
	label.pixel_size = 0.005
	label.modulate = color
	label.outline_size = 0
	label.shaded = false
	label.double_sided = false
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.fixed_size = false
	return label


func _build_crowd() -> void:
	if _crowd:
		remove_child(_crowd)  # gone at once: its name is free for the new one, and no orphan waits
		_crowd.free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7979
	var transforms := []
	var custom := []
	var colors := []
	var z := 14.0
	while z > -PullMeshes.LENGTH + 20.0:
		for side: float in [-1.0, 1.0]:
			for t in PullMeshes.STAND_TIERS:
				var x := side * (PullMeshes.STAND_X + PullMeshes.TIER_DEPTH * (t + 0.5))
				var y := PullMeshes.TIER_RISE * (t + 1)
				var s := 0.6
				while s < PullMeshes.SECTION - 0.6:
					if rng.randf() < CROWD_FILL:
						transforms.append(Transform3D(Basis(), Vector3(x + rng.randf_range(-0.2, 0.2), y, z - s)))
						custom.append(Color(rng.randf(), rng.randf_range(0.4, 1.0), rng.randf(), 0.0))
						colors.append(CROWD_COLORS[rng.randi() % CROWD_COLORS.size()])
					s += 0.85
		z -= PullMeshes.TOWER_SPACING
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.85)
	quad.center_offset = Vector3(0.0, 0.425, 0.0)
	_crowd = KartMeshKit.multimesh_node(quad, transforms, "Crowd", custom, colors)
	_crowd.material_override = _crowd_mat
	_crowd.custom_aabb = AABB(Vector3(-30, -2, -PullMeshes.LENGTH - 20.0), Vector3(60, 10, PullMeshes.LENGTH + 60.0))
	add_child(_crowd)


# --- Per frame ---

## The chain from the bike's tow point to the sled's hitch, sagging with `_slack`.
func _lay_chain() -> void:
	var a := _rig.position + CHAIN_FROM
	var b := Vector3(0.0, 0.6, _sled.position.z)
	var sag := lerpf(0.03, 0.45, _slack)
	var dir := (b - a).normalized()
	for i in CHAIN_LINKS:
		var t := float(i) / (CHAIN_LINKS - 1)
		var p := a.lerp(b, t) - Vector3.UP * sag * 4.0 * t * (1.0 - t)
		p.y = maxf(p.y, 0.03)
		var basis := Basis.looking_at(dir, Vector3.UP)
		if i % 2 == 1:
			basis = basis.rotated(dir, PI / 2.0)
		_chain.set_instance_transform(i, Transform3D(basis, p))


func _set_flood(strength: float) -> void:
	for mat in [_track_mat, _infield_mat, _scenery_mat, _flag_mat, _crowd_mat]:
		mat.set_shader_parameter("flood_strength", strength)
	_scenery_mat.set_shader_parameter("glow_gain", strength)
