class_name TugWorld
extends Node3D
## Tug of War's 3D view (#40), first person: the rider stands at the end of a wooden pier, the
## rope runs out over a river to a bot on the far pier, and a flag on the rope shows who is
## winning. Win and the bot is hauled off its pier into the water; lose and the camera is
## pulled in. All of it is procedural (boxes, cylinders, spheres, one water shader), except the
## trees, which are the CC0 Kenney nature-kit models Dodge Ball already ships.
##
## It only draws: `TugLogic` holds the rules, and `update_view` is told the rope marker and the
## bot's state each frame. The tablet recipe (docs/GAMES.md, "On the tablet") applies: unshaded
## water lit by hand, per-vertex lit everything else, MultiMesh for the rope, trees and crowd,
## CPUParticles3D for the splash, and nothing laid out per frame beyond the rope's 22 segments.

const DodgeTimeOfDayRes := preload("res://games/dodge_ball/TimeOfDay.gd")

const EYE_HEIGHT := 1.6
const CAMERA_PITCH := -9.0
const FOV := 66.0
const DECK_TOP := 0.4  ## the piers' top, above the water at y = 0
const NEAR_EDGE_Z := -2.6  ## the near pier's end
const FAR_EDGE_Z := -11.0  ## the far pier's end
const BOT_HOME_Z := -13.6
const ROPE_SEGMENTS := 22
const CROWD_FAR := 44
const CROWD_NEAR := 16
const FALL_SEC := 1.3
## The rider's fists, in the camera's space: low and ahead, so both show above the screen's foot.
const HANDS_POS := Vector3(0.0, -0.3, -0.95)

## The bots: a material and an animal, so each rung's opponent gets a new name and colour.
## Plain words only: none of this is anyone's character.
const MATERIALS := ["Rust", "Copper", "Tin", "Brass", "Iron", "Steel", "Zinc", "Chrome"]
const ANIMALS := ["Mule", "Ox", "Badger", "Heron", "Otter", "Moose", "Walrus", "Yak"]
const BOT_COLORS := [Color(0.68, 0.32, 0.16), Color(0.82, 0.48, 0.25), Color(0.62, 0.68, 0.72),
	Color(0.85, 0.7, 0.28), Color(0.38, 0.42, 0.5), Color(0.52, 0.6, 0.68), Color(0.5, 0.58, 0.55),
	Color(0.78, 0.82, 0.88)]
const CROWD_COLORS := [Color(0.9, 0.35, 0.3), Color(0.95, 0.75, 0.25), Color(0.3, 0.6, 0.9),
	Color(0.4, 0.75, 0.4), Color(0.85, 0.5, 0.8), Color(0.95, 0.95, 0.9), Color(0.95, 0.55, 0.2)]

var camera: Camera3D
var excitement := 0.0  ## 0-1, how much the crowd is cheering
var flag_t := 0.5  ## where the flag is along the rope, 0 at the rider, 1 at the bot

var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _water_mat: ShaderMaterial
var _noise: ImageTexture
var _rig: Node3D
var _hands: Node3D
var _rope_mm: MultiMesh
var _flag: Node3D
var _bot: Node3D
var _bot_body_mat: StandardMaterial3D
var _bot_eye_mat: StandardMaterial3D
var _torch_mat: StandardMaterial3D
var _torches: Array[MeshInstance3D] = []
var _crowd_body: MultiMesh
var _crowd_head: MultiMesh
var _crowd_base: Array[Vector3] = []
var _crowd_phase: Array[float] = []
var _splash: CPUParticles3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _fall := 0.0  ## 0-1 through a fall into the water
var _faller := 0  ## +1: the bot falls, -1: the rider falls, 0: nobody
var _t := 0.0
var _pull_phase := 0.0
var _shake := 0.0
var _crowd_tick := 0.0
var _bot_name := ""


func _ready() -> void:
	_noise = DodgeWorld._noise_texture()
	_build_environment()
	_build_river_and_banks()
	_build_piers()
	_build_scenery()
	_build_crowd()
	_build_rope()
	_build_bot()
	_build_rig()
	_build_fx()
	set_bot(0)


## The rider's view of the rope: `p` is the marker (-1 to +1), `tension` 0.5-1 how taut the
## rope is, `surge` the bot's state ("", "telegraph" or "surge"), `cadence` in rpm.
func update_view(delta: float, p: float, tension: float, surge: String, cadence: float) -> void:
	_t += delta
	if _faller != 0:
		_fall = minf(_fall + delta / FALL_SEC, 1.0)
	_pull_phase += delta * cadence / 60.0 * TAU
	_shake = move_toward(_shake, 0.012 if surge == "surge" else 0.0, delta * 0.05)
	var bot_pull := clampf(p, 0.0, 1.0)
	var rider_pull := clampf(-p, 0.0, 1.0)
	# The bot is hauled toward the near pier, the camera toward the far one.
	var bot_pos := Vector3(0.0, DECK_TOP, BOT_HOME_Z + bot_pull * 3.8)
	bot_pos.y -= smoothstep(0.88, 1.0, bot_pull) * 0.35
	if _faller > 0:
		bot_pos.y -= ease(_fall, 2.0) * 2.6
		bot_pos.z += _fall * 0.8
	var cam_pos := Vector3(0.0, EYE_HEIGHT, -rider_pull * 3.2)
	cam_pos.y -= smoothstep(0.88, 1.0, rider_pull) * 0.25
	if _faller < 0:
		cam_pos.y -= ease(_fall, 2.0) * 1.35
		cam_pos.z -= _fall * 0.9
	var jitter := Vector3(sin(_t * 61.0), cos(_t * 53.0), 0.0) * _shake
	_rig.position = cam_pos + jitter
	camera.rotation_degrees.x = CAMERA_PITCH + (_fall * 8.0 if _faller < 0 else 0.0)
	_hands.position = HANDS_POS + Vector3(0.0, sin(_pull_phase) * 0.018, 0.0)
	# The bot braces on a telegraphed surge and leans into it.
	var lean := 0.0
	var eyes := Color(0.3, 0.9, 1.0)
	var glow := 1.5
	match surge:
		"telegraph":
			lean = -10.0
			eyes = Color(1.0, 0.7, 0.2)
			glow = 2.5 + 2.0 * absf(sin(_t * 18.0))
		"surge":
			lean = -16.0
			eyes = Color(1.0, 0.2, 0.15)
			glow = 3.5
	_bot.position = bot_pos
	_bot.rotation_degrees.x = lerpf(_bot.rotation_degrees.x, lean + bot_pull * 8.0, minf(delta * 8.0, 1.0))
	_bot_eye_mat.emission = eyes
	_bot_eye_mat.emission_energy_multiplier = glow
	_bot_eye_mat.albedo_color = eyes
	_update_rope(cam_pos + camera.basis * (HANDS_POS + Vector3(0.0, sin(_pull_phase) * 0.018, 0.0)),
		bot_pos + Vector3(0.0, 1.3, 0.97), tension, p)
	for torch in _torches:
		torch.scale = Vector3.ONE * (0.9 + 0.2 * sin(_t * 17.0 + torch.position.x * 3.0))
	_animate_crowd(delta)


## A new bot for this ladder rung (or round): its name and colour, returned as the name.
func set_bot(rung: int) -> String:
	var m := rung % MATERIALS.size()
	var a := (rung * 3 + rung / MATERIALS.size()) % ANIMALS.size()
	_bot_body_mat.albedo_color = BOT_COLORS[m]
	_bot.get_node("Ears").visible = rung % 2 == 0
	_bot.get_node("Horns").visible = rung % 2 == 1
	_bot_name = "%s %s" % [MATERIALS[m], ANIMALS[a]]
	return _bot_name


func bot_name() -> String:
	return _bot_name


## A round has ended: the loser falls into the river. The splash lands a moment later, at the
## far pier's end for the bot and just ahead of the camera for the rider.
func fall(bot_falls: bool) -> void:
	_faller = 1 if bot_falls else -1
	_fall = 0.0
	var splash_at_z := FAR_EDGE_Z + 1.4 if bot_falls else _rig.position.z - 3.2
	var timer := get_tree().create_timer(FALL_SEC * 0.55)
	timer.timeout.connect(func(): splash_at(Vector3(0.0, 0.05, splash_at_z)))


## A new round: the rope returns to the middle.
func reset_round() -> void:
	_faller = 0
	_fall = 0.0


func splash_at(pos: Vector3) -> void:
	_splash.position = pos
	_splash.restart()
	_splash.emitting = true
	_ring.position = pos + Vector3(0.0, 0.03, 0.0)
	_ring.scale = Vector3(0.3, 1.0, 0.3)
	_ring_mat.albedo_color.a = 0.75
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_ring, "scale", Vector3(4.5, 1.0, 4.5), 1.3)
	tween.tween_property(_ring_mat, "albedo_color:a", 0.0, 1.3)
	_shake = 0.03


## Draws every effect once off-screen so none hitches on first use.
func prewarm() -> void:
	_splash.emitting = true
	_splash.restart()
	_splash.emitting = false


func set_time_of_day(tod: DodgeTimeOfDay) -> void:
	_sky_mat.set_shader_parameter("top_color", tod.sky_top)
	_sky_mat.set_shader_parameter("horizon_color", tod.sky_horizon)
	_sky_mat.set_shader_parameter("ground_color", tod.sky_ground)
	_sky_mat.set_shader_parameter("sun_color", tod.sun_color)
	_sky_mat.set_shader_parameter("sun_size", tod.sun_size)
	_sky_mat.set_shader_parameter("halo", tod.halo)
	_sky_mat.set_shader_parameter("stars", tod.stars)
	_sky_mat.set_shader_parameter("clouds", tod.clouds)
	_sky_mat.set_shader_parameter("cloud_color", tod.cloud_color)
	var e := deg_to_rad(tod.sun_elevation)
	var a := deg_to_rad(tod.sun_azimuth)
	var to_sun := Vector3(sin(a) * cos(e), sin(e), -cos(a) * cos(e))
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	_sun.light_color = tod.sun_color
	_sun.light_energy = tod.sun_energy
	var env := _env.environment
	env.ambient_light_color = tod.ambient
	env.ambient_light_energy = tod.ambient_energy
	env.fog_light_color = tod.fog_color
	env.fog_density = tod.fog_density
	var light := tod.ambient * tod.ambient_energy + tod.sun_color * tod.sun_energy * maxf(sin(e), 0.12)
	_water_mat.set_shader_parameter("light_color", Vector3(light.r, light.g, light.b))
	_water_mat.set_shader_parameter("fog_color", tod.fog_color)
	_water_mat.set_shader_parameter("fog_density", tod.fog_density)
	_water_mat.set_shader_parameter("sky_tint", tod.sky_horizon)
	_water_mat.set_shader_parameter("sparkle", 0.45 if tod.sun_elevation > 25.0 else 0.2)
	_torch_mat.emission_energy_multiplier = 1.2 + 3.0 * clampf(tod.lamp_glow + (1.0 - tod.sun_energy * 0.7), 0.0, 1.0)


# --- Building ---

func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://games/dodge_ball/shaders/sky.gdshader")
	_sky_mat.set_shader_parameter("noise_tex", _noise)
	_sky_mat.set_shader_parameter("star_tex", DodgeWorld._noise_texture())
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.environment = env
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	add_child(_sun)


func _mat(color: Color, emission := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 1.0
	m.metallic = 0.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node3D = self) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := DodgeWorld._part(mesh, mat, pos, Vector3.ZERO)
	parent.add_child(mi)
	return mi


func _build_river_and_banks() -> void:
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load("res://games/tug_of_war/shaders/water.gdshader")
	_water_mat.set_shader_parameter("noise_tex", _noise)
	var water := PlaneMesh.new()
	water.size = Vector2(160.0, 60.0)
	var wi := DodgeWorld._part(water, _water_mat, Vector3(0.0, 0.0, -8.6), Vector3.ZERO)
	wi.name = "Water"
	add_child(wi)
	var grass := _mat(Color(0.3, 0.5, 0.2))
	_box(Vector3(160.0, 2.0, 30.0), Vector3(0.0, DECK_TOP - 1.0 - 0.05, NEAR_EDGE_Z + 15.0 - 0.4), grass).name = "NearBank"
	_box(Vector3(160.0, 2.0, 60.0), Vector3(0.0, DECK_TOP - 1.0 - 0.05, FAR_EDGE_Z - 30.0 + 0.4), grass).name = "FarBank"
	# Far hills, flattened spheres in two tints, behind everything.
	var hill := SphereMesh.new()
	hill.radius = 1.0
	hill.height = 2.0
	hill.radial_segments = 12
	hill.rings = 6
	var rng := RandomNumberGenerator.new()
	rng.seed = 4021
	for i in 9:
		var tint := Color(0.22, 0.38, 0.28).lerp(Color(0.3, 0.45, 0.35), rng.randf())
		var mi := DodgeWorld._part(hill, _mat(tint), Vector3(-90.0 + i * 22.0 + rng.randf_range(-6.0, 6.0), 0.0,
			rng.randf_range(-95.0, -70.0)), Vector3.ZERO)
		mi.scale = Vector3(rng.randf_range(24.0, 36.0), rng.randf_range(9.0, 18.0), rng.randf_range(14.0, 20.0))
		add_child(mi)


func _plank_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var img := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for x in 64:
		var plank := x / 16
		var tone := 0.82 + 0.06 * float(plank % 3)
		for y in 64:
			var grain := 0.9 + 0.1 * sin(float(y) * 0.5 + float(plank) * 2.0) + rng.randf_range(-0.03, 0.03)
			var edge := 0.3 if x % 16 < 2 else 1.0
			var c := Color(0.55, 0.38, 0.22) * tone * grain * edge
			img.set_pixel(x, y, Color(c.r, c.g, c.b))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_piers() -> void:
	var wood := _mat(Color.WHITE)
	wood.albedo_texture = _plank_texture()
	wood.uv1_scale = Vector3(2.0, 4.0, 1.0)
	var dark := _mat(Color(0.3, 0.2, 0.12))
	# Near pier: the rider stands at its end.
	_box(Vector3(5.0, 0.3, 9.0), Vector3(0.0, DECK_TOP - 0.15, NEAR_EDGE_Z + 4.5), wood).name = "NearPier"
	_box(Vector3(5.0, 0.3, 7.0), Vector3(0.0, DECK_TOP - 0.15, FAR_EDGE_Z - 3.5), wood).name = "FarPier"
	for z_edge in [NEAR_EDGE_Z, FAR_EDGE_Z]:
		for x in [-2.35, 2.35]:
			var post_z: float = z_edge + (0.15 if z_edge == NEAR_EDGE_Z else -0.15)
			# Pilings below the deck, into the water. Only the far pier has torch posts: on the
			# near pier they'd stand beside the camera, as big dark pillars across the view.
			_box(Vector3(0.22, 1.6, 0.22), Vector3(x, -0.6, post_z), dark)
			if z_edge == FAR_EDGE_Z:
				_box(Vector3(0.18, 1.5, 0.18), Vector3(x, DECK_TOP + 0.55, post_z), dark)
	# Torches: a post and an emissive flame, so they cost no real lights.
	_torch_mat = _mat(Color(1.0, 0.6, 0.2), 3.0)
	_torch_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var flame := SphereMesh.new()
	flame.radius = 0.14
	flame.height = 0.4
	flame.radial_segments = 8
	flame.rings = 4
	for x in [-2.35, 2.35]:
		for z_edge in [FAR_EDGE_Z]:
			var post_z: float = z_edge - 0.15
			var f := DodgeWorld._part(flame, _torch_mat, Vector3(x, DECK_TOP + 1.5, post_z), Vector3.ZERO)
			add_child(f)
			_torches.append(f)


func _build_scenery() -> void:
	var trees := [DodgeWorld._recolor(DodgeWorld._model_mesh("tree_default.glb"), Color(0.32, 0.56, 0.2)),
		DodgeWorld._recolor(DodgeWorld._model_mesh("tree_oak.glb"), Color(0.26, 0.48, 0.17)),
		DodgeWorld._recolor(DodgeWorld._model_mesh("tree_pineTallA.glb"), Color(0.16, 0.36, 0.2)),
		DodgeWorld._recolor(DodgeWorld._model_mesh("tree_cone.glb"), Color(0.38, 0.6, 0.22))]
	var bush := DodgeWorld._recolor(DodgeWorld._model_mesh("plant_bushLarge.glb"), Color(0.3, 0.52, 0.2))
	var rock := DodgeWorld._recolor(DodgeWorld._model_mesh("rock_largeA.glb"), Color(0.5, 0.5, 0.47), Color(0.42, 0.41, 0.39))
	var rng := RandomNumberGenerator.new()
	rng.seed = 9981
	var per_tree: Array = [[], [], [], []]
	var bushes: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	for i in 70:
		var far := rng.randf() < 0.75
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x := side * rng.randf_range(7.0, 38.0)
		var z := rng.randf_range(FAR_EDGE_Z - 40.0, FAR_EDGE_Z - 1.0) if far else rng.randf_range(NEAR_EDGE_Z - 1.0, NEAR_EDGE_Z + 12.0)
		var s := rng.randf_range(2.6, 4.4)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, DECK_TOP - 0.05, z))
		per_tree[rng.randi() % 4].append(t)
	for i in 36:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var far := rng.randf() < 0.6
		var x := side * rng.randf_range(4.0, 26.0)
		var z := rng.randf_range(FAR_EDGE_Z - 22.0, FAR_EDGE_Z - 0.5) if far else rng.randf_range(NEAR_EDGE_Z - 0.4, NEAR_EDGE_Z + 8.0)
		var t := Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(1.6, 2.6)),
			Vector3(x, DECK_TOP - 0.05, z))
		(rocks if rng.randf() < 0.3 else bushes).append(t)
	for i in trees.size():
		if trees[i] != null and not per_tree[i].is_empty():
			var transforms: Array[Transform3D] = []
			transforms.assign(per_tree[i])
			add_child(DodgeWorld._multimesh(trees[i], transforms, "Trees%d" % i))
	if bush != null and not bushes.is_empty():
		add_child(DodgeWorld._multimesh(bush, bushes, "Bushes"))
	if rock != null and not rocks.is_empty():
		add_child(DodgeWorld._multimesh(rock, rocks, "Rocks"))


func _build_crowd() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 515
	var body := CapsuleMesh.new()
	body.radius = 0.22
	body.height = 1.1
	body.radial_segments = 8
	body.rings = 3
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.34
	head.radial_segments = 8
	head.rings = 4
	var count := CROWD_FAR + CROWD_NEAR
	_crowd_body = _crowd_multimesh(body, count)
	_crowd_head = _crowd_multimesh(head, count)
	for i in count:
		var near := i >= CROWD_FAR
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos: Vector3
		if near:
			pos = Vector3(side * rng.randf_range(3.2, 8.0), DECK_TOP, rng.randf_range(NEAR_EDGE_Z + 0.3, NEAR_EDGE_Z + 3.0))
		else:
			pos = Vector3(side * rng.randf_range(4.0, 14.0), DECK_TOP, rng.randf_range(FAR_EDGE_Z - 6.0, FAR_EDGE_Z - 0.6))
		_crowd_base.append(pos)
		_crowd_phase.append(rng.randf() * TAU)
		var c: Color = CROWD_COLORS[rng.randi() % CROWD_COLORS.size()]
		_crowd_body.set_instance_color(i, c)
		_crowd_head.set_instance_color(i, Color(0.9, 0.72, 0.58).lerp(Color(0.45, 0.3, 0.2), rng.randf()))
	_place_crowd(0.0)
	for mm in [_crowd_body, _crowd_head]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := _mat(Color.WHITE)
		m.vertex_color_use_as_albedo = true
		mmi.material_override = m
		add_child(mmi)


func _crowd_multimesh(mesh: Mesh, count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = count
	return mm


func _place_crowd(cheer: float) -> void:
	for i in _crowd_base.size():
		var hop := absf(sin(_t * 7.0 + _crowd_phase[i])) * 0.3 * cheer
		var base := _crowd_base[i]
		var at := base + Vector3(0.0, 0.7 + hop, 0.0)
		# They face the rope: the far crowd looks toward +z, the near crowd toward -z.
		var facing := PI if i >= CROWD_FAR else 0.0
		var basis := Basis(Vector3.UP, facing)
		_crowd_body.set_instance_transform(i, Transform3D(basis, at))
		_crowd_head.set_instance_transform(i, Transform3D(basis, at + Vector3(0.0, 0.78, 0.0)))


func _animate_crowd(delta: float) -> void:
	_crowd_tick -= delta
	if _crowd_tick > 0.0:
		return
	_crowd_tick = 1.0 / 20.0
	_place_crowd(excitement)


func _build_rope() -> void:
	var seg := CylinderMesh.new()
	seg.top_radius = 0.035
	seg.bottom_radius = 0.035
	seg.height = 1.0
	seg.radial_segments = 6
	seg.rings = 1
	_rope_mm = MultiMesh.new()
	_rope_mm.transform_format = MultiMesh.TRANSFORM_3D
	_rope_mm.use_colors = true
	_rope_mm.mesh = seg
	_rope_mm.instance_count = ROPE_SEGMENTS
	for i in ROPE_SEGMENTS:
		_rope_mm.set_instance_color(i, Color(0.78, 0.66, 0.42) if i % 2 == 0 else Color(0.55, 0.42, 0.26))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rope"
	mmi.multimesh = _rope_mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := _mat(Color.WHITE)
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mmi.material_override = m
	mmi.extra_cull_margin = 40.0
	add_child(mmi)
	# The flag: a pole and a pennant on the rope.
	_flag = Node3D.new()
	_flag.name = "Flag"
	var pole := CylinderMesh.new()
	pole.top_radius = 0.02
	pole.bottom_radius = 0.02
	pole.height = 1.5
	pole.radial_segments = 6
	pole.rings = 1
	_flag.add_child(DodgeWorld._part(pole, _mat(Color(0.9, 0.9, 0.85)), Vector3(0.0, 0.75, 0.0), Vector3.ZERO))
	var pennant := QuadMesh.new()
	pennant.size = Vector2(0.95, 0.55)
	var flag_mat := _mat(Color(1.0, 0.25, 0.12), 0.6)
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var pennant_node := DodgeWorld._part(pennant, flag_mat, Vector3(0.0, 1.2, 0.48), Vector3(0.0, 90.0, 0.0))
	pennant_node.name = "Pennant"
	_flag.add_child(pennant_node)
	add_child(_flag)


func _update_rope(from: Vector3, to: Vector3, tension: float, p: float) -> void:
	var sag := 0.55 * (1.0 - clampf(tension, 0.0, 1.0)) + 0.06
	var prev := from
	for i in ROPE_SEGMENTS:
		var t := float(i + 1) / ROPE_SEGMENTS
		var point := from.lerp(to, t)
		point.y -= sag * 4.0 * t * (1.0 - t)
		var d := point - prev
		var len := d.length()
		var q := Quaternion(Vector3.UP, d / len)
		_rope_mm.set_instance_transform(i, Transform3D(Basis(q).scaled_local(Vector3(1.0, len * 1.08, 1.0)), (prev + point) * 0.5))
		prev = point
	flag_t = 0.5 + 0.42 * p
	var fp := from.lerp(to, flag_t)
	fp.y -= sag * 4.0 * flag_t * (1.0 - flag_t)
	_flag.position = fp
	_flag.get_node("Pennant").rotation_degrees.y = 90.0 + sin(_t * 9.0) * 10.0


func _build_bot() -> void:
	_bot = Node3D.new()
	_bot.name = "Bot"
	add_child(_bot)
	_bot_body_mat = _mat(BOT_COLORS[0])
	var dark := _mat(Color(0.14, 0.15, 0.18))
	_bot_eye_mat = _mat(Color(0.3, 0.9, 1.0), 2.0)
	_bot_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# The body faces the rider (+z).
	_box(Vector3(1.1, 1.0, 0.7), Vector3(0.0, 1.0, 0.0), _bot_body_mat, _bot)
	_box(Vector3(0.85, 0.7, 0.6), Vector3(0.0, 1.85, 0.05), _bot_body_mat, _bot)
	_box(Vector3(1.25, 0.28, 0.8), Vector3(0.0, 0.14, 0.0), dark, _bot)  # the treads' block
	var eye := SphereMesh.new()
	eye.radius = 0.1
	eye.height = 0.2
	eye.radial_segments = 8
	eye.rings = 4
	for x in [-0.2, 0.2]:
		_bot.add_child(DodgeWorld._part(eye, _bot_eye_mat, Vector3(x, 1.9, 0.36), Vector3.ZERO))
	_box(Vector3(0.5, 0.12, 0.05), Vector3(0.0, 1.68, 0.36), dark, _bot)  # a grille for a mouth
	var arm := CylinderMesh.new()
	arm.top_radius = 0.1
	arm.bottom_radius = 0.1
	arm.height = 0.9
	arm.radial_segments = 8
	arm.rings = 1
	for x in [-0.6, 0.6]:
		_bot.add_child(DodgeWorld._part(arm, dark, Vector3(x, 1.1, 0.45), Vector3(-70.0, 0.0, 0.0)))
	var stack := CylinderMesh.new()  # a little chimney, shared by every bot
	stack.top_radius = 0.07
	stack.bottom_radius = 0.09
	stack.height = 0.4
	stack.radial_segments = 8
	stack.rings = 1
	_bot.add_child(DodgeWorld._part(stack, dark, Vector3(0.25, 2.35, 0.0), Vector3.ZERO))
	var ears := Node3D.new()
	ears.name = "Ears"
	_bot.add_child(ears)
	for x in [-0.34, 0.34]:
		_box(Vector3(0.18, 0.4, 0.1), Vector3(x, 2.35, 0.0), _bot_body_mat, ears)
	var horns := Node3D.new()
	horns.name = "Horns"
	_bot.add_child(horns)
	for x in [-0.4, 0.4]:
		var h := _box(Vector3(0.12, 0.5, 0.12), Vector3(x, 2.4, 0.0), dark, horns)
		h.rotation_degrees.z = -25.0 * signf(x)
	_bot.scale = Vector3.ONE * 1.3
	_bot.position = Vector3(0.0, DECK_TOP, BOT_HOME_Z)


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 260.0
	camera.rotation_degrees = Vector3(CAMERA_PITCH, 0.0, 0.0)
	_rig.add_child(camera)
	_rig.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(_rig)
	# The rider's hands, on the rope: two fists and the forearms going back under the camera.
	_hands = Node3D.new()
	_hands.name = "Hands"
	camera.add_child(_hands)
	var skin := _mat(Color(0.86, 0.66, 0.52), 0.35)
	var sleeve := _mat(Color(0.35, 0.5, 0.85), 0.3)
	var fist := SphereMesh.new()
	fist.radius = 0.055
	fist.height = 0.11
	fist.radial_segments = 8
	fist.rings = 4
	var cuff := CylinderMesh.new()
	cuff.top_radius = 0.05
	cuff.bottom_radius = 0.06
	cuff.height = 0.14
	cuff.radial_segments = 8
	cuff.rings = 1
	for x in [-0.075, 0.075]:
		_hands.add_child(DodgeWorld._part(fist, skin, Vector3(x, 0.0, 0.0), Vector3.ZERO))
		_hands.add_child(DodgeWorld._part(cuff, sleeve, Vector3(x * 1.3, -0.03, 0.1), Vector3(75.0, 0.0, 0.0)))
	# The camera looks down the camera-local -z; the hands sit in front of it and a bit low.


func _build_fx() -> void:
	var drop := SphereMesh.new()
	drop.radius = 0.05
	drop.height = 0.1
	drop.radial_segments = 6
	drop.rings = 3
	_splash = CPUParticles3D.new()
	_splash.mesh = drop
	# Unshaded and bright: a lit drop reads as a dark blob against the water at night.
	var drop_mat := _mat(Color(0.85, 0.95, 1.0))
	drop_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_splash.material_override = drop_mat
	_splash.amount = 48
	_splash.lifetime = 1.3
	_splash.one_shot = true
	_splash.emitting = false
	_splash.explosiveness = 0.95
	_splash.direction = Vector3.UP
	_splash.spread = 38.0
	_splash.initial_velocity_min = 3.0
	_splash.initial_velocity_max = 6.5
	_splash.gravity = Vector3(0.0, -9.8, 0.0)
	_splash.local_coords = false
	add_child(_splash)
	var ring := TorusMesh.new()  # lies flat, so it reads as a ripple on the water
	ring.inner_radius = 0.9
	ring.outer_radius = 1.0
	ring.rings = 24
	ring.ring_segments = 4
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring_mat.albedo_color = Color(0.9, 0.97, 1.0, 0.0)
	_ring_mat.disable_fog = true
	_ring = DodgeWorld._part(ring, _ring_mat, Vector3(0.0, 0.03, -8.0), Vector3.ZERO)
	_ring.name = "Ripple"
	add_child(_ring)
