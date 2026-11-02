class_name WattLaneWorld
extends Node3D
## Watt Lane's 3D view (#78; ART_BIBLE.md): first person from a light-bike on a night highway.
## The road is a watt scale (`x_of`): your smoothed power is your place across it, and the lane's
## two light rails bend ahead of you along the course's future, `SPEED` metres a second, so a jump
## is seen coming as an S-bend with amber chevrons leading into it.
##
## It only draws: `WattLaneLogic` holds the rules. The tablet recipe (docs/GAMES.md): every surface
## unshaded with the grade folded in (`shaders/wl_look.gdshaderinc`), no engine lights, fog or post
## passes, five draws (sky card, road, rails, lamp posts as one MultiMesh, the bike's nose), and per
## frame only uniforms: the lane's 64 offsets, the scroll and a few states.

const SPEED := 14.0  ## metres a second: course time ahead maps to distance ahead
const ROWS := 64
const ROW_LEN := 2.2  ## metres between the lane's rows: 139 m, about 10 s, ahead
const M_PER_FTP := 24.0  ## metres across the road per FTP of watts
const CENTRE_SHARE := 0.575  ## the share of FTP at the road's centre line
const ROAD_HALF := 10.2  ## the road's edges: 15% and 100% of FTP
const SHOULDER := 1.4  ## how far past an edge the bike can go
const EYE_Y := 1.5
const PITCH := -8.0
const FOV := 66.0
const RAIL_HEIGHT := 0.55
const RAIL_CORE := 0.08  ## half-width of the rail's core on the road
const LAMP_SPACING := 40.0
const LAMP_X := 12.0
const LAMPS_PER_SIDE := 6
const SKY_Z := -195.0
const SKY_SIZE := Vector2(760.0, 230.0)
const HORIZON_V := 0.86
const BACKGROUND := Color(0.01, 0.025, 0.035)
const HAZE := {"haze_color": Color(0.05, 0.2, 0.21), "haze_density": 0.011, "haze_max": 0.92}
const BIKE_EASE := 8.0  ## per second: the bike's ease to its place (visual only)

var camera: Camera3D
var ftp := 150.0
var lane_width := 40  ## watts
var bike_x := 0.0  ## metres
var flash := 0.0  ## 0-1, set to 1 on a catch
## The showcase view (the hub card and the intro picture): the camera behind and above the bike,
## which rides at full size with its light trail on the road behind it.
var chase := false

var _road_mat: ShaderMaterial
var _rail_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _post_mat: ShaderMaterial
var _bike_mat: ShaderMaterial
var _bike: MeshInstance3D
var _offsets := PackedFloat32Array()
var _scroll := 0.0
var _clock := 0.0
var _glow := 1.0
var _warn := 0.0
var _roll := 0.0
var _placed := false


func _ready() -> void:
	_offsets.resize(ROWS)
	_build_environment()
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.fov = FOV
	camera.near = 0.1
	camera.far = 260.0
	camera.position = Vector3(0.0, EYE_Y, 0.0)
	camera.rotation_degrees = Vector3(PITCH, 0.0, 0.0)
	add_child(camera)
	_road_mat = _material("road")
	_rail_mat = _material("rails")
	_sky_mat = _material("sky")
	_post_mat = _material("posts")
	_bike_mat = _material("bike")
	_build_sky()
	_build_road()
	_build_rails()
	_build_posts()
	_build_bike()
	var noise := WorldLook.noise_texture()
	WorldLook.apply(_opaque_materials(), HAZE.merged({"noise_tex": noise}))
	WorldLook.apply([_rail_mat], {"noise_tex": noise, "haze_color": Color.BLACK,
		"haze_density": HAZE.haze_density, "haze_max": 1.0})
	for mat in [_road_mat, _rail_mat]:
		mat.set_shader_parameter("row_len", ROW_LEN)
	for mat in [_road_mat, _post_mat]:
		mat.set_shader_parameter("lamp_spacing" if mat == _road_mat else "spacing", LAMP_SPACING)
	_road_mat.set_shader_parameter("road_half", ROAD_HALF)
	_road_mat.set_shader_parameter("scale_lines", Vector4(x_of_share(0.25), x_of_share(0.5), x_of_share(0.75), 99.0))
	_road_mat.set_shader_parameter("lamp_x", LAMP_X)


## The rider's FTP and the lane's width in watts: they set the road's scale.
func setup(ftp_watts: float, width_watts: int) -> void:
	ftp = maxf(ftp_watts, 50.0)
	lane_width = width_watts
	var half := float(width_watts) / 2.0 / ftp * M_PER_FTP
	for mat in [_road_mat, _rail_mat]:
		mat.set_shader_parameter("half_w", half)
	_placed = false


## x across the road (metres) for a share of FTP.
static func x_of_share(share: float) -> float:
	return (share - CENTRE_SHARE) * M_PER_FTP


## x across the road (metres) for `watts`, on the road or its shoulders.
func x_of(watts: float) -> float:
	return clampf(x_of_share(watts / ftp), -ROAD_HALF - SHOULDER, ROAD_HALF + SHOULDER)


## One frame. `t` is the course's clock, `watts` the smoothed power (your place), `in_lane` and
## `side` (-1 under, 0 in, +1 over) the rules' verdict, `jump_at` seconds to the announced jump
## (< 0: none) and `jump_up` its direction, `beat` 0-1 a pedal-stroke pulse for the nose.
func update_view(delta: float, course: WattLaneCourse, t: float, watts: float, in_lane: bool,
		jump_at: float, jump_up: bool, beat := 0.0) -> void:
	_clock += delta
	_scroll += delta * SPEED
	for i in ROWS:
		_offsets[i] = x_of(course.visual_centre_at(t + float(i) * ROW_LEN / SPEED))
	var target := x_of(watts)
	var before := bike_x
	bike_x = target if not _placed else lerpf(bike_x, target, minf(delta * BIKE_EASE, 1.0))
	_placed = true
	var lateral := (bike_x - before) / maxf(delta, 1e-3)
	_roll = lerpf(_roll, clampf(-lateral * 1.2, -4.0, 4.0), minf(delta * 4.0, 1.0))
	camera.position.x = bike_x
	camera.rotation_degrees.z = _roll
	_bike.position.x = bike_x
	if chase:
		camera.position = Vector3(bike_x, 2.4, 6.5)
		camera.rotation_degrees = Vector3(-9.0, 0.0, 0.0)
		_bike.position = Vector3(bike_x, 0.22, 0.4)
		_bike.scale = Vector3.ONE * 2.2
	_road_mat.set_shader_parameter("trail", 1.0 if chase else 0.0)
	_glow = move_toward(_glow, 1.0 if in_lane else 0.55, delta * 2.5)
	_warn = move_toward(_warn, 0.0 if in_lane else 1.0, delta * 3.0)
	flash = maxf(flash - delta * 2.5, 0.0)
	_apply(jump_at, jump_up, beat)


func _apply(jump_at: float, jump_up: bool, beat: float) -> void:
	for mat in [_road_mat, _rail_mat]:
		mat.set_shader_parameter("offsets", _offsets)
		mat.set_shader_parameter("glow", _glow + flash)
	_road_mat.set_shader_parameter("scroll", _scroll)
	_post_mat.set_shader_parameter("scroll", _scroll)
	_road_mat.set_shader_parameter("bike_x", bike_x)
	_road_mat.set_shader_parameter("beam_warn", _warn)
	_rail_mat.set_shader_parameter("flash", flash)
	_sky_mat.set_shader_parameter("time", _clock)
	_bike_mat.set_shader_parameter("warn", _warn)
	_bike_mat.set_shader_parameter("pulse", beat)
	var announced := jump_at >= 0.0
	_road_mat.set_shader_parameter("jump_d", jump_at * SPEED if announced else -100.0)
	_road_mat.set_shader_parameter("jump_dir", 1.0 if jump_up else -1.0)
	var pulse := 0.75 + 0.25 * sin(_clock * TAU * 2.0)
	_road_mat.set_shader_parameter("chevrons", pulse if announced else 0.0)


## The opaque world materials (full grade, haze toward the night).
func _opaque_materials() -> Array:
	return [_road_mat, _sky_mat, _post_mat]


# --- Building ---

func _material(shader_name: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://games/watt_lane/shaders/%s.gdshader" % shader_name)
	return mat


func _instance(node_name: String, mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.5, 0.5)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var node := WorldEnvironment.new()
	node.environment = env
	add_child(node)


func _build_sky() -> void:
	var card := QuadMesh.new()
	card.size = SKY_SIZE
	_sky_mat.set_shader_parameter("horizon_v", HORIZON_V)
	var sky := _instance("Sky", card, _sky_mat)
	# The card's horizon line (UV.y = HORIZON_V from its top) at the road's height.
	sky.position = Vector3(0.0, SKY_SIZE.y * (HORIZON_V - 0.5), SKY_Z)


func _build_road() -> void:
	var plane := PlaneMesh.new()
	var length := -SKY_Z + 5.0
	plane.size = Vector2(SKY_SIZE.x * 0.7, length + 10.0)
	var road := _instance("Road", plane, _road_mat)
	road.position = Vector3(0.0, 0.0, 15.0 - (length + 10.0) / 2.0)


func _build_rails() -> void:
	var rails := _instance("Rails", rails_mesh(), _rail_mat)
	# The vertex shader moves every vertex across the road: cull with the whole road.
	rails.custom_aabb = AABB(Vector3(-40.0, -1.0, -ROWS * ROW_LEN - 5.0), Vector3(80.0, 4.0, ROWS * ROW_LEN + 10.0))


## Both rails as strips along the lane's rows, unbent (the shader bends them): per side, a fence
## of light (two vertices a row, UV.y 0 at the road and 1 at the top, UV2.x 0) and a core on the
## road (UV2.x 1, UV2.y -1..1 across). UV.x is the side. VERTEX.z is -distance ahead.
static func rails_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [-1.0, 1.0]:
		_rail_strip(st, side, [Vector3(0.0, 0.0, 0.0), Vector3(0.0, RAIL_HEIGHT, 0.0)], [0.0, 1.0], 0.0)
		_rail_strip(st, side, [Vector3(-RAIL_CORE, 0.02, 0.0), Vector3(RAIL_CORE, 0.02, 0.0)], [-1.0, 1.0], 1.0)
	return st.commit()


static func _rail_strip(st: SurfaceTool, side: float, ends: Array, across: Array, part: float) -> void:
	for i in ROWS - 1:
		var quad: Array[Vector3] = []
		var uv2: Array[float] = []
		for row in [i, i + 1]:
			for k in 2:
				var p: Vector3 = ends[k]
				quad.append(Vector3(p.x, p.y, -float(row) * ROW_LEN))
				uv2.append(across[k])
		for idx in [0, 1, 3, 0, 3, 2]:
			var is_fence := part == 0.0
			st.set_uv(Vector2(side, (uv2[idx] if is_fence else 0.0)))
			st.set_uv2(Vector2(part, uv2[idx]))
			st.add_vertex(quad[idx])


func _build_posts() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	mm.mesh = post_mesh()
	mm.instance_count = LAMPS_PER_SIDE * 2
	for i in LAMPS_PER_SIDE:
		var z := -float(i) * LAMP_SPACING
		mm.set_instance_transform(i * 2, Transform3D(Basis.IDENTITY, Vector3(LAMP_X, 0.0, z)))
		mm.set_instance_transform(i * 2 + 1, Transform3D(Basis.from_scale(Vector3(-1.0, 1.0, 1.0)),
			Vector3(-LAMP_X, 0.0, z - LAMP_SPACING / 2.0)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Lamps"
	mmi.multimesh = mm
	mmi.material_override = _post_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-20.0, -1.0, -LAMP_SPACING * LAMPS_PER_SIDE - 30.0), Vector3(40.0, 12.0, LAMP_SPACING * LAMPS_PER_SIDE + 60.0))
	add_child(mmi)


## A lamp post on the right shoulder (the left one is mirrored): a pole, an arm over the road and
## a lamp head. Vertex colour: the part's colour, alpha 1 on the head (it glows).
static func post_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steel := Color(0.06, 0.08, 0.09, 0.0)
	_box(st, Vector3(0.0, 3.6, 0.0), Vector3(0.16, 7.2, 0.16), steel)
	_box(st, Vector3(-1.1, 7.1, 0.0), Vector3(2.2, 0.12, 0.12), steel)
	_box(st, Vector3(-2.1, 6.98, 0.0), Vector3(0.7, 0.12, 0.3), Color(1, 1, 1, 1.0))
	return st.commit()


static func _box(st: SurfaceTool, centre: Vector3, size: Vector3, color: Color) -> void:
	var h := size / 2.0
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)], [Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(0, 0, 1), Vector3(1, 0, 0)], [Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)], [Vector3(0, 0, -1), Vector3(0, 1, 0), Vector3(1, 0, 0)],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var a: Vector3 = f[1]
		var b: Vector3 = f[2]
		var c := centre + n * h
		var corners := [c - a * h - b * h, c + a * h - b * h, c + a * h + b * h, c - a * h + b * h]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(color)
			st.add_vertex(corners[idx])


func _build_bike() -> void:
	_bike = _instance("BikeNose", bike_mesh(), _bike_mat)
	_bike.position = Vector3(0.0, 0.72, -1.7)


## The light-bike's nose: a flat, notched arrowhead fan, UV.y 0 at its centre and 1 on its outline (the
## shader lights the outline).
static func bike_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centre := Vector3(0.0, 0.05, -0.42)
	var outline: Array[Vector3] = [Vector3(0.0, 0.0, -0.9), Vector3(0.2, 0.0, 0.0), Vector3(0.0, 0.03, -0.22),
		Vector3(-0.2, 0.0, 0.0)]
	for i in outline.size():
		st.set_uv(Vector2(0.0, 0.0))
		st.add_vertex(centre)
		for p in [outline[i], outline[(i + 1) % outline.size()]]:
			st.set_uv(Vector2(0.0, 1.0))
			st.add_vertex(p)
	return st.commit()
