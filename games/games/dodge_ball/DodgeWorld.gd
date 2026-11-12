class_name DodgeWorld
extends Node3D
## Dodge Ball's 3D view (#39): the road seen from the bike. It only draws `DodgeBallLogic`; the
## game scene (`DodgeBall.gd`) feeds it each frame. Built in code for GL Compatibility on the
## Gen 2 tablet (PowerVR GX6250), so every choice here is about draw calls and fill rate:
##
##   - One hand light (framework/shaders/world_look.gdshaderinc, Dodge's grade in
##     shaders/look.gdshaderinc): the road, verges, scenery, horizon, sky and handlebars are
##     unshaded and light, haze and grade themselves from one look (`set_time_of_day`). Night
##     lighting (headlight, street lamps) is added light in the shaders, not real lights (each
##     is an extra pass in Compatibility). Only the balls take the engine sun.
##   - The road and verges are single planes whose shaders scroll with distance travelled; a
##     far ring of hills and a tree line (one mesh) closes the view.
##   - Scenery comes in three 50 m chunks that leapfrog forward as they pass the bike, each a few
##     MultiMeshes (one draw call per model per chunk), so nothing moves per instance.
##   - Balls, their shadows and their warnings are three MultiMeshes, updated per frame.
##   - Bursts and sparks are one pooled MultiMesh of streaks moved by its vertex shader;
##     popups are pooled Label3D; screen effects are one canvas shader.
##
## Comfort on a stationary bike: the view only moves sideways with the rider's own lean, rolls
## a few degrees at most (and not at all when the rider turns it off), and the hit shake is a
## small, brief sideways nudge with no rotation.

const DodgeTimeOfDayRes := preload("res://framework/TimeOfDay.gd")

const RIDER_LINE_Z := -1.4  ## where balls reach the bike (just ahead of the camera)
const POPUP_INK := Color("0e1b3d")  ## the floating points' outline: Dodge Ball's ink (DodgeStatus.look)
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
const BARK := Color(0.42, 0.29, 0.19)
const TREE_SWAY := 0.0016  ## m of sway per m² of height (a 7 m tree's crown moves about 8 cm)
const BUSH_SWAY := 0.012
const FENCE_OFFSET := 4.5  ## m from the kerb to the fence line
const FENCE_SPACING := 3.125  ## m between posts; the fence's scroll wraps at this
const FENCE_LEN := 175.0  ## m of fence ahead of the bike (past the far plane, 170)
const FX_POOL := 64  ## streaks and chunks alive at once (a hit writes 24; ART_BIBLE §9)
const HORIZON_HILLS := 155.0  ## m to the hills (inside the far plane, 170)
const HORIZON_TREES := 125.0  ## m to the distant tree line

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

const MODELS := "res://assets/models/"

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
var _scenery_mats := {}  ## the hand-lit scenery materials by surface colour, shared by every chunk
var _horizon: MeshInstance3D
var _fence: MeshInstance3D
var _fx_until := 0.0  ## _anim_t when the last live FX instance dies (the pool is hidden after)
var _bars_mat: ShaderMaterial
var _blob_mats: Array[ShaderMaterial] = []
var _fx_mm: MultiMesh
var _fx_mat: ShaderMaterial
var _fx_mmi: MultiMeshInstance3D
var _fx_next := 0
var _fx_rng := RandomNumberGenerator.new()
var _shards: CPUParticles3D
var _popups: Array[Label3D] = []
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
var _tod: TimeOfDay
var _noise: ImageTexture


func _ready() -> void:
	_noise = _noise_texture()
	_build_environment()
	_build_road()
	_build_horizon()
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
	_fence.visible = tuning.get("scenery", true)
	_horizon.visible = tuning.get("scenery", true)
	for node in get_children():
		if node is MeshInstance3D and node.material_override == _verge_mat:
			node.visible = tuning.get("verges", true)
		if node is MeshInstance3D and node.material_override == _road_mat:
			node.visible = tuning.get("road", true)
		if node is MultiMeshInstance3D and node != _fx_mmi:
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
	_fence.position.z = fmod(distance, FENCE_SPACING)

	_rig.position.x = logic.rider_x
	# The horizon keeps its distance: it follows the rider sideways and never scrolls.
	_horizon.position.x = logic.rider_x
	_fx_mat.set_shader_parameter("now", _anim_t)
	_fx_mmi.visible = _anim_t < _fx_until
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


func set_time_of_day(tod: TimeOfDay) -> void:
	_tod = tod
	var env := _env.environment
	_sky_mat.set_shader_parameter("top_color", tod.sky_top)
	_sky_mat.set_shader_parameter("horizon_color", tod.sky_horizon)
	_sky_mat.set_shader_parameter("below_color", tod.sky_ground)
	_sky_mat.set_shader_parameter("disc_color", tod.sun_color)
	_sky_mat.set_shader_parameter("sun_size", tod.sun_size)
	_sky_mat.set_shader_parameter("halo", tod.halo)
	_sky_mat.set_shader_parameter("stars", tod.stars)
	_sky_mat.set_shader_parameter("clouds", tod.clouds)
	_sky_mat.set_shader_parameter("cloud_color", tod.cloud_color)
	_sky_mat.set_shader_parameter("cloud_shade", tod.cloud_color.lerp(tod.sky_top, 0.45) * 0.82)
	var to_sun := WorldLook.sun_dir(tod.sun_elevation, tod.sun_azimuth)
	# The engine sun now lights only the balls (and places the sky's disc).
	_sun.basis = Basis.looking_at(-to_sun, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.FORWARD)
	_sun.light_color = tod.sun_color
	_sun.light_energy = tod.sun_energy
	env.ambient_light_color = tod.ambient
	env.ambient_light_energy = tod.ambient_energy
	env.fog_light_color = tod.fog_color
	env.fog_density = tod.fog_density
	WorldLook.apply(look_materials(), look_for(tod, tuning.get("fog", true)))
	_road_mat.set_shader_parameter("headlight", tod.headlight)
	_road_mat.set_shader_parameter("lamp_glow", tod.lamp_glow)
	for mat in _scenery_mats.values():
		mat.set_shader_parameter("lamp_glow", tod.lamp_glow)
	_halo_mat.albedo_color = Color(1.0, 0.8, 0.5, clampf(tod.lamp_glow, 0.0, 1.0))
	for chunk in _chunks:
		chunk.get_node("Halos").visible = tod.lamp_glow > 0.05
	if not tuning.get("fog", true):
		env.fog_enabled = false


## The shared light (`WorldLook`) for a time of day: the sun at its place and strength, the
## ambient as the sky's half of the hemisphere (the ground's a darker share of it), the fog as
## the haze. Energies scale the colours in linear light, as the engine's lights did (the
## uniforms are `source_color`, so they're handed over in sRGB).
static func look_for(tod: TimeOfDay, fog := true) -> Dictionary:
	var ambient := tod.ambient.srgb_to_linear() * tod.ambient_energy
	return {
		"sun_dir": WorldLook.sun_dir(tod.sun_elevation, tod.sun_azimuth),
		"sun_color": _to_srgb(tod.sun_color.srgb_to_linear() * tod.sun_energy),
		"sky_color": _to_srgb(ambient),
		"ground_color": _to_srgb(ambient * 0.7),
		"haze_color": tod.fog_color,
		"haze_density": tod.fog_density if fog else 0.0,
		"haze_max": 0.9 if tod.id == "day" else 0.93,
	}


static func _to_srgb(linear: Color) -> Color:
	var c := linear.linear_to_srgb()
	c.a = 1.0
	return c


## Every material that lights itself with the shared look.
func look_materials() -> Array:
	var mats: Array = [_road_mat, _verge_mat, _sky_mat, _bars_mat, _horizon.material_override]
	mats.append_array(_scenery_mats.values())
	mats.append_array(_blob_mats)
	return mats


# --- Feedback ---

## A hit: the ball bursts at `x`, the screen nudges sideways.
func hit_fx(x: float, kind: String, catch_mode := false, shake := 1.0) -> void:
	# A little ahead of the bars, so the burst reads as the ball breaking up, not as debris in
	# the rider's face: chunks of the ball tumble out sideways and fall, hot streaks fly off.
	var at := Vector3(x, 0.5, RIDER_LINE_Z - 2.0)
	var col := ball_color(kind, catch_mode)
	burst(at, col, 16, 3.0, 7.0, -12.0, 0.7, 0.09, true)
	burst(at, col.lightened(0.35), 8, 4.0, 8.0, -6.0, 0.35, 0.05, false)
	_shake = shake


## Catch: a caught ball bursts into gold sparks at the bike, and the points float up.
func catch_fx(ball: Dictionary, points: float, bonus: bool) -> void:
	burst(Vector3(ball.x1, 0.7, RIDER_LINE_Z - 1.0), Color(1.0, 0.85, 0.3), 18, 2.0, 4.5, -3.0, 0.45, 0.045, false)
	_shield_flash = maxf(_shield_flash, 0.35)
	_popup(ball.x1, points, bonus, GameTheme.TARGET if bonus else Color.WHITE)


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
	burst(Vector3(ball.x1, 0.5, RIDER_LINE_Z), Color(0.6, 0.95, 1.0), 14, 2.0, 4.0, 0.0, 0.45, 0.04, false)
	_ghost(ball)
	_popup(ball.x1, points, bonus, GameTheme.TARGET if bonus else Color.WHITE)


## Writes `count` streaks (or tumbling `chunks`) into the pooled FX MultiMesh, starting now at
## `at`: speeds between `v_min` and `v_max`, out sideways and up and never at the rider, under
## `gravity` (m/s², on y), living `life` seconds, `size` m. Written once; the vertex shader
## (shaders/fx.gdshader) moves them, so nothing runs per frame after.
func burst(at: Vector3, color: Color, count: int, v_min: float, v_max: float, gravity: float,
		life: float, size: float, chunks: bool) -> void:
	for i in count:
		_fx_mm.set_instance_transform(_fx_next, fx_instance(_fx_rng, at, v_min, v_max, gravity, life, size, chunks))
		_fx_mm.set_instance_color(_fx_next, color)
		_fx_mm.set_instance_custom_data(_fx_next, Color(_anim_t, 0, 0, 0))
		_fx_next = (_fx_next + 1) % FX_POOL
	_fx_until = maxf(_fx_until, _anim_t + life + 0.05)
	_fx_mmi.visible = true


## One FX instance's data, packed in its transform as shaders/fx.gdshader reads it: the origin,
## the velocity (basis x), (gravity, life, size) (basis y) and (kind, seed) (basis z).
static func fx_instance(rng: RandomNumberGenerator, at: Vector3, v_min: float, v_max: float,
		gravity: float, life: float, size: float, chunks: bool) -> Transform3D:
	var speed := rng.randf_range(v_min, v_max)
	var dir := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.25, 1.0), rng.randf_range(-0.7, 0.35)).normalized()
	if dir.z > 0.3:
		# At most 17° toward the rider: debris never flies at the face (ART_BIBLE §7).
		var rest := Vector2(dir.x, dir.y).normalized() * sqrt(1.0 - 0.09)
		dir = Vector3(rest.x, rest.y, 0.3)
	var data := Basis(dir * speed, Vector3(gravity, life * rng.randf_range(0.75, 1.0), size * rng.randf_range(0.7, 1.3)),
		Vector3(1.0 if chunks else 0.0, rng.randf(), 0.0))
	return Transform3D(data, at)


func _ghost(ball: Dictionary) -> void:
	_ghosts.append({"x": ball.x1, "z": RIDER_LINE_Z, "kind": ball.kind, "t": 0.0, "y": BALL_RADIUS(),
		"v": _ball_speed.get(ball.id, approach_speed()), "catch": ball.get("mode", "") == "catch"})
	_ball_speed.erase(ball.id)


## Points lost to a hit with the shield down, floating up in red where the ball struck.
func penalty_fx(x: float, points: float) -> void:
	_popup(x, -points, false, GameTheme.DANGER)


func _popup(x_at: float, points: float, _bonus: bool, color: Color) -> void:
	if is_zero_approx(points):
		return
	var label := _popups[_next_popup]
	_next_popup = (_next_popup + 1) % _popups.size()
	label.text = ("+%d" if points > 0.0 else "−%d") % roundi(absf(points))
	label.modulate = color
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
	var ahead := Vector3(_rig.position.x, 1.0, RIDER_LINE_Z - 6.0)
	burst(ahead, Color(1, 1, 1), 2, 1.0, 2.0, -6.0, 0.3, 0.05, true)
	burst(ahead, Color(1, 1, 1), 2, 1.0, 2.0, 0.0, 0.3, 0.05, false)
	_shards.position = ahead
	_shards.restart()
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


## The far edge of the world: a ring of low rolling hills and, in front of it, a distant tree
## line, both one vertex-coloured mesh on the scenery shader, hazed nearly to the haze's cap so
## they read as far away. It follows the rider sideways only (`update_view`), never the scroll.
func _build_horizon() -> void:
	_horizon = MeshInstance3D.new()
	_horizon.name = "Horizon"
	_horizon.mesh = horizon_mesh()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/dodge_ball/shaders/scenery.gdshader")
	mat.set_shader_parameter("use_vertex_color", true)
	mat.set_shader_parameter("haze_scale", 2.5)
	mat.set_shader_parameter("ao_height", 0.001)
	_horizon.material_override = mat
	_horizon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_horizon)


## The horizon's mesh: an arc ahead (±85° of straight ahead) of hills 6-14 m high at
## HORIZON_HILLS, and chunky tree crowns 4-9 m high at HORIZON_TREES. Both reach 8 m below the
## ground, so no gap shows under them past the verges' far edges.
static func horizon_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	_arc(st, HORIZON_HILLS, 96, func(a: float) -> float:
		return 10.0 + 2.6 * sin(a * 3.1 + 0.6) + 1.4 * sin(a * 7.3 + 2.0),
		Color(0.36, 0.52, 0.3), Color(0.24, 0.36, 0.22))
	_arc(st, HORIZON_TREES, 220, func(a: float) -> float:
		var lump := absf(sin(a * 37.0)) * 0.6 + absf(sin(a * 91.0 + 1.3)) * 0.4
		return 4.5 + 3.5 * lump + 1.0 * sin(a * 5.0),
		Color(0.2, 0.36, 0.2), Color(0.14, 0.26, 0.15))
	return st.commit()


static func _arc(st: SurfaceTool, radius: float, segments: int, height: Callable, top: Color, foot: Color) -> void:
	var span := deg_to_rad(85.0)
	for i in segments:
		var a0 := lerpf(-span, span, float(i) / segments)
		var a1 := lerpf(-span, span, float(i + 1) / segments)
		var p0 := Vector3(sin(a0), 0, -cos(a0)) * radius
		var p1 := Vector3(sin(a1), 0, -cos(a1)) * radius
		var corners := [p0 + Vector3(0, -8, 0), p1 + Vector3(0, -8, 0),
			p1 + Vector3(0, float(height.call(a1)), 0), p0 + Vector3(0, float(height.call(a0)), 0)]
		var colours := [foot, foot, top, top]
		# Clockwise seen from the rider (Godot's front faces).
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(colours[k])
			st.add_vertex(corners[k])


## Each chunk: lamps both sides (staggered), trees, bushes and rocks, a few cones on the kerb, a
## post-and-rail fence each side, and a painted contact disc under everything that stands.
func _build_scenery() -> void:
	var lamp := _hand_lit(_glow_tip(_model_mesh("light-curved.glb")), _scenery_mats)
	var trees := [_hand_lit(_model_mesh("tree_default.glb"), _scenery_mats, Color(0.32, 0.56, 0.2), BARK, TREE_SWAY),
		_hand_lit(_model_mesh("tree_oak.glb"), _scenery_mats, Color(0.26, 0.48, 0.17), BARK, TREE_SWAY),
		_hand_lit(_model_mesh("tree_pineTallA.glb"), _scenery_mats, Color(0.16, 0.36, 0.2), BARK, TREE_SWAY),
		_hand_lit(_model_mesh("tree_cone.glb"), _scenery_mats, Color(0.38, 0.6, 0.22), BARK, TREE_SWAY)]
	var bush := _hand_lit(_model_mesh("plant_bushLarge.glb"), _scenery_mats, Color(0.3, 0.52, 0.2), BARK, BUSH_SWAY)
	# Rocks: a lighter top over a darker foot (the painted AO over their whole height).
	var rock := _hand_lit(_model_mesh("rock_largeA.glb"), _scenery_mats, Color(0.56, 0.56, 0.53),
		Color(0.46, 0.45, 0.43), 0.0, 0.9)
	var cone := _hand_lit(_model_mesh("construction-cone.glb"), _scenery_mats)
	# One fence for the whole road (a draw call, not one a chunk): it scrolls like the chunks and
	# steps back a post spacing as it passes, which can't be seen.
	_fence = MeshInstance3D.new()
	_fence.name = "Fence"
	_fence.mesh = fence_mesh()
	_fence.material_override = _scenery_material(_scenery_mats, Color(1, 1, 1), null, 0.0, 1.0, false, true)
	_fence.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_fence)
	var disc := QuadMesh.new()
	disc.size = Vector2.ONE
	disc.orientation = PlaneMesh.FACE_Y
	var disc_mat := ShaderMaterial.new()
	disc_mat.shader = load("res://games/dodge_ball/shaders/blob.gdshader")
	disc_mat.set_shader_parameter("core", 0.3)
	disc_mat.set_shader_parameter("darkness", 1.0)
	disc_mat.set_shader_parameter("strength", 0.42)
	disc.material = disc_mat
	_blob_mats.append(disc_mat)
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
		var discs: Array[Transform3D] = []
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
				discs.append(_disc(Vector3(side * lamp_x, 0, z), 0.7))
		if lamp:
			chunk.add_child(_multimesh(lamp, lamp_xf, "Lamps"))
		var halos := _multimesh(halo_quad, halo_xf, "Halos")
		chunk.add_child(halos)

		var per_tree: Array[Array] = []
		for t in 4:
			per_tree.append([] as Array[Transform3D])
		for i in 26:
			var side := -1.0 if i % 2 == 0 else 1.0
			var x := side * clear_of_fence(rng.randf_range(DodgeBallLogic.ROAD_HALF + 3.5, 32.0))
			var z := -rng.randf_range(0.0, CHUNK_LEN)
			var which := rng.randi_range(0, 3)
			var mesh: Mesh = trees[which]
			if mesh == null:
				continue
			var h := rng.randf_range(5.0, 9.0) * (1.3 if which == 2 else 1.0)
			var s := h / maxf(0.01, mesh.get_aabb().size.y)
			per_tree[which].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, 0, z)))
			discs.append(_disc(Vector3(x, 0, z), maxf(mesh.get_aabb().size.x, mesh.get_aabb().size.z) * s * 0.75))
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
				var x := side * clear_of_fence(rng.randf_range(DodgeBallLogic.ROAD_HALF + 1.8, 20.0))
				var s: float = rng.randf_range(pair[2], pair[3]) / maxf(0.01, mesh.get_aabb().size.y)
				var at := Vector3(x, 0, -rng.randf_range(0.0, CHUNK_LEN))
				xfs.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), at))
				discs.append(_disc(at, maxf(mesh.get_aabb().size.x, mesh.get_aabb().size.z) * s * 1.1))
			chunk.add_child(_multimesh(mesh, xfs, pair[4]))
		if cone and c == 1:
			var cones: Array[Transform3D] = []
			var cs := 0.7 / maxf(0.01, cone.get_aabb().size.y)
			for i in 4:
				cones.append(Transform3D(Basis().scaled(Vector3.ONE * cs), Vector3(-(DodgeBallLogic.ROAD_HALF + 0.6), 0, -10.0 - i * 2.5)))
			chunk.add_child(_multimesh(cone, cones, "Cones"))
		var disc_mmi := _multimesh(disc, discs, "Discs")
		chunk.add_child(disc_mmi)


## An |x| for scenery that keeps it at least 1.2 m off the fence line (pushed outwards).
static func clear_of_fence(ax: float) -> float:
	var line := DodgeBallLogic.ROAD_HALF + FENCE_OFFSET
	return ax + 2.4 if absf(ax - line) < 1.2 else ax


## A contact disc's transform: `diameter` m across, flat on the ground just above the verge.
static func _disc(at: Vector3, diameter: float) -> Transform3D:
	return Transform3D(Basis().scaled(Vector3(diameter, 1.0, diameter)), Vector3(at.x, 0.03, at.z))


## The fence (both sides, from just behind the bike to FENCE_LEN ahead): weathered posts every
## FENCE_SPACING and two rails, vertex-coloured, about 1.2k triangles.
static func fence_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var post := Color(0.62, 0.53, 0.41)
	var rail := Color(0.78, 0.7, 0.57)
	var x := DodgeBallLogic.ROAD_HALF + FENCE_OFFSET
	var posts := int(FENCE_LEN / FENCE_SPACING) + 2
	var start := FENCE_SPACING * 2.0
	for side in [-1.0, 1.0]:
		for i in posts:
			_box(st, Vector3(side * x, 0.45, start - i * FENCE_SPACING), Vector3(0.12, 0.9, 0.12), post)
		for y in [0.42, 0.78]:
			var length := posts * FENCE_SPACING
			_box(st, Vector3(side * (x - 0.07), y, start - length * 0.5), Vector3(0.05, 0.1, length), rail)
	return st.commit()


## A box without its bottom face (10 triangles) into `st`.
static func _box(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size * 0.5
	var faces := [[Vector3.UP, Vector3.RIGHT, Vector3.BACK], [Vector3.RIGHT, Vector3.BACK, Vector3.UP],
		[Vector3.LEFT, Vector3.FORWARD, Vector3.UP], [Vector3.BACK, Vector3.LEFT, Vector3.UP],
		[Vector3.FORWARD, Vector3.RIGHT, Vector3.UP]]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var c := centre + n * h
		var du := u * h
		var dv := v * h
		var quad := [c - du - dv, c + du - dv, c + du + dv, c - du + dv]
		# Wind each face to face out along n (counter-clockwise seen from outside, Godot's front).
		var order := [0, 2, 1, 0, 3, 2] if u.cross(v).dot(n) > 0.0 else [0, 1, 2, 0, 2, 3]
		st.set_color(color)
		st.set_normal(n)
		for k in order:
			st.add_vertex(quad[k])


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
	# Handlebars, in the camera's frame so they stay put while the world rolls by: bar, grips,
	# drops, stem and head merged into one vertex-coloured mesh, hand-lit (shaders/bars.gdshader).
	# Vertex alpha is the metal's sheen.
	var bars := MeshInstance3D.new()
	bars.name = "Bars"
	bars.position = Vector3(0, -0.335, -0.58)
	bars.rotation_degrees.x = -CAMERA_PITCH
	bars.mesh = handlebar_mesh()
	_bars_mat = ShaderMaterial.new()
	_bars_mat.shader = load("res://games/dodge_ball/shaders/bars.gdshader")
	bars.material_override = _bars_mat
	bars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	camera.add_child(bars)
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


## The handlebars as one mesh: the parts the bars were built from (7 draw calls before), each
## vertex-coloured. Metal is a cool grey with sheen (alpha 1), the grips matte rubber, the stem
## and head the accent #F26626.
static func handlebar_mesh() -> ArrayMesh:
	var metal := Color(0.42, 0.44, 0.49, 1.0)
	var rubber := Color(0.06, 0.06, 0.07, 0.0)
	var accent := Color("f26626", 0.35)
	var parts := []
	parts.append([_cylinder(0.016, 0.016, 0.56, 10), metal, Vector3.ZERO, Vector3(0, 0, 90)])
	for side in [-1.0, 1.0]:
		parts.append([_cylinder(0.021, 0.021, 0.13, 10), rubber, Vector3(side * 0.33, 0, 0), Vector3(0, 0, 90)])
		parts.append([_cylinder(0.014, 0.014, 0.12, 8), metal, Vector3(side * 0.27, -0.05, -0.02), Vector3(25, 0, 0)])
	var stem := BoxMesh.new()
	stem.size = Vector3(0.05, 0.05, 0.16)
	parts.append([stem, accent, Vector3(0, -0.02, 0.07), Vector3(-12, 0, 0)])
	parts.append([_cylinder(0.03, 0.034, 0.3, 10), accent, Vector3(0, -0.16, 0.14), Vector3(-15, 0, 0)])
	return _merged(parts)


static func _cylinder(top: float, bottom: float, height: float, segments: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c


## Bakes `parts` ([mesh, colour, position, rotation in degrees], placed as a child node would
## be) into one vertex-coloured ArrayMesh.
static func _merged(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var mesh: Mesh = part[0]
		var xf := Transform3D(Basis.from_euler((part[3] as Vector3) * (PI / 180.0)), part[2])
		var arrays := mesh.surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		for i in indices:
			st.set_color(part[1])
			st.set_normal((xf.basis * normals[i]).normalized())
			st.add_vertex(xf * verts[i])
	st.index()
	return st.commit()


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
	_blob_mats.append(blob_mat)
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
	# Bursts and sparks: one pooled MultiMesh of quads, moved by shaders/fx.gdshader.
	_fx_rng.seed = 4242
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_fx_mat = ShaderMaterial.new()
	_fx_mat.shader = load("res://games/dodge_ball/shaders/fx.gdshader")
	quad.material = _fx_mat
	_fx_mm = MultiMesh.new()
	_fx_mm.transform_format = MultiMesh.TRANSFORM_3D
	_fx_mm.use_colors = true
	_fx_mm.use_custom_data = true
	_fx_mm.mesh = quad
	_fx_mm.instance_count = FX_POOL
	for i in FX_POOL:
		# Born long ago: every slot starts dead.
		_fx_mm.set_instance_transform(i, Transform3D(Basis(Vector3.ZERO, Vector3(0, 0.1, 0), Vector3.ZERO), Vector3.ZERO))
		_fx_mm.set_instance_custom_data(i, Color(-1000.0, 0, 0, 0))
	_fx_mmi = MultiMeshInstance3D.new()
	_fx_mmi.name = "Fx"
	_fx_mmi.multimesh = _fx_mm
	_fx_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The shader places the instances: one box round the near road keeps them from being culled.
	_fx_mmi.custom_aabb = AABB(Vector3(-20, -2, -40), Vector3(40, 14, 44))
	# Hidden while nothing is alive (a burst shows it), so an idle pool costs no draw call.
	_fx_mmi.visible = false
	add_child(_fx_mmi)
	var add := StandardMaterial3D.new()
	add.vertex_color_use_as_albedo = true
	add.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	add.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
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
		# The shared display face with the game's navy ink (framework/ui/UI_STYLE.md).
		label.font = GameTheme.display_font()
		label.font_size = 96
		label.outline_size = 18
		label.outline_modulate = POPUP_INK
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
		var bouncing: bool = ball.kind != "double" and int(ball.id) % 2 == 1
		if bouncing:
			# Every other ball bounces, landing on the beat of BOUNCE_PERIOD and on the line.
			var phase: float = ball.eta / BOUNCE_PERIOD
			y += BOUNCE_HEIGHT * absf(sin(PI * phase)) * clampf(ball.eta / 0.6, 0.35, 1.0)
			var landing := int(floor(phase))
			if _bounce_phase.get(ball.id, landing) != landing and ball.eta < 1.6:
				ball_bounced.emit(clampf(1.0 - ball.eta / 1.6, 0.1, 1.0))
			_bounce_phase[ball.id] = landing
		var near := clampf(1.0 - ball.eta / 1.2, 0.0, 1.0)
		var lift := y - BALL_RADIUS()
		_set_ball(n, Vector3(x, y, z), ball.kind, near, glow, catch_mode, squash_for(lift) if bouncing else 0.0)
		# The shadow tightens and darkens as a bouncing ball comes down, so its height reads.
		_blob_mm.set_instance_transform(n, Transform3D(Basis().scaled(Vector3.ONE * shadow_scale(lift)), Vector3(x, 0.015, z)))
		_blob_mm.set_instance_custom_data(n, Color(clampf(1.2 - lift * 0.8, 0.2, 1.0), 0, 0, 0))
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


func _set_ball(i: int, pos: Vector3, kind: String, near: float, glow: float, catch_mode := false, squash := 0.0) -> void:
	var spin := Basis(Vector3.RIGHT, (pos.z - distance) / BALL_RADIUS())
	# A faint squash as a bouncing ball lands: in world axes, over the spin, sitting on the road.
	var squashed := Basis.from_scale(Vector3(1.0 + squash * 0.5, 1.0 - squash, 1.0 + squash * 0.5)) * spin
	_ball_mm.set_instance_transform(i, Transform3D(squashed, pos - Vector3(0, squash * BALL_RADIUS(), 0)))
	_ball_mm.set_instance_color(i, ball_color(kind, catch_mode))
	_ball_mm.set_instance_custom_data(i, Color(near, glow, 1.0 if catch_mode else 0.0, 0))


## How much a ball `lift` m off the road squashes (0-0.14): only in its last 8 cm down.
static func squash_for(lift: float) -> float:
	return 0.14 * clampf(1.0 - lift / 0.08, 0.0, 1.0)


## The ball shadow's scale for a ball `lift` m up: tight at the road, wider in the air.
static func shadow_scale(lift: float) -> float:
	return lerpf(0.85, 1.3, clampf(lift / BOUNCE_HEIGHT, 0.0, 1.0))


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
	return MeshKit3D.model_mesh(file)


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


## A copy of a model mesh on the hand-lit scenery shader (shaders/scenery.gdshader), one
## material per surface colour from `cache`, so every chunk shares them. With `leaf`, the greener
## surfaces take `leaf` and sway by `sway`, the rest `bark` (as `_recolor` picks them); without,
## each surface keeps its colour and texture (the city kit's palette map). A mesh carrying vertex
## colours marks its self-lit part in their alpha (`_glow_tip`). `_recolor` and `_cheap` stay as
## they were for Tug of War, which builds its own look.
static func _hand_lit(mesh: Mesh, cache: Dictionary, leaf: Variant = null, bark := BARK, sway := 0.0,
		ao_height := 1.5) -> Mesh:
	if mesh == null:
		return null
	var copy := mesh.duplicate() as Mesh
	for s in copy.get_surface_count():
		var src := copy.surface_get_material(s) as BaseMaterial3D
		var c := src.albedo_color if src else Color.WHITE
		var tex: Texture2D = src.albedo_texture if src else null
		var is_leaf := leaf != null and c.g > c.r
		var colour: Color = (leaf if is_leaf else bark) if leaf != null else c
		var glow: bool = (copy.surface_get_format(s) & Mesh.ARRAY_FORMAT_COLOR) != 0
		copy.surface_set_material(s, _scenery_material(cache, colour, tex, sway if is_leaf else 0.0,
			ao_height, glow, false))
	return copy


## The shared scenery material for one look of surface, made once per `cache`.
static func _scenery_material(cache: Dictionary, colour: Color, tex: Texture2D, sway: float,
		ao_height: float, glow: bool, vertex_color: bool) -> ShaderMaterial:
	var key := "%s|%s|%.4f|%.2f|%s|%s" % [colour.to_html(), tex.resource_path if tex else "",
		sway, ao_height, glow, vertex_color]
	if cache.has(key):
		return cache[key]
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/dodge_ball/shaders/scenery.gdshader")
	mat.set_shader_parameter("albedo", colour)
	if tex:
		mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("sway", sway)
	mat.set_shader_parameter("ao_height", ao_height)
	mat.set_shader_parameter("glow_mask", glow)
	mat.set_shader_parameter("use_vertex_color", vertex_color)
	cache[key] = mat
	return mat


## The street lamp with its head marked self-lit: vertex alpha 1 on the lamp at the arm's tip
## (the top 7 cm of the model, its last 6 cm along the arm), 0 elsewhere.
static func _glow_tip(mesh: Mesh) -> Mesh:
	if mesh == null:
		return null
	var aabb := mesh.get_aabb()
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colours := PackedColorArray()
		colours.resize(verts.size())
		for i in verts.size():
			var v := verts[i]
			var tip := v.y > aabb.end.y - 0.07 and v.z < aabb.position.z + 0.06
			colours[i] = Color(1, 1, 1, 1.0 if tip else 0.0)
		arrays[Mesh.ARRAY_COLOR] = colours
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out


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
