class_name CadenceWorld
extends Node3D
## Cadence Karaoke's 3D view (#42), first person down a neon tunnel. Your orb rolls along the
## floor. A lane is marked on the floor, a box with a bright beat line across its middle, and beat
## rings fly down the tunnel toward the line, one landing on it every beat. When your cadence
## matches the target the orb sits in the middle of the box on the line; the faster you pedal above
## the target the further it moves in front of the box (further up the floor), the slower below it
## the further it falls behind the box (nearer you, lower on the screen). Keep it inside the box.
## All of it is procedural: shaders for the tunnel and rings, boxes for the lane, nothing imported.
##
## It only draws: `CadenceLogic` holds the rules. The tablet recipe (docs/GAMES.md, "On the
## tablet") applies: unshaded surfaces, MultiMesh, and nothing laid out per frame beyond a dozen
## ring transforms.

const ORB_Z := -18.0  ## the depth of the beat line
const Z_RANGE := 10.0  ## metres the orb moves at full gap: in front of or behind the band
const RING_SPACING := 7.0  ## metres between beat rings
const CAMERA_Y := 2.2
const CAMERA_PITCH := -12.0
const ORB_RADIUS := 0.6
const LANE_HALF_W := 3.2  ## half the width of the lane the box is marked on
const RING_COUNT := 18
const RING_SIZE := Vector2(15.0, 7.4)
const FLOOR_Y := -3.4
const CEIL_Y := 4.2
const HALF_W := 7.5

const THEMES := {
	"warmup": Color(0.25, 0.8, 1.0),
	"recovery": Color(0.3, 1.0, 0.65),
	"cooldown": Color(0.72, 0.5, 1.0),
	"free": Color(1.0, 0.45, 0.8),
	"cyan": Color(0.25, 0.8, 1.0),
	"green": Color(0.3, 1.0, 0.65),
	"violet": Color(0.72, 0.5, 1.0),
	"pink": Color(1.0, 0.45, 0.8),
}

var camera: Camera3D
var theme_color := THEMES.free
var beat := 0.0  ## 0-1, decays after each beat; set by the scene
var orb_flash := 0.0  ## 0-1, a red flash when the streak breaks

var _grid_mats: Array[ShaderMaterial] = []
var _ring_mat: ShaderMaterial
var _ring_mm: MultiMesh
var _line: MeshInstance3D
var _line_mat: StandardMaterial3D
var _gates: Array[MeshInstance3D] = []
var _gate_mat: StandardMaterial3D
var _lane: MeshInstance3D
var _lane_mat: StandardMaterial3D
var _orb: MeshInstance3D
var _orb_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _scroll := 0.0
var _orb_z := ORB_Z
var _noise: ImageTexture


func _ready() -> void:
	_build_environment()
	_build_tunnel()
	_build_rings()
	_build_line()
	_build_orb()
	camera = Camera3D.new()
	camera.fov = 64.0
	camera.near = 0.1
	camera.far = 140.0
	camera.position = Vector3(0.0, CAMERA_Y, 0.0)
	camera.rotation_degrees = Vector3(CAMERA_PITCH, 0.0, 0.0)
	add_child(camera)
	set_theme_color(theme_color)


## Draws one frame. `gap` is -1 to 1: 0 puts the orb on the line, 1 in front of the box and -1
## behind it. `band` is the box's half-depth on that scale, `beat_phase` 0-1 through the current
## beat (a ring lands on the line as it wraps), `state` "in_bonus", "in_band", "near" or "out"
## (the orb's colour), `frozen` whether scoring is frozen, `streak` 0-1 (how far through the
## multiplier) and `beat_rate` beats per second.
func update_view(delta: float, gap: float, band: float, beat_phase: float, state: String, frozen: bool, streak: float, beat_rate: float) -> void:
	_scroll += delta * beat_rate * RING_SPACING
	for mat in _grid_mats:
		mat.set_shader_parameter("scroll", _scroll)
		mat.set_shader_parameter("beat", beat)
	_ring_mat.set_shader_parameter("pulse", beat)
	_line_mat.emission_energy_multiplier = 1.6 + beat * 1.6
	_lane_mat.albedo_color = Color(theme_color, 0.16 + beat * 0.1)
	_update_rings(beat_phase)
	var reach := maxf(band * Z_RANGE, 0.4)  # the box's half-depth
	_gates[0].position.z = ORB_Z - reach
	_gates[1].position.z = ORB_Z + reach
	_lane.scale = Vector3(1.0, 1.0, reach * 2.0)
	_orb_z = lerpf(_orb_z, ORB_Z - gap * Z_RANGE, minf(delta * 8.0, 1.0))
	orb_flash = maxf(orb_flash - delta * 2.5, 0.0)
	var color := _orb_color(state, frozen)
	color = color.lerp(Color(1.0, 0.15, 0.1), orb_flash)
	_orb_mat.albedo_color = color
	_orb_mat.emission = color
	_orb_mat.emission_energy_multiplier = 1.8 + beat * 1.5 + streak * 1.2
	_halo_mat.albedo_color = Color(color, 0.5)
	_orb.position = Vector3(0.0, FLOOR_Y + ORB_RADIUS, _orb_z)
	# Plain perspective: small and far when ahead, big and close when behind.
	var size := 1.0 + beat * 0.12 + streak * 0.2
	_orb.scale = Vector3.ONE * size
	_halo.position = _orb.position
	_halo.scale = Vector3.ONE * (size + beat * 0.3 + streak * 0.5)


func set_theme_color(color: Color) -> void:
	theme_color = color
	for mat in _grid_mats:
		mat.set_shader_parameter("line_color", color)
	_ring_mat.set_shader_parameter("ring_color", color)
	_gate_mat.albedo_color = color
	_gate_mat.emission = color
	_lane_mat.emission = color


func _orb_color(state: String, frozen: bool) -> Color:
	if frozen:
		return Color(1.0, 0.7, 0.2)
	match state:
		"in_bonus":
			return Color(0.45, 1.0, 0.65)
		"in_band":
			return Color(0.6, 1.0, 0.5)
		"near":
			return Color(1.0, 0.85, 0.3)
	return Color(1.0, 0.4, 0.35)


# --- Building ---

func _build_environment() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.01, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.6)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env_node.environment = env
	add_child(env_node)


func _build_tunnel() -> void:
	var length := 150.0
	# [centre, rotation in degrees, size, the axis the cross lines follow]
	var faces := [
		[Vector3(0.0, FLOOR_Y, -length / 2.0), Vector3(0, 0, 0), Vector2(HALF_W * 2.0, length), Vector3(1, 0, 0)],
		[Vector3(0.0, CEIL_Y, -length / 2.0), Vector3(0, 0, 0), Vector2(HALF_W * 2.0, length), Vector3(1, 0, 0)],
		[Vector3(-HALF_W, (FLOOR_Y + CEIL_Y) / 2.0, -length / 2.0), Vector3(0, 0, 90), Vector2(CEIL_Y - FLOOR_Y, length), Vector3(0, 1, 0)],
		[Vector3(HALF_W, (FLOOR_Y + CEIL_Y) / 2.0, -length / 2.0), Vector3(0, 0, 90), Vector2(CEIL_Y - FLOOR_Y, length), Vector3(0, 1, 0)],
	]
	var shader := load("res://games/cadence_karaoke/shaders/grid.gdshader")
	for face in faces:
		var mesh := PlaneMesh.new()
		mesh.size = face[2]
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("across_axis", face[3])
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = face[0]
		mi.rotation_degrees = face[1]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		_grid_mats.append(mat)


func _build_rings() -> void:
	var quad := QuadMesh.new()
	quad.size = RING_SIZE
	_ring_mat = ShaderMaterial.new()
	_ring_mat.shader = load("res://games/cadence_karaoke/shaders/ring.gdshader")
	_ring_mm = MultiMesh.new()
	_ring_mm.transform_format = MultiMesh.TRANSFORM_3D
	_ring_mm.mesh = quad
	_ring_mm.instance_count = RING_COUNT
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rings"
	mmi.multimesh = _ring_mm
	mmi.material_override = _ring_mat
	mmi.extra_cull_margin = 200.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	_update_rings(0.0)


## Beat rings: one a beat apart, flowing toward the rider. Ring k lands on the line when
## `beat_phase` reaches 1 (k = 1), so the line flares as a ring arrives.
func _update_rings(beat_phase: float) -> void:
	for i in RING_COUNT:
		var z := ORB_Z - (float(i - 1) - beat_phase) * RING_SPACING
		_ring_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, (FLOOR_Y + CEIL_Y) / 2.0, z)))


## The box on the floor: a translucent lane as deep as the band, a dim gate at each end, and the
## beat line, a bright bar across the middle (white, so it is never mistaken for a ring).
func _build_line() -> void:
	_line_mat = _flat_material(Color(1, 1, 1), false)
	_gate_mat = _flat_material(Color(1, 1, 1), false)
	_lane_mat = _flat_material(Color(1, 1, 1, 0.2), true)
	_line = _floor_bar("BeatLine", Vector3(LANE_HALF_W * 2.0 + 1.6, 0.12, 0.45), _line_mat, 0.07)
	_line.position.z = ORB_Z
	for gate_name in ["BoxFar", "BoxNear"]:
		var gate := _floor_bar(gate_name, Vector3(LANE_HALF_W * 2.0 + 0.6, 0.1, 0.22), _gate_mat, 0.06)
		_gates.append(gate)
	_lane = _floor_bar("Lane", Vector3(LANE_HALF_W * 2.0, 0.03, 1.0), _lane_mat, 0.02)
	_lane.position.z = ORB_Z


func _floor_bar(bar_name: String, size: Vector3, mat: StandardMaterial3D, lift: float) -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = size
	var mi := MeshInstance3D.new()
	mi.name = bar_name
	mi.mesh = box
	mi.material_override = mat
	mi.position = Vector3(0.0, FLOOR_Y + lift, ORB_Z)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


func _flat_material(color: Color, see_through: bool) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.5
	if see_through:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.disable_receive_shadows = true
	return mat


func _build_orb() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = ORB_RADIUS
	sphere.height = ORB_RADIUS * 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	_orb_mat = StandardMaterial3D.new()
	_orb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_orb_mat.emission_enabled = true
	_orb = MeshInstance3D.new()
	_orb.name = "Orb"
	_orb.mesh = sphere
	_orb.material_override = _orb_mat
	_orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_orb)
	# A soft halo: a billboard with a radial gradient, added to the picture.
	var glow := GradientTexture2D.new()
	glow.fill = GradientTexture2D.FILL_RADIAL
	glow.fill_from = Vector2(0.5, 0.5)
	glow.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 0.35))
	glow.gradient = g
	var quad := QuadMesh.new()
	quad.size = Vector2(3.6, 3.6)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.albedo_texture = glow
	_halo_mat.disable_fog = true
	_halo = MeshInstance3D.new()
	_halo.name = "Halo"
	_halo.mesh = quad
	_halo.material_override = _halo_mat
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)
