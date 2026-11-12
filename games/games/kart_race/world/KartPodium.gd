class_name KartPodium
extends Node3D
## The Grand Prix podium on the track (#43, the polish pass): three stepped blocks on a plinth,
## built on the start straight just past the line, the top three's own karts (`KartView`) landing
## on them in turn and cheering, under a held camera that frames the stage in the left two
## thirds of the screen (the standings sit on the right). KartRace drives it: `stage()` builds
## it facing the camera, `advance()` each frame raises the blocks and drops the karts, and
## `kart_state(i)` gives each podium kart the pose to draw (a KartState that never races).
##
## Look: the blocks are vertex-coloured (painted AO, a lighter bevelled cap, a pale stripe under
## the cap, a darker foot) and lit by the world's one hand-made light (`scenery_mat`), like every
## other prop. Gold, silver and bronze per the art bible. The place numbers, names and points are
## the board's (2D, baked), placed from `screen_points()`.
##
## Cost: a non-racing state (the race logic idles behind the board). Four meshes (three blocks
## that rise separately and the plinth), the three karts already loaded, and nothing per frame
## but `advance` (a few transforms) while the stage shows.

const COLORS := [Color(1.0, 0.76, 0.18), Color(0.78, 0.82, 0.92), Color(0.86, 0.5, 0.24)]
const HEIGHTS := [1.25, 0.9, 0.62]  ## metres, places 1-3
const XS := [0.0, -2.55, 2.55]  ## across the stage (+x is screen right)
const BLOCK := Vector2(2.35, 2.4)  ## width, depth
const RISE_AT := [1.25, 0.8, 0.35]  ## seconds: third rises first, the champion last
const RISE_SEC := 0.5
const DROP_SEC := 0.42
const DROP_H := 1.8
## The held camera, in the stage's frame (+z toward the camera): off to the right, so the stage
## sits in the left two thirds of the screen.
const CAMERA_AT := Vector3(2.7, 2.8, 10.8)
const CAMERA_LOOK := Vector3(2.7, 2.25, 0.0)
const CAMERA_FOV := 50.0

var time := 0.0
var _blocks: Array[Node3D] = []
var _states: Array[KartState] = []
var _facing := Vector3.BACK


## Builds the stage at `origin` (on the road), its front facing `facing` (horizontal), with the
## world's scenery material.
func stage(mat: Material, origin: Vector3, facing: Vector3) -> void:
	name = "Podium"
	_facing = Vector3(facing.x, 0.0, facing.z).normalized()
	transform = Transform3D(Basis.looking_at(-_facing, Vector3.UP), origin)
	var plinth := MeshKit3D.new()
	plinth.ao_y0 = -0.1
	plinth.ao_y1 = 0.2
	plinth.ao_min = 0.6
	plinth.add(MeshKit3D.box(Vector3(8.0, 0.16, 3.1)), MeshKit3D.xf(Vector3(0, 0.08, 0.1)), Color(0.24, 0.16, 0.46))
	plinth.add(MeshKit3D.box(Vector3(8.2, 0.04, 3.3)), MeshKit3D.xf(Vector3(0, 0.16, 0.1)), Color(0.55, 0.42, 1.0))
	add_child(MeshKit3D.mesh_node(plinth.commit(), mat, "Plinth"))
	for i in 3:
		var h: float = HEIGHTS[i]
		var col: Color = COLORS[i]
		var kit := MeshKit3D.new()
		kit.ao_y0 = 0.0
		kit.ao_y1 = h * 0.8
		kit.ao_min = 0.62
		var w := BLOCK.x
		var dd := BLOCK.y
		kit.add(MeshKit3D.box(Vector3(w, h - 0.1, dd)), MeshKit3D.xf(Vector3(0, (h - 0.1) * 0.5, 0)), col)
		# The bevelled cap: a lighter slab, a little wider, with a softer step under it.
		kit.add(MeshKit3D.box(Vector3(w + 0.08, 0.1, dd + 0.08)), MeshKit3D.xf(Vector3(0, h - 0.05, 0)), col.lightened(0.35))
		kit.add(MeshKit3D.box(Vector3(w + 0.03, 0.05, dd + 0.03)), MeshKit3D.xf(Vector3(0, h - 0.125, 0)), col.lightened(0.15))
		# A pale stripe across the front under the cap, and a dark foot.
		kit.add(MeshKit3D.box(Vector3(w * 0.92, 0.07, 0.02)), MeshKit3D.xf(Vector3(0, h - 0.26, dd * 0.5 + 0.005)), col.lightened(0.55))
		kit.add(MeshKit3D.box(Vector3(w + 0.02, 0.1, dd + 0.02)), MeshKit3D.xf(Vector3(0, 0.05, 0)), col.darkened(0.45))
		var block := MeshKit3D.mesh_node(kit.commit(), mat, "Block%d" % (i + 1))
		block.position = Vector3(XS[i], 0.16 - h, 0.0)
		add_child(block)
		_blocks.append(block)
		var k := KartState.new()
		k.id = i
		k.finished = true
		k.place = i + 1
		k.normal = Vector3.UP
		_states.append(k)
	time = 0.0
	advance(0.0)


## The held camera's transform (world).
func camera_transform() -> Transform3D:
	var eye := global_transform * CAMERA_AT
	var look := global_transform * CAMERA_LOOK
	return Transform3D(Basis.looking_at(look - eye, Vector3.UP), eye)


## Raises the blocks and drops the karts on them, `dt` seconds on.
func advance(dt: float) -> void:
	time += dt
	var heading := atan2(-_facing.x, -_facing.z)  # KartState.forward() == the stage's front
	for i in 3:
		var h: float = HEIGHTS[i]
		var u := clampf((time - float(RISE_AT[i])) / RISE_SEC, 0.0, 1.0)
		var e := 1.0 - pow(1.0 - u, 3.0)
		var lift := e + sin(u * PI) * 0.08  # a little overshoot
		_blocks[i].position.y = 0.16 - h + h * lift
		var k := _states[i]
		var v := clampf((time - landed_at(i) + DROP_SEC) / DROP_SEC, 0.0, 1.0)
		k.pos = global_transform * Vector3(XS[i], 0.16 + h, 0.1) + Vector3.UP * DROP_H * (1.0 - v * v)
		k.heading = heading
		k.hop = 0.0


## When place i's kart (0 = the champion) lands on its block, in stage seconds.
static func landed_at(i: int) -> float:
	return float(RISE_AT[i]) + RISE_SEC + DROP_SEC


## Whether place i's kart is shown yet (it drops in once its block is up).
func kart_shown(i: int) -> bool:
	return time >= float(RISE_AT[i]) + RISE_SEC


## The pose place i's kart draws with (KartView.sync): on its block, facing the camera, cheering.
func kart_state(i: int) -> KartState:
	return _states[i]


## Where each place's block front and kart top show on the stage (1920x1080, `Stage`), from
## `camera` drawing a view of `view_size` pixels over the whole window: {faces, heads (Vector2
## each, places 1-3), face_h (px)}.
func screen_points(camera: Camera3D, view_size: Vector2) -> Dictionary:
	var at := func(p: Vector3) -> Vector2: return Stage.from_view(camera.unproject_position(p), view_size)
	var faces: Array[Vector2] = []
	var heads: Array[Vector2] = []
	var face_h: Array[float] = []
	for i in 3:
		var h: float = HEIGHTS[i]
		var top := global_transform * Vector3(XS[i], 0.16 + h, BLOCK.y * 0.5)
		var bottom := global_transform * Vector3(XS[i], 0.16, BLOCK.y * 0.5)
		var a: Vector2 = at.call(top)
		var b: Vector2 = at.call(bottom)
		faces.append((a + b) * 0.5)
		face_h.append(b.y - a.y)
		heads.append(at.call(global_transform * Vector3(XS[i], 0.16 + h + 1.75, 0.1)))
	return {"faces": faces, "heads": heads, "face_h": face_h,
		"centre": at.call(global_transform * Vector3(0, 1.2, 0))}
