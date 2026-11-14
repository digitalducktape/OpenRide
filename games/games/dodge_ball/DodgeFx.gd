class_name DodgeFx
extends RefCounted
## Dodge Ball's effect parts (#39), made once by DodgeWorld._build_fx: the pooled FX MultiMesh
## (bursts and sparks, moved by shaders/fx.gdshader), the shield's shard mesh, the speed streaks
## and the floating points' labels; and the packing of one FX instance. DodgeWorld keeps the
## pool's state and drives it (burst, update_view).


## The pool: FX_POOL quads in `mat`, every slot born long ago (dead).
static func pool(mat: ShaderMaterial) -> MultiMesh:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = quad
	mm.instance_count = DodgeWorld.FX_POOL
	for i in DodgeWorld.FX_POOL:
		# Born long ago: every slot starts dead.
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.ZERO, Vector3(0, 0.1, 0), Vector3.ZERO), Vector3.ZERO))
		mm.set_instance_custom_data(i, Color(-1000.0, 0, 0, 0))
	return mm


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


## A shard off the shield: a small additive prism.
static func shard_mesh() -> PrismMesh:
	var add := StandardMaterial3D.new()
	add.vertex_color_use_as_albedo = true
	add.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	add.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	add.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var shard := PrismMesh.new()
	shard.size = Vector3(0.1, 0.14, 0.02)
	shard.material = add
	return shard


## Speed streaks: thin bright lines rushing past the edges of the view at high cadence (not
## emitting until update_view turns them on).
static func streaks() -> CPUParticles3D:
	var line := BoxMesh.new()
	line.size = Vector3(0.012, 0.012, 1.4)
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.vertex_color_use_as_albedo = true
	line_mat.disable_fog = true
	line.material = line_mat
	var streaks := CPUParticles3D.new()
	streaks.mesh = line
	streaks.amount = 40
	streaks.lifetime = 0.5
	streaks.local_coords = true
	streaks.emitting = false
	# A ring around the line of sight, so the streaks rush past the edges and never cross the
	# middle of the road.
	streaks.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	streaks.emission_ring_axis = Vector3(0, 0, 1)
	streaks.emission_ring_height = 6.0
	streaks.emission_ring_radius = 4.6
	streaks.emission_ring_inner_radius = 3.0
	streaks.direction = Vector3(0, 0, 1)
	streaks.spread = 0.0
	streaks.gravity = Vector3.ZERO
	streaks.color = Color(1, 1, 1, 0.22)
	streaks.position = Vector3(0, 0, -9.0)
	return streaks


## A floating points label, hidden until a popup shows it.
static func popup_label() -> Label3D:
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	# The shared display face with the game's navy ink (framework/ui/UI_STYLE.md).
	label.font = GameTheme.display_font()
	label.font_size = 96
	label.outline_size = 18
	label.outline_modulate = DodgeWorld.POPUP_INK
	label.pixel_size = 0.004
	label.no_depth_test = true
	label.visible = false
	return label
