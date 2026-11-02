class_name KeepyWorld
extends Node3D
## Keepy Uppy's 3D view (#77), first person from the bike: a meadow on a breezy afternoon, a
## wooden pedal fan on the grass ahead, a coral balloon riding its column of air, a height pole
## painted in the three bands, and the weather coming in from the horizon. The look is in
## ART_BIBLE.md (this folder).
##
## It only draws: `KeepyLogic` holds the rules, and `update_view` reads it each frame. The tablet
## recipe (docs/GAMES.md, "World look (3D)"): every surface is unshaded and lit by hand on the
## shared look (`WorldLook`, shaders/keepy_look.gdshaderinc), the statics are baked into one
## vertex-coloured mesh (`KeepyMeshes.meadow`), the sky is drawn once into its cubemap, and the
## grass, streamers, clouds' drift and the birds' wings move in their shaders. Per frame, GDScript
## places the balloon, the fan, the birds and the rain cloud and sets a handful of uniforms.

const EYE_HEIGHT := 1.5
const FOV := 66.0
## The camera pitches with the balloon (ART_BIBLE §8): from PITCH_LOW with it on the fan to
## PITCH_HIGH at the top, eased over about a second.
const PITCH_LOW := 4.0
const PITCH_HIGH := 22.0
const PITCH_TAU := 0.9
## With Steer on, the camera pans toward the balloon's side by this share of its offset.
const PAN_SHARE := 0.35
const PAN_TAU := 1.2
const GRASS_TUFTS := 520
const FLOWERS := 220
const WARM_FRAMES := 3
## The rain cloud: far on the horizon, then overhead just behind the fan.
const CLOUD_FAR := Vector3(-30.0, 30.0, -110.0)
const CLOUD_OVER := Vector3(0.4, 9.0, KeepyMeshes.FAN_Z - 5.0)
const CLOUD_GONE := Vector3(40.0, 28.0, -60.0)
const SHAKE_DECAY := 0.06
## The flying bird's start, off to the side and above.
const BIRD_FROM := Vector3(-11.0, 8.5, KeepyMeshes.FAN_Z - 5.0)
## Where perched birds sit on the balloon (its local space), in landing order.
const PERCHES := [Vector3(0.0, 0.5, 0.06), Vector3(-0.24, 0.42, 0.1), Vector3(0.24, 0.42, 0.1)]

const SHADERS := "res://games/keepy_uppy/shaders/"
## The afternoon (ART_BIBLE §2): warm sun from the upper left.
const LOOK := {
	&"sun_elevation": 48.0,
	&"sun_azimuth": -38.0,
	&"sun_color": Color(1.0, 0.95, 0.85),
	&"sky_color": Color(0.5, 0.62, 0.78),
	&"ground_color": Color(0.32, 0.4, 0.26),
	&"haze_color": Color(0.8, 0.9, 0.97),
	&"haze_density": 0.0065,
	&"haze_max": 0.8,
}

var camera: Camera3D

var _noise: ImageTexture
var _lit: Array[ShaderMaterial] = []
var _dimmed: Array[ShaderMaterial] = []
var _sky_mat: ShaderMaterial
var _meadow_mat: ShaderMaterial
var _sun: DirectionalLight3D
var _ground_mat: ShaderMaterial
var _grass_mat: ShaderMaterial
var _streamer_mat: ShaderMaterial
var _column_mat: ShaderMaterial
var _balloon_mat: ShaderMaterial
var _rain_mat: ShaderMaterial
var _ring_mat: ShaderMaterial
var _bird_fly_mat: ShaderMaterial
var _rig: Node3D
var _fan: Node3D
var _blades: Node3D
var _balloon: Node3D
var _perched: Array[Node3D] = []
var _flyer: Node3D
var _rain_cloud: Node3D
var _rain: MeshInstance3D
var _curtain: MeshInstance3D
var _curtain_mat: ShaderMaterial
var _pop: CPUParticles3D
var _ring: MeshInstance3D

var _t := 0.0
var _pitch := PITCH_LOW
var _pan := 0.0
var _shake := 0.0
var _cloud_t := 0.0  ## 0 far, 1 overhead
var _cloud_leaving := false
var _rain_amount := 0.0
var _dim_shown := 1.0
var _downdraft_front := -45.0
var _downdraft_strength := 0.0
var _gusty_shown := -1.0
var _wind_shown := 99.0
var _flash := 0.0
var _blade_angle := 0.0
var _warming := false
var _popping := false
var _balloon_pos := Vector3(0.0, KeepyMeshes.height_y(KeepyLogic.START_HEIGHT), KeepyMeshes.FAN_Z)


func _ready() -> void:
	_noise = WorldLook.noise_texture()
	_build_environment()
	_build_ground()
	_build_meadow()
	_build_grass()
	_build_pole()
	_build_fan()
	_build_balloon()
	_build_birds()
	_build_weather()
	_build_rig()
	_build_fx()
	WorldLook.apply(_lit, look())


## The world's light: `WorldLook`'s uniforms for the afternoon.
static func look() -> Dictionary:
	return {
		&"sun_dir": WorldLook.sun_dir(LOOK.sun_elevation, LOOK.sun_azimuth),
		&"sun_color": LOOK.sun_color,
		&"sky_color": LOOK.sky_color,
		&"ground_color": LOOK.ground_color,
		&"haze_color": LOOK.haze_color,
		&"haze_density": LOOK.haze_density,
		&"haze_max": LOOK.haze_max,
	}


## Draws the logic's state. `cadence` turns the fan's drive wheel and blades.
func update_view(delta: float, logic: KeepyLogic, cadence := 0.0) -> void:
	_t += delta
	_update_balloon(delta, logic)
	_update_fan(delta, logic)
	_update_birds(logic)
	_update_weather(delta, logic)
	_update_camera(delta, logic)
	if _flash > 0.0:
		_flash = move_toward(_flash, 0.0, delta * 3.0)
		_balloon_mat.set_shader_parameter("flash", _flash)


## The balloon's place in the world now (for the HUD's and the tests' use).
func balloon_position() -> Vector3:
	return _balloon_pos


func pop_at_balloon() -> void:
	_pop.position = _balloon_pos
	_pop.restart()
	_pop.emitting = true
	_ring.position = _balloon_pos
	_ring.visible = true
	_popping = true
	_ring_mat.set_shader_parameter("progress", 0.0)
	var tween := create_tween()
	tween.tween_property(_ring_mat, "shader_parameter/progress", 1.0, 0.45)
	tween.tween_callback(func():
		_popping = false
		_ring.visible = _warming)
	_shake = 0.05
	_balloon.visible = false


## A gust or a landing: a white flash on the latex and a little shake.
func nudge(strength := 0.5) -> void:
	_flash = maxf(_flash, 0.25 * strength)
	_shake = maxf(_shake, 0.012 * strength)


## Draws every effect that starts hidden once, behind the intro card, so its shader compiles then
## (the Compatibility renderer compiles a material the first time it draws it).
func prewarm() -> void:
	_warming = true
	_ring.visible = true
	_ring_mat.set_shader_parameter("progress", 1.0)
	_rain.visible = true
	_flyer.visible = true
	_pop.position = Vector3(0.0, -4.0, KeepyMeshes.FAN_Z)
	_pop.restart()
	_pop.emitting = true
	for p in _perched:
		p.visible = true
	for i in WARM_FRAMES:
		await get_tree().process_frame
	_warming = false
	_pop.emitting = false
	_ring.visible = _popping
	_rain.visible = _rain_amount > 0.01
	_flyer.visible = false
	for p in _perched:
		p.visible = false


# --- Per frame ---

func _update_balloon(delta: float, logic: KeepyLogic) -> void:
	match logic.balloon:
		KeepyLogic.Balloon.FLYING:
			_balloon.visible = true
			var y := KeepyMeshes.height_y(logic.h) + sin(_t * 1.7) * 0.05
			var x := logic.x + sin(_t * 1.1) * 0.03
			if logic.gust == "gust":
				x += sin(_t * 19.0) * 0.08
			_balloon_pos = Vector3(x, y, KeepyMeshes.FAN_Z)
			var squash := clampf(logic.rate, -0.3, 0.3)
			_balloon.scale = Vector3(1.0 - squash * 0.25, 1.0 + squash * 0.5, 1.0 - squash * 0.25)
			var tilt := sin(_t * 1.3) * 4.0 + clampf((logic.x - logic.fan_x) * 10.0, -14.0, 14.0)
			_balloon.rotation_degrees = Vector3(0.0, sin(_t * 0.5) * 20.0, -tilt)
		KeepyLogic.Balloon.POPPED:
			_balloon.visible = false
		KeepyLogic.Balloon.ARRIVING:
			_balloon.visible = true
			var p := 1.0 - logic.state_left / KeepyLogic.ARRIVE_SEC
			var e := ease(clampf(p, 0.0, 1.0), -2.0)
			var from := Vector3(-7.5, 6.5, KeepyMeshes.FAN_Z - 2.5)
			var to := Vector3(logic.fan_x, KeepyMeshes.height_y(KeepyLogic.START_HEIGHT), KeepyMeshes.FAN_Z)
			_balloon_pos = from.lerp(to, e) + Vector3(0.0, sin(p * PI) * 0.6, 0.0)
			_balloon.scale = Vector3.ONE
			_balloon.rotation_degrees = Vector3(0.0, 0.0, (1.0 - e) * 18.0)
	_balloon.position = _balloon_pos


func _update_fan(delta: float, logic: KeepyLogic) -> void:
	_fan.position.x = logic.fan_x
	var power_share := clampf(logic.smoothed / maxf(logic.ftp, 1.0), 0.0, 1.2)
	_blade_angle = fmod(_blade_angle + delta * power_share * 40.0, TAU)
	_blades.rotation.y = _blade_angle
	var strength := clampf(logic.smoothed / maxf(logic.weight(), 1.0) * 0.7, 0.0, 1.0) * logic.efficiency
	var speed := lerpf(0.25, 1.4, strength)
	if logic.weather == KeepyLogic.Weather.ACTIVE and logic.force == "downdraft":
		speed = -0.9
	_column_mat.set_shader_parameter("strength", strength)
	_column_mat.set_shader_parameter("speed", speed)


func _update_birds(logic: KeepyLogic) -> void:
	var flying := logic.balloon == KeepyLogic.Balloon.FLYING
	for i in _perched.size():
		var on := flying and i < logic.birds
		_perched[i].visible = on or _warming
		if on:
			var perch: Vector3 = PERCHES[i]
			_perched[i].position = _balloon_pos + _balloon.basis * (perch * Vector3(1.0, _balloon.scale.y, 1.0))
	var incoming := logic.weather == KeepyLogic.Weather.TELEGRAPH and logic.force == "bird" and flying
	_flyer.visible = incoming or _warming
	if incoming:
		var p := 1.0 - logic.force_left / KeepyLogic.WARNING.bird
		var land: Vector3 = _balloon_pos + PERCHES[mini(logic.birds, PERCHES.size() - 1)]
		var e := ease(clampf(p, 0.0, 1.0), -1.6)
		_flyer.position = BIRD_FROM.lerp(land, e) + Vector3(0.0, sin(p * PI) * 1.2, 0.0)
		_flyer.rotation_degrees.y = 60.0 * (1.0 - e)


func _update_weather(delta: float, logic: KeepyLogic) -> void:
	# The rain cloud: in on its warning, overhead while it rains, then away to the right.
	var rain_coming := logic.force == "rain" and logic.weather != KeepyLogic.Weather.CALM
	if rain_coming:
		_cloud_leaving = false
		if logic.weather == KeepyLogic.Weather.TELEGRAPH:
			_cloud_t = maxf(_cloud_t, 1.0 - logic.force_left / KeepyLogic.WARNING.rain)
		else:
			_cloud_t = 1.0
	elif logic.raining:
		_cloud_t = 1.0
	elif _cloud_t > 0.0:
		_cloud_leaving = true
		_cloud_t = move_toward(_cloud_t, 0.0, delta / 4.0)
	var e := ease(_cloud_t, -1.8)
	var far := CLOUD_GONE if _cloud_leaving else CLOUD_FAR
	_rain_cloud.position = far.lerp(CLOUD_OVER, e) + Vector3(sin(_t * 0.3) * 0.4, 0.0, 0.0)
	_rain_cloud.visible = _cloud_t > 0.001
	_rain_amount = move_toward(_rain_amount, 1.0 if logic.raining else 0.0, delta / 1.2)
	_rain.visible = _rain_amount > 0.01 or _warming
	_rain_mat.set_shader_parameter("amount", _rain_amount)
	var cp := _rain_cloud.position
	_ground_mat.set_shader_parameter("cloud_shadow", Vector4(cp.x + 2.0, cp.z + 3.0, 8.5, clampf(e * 1.2, 0.0, 1.0)))
	var dim := 1.0 - 0.2 * _rain_amount
	if absf(dim - _dim_shown) > 0.005:
		_dim_shown = dim
		for m in _dimmed:
			m.set_shader_parameter("dim", dim)
	# The downdraft: a dark band of flattened grass rolls in on its warning and past the fan.
	if logic.force == "downdraft" and logic.weather == KeepyLogic.Weather.TELEGRAPH:
		var p := 1.0 - logic.force_left / KeepyLogic.WARNING.downdraft
		_downdraft_front = lerpf(-45.0, KeepyMeshes.FAN_Z, p)
		_downdraft_strength = minf(_downdraft_strength + delta * 2.0, 1.0)
	elif logic.force == "downdraft" and logic.weather == KeepyLogic.Weather.ACTIVE:
		_downdraft_front = minf(_downdraft_front + delta * 8.0, 4.0)
		_downdraft_strength = 1.0
	else:
		_downdraft_front = minf(_downdraft_front + delta * 8.0, 6.0)
		_downdraft_strength = move_toward(_downdraft_strength, 0.0, delta * 1.5)
	var band := Vector3(_downdraft_front, 12.0, _downdraft_strength)
	_curtain.visible = (_downdraft_strength > 0.01 and _downdraft_front < 1.0) or _warming
	if _curtain.visible:
		_curtain.position = Vector3(0.0, 6.0, _downdraft_front - 1.0)
		_curtain_mat.set_shader_parameter("amount", _downdraft_strength * (1.0 - smoothstep(-6.0, 0.5, _downdraft_front)))
	_ground_mat.set_shader_parameter("downdraft", band)
	_grass_mat.set_shader_parameter("downdraft", band)
	# Gusts whip the streamers; the wind leans everything.
	var gusty := 0.0
	if logic.gust != "" or (logic.force == "downdraft" and logic.weather != KeepyLogic.Weather.CALM):
		gusty = 1.0
	elif logic.steer:
		gusty = absf(logic.wind_target) / KeepyLogic.WIND_MAX * 0.3
	# The windsock and streamers show the new wind as soon as it's chosen (the target).
	var wind := 0.3
	if logic.steer:
		wind = logic.wind_target / KeepyLogic.WIND_MAX
	var g := move_toward(maxf(_gusty_shown, 0.0), gusty, delta * 3.0)
	var w := move_toward(_wind_shown if _wind_shown < 90.0 else wind, wind, delta * 1.5)
	if absf(g - _gusty_shown) > 0.01 or absf(w - _wind_shown) > 0.01:
		_gusty_shown = g
		_wind_shown = w
		for m in [_streamer_mat, _grass_mat, _meadow_mat]:
			m.set_shader_parameter("gusty", g)
			m.set_shader_parameter("wind_dir", w)


func _update_camera(delta: float, logic: KeepyLogic) -> void:
	var h_vis := clampf((_balloon_pos.y - KeepyMeshes.GROUND_Y) / (KeepyMeshes.TOP_Y - KeepyMeshes.GROUND_Y), 0.0, 1.0)
	_pitch = lerpf(_pitch, lerpf(PITCH_LOW, PITCH_HIGH, h_vis), 1.0 - exp(-delta / PITCH_TAU))
	var pan_target := 0.0
	if logic.steer:
		pan_target = -rad_to_deg(atan2(_balloon_pos.x * PAN_SHARE, -KeepyMeshes.FAN_Z))
	_pan = lerpf(_pan, pan_target, 1.0 - exp(-delta / PAN_TAU))
	_shake = move_toward(_shake, 0.0, delta * SHAKE_DECAY)
	var jitter := Vector3(sin(_t * 61.0), cos(_t * 53.0), 0.0) * _shake
	_rig.position = Vector3(0.0, EYE_HEIGHT, 0.0) + jitter
	_rig.rotation_degrees = Vector3(0.0, _pan, 0.0)
	camera.rotation_degrees = Vector3(_pitch, 0.0, 0.0)


# --- Building ---

func _material(shader_file: String, dimmed := true) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(SHADERS + shader_file)
	m.set_shader_parameter("noise_tex", _noise)
	_lit.append(m)
	if dimmed:
		_dimmed.append(m)
	return m


func _instance(mesh: Mesh, mat: Material, node_name: String, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load(SHADERS + "sky.gdshader")
	_sky_mat.set_shader_parameter("noise_tex", _noise)
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.fog_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	add_child(we)
	_lit.append(_sky_mat)
	# The sun only places the sky's disc; it lights nothing.
	_sun = DirectionalLight3D.new()
	_sun.shadow_enabled = false
	_sun.sky_mode = DirectionalLight3D.SKY_MODE_SKY_ONLY
	var to_sun := WorldLook.sun_dir(LOOK.sun_elevation, LOOK.sun_azimuth)
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP)
	_sun.light_color = LOOK.sun_color
	add_child(_sun)


func _build_ground() -> void:
	_ground_mat = _material("ground.gdshader")
	var plane := PlaneMesh.new()
	plane.size = Vector2(360.0, 300.0)
	plane.subdivide_width = 23
	plane.subdivide_depth = 19
	var gi := _instance(plane, _ground_mat, "Ground")
	gi.position = Vector3(0.0, 0.0, -130.0)


func _build_meadow() -> void:
	var models := {
		"trees": [KeepyMeshes.model(DodgeWorld._model_mesh("tree_oak.glb"), Color(0.36, 0.6, 0.24), Color(0.45, 0.32, 0.2)),
			KeepyMeshes.model(DodgeWorld._model_mesh("tree_default.glb"), Color(0.42, 0.66, 0.26), Color(0.45, 0.32, 0.2)),
			KeepyMeshes.model(DodgeWorld._model_mesh("tree_cone.glb"), Color(0.3, 0.55, 0.26), Color(0.45, 0.32, 0.2))],
		"bush": KeepyMeshes.model(DodgeWorld._model_mesh("plant_bushLarge.glb"), Color(0.38, 0.62, 0.26), Color(0.38, 0.62, 0.26)),
	}
	var mi := _instance(KeepyMeshes.meadow(models), _lit_meadow(), "Meadow")
	mi.extra_cull_margin = 4.0
	var cloud_mat := _material("meadow.gdshader", false)
	cloud_mat.set_shader_parameter("self_lit", 0.85)
	cloud_mat.set_shader_parameter("grain", 0.0)
	_instance(KeepyMeshes.sky_clouds(), cloud_mat, "Clouds")


func _build_grass() -> void:
	_grass_mat = _material("grass.gdshader")
	var rng := RandomNumberGenerator.new()
	rng.seed = 2611
	for kind in 2:
		var flower := kind == 1
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true  # Compatibility zeroes COLOR in a MultiMesh without instance colours
		mm.use_custom_data = true
		mm.mesh = KeepyMeshes.tuft(flower)
		mm.instance_count = FLOWERS if flower else GRASS_TUFTS
		for i in mm.instance_count:
			# Scattered in front, thicker near, kept off the fan's rails.
			var z := -lerpf(2.2, 34.0, pow(rng.randf(), 1.6))
			var x := rng.randf_range(-1.0, 1.0) * (3.0 + -z * 0.9)
			if absf(z - KeepyMeshes.FAN_Z) < 1.0 and absf(x) < 2.6:
				x += 3.2 * signf(x if x != 0.0 else 1.0)
			var s := rng.randf_range(0.8, 1.5) * (1.0 + -z * 0.02)
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, 0.0, z)))
			mm.set_instance_color(i, Color.WHITE)
			var fc: Color = KeepyMeshes.lin(KeepyMeshes.FLOWERS[rng.randi() % KeepyMeshes.FLOWERS.size()])
			mm.set_instance_custom_data(i, fc)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "Flowers" if flower else "Grass"
		mmi.multimesh = mm
		mmi.material_override = _grass_mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.extra_cull_margin = 2.0
		add_child(mmi)


func _build_pole() -> void:
	var pole_node := Node3D.new()
	pole_node.name = "Pole"
	pole_node.position = Vector3(KeepyMeshes.POLE_X, 0.0, KeepyMeshes.FAN_Z)
	add_child(pole_node)
	_instance(KeepyMeshes.pole(), _lit_meadow(), "Post", pole_node)
	_streamer_mat = _material("meadow.gdshader")
	_streamer_mat.shader = _streamer_shader()
	_streamer_mat.set_shader_parameter("sway", 0.22)
	_streamer_mat.set_shader_parameter("grain", 0.0)
	_instance(KeepyMeshes.streamers(), _streamer_mat, "Streamers", pole_node)


## The meadow's own material, shared by every lit built thing (one material: the batch stays
## cheap and the wind uniforms are set once).
func _lit_meadow() -> ShaderMaterial:
	if _meadow_mat == null:
		_meadow_mat = _material("meadow.gdshader")
	return _meadow_mat


## Streamers are thin cards seen from both sides: the meadow shader without back-face culling.
static var _streamer_shader_cache: Shader


static func _streamer_shader() -> Shader:
	if _streamer_shader_cache == null:
		var src := (load(SHADERS + "meadow.gdshader") as Shader).code
		_streamer_shader_cache = Shader.new()
		_streamer_shader_cache.code = src.replace("cull_back", "cull_disabled")
	return _streamer_shader_cache


func _build_fan() -> void:
	_fan = Node3D.new()
	_fan.name = "Fan"
	_fan.position = Vector3(0.0, 0.0, KeepyMeshes.FAN_Z)
	add_child(_fan)
	_instance(KeepyMeshes.fan_box(), _lit_meadow(), "Crate", _fan)
	_blades = Node3D.new()
	_blades.position = Vector3(0.0, KeepyMeshes.FAN_TOP - 0.08, 0.0)
	_fan.add_child(_blades)
	_instance(KeepyMeshes.fan_blades(), _lit_meadow(), "Blades", _blades)
	_column_mat = ShaderMaterial.new()
	_column_mat.shader = load(SHADERS + "column.gdshader")
	_column_mat.set_shader_parameter("noise_tex", _noise)
	var col := _instance(KeepyMeshes.column(), _column_mat, "Column", _fan)
	col.extra_cull_margin = 2.0


func _build_balloon() -> void:
	_balloon = Node3D.new()
	_balloon.name = "Balloon"
	add_child(_balloon)
	_balloon_mat = _material("balloon.gdshader")
	_instance(KeepyMeshes.balloon(), _balloon_mat, "Latex", _balloon)
	_balloon.position = _balloon_pos


func _build_birds() -> void:
	var mesh := KeepyMeshes.bird()
	var perched_mat := _lit_meadow()
	for i in KeepyLogic.MAX_BIRDS:
		var b := Node3D.new()
		b.name = "Bird%d" % i
		b.scale = Vector3.ONE * 1.5
		b.visible = false
		add_child(b)
		_instance(mesh, perched_mat, "Body", b)
		_perched.append(b)
	_flyer = Node3D.new()
	_flyer.name = "FlyingBird"
	_flyer.scale = Vector3.ONE * 1.5
	_flyer.visible = false
	add_child(_flyer)
	_bird_fly_mat = _material("meadow.gdshader")
	_bird_fly_mat.set_shader_parameter("flap", 1.0)
	_bird_fly_mat.set_shader_parameter("grain", 0.0)
	_instance(mesh, _bird_fly_mat, "Body", _flyer)


func _build_weather() -> void:
	_rain_cloud = Node3D.new()
	_rain_cloud.name = "RainCloud"
	_rain_cloud.visible = false
	add_child(_rain_cloud)
	var cloud_mat := _material("meadow.gdshader", false)
	cloud_mat.set_shader_parameter("self_lit", 0.6)
	cloud_mat.set_shader_parameter("grain", 0.0)
	var c := _instance(KeepyMeshes.rain_cloud(), cloud_mat, "Cloud", _rain_cloud)
	c.scale = Vector3(2.2, 1.4, 1.8)
	_rain_mat = ShaderMaterial.new()
	_rain_mat.shader = load(SHADERS + "rain.gdshader")
	_rain_mat.set_shader_parameter("noise_tex", _noise)
	var tube := CylinderMesh.new()
	tube.top_radius = 3.4
	tube.bottom_radius = 3.0
	tube.height = 10.0
	tube.radial_segments = 16
	tube.rings = 1
	tube.cap_top = false
	tube.cap_bottom = false
	_rain = _instance(tube, _rain_mat, "Rain", _rain_cloud)
	_rain.position = Vector3(0.0, -5.0, 0.0)
	_rain.visible = false
	# The downdraft's curtain: a wide card of dark, slanting air rolling in toward the fan.
	_curtain_mat = ShaderMaterial.new()
	_curtain_mat.shader = _rain_mat.shader
	_curtain_mat.set_shader_parameter("noise_tex", _noise)
	_curtain_mat.set_shader_parameter("tint", Color(0.24, 0.3, 0.34))
	_curtain_mat.set_shader_parameter("fall", 1.4)
	_curtain_mat.set_shader_parameter("columns", 56.0)
	_curtain_mat.set_shader_parameter("density", 0.55)
	_curtain_mat.set_shader_parameter("opacity", 0.5)
	_curtain_mat.set_shader_parameter("slant", 4.0)
	var card := QuadMesh.new()
	card.size = Vector2(46.0, 13.0)
	_curtain = _instance(card, _curtain_mat, "Downdraft")
	_curtain.visible = false


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	camera = Camera3D.new()
	camera.fov = FOV
	camera.near = 0.05
	camera.far = 300.0
	_rig.add_child(camera)
	_rig.position = Vector3(0.0, EYE_HEIGHT, 0.0)
	add_child(_rig)
	camera.rotation_degrees = Vector3(PITCH_LOW, 0.0, 0.0)
	# The bars ride with the camera, so they stay at the foot of the view as it pitches up.
	var bars := _instance(KeepyMeshes.handlebars(), _lit_meadow(), "Handlebars", camera)
	bars.position = Vector3(0.0, -0.34, -0.72)


func _build_fx() -> void:
	var shard := BoxMesh.new()
	shard.size = Vector3(0.09, 0.06, 0.015)
	_pop = CPUParticles3D.new()
	_pop.name = "Pop"
	_pop.mesh = shard
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = KeepyMeshes.BALLOON
	mat.disable_fog = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_pop.material_override = mat
	_pop.amount = 28
	_pop.lifetime = 1.1
	_pop.one_shot = true
	_pop.emitting = false
	_pop.explosiveness = 1.0
	_pop.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	_pop.emission_sphere_radius = 0.35
	_pop.direction = Vector3.UP
	_pop.spread = 180.0
	_pop.initial_velocity_min = 2.0
	_pop.initial_velocity_max = 4.5
	_pop.gravity = Vector3(0.0, -6.0, 0.0)
	_pop.angular_velocity_min = -360.0
	_pop.angular_velocity_max = 360.0
	_pop.damping_min = 1.0
	_pop.damping_max = 2.0
	_pop.local_coords = false
	add_child(_pop)
	var quad := QuadMesh.new()
	quad.size = Vector2(2.6, 2.6)
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load(SHADERS + "ring.gdshader")
	_ring = _instance(quad, _ring_mat, "Ring")
	_ring.visible = false
	_ring.extra_cull_margin = 2.0
