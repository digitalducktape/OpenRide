class_name CadenceWorld
extends Node3D
## Cadence Karaoke's 3D view (#42), first person down a neon tunnel. The target is a glowing
## rail ahead whose height is the target cadence (changes rise and fall in the distance); your
## cadence is an orb hovering at the same depth. Keep the orb on the rail. Beat rings fly past,
## one a beat, and the tunnel's lines flare with the beat. All of it is procedural: shaders for the
## tunnel and rings, boxes in MultiMeshes for the rail, nothing imported.
##
## It only draws: `CadenceLogic` holds the rules. The tablet recipe (docs/GAMES.md, "On the
## tablet") applies: unshaded surfaces, MultiMesh, and nothing laid out per frame beyond the
## rail's 3 × 48 box transforms.

const RAIL_POINTS := 48
const ORB_Z := -6.0  ## the depth the orb and the rail's start sit at
const LOOK_DIST := 44.0  ## how far ahead the rail reaches (LOOKAHEAD_SEC of target changes)
const Y_PER_RPM := 0.045
const MID_RPM := 80.0
const CAMERA_Y := 2.2
const CAMERA_PITCH := -9.0
const SPEED := 3.6  ## m/s the tunnel flows past; LOOK_DIST / SPEED is the lookahead
const RING_COUNT := 14
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
var _rail_mm: MultiMesh
var _band_mm: MultiMesh
var _orb: MeshInstance3D
var _orb_mat: StandardMaterial3D
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _scroll := 0.0
var _orb_y := 0.0
var _noise: ImageTexture


func _ready() -> void:
	_build_environment()
	_build_tunnel()
	_build_rings()
	_build_rail()
	_build_orb()
	camera = Camera3D.new()
	camera.fov = 64.0
	camera.near = 0.1
	camera.far = 140.0
	camera.position = Vector3(0.0, CAMERA_Y, 0.0)
	camera.rotation_degrees = Vector3(CAMERA_PITCH, 0.0, 0.0)
	add_child(camera)
	set_theme_color(theme_color)


## Draws one frame. `targets` holds RAIL_POINTS target cadences from now to LOOKAHEAD_SEC ahead,
## `cadence` the rider's, `tolerance` the band's half-width (rpm), `state` "in_bonus", "in_band",
## "near" or "out" (the orb's colour), `frozen` whether scoring is frozen, `streak` 0-1 (how far
## through the multiplier) and `beat_rate` beats per second.
func update_view(delta: float, targets: PackedFloat32Array, cadence: float, tolerance: float, state: String, frozen: bool, streak: float, beat_rate: float) -> void:
	_scroll += delta * SPEED
	for mat in _grid_mats:
		mat.set_shader_parameter("scroll", _scroll)
		mat.set_shader_parameter("beat", beat)
	_ring_mat.set_shader_parameter("pulse", beat)
	_update_rings(beat_rate)
	_update_rail(targets, tolerance)
	var want := clampf((cadence - MID_RPM) * Y_PER_RPM, -2.3, 2.3)
	_orb_y = lerpf(_orb_y, want, minf(delta * 14.0, 1.0))
	orb_flash = maxf(orb_flash - delta * 2.5, 0.0)
	var color := _orb_color(state, frozen)
	color = color.lerp(Color(1.0, 0.15, 0.1), orb_flash)
	_orb_mat.albedo_color = color
	_orb_mat.emission = color
	_orb_mat.emission_energy_multiplier = 1.8 + beat * 1.5 + streak * 1.2
	_halo_mat.albedo_color = Color(color, 0.5)
	_orb.position = Vector3(0.0, _orb_y, ORB_Z)
	_orb.scale = Vector3.ONE * (1.0 + beat * 0.12 + streak * 0.2)
	_halo.position = _orb.position
	_halo.scale = Vector3.ONE * (1.0 + beat * 0.3 + streak * 0.6)


func set_theme_color(color: Color) -> void:
	theme_color = color
	for mat in _grid_mats:
		mat.set_shader_parameter("line_color", color)
	_ring_mat.set_shader_parameter("ring_color", color)
	var rail_mat := _rail_mm_material(_rail_mm)
	rail_mat.albedo_color = color
	rail_mat.emission = color
	var band_mat := _rail_mm_material(_band_mm)
	band_mat.albedo_color = Color(color, 0.22)
	band_mat.emission = color


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


func _rail_mm_material(mm: MultiMesh) -> StandardMaterial3D:
	return (mm.get_meta("mat") as StandardMaterial3D)


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
	_update_rings(1.4)


## Beat rings: spaced one beat apart along the tunnel, all flowing toward the rider.
func _update_rings(beat_rate: float) -> void:
	var spacing := SPEED / maxf(beat_rate, 0.3)
	var offset := fposmod(_scroll, spacing)
	for i in RING_COUNT:
		var z := -(i * spacing) + offset - 1.0
		_ring_mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(0.0, (FLOOR_Y + CEIL_Y) / 2.0, z)))


func _build_rail() -> void:
	var seg := BoxMesh.new()
	seg.size = Vector3(1.0, 1.0, 1.0)
	_rail_mm = _rail_multimesh(seg, "Rail", Color(1, 1, 1))
	_band_mm = _rail_multimesh(seg, "Band", Color(1, 1, 1, 0.5))


func _rail_multimesh(mesh: Mesh, node_name: String, color: Color) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = RAIL_POINTS - 1
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 1.0
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.disable_receive_shadows = true
	mm.set_meta("mat", mat)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.extra_cull_margin = 200.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


## The rail is a chain of flat boxes along the targets; the band is the same chain, wider and
## translucent, as tall as the tolerance.
func _update_rail(targets: PackedFloat32Array, tolerance: float) -> void:
	var count := mini(targets.size(), RAIL_POINTS)
	if count < 2:
		return
	var band_h := maxf(tolerance * Y_PER_RPM * 2.0, 0.2)
	var prev := _rail_point(0, targets[0])
	for i in range(1, count):
		var point := _rail_point(i, targets[i])
		var d := point - prev
		var len := d.length()
		var q := Quaternion(Vector3.FORWARD, d / len)
		var mid := (prev + point) * 0.5
		var basis := Basis(q)
		_rail_mm.set_instance_transform(i - 1, Transform3D(basis.scaled_local(Vector3(1.3, 0.09, len * 1.04)), mid))
		_band_mm.set_instance_transform(i - 1, Transform3D(basis.scaled_local(Vector3(3.4, band_h, len * 1.04)), mid))
		prev = point


func _rail_point(i: int, rpm: float) -> Vector3:
	var t := float(i) / (RAIL_POINTS - 1)
	return Vector3(0.0, (rpm - MID_RPM) * Y_PER_RPM, ORB_Z - t * LOOK_DIST)


func _build_orb() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.42
	sphere.height = 0.84
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
	quad.size = Vector2(2.6, 2.6)
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
