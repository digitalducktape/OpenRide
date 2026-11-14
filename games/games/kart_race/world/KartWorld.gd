class_name KartWorld
extends Node3D
## Kart Race's world (#43): any of the cup's four tracks, either direction, dressed in its
## theme (KartLook): Meadow Ring's hills, Canyon Dash's red rock, Harbor Lights' sunset quay,
## Frost Pass's snow and ice.
##
## Everything is procedural (MeshKit3D) and lit by hand (KartLook, shaders/): no engine light
## pass, no per-pixel fog. Shared here: the road (one unshaded mesh painted from track-space
## UVs: asphalt, lines, the chequered line, grid boxes, kerbs, tyre marks, verges), the boost
## pads and item rows painted over it, the barriers, the land (KartTerrain, one heightfield to
## the horizon) with a skirt from the barriers' feet, the start gate and its lights, the
## grandstand and crowd, flags, item-row pylons, climb signs, corner chevrons and clouds. Each
## theme's KartDress shapes the land and adds its own set pieces.
##
## Static scenery is baked into one mesh per CELL-metre square (culled by the frustum and
## beyond CELL_RANGE) or per wedge of the far woods (SECTORS); repeated animated things are
## MultiMeshes. About 30 draw calls in view (`draw_budget()` counts the upper bound).
##
## This node owns the materials, the build order, the placement helpers the dressers call and
## the per-frame bits (spin, start lights, quality trims). The builders live beside it:
## KartRoadMeshes (road, pads, barriers, skirt), KartTrackside (pylons, climb signs, chevrons),
## KartStartArea (grandstand, crowd, gate, flags), KartClouds, and KartGridShot (the title shot).

const ROAD_DEFAULTS := {"cobbles": 0.0, "verge_grain": 0.3, "verge_gain": 1.0}
const GROUND_DEFAULTS := {"snow": 0.0, "grain": 0.24}
const SKY_DEFAULTS := {"glare": 0.55, "halo": 0.18}
const ROAD_STEP := KartRoadMeshes.ROAD_STEP  ## metres between mesh rows along the track
const SKIRT := KartRoadMeshes.SKIRT  ## the skirt from the barrier's foot out and down under the land
const WALL_HEIGHT := KartRoadMeshes.WALL_HEIGHT
const TREE_CLEARANCE := 5.0  ## trees keep this far beyond the barrier
const SECTORS := 12
const CELL := 110.0
const CELL_RANGE := 230.0
## The quality governor's trims (KartQualityGovernor): foliage cells drawn to this range, and
## this share of the crowd.
const CELL_RANGE_TRIMMED := 150.0
const CROWD_TRIMMED := 0.5

## The grid shot's frame and what covers it during the title (KartGridShot).
const SHOT_SIZE := KartGridShot.SHOT_SIZE
const TITLE_BAND := KartGridShot.TITLE_BAND  ## KartHud's title card band
const SHOT_CORNER := KartGridShot.SHOT_CORNER
const SHOT_KART := KartGridShot.SHOT_KART
const GRID_KARTS := KartGridShot.GRID_KARTS
const STAND_LENGTH := 84.0
const STAND_ROWS := 8

const FLAG_COLORS := [Color(0.95, 0.25, 0.2), Color(1.0, 0.8, 0.15), Color(0.2, 0.6, 1.0),
	Color(0.35, 0.85, 0.35), Color(0.75, 0.35, 0.95), Color(1.0, 0.5, 0.15), Color(0.98, 0.98, 0.98)]

## Dev switches (KartRace's tuning file, [world] section), each true by default, set before
## `build`: road, walls, ground, scenery, and within the scenery foliage, props, woods, stand,
## clouds; ground_detail (the land's rock strata and specks).
var tuning := {}
var track: KartTrackModel
var terrain: KartTerrain
var dress: KartDress
var centre := Vector3.ZERO
## How far the track reaches from `centre` (the larger of its x and z half-extents), metres.
var reach := 0.0
var look: Dictionary = KartLook.look

var road_mat: ShaderMaterial
var ground_mat: ShaderMaterial
var scenery_mat: ShaderMaterial
var foliage_mat: ShaderMaterial
var props_mat: ShaderMaterial  ## scenery with COLOR.a = glow (windows, bulbs, signs)
var tint_mat: ShaderMaterial
var flag_mat: ShaderMaterial
var banner_mat: ShaderMaterial
var crowd_mat: ShaderMaterial
var lamps_mat: ShaderMaterial
var water_mat: ShaderMaterial
var pads_mat: ShaderMaterial

## Quality trims in force (set_quality); kept across tracks.
var foliage_range := CELL_RANGE
## The title shot over the grid (KartChaseCamera.flyover opens on it), solved once per build so
## the shot frames the theme's hero set piece (KartDress.hero): {eye, look, fov, focus, score}.
## Empty when the theme has none (the camera falls back to its generic shot).
var grid_shot := {}
## The grandstand's frame (local -z along the track, +x away from it), once built.
var stand_xf := Transform3D.IDENTITY
var crowd_share := 1.0

var _built: Node3D
var _foliage_cells: Array[GeometryInstance3D] = []
var _crowd: MultiMesh
var _sky_mat: ShaderMaterial
var _env: WorldEnvironment
var _halos: MultiMeshInstance3D
var _spinners: Array[Node3D] = []  ## spin(): nodes turning every frame
var _spin_rates: Array[Vector3] = []  ## their axes × rad/s
var _stand_lamps: Array[Vector3] = []


func _ready() -> void:
	_build_environment()
	road_mat = KartLook.material("road.gdshader")
	road_mat.set_shader_parameter("kerb_width", KartTrackModel.KERB_WIDTH)
	road_mat.set_shader_parameter("grid_first", KartRaceLogic.GRID_FIRST)
	road_mat.set_shader_parameter("grid_gap", KartRaceLogic.GRID_GAP)
	road_mat.set_shader_parameter("grid_d", KartRaceLogic.GRID_D)
	ground_mat = KartLook.material("ground.gdshader")
	scenery_mat = KartLook.material("scenery.gdshader")
	foliage_mat = KartLook.material("scenery.gdshader")
	foliage_mat.set_shader_parameter("sway", 0.22)
	props_mat = KartLook.material("scenery.gdshader")
	props_mat.set_shader_parameter("alpha_glow", true)
	tint_mat = KartLook.material("scenery.gdshader")
	tint_mat.set_shader_parameter("tint_custom", true)
	flag_mat = KartLook.material("flag.gdshader")
	flag_mat.set_shader_parameter("tint_custom", true)
	banner_mat = KartLook.material("flag.gdshader")
	banner_mat.set_shader_parameter("hang", 1.0)
	banner_mat.set_shader_parameter("amplitude", 0.12)
	banner_mat.set_shader_parameter("speed", 3.0)
	crowd_mat = KartLook.material("crowd.gdshader")
	crowd_mat.set_shader_parameter("sprite", KartStartArea.crowd_sprite())
	water_mat = KartLook.material("water.gdshader")
	pads_mat = KartLook.material("pads.gdshader")
	lamps_mat = ShaderMaterial.new()
	lamps_mat.shader = KartLook.shader("lamps.gdshader")


## (Re)builds everything for `model` (a new track, or the same one reversed).
func build(model: KartTrackModel) -> void:
	track = model
	KartLook.set_theme(track.def.theme)
	look = KartLook.look
	_apply_theme()
	if _built:
		_built.queue_free()
	_built = Node3D.new()
	_built.name = "Track"
	add_child(_built)
	_spinners.clear()
	_spin_rates.clear()
	_stand_lamps.clear()
	_foliage_cells.clear()
	_crowd = null
	_measure()
	dress = KartDress.for_theme(track.def.theme)
	dress.world = self
	dress.rng.seed = hash(track.def.id) + (1 if track.reversed else 0)
	terrain = KartTerrain.new(track, centre, dress.base_height)

	road_mat.set_shader_parameter("track_length", track.length)
	var road := MeshKit3D.mesh_node(KartRoadMeshes.road(track), road_mat, "Road")
	road.visible = tuning.get("road", true)
	_built.add_child(road)
	var paint := KartRoadMeshes.paint(track)
	if paint:
		var pads := MeshKit3D.mesh_node(paint, pads_mat, "Pads")
		pads.visible = road.visible
		_built.add_child(pads)
	var walls := MeshKit3D.mesh_node(KartRoadMeshes.walls(track, look), props_mat, "Barriers")
	walls.visible = tuning.get("walls", true)
	_built.add_child(walls)
	var ground := Node3D.new()
	ground.name = "Ground"
	ground.visible = tuning.get("ground", true)
	_built.add_child(ground)
	ground.add_child(MeshKit3D.mesh_node(
		terrain.mesh(reach + 60.0, reach + 600.0, look.get("far_tint", Color(0.86, 0.92, 1.0)), dress.ground_tint), ground_mat, "Land"))
	ground.add_child(MeshKit3D.mesh_node(KartRoadMeshes.skirt(track, terrain), ground_mat, "Skirts"))

	var scenery := Node3D.new()
	scenery.name = "Scenery"
	scenery.visible = tuning.get("scenery", true)
	_built.add_child(scenery)
	var foliage := {}
	var props := {}
	var woods := sector_kits()
	KartTrackside.build(self, props)
	# The hero set piece and the grandstand first: the title shot is solved round them, and the
	# scattered scenery then keeps out of its sight line (KartDress.in_hero_sight).
	dress.dress_hero(scenery, props)
	if tuning.get("stand", true):
		_crowd = KartStartArea.build_grandstand(self, scenery, _stand_lamps)
	grid_shot = solve_grid_shot()
	dress.dress(scenery, foliage, props, woods)
	if tuning.get("foliage", true):
		commit_cells(scenery, foliage, "Foliage", foliage_mat)
	if tuning.get("props", true):
		commit_cells(scenery, props, "Props", props_mat)
	if tuning.get("woods", true):
		commit_sectors(scenery, woods, "Woods", foliage_mat)
	_halos = KartStartArea.build_gate(self, scenery)
	KartStartArea.build_flags(self, scenery)
	if tuning.get("clouds", true):
		KartClouds.build(scenery, look, centre)
	ground_mat.set_shader_parameter("detail", 1.0 if tuning.get("ground_detail", true) else 0.0)
	set_start_lights(0)
	set_quality(foliage_range, crowd_share)


## The quality governor's world trims: how far foliage cells are drawn (metres), and the share
## of the crowd shown (the instances are shuffled, so any share thins evenly). Instant: no
## rebuild, so it can change mid-race.
func set_quality(foliage_m: float, crowd: float) -> void:
	foliage_range = foliage_m
	crowd_share = clampf(crowd, 0.0, 1.0)
	for node in _foliage_cells:
		node.visibility_range_end = foliage_range
	if _crowd:
		_crowd.visible_instance_count = roundi(_crowd.instance_count * crowd_share)


## The start gantry: 0 dark, 1-5 red lamps lit, 6 all green.
func set_start_lights(stage: int) -> void:
	lamps_mat.set_shader_parameter("stage", stage)
	if _halos:
		var mm := _halos.multimesh
		mm.visible_instance_count = mini(stage, 5) if stage < 6 else 5
		var color := Color(1.0, 0.25, 0.15, 0.85) if stage < 6 else Color(0.4, 1.0, 0.5, 0.85)
		for i in mm.instance_count:
			mm.set_instance_color(i, color)


## Environment glow (a dev switch, KartRace's tuning file [render] glow): two levels over the
## bright sky, lines and lamps. Off by default: the faked additive halos cost nothing.
func set_glow(on: bool) -> void:
	var env := _env.environment
	env.glow_enabled = on
	env.glow_intensity = 0.7
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 0.85
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, 1.0 if i == 1 or i == 2 else 0.0)


## Turns `node` about its local `axis` at `rate` rad/s every frame (windmill sails, a lighthouse
## lamp, a ski lift's wheel).
func spin(node: Node3D, axis: Vector3, rate: float) -> void:
	_spinners.append(node)
	_spin_rates.append(axis.normalized() * rate)


func _process(delta: float) -> void:
	for i in _spinners.size():
		var r := _spin_rates[i]
		_spinners[i].rotate_object_local(r.normalized(), r.length() * delta)


## The most draw calls the built track can issue (every mesh and multimesh node under it; the
## frustum and the visibility ranges cull many in play), and its triangles. The sky adds one.
func draw_budget() -> Dictionary:
	var calls := 1
	var tris := 0
	var stack: Array[Node] = [_built]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if n is MeshInstance3D and n.mesh:
			calls += n.mesh.get_surface_count() * (2 if n.material_override and n.material_override.next_pass else 1)
			tris += _tris(n.mesh)
		elif n is MultiMeshInstance3D and n.multimesh and n.multimesh.mesh:
			calls += 1
			tris += _tris(n.multimesh.mesh) * n.multimesh.instance_count
	return {"calls": calls, "triangles": tris}


static func _tris(mesh: Mesh) -> int:
	var t := 0
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var idx = arrays[Mesh.ARRAY_INDEX]
		t += (idx.size() if idx != null and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	return t


# --- The title shot (KartGridShot) ---

## Searches camera spots round the grid for the one that frames the dresser's hero piece
## (KartDress.hero) over the karts on the grid. Runs once per build (pure maths): nothing per frame.
func solve_grid_shot() -> Dictionary:
	return KartGridShot.solve(self)


## Where a world point lands in the 1920×1080 frame of a camera at `eye` looking at `look_at`
## with vertical `fov` (degrees): (x, y, depth); depth < 0 when behind the lens.
static func shot_project(eye: Vector3, look_at: Vector3, fov: float, p: Vector3) -> Vector3:
	return KartGridShot.project(eye, look_at, fov, p)


## The screen rects of the karts on the grid in that shot (KartGridShot.kart_rects).
func shot_kart_rects(eye: Vector3, look_at: Vector3, fov: float) -> Array[Rect2]:
	return KartGridShot.kart_rects(track, eye, look_at, fov)


## How good a title shot is (-INF: unusable; KartGridShot.rate).
func shot_score(eye: Vector3, look_at: Vector3, fov: float, focus: Vector3, size: float) -> float:
	return KartGridShot.rate(self, eye, look_at, fov, focus, size)


## Whether this build has a grandstand (the "stand" dev switch).
func has_grandstand() -> bool:
	return _built.get_node_or_null("Scenery/Grandstand") != null


# --- Placement helpers (for the dressers) ---

## A spot `out` metres beyond the barrier at s on `side`, at least `clearance` beyond every
## barrier, on the ground. Null when another stretch of road is too close.
func beyond(s: float, side: float, out: float, clearance := TREE_CLEARANCE) -> Variant:
	var edge := track.half_width(s) + track.verge
	var p := track.position_at(track.wrap(s), side * (edge + out))
	if not clear_of_road(p, clearance):
		return null
	p.y = terrain.height_at(p.x, p.z)
	return p


## Whether (x, z) is at least `clearance` metres beyond every barrier.
func clear_of_road(p: Vector3, clearance: float) -> bool:
	var rough := terrain.road_clearance(p.x, p.z)
	if rough > clearance + 12.0:
		return true
	if rough < clearance - 12.0:
		return false
	var near := track.project(p)
	return absf(near.d) >= track.half_width(near.s) + track.verge + clearance


## The ground's height at (x, z).
func ground_at(x: float, z: float) -> float:
	return terrain.height_at(x, z)


## Where the track def's first landmark of `type` is: {p (on the ground), s, d (this
## direction's), dir (the road's horizontal direction there), out (horizontal, from the road
## toward p), r}; empty when the track has none.
func landmark(type: String) -> Dictionary:
	var all := landmarks(type)
	return all[0] if not all.is_empty() else {}


## Every landmark of `type`, each as `landmark` gives it (plus the def's own keys).
func landmarks(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for lm in track.def.landmarks:
		if lm.type != type:
			continue
		var s0 := float(lm.s) - track.def.start_s
		var s := fposmod(-s0, track.length) if track.reversed else fposmod(s0, track.length)
		var d := -float(lm.get("d", 0.0)) if track.reversed else float(lm.get("d", 0.0))
		var on := track.position_at(s, 0.0)
		var p := track.position_at(s, d)
		var pt := track.sample(s)
		var out_dir := Vector3(p.x - on.x, 0.0, p.z - on.z)
		out_dir = out_dir.normalized() if out_dir.length() > 0.01 else pt.right
		p.y = terrain.height_at(p.x, p.z) if terrain else p.y
		var info: Dictionary = lm.duplicate()
		info.merge({"p": p, "s": s, "d": d, "dir": Vector3(pt.tangent.x, 0.0, pt.tangent.z).normalized(),
			"out": out_dir, "r": float(lm.get("r", 0.0))}, true)
		out.append(info)
	return out


## Whether s is along the grandstand (outside the start straight).
func in_stand(s: float) -> bool:
	var ss := s - track.length if s > track.length * 0.5 else s
	return ss > -70.0 and ss < 26.0


func sector_of(p: Vector3) -> int:
	var a := atan2(p.z - centre.z, p.x - centre.x)
	return posmod(int(floor((a + PI) / TAU * SECTORS)), SECTORS)


func sector_kits() -> Array:
	var kits := []
	for i in SECTORS:
		kits.append(MeshKit3D.new())
	return kits


func commit_sectors(parent: Node3D, kits: Array, node_name: String, mat: Material) -> void:
	for i in kits.size():
		var kit: MeshKit3D = kits[i]
		if not kit.is_empty():
			parent.add_child(MeshKit3D.mesh_node(kit.commit(), mat, "%s%d" % [node_name, i]))


## The trackside cell kit for `p` (created on demand).
func cell(cells: Dictionary, p: Vector3) -> MeshKit3D:
	var key := Vector2i(floori((p.x - centre.x) / CELL), floori((p.z - centre.z) / CELL))
	if not cells.has(key):
		cells[key] = MeshKit3D.new()
	return cells[key]


func commit_cells(parent: Node3D, cells: Dictionary, node_name: String, mat: Material) -> void:
	for key: Vector2i in cells:
		var kit: MeshKit3D = cells[key]
		if kit.is_empty():
			continue
		# The node sits at the cell's centre (vertices moved to match), so its visibility range
		# measures from the cell and not from the world's origin.
		var at := Vector3(centre.x + (key.x + 0.5) * CELL, centre.y, centre.z + (key.y + 0.5) * CELL)
		var arrays := kit.commit().surface_get_arrays(0)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in verts.size():
			verts[i] -= at
		arrays[Mesh.ARRAY_VERTEX] = verts
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var node := MeshKit3D.mesh_node(mesh, mat, "%s_%d_%d" % [node_name, key.x, key.y])
		node.position = at
		node.visibility_range_end = CELL_RANGE
		node.visibility_range_end_margin = 20.0
		parent.add_child(node)
		if node_name == "Foliage":
			_foliage_cells.append(node)


func mm(mesh: Mesh, xfs: Array, node_name: String, mat: Material, custom: Array = [], colors: Array = []) -> MultiMeshInstance3D:
	var node := MeshKit3D.multimesh_node(mesh, xfs, node_name, custom, colors)
	node.material_override = mat
	return node


# --- Environment ---

func _build_environment() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = KartLook.shader("sky.gdshader")
	_sky_mat.set_shader_parameter("noise_tex", KartLook.noise())
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = KartLook.SKY_AMBIENT
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env = WorldEnvironment.new()
	_env.name = "Environment"
	_env.environment = env
	add_child(_env)


## Sets the current theme's colours on the sky, road, ground and water.
func _apply_theme() -> void:
	KartLook.apply(_sky_mat, SKY_DEFAULTS.merged(look.sky, true))
	_sky_mat.set_shader_parameter("sun_dir", KartLook.sun_dir())
	# The materials outlive a track: a theme's optional keys fall back to their defaults.
	KartLook.apply(road_mat, ROAD_DEFAULTS.merged(look.road, true))
	KartLook.apply(ground_mat, GROUND_DEFAULTS.merged(look.ground, true))
	if look.has("water"):
		KartLook.apply(water_mat, look.water)
	_env.environment.ambient_light_color = look.light.sky_color


## The track's bounding box: its centre (at ground level) and reach.
func _measure() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	var ylo := INF
	var s := 0.0
	while s < track.length:
		var p := track.sample(s).position
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
		ylo = minf(ylo, p.y)
		s += 10.0
	centre = Vector3((lo.x + hi.x) * 0.5, ylo - 0.6, (lo.y + hi.y) * 0.5)
	reach = maxf(hi.x - lo.x, hi.y - lo.y) * 0.5


# --- Shared meshes and data (KartStartArea) ---

## The crowd's instances (KartStartArea.crowd_data).
static func crowd_data(theme_look: Dictionary, theme: String, rows: int, depth: float, rise: float, length: float) -> Dictionary:
	return KartStartArea.crowd_data(theme_look, theme, rows, depth, rise, length)


## A soft additive billboard (lamp halos; dressers use it for bulbs that should bloom).
static func halo_quad() -> QuadMesh:
	return KartStartArea.halo_quad()


## A flag's cloth, 1.7 × 1.05 m from the pole along +x; UV.x runs along it (the wave grows).
static func flag_cloth() -> ArrayMesh:
	return KartStartArea.flag_cloth()
