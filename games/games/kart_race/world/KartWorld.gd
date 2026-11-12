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

const ROAD_DEFAULTS := {"cobbles": 0.0, "verge_grain": 0.3, "verge_gain": 1.0}
const GROUND_DEFAULTS := {"snow": 0.0, "grain": 0.24}
const SKY_DEFAULTS := {"glare": 0.55, "halo": 0.18}
const ROAD_STEP := 2.0  ## metres between mesh rows along the track
const SKIRT := 8.0  ## the skirt from the barrier's foot out and down under the land
const WALL_HEIGHT := 0.95
const TREE_CLEARANCE := 5.0  ## trees keep this far beyond the barrier
const SECTORS := 12
const CELL := 110.0
const CELL_RANGE := 230.0
## The quality governor's trims (KartQualityGovernor): foliage cells drawn to this range, and
## this share of the crowd.
const CELL_RANGE_TRIMMED := 150.0
const CROWD_TRIMMED := 0.5

## The grid shot's frame (the HUD's pixels) and what covers it during the title: karts stay clear
## of the title band; the landmark of the band and the framework's clock and buttons (top right).
const SHOT_SIZE := Vector2(1920.0, 1080.0)
## KartHud's title card band (bottom left, in the HUD's 1920×1080 pixels).
const TITLE_BAND := Rect2(-40.0, 790.0, 1180.0, 240.0)
const SHOT_CORNER := Rect2(1240.0, 0.0, 680.0, 310.0)
const SHOT_KART := Vector3(0.85, 1.4, 1.15)  ## a kart and driver's half-width, height, half-length
const GRID_KARTS := 8
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
	crowd_mat.set_shader_parameter("sprite", _crowd_sprite())
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
	var road := MeshKit3D.mesh_node(_road_mesh(), road_mat, "Road")
	road.visible = tuning.get("road", true)
	_built.add_child(road)
	var paint := _paint_mesh()
	if paint:
		var pads := MeshKit3D.mesh_node(paint, pads_mat, "Pads")
		pads.visible = road.visible
		_built.add_child(pads)
	var walls := MeshKit3D.mesh_node(_wall_mesh(), props_mat, "Barriers")
	walls.visible = tuning.get("walls", true)
	_built.add_child(walls)
	var ground := Node3D.new()
	ground.name = "Ground"
	ground.visible = tuning.get("ground", true)
	_built.add_child(ground)
	ground.add_child(MeshKit3D.mesh_node(
		terrain.mesh(reach + 60.0, reach + 600.0, look.get("far_tint", Color(0.86, 0.92, 1.0)), dress.ground_tint), ground_mat, "Land"))
	ground.add_child(MeshKit3D.mesh_node(_skirt_mesh(), ground_mat, "Skirts"))

	var scenery := Node3D.new()
	scenery.name = "Scenery"
	scenery.visible = tuning.get("scenery", true)
	_built.add_child(scenery)
	var foliage := {}
	var props := {}
	var woods := sector_kits()
	_build_track_furniture(props)
	# The hero set piece and the grandstand first: the title shot is solved round them, and the
	# scattered scenery then keeps out of its sight line (KartDress.in_hero_sight).
	dress.dress_hero(scenery, props)
	if tuning.get("stand", true):
		_build_grandstand(scenery)
	grid_shot = solve_grid_shot()
	dress.dress(scenery, foliage, props, woods)
	if tuning.get("foliage", true):
		commit_cells(scenery, foliage, "Foliage", foliage_mat)
	if tuning.get("props", true):
		commit_cells(scenery, props, "Props", props_mat)
	if tuning.get("woods", true):
		commit_sectors(scenery, woods, "Woods", foliage_mat)
	_build_gate(scenery)
	_build_flags(scenery)
	if tuning.get("clouds", true):
		_build_clouds(scenery)
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


# --- The title shot ---

## Searches camera spots round the grid for the one that frames the dresser's hero piece
## (KartDress.hero) over the karts on the grid: the piece clear of the HUD, on a third; no kart
## under the title band or half off the frame; as many karts in shot as possible. Runs once per
## build (a few hundred candidates, pure maths): nothing per frame.
func solve_grid_shot() -> Dictionary:
	if dress == null or dress.hero.is_empty():
		return {}
	var focus: Vector3 = dress.hero.p
	var size: float = dress.hero.get("size", 10.0)
	var g := track.position_at(track.wrap(-22.0), 0.0)
	var eyes: Array[Vector3] = []
	for b in 16:
		var a := TAU * b / 16.0
		for dist: float in [11.0, 15.0, 20.0]:
			for h: float in [2.6, 4.5, 7.5, 12.0]:
				eyes.append(g + Vector3(cos(a), 0.0, sin(a)) * dist + Vector3.UP * h)
	if dress.hero.get("flat", false):
		# A lake: also from beyond its far shore, looking back across the ice to the grid.
		var across := Vector3(focus.x - g.x, 0.0, focus.z - g.z).normalized()
		for turn: float in [-0.5, -0.25, 0.0, 0.25, 0.5]:
			for k: float in [0.6, 0.9, 1.2]:
				for h: float in [6.0, 10.0, 14.0]:
					var at := focus + across.rotated(Vector3.UP, turn) * size * k
					eyes.append(Vector3(at.x, terrain.height_at(at.x, at.z) + h, at.z))
	var best := {}
	var best_score := -INF
	for eye in eyes:
		if not _shot_eye_ok(eye):
			continue
		for w: float in [0.3, 0.45, 0.6, 0.75]:
			var dir := (g + Vector3.UP * 0.6 - eye).normalized() * (1.0 - w) + (focus - eye).normalized() * w
			var look_at := eye + dir.normalized() * 10.0
			for fov: float in [46.0, 54.0, 62.0]:
				var score := shot_score(eye, look_at, fov, focus, size)
				if score > best_score:
					best_score = score
					best = {"eye": eye, "look": look_at, "fov": fov, "focus": focus, "score": score}
	return best if best_score > -INF else {}


## Where a world point lands in the 1920×1080 frame of a camera at `eye` looking at `look_at`
## with vertical `fov` (degrees): (x, y, depth); depth < 0 when behind the lens.
static func shot_project(eye: Vector3, look_at: Vector3, fov: float, p: Vector3) -> Vector3:
	var basis := Basis.looking_at(look_at - eye, Vector3.UP)
	var local := basis.transposed() * (p - eye)
	if local.z > -0.1:
		return Vector3(0.0, 0.0, -1.0)
	var t := tan(deg_to_rad(fov) * 0.5)
	var x := local.x / -local.z / (t * SHOT_SIZE.x / SHOT_SIZE.y)
	var y := local.y / -local.z / t
	return Vector3((x * 0.5 + 0.5) * SHOT_SIZE.x, (0.5 - y * 0.5) * SHOT_SIZE.y, -local.z)


## The screen rects of the karts on the grid in that shot; an empty Rect2 for a kart wholly
## behind the lens, and a zero-size one at (-1, -1) for a kart the lens is inside or too near.
func shot_kart_rects(eye: Vector3, look_at: Vector3, fov: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in GRID_KARTS:
		var s := track.wrap(-(KartRaceLogic.GRID_FIRST + KartRaceLogic.GRID_GAP * i))
		var d := -KartRaceLogic.GRID_D if i % 2 == 0 else KartRaceLogic.GRID_D
		var pt := track.sample(s)
		var at := track.position_at(s, d)
		var fwd := Vector3(pt.tangent.x, 0.0, pt.tangent.z).normalized()
		var right := Vector3(pt.right.x, 0.0, pt.right.z).normalized()
		if at.distance_to(eye) < 6.0:
			out.append(Rect2(-1.0, -1.0, 0.0, 0.0))
			continue
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		var behind := 0
		for corner in 8:
			var p := at + right * SHOT_KART.x * (1.0 if corner & 1 else -1.0) \
				+ fwd * SHOT_KART.z * (1.0 if corner & 2 else -1.0) + Vector3.UP * (SHOT_KART.y if corner & 4 else 0.0)
			var q := shot_project(eye, look_at, fov, p)
			if q.z < 0.0:
				behind += 1
				continue
			lo = Vector2(minf(lo.x, q.x), minf(lo.y, q.y))
			hi = Vector2(maxf(hi.x, q.x), maxf(hi.y, q.y))
		if behind == 8:
			out.append(Rect2())
		elif behind > 0:
			out.append(Rect2(-1.0, -1.0, 0.0, 0.0))
		else:
			out.append(Rect2(lo, hi - lo))
	return out


## How good a title shot is (-INF: unusable). Unusable: the hero piece off its framing area,
## under the HUD or hidden by the land; a kart under the title band or the lens inside one;
## fewer than four karts in shot. Better: more karts wholly in shot, the piece on a third and
## big enough to read.
func shot_score(eye: Vector3, look_at: Vector3, fov: float, focus: Vector3, size: float) -> float:
	var band := TITLE_BAND.grow(16.0)
	var screen := Rect2(Vector2.ZERO, SHOT_SIZE)
	var fp := shot_project(eye, look_at, fov, focus)
	# A flat piece (a lake) is seen from above, and may fill the foreground: aim lower.
	var flat: bool = dress.hero.get("flat", false) if dress else false
	if flat and (eye.y - focus.y) < 0.15 * Vector2(eye.x - focus.x, eye.z - focus.z).length():
		return -INF
	var aim_y := 0.62 if flat else 0.32
	if fp.z < 0.0 or fp.x < SHOT_SIZE.x * 0.08 or fp.x > SHOT_SIZE.x * 0.92 or fp.y < SHOT_SIZE.y * 0.08 \
			or fp.y > SHOT_SIZE.y * (0.85 if flat else 0.66):
		return -INF
	if SHOT_CORNER.grow(40.0).has_point(Vector2(fp.x, fp.y)) or band.has_point(Vector2(fp.x, fp.y)):
		return -INF
	if not _line_of_sight(eye, focus):
		return -INF
	var whole := 0
	var cut := 0
	var tall := 0.0
	for r in shot_kart_rects(eye, look_at, fov):
		if r.position.x == -1.0 and r.size == Vector2.ZERO:
			return -INF
		if r.size == Vector2.ZERO or not r.intersects(screen):
			continue
		if r.intersects(band):
			return -INF
		if screen.encloses(r):
			whole += 1
			tall += r.size.y / SHOT_SIZE.y
		else:
			cut += 1
	if whole < 4:
		return -INF
	var thirds := minf(absf(fp.x / SHOT_SIZE.x - 0.66), absf(fp.x / SHOT_SIZE.x - 0.34))
	var px := size / maxf(fp.z, 1.0) / tan(deg_to_rad(fov) * 0.5) * 0.5
	# The karts big enough to read (a tenth of the frame's height, on average, is plenty).
	var kart_size := 30.0 * minf(tall / maxf(whole, 1.0), 0.1)
	return whole + kart_size - 0.6 * cut - 3.0 * thirds - 2.0 * absf(fp.y / SHOT_SIZE.y - aim_y) + 4.0 * minf(px, 0.25) \
		- 0.04 * eye.distance_to(track.position_at(track.wrap(-22.0), 0.0)) \
		+ float(dress.hero.get("lift", 0.0) if dress else 0.0) * (eye.y - track.position_at(track.wrap(-22.0), 0.0).y) / 12.0


## A camera spot for the title: above the land, on the road side of the barriers (low), clear of
## the grandstand and the gate.
func _shot_eye_ok(eye: Vector3) -> bool:
	if eye.y < terrain.height_at(eye.x, eye.z) + 1.5:
		return false
	var near := track.project(eye)
	var edge := track.half_width(near.s) + track.verge
	var height := eye.y - near.position.y
	if absf(near.d) > edge - 0.5 and height < 10.0:
		return false
	if near.d > edge - 0.5 and in_stand(near.s):
		return false
	var ss := near.s - track.length if near.s > track.length * 0.5 else near.s
	# Not beside a flag pole (they line the start: _build_flags) or in the gate.
	if ss > -72.0 and ss < 42.0 and absf(absf(near.d) - (edge + 1.2)) < 3.0:
		return false
	return absf(ss - 1.0) > 3.0 or height > 9.0


## Whether the land leaves the line from `a` to `b` clear (sampled; the far end's last 10% is
## the piece itself, so it isn't tested).
func _line_of_sight(a: Vector3, b: Vector3) -> bool:
	var stand := stand_xf.affine_inverse()
	var has_stand := _built.get_node_or_null("Scenery/Grandstand") != null
	for i in range(1, 22):
		var p := a.lerp(b, i / 23.0)
		if terrain.height_at(p.x, p.z) > p.y + 0.5:
			return false
		if has_stand:
			var q := stand * p
			if q.x > -3.0 and q.x < 10.0 and q.y < 10.5 and absf(q.z) < STAND_LENGTH * 0.5 + 1.0:
				return false
	return true


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


# --- Road ---

## Rows every ROAD_STEP metres, columns at the road edges, kerbs and barrier feet. UV = (d, s),
## UV2.x = half-width, COLOR = (racing line, corner strength).
func _road_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rows := maxi(8, roundi(track.length / ROAD_STEP))
	var step := track.length / rows
	var kerb := KartTrackModel.KERB_WIDTH
	var cols := []  # per row: [s, hw, [d...], color]
	for i in rows + 1:
		var s := i * step
		var hw := track.half_width(s)
		var edge := hw + track.verge
		var line := clampf(track.racing_line(s), -10.0, 10.0)
		var corner := clampf(absf(track.curvature(s)) * 45.0, 0.0, 1.0)
		cols.append([s, hw, [-edge, -hw - kerb, -hw, 0.0, hw, hw + kerb, edge],
			Color((line + 10.0) / 20.0, corner, 0.0)])
	for i in rows:
		var a: Array = cols[i]
		var b: Array = cols[i + 1]
		for c in 6:
			var p := [[a, c], [b, c], [b, c + 1], [a, c], [b, c + 1], [a, c + 1]]
			for v in p:
				var row: Array = v[0]
				var d: float = row[2][v[1]]
				var s: float = row[0]
				st.set_color(row[3])
				st.set_uv(Vector2(d, s))
				st.set_uv2(Vector2(row[1], 0.0))
				st.set_normal(Vector3.UP)
				st.add_vertex(track.position_at(fmod(s, track.length), d))
	return st.commit()


## Boost pads and item rows: quads 3 cm over the road, painted by pads.gdshader. UV = (across,
## along) 0-1; COLOR.r = kind (0 pad, 1 item row), COLOR.g = length / 20 m.
func _paint_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for z in track.zones:
		var kind := -1.0
		var d0 := 0.0
		var d1 := 0.0
		var s0 := float(z.s0)
		var s1 := float(z.s1)
		if z.type == "boost":
			kind = 0.0
			var c := float(z.get("d", 0.0))
			var w := float(z.get("w", 1.4))
			d0 = c - w
			d1 = c + w
		elif z.type == "items":
			kind = 1.0
			var mid := s0 + track.delta(s0, s1) * 0.5
			s0 = mid - 1.1
			s1 = mid + 1.1
			var hw := track.half_width(track.wrap(mid))
			d0 = -hw + 0.4
			d1 = hw - 0.4
		if kind < 0.0:
			continue
		any = true
		var length := track.delta(s0, s1)
		if length < 0.0:
			length += track.length
		var steps := maxi(1, ceili(length / 2.0))
		for k in steps:
			var a := s0 + length * k / steps
			var b := s0 + length * (k + 1) / steps
			var va := float(k) / steps
			var vb := float(k + 1) / steps
			var col := Color(kind, length / 20.0, 0.0)
			var quad := [[a, d0, 0.0, va], [b, d0, 0.0, vb], [b, d1, 1.0, vb], [a, d0, 0.0, va], [b, d1, 1.0, vb], [a, d1, 1.0, va]]
			for q in quad:
				st.set_color(col)
				st.set_uv(Vector2(q[2], q[3]))
				st.set_normal(Vector3.UP)
				st.add_vertex(track.position_at(track.wrap(q[0]), q[1]) + Vector3.UP * 0.03)
	return st.commit() if any else null


## The barrier: one mesh in props_mat, lit by the sun like scenery (a 0.08 self-glow only). Its
## profile from the road: a dark foot (AO, or tyres), panels alternating in the theme's two
## colours with dark seams every row, the rail as a stripe, a chamfered lighter cap, and a shaded
## back. Per theme (`wall_style`): Meadow's foot is a row of tyres, Canyon's panels are timber
## planks, Harbor's quay wall is stone-footed, and Frost's cap is a fat lip of snow.
func _wall_mesh() -> ArrayMesh:
	var kit := MeshKit3D.new()
	var rows := maxi(8, roundi(track.length / ROAD_STEP))
	var step := track.length / rows
	var style := str(look.get("wall_style", ""))
	var h := WALL_HEIGHT + 0.14
	var cap: Color = look.get("wall_cap", Color(0.9, 0.9, 0.92))
	var foot_c: Color = look.get("wall_foot", Color(0.2, 0.2, 0.22))
	var rail: Color = look.wall_rail
	var lip := 0.1 if style == "snow" else 0.0
	# (out, up) from the barrier's face at the road edge, outward; one colour per segment
	# (null: the panel's colour). The foot runs to 0.2 m, the stripe sits under the cap.
	var prof := [Vector2(0.0, 0.0), Vector2(0.0, 0.2), Vector2(0.0, h - 0.17), Vector2(0.0, h - 0.07),
		Vector2(0.07 - lip, h + lip * 0.6), Vector2(0.38 + lip, h + lip * 0.6), Vector2(0.45, h - 0.07), Vector2(0.45, 0.0)]
	var seg_cols := [foot_c, null, rail, cap.darkened(0.06), cap, cap.darkened(0.2), null]
	for i in rows:
		var s0 := i * step
		var s1 := fmod((i + 1) * step, track.length)
		var panel: Color = look.wall_a if (i >> 1) & 1 == 0 else look.wall_b
		for side: float in [-1.0, 1.0]:
			var e0 := track.half_width(s0) + track.verge
			var e1 := track.half_width(s1) + track.verge
			for j in seg_cols.size():
				var c: Color = panel if seg_cols[j] == null else seg_cols[j]
				if j == seg_cols.size() - 1:
					c = panel.darkened(0.4)
				c.a = 0.08
				var p0: Vector2 = prof[j]
				var p1: Vector2 = prof[j + 1]
				var a0 := track.position_at(s0, side * (e0 + p0.x)) + Vector3.UP * p0.y
				var a1 := track.position_at(s0, side * (e0 + p1.x)) + Vector3.UP * p1.y
				var b0 := track.position_at(s1, side * (e1 + p0.x)) + Vector3.UP * p0.y
				var b1 := track.position_at(s1, side * (e1 + p1.x)) + Vector3.UP * p1.y
				# Wound so each face's front looks out of the barrier's profile (the old wall's were
				# inside out: the road saw its shaded back).
				if side > 0.0:
					kit.quad(b0, b1, a1, a0, c)
				else:
					kit.quad(a0, a1, b1, b0, c)
			# Painted detail on the face, a centimetre proud: a seam at the row's start, and the
			# theme's bands (tyres' treads, timber's plank joints).
			var lines: Array = []  # [up0, up1, s_len (0 = the whole row), colour]
			lines.append([0.2, h - 0.17, 0.08, panel.darkened(0.45)])
			match style:
				"tyres":
					lines.append([0.08, 0.11, 0.0, Color(0.32, 0.32, 0.35)])
				"timber":
					for k in [0.43, 0.66]:
						lines.append([k - 0.012, k + 0.012, 0.0, panel.darkened(0.35)])
				"snow":
					lines.append([0.2, 0.26, 0.0, foot_c.lightened(0.25)])
			for ln: Array in lines:
				var len: float = ln[2] if ln[2] > 0.0 else step
				var sa := s0
				var sb := fmod(s0 + len, track.length)
				var col: Color = ln[3]
				col.a = 0.08
				var ea := track.half_width(sa) + track.verge - 0.01
				var eb := track.half_width(sb) + track.verge - 0.01
				var lo := Vector3.UP * float(ln[0])
				var hi := Vector3.UP * float(ln[1])
				var a := track.position_at(sa, side * ea)
				var b := track.position_at(sb, side * eb)
				if side > 0.0:
					kit.quad(b + lo, b + hi, a + hi, a + lo, col)
				else:
					kit.quad(a + lo, a + hi, b + hi, b + lo, col)
	return kit.commit()


# --- Ground ---

## From the barrier's foot out and down under the land, so the land never shows a seam.
func _skirt_mesh() -> ArrayMesh:
	var rows := maxi(8, roundi(track.length / ROAD_STEP))
	var step := track.length / rows
	var ends := []
	for i in rows:
		var s := i * step
		var row := []
		for side: float in [-1.0, 1.0]:
			var e := track.half_width(s) + track.verge + 0.45
			var foot := track.position_at(s, side * e)
			var end := track.position_at(s, side * (e + SKIRT))
			end.y = minf(foot.y - 0.5, terrain.height_at(end.x, end.z) - 0.35)
			row.append([foot, end])
		ends.append(row)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in rows:
		var a: Array = ends[i]
		var b: Array = ends[(i + 1) % rows]
		for side in 2:
			var p0: Vector3 = a[side][0]
			var p1: Vector3 = b[side][0]
			var p2: Vector3 = b[side][1]
			var p3: Vector3 = a[side][1]
			# Lit as land: the normal faces up whichever way the quad winds.
			var n := (p1 - p0).cross(p3 - p0).normalized()
			if n.y < 0.0:
				n = -n
			for v in [p0, p1, p2, p0, p2, p3]:
				st.set_color(Color.WHITE)
				st.set_normal(n)
				st.add_vertex(v)
	return st.commit()


# --- Track furniture ---

## Item-row pylons, climb signs and corner chevrons, baked into the trackside props.
func _build_track_furniture(props: Dictionary) -> void:
	var pylon := _pylon_mesh()
	var sign := _climb_sign_mesh()
	for z in track.zones:
		if z.type == "items":
			var mid := track.wrap(float(z.s0) + track.delta(z.s0, z.s1) * 0.5)
			for side: float in [-1.0, 1.0]:
				var p := track.position_at(mid, side * (track.half_width(mid) + KartTrackModel.KERB_WIDTH + 1.2))
				cell(props, p).add_baked(pylon, Transform3D(Basis(Vector3.UP, track.yaw_at(mid)), p))
		elif z.type == "climb":
			var s := track.wrap(float(z.s0) - 12.0)
			for side: float in [-1.0, 1.0]:
				var p := track.position_at(s, side * (track.half_width(s) + track.verge - 0.6))
				# Facing the oncoming karts.
				cell(props, p).add_baked(sign, Transform3D(Basis(Vector3.UP, track.yaw_at(s)), p))
	_build_chevrons(props)


## Chevron boards on the barrier round the outside of tight corners, pointing the way.
func _build_chevrons(props: Dictionary) -> void:
	var left := _chevron_mesh(1.0)
	var right := _chevron_mesh(-1.0)
	var s := 0.0
	while s < track.length:
		var k := track.curvature(s)
		if absf(k) > 1.0 / 32.0 and not in_stand(s):
			var side := signf(k)  # the outside (+ curvature turns left: the right edge)
			var p := track.position_at(s, side * (track.half_width(s) + track.verge - 0.05))
			# The board's front (+z) faces the road.
			var face := -track.sample(s).right * side
			var basis := Basis(Vector3.UP.cross(face), Vector3.UP, face)
			cell(props, p).add_baked(left if k > 0.0 else right, Transform3D(basis, p))
			s += 5.0
		else:
			s += 2.0


## A board facing +z (from the outside wall toward the road), its arrow pointing along -x for
## `dir` = 1 (the board's left as seen from the road).
func _chevron_mesh(dir: float) -> ArrayMesh:
	var kit := MeshKit3D.new()
	var back := Color(0.08, 0.08, 0.1, 0.0)
	var yellow := Color(1.0, 0.8, 0.1, 0.35)
	kit.add(MeshKit3D.box(Vector3(1.9, 1.1, 0.08)), MeshKit3D.xf(Vector3(0, 1.75, 0)), back)
	kit.add(MeshKit3D.box(Vector3(0.1, 1.3, 0.1)), MeshKit3D.xf(Vector3(-0.6, 0.65, -0.05)), Color(0.5, 0.5, 0.52, 0.0))
	kit.add(MeshKit3D.box(Vector3(0.1, 1.3, 0.1)), MeshKit3D.xf(Vector3(0.6, 0.65, -0.05)), Color(0.5, 0.5, 0.52, 0.0))
	for k in 2:
		var x := (-0.35 + k * 0.6) * dir
		for half: float in [-1.0, 1.0]:
			# Each chevron: two slanted bars meeting at the point.
			kit.add(MeshKit3D.box(Vector3(0.5, 0.16, 0.04)),
				MeshKit3D.xf(Vector3(x + 0.12 * dir, 1.75 + half * 0.2, 0.05), Vector3(0, 0, half * 42.0 * dir)), yellow)
	return kit.commit()


## An item-row pylon: a striped post with a glowing orb.
func _pylon_mesh() -> ArrayMesh:
	var kit := MeshKit3D.new()
	kit.add(MeshKit3D.cylinder(0.16, 0.22, 1.6, 8), MeshKit3D.xf(Vector3(0, 0.8, 0)), Color(0.96, 0.96, 0.98, 0.0))
	for k in 3:
		kit.add(MeshKit3D.cylinder(0.2, 0.21, 0.18, 8), MeshKit3D.xf(Vector3(0, 0.35 + k * 0.45, 0)), Color(0.55, 0.3, 0.95, 0.0))
	kit.add(MeshKit3D.sphere(0.32, 10, 5), MeshKit3D.xf(Vector3(0, 1.85, 0)), Color(0.75, 0.55, 1.0, 1.0))
	kit.add(MeshKit3D.cylinder(0.32, 0.36, 0.14, 8), MeshKit3D.xf(Vector3(0, 0.07, 0)), Color(0.2, 0.2, 0.24, 0.0))
	return kit.commit()


## The climb sign: a yellow board on two posts with a mountain and an up-arrow, facing the
## oncoming karts (+z).
func _climb_sign_mesh() -> ArrayMesh:
	var kit := MeshKit3D.new()
	var post := Color(0.55, 0.55, 0.58, 0.0)
	var board := Color(1.0, 0.78, 0.1, 0.25)
	var ink := Color(0.1, 0.1, 0.12, 0.0)
	for x: float in [-0.75, 0.75]:
		kit.add(MeshKit3D.box(Vector3(0.12, 2.4, 0.12)), MeshKit3D.xf(Vector3(x, 1.2, -0.05)), post)
	kit.add(MeshKit3D.box(Vector3(2.2, 1.5, 0.08)), MeshKit3D.xf(Vector3(0, 2.4, 0)), board)
	kit.add(MeshKit3D.box(Vector3(2.3, 1.6, 0.06)), MeshKit3D.xf(Vector3(0, 2.4, -0.02)), ink)
	# The mountain: a slope up to the right.
	kit.quad(Vector3(-0.9, 1.85, 0.05), Vector3(0.9, 2.55, 0.05), Vector3(0.9, 1.85, 0.05), Vector3(-0.9, 1.85, 0.05), ink)
	# The arrow: a shaft and a head, pointing up.
	kit.add(MeshKit3D.box(Vector3(0.16, 0.6, 0.04)), MeshKit3D.xf(Vector3(-0.45, 2.5, 0.06)), ink)
	kit.quad(Vector3(-0.75, 2.75, 0.06), Vector3(-0.45, 3.05, 0.06), Vector3(-0.15, 2.75, 0.06), Vector3(-0.75, 2.75, 0.06), ink)
	return kit.commit()


# --- The start: grandstand, gate, flags ---

## The grandstand on the outside of the start straight, full of fans, dressed in its theme:
## Meadow's striped canopy, Canyon's awning over red rock, Harbor's lamps, Frost's snow-laden
## roof over wooden benches. Accent banners hang from the roof; flags fly along its back.
func _build_grandstand(parent: Node3D) -> void:
	var s_mid := track.wrap(-22.0)
	var hw := track.half_width(s_mid)
	var yaw := track.yaw_at(s_mid)
	var side := 1.0
	var origin := track.position_at(s_mid, side * (hw + track.verge + 3.2))
	origin.y = track.position_at(s_mid, 0.0).y
	var stand := Node3D.new()
	stand.name = "Grandstand"
	# Local frame: -z along the track (forward), +x away from the road.
	stand.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
	stand_xf = stand.transform
	parent.add_child(stand)
	var theme := KartLook.theme
	var length := STAND_LENGTH
	var rows := STAND_ROWS
	var depth := 0.95
	var rise := 0.6
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 6.0
	kit.ao_min = 0.6
	var concrete := Color(0.78, 0.77, 0.74, 0.0)
	var seat_a: Color = look.stand_a
	var seat_b: Color = look.stand_b
	var roof: Color = look.stand_roof
	var white := Color(0.97, 0.97, 0.97, 0.0)
	var snow := Color(0.95, 0.97, 1.0, 0.0)
	var wood := Color(0.56, 0.38, 0.24, 0.0)
	if theme == "canyon":
		concrete = Color(0.82, 0.66, 0.5, 0.0)  # adobe
	# Footings down to the land, so the stand never floats over a dip.
	kit.add(MeshKit3D.box(Vector3(back_x(rows, depth) + 0.6, 6.0, length)), MeshKit3D.xf(Vector3(back_x(rows, depth) * 0.5, -3.0, 0)), concrete.darkened(0.2))
	# Front wall with a coloured fascia.
	kit.add(MeshKit3D.box(Vector3(0.4, 1.4, length)), MeshKit3D.xf(Vector3(0.0, 0.7, 0)), concrete)
	kit.add(MeshKit3D.box(Vector3(0.45, 0.35, length)), MeshKit3D.xf(Vector3(-0.02, 1.25, 0)), Color(roof.r, roof.g, roof.b, 0.0))
	for r in rows:
		var x := 0.6 + r * depth
		var y := 1.2 + r * rise
		kit.add(MeshKit3D.box(Vector3(depth, y, length)), MeshKit3D.xf(Vector3(x + depth * 0.5, y * 0.5, 0)), concrete)
		if theme == "frost":
			# Wooden benches, a dusting of snow on each.
			var plank: Color = wood if r % 2 == 0 else wood.darkened(0.12)
			kit.add(MeshKit3D.box(Vector3(0.42, 0.12, length)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.3, 0)), plank)
			kit.add(MeshKit3D.box(Vector3(0.44, 0.04, length)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.38, 0)), snow)
			for z in range(-int(length * 0.5) + 2, int(length * 0.5), 6):
				kit.add(MeshKit3D.box(Vector3(0.08, 0.26, 0.08)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.13, z)), wood.darkened(0.3))
		else:
			var seat: Color = seat_a if r % 2 == 0 else seat_b
			kit.add(MeshKit3D.box(Vector3(0.35, 0.22, length)), MeshKit3D.xf(Vector3(x + 0.55, y + 0.11, 0)), Color(seat.r, seat.g, seat.b, 0.0))
	var bx := back_x(rows, depth)
	var top_y := 1.2 + rows * rise
	kit.add(MeshKit3D.box(Vector3(0.4, top_y + 2.6, length)), MeshKit3D.xf(Vector3(bx + 0.2, (top_y + 2.6) * 0.5, 0)), Color(seat_a.r * 0.5, seat_a.g * 0.5, seat_a.b * 0.6, 0.0))
	kit.add(MeshKit3D.box(Vector3(0.1, 0.5, length)), MeshKit3D.xf(Vector3(bx - 0.02, top_y + 0.9, 0)), Color(seat_b.r, seat_b.g, seat_b.b, 0.0))
	# Roof on posts.
	for i in 8:
		var z := -length * 0.5 + 2.0 + i * (length - 4.0) / 7.0
		kit.add(MeshKit3D.cylinder(0.12, 0.12, 4.6, 6), MeshKit3D.xf(Vector3(0.3, top_y + 0.6 - 1.6, z)),
			wood if theme == "frost" else Color(0.9, 0.9, 0.92, 0.0))
	var roof_y := top_y + 2.75
	for i in 12:
		var z0 := -length * 0.5 + i * length / 12.0
		var stripe := white if i % 2 == 0 else Color(roof.r, roof.g, roof.b, 0.0)
		if theme == "frost":
			stripe = Color(roof.r, roof.g, roof.b, 0.0)  # dark timber under the snow
		kit.add(MeshKit3D.box(Vector3(bx + 1.4, 0.25, length / 12.0)),
			MeshKit3D.xf(Vector3(bx * 0.5 + 0.1, roof_y, z0 + length / 24.0), Vector3(0, 0, -7)), stripe)
	match theme:
		"frost":
			# A thick blanket of snow on the roof, rounded at the eave, and icicles under it.
			kit.add(MeshKit3D.box(Vector3(bx + 1.5, 0.45, length + 0.3)), MeshKit3D.xf(Vector3(bx * 0.5 + 0.1, roof_y + 0.3, 0), Vector3(0, 0, -7)), snow)
			kit.add(MeshKit3D.cylinder(0.32, 0.32, length + 0.3, 6), MeshKit3D.xf(Vector3(-0.6, roof_y + 0.08 + 0.1, 0), Vector3(90, 0, 0)), snow)
			var r2 := RandomNumberGenerator.new()
			r2.seed = 17
			var z := -length * 0.5 + 0.5
			while z < length * 0.5:
				var l := r2.randf_range(0.3, 0.8)
				kit.add(MeshKit3D.cylinder(0.06, 0.0, l, 4), MeshKit3D.xf(Vector3(-0.62, roof_y - 0.12 - l * 0.5, z), Vector3(180, 0, 0)), Color(0.8, 0.9, 1.0, 0.3))
				z += r2.randf_range(0.5, 1.4)
		"canyon":
			# The striped awning runs out over the front rows on poles; red rock piles at the ends.
			for i in 12:
				var z0 := -length * 0.5 + i * length / 12.0
				var c := white if i % 2 == 0 else Color(look.gate_band.r, look.gate_band.g, look.gate_band.b, 0.0)
				kit.add(MeshKit3D.box(Vector3(2.6, 0.12, length / 12.0)), MeshKit3D.xf(Vector3(-1.3, roof_y - 0.75, z0 + length / 24.0), Vector3(0, 0, 18)), c)
				var flap := MeshKit3D.prism(Vector3(length / 12.0, 0.5, 0.06))
				kit.add(flap, MeshKit3D.xf(Vector3(-2.55, roof_y - 1.4, z0 + length / 24.0), Vector3(180, 90, 0)), c)
			for z: float in [-length * 0.5 - 4.0, length * 0.5 + 4.0]:
				for k in 3:
					kit.add(KartDress.rock_mesh(Color(0.74, 0.34, 0.2), 40 + k), MeshKit3D.xf(Vector3(1.5 + k * 3.0, -0.5, z + (k - 1) * 1.5), Vector3(0, k * 50, 0), Vector3(3.2, 4.0 + k * 1.6, 3.2) * (1.2 - k * 0.15)), Color(0.74, 0.34, 0.2, 0.0))
		"harbor":
			# Iron lamp posts along the front, lanterns lit (props_mat: alpha is glow).
			var iron := Color(0.14, 0.16, 0.2, 0.0)
			var z := -length * 0.5 + 6.0
			while z < length * 0.5:
				kit.add(MeshKit3D.cylinder(0.08, 0.12, 4.6, 6), MeshKit3D.xf(Vector3(-0.5, 2.3, z)), iron)
				kit.add(MeshKit3D.box(Vector3(0.36, 0.5, 0.36)), MeshKit3D.xf(Vector3(-0.5, 4.75, z)), Color(1.0, 0.86, 0.55, 1.0))
				kit.add(MeshKit3D.prism(Vector3(0.55, 0.3, 0.55)), MeshKit3D.xf(Vector3(-0.5, 5.15, z)), iron)
				_stand_lamps.append(stand.transform * Vector3(-0.5, 4.75, z))
				z += 12.0
	stand.add_child(MeshKit3D.mesh_node(kit.commit(), props_mat, "Stand"))
	if not _stand_lamps.is_empty():
		var halos := []
		var colors := []
		for p: Vector3 in _stand_lamps:
			halos.append(Transform3D(Basis().scaled(Vector3.ONE * 2.6), p))
			colors.append(Color(1.0, 0.75, 0.4, 0.55))
		var lamp_halos := MeshKit3D.multimesh_node(halo_quad(), halos, "StandHalos", [], colors)
		parent.add_child(lamp_halos)
	_build_stand_banners(stand, roof_y, length)
	_build_crowd(stand, rows, depth, rise, length)


## Accent banners hanging from the stand's roof edge (the banner cloth sways).
func _build_stand_banners(stand: Node3D, roof_y: float, length: float) -> void:
	var accents: Array = [look.gate_band, look.stand_roof, look.stand_b, look.stand_a]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var count := 7
	for b in count:
		var z0 := -length * 0.5 + (b + 0.5) * length / count - 0.8
		var c: Color = accents[b % accents.size()]
		var w := 1.6
		var h := 2.3
		var nx := 2
		var ny := 5
		for i in nx:
			for j in ny:
				var u0 := float(i) / nx
				var u1 := float(i + 1) / nx
				var v0 := float(j) / ny
				var v1 := float(j + 1) / ny
				# A white band near the foot, and a pointed tail.
				var col := Color(0.97, 0.97, 0.97) if j == ny - 2 else Color(c.r, c.g, c.b)
				for uv in [[u0, v0], [u1, v0], [u1, v1], [u0, v0], [u1, v1], [u0, v1]]:
					var v: float = uv[1]
					var u: float = uv[0]
					var tail := 0.0
					if j == ny - 1 and v > v0:
						tail = 0.45 * (1.0 - absf(u - 0.5) * 2.0)
					st.set_color(col)
					st.set_uv(Vector2(u, v))
					st.set_normal(Vector3.LEFT)
					st.add_vertex(Vector3(-0.75, roof_y - 0.2 - (v + tail * 0.25) * h, z0 + u * w))
	var node := MeshKit3D.mesh_node(st.commit(), banner_mat, "StandBanners")
	stand.add_child(node)


## The crowd: one MultiMesh of fans (crowd.gdshader). Each row has its own mix of shirts (the
## home colours toward the front, a supporters' block in the theme's accent) and heights; some
## fans wave their arms, and a stadium wave runs along the stand.
## The crowd's instances: {transforms, custom (crowd.gdshader's INSTANCE_CUSTOM), colors (the
## shirts)}, for theme `theme_look` (KartLook's values) named `theme`.
static func crowd_data(theme_look: Dictionary, theme: String, rows: int, depth: float, rise: float, length: float) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var xfs := []
	var custom := []
	var colors := []
	var shirts := [Color(0.95, 0.25, 0.2), Color(1.0, 0.8, 0.2), Color(0.25, 0.55, 1.0), Color(0.3, 0.8, 0.4),
		Color(0.95, 0.5, 0.8), Color(0.98, 0.98, 0.98), Color(0.6, 0.35, 0.9), Color(1.0, 0.55, 0.15), Color(0.2, 0.75, 0.8)]
	var row_tints: Array = [theme_look.stand_a, theme_look.gate_band, theme_look.stand_b, Color(0.98, 0.98, 0.98)]
	if theme == "frost":
		# Winter coats: deeper colours.
		shirts = [Color(0.85, 0.15, 0.2), Color(0.15, 0.35, 0.75), Color(0.2, 0.55, 0.35), Color(0.95, 0.75, 0.2),
			Color(0.45, 0.25, 0.6), Color(0.9, 0.45, 0.15), Color(0.2, 0.2, 0.25)]
	for r in rows:
		var x := 0.6 + r * depth + 0.45
		var y := 1.2 + r * rise - 0.15
		var z := -length * 0.5 + 0.6
		var tint: Color = row_tints[r % row_tints.size()]
		var tint_share := 0.55 if r % 3 == 1 else 0.2
		var row_height := 0.94 + 0.05 * float((r * 7) % 3)
		while z < length * 0.5 - 0.5:
			# Not every seat is taken: the alpha-tested fans are the start's costliest pixels.
			if rng.randf() < 0.7:
				var sc := rng.randf_range(0.92, 1.1)
				xfs.append(Transform3D(Basis().scaled(Vector3.ONE * sc), Vector3(x + rng.randf_range(-0.1, 0.1), y, z)))
				var c: Color = shirts[rng.randi() % shirts.size()]
				colors.append(c.lerp(tint, tint_share))
				var tall := row_height * (0.78 if rng.randf() < 0.08 else rng.randf_range(0.92, 1.12))
				var waver := 2.0 if rng.randf() < 0.3 else 0.0
				custom.append(Color(tall, rng.randf(), rng.randf(), clampf((z + length * 0.5) / length, 0.0, 0.999) + waver))
			z += rng.randf_range(0.6, 0.8)
	# Shuffled, so the quality governor's share of the crowd thins every row evenly.
	for i in range(xfs.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		for arr: Array in [xfs, custom, colors]:
			var t: Variant = arr[i]
			arr[i] = arr[j]
			arr[j] = t
	return {"transforms": xfs, "custom": custom, "colors": colors}


func _build_crowd(stand: Node3D, rows: int, depth: float, rise: float, length: float) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.7, 1.0)
	quad.center_offset = Vector3(0, 0.5, 0)
	var data := crowd_data(look, KartLook.theme, rows, depth, rise, length)
	var xfs: Array = data.transforms
	var custom: Array = data.custom
	var colors: Array = data.colors
	var crowd := mm(quad, xfs, "Crowd", crowd_mat, custom, colors)
	_crowd = crowd.multimesh
	stand.add_child(crowd)


static func back_x(rows: int, depth: float) -> float:
	return 0.6 + rows * depth


## The start gate over the line: pillars, a beam with five lamps, chequered banners.
func _build_gate(parent: Node3D) -> void:
	var s := 1.0
	var hw := track.half_width(s)
	var yaw := track.yaw_at(s)
	var gate := Node3D.new()
	gate.name = "StartGate"
	gate.transform = Transform3D(Basis(Vector3.UP, yaw), track.position_at(s, 0.0))
	parent.add_child(gate)
	var span := hw + KartTrackModel.KERB_WIDTH + 1.4
	var height := 6.4
	var kit := MeshKit3D.new()
	kit.ao_y0 = 0.0
	kit.ao_y1 = 4.0
	kit.ao_min = 0.65
	var navy: Color = look.gate
	navy.a = 0.0
	var band: Color = look.gate_band
	band.a = 0.0
	var white := Color(0.96, 0.96, 0.97, 0.0)
	for side: float in [-1.0, 1.0]:
		kit.add(MeshKit3D.box(Vector3(1.0, height + 1.2, 1.0)), MeshKit3D.xf(Vector3(side * span, (height + 1.2) * 0.5, 0)), white)
		for k in 4:
			kit.add(MeshKit3D.box(Vector3(1.04, 0.4, 1.04)), MeshKit3D.xf(Vector3(side * span, 0.8 + k * 1.5, 0)), band)
		kit.add(MeshKit3D.box(Vector3(1.6, 3.0, 1.6)), MeshKit3D.xf(Vector3(side * span, -1.0, 0)), navy)
	kit.add(MeshKit3D.box(Vector3(span * 2.0 + 1.0, 1.5, 1.1)), MeshKit3D.xf(Vector3(0, height, 0)), navy)
	# Chequered fascia on both faces of the beam.
	var cells := 24
	for face: float in [-1.0, 1.0]:
		for i in cells:
			for j in 2:
				var x0 := -span - 0.5 + (span * 2.0 + 1.0) * i / cells
				var x1 := -span - 0.5 + (span * 2.0 + 1.0) * (i + 1) / cells
				var y0 := height + 0.75 - 0.4 * (j + 1)
				var y1 := y0 + 0.4
				var c := Color(0.05, 0.05, 0.06, 0.0) if (i + j) % 2 == 0 else Color(0.97, 0.97, 0.97, 0.0)
				var z := face * 0.56
				if face > 0.0:
					kit.quad(Vector3(x0, y0, z), Vector3(x0, y1, z), Vector3(x1, y1, z), Vector3(x1, y0, z), c)
				else:
					kit.quad(Vector3(x1, y0, z), Vector3(x1, y1, z), Vector3(x0, y1, z), Vector3(x0, y0, z), c)
	# Lamp housings on the grid side (+z: behind the line, where the karts wait).
	kit.add(MeshKit3D.box(Vector3(5.2, 1.0, 0.5)), MeshKit3D.xf(Vector3(0, height - 1.15, 0.5)), Color(0.08, 0.08, 0.1, 0.0))
	gate.add_child(MeshKit3D.mesh_node(kit.commit(), scenery_mat, "Gate"))
	var lamps := MeshKit3D.new()
	var halo_xfs := []
	for i in 5:
		var x := -2.0 + i * 1.0
		lamps.add(MeshKit3D.sphere(0.3, 10, 5), MeshKit3D.xf(Vector3(x, height - 1.15, 0.78)), Color(i / 5.0, 1.0, 0.0))
		halo_xfs.append(Transform3D(Basis().scaled(Vector3.ONE * 1.6), gate.transform * Vector3(x, height - 1.15, 0.95)))
	gate.add_child(MeshKit3D.mesh_node(lamps.commit(), lamps_mat, "Lamps"))
	# Fake glow: additive halos for the lit lamps (cheaper than Environment glow).
	_halos = MultiMeshInstance3D.new()
	_halos.name = "LampHalos"
	_halos.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mmesh := MultiMesh.new()
	mmesh.transform_format = MultiMesh.TRANSFORM_3D
	mmesh.use_colors = true
	mmesh.mesh = halo_quad()
	mmesh.instance_count = halo_xfs.size()
	for i in halo_xfs.size():
		mmesh.set_instance_transform(i, halo_xfs[i])
		mmesh.set_instance_color(i, Color(1, 0.3, 0.2, 0.9))
	_halos.multimesh = mmesh
	parent.add_child(_halos)
	# Chequered banners hanging from the beam on the road side.
	var banner := SurfaceTool.new()
	banner.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b: float in [-1.0, 1.0]:
		var x0 := b * (span - 2.6) - 1.0
		var top := height - 0.75
		var w := 2.0
		var h := 1.6
		var nx := 6
		var ny := 5
		for i in nx:
			for j in ny:
				var c := Color(0.05, 0.05, 0.06) if (i + j) % 2 == 0 else Color(0.97, 0.97, 0.97)
				var u0 := float(i) / nx
				var u1 := float(i + 1) / nx
				var v0 := float(j) / ny
				var v1 := float(j + 1) / ny
				for uv in [[u0, v0], [u1, v0], [u1, v1], [u0, v0], [u1, v1], [u0, v1]]:
					banner.set_color(c)
					banner.set_uv(Vector2(uv[0], uv[1]))
					banner.set_normal(Vector3.BACK)
					banner.add_vertex(Vector3(x0 + uv[0] * w, top - uv[1] * h, 0.62))
	gate.add_child(MeshKit3D.mesh_node(banner.commit(), banner_mat, "Banners"))


static var _halo_quad: QuadMesh


## A soft additive billboard (lamp halos; dressers use it for bulbs that should bloom).
static func halo_quad() -> QuadMesh:
	if _halo_quad == null:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		mat.billboard_keep_scale = true
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = MeshKit3D.soft_disc(64)
		mat.disable_fog = true
		_halo_quad = QuadMesh.new()
		_halo_quad.size = Vector2(1.0, 1.0)
		_halo_quad.material = mat
	return _halo_quad


## Flags on tall poles along both sides of the start straight (not in front of the stand).
func _build_flags(parent: Node3D) -> void:
	var poles := MeshKit3D.new()
	var flag_xfs := []
	var custom := []
	var n := 0
	var s := -70.0
	while s < 40.0:
		var ss := track.wrap(s)
		var hw := track.half_width(ss)
		for side: float in [-1.0, 1.0]:
			if side > 0.0 and s > -66.0 and s < 22.0:
				continue  # the grandstand is there
			var p := track.position_at(ss, side * (hw + track.verge + 1.2))
			poles.add(MeshKit3D.cylinder(0.06, 0.08, 9.0, 5), MeshKit3D.xf(p + Vector3.UP * 2.5), Color(0.92, 0.92, 0.94, 0.0))
			var yaw := track.yaw_at(ss) + PI * 0.5
			flag_xfs.append(Transform3D(Basis(Vector3.UP, yaw), p + Vector3.UP * 6.3))
			custom.append(FLAG_COLORS[n % FLAG_COLORS.size()])
			n += 1
		s += 7.0
	if _built.get_node_or_null("Scenery/Grandstand"):
		# Flags along the back of the stand's roof, in the theme's accents.
		var accents: Array = [look.gate_band, look.stand_roof, look.stand_b, Color(0.98, 0.98, 0.98)]
		var bx := back_x(STAND_ROWS, 0.95)
		var roof_top := 1.2 + STAND_ROWS * 0.6 + 2.75 + bx * 0.5 * tan(deg_to_rad(7.0))
		var k := 0
		var z := -STAND_LENGTH * 0.5 + 4.0
		while z < STAND_LENGTH * 0.5:
			var foot := stand_xf * Vector3(bx + 0.3, roof_top - 0.6, z)
			poles.add(MeshKit3D.cylinder(0.05, 0.07, 3.6, 5), MeshKit3D.xf(foot + Vector3.UP * 1.8), Color(0.92, 0.92, 0.94, 0.0))
			flag_xfs.append(Transform3D(Basis(Vector3.UP, track.yaw_at(track.wrap(-22.0)) + PI * 0.5).scaled(Vector3.ONE * 0.8), foot + Vector3.UP * 3.5))
			var c: Color = accents[k % accents.size()]
			custom.append(Color(c.r, c.g, c.b, 1.0))
			k += 1
			z += 10.5
	parent.add_child(MeshKit3D.mesh_node(poles.commit(), scenery_mat, "FlagPoles"))
	parent.add_child(mm(flag_cloth(), flag_xfs, "Flags", flag_mat, custom))


static var _cloth: ArrayMesh


## A flag's cloth, 1.7 × 1.05 m from the pole along +x; UV.x runs along it (the wave grows).
static func flag_cloth() -> ArrayMesh:
	if _cloth == null:
		var cloth := PlaneMesh.new()
		cloth.size = Vector2(1.7, 1.05)
		cloth.subdivide_width = 8
		cloth.orientation = PlaneMesh.FACE_Z
		cloth.center_offset = Vector3(0.85, -0.5, 0)
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var arr := cloth.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var uvs: PackedVector2Array = arr[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			st.set_color(Color.WHITE if uvs[i].y > 0.25 else Color(0.85, 0.85, 0.85))
			st.set_uv(Vector2(verts[i].x / 1.7, uvs[i].y))
			st.set_normal(Vector3.BACK)
			st.add_vertex(verts[i])
		_cloth = st.commit()
	return _cloth


## Soft cumulus cards far away, over the hills, in the theme's tint.
func _build_clouds(parent: Node3D) -> void:
	var count: int = look.get("clouds", 26)
	if count <= 0:
		return
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	mat.albedo_texture = _cloud_texture()
	mat.albedo_color = look.get("cloud", Color(1.0, 0.97, 0.93))
	mat.disable_fog = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 1.0)
	quad.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Fewer, bigger cumulus: each a main card with one or two smaller cards overlapping it, a
	# little higher and to the side, so they read as banks, not rows of sausages (one MultiMesh).
	var xfs := []
	count = maxi(3, roundi(count * 0.6))
	for i in count:
		var a := TAU * i / count + rng.randf_range(-0.15, 0.15)
		var r := rng.randf_range(600.0, 840.0)
		var sc := rng.randf_range(150.0, 280.0)
		var at := centre + Vector3(cos(a) * r, rng.randf_range(110.0, 240.0), sin(a) * r)
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		xfs.append(Transform3D(Basis().scaled(Vector3(sc, sc * 0.55, sc)), at))
		for j in 1 + int(rng.randf() < 0.5):
			var k := rng.randf_range(0.45, 0.7)
			var shift := tangent * sc * rng.randf_range(-0.7, 0.7) + Vector3.UP * sc * rng.randf_range(0.12, 0.25)
			xfs.append(Transform3D(Basis().scaled(Vector3(sc * k, sc * k * 0.55, sc * k)), at + shift - (at - centre).normalized() * 6.0))
	parent.add_child(MeshKit3D.multimesh_node(quad, xfs, "Clouds"))


static var _cloud_tex: ImageTexture


static func _cloud_texture() -> ImageTexture:
	if _cloud_tex == null:
		# A cumulus: puffs piled into a dome over a flat base. Each puff is lit on its top and
		# shaded below; the base is a flat, cooler band.
		var img := Image.create(128, 64, true, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var blobs := []
		for i in 8:
			var x := lerpf(18.0, 110.0, i / 7.0) + rng.randf_range(-4, 4)
			var dome := 1.0 - pow((x - 64.0) / 52.0, 2.0)
			var rad := lerpf(11.0, 21.0, dome) * rng.randf_range(0.85, 1.1)
			blobs.append([Vector2(x, 46.0 - dome * 16.0 - rad * 0.35), rad])
		for y in 64:
			for x in 128:
				var a := 0.0
				var lit := 0.0
				for b in blobs:
					var d: Vector2 = Vector2(x, y) - b[0]
					var k: float = clampf(1.25 - d.length() / b[1], 0.0, 1.0)
					if k > a:
						a = k
						lit = clampf(-d.y / b[1], -1.0, 1.0)
				a *= smoothstep(50.0, 46.0, float(y))
				var shade := 0.88 + 0.12 * lit
				shade = lerpf(shade, 0.74, smoothstep(38.0, 47.0, float(y)))
				img.set_pixel(x, y, Color(shade * 0.98, shade * 0.98, shade * 1.04, clampf(a * 1.6, 0.0, 1.0)))
		img.generate_mipmaps()
		_cloud_tex = ImageTexture.create_from_image(img)
	return _cloud_tex


## The crowd sprite, two 32x48 frames side by side: a fan in a T-shirt (R), the head (G) and the
## arms (B): raised in the left frame, out to the sides in the right (crowd.gdshader flips them).
static func _crowd_sprite() -> ImageTexture:
	var w := 32
	var h := 48
	var img := Image.create(w * 2, h, true, Image.FORMAT_RGBA8)
	for frame in 2:
		for y in h:
			for x in w:
				var p := Vector2(x + 0.5, y + 0.5)
				var head := p.distance_to(Vector2(16, 12)) < 7.0
				var body := Rect2(7, 19, 18, 29).has_point(p) and p.distance_to(Vector2(16, 26)) < 13.5
				var arms := false
				if frame == 0:
					arms = (absf(p.x - 5.0) < 2.2 or absf(p.x - 27.0) < 2.2) and p.y > 6.0 and p.y < 24.0
				else:
					# Out and a little down, hands at the frame's edges.
					var ax := absf(p.x - 16.0)
					arms = ax > 8.0 and ax < 15.0 and absf(p.y - (21.0 + (ax - 8.0) * 0.45)) < 2.3
				var c := Color(0, 0, 0, 0)
				if head:
					c = Color(0, 1, 0, 1)
				elif body:
					c = Color(1, 0, 0, 1)
				elif arms:
					c = Color(0, 0, 1, 1)
				img.set_pixel(frame * w + x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)
