class_name DodgeWorld
extends Node3D
## Dodge Ball's 3D view (#39): the road seen from the bike. It only draws `DodgeBallLogic`; the
## game scene (`DodgeBall.gd`) feeds it each frame. Built in code for GL Compatibility on the
## Gen 2 tablet (PowerVR GX6250), so every choice here is about draw calls and fill rate:
##
##   - One sun (no shadows) and colour ambient light; night lighting (headlight, street lamps)
##     is emission in the road shader, not real lights (each is an extra pass in Compatibility).
##   - The road and verges are single planes whose shaders scroll with distance travelled.
##   - Scenery comes in three 50 m chunks that leapfrog forward as they pass the bike, each a few
##     MultiMeshes (one draw call per model per chunk), so nothing moves per instance.
##   - Balls, their shadows and their warnings are three MultiMeshes, updated per frame.
##   - Feedback uses pooled CPUParticles3D and Label3D; screen effects are one canvas shader.
##
## Comfort on a stationary bike: the view only moves sideways with the rider's own lean, rolls
## a few degrees at most (and not at all when the rider turns it off), and the hit shake is a
## small, brief sideways nudge with no rotation.

const DodgeTimeOfDayRes := preload("res://games/dodge_ball/TimeOfDay.gd")

const RIDER_LINE_Z := -1.4  ## where balls reach the bike (just ahead of the camera)
const EYE_HEIGHT := 1.45
const CAMERA_PITCH := -7.0
const ROLL_MAX_DEG := 3.0
const CHUNK_LEN := 50.0
const CHUNKS := 3
const LAMP_SPACING := 25.0
const SCROLL_WRAP := 450.0  ## a multiple of every road pattern's period (9, 2, 25 and 45 m)
const ROLL_SPEED := 6.0  ## m/s a ball rolls at the rider, on top of road speed
## m/s² cap on the road speed's change: quick enough that a burst of pedalling shows at once,
## smooth enough that stopping eases the bike to a halt. (Balls keep the approach speed they
## were thrown at, so this never bunches or reverses them.)
const MAX_ACCEL := 7.0
const FOV_SLOW := 62.0
const FOV_FAST := 72.0  ## a slight widening at speed
const FAST_SPEED := 25.0  ## m/s where the FOV is widest and the speed streaks are thickest
const STREAKS_FROM := 17.0  ## m/s (about 90 rpm) where speed streaks start
const BALLS_MAX := 32
const BOUNCE_PERIOD := 0.55
const BOUNCE_HEIGHT := 0.7
const GHOST_SEC := 0.6

## Dodge: danger reds. Catch: reward golds, so the mode is unmistakable at a glance.
const BALL_COLORS := {
	"plain": Color(0.98, 0.22, 0.16),
	"curve": Color(0.85, 0.15, 0.45),
	"double": Color(1.0, 0.42, 0.1),
}
const CATCH_COLORS := {
	"plain": Color(1.0, 0.8, 0.18),
	"curve": Color(1.0, 0.62, 0.1),
	"double": Color(0.95, 0.9, 0.35),
}

const MODELS := "res://games/dodge_ball/models/"

## Dev switches from the tablet tuning file (`DodgeBall.TUNING_PATH`, [world] section), for
## finding what costs frame time: sky, fog, scenery, verges, road, balls, rig (each true by
## default). Set before the node enters the tree. (An instance property: assigning another
## class's static var crashed the exported build on the tablet.)
var tuning := {}

## Emitted when a bouncing ball lands near the rider (for its sound), with 0-1 loudness.
signal ball_bounced(loudness: float)

var roll_enabled := true
var road_speed := 0.0  ## m/s, smoothed
var distance := 0.0

var camera: Camera3D
var _rig: Node3D
var _env: WorldEnvironment
var _sun: DirectionalLight3D
var _sky_mat: ShaderMaterial
var _road_mat: ShaderMaterial
var _verge_mat: ShaderMaterial
var _shield_mat: ShaderMaterial
var _ball_mm: MultiMesh
var _blob_mm: MultiMesh
var _warn_mm: MultiMesh
var _chunks: Array[Node3D] = []
var _halo_mat: StandardMaterial3D
var _bursts: Array[CPUParticles3D] = []
var _sparks: Array[CPUParticles3D] = []
var _shards: CPUParticles3D
var _popups: Array[Label3D] = []
var _next_burst := 0
var _next_spark := 0
var _next_popup := 0
var _roll := 0.0
var _shield_flash := 0.0
var _shake := 0.0
var _shake_t := 0.0
var _anim_t := 0.0
var _ghosts: Array[Dictionary] = []  # dodged balls rolling on past the bike: {x, z, kind, t, y}
var _bounce_phase := {}  # ball id -> last bounce index, for the landing sound
var _ball_speed := {}  # ball id -> its approach speed (m/s), fixed when it was thrown
var _streaks: CPUParticles3D
var _speed_feel := 0.0  ## 0-1: how fast the ride looks (FOV, streaks), smoothed
var _tod: DodgeTimeOfDay
var _noise: ImageTexture


func _ready() -> void:
	_noise = _noise_texture()
	_build_environment()
	_build_road()
	_build_scenery()
	_build_rig()
	_build_balls()
	_build_fx()
	_apply_tuning()


## The dev switches in `tuning` (after everything is built).
func _apply_tuning() -> void:
	if not tuning.get("sky", true):
		_env.environment.background_mode = Environment.BG_COLOR
		_env.environment.background_color = Color(0.4, 0.5, 0.7)
	if not tuning.get("fog", true):
		_env.environment.fog_enabled = false
	for chunk in _chunks:
		chunk.visible = tuning.get("scenery", true)
	for node in get_children():
		if node is MeshInstance3D and node.material_override == _verge_mat:
			node.visible = tuning.get("verges", true)
		if node is MeshInstance3D and node.material_override == _road_mat:
			node.visible = tuning.get("road", true)
		if node is MultiMeshInstance3D:
			node.visible = tuning.get("balls", true)
	for node in camera.get_children():
		node.visible = tuning.get("rig", true)


# --- Feeding the view ---

## Advances the scenery and draws `logic`'s balls. `cadence_speed` is the road speed the
## cadence asks for (m/s); `lean` the raw lean for the roll.
func update_view(delta: float, logic: DodgeBallLogic, cadence_speed: float, lean: float) -> void:
	_anim_t += delta
	road_speed = move_toward(road_speed, cadence_speed, MAX_ACCEL * delta)
	_speed_feel = clampf(road_speed / FAST_SPEED, 0.0, 1.0)
	camera.fov = lerpf(FOV_SLOW, FOV_FAST, _speed_feel * _speed_feel)
	var streaks := clampf((road_speed - STREAKS_FROM) / (FAST_SPEED + 5.0 - STREAKS_FROM), 0.0, 1.0)
	_streaks.emitting = streaks > 0.0 and tuning.get("streaks", true)
	_streaks.color = Color(1, 1, 1, 0.08 + 0.2 * streaks)
	_streaks.initial_velocity_min = road_speed * 1.6
	_streaks.initial_velocity_max = road_speed * 2.0
	distance += road_speed * delta
	var scroll := fmod(distance, SCROLL_WRAP)
	_road_mat.set_shader_parameter("scroll", scroll)
	_verge_mat.set_shader_parameter("scroll", scroll)
	for chunk in _chunks:
		chunk.position.z += road_speed * delta
		if chunk.position.z - CHUNK_LEN > 4.0:
			chunk.position.z -= CHUNK_LEN * CHUNKS

	_rig.position.x = logic.rider_x
	_road_mat.set_shader_parameter("rider_x", logic.rider_x)
	var target_roll := -clampf(lean, -1.0, 1.0) * deg_to_rad(ROLL_MAX_DEG) if roll_enabled else 0.0
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-6.0 * delta))
	camera.rotation.z = _roll
	if _shake > 0.0:
		_shake = maxf(0.0, _shake - delta * 4.0)
		_shake_t += delta * 40.0
		camera.position.x = sin(_shake_t) * 0.04 * _shake * _shake
	else:
		camera.position.x = 0.0

	_shield_mat.set_shader_parameter("strength", logic.shield)
	_shield_flash = maxf(0.0, _shield_flash - delta * 2.5)
	_shield_mat.set_shader_parameter("flash", _shield_flash)
	_draw_balls(delta, logic)


func approach_speed() -> float:
	return road_speed + ROLL_SPEED


## A new ball: it keeps the approach speed of this moment, so it closes at a steady speed and
## arrives exactly when the rules say, however the rider's cadence changes meanwhile.
func note_spawn(ball: Dictionary) -> void:
	_ball_speed[ball.id] = approach_speed()


## The z a ball with `eta` seconds to go is at.
func z_for_eta(eta: float, speed := -1.0) -> float:
	return RIDER_LINE_Z - eta * (speed if speed > 0.0 else approach_speed())


## A ball's colour: danger red when dodging, reward gold when catching.
static func ball_color(kind: String, catch_mode: bool) -> Color:
	var table: Dictionary = CATCH_COLORS if catch_mode else BALL_COLORS
	return table.get(kind, table.plain)


func set_time_of_day(tod: DodgeTimeOfDay) -> void:
	_tod = tod
	var env := _env.environment
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
	env.ambient_light_color = tod.ambient
	env.ambient_light_energy = tod.ambient_energy
	env.fog_light_color = tod.fog_color
	env.fog_density = tod.fog_density
	# The road and verges light and fog themselves (see road.gdshader): a flat surface under
	# the sun gets sin(elevation) of it, plus the ambient light.
	var light := tod.ambient * tod.ambient_energy + tod.sun_color * tod.sun_energy * maxf(sin(e), 0.12)
	for mat in [_road_mat, _verge_mat]:
		mat.set_shader_parameter("light_color", Vector3(light.r, light.g, light.b))
		mat.set_shader_parameter("fog_color", tod.fog_color)
		mat.set_shader_parameter("fog_density", tod.fog_density if tuning.get("fog", true) else 0.0)
	_road_mat.set_shader_parameter("headlight", tod.headlight)
	_road_mat.set_shader_parameter("lamp_glow", tod.lamp_glow)
	_halo_mat.albedo_color = Color(1.0, 0.8, 0.5, clampf(tod.lamp_glow, 0.0, 1.0))
	for chunk in _chunks:
		chunk.get_node("Halos").visible = tod.lamp_glow > 0.05
	if not tuning.get("fog", true):
		env.fog_enabled = false


# --- Feedback ---

## A hit: the ball bursts at `x`, the screen nudges sideways.
func hit_fx(x: float, kind: String, catch_mode := false, shake := 1.0) -> void:
	var p := _bursts[_next_burst]
	_next_burst = (_next_burst + 1) % _bursts.size()
	# A little ahead of the bars, so the burst reads as the ball breaking up, not as debris in
	# the rider's face.
	p.position = Vector3(x, 0.5, RIDER_LINE_Z - 2.0)
	p.color = ball_color(kind, catch_mode)
	p.restart()
	_shake = shake


## Catch: a caught ball bursts into gold sparks at the bike, and the points float up.
func catch_fx(ball: Dictionary, points: float, bonus: bool) -> void:
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	p.position = Vector3(ball.x1, 0.7, RIDER_LINE_Z - 1.0)
	p.color = Color(1.0, 0.85, 0.3)
	p.restart()
	_shield_flash = maxf(_shield_flash, 0.35)
	_popup(ball.x1, points, true if bonus else false, Color(1.0, 0.85, 0.3))


## Catch: a missed ball rolls on past the bike.
func miss_fx(ball: Dictionary) -> void:
	_ghost(ball)


## Catch: a fumbled ball (caught with the shield down) knocks against the bike and rolls away.
func fumble_fx(ball: Dictionary) -> void:
	hit_fx(ball.x1, ball.kind, true, 0.4)


## The shield takes a hit: a flash and shards off the shield.
func shield_fx(x: float, kind: String) -> void:
	hit_fx(x, kind)
	_shake = 0.6
	_shield_flash = 1.0
	_shards.position = Vector3(x, 0.9, RIDER_LINE_Z - 1.0)
	_shards.restart()


func shield_ready_fx() -> void:
	_shield_flash = 0.5


## A clean dodge: sparks where the ball passed, and the points floating up.
func dodge_fx(ball: Dictionary, points: float, bonus: bool) -> void:
	var p := _sparks[_next_spark]
	_next_spark = (_next_spark + 1) % _sparks.size()
	p.position = Vector3(ball.x1, 0.5, RIDER_LINE_Z)
	p.color = Color(0.6, 0.95, 1.0)
	p.restart()
	_ghost(ball)
	_popup(ball.x1, points, bonus, Color(1.0, 0.82, 0.25) if bonus else Color(1, 1, 1))


func _ghost(ball: Dictionary) -> void:
	_ghosts.append({"x": ball.x1, "z": RIDER_LINE_Z, "kind": ball.kind, "t": 0.0, "y": BALL_RADIUS(),
		"v": _ball_speed.get(ball.id, approach_speed()), "catch": ball.get("mode", "") == "catch"})
	_ball_speed.erase(ball.id)


func _popup(x_at: float, points: float, _bonus: bool, color: Color) -> void:
	if points <= 0.0:
		return
	var label := _popups[_next_popup]
	_next_popup = (_next_popup + 1) % _popups.size()
	label.text = "+%d" % roundi(points)
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.8)
	var x := clampf(lerpf(x_at, _rig.position.x, 0.5), _rig.position.x - 1.2, _rig.position.x + 1.2)
	label.position = Vector3(x, 0.9, RIDER_LINE_Z - 3.0)
	label.visible = true
	var tween := label.create_tween()
	tween.set_parallel()
	tween.tween_property(label, "position:y", 1.35, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.2)
	tween.chain().tween_callback(func(): label.visible = false)


## Fires every effect once in view, behind the intro card, so their shaders compile then and not
## at the first hit (that hitch read 9 fps on the tablet).
func prewarm() -> void:
	var all: Array[CPUParticles3D] = []
	all.append_array(_bursts)
	all.append_array(_sparks)
	all.append(_shards)
	for p in all:
		p.position = Vector3(_rig.position.x, 1.0, RIDER_LINE_Z - 6.0)
		p.restart()
	_streaks.emitting = true
	_popup(_rig.position.x, 10.0, false, Color(1, 1, 1))


func streak_fx() -> void:
	var tween := create_tween()
	tween.tween_method(func(v: float): _road_mat.set_shader_parameter("pulse", v), 1.0, 0.0, 0.8)


# --- Building ---

func _build_environment() -> void:
	_env = WorldEnvironment.new()
	var env := Environment.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://games/dodge_ball/shaders/sky.gdshader")
	_sky_mat.set_shader_parameter("noise_tex", _noise)
	# Its own texture object: GLES3 keeps filtering per texture, and stars need nearest.
	_sky_mat.set_shader_parameter("star_tex", _noise_texture())
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


func _build_road() -> void:
	var road := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(DodgeBallLogic.ROAD_HALF * 2.0, 220.0)
	road.mesh = plane
	road.position = Vector3(0, 0, -100.0)
	_road_mat = ShaderMaterial.new()
	_road_mat.shader = load("res://games/dodge_ball/shaders/road.gdshader")
	_road_mat.set_shader_parameter("road_half", DodgeBallLogic.ROAD_HALF)
	_road_mat.set_shader_parameter("noise_tex", _noise)
	_road_mat.set_shader_parameter("lamp_side_x", DodgeBallLogic.ROAD_HALF + 1.2)
	_road_mat.set_shader_parameter("lamp_spacing", LAMP_SPACING)
	road.material_override = _road_mat
	road.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(road)
	_verge_mat = ShaderMaterial.new()
	_verge_mat.shader = load("res://games/dodge_ball/shaders/verge.gdshader")
	_verge_mat.set_shader_parameter("road_half", DodgeBallLogic.ROAD_HALF)
	_verge_mat.set_shader_parameter("noise_tex", _noise)
	for side in [-1.0, 1.0]:
		var verge := MeshInstance3D.new()
		var vp := PlaneMesh.new()
		vp.size = Vector2(80.0, 220.0)
		verge.mesh = vp
		verge.position = Vector3(side * (DodgeBallLogic.ROAD_HALF + 40.0), -0.02, -100.0)
		verge.material_override = _verge_mat
		verge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(verge)


## Each chunk: lamps both sides (staggered), trees, bushes and rocks, a few cones on the kerb.
func _build_scenery() -> void:
	var lamp := _cheap(_model_mesh("light-curved.glb"))
	var trees := [_recolor(_model_mesh("tree_default.glb"), Color(0.32, 0.56, 0.2)),
		_recolor(_model_mesh("tree_oak.glb"), Color(0.26, 0.48, 0.17)),
		_recolor(_model_mesh("tree_pineTallA.glb"), Color(0.16, 0.36, 0.2)),
		_recolor(_model_mesh("tree_cone.glb"), Color(0.38, 0.6, 0.22))]
	var bush := _recolor(_model_mesh("plant_bushLarge.glb"), Color(0.3, 0.52, 0.2))
	var rock := _recolor(_model_mesh("rock_largeA.glb"), Color(0.5, 0.5, 0.47), Color(0.42, 0.41, 0.39))
	var cone := _cheap(_model_mesh("construction-cone.glb"))
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.disable_fog = true
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.25, Color(1, 1, 1, 0.45))
	glow.gradient = g
	_halo_mat.albedo_texture = glow
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(1.6, 1.6)
	halo_quad.material = _halo_mat

	var lamp_height := 6.0
	var lamp_scale := lamp_height / maxf(0.01, lamp.get_aabb().size.y) if lamp else 1.0
	var lamp_aabb: AABB = lamp.get_aabb() if lamp else AABB()
	# The model's arm reaches along -z; each lamp is turned so it reaches over the road.
	var head_local := Vector3(lamp_aabb.get_center().x, lamp_aabb.end.y - 0.03, lamp_aabb.position.z + 0.02) * lamp_scale

	for c in CHUNKS:
		var chunk := Node3D.new()
		chunk.name = "Chunk%d" % c
		chunk.position.z = -c * CHUNK_LEN
		add_child(chunk)
		_chunks.append(chunk)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7919 * (c + 1)
		var lamp_xf: Array[Transform3D] = []
		var halo_xf: Array[Transform3D] = []
		var lamp_x := DodgeBallLogic.ROAD_HALF + 1.2
		for k in int(CHUNK_LEN / LAMP_SPACING):
			for side in [-1.0, 1.0]:
				var z := -k * LAMP_SPACING - (0.0 if side < 0.0 else LAMP_SPACING * 0.5)
				# Left lamps reach towards +x, right ones towards -x.
				var yaw := -PI / 2.0 if side < 0.0 else PI / 2.0
				var basis := Basis(Vector3.UP, yaw).scaled(Vector3.ONE * lamp_scale)
				lamp_xf.append(Transform3D(basis, Vector3(side * lamp_x, 0, z)))
				var head := Basis(Vector3.UP, yaw) * head_local
				halo_xf.append(Transform3D(Basis(), Vector3(side * lamp_x, -0.15, z) + head))
		if lamp:
			chunk.add_child(_multimesh(lamp, lamp_xf, "Lamps"))
		var halos := _multimesh(halo_quad, halo_xf, "Halos")
		chunk.add_child(halos)

		var per_tree: Array[Array] = []
		for t in 4:
			per_tree.append([] as Array[Transform3D])
		for i in 26:
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := side * rng.randf_range(DodgeBallLogic.ROAD_HALF + 3.5, 32.0)
			var z := -rng.randf_range(0.0, CHUNK_LEN)
			var which := rng.randi_range(0, 3)
			var mesh: Mesh = trees[which]
			if mesh == null:
				continue
			var h := rng.randf_range(5.0, 9.0) * (1.3 if which == 2 else 1.0)
			var s := h / maxf(0.01, mesh.get_aabb().size.y)
			per_tree[which].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, 0, z)))
		for which in 4:
			if trees[which] and not per_tree[which].is_empty():
				var xfs: Array[Transform3D] = []
				xfs.assign(per_tree[which])
				chunk.add_child(_multimesh(trees[which], xfs, "Trees%d" % which))
		for pair in [[bush, 14, 1.2, 2.2, "Bushes"], [rock, 6, 0.8, 1.8, "Rocks"]]:
			var mesh: Mesh = pair[0]
			if mesh == null:
				continue
			var xfs: Array[Transform3D] = []
			for i in int(pair[1]):
				var side := -1.0 if i % 2 == 0 else 1.0
				var x := side * rng.randf_range(DodgeBallLogic.ROAD_HALF + 1.8, 20.0)
				var s: float = rng.randf_range(pair[2], pair[3]) / maxf(0.01, mesh.get_aabb().size.y)
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, 0, -rng.randf_range(0.0, CHUNK_LEN))))
			chunk.add_child(_multimesh(mesh, xfs, pair[4]))
		if cone and c == 1:
			var cones: Array[Transform3D] = []
			var cs := 0.7 / maxf(0.01, cone.get_aabb().size.y)
			for i in 4:
				cones.append(Transform3D(Basis().scaled(Vector3.ONE * cs), Vector3(-(DodgeBallLogic.ROAD_HALF + 0.6), 0, -10.0 - i * 2.5)))
			chunk.add_child(_multimesh(cone, cones, "Cones"))


func _build_rig() -> void:
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	camera = Camera3D.new()
	camera.position = Vector3(0, EYE_HEIGHT, 0.0)
	camera.rotation_degrees.x = CAMERA_PITCH
	camera.fov = 62.0
	camera.near = 0.08
	camera.far = 170.0
	_rig.add_child(camera)
	camera.make_current()
	# Handlebars, in the camera's frame so they stay put while the world rolls by.
	var bars := Node3D.new()
	bars.position = Vector3(0, -0.335, -0.58)
	bars.rotation_degrees.x = -CAMERA_PITCH
	camera.add_child(bars)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.4, 0.42, 0.46)
	metal.metallic = 0.6
	metal.roughness = 0.35
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.05, 0.05, 0.06)
	rubber.roughness = 0.9
	var accent := StandardMaterial3D.new()
	accent.albedo_color = Color(0.95, 0.4, 0.15)
	var bar := CylinderMesh.new()
	bar.top_radius = 0.016
	bar.bottom_radius = 0.016
	bar.height = 0.56
	bar.radial_segments = 10
	bar.rings = 1
	bars.add_child(_part(bar, metal, Vector3.ZERO, Vector3(0, 0, 90)))
	var grip := CylinderMesh.new()
	grip.top_radius = 0.021
	grip.bottom_radius = 0.021
	grip.height = 0.13
	grip.radial_segments = 10
	grip.rings = 1
	for side in [-1.0, 1.0]:
		bars.add_child(_part(grip, rubber, Vector3(side * 0.33, 0, 0), Vector3(0, 0, 90)))
		var drop := CylinderMesh.new()
		drop.top_radius = 0.014
		drop.bottom_radius = 0.014
		drop.height = 0.12
		drop.radial_segments = 8
		drop.rings = 1
		bars.add_child(_part(drop, metal, Vector3(side * 0.27, -0.05, -0.02), Vector3(25, 0, 0)))
	var stem := BoxMesh.new()
	stem.size = Vector3(0.05, 0.05, 0.16)
	bars.add_child(_part(stem, accent, Vector3(0, -0.02, 0.07), Vector3(-12, 0, 0)))
	var head := CylinderMesh.new()
	head.top_radius = 0.03
	head.bottom_radius = 0.034
	head.height = 0.3
	head.radial_segments = 10
	head.rings = 1
	bars.add_child(_part(head, accent, Vector3(0, -0.16, 0.14), Vector3(-15, 0, 0)))
	# The shield: a faint curved screen ahead of the bars.
	var shield := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.5, 0.26)
	shield.mesh = quad
	shield.position = Vector3(0, -0.42, -0.95)
	_shield_mat = ShaderMaterial.new()
	_shield_mat.shader = load("res://games/dodge_ball/shaders/shield.gdshader")
	shield.material_override = _shield_mat
	shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(shield)


func _build_balls() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS()
	sphere.height = BALL_RADIUS() * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/dodge_ball/shaders/ball.gdshader")
	sphere.material = mat
	_ball_mm = _dynamic_mm(sphere, true)
	var blob := QuadMesh.new()
	blob.size = Vector2(1.3, 1.3)
	blob.orientation = PlaneMesh.FACE_Y
	var blob_mat := ShaderMaterial.new()
	blob_mat.shader = load("res://games/dodge_ball/shaders/blob.gdshader")
	blob.material = blob_mat
	_blob_mm = _dynamic_mm(blob, false)
	var strip := QuadMesh.new()
	strip.size = Vector2(1.1, 11.0)
	strip.orientation = PlaneMesh.FACE_Y
	var warn_mat := ShaderMaterial.new()
	warn_mat.shader = load("res://games/dodge_ball/shaders/warning.gdshader")
	strip.material = warn_mat
	_warn_mm = _dynamic_mm(strip, false)
	for mm in [_warn_mm, _blob_mm, _ball_mm]:
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		# Instances move anywhere along the road: one big box keeps them from being culled.
		mmi.custom_aabb = AABB(Vector3(-20, -1, -200), Vector3(40, 10, 210))
		add_child(mmi)


func _build_fx() -> void:
	var chunk_mesh := BoxMesh.new()
	chunk_mesh.size = Vector3.ONE * 0.06
	var vc := StandardMaterial3D.new()
	vc.vertex_color_use_as_albedo = true
	vc.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	vc.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	chunk_mesh.material = vc
	for i in 3:
		var p := _particles(chunk_mesh, 24, 0.7, 3.0, 7.0)
		p.gravity = Vector3(0, -12, 0)
		p.direction = Vector3(0, 0.6, 1)
		p.spread = 70.0
		_bursts.append(p)
	var spark := SphereMesh.new()
	spark.radius = 0.04
	spark.height = 0.08
	spark.radial_segments = 6
	spark.rings = 3
	var add := StandardMaterial3D.new()
	add.vertex_color_use_as_albedo = true
	add.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	add.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.material = add
	for i in 3:
		var p := _particles(spark, 14, 0.45, 2.0, 4.0)
		p.gravity = Vector3.ZERO
		p.direction = Vector3(0, 0.3, 1)
		p.spread = 50.0
		p.color = Color(0.6, 0.95, 1.0)
		_sparks.append(p)
	var shard := PrismMesh.new()
	shard.size = Vector3(0.1, 0.14, 0.02)
	shard.material = add
	_shards = _particles(shard, 30, 0.8, 2.0, 5.0)
	_shards.gravity = Vector3(0, -6, 0)
	_shards.direction = Vector3(0, 0.4, 1)
	_shards.spread = 80.0
	_shards.color = Color(0.4, 0.85, 1.0)
	# Speed streaks: thin bright lines rushing past the edges of the view at high cadence.
	var line := BoxMesh.new()
	line.size = Vector3(0.012, 0.012, 1.4)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.vertex_color_use_as_albedo = true
	line_mat.disable_fog = true
	line.material = line_mat
	_streaks = CPUParticles3D.new()
	_streaks.mesh = line
	_streaks.amount = 40
	_streaks.lifetime = 0.5
	_streaks.local_coords = true
	_streaks.emitting = false
	# A ring around the line of sight, so the streaks rush past the edges and never cross the
	# middle of the road.
	_streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	_streaks.emission_ring_axis = Vector3(0, 0, 1)
	_streaks.emission_ring_height = 6.0
	_streaks.emission_ring_radius = 4.6
	_streaks.emission_ring_inner_radius = 3.0
	_streaks.direction = Vector3(0, 0, 1)
	_streaks.spread = 0.0
	_streaks.gravity = Vector3.ZERO
	_streaks.color = Color(1, 1, 1, 0.22)
	_streaks.position = Vector3(0, 0, -9.0)
	camera.add_child(_streaks)
	for i in 4:
		var label := Label3D.new()
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 96
		label.outline_size = 18
		label.pixel_size = 0.004
		label.no_depth_test = true
		label.visible = false
		add_child(label)
		_popups.append(label)


# --- Drawing balls ---

func _draw_balls(delta: float, logic: DodgeBallLogic) -> void:
	var n := 0
	var w := 0
	var glow := _tod.ball_glow if _tod else 0.0
	for ball in logic.balls:
		if n >= BALLS_MAX:
			break
		var catch_mode: bool = ball.get("mode", "") == "catch"
		var z := z_for_eta(ball.eta, _ball_speed.get(ball.id, -1.0))
		var x := DodgeBallLogic.ball_x(ball)
		var y := BALL_RADIUS()
		if ball.kind != "double" and int(ball.id) % 2 == 1:
			# Every other ball bounces, landing on the beat of BOUNCE_PERIOD and on the line.
			var phase: float = ball.eta / BOUNCE_PERIOD
			y += BOUNCE_HEIGHT * absf(sin(PI * phase)) * clampf(ball.eta / 0.6, 0.35, 1.0)
			var landing := int(floor(phase))
			if _bounce_phase.get(ball.id, landing) != landing and ball.eta < 1.6:
				ball_bounced.emit(clampf(1.0 - ball.eta / 1.6, 0.1, 1.0))
			_bounce_phase[ball.id] = landing
		var near := clampf(1.0 - ball.eta / 1.2, 0.0, 1.0)
		_set_ball(n, Vector3(x, y, z), ball.kind, near, glow, catch_mode)
		_blob_mm.set_instance_transform(n, Transform3D(Basis(), Vector3(x, 0.015, z)))
		_blob_mm.set_instance_custom_data(n, Color(clampf(1.2 - (y - BALL_RADIUS()) * 0.8, 0.2, 1.0), 0, 0, 0))
		n += 1
		# The warning strip in the lane where it will arrive.
		var urgency := clampf(1.0 - ball.eta / ball.eta0, 0.0, 1.0)
		_warn_mm.set_instance_transform(w, Transform3D(Basis(), Vector3(ball.x1, 0.02, RIDER_LINE_Z - 5.2)))
		_warn_mm.set_instance_custom_data(w, Color(urgency, _anim_t, 1.0 if catch_mode else 0.0, 1))
		w += 1
	var kept: Array[Dictionary] = []
	for ghost in _ghosts:
		ghost.t += delta
		ghost.z += float(ghost.v) * delta
		if ghost.t < GHOST_SEC and n < BALLS_MAX:
			_set_ball(n, Vector3(ghost.x, ghost.y, ghost.z), ghost.kind, 0.0, glow, ghost.catch)
			_blob_mm.set_instance_transform(n, Transform3D(Basis(), Vector3(ghost.x, 0.015, ghost.z)))
			_blob_mm.set_instance_custom_data(n, Color(1, 0, 0, 0))
			n += 1
			kept.append(ghost)
	_ghosts = kept
	_ball_mm.visible_instance_count = n
	_blob_mm.visible_instance_count = n
	_warn_mm.visible_instance_count = w
	if _bounce_phase.size() > 64:
		_bounce_phase.clear()
	if _ball_speed.size() > 64:
		# Balls that arrived without a ghost (hits, catches): keep only the live ones.
		var live := {}
		for ball in logic.balls:
			if _ball_speed.has(ball.id):
				live[ball.id] = _ball_speed[ball.id]
		_ball_speed = live


func _set_ball(i: int, pos: Vector3, kind: String, near: float, glow: float, catch_mode := false) -> void:
	var spin := Basis(Vector3.RIGHT, (pos.z - distance) / BALL_RADIUS())
	_ball_mm.set_instance_transform(i, Transform3D(spin, pos))
	_ball_mm.set_instance_color(i, ball_color(kind, catch_mode))
	_ball_mm.set_instance_custom_data(i, Color(near, glow, 1.0 if catch_mode else 0.0, 0))


# --- Helpers ---

## 64x64 random values; with linear filtering and repeat, sampling it is value noise for the
## road, verge and sky shaders (cheaper on the tablet than hashing per pixel).
static func _noise_texture() -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1337
	var data := PackedByteArray()
	data.resize(64 * 64)
	for i in data.size():
		data[i] = rng.randi_range(0, 255)
	var img := Image.create_from_data(64, 64, false, Image.FORMAT_L8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func BALL_RADIUS() -> float:
	return DodgeBallLogic.BALL_RADIUS


static func _model_mesh(file: String) -> Mesh:
	var scene := load(MODELS + file) as PackedScene
	if scene == null:
		push_warning("DodgeWorld: can't load %s" % file)
		return null
	var root := scene.instantiate()
	var found: Mesh = null
	var stack: Array[Node] = [root]
	while not stack.is_empty() and found == null:
		var node: Node = stack.pop_back()
		if node is MeshInstance3D:
			found = (node as MeshInstance3D).mesh
		stack.append_array(node.get_children())
	root.free()
	return found


## A copy of a nature-kit mesh in this road's palette: leaves (the greener surfaces) in
## `leaf`, the rest (trunks) in `bark`. The kit's materials are fully metallic, which renders
## near-black without reflections, so they become plain matte ones lit per vertex.
static func _recolor(mesh: Mesh, leaf: Color, bark := Color(0.42, 0.29, 0.19)) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s) as StandardMaterial3D
		if mat == null:
			continue
		var m := mat.duplicate() as StandardMaterial3D
		var c := mat.albedo_color
		m.albedo_color = leaf if c.g > c.r else bark
		m.metallic = 0.0
		m.roughness = 0.95
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		copy.surface_set_material(s, m)
	return copy


## A copy of a model mesh lit per vertex, without specular: flat-shaded low-poly models look
## the same, and the tablet's GPU does a fraction of the work.
static func _cheap(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var mat := copy.surface_get_material(s) as BaseMaterial3D
		if mat == null:
			continue
		var m := mat.duplicate() as BaseMaterial3D
		m.metallic = 0.0
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
		copy.surface_set_material(s, m)
	return copy


static func _multimesh(mesh: Mesh, transforms: Array[Transform3D], node_name: String) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


func _dynamic_mm(mesh: Mesh, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = BALLS_MAX
	mm.visible_instance_count = 0
	return mm


static func _part(mesh: Mesh, mat: Material, pos: Vector3, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


func _particles(mesh: Mesh, amount: int, lifetime: float, v_min: float, v_max: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.mesh = mesh
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 1.0
	p.initial_velocity_min = v_min
	p.initial_velocity_max = v_max
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.3
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = fade
	p.local_coords = false
	add_child(p)
	return p
